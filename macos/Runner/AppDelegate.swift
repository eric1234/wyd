import Cocoa
import Darwin
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
  private let clearDataFlag = "--clear-data"
  private let runningInstanceMessage = "wyd is currently running. Quit wyd before clearing data."
  private var instanceLockFileDescriptor: Int32 = -1
  private var singleInstanceChannel: FlutterMethodChannel?
  private var lifecycleChannel: FlutterMethodChannel?
  private var powerEventChannel: FlutterEventChannel?
  private var launchAtStartupChannels: [FlutterMethodChannel] = []
  private var pendingExistingInstanceActivation = false
  private var singleInstanceReady = false
  private var lifecycleReady = false
  private var terminationRequestInProgress = false
  private var terminationRequestDeliveredToDart = false
  private var terminationReplyApplication: NSApplication?
  private var terminationTimeout: DispatchWorkItem?
  private var powerEventSink: FlutterEventSink?
  private var powerObservers: [NSObjectProtocol] = []

  func configureFlutterChannels(for controller: FlutterViewController) {
    let binaryMessenger = controller.engine.binaryMessenger
    configureSingleInstanceChannel(binaryMessenger: binaryMessenger)
    configureLifecycleChannel(binaryMessenger: binaryMessenger)
    configurePowerEventChannel(binaryMessenger: binaryMessenger)
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

    terminationRequestInProgress = true
    terminationRequestDeliveredToDart = false
    terminationReplyApplication = sender
    scheduleTerminationTimeout()
    deliverTerminationRequestIfReady()
    return .terminateLater
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return false
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    powerEventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    powerEventSink = nil
    return nil
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

  private func configureLifecycleChannel(binaryMessenger: FlutterBinaryMessenger) {
    guard lifecycleChannel == nil else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "dev.wyd.tracker/lifecycle",
      binaryMessenger: binaryMessenger
    )
    lifecycleChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "lifecycleReady" else {
        result(FlutterMethodNotImplemented)
        return
      }

      result(nil)
      self?.lifecycleReady = true
      DispatchQueue.main.async { [weak self] in
        self?.deliverTerminationRequestIfReady()
      }
    }
  }

  private func configurePowerEventChannel(binaryMessenger: FlutterBinaryMessenger) {
    guard powerEventChannel == nil else {
      return
    }

    let channel = FlutterEventChannel(
      name: "dev.wyd.tracker/power_events",
      binaryMessenger: binaryMessenger
    )
    channel.setStreamHandler(self)
    powerEventChannel = channel

    let workspaceCenter = NSWorkspace.shared.notificationCenter
    powerObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.sendPowerEvent("sleep")
      }
    )
    powerObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.sessionDidResignActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.sendPowerEvent("lock")
      }
    )
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

  private func sendPowerEvent(_ event: String) {
    powerEventSink?(event)
  }

  private func scheduleTerminationTimeout() {
    terminationTimeout?.cancel()
    let timeout = DispatchWorkItem { [weak self] in
      self?.finishNativeTermination()
    }
    terminationTimeout = timeout
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .seconds(5),
      execute: timeout
    )
  }

  private func deliverTerminationRequestIfReady() {
    guard terminationRequestInProgress,
          lifecycleReady,
          !terminationRequestDeliveredToDart,
          let lifecycleChannel else {
      return
    }

    terminationRequestDeliveredToDart = true
    lifecycleChannel.invokeMethod("terminationRequested", arguments: nil) { [weak self] _ in
      self?.finishNativeTermination()
    }
  }

  private func finishNativeTermination() {
    guard terminationRequestInProgress else {
      return
    }

    terminationTimeout?.cancel()
    terminationTimeout = nil
    terminationRequestInProgress = false
    terminationRequestDeliveredToDart = false
    terminationReplyApplication?.reply(toApplicationShouldTerminate: true)
    terminationReplyApplication = nil
  }

  private func hideMainFlutterWindow() {
    for window in NSApplication.shared.windows where window is MainFlutterWindow {
      window.orderOut(nil)
    }
  }

  deinit {
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    for observer in powerObservers {
      workspaceCenter.removeObserver(observer)
    }
  }
}
