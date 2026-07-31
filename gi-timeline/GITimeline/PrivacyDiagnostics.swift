import Foundation

enum PrivacyDiagnostics {
  /// Final device builds call this after creating protected files. The preflight records its DEBUG log.
  static func assertCompleteProtection(at urls: [URL], requireExisting: Bool = true) {
    #if DEBUG
    // XCTest runs in an iOS simulator, whose filesystem does not report iPhone
    // data-protection classes. Keep the strict assertion active for real app runs;
    // the physical-device preflight remains the authority for this gate.
    if AppRuntime.isUnitTesting { return }
    for url in urls {
      let exists = FileManager.default.fileExists(atPath: url.path)
      if requireExisting { assert(exists, "Protected file is missing: \(url.lastPathComponent)") }
      guard exists else { continue }
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
      let protection = attributes?[.protectionKey] as? FileProtectionType
      assert(protection == .complete, "Expected complete file protection: \(url.lastPathComponent)")
      if protection == .complete { print("PRIVACY_PROTECTION_OK \(url.path) complete") }
    }
    #endif
  }
}
