import Foundation

enum AppFolders {
  static let privacyLine = "The app sends no journal data to its own server and provides no app-managed sync. iOS may include journal data in your device backup, depending on your settings."

  static func applicationSupport() throws -> URL {
    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("GITimeline", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try protect(base)
    return base
  }
  static func drafts() throws -> URL { try directory("Drafts", excludedFromBackup: false) }
  static func images() throws -> URL { try directory("Images", excludedFromBackup: false) }
  static func models() throws -> URL { try directory("Models", excludedFromBackup: true) }
  static func modelCache() throws -> URL {
    let url = try models().appendingPathComponent("Cache", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try protect(url)
    return url
  }
  static func storeURL() throws -> URL { try applicationSupport().appendingPathComponent("GITimeline.store") }
  static func storeFiles() throws -> [URL] {
    let store = try storeURL()
    return [store, URL(fileURLWithPath: store.path + "-wal"), URL(fileURLWithPath: store.path + "-shm")]
  }
  static func enforceStoreProtection(requireAllStoreFiles: Bool = false) {
    guard let urls = try? storeFiles() else { return }
    for url in urls where FileManager.default.fileExists(atPath: url.path) { try? protect(url) }
    PrivacyDiagnostics.assertCompleteProtection(at: urls, requireExisting: requireAllStoreFiles)
  }
  static func importFolder() throws -> URL {
    let url = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Import", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  private static func directory(_ name: String, excludedFromBackup: Bool) throws -> URL {
    let url = try applicationSupport().appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var values = URLResourceValues(); values.isExcludedFromBackup = excludedFromBackup
    var mutable = url; try mutable.setResourceValues(values)
    try protect(url)
    return url
  }
  private static func protect(_ url: URL) throws {
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
  }
}

enum GITimelineError: LocalizedError {
  case noImage, invalidImage, noteTooLong, modelHashMismatch, insufficientModelStorage, missingRepairContext, operationInProgress
  var errorDescription: String? {
    switch self {
    case .noImage: return "Select a photo before saving."
    case .invalidImage: return "The selected item could not be prepared as an image."
    case .noteTooLong: return "Notes are limited to 500 characters."
    case .modelHashMismatch: return "The model hash did not match. The Import copy was retained."
    case .insufficientModelStorage: return "At least twice the model size must be free before importing."
    case .missingRepairContext: return "The analysis repair context was no longer available."
    case .operationInProgress: return "Wait for the current local operation to finish."
    }
  }
}
