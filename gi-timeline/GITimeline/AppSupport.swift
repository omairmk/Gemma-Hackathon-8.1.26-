import Foundation

enum DemoDataPolicy {
  static let notePrefix = "Synthetic Gemma demo"
  static func isSyntheticDemo(_ entry: EntryRecord) -> Bool {
    entry.demoKind != nil
  }
  static func isSyntheticDemoNote(_ note: String?) -> Bool {
    note?.hasPrefix(notePrefix) == true
  }
  static func presentedNote(for entry: EntryRecord) -> String? {
    guard let demoKind = entry.demoKind else { return entry.note }
    return "Bundled synthetic \(demoKind) demo image"
  }
}

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
  static func modelDirectory(for descriptor: ModelDescriptor) throws -> URL {
    let url = try models().appendingPathComponent(descriptor.cacheNamespace, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try protect(url)
    return url
  }
  static func modelURL(for descriptor: ModelDescriptor) throws -> URL {
    try modelDirectory(for: descriptor).appendingPathComponent(descriptor.artifactFilename)
  }
  static func modelCache(for descriptor: ModelDescriptor) throws -> URL {
    let url = try modelDirectory(for: descriptor).appendingPathComponent("Cache", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try protect(url)
    return url
  }
  static func receiptURL(for descriptor: ModelDescriptor) throws -> URL {
    let directory = try models().appendingPathComponent("Receipts", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try protect(directory)
    return directory.appendingPathComponent("\(descriptor.id).json")
  }
  #if DEBUG
  static func inferenceEvidence() throws -> URL {
    let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent(".devdata_inference", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try protect(directory)
    return directory
  }
  #endif
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
  static func protect(_ url: URL) throws {
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
  }
}

enum GITimelineError: LocalizedError {
  case noImage, invalidImage, noteTooLong, modelHashMismatch, modelSizeMismatch, insufficientModelStorage, missingRepairContext, operationInProgress, missingModelDescriptor, invalidModelDescriptor, invalidModelReceipt, modelNotVerified, engineInitializationInProgress, invalidDominantColorProbe, syntheticFixtureIntegrity, evidenceAlreadyExists
  var errorDescription: String? {
    switch self {
    case .noImage: return "Select a photo before saving."
    case .invalidImage: return "The selected item could not be prepared as an image."
    case .noteTooLong: return "Notes are limited to 500 characters."
    case .modelHashMismatch: return "The model hash did not match. The Import copy was retained."
    case .modelSizeMismatch: return "The model size did not match its immutable descriptor. The Import copy was retained."
    case .insufficientModelStorage: return "At least twice the model size must be free before importing."
    case .missingRepairContext: return "The analysis repair context was no longer available."
    case .operationInProgress: return "Wait for the current local operation to finish."
    case .missingModelDescriptor: return "No physically accepted model is selected for this build."
    case .invalidModelDescriptor: return "The model descriptor contains an invalid identity or unsafe path component."
    case .invalidModelReceipt: return "The on-disk model verification receipt is missing or does not match this candidate."
    case .modelNotVerified: return "Verify the exact model file before initializing the engine."
    case .engineInitializationInProgress: return "The local engine is already initializing."
    case .invalidDominantColorProbe: return "The dominant-color response was not exactly BROWN, GREEN, or OTHER."
    case .syntheticFixtureIntegrity: return "The bundled synthetic fixture did not match its project-recorded hash."
    case .evidenceAlreadyExists: return "Evidence for this run already exists and was not overwritten."
    }
  }
}
