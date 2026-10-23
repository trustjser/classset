import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.appearance = NSAppearance(named: .aqua)
    let defaultSize = NSSize(width: 1440, height: 900)
    let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
    let windowFrame: NSRect
    if let screenFrame {
      let size = NSSize(
        width: min(defaultSize.width, screenFrame.width),
        height: min(defaultSize.height, screenFrame.height)
      )
      windowFrame = NSRect(
        x: screenFrame.midX - size.width / 2,
        y: screenFrame.midY - size.height / 2,
        width: size.width,
        height: size.height
      )
    } else {
      windowFrame = NSRect(origin: self.frame.origin, size: defaultSize)
    }
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let appearanceChannel = FlutterMethodChannel(
      name: "class_set/window_appearance",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    appearanceChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setAppearance", let mode = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch mode {
      case "system":
        self?.appearance = nil
      case "light":
        self?.appearance = NSAppearance(named: .aqua)
      case "dark":
        self?.appearance = NSAppearance(named: .darkAqua)
      default:
        result(FlutterError(code: "INVALID_APPEARANCE", message: "Unknown appearance mode", details: nil))
        return
      }
      result(nil)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
