import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    FlutterMethodChannel(
      name: "cohabit/files",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { [weak self] call, result in
      guard call.method == "saveDocument", let self = self,
        let args = call.arguments as? [String: Any],
        let fileName = args["fileName"] as? String,
        let bytes = args["bytes"] as? FlutterStandardTypedData
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.saveDocument(fileName: fileName, data: bytes.data, result: result)
    }

    super.awakeFromNib()
  }

  private func saveDocument(fileName: String, data: Data, result: @escaping FlutterResult) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = fileName
    panel.beginSheetModal(for: self) { response in
      guard response == .OK, let url = panel.url else {
        result(false)
        return
      }
      do {
        // Atomic: a failed write leaves any existing file untouched.
        try data.write(to: url, options: .atomic)
        guard try Data(contentsOf: url) == data else {
          result(FlutterError(code: "write_failed", message: "Saved file differs", details: nil))
          return
        }
        result(true)
      } catch {
        result(FlutterError(code: "write_failed", message: "Could not save the file", details: nil))
      }
    }
  }
}
