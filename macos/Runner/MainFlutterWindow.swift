import Cocoa
import desktop_multi_window
import FlutterMacOS
import screen_retriever_macos
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    isRestorable = false
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    (NSApplication.shared.delegate as? AppDelegate)?.configureFlutterChannels(for: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      // Child windows must not register tray_manager. The tray belongs to the
      // primary process window; registering it in child engines can steal tray
      // menu events from the controller that handles Report/Settings/Exit.
      FlutterMultiWindowPlugin.register(with: controller.registrar(forPlugin: "FlutterMultiWindowPlugin"))
      ScreenRetrieverMacosPlugin.register(with: controller.registrar(forPlugin: "ScreenRetrieverMacosPlugin"))
      WindowManagerPlugin.register(with: controller.registrar(forPlugin: "WindowManagerPlugin"))
    }
    super.awakeFromNib()
    orderOut(nil)
  }
}
