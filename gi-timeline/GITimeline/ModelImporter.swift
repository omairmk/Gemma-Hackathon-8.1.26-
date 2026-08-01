import CryptoKit
import Foundation

struct ModelImporter: Sendable {
  private let customImportDirectory: URL?
  private let customModelsDirectory: URL?
  private let customEmbeddedModelsDirectory: URL?
  private let appBuildIdentity: ModelAppBuildIdentity

  init(
    importDirectory: URL? = nil,
    modelsDirectory: URL? = nil,
    embeddedModelsDirectory: URL? = nil,
    appBuildIdentity: ModelAppBuildIdentity = .current
  ) {
    customImportDirectory = importDirectory
    customModelsDirectory = modelsDirectory
    customEmbeddedModelsDirectory = embeddedModelsDirectory
    self.appBuildIdentity = appBuildIdentity
  }

  func importModel(_ descriptor: ModelDescriptor) throws -> ModelImportResult {
    let source = try importDirectory().appendingPathComponent(descriptor.artifactFilename)
    let destination = try modelURL(for: descriptor)
    let temporary = destination.deletingLastPathComponent().appendingPathComponent("model.tmp")
    let manager = FileManager.default
    let sourceSize = try fileSize(source)
    guard sourceSize == descriptor.expectedBytes else { throw GITimelineError.modelSizeMismatch }

    let remaining = try destination.deletingLastPathComponent()
      .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage ?? 0
    guard remaining >= sourceSize * 2 else { throw GITimelineError.insufficientModelStorage }

    let sourceHash = try sha256(of: source)
    guard sourceHash.caseInsensitiveCompare(descriptor.expectedSHA256) == .orderedSame else {
      throw GITimelineError.modelHashMismatch
    }

    try? manager.removeItem(at: temporary)
    try manager.copyItem(at: source, to: temporary)
    do {
      let copiedSize = try fileSize(temporary)
      guard copiedSize == descriptor.expectedBytes else { throw GITimelineError.modelSizeMismatch }
      let copiedHash = try sha256(of: temporary)
      guard copiedHash.caseInsensitiveCompare(descriptor.expectedSHA256) == .orderedSame else {
        throw GITimelineError.modelHashMismatch
      }
      try AppFolders.protect(temporary)
      if manager.fileExists(atPath: destination.path) {
        _ = try manager.replaceItemAt(destination, withItemAt: temporary)
      } else {
        try manager.moveItem(at: temporary, to: destination)
      }
      try AppFolders.protect(destination)
    } catch {
      try? manager.removeItem(at: temporary)
      throw error
    }

    let receipt = ModelVerificationReceipt(
      descriptorID: descriptor.id,
      modelID: descriptor.modelID,
      sourceRevision: descriptor.sourceRevision,
      artifactFilename: descriptor.artifactFilename,
      importedBytes: descriptor.expectedBytes,
      importedSHA256: descriptor.expectedSHA256.lowercased(),
      verifiedAt: Date(),
      locationKind: .applicationSupport
    )
    try writeReceipt(receipt, for: descriptor)

    // Retain the Finder-staged source through successful engine initialization.
    // Import approval is intentionally not deletion approval.
    return ModelImportResult(
      sourceURL: source,
      verifiedModel: try VerifiedModel(validating: descriptor, modelURL: destination, receipt: receipt)
    )
  }

  /// Fast launch-time receipt check. This validates identity, path, and size but
  /// deliberately does not rehash several gigabytes on every view appearance.
  func receipt(for descriptor: ModelDescriptor) throws -> ModelVerificationReceipt? {
    let url = try receiptURL(for: descriptor, locationKind: .applicationSupport)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let receipt = try decoder.decode(ModelVerificationReceipt.self, from: Data(contentsOf: url))
    guard receipt.matches(descriptor),
      receipt.locationKind == nil || receipt.locationKind == .applicationSupport
    else { throw GITimelineError.invalidModelReceipt }
    let installed = try modelURL(for: descriptor)
    guard FileManager.default.fileExists(atPath: installed.path), try fileSize(installed) == descriptor.expectedBytes else {
      throw GITimelineError.invalidModelReceipt
    }
    return receipt
  }

  func verifiedModel(for descriptor: ModelDescriptor) throws -> VerifiedModel? {
    guard let receipt = try receipt(for: descriptor) else { return nil }
    return try VerifiedModel(validating: descriptor, modelURL: modelURL(for: descriptor), receipt: receipt)
  }

  /// Explicit verification rehashes the installed copy and refreshes its receipt.
  func verifyInstalledModel(_ descriptor: ModelDescriptor) throws -> VerifiedModel {
    let installed = try modelURL(for: descriptor)
    guard try fileSize(installed) == descriptor.expectedBytes else { throw GITimelineError.modelSizeMismatch }
    let actual = try sha256(of: installed)
    guard actual.caseInsensitiveCompare(descriptor.expectedSHA256) == .orderedSame else {
      throw GITimelineError.modelHashMismatch
    }
    let receipt = ModelVerificationReceipt(
      descriptorID: descriptor.id,
      modelID: descriptor.modelID,
      sourceRevision: descriptor.sourceRevision,
      artifactFilename: descriptor.artifactFilename,
      importedBytes: descriptor.expectedBytes,
      importedSHA256: actual.lowercased(),
      verifiedAt: Date(),
      locationKind: .applicationSupport
    )
    try writeReceipt(receipt, for: descriptor)
    return try VerifiedModel(validating: descriptor, modelURL: installed, receipt: receipt)
  }

  func modelURL(for descriptor: ModelDescriptor) throws -> URL {
    if let customModelsDirectory {
      let directory = customModelsDirectory.appendingPathComponent(descriptor.cacheNamespace, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return directory.appendingPathComponent(descriptor.artifactFilename)
    }
    return try AppFolders.modelURL(for: descriptor)
  }

  func bundledModelLocation(for descriptor: ModelDescriptor) throws -> ModelLocation {
    let directory: URL
    if let customEmbeddedModelsDirectory {
      directory = customEmbeddedModelsDirectory
    } else {
      guard let resources = Bundle.main.resourceURL else { throw GITimelineError.modelNotVerified }
      directory = resources.appendingPathComponent("EmbeddedModels", isDirectory: true)
    }
    return .bundled(directory.appendingPathComponent(descriptor.artifactFilename))
  }

  /// Resolves the distribution mode selected at compile time. The Hackathon
  /// target always prefers the signed bundle; ordinary Debug retains the
  /// existing Documents/Import -> Application Support fallback.
  func resolveVerifiedModel(for descriptor: ModelDescriptor) throws -> VerifiedModel {
    #if HACKATHON_EMBEDDED_GEMMA
    return try verifiedBundledModel(for: descriptor)
    #elseif DEBUG
    guard let imported = try verifiedModel(for: descriptor) else {
      throw GITimelineError.modelNotVerified
    }
    return imported
    #else
    throw GITimelineError.missingModelDescriptor
    #endif
  }

  /// Uses a build-keyed receipt to avoid hashing the 3.66 GB signed-bundle
  /// artifact on every launch. A missing, stale, or mismatched receipt triggers
  /// full streaming verification before a capability is returned.
  func verifiedBundledModel(for descriptor: ModelDescriptor) throws -> VerifiedModel {
    let location = try bundledModelLocation(for: descriptor)
    guard FileManager.default.fileExists(atPath: location.url.path),
      try fileSize(location.url) == descriptor.expectedBytes
    else { throw GITimelineError.modelSizeMismatch }

    if let receipt = try bundledReceipt(for: descriptor),
      receipt.matches(descriptor, location: location, appBuildIdentity: appBuildIdentity)
    {
      return try VerifiedModel(
        validating: descriptor,
        location: location,
        receipt: receipt,
        appBuildIdentity: appBuildIdentity
      )
    }

    let actualHash = try sha256(of: location.url)
    guard actualHash.caseInsensitiveCompare(descriptor.expectedSHA256) == .orderedSame else {
      throw GITimelineError.modelHashMismatch
    }
    let receipt = ModelVerificationReceipt(
      descriptorID: descriptor.id,
      modelID: descriptor.modelID,
      sourceRevision: descriptor.sourceRevision,
      artifactFilename: descriptor.artifactFilename,
      importedBytes: descriptor.expectedBytes,
      importedSHA256: actualHash.lowercased(),
      verifiedAt: Date(),
      locationKind: .applicationBundle,
      appBuildIdentity: appBuildIdentity
    )
    try writeReceipt(receipt, for: descriptor, locationKind: .applicationBundle)
    return try VerifiedModel(
      validating: descriptor,
      location: location,
      receipt: receipt,
      appBuildIdentity: appBuildIdentity
    )
  }

  private func importDirectory() throws -> URL {
    if let customImportDirectory {
      try FileManager.default.createDirectory(at: customImportDirectory, withIntermediateDirectories: true)
      return customImportDirectory
    }
    return try AppFolders.importFolder()
  }

  private func receiptURL(
    for descriptor: ModelDescriptor,
    locationKind: ModelLocation.Kind = .applicationSupport
  ) throws -> URL {
    let filename = locationKind == .applicationBundle
      ? "\(descriptor.id)-embedded.json"
      : "\(descriptor.id).json"
    if let customModelsDirectory {
      let directory = customModelsDirectory.appendingPathComponent("Receipts", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return directory.appendingPathComponent(filename)
    }
    let importedURL = try AppFolders.receiptURL(for: descriptor)
    return importedURL.deletingLastPathComponent().appendingPathComponent(filename)
  }

  private func bundledReceipt(for descriptor: ModelDescriptor) throws -> ModelVerificationReceipt? {
    let url = try receiptURL(for: descriptor, locationKind: .applicationBundle)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let receipt = try? decoder.decode(ModelVerificationReceipt.self, from: Data(contentsOf: url)) else {
      return nil
    }
    return receipt.matches(descriptor, location: try bundledModelLocation(for: descriptor), appBuildIdentity: appBuildIdentity)
      ? receipt
      : nil
  }

  private func writeReceipt(
    _ receipt: ModelVerificationReceipt,
    for descriptor: ModelDescriptor,
    locationKind: ModelLocation.Kind = .applicationSupport
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(receipt)
    let url = try receiptURL(for: descriptor, locationKind: locationKind)
    try data.write(to: url, options: .atomic)
    try AppFolders.protect(url)
  }

  private func fileSize(_ url: URL) throws -> Int64 {
    let value = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
    return value?.int64Value ?? 0
  }

  func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while let chunk = try handle.read(upToCount: 4 * 1_024 * 1_024), !chunk.isEmpty {
      digest.update(data: chunk)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
