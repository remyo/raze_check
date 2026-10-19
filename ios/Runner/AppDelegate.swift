import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let storage = FlutterMethodChannel(
      name: "com.remyo.razecheck/private_storage",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    storage.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup", let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let support = try FileManager.default.url(
          for: .applicationSupportDirectory, in: .userDomainMask,
          appropriateFor: nil, create: true).appendingPathComponent("raze_check").standardizedFileURL
        var target = URL(fileURLWithPath: path).standardizedFileURL
        guard target == support else {
          result(FlutterError(code: "invalidPath", message: "Private storage path required", details: nil))
          return
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "storageFailure", message: "Could not exclude private storage", details: nil))
      }
    }
  }
}
