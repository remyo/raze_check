import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var documents: BoundedDocumentPicker?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    documents = BoundedDocumentPicker()
    let documentChannel = FlutterMethodChannel(name: "com.remyo.razecheck/documents", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    documentChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pick", let args = call.arguments as? [String: Any], let purpose = args["purpose"] as? String else { result(FlutterMethodNotImplemented); return }
      self?.documents?.pick(purpose: purpose, result: result)
    }
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


// Open-in-place avoids requesting UIDocumentPicker's imported full copy.
// External providers/OS may still materialize content outside app control.
final class BoundedDocumentPicker: NSObject, UIDocumentPickerDelegate {
  private var pending: FlutterResult?
  private var limit = 65536
  func pick(purpose: String, result: @escaping FlutterResult) {
    guard pending == nil else { result(FlutterError(code: "busy", message: "Document already open", details: nil)); return }
    switch purpose {
    case "message": limit = 65536
    case "image": limit = 20*1024*1024
    case "archive": limit = 64*1024*1024
    default: result(FlutterError(code: "invalidPurpose", message: "Invalid purpose", details: nil)); return
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: purpose == "image" ? [.png, .jpeg] : [.data], asCopy: false)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "unavailable", message: "Files unavailable", details: nil)); return
    }
    var presenter = root
    while let next = presenter.presentedViewController { presenter = next }
    pending = result
    presenter.present(picker, animated: true)
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
  private func finish(_ value: Any?) { let result = pending; pending = nil; result?(value) }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { finish(FlutterError(code: "unavailable", message: "No readable file", details: nil)); return }
    let max = limit
    DispatchQueue.global(qos: .userInitiated).async {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let fm = FileManager.default
      let dir = fm.temporaryDirectory.appendingPathComponent("raze-document-staging", isDirectory: true)
      let target = dir.appendingPathComponent(UUID().uuidString)
      var failure: Error?
      var coordinatedError: NSError?
      do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for old in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
          if let date = try? old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date.timeIntervalSinceNow < -86400 { try? fm.removeItem(at: old) }
        }
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatedError) { readable in
          do {
            let size = try? readable.resourceValues(forKeys: [.fileSizeKey]).fileSize
            try boundedDocumentCopy(readable, target, max, size)
          } catch { failure = error }
        }
        if let error = coordinatedError { throw error }
        if let error = failure { throw error }
        guard fm.fileExists(atPath: target.path) else { throw CocoaError(.fileReadUnknown) }
        DispatchQueue.main.async { self.finish(target.path) }
      } catch {
        try? fm.removeItem(at: target)
        let code = error is DocumentLimitError ? "limitExceeded" : "unavailable"
        DispatchQueue.main.async { self.finish(FlutterError(code: code, message: "Save locally and retry", details: nil)) }
      }
    }
  }
}
struct DocumentLimitError: Error {}
func boundedDocumentCopy(_ source: URL, _ target: URL, _ limit: Int, _ size: Int?) throws {
  do {
    if let size = size, size > limit { throw DocumentLimitError() }
    guard let input = InputStream(url: source), let output = OutputStream(url: target, append: false) else { throw CocoaError(.fileReadUnknown) }
    input.open(); output.open()
    defer { input.close(); output.close() }
    var buffer = [UInt8](repeating: 0, count: 32768)
    var total = 0
    while true {
      let count = input.read(&buffer, maxLength: buffer.count)
      if count < 0 { throw input.streamError ?? CocoaError(.fileReadUnknown) }
      if count == 0 { break }
      if count > limit - total { throw DocumentLimitError() }
      total += count
      try buffer.withUnsafeBufferPointer { ptr in
        var offset = 0
        while offset < count {
          let n = output.write(ptr.baseAddress!.advanced(by: offset), maxLength: count-offset)
          if n <= 0 { throw output.streamError ?? CocoaError(.fileWriteUnknown) }
          offset += n
        }
      }
    }
  } catch { try? FileManager.default.removeItem(at: target); throw error }
}
