import Cocoa
import Darwin
import FlutterMacOS
import IOKit.pwr_mgt
import ServiceManagement

private let macOSPowerEventAcknowledgementTimeoutMilliseconds = 1800

// Swift does not import the iokit_common_msg(...) C macros from IOMessage.h.
private let macOSIOMessageCanSystemSleep: UInt32 = 0xe0000270
private let macOSIOMessageSystemWillSleep: UInt32 = 0xe0000280
private let macOSScreenIsLockedNotification = Notification.Name("com.apple.screenIsLocked")
private let macOSScreenIsUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

private struct PendingLifecycleEvent {
  let kind: String
  let occurredAtUtc: String
  let completion: (() -> Void)?
}

@main
class AppDelegate: FlutterAppDelegate {
  private let clearDataFlag = "--clear-data"
  private let runningInstanceMessage = "wyd is currently running. Quit wyd before clearing data."
  private var instanceLockFileDescriptor: Int32 = -1
  private var singleInstanceChannel: FlutterMethodChannel?
  private var lifecycleEventsChannel: FlutterMethodChannel?
  private var launchAtStartupChannels: [FlutterMethodChannel] = []
  private var pendingExistingInstanceActivation = false
  private var singleInstanceReady = false
  private var lifecycleEventsReady = false
  private var pendingLifecycleEvents: [PendingLifecycleEvent] = []
  private var lifecycleEventDeliveryInProgress = false
  private var terminationRequestGeneration = 0
  private var terminationRequestInProgress = false
  private var terminationRequestDeliveredToDart = false
  private var terminationRequestOccurredAtUtc: String?
  private var terminationReplyApplication: NSApplication?
  private var terminationTimeout: DispatchWorkItem?
  private var sleepPowerChangeInProgress = false
  private var sleepPowerChangeNotificationID: intptr_t?
  private var sleepPowerChangeTimeout: DispatchWorkItem?
  private var powerObservers: [NSObjectProtocol] = []
  private var distributedPowerObservers: [NSObjectProtocol] = []
  private var powerEventSourcesConfigured = false
  private var screenLockEventReported = false
  private var systemPowerConnection: io_connect_t = IO_OBJECT_NULL
  private var systemPowerNotificationPort: IONotificationPortRef?
  private var systemPowerNotifier: io_object_t = IO_OBJECT_NULL
  private let powerEventTimestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }()

  func configureFlutterChannels(for controller: FlutterViewController) {
    let binaryMessenger = controller.engine.binaryMessenger
    configureSingleInstanceChannel(binaryMessenger: binaryMessenger)
    configureLifecycleEventsChannel(binaryMessenger: binaryMessenger)
    configureLifecycleEventSources()
    configureLaunchAtStartupChannel(for: controller)
  }

  func configureLaunchAtStartupChannel(for controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "launch_at_startup",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(self?.isLaunchAtStartupEnabled() ?? false)
      case "launchAtStartupSetEnabled":
        guard let arguments = call.arguments as? [String: Any],
              let enabled = arguments["setEnabledValue"] as? Bool else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "launchAtStartupSetEnabled requires setEnabledValue.",
              details: nil
            )
          )
          return
        }
        guard let self else {
          result(
            FlutterError(
              code: "app_delegate_unavailable",
              message: "App delegate is unavailable.",
              details: nil
            )
          )
          return
        }
        self.setLaunchAtStartupEnabled(enabled, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    launchAtStartupChannels.append(channel)
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    acquireInstanceLockOrExit()
    super.applicationWillFinishLaunching(notification)
  }

  private func isLaunchAtStartupEnabled() -> Bool {
    guard #available(macOS 13.0, *) else {
      return false
    }

    return SMAppService.mainApp.status == .enabled
  }

  private func setLaunchAtStartupEnabled(_ enabled: Bool, result: FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result(
        FlutterError(
          code: "unsupported_macos_version",
          message: "Launch at login requires macOS 13 or later.",
          details: nil
        )
      )
      return
    }

    let service = SMAppService.mainApp
    do {
      if enabled {
        if service.status != .enabled {
          try service.register()
        }
      } else if service.status == .enabled || service.status == .requiresApproval {
        try service.unregister()
      }
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "launch_at_login_update_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    releaseInstanceLock()
    super.applicationWillTerminate(notification)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    hideMainFlutterWindow()
    DispatchQueue.main.async { [weak self] in
      self?.hideMainFlutterWindow()
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if flag {
      return true
    }

    notifyExistingInstanceActivated()
    return false
  }

  private func acquireInstanceLockOrExit() {
    let lockURL = instanceLockURL()
    do {
      try FileManager.default.createDirectory(
        at: lockURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
    } catch {
      exitWithError("Failed to create wyd lock directory: \(error.localizedDescription)")
    }

    let fileDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fileDescriptor >= 0 else {
      exitWithError("Failed to open wyd lock file: \(currentErrnoMessage())")
    }

    if flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
      close(fileDescriptor)
      if CommandLine.arguments.contains(clearDataFlag) {
        exitWithError(runningInstanceMessage)
      }
      exit(EXIT_FAILURE)
    }

    instanceLockFileDescriptor = fileDescriptor
  }

  private func releaseInstanceLock() {
    guard instanceLockFileDescriptor >= 0 else {
      return
    }

    flock(instanceLockFileDescriptor, LOCK_UN)
    close(instanceLockFileDescriptor)
    instanceLockFileDescriptor = -1
  }

  private func instanceLockURL() -> URL {
    let applicationSupportURL = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? FileManager.default.homeDirectoryForCurrentUser

    return applicationSupportURL
      .appendingPathComponent("wyd", isDirectory: true)
      .appendingPathComponent("wyd.lock", isDirectory: false)
  }

  private func currentErrnoMessage() -> String {
    return String(cString: strerror(errno))
  }

  private func exitWithError(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(EXIT_FAILURE)
  }

  override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    if terminationRequestInProgress {
      return .terminateLater
    }

    let occurredAtUtc = powerEventTimestampFormatter.string(from: Date())
    terminationRequestGeneration += 1
    let requestGeneration = terminationRequestGeneration
    terminationRequestInProgress = true
    terminationRequestDeliveredToDart = false
    terminationRequestOccurredAtUtc = occurredAtUtc
    terminationReplyApplication = sender
    scheduleTerminationTimeout(requestGeneration: requestGeneration)
    enqueueTerminationRequestIfReady()
    return .terminateLater
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return false
  }

  private func configureSingleInstanceChannel(binaryMessenger: FlutterBinaryMessenger) {
    guard singleInstanceChannel == nil else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "dev.wyd.tracker/single_instance",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "consumePendingActivation" else {
        result(FlutterMethodNotImplemented)
        return
      }

      self?.singleInstanceReady = true
      let pending = self?.pendingExistingInstanceActivation ?? false
      self?.pendingExistingInstanceActivation = false
      result(pending)
    }
    singleInstanceChannel = channel
  }

  private func configureLifecycleEventsChannel(binaryMessenger: FlutterBinaryMessenger) {
    guard lifecycleEventsChannel == nil else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "dev.wyd.tracker/lifecycle_events",
      binaryMessenger: binaryMessenger
    )
    lifecycleEventsChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "lifecycleEventsReady" else {
        result(FlutterMethodNotImplemented)
        return
      }

      self?.lifecycleEventsReady = true
      result(nil)
      DispatchQueue.main.async { [weak self] in
        self?.enqueueTerminationRequestIfReady()
        self?.drainPendingLifecycleEvents()
      }
    }
  }

  private func configureLifecycleEventSources() {
    guard !powerEventSourcesConfigured else {
      return
    }
    powerEventSourcesConfigured = true

    let systemPowerRegistered = registerSystemPowerNotifications()
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    if !systemPowerRegistered {
      powerObservers.append(
        workspaceCenter.addObserver(
          forName: NSWorkspace.willSleepNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          self?.enqueueLifecycleEvent(kind: "sleep")
        }
      )
    }
    powerObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.sessionDidResignActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.reportScreenLockIfNeeded()
      }
    )
    powerObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.sessionDidBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.screenLockEventReported = false
      }
    )
    distributedPowerObservers.append(
      DistributedNotificationCenter.default().addObserver(
        forName: macOSScreenIsLockedNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.reportScreenLockIfNeeded()
      }
    )
    distributedPowerObservers.append(
      DistributedNotificationCenter.default().addObserver(
        forName: macOSScreenIsUnlockedNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.screenLockEventReported = false
      }
    )
  }

  private func registerSystemPowerNotifications() -> Bool {
    guard systemPowerConnection == IO_OBJECT_NULL else {
      return true
    }

    var notificationPort: IONotificationPortRef?
    var notifier = io_object_t()
    let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    let connection = IORegisterForSystemPower(
      refcon,
      &notificationPort,
      { refcon, _, messageType, messageArgument in
        guard let refcon else {
          return
        }
        let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
        delegate.handleSystemPowerMessage(messageType, argument: messageArgument)
      },
      &notifier
    )

    guard connection != IO_OBJECT_NULL, let notificationPort else {
      if connection != IO_OBJECT_NULL {
        IOServiceClose(connection)
      }
      return false
    }

    IONotificationPortSetDispatchQueue(notificationPort, DispatchQueue.main)
    systemPowerConnection = connection
    systemPowerNotificationPort = notificationPort
    systemPowerNotifier = notifier
    return true
  }

  private func handleSystemPowerMessage(
    _ messageType: UInt32,
    argument: UnsafeMutableRawPointer?
  ) {
    switch messageType {
    case macOSIOMessageCanSystemSleep:
      allowPowerChange(argument: argument)
    case macOSIOMessageSystemWillSleep:
      acknowledgeSleepBeforePowerChange(argument: argument)
    default:
      break
    }
  }

  private func notifyExistingInstanceActivated() {
    pendingExistingInstanceActivation = true
    guard singleInstanceReady else {
      return
    }

    singleInstanceChannel?.invokeMethod(
      "secondInstanceActivated",
      arguments: nil
    ) { [weak self] _ in
      self?.pendingExistingInstanceActivation = false
    }
  }

  private func reportScreenLockIfNeeded() {
    guard !screenLockEventReported else {
      return
    }
    screenLockEventReported = true
    enqueueLifecycleEvent(kind: "lock")
  }

  private func acknowledgeSleepBeforePowerChange(argument: UnsafeMutableRawPointer?) {
    let occurrence = makeLifecycleEvent(kind: "sleep")
    guard lifecycleEventsReady else {
      enqueueLifecycleEvent(occurrence)
      allowPowerChange(argument: argument)
      return
    }
    guard !sleepPowerChangeInProgress else {
      enqueueLifecycleEvent(occurrence)
      allowPowerChange(argument: argument)
      return
    }

    let notificationID = intptr_t(bitPattern: argument)
    sleepPowerChangeInProgress = true
    sleepPowerChangeNotificationID = notificationID
    let timeout = DispatchWorkItem { [weak self] in
      self?.finishSleepPowerChange(notificationID: notificationID)
    }
    sleepPowerChangeTimeout = timeout
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .milliseconds(macOSPowerEventAcknowledgementTimeoutMilliseconds),
      execute: timeout
    )
    enqueueLifecycleEvent(
      PendingLifecycleEvent(
        kind: occurrence.kind,
        occurredAtUtc: occurrence.occurredAtUtc,
        completion: { [weak self] in
          self?.finishSleepPowerChange(notificationID: notificationID)
        }
      )
    )
  }

  private func enqueueLifecycleEvent(kind: String) {
    enqueueLifecycleEvent(makeLifecycleEvent(kind: kind))
  }

  private func enqueueLifecycleEvent(_ occurrence: PendingLifecycleEvent) {
    pendingLifecycleEvents.append(occurrence)
    drainPendingLifecycleEvents()
  }

  private func drainPendingLifecycleEvents() {
    guard lifecycleEventsReady,
          !lifecycleEventDeliveryInProgress,
          let lifecycleEventsChannel,
          let occurrence = pendingLifecycleEvents.first else {
      return
    }

    lifecycleEventDeliveryInProgress = true
    lifecycleEventsChannel.invokeMethod(
      "lifecycleEvent",
      arguments: lifecycleEventArguments(occurrence)
    ) { [weak self] _ in
      guard let self else {
        return
      }
      if !self.pendingLifecycleEvents.isEmpty {
        self.pendingLifecycleEvents.removeFirst()
      }
      self.lifecycleEventDeliveryInProgress = false
      occurrence.completion?()
      self.drainPendingLifecycleEvents()
    }
  }

  private func finishSleepPowerChange(notificationID: intptr_t) {
    guard sleepPowerChangeInProgress,
          sleepPowerChangeNotificationID == notificationID else {
      return
    }

    sleepPowerChangeTimeout?.cancel()
    sleepPowerChangeTimeout = nil
    sleepPowerChangeInProgress = false
    sleepPowerChangeNotificationID = nil
    allowPowerChange(notificationID: notificationID)
  }

  private func allowPowerChange(argument: UnsafeMutableRawPointer?) {
    allowPowerChange(notificationID: intptr_t(bitPattern: argument))
  }

  private func allowPowerChange(notificationID: intptr_t) {
    guard systemPowerConnection != IO_OBJECT_NULL else {
      return
    }
    IOAllowPowerChange(systemPowerConnection, notificationID)
  }

  private func makeLifecycleEvent(
    kind: String,
    occurredAtUtc: String? = nil,
    completion: (() -> Void)? = nil
  ) -> PendingLifecycleEvent {
    return PendingLifecycleEvent(
      kind: kind,
      occurredAtUtc: occurredAtUtc ?? powerEventTimestampFormatter.string(from: Date()),
      completion: completion
    )
  }

  private func lifecycleEventArguments(_ occurrence: PendingLifecycleEvent) -> [String: String] {
    return [
      "kind": occurrence.kind,
      "occurredAtUtc": occurrence.occurredAtUtc,
    ]
  }

  private func scheduleTerminationTimeout(requestGeneration: Int) {
    terminationTimeout?.cancel()
    let timeout = DispatchWorkItem { [weak self] in
      self?.finishNativeTermination(requestGeneration: requestGeneration)
    }
    terminationTimeout = timeout
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .seconds(5),
      execute: timeout
    )
  }

  private func enqueueTerminationRequestIfReady() {
    guard terminationRequestInProgress,
          lifecycleEventsReady,
          !terminationRequestDeliveredToDart,
          let occurredAtUtc = terminationRequestOccurredAtUtc else {
      return
    }

    let requestGeneration = terminationRequestGeneration
    terminationRequestDeliveredToDart = true
    let termination = makeLifecycleEvent(
      kind: "termination",
      occurredAtUtc: occurredAtUtc,
      completion: { [weak self] in
        self?.finishNativeTermination(requestGeneration: requestGeneration)
      }
    )
    if lifecycleEventDeliveryInProgress, let current = pendingLifecycleEvents.first {
      pendingLifecycleEvents = [current, termination]
    } else {
      pendingLifecycleEvents = [termination]
    }
    drainPendingLifecycleEvents()
  }

  private func finishNativeTermination(requestGeneration: Int) {
    guard terminationRequestInProgress,
          terminationRequestGeneration == requestGeneration else {
      return
    }

    terminationTimeout?.cancel()
    terminationTimeout = nil
    terminationRequestInProgress = false
    terminationRequestDeliveredToDart = false
    terminationRequestOccurredAtUtc = nil
    terminationReplyApplication?.reply(toApplicationShouldTerminate: true)
    terminationReplyApplication = nil
  }

  private func hideMainFlutterWindow() {
    for window in NSApplication.shared.windows where window is MainFlutterWindow {
      window.orderOut(nil)
    }
  }

  private func unregisterSystemPowerNotifications() {
    if sleepPowerChangeInProgress, let notificationID = sleepPowerChangeNotificationID {
      allowPowerChange(notificationID: notificationID)
    }
    sleepPowerChangeTimeout?.cancel()
    sleepPowerChangeTimeout = nil
    sleepPowerChangeInProgress = false
    sleepPowerChangeNotificationID = nil

    if systemPowerNotifier != IO_OBJECT_NULL {
      IODeregisterForSystemPower(&systemPowerNotifier)
      systemPowerNotifier = IO_OBJECT_NULL
    }
    if let notificationPort = systemPowerNotificationPort {
      IONotificationPortSetDispatchQueue(notificationPort, nil)
      IONotificationPortDestroy(notificationPort)
      systemPowerNotificationPort = nil
    }
    if systemPowerConnection != IO_OBJECT_NULL {
      IOServiceClose(systemPowerConnection)
      systemPowerConnection = IO_OBJECT_NULL
    }
  }

  deinit {
    terminationTimeout?.cancel()
    unregisterSystemPowerNotifications()
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    for observer in powerObservers {
      workspaceCenter.removeObserver(observer)
    }
    let distributedCenter = DistributedNotificationCenter.default()
    for observer in distributedPowerObservers {
      distributedCenter.removeObserver(observer)
    }
  }
}
