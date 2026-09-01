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

struct PhotoTechnicalQualityMetrics: Equatable, Sendable {
  let pixelWidth: Int
  let pixelHeight: Int
  let aspectRatio: Double
  let meanLuminance: Double
  let p05Luminance: Double
  let p10Luminance: Double
  let p90Luminance: Double
  let p95Luminance: Double
  let laplacianVariance: Double
}

struct PhotoTechnicalQualityAssessment: Equatable, Sendable {
  static let contractVersion = "gi-v1-extreme-photo-quality-v1"
  static let minimumPixelDimension = 256
  static let maximumAspectRatio = 3.5
  static let maximumDarkMeanLuminance = 0.08
  static let maximumDarkP90Luminance = 0.12
  static let minimumGlareMeanLuminance = 0.84
  static let minimumGlareP10Luminance = 0.82
  static let minimumGlareP90Luminance = 0.96
  static let minimumSharpLaplacianVariance = 0.0004
  static let minimumBlurContrastRange = 0.15

  let metrics: PhotoTechnicalQualityMetrics
  let retakeReason: PhotoRetakeReason?

  var shouldCallGemma: Bool { retakeReason == nil }

  /// Evaluates only extreme, color-neutral capture failures on the already
  /// validated sanitized JPEG. The 64x64 sRGB raster, nearest-rank quantiles,
  /// ordered thresholds and four-neighbor Laplacian match the frozen plan.
  static func evaluate(_ data: Data) throws -> PhotoTechnicalQualityAssessment {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: 64,
        height: 64,
        bitsPerComponent: 8,
        bytesPerRow: 64 * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { throw GITimelineError.invalidImage }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
      throw GITimelineError.invalidImage
    }

    var luminance = [Double](repeating: 0, count: 64 * 64)
    for index in luminance.indices {
      let offset = index * 4
      luminance[index] = (
        0.2126 * Double(bytes[offset])
          + 0.7152 * Double(bytes[offset + 1])
          + 0.0722 * Double(bytes[offset + 2])
      ) / 255.0
    }
    let sorted = luminance.sorted()
    func nearestRank(_ probability: Double) -> Double {
      let rank = max(1, Int(ceil(probability * Double(sorted.count))))
      return sorted[min(sorted.count - 1, rank - 1)]
    }

    let mean = luminance.reduce(0, +) / Double(luminance.count)
    let p05 = nearestRank(0.05)
    let p10 = nearestRank(0.10)
    let p90 = nearestRank(0.90)
    let p95 = nearestRank(0.95)
    var laplacians: [Double] = []
    laplacians.reserveCapacity(62 * 62)
    for y in 1..<63 {
      for x in 1..<63 {
        let center = luminance[y * 64 + x]
        laplacians.append(
          luminance[(y - 1) * 64 + x]
            + luminance[(y + 1) * 64 + x]
            + luminance[y * 64 + x - 1]
            + luminance[y * 64 + x + 1]
            - 4 * center
        )
      }
    }
    let laplacianMean = laplacians.reduce(0, +) / Double(laplacians.count)
    let laplacianVariance = laplacians.reduce(0) { partial, value in
      let delta = value - laplacianMean
      return partial + delta * delta
    } / Double(laplacians.count)
    let aspect = max(
      Double(image.width) / Double(image.height),
      Double(image.height) / Double(image.width)
    )

    let metrics = PhotoTechnicalQualityMetrics(
      pixelWidth: image.width,
      pixelHeight: image.height,
      aspectRatio: aspect,
      meanLuminance: mean,
      p05Luminance: p05,
      p10Luminance: p10,
      p90Luminance: p90,
      p95Luminance: p95,
      laplacianVariance: laplacianVariance
    )
    return PhotoTechnicalQualityAssessment(
      metrics: metrics,
      retakeReason: retakeReason(for: metrics)
    )
  }

  /// Pure ordered classifier used by the JPEG evaluator and boundary tests.
  /// Keeping all frozen inequalities here makes exact edges and precedence
  /// inspectable without relying on lossy-JPEG round trips.
  static func retakeReason(
    for metrics: PhotoTechnicalQualityMetrics
  ) -> PhotoRetakeReason? {
    if metrics.pixelWidth < minimumPixelDimension
      || metrics.pixelHeight < minimumPixelDimension
    {
      return .other
    } else if metrics.aspectRatio > maximumAspectRatio {
      return .other
    } else if metrics.meanLuminance <= maximumDarkMeanLuminance
      && metrics.p90Luminance <= maximumDarkP90Luminance
    {
      return .tooDark
    } else if metrics.p90Luminance >= minimumGlareP90Luminance
      && (metrics.meanLuminance >= minimumGlareMeanLuminance
        || metrics.p10Luminance >= minimumGlareP10Luminance)
    {
      return .glare
    } else if metrics.laplacianVariance < minimumSharpLaplacianVariance
      && (metrics.p95Luminance - metrics.p05Luminance)
        >= minimumBlurContrastRange
    {
      return .blurred
    }
    return nil
  }
}

enum PhotoQualityRecommendationSeverity: String, Codable, Equatable, Sendable {
  case borderline
  case hard
}

enum PhotoQualityIssue: String, Codable, Equatable, Sendable {
  case severeBlur = "severe_blur"
  case tooDark = "too_dark"
  case overexposedGlare = "overexposed_glare"
  case nearBlank = "near_blank"
  case veryLowContrast = "very_low_contrast"
}

/// UI-facing interpretation of the existing, deterministic
/// `HybridPixelAnalyzer` evidence. Hard results stop automatic photo analysis;
/// borderline results keep the same photo eligible while offering a light
/// retake recommendation. No semantic model output participates in this gate.
struct PhotoQualityRecommendation: Codable, Equatable, Sendable {
  static let contractVersion = "gi-hybrid-photo-quality-preflight-v1"
  static let borderlineDarkFractionPPM = 650_000
  static let borderlineOverexposedFractionPPM = 650_000
  static let borderlineForegroundFractionPPM = 10_000
  static let borderlineLumaRange = 32
  static let borderlineStrongEdgeFractionPPM = 5_000

  let issue: PhotoQualityIssue
  let severity: PhotoQualityRecommendationSeverity
  let retakeReason: PhotoRetakeReason

  var shouldRunQwen: Bool { severity != .hard }

  var message: String {
    switch (severity, issue) {
    case (.hard, .severeBlur):
      return "This photo may be too blurry to provide useful suggestions. Taking another photo may improve the results."
    case (.hard, .tooDark):
      return "This photo may be too dark to provide useful suggestions. Taking another photo in more even light may improve the results."
    case (.hard, .overexposedGlare):
      return "This photo may be too bright or have too much glare to provide useful suggestions. Taking another photo in more even light may improve the results."
    case (.hard, .nearBlank):
      return "This photo may not show a visible subject clearly enough to provide useful suggestions. Taking another photo may improve the results."
    case (.hard, .veryLowContrast):
      return "This photo may have too little contrast or be too obscured to provide useful suggestions. Taking another photo may improve the results."
    case (.borderline, .severeBlur):
      return "This photo may be a little blurry. Another photo may improve the suggestions, or you can continue with this one."
    case (.borderline, .tooDark):
      return "This photo may be a little dark. Another photo in more even light may improve the suggestions, or you can continue with this one."
    case (.borderline, .overexposedGlare):
      return "This photo may be a little bright or have some glare. Another photo may improve the suggestions, or you can continue with this one."
    case (.borderline, .nearBlank):
      return "The subject may be difficult to see in this photo. Another photo may improve the suggestions, or you can continue with this one."
    case (.borderline, .veryLowContrast):
      return "This photo may have low contrast. Another photo may improve the suggestions, or you can continue with this one."
    }
  }

  static func make(
    from evidence: HybridPixelEvidence
  ) -> PhotoQualityRecommendation? {
    switch evidence.quality {
    case .hardPoorTooDark:
      return .init(issue: .tooDark, severity: .hard, retakeReason: .tooDark)
    case .hardPoorOverexposed:
      return .init(
        issue: .overexposedGlare, severity: .hard, retakeReason: .glare
      )
    case .hardPoorNearBlank:
      return .init(issue: .nearBlank, severity: .hard, retakeReason: .other)
    case .hardPoorLowContrast:
      return .init(
        issue: .veryLowContrast, severity: .hard, retakeReason: .obstructed
      )
    case .hardPoorSevereBlur:
      return .init(issue: .severeBlur, severity: .hard, retakeReason: .blurred)
    case .usable:
      break
    }

    if evidence.darkPixelFractionPPM >= borderlineDarkFractionPPM {
      return .init(issue: .tooDark, severity: .borderline, retakeReason: .tooDark)
    }
    if evidence.overexposedPixelFractionPPM
      >= borderlineOverexposedFractionPPM
    {
      return .init(
        issue: .overexposedGlare,
        severity: .borderline,
        retakeReason: .glare
      )
    }
    if evidence.foregroundFractionPPM <= borderlineForegroundFractionPPM {
      return .init(issue: .nearBlank, severity: .borderline, retakeReason: .other)
    }
    if evidence.lumaRange <= borderlineLumaRange {
      return .init(
        issue: .veryLowContrast,
        severity: .borderline,
        retakeReason: .obstructed
      )
    }
    if evidence.foregroundFractionPPM >= 20_000,
      evidence.strongEdgeFractionPPM <= borderlineStrongEdgeFractionPPM
    {
      return .init(
        issue: .severeBlur,
        severity: .borderline,
        retakeReason: .blurred
      )
    }
    return nil
  }
}

/// The only pre-model gate on the frozen candidate route. Both streaming and
/// synchronous sends call this seam, making a rejected photo provably return a
/// conservative abstention before the supplied native-send closure can run.
enum CandidatePhotoQualityGate {
  static func resolve(
    data: Data,
    sendToGemma: () async throws -> String
  ) async throws -> String {
    try await resolve(
      assessment: PhotoTechnicalQualityAssessment.evaluate(data),
      sendToGemma: sendToGemma
    )
  }

  static func resolve(
    assessment: PhotoTechnicalQualityAssessment,
    sendToGemma: () async throws -> String
  ) async throws -> String {
    if let reason = assessment.retakeReason {
      return try FullPrefillPhotoSuggestionV1Parser.canonicalJSON(
        .technicalAbstention(reason: reason)
      )
    }
    return try await sendToGemma()
  }
}

/// A photo that has been atomically moved out of the canonical Images folder,
/// but has not yet been permanently removed.  Keeping this state on the same
/// volume lets a failed SwiftData transaction restore the exact original file.
struct StagedImageDeletion: Equatable {
  let originalURL: URL
  let queuedURL: URL
}

enum ImageStoreDirectoryKind: Equatable {
  case drafts
  case images
  case deletionQueue
}

@MainActor final class ImageStore {
  typealias PreparedImageWriter = (Data, URL) throws -> Void
  typealias ImageDataReader = (URL) throws -> Data
  typealias DirectoryAccessFailureInjector = (ImageStoreDirectoryKind) throws -> Void
  typealias QueuedImageRemover = (URL) throws -> Void
  typealias BackupExcluder = (URL) throws -> Void
  typealias ProtectedDataAvailability = @MainActor () -> Bool

  nonisolated static let savedJPEGQuality: CGFloat = 0.80
  nonisolated static let savedColorSpaceName = CGColorSpace.sRGB

  private let fileManager = FileManager.default
  private let customDraftsDirectory: URL?
  private let customImagesDirectory: URL?
  private let preparedImageWriter: PreparedImageWriter
  private let imageDataReader: ImageDataReader
  private let directoryAccessFailureInjector: DirectoryAccessFailureInjector?
  private let queuedImageRemover: QueuedImageRemover
  private let backupExcluder: BackupExcluder
  private let protectedDataIsAvailable: ProtectedDataAvailability
  private let writeGate: JournalWriteGate

  init(
    draftsDirectory: URL? = nil,
    imagesDirectory: URL? = nil,
    preparedImageWriter: PreparedImageWriter? = nil,
    imageDataReader: ImageDataReader? = nil,
    directoryAccessFailureInjector: DirectoryAccessFailureInjector? = nil,
    queuedImageRemover: QueuedImageRemover? = nil,
    backupExcluder: BackupExcluder? = nil,
    protectedDataIsAvailable: @escaping ProtectedDataAvailability = {
      UIApplication.shared.isProtectedDataAvailable
    },
    writeGate: JournalWriteGate? = nil
  ) {
    customDraftsDirectory = draftsDirectory
    customImagesDirectory = imagesDirectory
    self.preparedImageWriter = preparedImageWriter ?? { data, url in
      try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
    self.imageDataReader = imageDataReader ?? { url in
      try Data(contentsOf: url, options: [.mappedIfSafe])
    }
    self.directoryAccessFailureInjector = directoryAccessFailureInjector
    self.queuedImageRemover = queuedImageRemover ?? { try FileManager.default.removeItem(at: $0) }
    self.backupExcluder = backupExcluder ?? AppFolders.excludeFromBackup
    self.protectedDataIsAvailable = protectedDataIsAvailable
    self.writeGate = writeGate ?? .app
  }

  func prepare(_ sourceData: Data) throws -> PreparedDraft {
    // This store captures the process epoch when its owning UI is created.
    // Check before image decoding or directory resolution so a late picker
    // completion cannot recreate even an empty Drafts directory after erase.
    try writeGate.requireWritable()
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
    guard let sanitizedCG = context.makeImage(),
      sanitizedCG.colorSpace?.name == Self.savedColorSpaceName
    else { throw GITimelineError.invalidImage }
    let encoded = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else {
      throw GITimelineError.invalidImage
    }
    CGImageDestinationAddImageAndMetadata(
      destination,
      sanitizedCG,
      nil,
      [kCGImageDestinationLossyCompressionQuality: Self.savedJPEGQuality] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else { throw GITimelineError.invalidImage }
    let jpeg = try stripMetadataSegments(from: encoded as Data)
    let id = UUID(); let url = try draftsDirectory().appendingPathComponent("\(id.uuidString).jpg")
    do {
      // Protection is part of the atomic commit. There is no separate
      // throwing protection operation after a complete JPEG becomes visible.
      try preparedImageWriter(jpeg, url)
      // Backup exclusion on the Drafts directory does not propagate as a
      // queryable resource value to newly created files on iOS. Apply it to
      // the concrete sanitized JPEG before returning it to durable draft
      // state. A failure follows the same orphan-cleanup boundary as a failed
      // write so callers never retain an unprotected draft reference.
      try backupExcluder(url)
    } catch {
      // Also covers a custom/future writer that reports failure after creating
      // the destination or a backup-exclusion failure: a failed prepare must
      // never strand an orphan draft.
      try? fileManager.removeItem(at: url)
      throw error
    }
    let digest = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
    #if DEBUG
    if let source = CGImageSourceCreateWithData(jpeg as CFData, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
      let privacyMetadataKeys: [CFString] = [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary]
      assert(privacyMetadataKeys.allSatisfy { properties[$0] == nil }, "Saved image must have zero EXIF/GPS dictionaries.")
      assert(properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelRGB as String, "Saved image must use an RGB color model.")
      let profile = properties[kCGImagePropertyProfileName] as? String
      assert(profile?.localizedCaseInsensitiveContains("sRGB") == true, "Saved image must declare an sRGB profile.")
    }
    #endif
    return PreparedDraft(reference: DraftReference(id: id, path: url.path, sha256: digest), url: url)
  }

  func promotedURL(for id: UUID) throws -> URL {
    try imagesDirectory().appendingPathComponent("\(id.uuidString).jpg")
  }

  /// Copies a sanitized draft only after confirming its expected hash and
  /// verifies the resulting canonical JPEG again immediately after promotion.
  /// A failed promotion never overwrites an existing canonical image.
  func promoteVerifiedDraft(_ draft: URL, to image: URL, expectedSHA256: String) throws {
    try writeGate.requireWritable()
    let normalizedDraft = try validatedDraftURL(draft)
    let normalizedImage = try validatedCanonicalImageURL(image)
    guard Self.isValidSHA256(expectedSHA256) else { throw GITimelineError.invalidPhotoAttachment }
    if fileManager.fileExists(atPath: normalizedImage.path) {
      // EntryStore has already proven that no row owns this transaction ID.
      // A byte-identical canonical JPEG is therefore a recoverable promotion
      // from a crash between copy verification and row insertion.
      do {
        try verifyJPEG(at: normalizedImage, expectedSHA256: expectedSHA256)
      } catch {
        // Never replace or remove a different/unsafe canonical candidate.
        throw GITimelineError.ambiguousPhotoState
      }
      // iOS can drop this URL resource value during a move or restore. A
      // byte-identical crash-recovery promotion still needs the retained
      // journal file explicitly re-hardened before its row can be inserted.
      try backupExcluder(normalizedImage)
      return
    }

    // This is deliberately adjacent to copyItem: the exact staged bytes are
    // rehashed immediately before they cross into the canonical folder.
    try verifyJPEG(at: normalizedDraft, expectedSHA256: expectedSHA256)

    var copied = false
    do {
      try fileManager.copyItem(at: normalizedDraft, to: normalizedImage)
      copied = true
      try protect(normalizedImage)
      // Backup exclusion is required file hardening, not best effort: a row
      // must never commit while its retained journal JPEG can be backed up.
      try backupExcluder(normalizedImage)
      // Rehash immediately after promotion.  A partial or altered copy is
      // never allowed to become a durable record attachment.
      try verifyJPEG(at: normalizedImage, expectedSHA256: expectedSHA256)
    } catch {
      if copied {
        discardUncommittedPromotion(at: normalizedImage)
      }
      throw error
    }
  }

  /// Verifies a regular, non-symlink JPEG and returns its canonical SHA-256.
  /// Callers are responsible for constraining the parent directory first.
  @discardableResult
  func verifyJPEG(at url: URL, expectedSHA256: String) throws -> String {
    guard Self.isValidSHA256(expectedSHA256) else { throw GITimelineError.invalidPhotoAttachment }
    try requireRegularFile(at: url)
    let data = try imageDataReader(url)
    try Self.validateSanitizedJournalJPEG(data, expectedSHA256: expectedSHA256)
    return Self.sha256Hex(data)
  }

  /// Produces the provider-neutral identity of the exact sanitized bytes that
  /// a photo engine may analyze. The engine must independently re-read and
  /// rehash the same URL immediately before its one model call.
  func preparedPhotoSuggestionInput(
    for draft: PreparedDraft,
    requestID: UUID
  ) throws -> PreparedPhotoSuggestionInput {
    let data = try imageDataReader(draft.url)
    try Self.validateSanitizedJournalJPEG(
      data,
      expectedSHA256: draft.reference.sha256
    )
    let assessment = try PhotoTechnicalQualityAssessment.evaluate(data)
    return PreparedPhotoSuggestionInput(
      requestID: requestID,
      url: draft.url,
      sha256: draft.reference.sha256,
      pixelWidth: assessment.metrics.pixelWidth,
      pixelHeight: assessment.metrics.pixelHeight
    )
  }

  /// Runs the same deterministic pixel analyzer used by the Qwen hybrid lane
  /// against the exact retained, hash-validated JPEG before any automatic
  /// engine preparation or generation. Quality is measured on decoded source
  /// content, before Qwen's square derivative adds neutral letterboxing; the
  /// padding must never make a dark, bright, or blurred 4:3 photo look usable.
  func photoQualityRecommendation(
    for draft: PreparedDraft
  ) throws -> PhotoQualityRecommendation? {
    let data = try imageDataReader(draft.url)
    try Self.validateSanitizedJournalJPEG(
      data,
      expectedSHA256: draft.reference.sha256
    )
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw GITimelineError.invalidImage }

    return PhotoQualityRecommendation.make(
      from: HybridPixelAnalyzer.evaluate(
        try Self.canonicalHybridRGBA(image)
      )
    )
  }

  private static func canonicalHybridRGBA(
    _ image: CGImage
  ) throws -> HybridRGBAFrame {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw GITimelineError.invalidImage
    }
    var rgba = Data(count: image.width * image.height * 4)
    let rendered = rgba.withUnsafeMutableBytes { raw -> Bool in
      guard let context = CGContext(
        data: raw.baseAddress,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return false }
      context.interpolationQuality = .none
      context.translateBy(x: 0, y: CGFloat(image.height))
      context.scaleBy(x: 1, y: -1)
      context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
      )
      return true
    }
    guard rendered else { throw GITimelineError.invalidImage }
    return try HybridRGBAFrame(
      width: image.width,
      height: image.height,
      rgba: rgba
    )
  }

  /// Retained journal bytes are valid only when they match the same bounded,
  /// metadata-free JPEG representation produced by `prepare`.
  nonisolated static func validateSanitizedJournalJPEG(_ data: Data, expectedSHA256: String) throws {
    guard isValidSHA256(expectedSHA256), sha256Hex(data) == expectedSHA256 else {
      throw GITimelineError.imageHashMismatch
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let type = CGImageSourceGetType(source),
      CFEqual(type, UTType.jpeg.identifier as CFString),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
      width > 0, height > 0, width <= 1_024, height <= 1_024,
      properties[kCGImagePropertyExifDictionary] == nil,
      properties[kCGImagePropertyGPSDictionary] == nil,
      properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelRGB as String,
      (properties[kCGImagePropertyProfileName] as? String)?.localizedCaseInsensitiveContains("sRGB") == true,
      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    else { throw GITimelineError.invalidImage }
  }

  /// True only when the stored image can be read as the expected JPEG. Missing
  /// or invalid evidence returns false, while a temporary complete-protection
  /// denial is propagated so launch blocks and retries after the next unlock.
  /// The check is intentionally non-destructive.
  func storedImageIsVerified(filename: String, expectedSHA256: String) throws -> Bool {
    guard let url = imageURL(filename: filename) else { return false }
    do {
      try verifyJPEG(at: url, expectedSHA256: expectedSHA256)
      return true
    } catch {
      if Self.isProtectedDataReadFailure(
        error,
        protectedDataIsAvailable: protectedDataIsAvailable()
      ) {
        throw error
      }
      return false
    }
  }

  static func isProtectedDataReadFailure(
    _ error: Error,
    protectedDataIsAvailable: Bool
  ) -> Bool {
    if !protectedDataIsAvailable { return true }
    let cocoa = error as NSError
    if cocoa.domain == NSCocoaErrorDomain,
      cocoa.code == CocoaError.Code.fileReadNoPermission.rawValue
    {
      return true
    }
    if cocoa.domain == NSPOSIXErrorDomain,
      cocoa.code == 1 || cocoa.code == 13
    {
      return true
    }
    if let underlying = cocoa.userInfo[NSUnderlyingErrorKey] as? NSError,
      underlying.domain == NSPOSIXErrorDomain,
      underlying.code == 1 || underlying.code == 13
    {
      return true
    }
    return false
  }

  /// Atomically moves a canonical image into a protected, same-volume queue.
  /// If a process stops before the database save, reconcile can move it back.
  func stageForDeletion(_ image: URL) throws -> StagedImageDeletion? {
    try writeGate.requireWritable()
    let original = try validatedCanonicalImageURL(image)
    let queue = try deletionQueueDirectory()
    let queued = queue.appendingPathComponent(original.lastPathComponent, isDirectory: false)
    let originalExists = fileManager.fileExists(atPath: original.path)
    let queuedExists = fileManager.fileExists(atPath: queued.path)

    if originalExists && queuedExists {
      // Two independently durable candidates for one filename are ambiguous.
      // Preserve both until a human or a later repair can resolve them.
      throw GITimelineError.ambiguousPhotoState
    }
    if queuedExists {
      try requireRegularFile(at: queued)
      // A retry can encounter a queue item restored from a move or a system
      // recovery. Reassert the file-level exclusion before treating it as a
      // protected deletion candidate.
      try backupExcluder(queued)
      return StagedImageDeletion(originalURL: original, queuedURL: queued)
    }
    guard originalExists else { return nil }
    try requireRegularFile(at: original)
    try fileManager.moveItem(at: original, to: queued)
    try protect(queued)
    // A move can drop the file-level resource value even though the queue
    // directory is excluded. A failure leaves the exact bytes queued for
    // reconciliation rather than discarding the retained-photo evidence.
    try backupExcluder(queued)
    return StagedImageDeletion(originalURL: original, queuedURL: queued)
  }

  /// Reverses a staged deletion after a database failure.  The operation is
  /// conservative: when both locations exist, neither one is removed.
  func restore(_ staged: StagedImageDeletion) throws {
    try writeGate.requireWritable()
    let original = try validatedCanonicalImageURL(staged.originalURL)
    let queued = try validatedQueuedURL(staged.queuedURL)
    let originalExists = fileManager.fileExists(atPath: original.path)
    let queuedExists = fileManager.fileExists(atPath: queued.path)

    if originalExists && queuedExists { throw GITimelineError.ambiguousPhotoState }
    if originalExists {
      // The prior move or a system recovery may have dropped this value. An
      // idempotent restore retry must still re-harden the retained JPEG.
      try backupExcluder(original)
      return
    }
    guard queuedExists else { throw GITimelineError.photoRecoveryRequired }
    try requireRegularFile(at: queued)
    try fileManager.moveItem(at: queued, to: original)
    do {
      try protect(original)
      // A same-volume restoration can still lose the file-level resource
      // value. Do not make a retained row visible again until its JPEG is
      // explicitly excluded from automatic backup.
      try backupExcluder(original)
    } catch {
      // The database row still owns these exact bytes. Return them to the
      // protected recovery queue so a failed re-hardening cannot leave an
      // unexcluded canonical JPEG or discard the only retained copy.
      if !fileManager.fileExists(atPath: queued.path),
        fileManager.fileExists(atPath: original.path)
      {
        try? fileManager.moveItem(at: original, to: queued)
        try? protect(queued)
      }
      throw error
    }
  }

  /// Permanently removes only a file already placed in the deletion queue.
  /// A failure leaves the queued copy for launch reconciliation to retry.
  @discardableResult
  func finalize(_ staged: StagedImageDeletion) -> Bool {
    guard (try? writeGate.requireWritable()) != nil else { return false }
    guard let queued = try? validatedQueuedURL(staged.queuedURL),
      fileManager.fileExists(atPath: queued.path),
      (try? isRegularFile(at: queued)) == true
    else { return false }
    do {
      try queuedImageRemover(queued)
      return true
    } catch {
      return false
    }
  }

  /// Removes a save-time promoted copy only through the recovery queue.  The
  /// original draft is retained, so an interrupted cleanup remains recoverable.
  func discardUncommittedPromotion(at image: URL) {
    guard let staged = try? stageForDeletion(image) else { return }
    _ = finalize(staged)
  }

  /// This legacy convenience is intentionally restricted to prepared drafts.
  /// Canonical Images and queued deletions must use the transactional APIs
  /// above so an ambiguous caller cannot silently erase journal evidence.
  @discardableResult
  func deleteBestEffort(_ url: URL) -> Bool {
    guard (try? writeGate.requireWritable()) != nil else { return false }
    guard let drafts = try? draftsDirectory().standardizedFileURL else { return false }
    let candidate = url.standardizedFileURL
    guard candidate.deletingLastPathComponent() == drafts,
      Self.isSafeImageFilename(candidate.lastPathComponent)
    else { return false }
    guard fileManager.fileExists(atPath: candidate.path) else { return true }
    do {
      try fileManager.removeItem(at: candidate)
      return true
    } catch {
      return false
    }
  }

  /// Returns a URL only for a flat JPEG name in this app's canonical Images
  /// directory.  It deliberately refuses traversal and non-JPEG references.
  func imageURL(filename: String?) -> URL? {
    guard let filename, Self.isSafeImageFilename(filename), let folder = try? imagesDirectory() else { return nil }
    return folder.standardizedFileURL.appendingPathComponent(filename, isDirectory: false)
  }

  func sweepDrafts(keeping current: URL?) {
    guard let folder = try? draftsDirectory(), let files = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
    for file in files where file != current { deleteBestEffort(file) }
  }
  func draftsDirectory() throws -> URL {
    try directoryAccessFailureInjector?(.drafts)
    return try preparedDirectory(customDraftsDirectory, fallback: AppFolders.drafts)
  }
  func imagesDirectory() throws -> URL {
    try directoryAccessFailureInjector?(.images)
    return try preparedDirectory(customImagesDirectory, fallback: AppFolders.images)
  }

  /// Entries in this protected child directory are never shown as journal
  /// photos.  It sits under Images, guaranteeing same-volume atomic moves.
  func deletionQueueDirectory() throws -> URL {
    try directoryAccessFailureInjector?(.deletionQueue)
    let images = try imagesDirectory().standardizedFileURL
    let queue = images.appendingPathComponent(".DeletionQueue", isDirectory: true)
    if fileManager.fileExists(atPath: queue.path) {
      let values = try queue.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        throw GITimelineError.ambiguousPhotoState
      }
    } else {
      try fileManager.createDirectory(at: queue, withIntermediateDirectories: true)
    }
    try protect(queue)
    try? AppFolders.excludeFromBackup(queue)
    return queue
  }

  /// Direct regular JPEG files only; directories, symlinks, queue contents,
  /// and unknown extensions are deliberately left untouched by reconciliation.
  func canonicalImageFilesForReconciliation() throws -> [URL] {
    try regularJPEGChildren(of: imagesDirectory())
  }

  /// Direct regular queue JPEGs only.  Unrecognized artifacts are preserved
  /// rather than treated as safe deletion targets.
  func queuedImageFilesForReconciliation() throws -> [URL] {
    try regularJPEGChildren(of: deletionQueueDirectory())
  }

  func restoreQueuedImage(named filename: String) throws -> Bool {
    guard Self.isSafeImageFilename(filename),
      let original = imageURL(filename: filename)
    else { throw GITimelineError.invalidPhotoAttachment }
    let queued = try deletionQueueDirectory().appendingPathComponent(filename, isDirectory: false)
    guard fileManager.fileExists(atPath: queued.path) else { return false }
    try restore(StagedImageDeletion(originalURL: original, queuedURL: queued))
    return true
  }

  /// Retries deletion only for a regular JPEG that is already inside the
  /// recovery queue.  This can never remove a canonical Images file.
  @discardableResult
  func finalizeQueuedImage(at queued: URL) -> Bool {
    guard (try? writeGate.requireWritable()) != nil else { return false }
    guard let normalized = try? validatedQueuedURL(queued),
      fileManager.fileExists(atPath: normalized.path),
      (try? isRegularFile(at: normalized)) == true
    else { return false }
    do {
      try queuedImageRemover(normalized)
      return true
    } catch {
      return false
    }
  }

  nonisolated static func isSafeImageFilename(_ filename: String) -> Bool {
    guard !filename.isEmpty,
      filename == (filename as NSString).lastPathComponent,
      !filename.hasPrefix("."),
      (filename as NSString).pathExtension.lowercased() == "jpg",
      filename.count <= 128
    else { return false }
    return true
  }

  nonisolated static func isValidSHA256(_ value: String) -> Bool {
    value.count == 64 && value == value.lowercased() && value.allSatisfy(\.isHexDigit)
  }

  private func preparedDirectory(_ custom: URL?, fallback: () throws -> URL) throws -> URL {
    guard let custom else { return try fallback() }
    try fileManager.createDirectory(at: custom, withIntermediateDirectories: true)
    try protect(custom)
    return custom
  }
  private func protect(_ url: URL) throws { try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path) }

  private func validatedDraftURL(_ url: URL) throws -> URL {
    let folder = try draftsDirectory().standardizedFileURL
    let candidate = url.standardizedFileURL
    guard candidate.deletingLastPathComponent() == folder,
      Self.isSafeImageFilename(candidate.lastPathComponent),
      UUID(uuidString: String(candidate.lastPathComponent.dropLast(4))) != nil
    else { throw GITimelineError.invalidPhotoAttachment }
    return candidate
  }

  private func validatedCanonicalImageURL(_ url: URL) throws -> URL {
    let folder = try imagesDirectory().standardizedFileURL
    let candidate = url.standardizedFileURL
    guard candidate.deletingLastPathComponent() == folder,
      Self.isSafeImageFilename(candidate.lastPathComponent)
    else { throw GITimelineError.invalidPhotoAttachment }
    return candidate
  }

  private func validatedQueuedURL(_ url: URL) throws -> URL {
    let folder = try deletionQueueDirectory().standardizedFileURL
    let candidate = url.standardizedFileURL
    guard candidate.deletingLastPathComponent() == folder,
      Self.isSafeImageFilename(candidate.lastPathComponent)
    else { throw GITimelineError.invalidPhotoAttachment }
    return candidate
  }

  private func regularJPEGChildren(of folder: URL) throws -> [URL] {
    let normalizedFolder = folder.standardizedFileURL
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
    return try fileManager.contentsOfDirectory(at: normalizedFolder, includingPropertiesForKeys: Array(keys), options: [])
      .map(\.standardizedFileURL)
      .filter { candidate in
        guard candidate.deletingLastPathComponent() == normalizedFolder,
          Self.isSafeImageFilename(candidate.lastPathComponent),
          let values = try? candidate.resourceValues(forKeys: keys)
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
      }
  }

  private func requireRegularFile(at url: URL) throws {
    guard try isRegularFile(at: url) else { throw GITimelineError.invalidPhotoAttachment }
  }

  private func isRegularFile(at url: URL) throws -> Bool {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    return values.isRegularFile == true && values.isSymbolicLink != true
  }

  nonisolated private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

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
