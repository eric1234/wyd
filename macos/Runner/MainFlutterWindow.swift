import Cocoa
import desktop_multi_window
import FlutterMacOS
import package_info_plus
import screen_retriever_macos
import system_idle_macos
import url_launcher_macos
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    isRestorable = false
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let appDelegate = NSApplication.shared.delegate as? AppDelegate
    appDelegate?.configureFlutterChannels(for: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      // Child windows must not register tray_manager. The tray belongs to the
      // primary process window; registering it in child engines can steal tray
      // menu events from the controller that handles Report/Settings/Exit.
      FlutterMultiWindowPlugin.register(with: controller.registrar(forPlugin: "FlutterMultiWindowPlugin"))
      FPPPackageInfoPlusPlugin.register(with: controller.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
      ScreenRetrieverMacosPlugin.register(with: controller.registrar(forPlugin: "ScreenRetrieverMacosPlugin"))
      SystemIdlePlugin.register(with: controller.registrar(forPlugin: "SystemIdlePlugin"))
      UrlLauncherPlugin.register(with: controller.registrar(forPlugin: "UrlLauncherPlugin"))
      WindowManagerPlugin.register(with: controller.registrar(forPlugin: "WindowManagerPlugin"))
      appDelegate?.configureLaunchAtStartupChannel(for: controller)
    }
    super.awakeFromNib()
    orderOut(nil)
  }
}
