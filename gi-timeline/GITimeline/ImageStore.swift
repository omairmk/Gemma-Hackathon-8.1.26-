import CryptoKit
import Foundation
import ImageIO
import UIKit
import GITimelineCore
import UniformTypeIdentifiers

struct PreparedDraft: Sendable {
  let reference: DraftReference
  let url: URL
}

@MainActor final class ImageStore {
  private let fileManager = FileManager.default
  private let customDraftsDirectory: URL?
  private let customImagesDirectory: URL?

  init(draftsDirectory: URL? = nil, imagesDirectory: URL? = nil) {
    customDraftsDirectory = draftsDirectory
    customImagesDirectory = imagesDirectory
  }

  func prepare(_ sourceData: Data) throws -> PreparedDraft {
    guard let source = UIImage(data: sourceData) else { throw GITimelineError.invalidImage }
    let maxSide: CGFloat = 1024
    let scale = min(1, maxSide / max(source.size.width, source.size.height))
    let target = CGSize(width: max(1, (source.size.width * scale).rounded()), height: max(1, (source.size.height * scale).rounded()))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.preferredRange = .standard
    let normalized = UIGraphicsImageRenderer(size: target, format: format).image { _ in source.draw(in: CGRect(origin: .zero, size: target)) }
    guard let normalizedCG = normalized.cgImage, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: Int(target.width), height: Int(target.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw GITimelineError.invalidImage }
    context.interpolationQuality = .high
    context.draw(normalizedCG, in: CGRect(origin: .zero, size: target))
    guard let sanitizedCG = context.makeImage() else { throw GITimelineError.invalidImage }
    let encoded = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else {
      throw GITimelineError.invalidImage
    }
    CGImageDestinationAddImageAndMetadata(destination, sanitizedCG, nil, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw GITimelineError.invalidImage }
    let jpeg = try stripMetadataSegments(from: encoded as Data)
    let id = UUID(); let url = try draftsDirectory().appendingPathComponent("\(id.uuidString).jpg")
    try jpeg.write(to: url, options: .atomic)
    try protect(url)
    let digest = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
    #if DEBUG
    if let source = CGImageSourceCreateWithData(jpeg as CFData, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
      let privacyMetadataKeys: [CFString] = [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary]
      assert(privacyMetadataKeys.allSatisfy { properties[$0] == nil }, "Saved image must have zero EXIF/GPS dictionaries.")
      assert(properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelRGB as String, "Saved image must use an RGB color model.")
    }
    #endif
    return PreparedDraft(reference: DraftReference(id: id, path: url.path, sha256: digest), url: url)
  }

  func promotedURL(for id: UUID) throws -> URL { try imagesDirectory().appendingPathComponent("\(id.uuidString).jpg") }
  func copyDraft(_ draft: URL, to image: URL) throws { try fileManager.copyItem(at: draft, to: image); try protect(image) }
  func deleteBestEffort(_ url: URL) { try? fileManager.removeItem(at: url) }
  func imageURL(filename: String?) -> URL? { guard let filename else { return nil }; return try? imagesDirectory().appendingPathComponent(filename) }
  func sweepDrafts(keeping current: URL?) {
    guard let folder = try? draftsDirectory(), let files = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
    for file in files where file != current { deleteBestEffort(file) }
  }
  func draftsDirectory() throws -> URL { try preparedDirectory(customDraftsDirectory, fallback: AppFolders.drafts) }
  func imagesDirectory() throws -> URL { try preparedDirectory(customImagesDirectory, fallback: AppFolders.images) }
  private func preparedDirectory(_ custom: URL?, fallback: () throws -> URL) throws -> URL {
    guard let custom else { return try fallback() }
    try fileManager.createDirectory(at: custom, withIntermediateDirectories: true)
    try protect(custom)
    return custom
  }
  private func protect(_ url: URL) throws { try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path) }

  /// ImageIO writes a small APP1 EXIF block even for a newly drawn CGImage.
  /// Remove metadata-bearing JPEG segments while retaining JFIF, ICC/sRGB,
  /// quantization/Huffman tables, frame data, and the entropy-coded scan.
  private func stripMetadataSegments(from jpeg: Data) throws -> Data {
    let bytes = [UInt8](jpeg)
    guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { throw GITimelineError.invalidImage }
    var output = Data(bytes[0...1])
    var index = 2

    while index < bytes.count {
      let markerStart = index
      guard bytes[index] == 0xFF else { throw GITimelineError.invalidImage }
      while index < bytes.count, bytes[index] == 0xFF { index += 1 }
      guard index < bytes.count else { throw GITimelineError.invalidImage }
      let marker = bytes[index]
      index += 1

      if marker == 0xDA { // Start of scan: the remainder is entropy-coded image data.
        output.append(contentsOf: bytes[markerStart...])
        return output
      }
      if marker == 0xD9 {
        output.append(contentsOf: bytes[markerStart..<index])
        return output
      }
      if marker == 0x01 || (0xD0...0xD7).contains(marker) {
        output.append(contentsOf: bytes[markerStart..<index])
        continue
      }

      guard index + 1 < bytes.count else { throw GITimelineError.invalidImage }
      let length = (Int(bytes[index]) << 8) | Int(bytes[index + 1])
      guard length >= 2, index + length <= bytes.count else { throw GITimelineError.invalidImage }
      let segmentEnd = index + length
      let isMetadata = marker == 0xE1 || marker == 0xED || marker == 0xFE // APP1, APP13, COM
      if !isMetadata { output.append(contentsOf: bytes[markerStart..<segmentEnd]) }
      index = segmentEnd
    }
    throw GITimelineError.invalidImage
  }
}
