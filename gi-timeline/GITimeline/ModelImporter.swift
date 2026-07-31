import CryptoKit
import Foundation

struct ModelImporter: Sendable {
  static let sourceFilename = "gemma-4-E4B-it.litertlm"

  func importE4B(expectedSHA256: String) throws -> URL {
    let source = try AppFolders.importFolder().appendingPathComponent(Self.sourceFilename)
    let destination = try AppFolders.models().appendingPathComponent("gemma-4-E4B-it.litertlm")
    let temporary = destination.deletingLastPathComponent().appendingPathComponent("model.tmp")
    let manager = FileManager.default
    let sourceSize = (try manager.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
    let remaining = try destination.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
    guard remaining >= sourceSize * 2 else { throw GITimelineError.insufficientModelStorage }
    try? manager.removeItem(at: temporary)
    try manager.copyItem(at: source, to: temporary) // source is retained until verification succeeds
    let actual = try sha256(of: temporary)
    guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else { try? manager.removeItem(at: temporary); throw GITimelineError.modelHashMismatch }
    do {
      if manager.fileExists(atPath: destination.path) {
        _ = try manager.replaceItemAt(destination, withItemAt: temporary)
      } else {
        try manager.moveItem(at: temporary, to: destination)
      }
    } catch {
      try? manager.removeItem(at: temporary)
      throw error
    }
    try manager.removeItem(at: source)
    return destination
  }
  private func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty { digest.update(data: chunk) }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
