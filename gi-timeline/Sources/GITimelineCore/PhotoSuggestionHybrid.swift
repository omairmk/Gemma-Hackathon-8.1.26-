import CryptoKit
import Foundation

public enum Qwen3HybridTriState: String, Codable, CaseIterable, Sendable {
  case yes
  case no
  case notSure = "not_sure"
}

public enum Qwen3HybridWireForm: String, Codable, CaseIterable, Sendable {
  case hardLumps = "hard_lumps"
  case lumpyFormed = "lumpy_formed"
  case crackedFormed = "cracked_formed"
  case smoothFormed = "smooth_formed"
  case softBlobs = "soft_blobs"
  case mushy
  case watery
  case notSure = "not_sure"
}

public enum Qwen3HybridWireColor: String, Codable, CaseIterable, Hashable, Sendable {
  case brown
  case lightBrown = "light_brown"
  case darkBrown = "dark_brown"
  case green
  case yellow
  case orange
  case redAppearing = "red_appearing"
  case blackAppearing = "black_appearing"
  case paleOrClayAppearing = "pale_or_clay_appearing"
  case mixed
  case notSure = "not_sure"
}

/// The compact model-only wire object. It is never persisted as a V2 payload.
/// Fusion is the only component allowed to emit `PhotoSuggestionPayloadV2`.
public struct Qwen3HybridWirePayload: Codable, Equatable, Sendable {
  public let s: Qwen3HybridTriState
  public let f: Qwen3HybridWireForm
  public let m: Qwen3HybridTriState
  public let c: Qwen3HybridWireColor
  public let r: Qwen3HybridTriState
  public let b: Qwen3HybridTriState
  public let g: Qwen3HybridTriState

  public init(
    s: Qwen3HybridTriState,
    f: Qwen3HybridWireForm,
    m: Qwen3HybridTriState,
    c: Qwen3HybridWireColor,
    r: Qwen3HybridTriState,
    b: Qwen3HybridTriState,
    g: Qwen3HybridTriState
  ) {
    self.s = s
    self.f = f
    self.m = m
    self.c = c
    self.r = r
    self.b = b
    self.g = g
  }
}

public enum Qwen3HybridWireParserError: Error, Equatable, Sendable {
  case invalidUTF8
  case invalidEnvelope
  case invalidJSON
  case duplicateKey
  case wrongKeySet
  case wrongTypeOrEnum
  case inconsistent(String)
}

public struct Qwen3HybridWireParseResult: Equatable, Sendable {
  public let payload: Qwen3HybridWirePayload
  public let rawUTF8: Data
  public let rawSHA256: String
  public let extractedObjectUTF8: Data
  public let extractedObjectSHA256: String
  public let canonicalObject: String
  public let formatCompliant: Bool

  public init(
    payload: Qwen3HybridWirePayload,
    rawUTF8: Data,
    rawSHA256: String,
    extractedObjectUTF8: Data,
    extractedObjectSHA256: String,
    canonicalObject: String,
    formatCompliant: Bool
  ) {
    self.payload = payload
    self.rawUTF8 = rawUTF8
    self.rawSHA256 = rawSHA256
    self.extractedObjectUTF8 = extractedObjectUTF8
    self.extractedObjectSHA256 = extractedObjectSHA256
    self.canonicalObject = canonicalObject
    self.formatCompliant = formatCompliant
  }
}

public enum Qwen3HybridWireParser {
  public static let parserVersion = "q3h2-parser-v1"
  public static let orderedKeys = ["s", "f", "m", "c", "r", "b", "g"]
  public static let expectedKeys = Set(orderedKeys)

  public static func parse(rawUTF8: Data) throws -> Qwen3HybridWireParseResult {
    guard String(data: rawUTF8, encoding: .utf8) != nil,
      !rawUTF8.starts(with: [0xEF, 0xBB, 0xBF])
    else { throw Qwen3HybridWireParserError.invalidUTF8 }

    let objectData = try extractOnlyObject(rawUTF8)
    guard let object = String(data: objectData, encoding: .utf8) else {
      throw Qwen3HybridWireParserError.invalidUTF8
    }
    guard JSONTopLevelKeyScanner.hasUniqueKeys(in: object) else {
      throw Qwen3HybridWireParserError.duplicateKey
    }
    guard let decoded = try? JSONSerialization.jsonObject(with: objectData),
      let dictionary = decoded as? [String: Any]
    else { throw Qwen3HybridWireParserError.invalidJSON }
    // A unique balanced object remains usable when just one semantic field is
    // malformed: each field maps independently to not_sure without repair.
    let payload = Qwen3HybridWirePayload(
      s: tri(dictionary["s"]), f: form(dictionary["f"]),
      m: tri(dictionary["m"]), c: color(dictionary["c"]),
      r: tri(dictionary["r"]), b: tri(dictionary["b"]),
      g: tri(dictionary["g"])
    )
    let canonical = canonicalObject(payload)
    return Qwen3HybridWireParseResult(
      payload: payload,
      rawUTF8: rawUTF8,
      rawSHA256: sha256(rawUTF8),
      extractedObjectUTF8: objectData,
      extractedObjectSHA256: sha256(objectData),
      canonicalObject: canonical,
      formatCompliant: object == canonical && Set(dictionary.keys) == expectedKeys
    )
  }

  public static func validate(_ payload: Qwen3HybridWirePayload) throws {
    // Safety and cross-field handling occur in deterministic fusion.
  }

  public static func canonicalObject(_ payload: Qwen3HybridWirePayload) -> String {
    "{\"s\":\"" + payload.s.rawValue + "\",\"f\":\"" + payload.f.rawValue
      + "\",\"m\":\"" + payload.m.rawValue + "\",\"c\":\"" + payload.c.rawValue + "\",\"r\":\"" + payload.r.rawValue
      + "\",\"b\":\"" + payload.b.rawValue + "\",\"g\":\"" + payload.g.rawValue + "\"}"
  }

  private static func tri(_ value: Any?) -> Qwen3HybridTriState {
    guard let value = value as? String, let parsed = Qwen3HybridTriState(rawValue: value) else { return .notSure }
    return parsed
  }

  private static func form(_ value: Any?) -> Qwen3HybridWireForm {
    guard let value = value as? String, let parsed = Qwen3HybridWireForm(rawValue: value) else { return .notSure }
    return parsed
  }

  private static func color(_ value: Any?) -> Qwen3HybridWireColor {
    guard let value = value as? String, let parsed = Qwen3HybridWireColor(rawValue: value) else { return .notSure }
    return parsed
  }

  private static func extractOnlyObject(_ data: Data) throws -> Data {
    let bytes = [UInt8](data)
    var start: Int?
    var end: Int?
    var depth = 0
    var inString = false
    var escaped = false

    for index in bytes.indices {
      let byte = bytes[index]
      if start == nil {
        if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { continue }
        if byte == 0x7D { throw Qwen3HybridWireParserError.invalidEnvelope }
        if byte == 0x7B {
          start = index
          depth = 1
        } else { throw Qwen3HybridWireParserError.invalidEnvelope }
        continue
      }
      if end != nil {
        guard byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D else {
          throw Qwen3HybridWireParserError.invalidEnvelope
        }
        continue
      }
      if inString {
        if escaped { escaped = false }
        else if byte == 0x5C { escaped = true }
        else if byte == 0x22 { inString = false }
        continue
      }
      if byte == 0x22 { inString = true }
      else if byte == 0x7B { depth += 1 }
      else if byte == 0x7D {
        depth -= 1
        if depth == 0 { end = index }
        else if depth < 0 { throw Qwen3HybridWireParserError.invalidEnvelope }
      }
    }
    guard let objectStart = start, let objectEnd = end, !inString, depth == 0 else {
      throw Qwen3HybridWireParserError.invalidEnvelope
    }
    return Data(bytes[objectStart...objectEnd])
  }

  fileprivate static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

public struct HybridRGBAFrame: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public let rgba: Data

  public init(width: Int, height: Int, rgba: Data) throws {
    guard width > 0, height > 0,
      width <= Int.max / height / 4,
      rgba.count == width * height * 4
    else { throw HybridImagePreparationError.invalidFrame }
    self.width = width
    self.height = height
    self.rgba = rgba
  }
}

public struct HybridContentRect: Codable, Equatable, Sendable {
  public let x: Int
  public let y: Int
  public let width: Int
  public let height: Int
}

public struct HybridDerivativeProvenance: Codable, Equatable, Sendable {
  public static let policy = "whole_frame_pixel_center_nearest_neighbor_aspect_fit_centered_no_crop_no_stretch"

  public let sourceImageBytes: Int
  public let sourceImageSHA256: String
  public let decodedWidth: Int
  public let decodedHeight: Int
  public let decodedRGBASHA256: String
  public let derivativeWidth: Int
  public let derivativeHeight: Int
  public let derivativeBytesPerRow: Int
  public let derivativeRGBASHA256: String
  public let contentRect: HybridContentRect
  public let horizontalScaleNumerator: Int
  public let horizontalScaleDenominator: Int
  public let verticalScaleNumerator: Int
  public let verticalScaleDenominator: Int
  public let paddingRGBA: [UInt8]
  public let rowOrder: String
  public let colorSpace: String
  public let policy: String
}

public struct HybridPreparedImage: Equatable, Sendable {
  public let rgba: Data
  public let provenance: HybridDerivativeProvenance
}

public enum HybridImagePreparationError: Error, Equatable, Sendable {
  case invalidFrame
  case emptySourceData
  case invalidHostOnlyCanvasSize
}

public enum HybridImagePreparer {
  public static let canvasSize = 512
  public static let paddingRGBA: [UInt8] = [128, 128, 128, 255]

  /// The caller must decode one held, sanitized source image into canonical
  /// upright sRGB RGBA once. This function consumes those same held bytes and pixels;
  /// it never reopens a path or performs another decode.
  public static func prepare(
    heldSourceImageData: Data,
    decodedRGBA: HybridRGBAFrame
  ) throws -> HybridPreparedImage {
    try prepare(
      heldSourceImageData: heldSourceImageData,
      decodedRGBA: decodedRGBA,
      hostOnlyCanvasSize: canvasSize
    )
  }

  /// Internal QA and host evidence tooling may request a pinned comparison
  /// derivative. The production app always calls the two-argument overload
  /// above, whose 512-pixel output remains byte-for-byte unchanged. A caller
  /// using 768 or 1024 must preserve its QA/host-only qualification; this API
  /// does not establish model-runtime or device equivalence.
  public static func prepare(
    heldSourceImageData: Data,
    decodedRGBA: HybridRGBAFrame,
    hostOnlyCanvasSize: Int
  ) throws -> HybridPreparedImage {
    guard !heldSourceImageData.isEmpty else { throw HybridImagePreparationError.emptySourceData }
    guard [canvasSize, 768, 1024].contains(hostOnlyCanvasSize) else {
      throw HybridImagePreparationError.invalidHostOnlyCanvasSize
    }
    let contentWidth: Int
    let contentHeight: Int
    if decodedRGBA.width >= decodedRGBA.height {
      contentWidth = hostOnlyCanvasSize
      contentHeight = max(1, decodedRGBA.height * hostOnlyCanvasSize / decodedRGBA.width)
    } else {
      contentHeight = hostOnlyCanvasSize
      contentWidth = max(1, decodedRGBA.width * hostOnlyCanvasSize / decodedRGBA.height)
    }
    let originX = (hostOnlyCanvasSize - contentWidth) / 2
    let originY = (hostOnlyCanvasSize - contentHeight) / 2
    var output = Data(count: hostOnlyCanvasSize * hostOnlyCanvasSize * 4)
    output.withUnsafeMutableBytes { raw in
      guard let destination = raw.bindMemory(to: UInt8.self).baseAddress else { return }
      for pixel in 0..<(hostOnlyCanvasSize * hostOnlyCanvasSize) {
        let offset = pixel * 4
        destination[offset] = paddingRGBA[0]
        destination[offset + 1] = paddingRGBA[1]
        destination[offset + 2] = paddingRGBA[2]
        destination[offset + 3] = paddingRGBA[3]
      }
      decodedRGBA.rgba.withUnsafeBytes { sourceRaw in
        guard let source = sourceRaw.bindMemory(to: UInt8.self).baseAddress else { return }
        for y in 0..<contentHeight {
          let sourceY = min(
            decodedRGBA.height - 1,
            (2 * y + 1) * decodedRGBA.height / (2 * contentHeight)
          )
          for x in 0..<contentWidth {
            let sourceX = min(
              decodedRGBA.width - 1,
              (2 * x + 1) * decodedRGBA.width / (2 * contentWidth)
            )
            let sourceOffset = (sourceY * decodedRGBA.width + sourceX) * 4
            let destinationOffset = ((originY + y) * hostOnlyCanvasSize + originX + x) * 4
            destination[destinationOffset] = source[sourceOffset]
            destination[destinationOffset + 1] = source[sourceOffset + 1]
            destination[destinationOffset + 2] = source[sourceOffset + 2]
            destination[destinationOffset + 3] = source[sourceOffset + 3]
          }
        }
      }
    }
    let provenance = HybridDerivativeProvenance(
      sourceImageBytes: heldSourceImageData.count,
      sourceImageSHA256: Qwen3HybridWireParser.sha256(heldSourceImageData),
      decodedWidth: decodedRGBA.width,
      decodedHeight: decodedRGBA.height,
      decodedRGBASHA256: Qwen3HybridWireParser.sha256(decodedRGBA.rgba),
      derivativeWidth: hostOnlyCanvasSize,
      derivativeHeight: hostOnlyCanvasSize,
      derivativeBytesPerRow: hostOnlyCanvasSize * 4,
      derivativeRGBASHA256: Qwen3HybridWireParser.sha256(output),
      contentRect: HybridContentRect(
        x: originX, y: originY, width: contentWidth, height: contentHeight
      ),
      horizontalScaleNumerator: contentWidth,
      horizontalScaleDenominator: decodedRGBA.width,
      verticalScaleNumerator: contentHeight,
      verticalScaleDenominator: decodedRGBA.height,
      paddingRGBA: paddingRGBA,
      rowOrder: "top_left",
      colorSpace: "sRGB_RGBA8_opaque_premultiplied_last_top_left",
      policy: HybridDerivativeProvenance.policy
    )
    return HybridPreparedImage(rgba: output, provenance: provenance)
  }
}

public enum HybridEvidenceStrength: String, Codable, Sendable {
  case highPositive = "high_positive"
  case highNegative = "high_negative"
  case ambiguous
}

public enum HybridPixelQuality: String, Codable, Sendable {
  case usable
  case hardPoorTooDark = "hard_poor_too_dark"
  case hardPoorOverexposed = "hard_poor_overexposed"
  case hardPoorNearBlank = "hard_poor_near_blank"
  case hardPoorLowContrast = "hard_poor_low_contrast"
  case hardPoorSevereBlur = "hard_poor_severe_blur"
}

/// Distinct pixel evidence. It deliberately has no stool-presence field and is
/// never serialized as a model or V2 semantic answer.
public struct HybridPixelEvidence: Codable, Equatable, Sendable {
  public static let schemaVersion = "gi-hybrid-pixel-evidence-v2"
  public static let thresholdVersion = "gi-hybrid-thresholds-v2"

  public let schemaVersion: String
  public let thresholdVersion: String
  public let quality: HybridPixelQuality
  public let baseColorCandidate: Qwen3HybridWireColor
  public let baseColorConfidencePPM: Int
  public let localizedRed: HybridEvidenceStrength
  public let localizedBlack: HybridEvidenceStrength
  public let tarryGlossSmear: HybridEvidenceStrength
  public let darkPixelFractionPPM: Int
  public let overexposedPixelFractionPPM: Int
  public let foregroundFractionPPM: Int
  public let foregroundComponentCount: Int
  public let largestForegroundRegionFractionPPM: Int
  public let largestForegroundSolidityPPM: Int
  public let redPixelFractionPPM: Int
  public let blackLowChromaPixelFractionPPM: Int
  public let largestRedRegionFractionPPM: Int
  public let largestBlackRegionFractionPPM: Int
  public let largestBlackRegionElongationNumerator: Int
  public let largestBlackRegionElongationDenominator: Int
  public let componentLocalGlossFractionPPM: Int
  public let strongEdgeFractionPPM: Int
  public let lumaRange: Int
  public let edgeMean: Int
}

public enum HybridPixelAnalyzer {
  private struct Region {
    var count = 0
    var minX = Int.max
    var maxX = Int.min
    var minY = Int.max
    var maxY = Int.min

    var elongationNumerator: Int {
      guard count > 0 else { return 0 }
      return max(maxX - minX + 1, maxY - minY + 1)
    }
    var elongationDenominator: Int {
      guard count > 0 else { return 1 }
      return max(1, min(maxX - minX + 1, maxY - minY + 1))
    }
    var boundingBoxArea: Int {
      guard count > 0 else { return 0 }
      return (maxX - minX + 1) * (maxY - minY + 1)
    }
  }

  public static func evaluate(_ frame: HybridRGBAFrame) -> HybridPixelEvidence {
    let pixels = frame.width * frame.height
    let bytes = [UInt8](frame.rgba)
    let border = borderReference(bytes: bytes, width: frame.width, height: frame.height)
    var foregroundMask = [Bool](repeating: false, count: pixels)
    var redMask = [Bool](repeating: false, count: pixels)
    var blackMask = [Bool](repeating: false, count: pixels)
    var glossMask = [Bool](repeating: false, count: pixels)
    var dark20 = 0
    var overexposed245 = 0
    var foregroundCount = 0
    var redCount = 0
    var blackCount = 0
    var buckets: [Qwen3HybridWireColor: Int] = [:]
    var edgeTotal = 0
    var edgeComparisons = 0
    var strongEdges = 0
    var lumaMinimum = 255
    var lumaMaximum = 0

    for index in 0..<pixels {
      let offset = index * 4
      let r = Int(bytes[offset])
      let g = Int(bytes[offset + 1])
      let b = Int(bytes[offset + 2])
      let luma = (77 * r + 150 * g + 29 * b) >> 8
      let chroma = max(r, g, b) - min(r, g, b)
      if luma < 20 { dark20 += 1 }
      if luma >= 245 { overexposed245 += 1 }
      lumaMinimum = min(lumaMinimum, luma)
      lumaMaximum = max(lumaMaximum, luma)
      let foreground = max(
        abs(r - border.r), abs(g - border.g), abs(b - border.b)
      ) >= 18
      foregroundMask[index] = foreground
      if foreground { foregroundCount += 1 }
      let red = foreground && r >= 160 && r * 2 >= g * 3 && r * 2 >= b * 3
      let black = foreground && luma <= 32 && chroma <= 14
      let gloss = foreground && luma >= 190 && chroma <= 36
      redMask[index] = red
      blackMask[index] = black
      glossMask[index] = gloss
      if red { redCount += 1 }
      if black { blackCount += 1 }
      if foreground {
        buckets[colorBucket(r: r, g: g, b: b, luma: luma, chroma: chroma), default: 0] += 1
      }

      let x = index % frame.width
      let y = index / frame.width
      if x > 0 {
        let other = offset - 4
        let differences = [
          abs(r - Int(bytes[other])), abs(g - Int(bytes[other + 1])),
          abs(b - Int(bytes[other + 2])),
        ]
        edgeTotal += differences.reduce(0, +)
        if differences.max() ?? 0 >= 48 { strongEdges += 1 }
        edgeComparisons += 3
      }
      if y > 0 {
        let other = offset - frame.width * 4
        let differences = [
          abs(r - Int(bytes[other])), abs(g - Int(bytes[other + 1])),
          abs(b - Int(bytes[other + 2])),
        ]
        edgeTotal += differences.reduce(0, +)
        if differences.max() ?? 0 >= 48 { strongEdges += 1 }
        edgeComparisons += 3
      }
    }
    let foregroundRegions = regions(
      mask: foregroundMask, width: frame.width, height: frame.height
    )
    let foregroundRegion = foregroundRegions.first ?? Region()
    let redRegion = largestRegion(mask: redMask, width: frame.width, height: frame.height)
    let blackComponent = largestComponent(
      mask: blackMask, width: frame.width, height: frame.height
    )
    let blackRegion = blackComponent.region
    let meaningfulForegroundComponents = foregroundRegions.filter {
      ppm($0.count, pixels) >= 2_000
    }
    let foregroundPPM = ppm(foregroundCount, pixels)
    let redPPM = ppm(redCount, pixels)
    let blackPPM = ppm(blackCount, pixels)
    let redRegionPPM = ppm(redRegion.count, pixels)
    let blackRegionPPM = ppm(blackRegion.count, pixels)
    let localizedRed: HybridEvidenceStrength = redRegionPPM >= 10_000
      ? .highPositive : (redPPM <= 1_000 ? .highNegative : .ambiguous)
    let localizedBlack: HybridEvidenceStrength = blackRegionPPM >= 20_000
      ? .highPositive : (blackPPM <= 1_000 ? .highNegative : .ambiguous)
    let elongatedBlack = blackRegion.count > 0
      && blackRegion.elongationNumerator >= blackRegion.elongationDenominator * 3
    let componentGlossCount = componentLocalCount(
      targetMask: glossMask,
      componentMask: blackComponent.mask,
      width: frame.width,
      height: frame.height
    )
    let componentGlossPPM = ppm(componentGlossCount, pixels)
    let tarry: HybridEvidenceStrength
    if localizedBlack == .highPositive && elongatedBlack && componentGlossPPM >= 2_000 {
      tarry = .highPositive
    } else if localizedBlack == .highNegative
      || (localizedBlack == .highPositive && (!elongatedBlack || componentGlossPPM <= 500))
    {
      tarry = .highNegative
    } else {
      tarry = .ambiguous
    }
    let rankedBuckets = buckets.sorted { lhs, rhs in
      if lhs.value != rhs.value { return lhs.value > rhs.value }
      return lhs.key.rawValue < rhs.key.rawValue
    }
    let firstBucket = rankedBuckets.first ?? (.notSure, 0)
    let dominant: (key: Qwen3HybridWireColor, value: Int)
    if rankedBuckets.count >= 2,
      ppm(rankedBuckets[1].value, foregroundCount) >= 300_000,
      ppm(firstBucket.value, foregroundCount) <= 650_000
    {
      dominant = (.mixed, firstBucket.value + rankedBuckets[1].value)
    } else {
      dominant = firstBucket
    }
    let edgeMean = edgeComparisons == 0 ? 0 : edgeTotal / edgeComparisons
    let strongEdgePPM = edgeComparisons == 0
      ? 0 : strongEdges * 3 * 1_000_000 / edgeComparisons
    let lumaRange = lumaMaximum - lumaMinimum
    let foregroundSolidityPPM = ppm(
      foregroundRegion.count, foregroundRegion.boundingBoxArea
    )
    let quality: HybridPixelQuality
    if ppm(dark20, pixels) >= 850_000 {
      quality = .hardPoorTooDark
    } else if ppm(overexposed245, pixels) >= 850_000 {
      quality = .hardPoorOverexposed
    } else if foregroundPPM <= 2_000 || lumaRange <= 4 {
      quality = .hardPoorNearBlank
    } else if lumaRange <= 18 {
      quality = .hardPoorLowContrast
    } else if foregroundPPM >= 20_000 && strongEdgePPM <= 1_000 {
      quality = .hardPoorSevereBlur
    } else {
      quality = .usable
    }
    return HybridPixelEvidence(
      schemaVersion: HybridPixelEvidence.schemaVersion,
      thresholdVersion: HybridPixelEvidence.thresholdVersion,
      quality: quality,
      baseColorCandidate: quality == .usable ? dominant.0 : .notSure,
      baseColorConfidencePPM: quality == .usable ? ppm(dominant.1, foregroundCount) : 0,
      localizedRed: quality == .usable ? localizedRed : .ambiguous,
      localizedBlack: quality == .usable ? localizedBlack : .ambiguous,
      tarryGlossSmear: quality == .usable ? tarry : .ambiguous,
      darkPixelFractionPPM: ppm(dark20, pixels),
      overexposedPixelFractionPPM: ppm(overexposed245, pixels),
      foregroundFractionPPM: foregroundPPM,
      foregroundComponentCount: meaningfulForegroundComponents.count,
      largestForegroundRegionFractionPPM: ppm(foregroundRegion.count, pixels),
      largestForegroundSolidityPPM: foregroundSolidityPPM,
      redPixelFractionPPM: redPPM,
      blackLowChromaPixelFractionPPM: blackPPM,
      largestRedRegionFractionPPM: redRegionPPM,
      largestBlackRegionFractionPPM: blackRegionPPM,
      largestBlackRegionElongationNumerator: blackRegion.elongationNumerator,
      largestBlackRegionElongationDenominator: blackRegion.elongationDenominator,
      componentLocalGlossFractionPPM: componentGlossPPM,
      strongEdgeFractionPPM: strongEdgePPM,
      lumaRange: lumaRange,
      edgeMean: edgeMean
    )
  }

  private static func borderReference(
    bytes: [UInt8], width: Int, height: Int
  ) -> (r: Int, g: Int, b: Int) {
    var red = 0
    var green = 0
    var blue = 0
    var count = 0
    for y in 0..<height {
      for x in 0..<width where y == 0 || y + 1 == height || x == 0 || x + 1 == width {
        let offset = (y * width + x) * 4
        red += Int(bytes[offset])
        green += Int(bytes[offset + 1])
        blue += Int(bytes[offset + 2])
        count += 1
      }
    }
    return (red / max(1, count), green / max(1, count), blue / max(1, count))
  }

  private static func componentLocalCount(
    targetMask: [Bool], componentMask: [Bool], width: Int, height: Int
  ) -> Int {
    var count = 0
    for index in targetMask.indices where targetMask[index] {
      let x = index % width
      let y = index / width
      var touchesComponent = false
      for neighborY in max(0, y - 1)...min(height - 1, y + 1) {
        for neighborX in max(0, x - 1)...min(width - 1, x + 1) {
          if componentMask[neighborY * width + neighborX] {
            touchesComponent = true
            break
          }
        }
        if touchesComponent { break }
      }
      if touchesComponent { count += 1 }
    }
    return count
  }

  private static func colorBucket(
    r: Int, g: Int, b: Int, luma: Int, chroma: Int
  ) -> Qwen3HybridWireColor {
    if luma <= 32 && chroma <= 14 { return .blackAppearing }
    if r >= 160 && r * 2 >= g * 3 && r * 2 >= b * 3 { return .redAppearing }
    if luma >= 190 && chroma <= 45 { return .paleOrClayAppearing }
    if g > r * 6 / 5 && g > b * 6 / 5 { return .green }
    if r >= 150 && g >= 125 && b * 2 < min(r, g) { return .yellow }
    if r >= 150 && g >= 70 && g <= 115 && b < 80 { return .orange }
    if r > g && g >= b {
      if luma < 75 { return .darkBrown }
      if luma > 155 { return .lightBrown }
      return .brown
    }
    return .mixed
  }

  private static func largestRegion(mask: [Bool], width: Int, height: Int) -> Region {
    regions(mask: mask, width: width, height: height).first ?? Region()
  }

  private static func largestComponent(
    mask: [Bool], width: Int, height: Int
  ) -> (region: Region, mask: [Bool]) {
    var visited = [Bool](repeating: false, count: mask.count)
    var best = Region()
    var bestIndices: [Int] = []
    for start in mask.indices where mask[start] && !visited[start] {
      var region = Region()
      var indices: [Int] = []
      var stack = [start]
      visited[start] = true
      while let index = stack.popLast() {
        indices.append(index)
        let x = index % width
        let y = index / width
        region.count += 1
        region.minX = min(region.minX, x)
        region.maxX = max(region.maxX, x)
        region.minY = min(region.minY, y)
        region.maxY = max(region.maxY, y)
        if x > 0 { visit(index - 1, mask: mask, visited: &visited, stack: &stack) }
        if x + 1 < width { visit(index + 1, mask: mask, visited: &visited, stack: &stack) }
        if y > 0 { visit(index - width, mask: mask, visited: &visited, stack: &stack) }
        if y + 1 < height { visit(index + width, mask: mask, visited: &visited, stack: &stack) }
      }
      if region.count > best.count {
        best = region
        bestIndices = indices
      }
    }
    var componentMask = [Bool](repeating: false, count: mask.count)
    for index in bestIndices { componentMask[index] = true }
    return (best, componentMask)
  }

  private static func regions(mask: [Bool], width: Int, height: Int) -> [Region] {
    var visited = [Bool](repeating: false, count: mask.count)
    var found: [Region] = []
    for start in mask.indices where mask[start] && !visited[start] {
      var region = Region()
      var stack = [start]
      visited[start] = true
      while let index = stack.popLast() {
        let x = index % width
        let y = index / width
        region.count += 1
        region.minX = min(region.minX, x)
        region.maxX = max(region.maxX, x)
        region.minY = min(region.minY, y)
        region.maxY = max(region.maxY, y)
        if x > 0 { visit(index - 1, mask: mask, visited: &visited, stack: &stack) }
        if x + 1 < width { visit(index + 1, mask: mask, visited: &visited, stack: &stack) }
        if y > 0 { visit(index - width, mask: mask, visited: &visited, stack: &stack) }
        if y + 1 < height { visit(index + width, mask: mask, visited: &visited, stack: &stack) }
      }
      found.append(region)
    }
    return found.sorted { lhs, rhs in
      if lhs.count != rhs.count { return lhs.count > rhs.count }
      if lhs.minY != rhs.minY { return lhs.minY < rhs.minY }
      return lhs.minX < rhs.minX
    }
  }

  private static func visit(
    _ index: Int, mask: [Bool], visited: inout [Bool], stack: inout [Int]
  ) {
    if mask[index] && !visited[index] {
      visited[index] = true
      stack.append(index)
    }
  }

  private static func ppm(_ numerator: Int, _ denominator: Int) -> Int {
    denominator == 0 ? 0 : numerator * 1_000_000 / denominator
  }
}

public enum HybridFusionOrigin: String, Codable, Sendable {
  case rawAndPixels = "raw_and_pixels"
  case deterministicHardPoor = "deterministic_hard_poor"
  case deterministicNoRawEvidence = "deterministic_no_raw_evidence"
}

public enum HybridManualFallbackReason: String, Codable, Equatable, Sendable {
  case invalidRawNoSemanticFusion = "invalid_raw_no_semantic_fusion"
  case rawUsabilityNotSureCannotMapToV2Bool = "raw_usability_not_sure_cannot_map_to_v2_bool"
}

public struct HybridFusedSuggestion: Equatable, Sendable {
  public let suggestion: PhotoSuggestionPayloadV2
  public let canonicalV2JSON: String
  public let origin: HybridFusionOrigin
}

public enum HybridFusionOutcome: Equatable, Sendable {
  case suggestion(HybridFusedSuggestion)
  case manualFallback(HybridManualFallbackReason)
}

public enum HybridFusion {
  public static let fusionVersion = "gi-qwen3-hybrid-fusion-v2"

  public static func fuse(
    raw: Qwen3HybridWirePayload?,
    pixels: HybridPixelEvidence
  ) throws -> HybridFusionOutcome {
    if pixels.quality != .usable {
      return try finish(
        PhotoSuggestionPayloadV2.technicalAbstention(
          reason: technicalReason(for: pixels.quality)
        ),
        origin: .deterministicHardPoor
      )
    }
    guard let raw else {
      // A malformed envelope does not erase independently measured image
      // quality or broad color. It still contributes no model semantics.
      let color = pixels.baseColorConfidencePPM >= 550_000
        && pixels.baseColorCandidate != .notSure
        ? pixels.baseColorCandidate.rawValue : nil
      return try finish(PhotoSuggestionPayloadV2(
        imageUsable: true, retakeReason: nil, stoolPresence: .uncertain,
        bristolType: nil, form: "unable_to_assess", mixedForm: .notSure,
        apparentColor: color, redAppearingMaterial: .notSure,
        blackAppearance: .notSure, blackTarryAppearance: .notSure
      ), origin: .deterministicNoRawEvidence)
    }
    let stoolPresence: StoolPresence
    switch raw.s {
    case .yes: stoolPresence = .stool
    case .no: stoolPresence = .nonStool
    case .notSure: stoolPresence = .uncertain
    }
    let subjectIsStool = raw.s == .yes
    // s != yes only removes model morphology. Deterministic color/warnings
    // remain independently safe and cannot be erased by a weak field.
    let morphology: (bristol: Int?, form: String, mixed: PhotoSuggestionAnswer)
    if !subjectIsStool {
      morphology = (nil, "unable_to_assess", .notSure)
    } else if raw.m == .yes {
      morphology = (nil, "mixed", .yes)
    } else {
      let form = morphologyValues(raw.f)
      morphology = (form.bristol, form.form, raw.m == .no ? .no : .notSure)
    }
    let contradictoryBlackTarry = raw.g == .yes && raw.b != .yes
    let fusedBlack = fuseAppearance(
      raw: contradictoryBlackTarry ? .notSure : raw.b,
      deterministic: pixels.localizedBlack
    )
    let candidateTarry = fuseAppearance(
      raw: contradictoryBlackTarry ? .notSure : raw.g,
      deterministic: pixels.tarryGlossSmear
    )
    let fusedTarry: PhotoSuggestionAnswer = candidateTarry == .yes
      && fusedBlack != .yes ? .notSure : candidateTarry
    let suggestion = PhotoSuggestionPayloadV2(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: stoolPresence,
      bristolType: morphology.bristol,
      form: morphology.form,
      mixedForm: morphology.mixed,
      apparentColor: fusedColor(raw: raw.c, pixels: pixels),
      redAppearingMaterial: fuseAppearance(raw: raw.r, deterministic: pixels.localizedRed),
      blackAppearance: fusedBlack,
      blackTarryAppearance: fusedTarry
    )
    return try finish(suggestion, origin: .rawAndPixels)
  }

  private static func finish(
    _ suggestion: PhotoSuggestionPayloadV2,
    origin: HybridFusionOrigin
  ) throws -> HybridFusionOutcome {
    let canonical = try PhotoSuggestionPayloadV2Parser.canonicalJSON(suggestion)
    guard try PhotoSuggestionPayloadV2Parser.parse(canonical) == suggestion else {
      throw ObservationParserError.invalidJSON
    }
    return .suggestion(HybridFusedSuggestion(
      suggestion: suggestion,
      canonicalV2JSON: canonical,
      origin: origin
    ))
  }

  private static func fuseAppearance(
    raw: Qwen3HybridTriState,
    deterministic: HybridEvidenceStrength
  ) -> PhotoSuggestionAnswer {
    if raw == .yes, deterministic == .highPositive { return .yes }
    if raw == .no, deterministic == .highNegative { return .no }
    return .notSure
  }

  private static func fusedColor(
    raw: Qwen3HybridWireColor,
    pixels: HybridPixelEvidence
  ) -> String? {
    // Color is a low-risk appearance prefill: strong deterministic evidence
    // wins; otherwise retain a valid Qwen color without requiring agreement.
    if pixels.baseColorConfidencePPM >= 550_000,
      pixels.baseColorCandidate != .notSure {
      return pixels.baseColorCandidate.rawValue
    }
    return raw == .notSure ? nil : raw.rawValue
  }

  private static func technicalReason(
    for quality: HybridPixelQuality
  ) -> PhotoRetakeReason {
    switch quality {
    case .usable: return .other
    case .hardPoorTooDark: return .tooDark
    case .hardPoorOverexposed: return .glare
    case .hardPoorNearBlank, .hardPoorLowContrast: return .other
    case .hardPoorSevereBlur: return .blurred
    }
  }

  private static func morphologyValues(
    _ form: Qwen3HybridWireForm
  ) -> (bristol: Int?, form: String, mixed: PhotoSuggestionAnswer) {
    switch form {
    case .hardLumps: return (1, "hard_lumps", .no)
    case .lumpyFormed: return (2, "lumpy_formed", .no)
    case .crackedFormed: return (3, "cracked_formed", .no)
    case .smoothFormed: return (4, "smooth_formed", .no)
    case .softBlobs: return (5, "soft_blobs", .no)
    case .mushy: return (6, "mushy", .no)
    case .watery: return (7, "watery", .no)
    case .notSure: return (nil, "unable_to_assess", .notSure)
    }
  }
}

// MARK: - Qwen3 decomposed field contract

public enum Qwen3DecomposedContract {
  public static let legacyParserVersion = "qwen3-decomposed-label-parser-v1"
  public static let parserVersion = "qwen3-decomposed-label-parser-v2"
  public static let supportedParserVersions: Set<String> = [
    legacyParserVersion,
    parserVersion,
  ]
  public static let promptSetVersion = "qwen3-decomposed-prompt-set-v1"
  public static let qualificationPolicyVersion = "qwen3-decomposed-qualification-v1"
  public static let qualifiedFields: [Qwen3DecomposedField] = [
    .color, .red, .black, .glossy,
  ]
  public static let forcedNotSureFields: [Qwen3DecomposedField] = [
    .subject, .bristol, .mixed,
  ]

  public static var canonicalPromptSet: String {
    Qwen3DecomposedField.allCases.map { "\($0.rawValue)|\($0.prompt)" }
      .joined(separator: "\n")
  }

  public static var promptSetSHA256: String {
    sha256(Data(canonicalPromptSet.utf8))
  }

  public static func promptSHA256(for field: Qwen3DecomposedField) -> String {
    sha256(Data(field.prompt.utf8))
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

/// The seven deliberately independent Qwen3 prompts. Their answers are kept
/// as evidence even where the current qualification policy requires the
/// displayed clinical field to remain Not sure.
public enum Qwen3DecomposedField: String, CaseIterable, Codable, Hashable, Sendable {
  case subject
  case bristol
  case mixed
  case color
  case red
  case black
  case glossy

  public var prompt: String {
    switch self {
    case .subject:
      return "Does this image show stool? Answer only: stool, nonstool, or unsure."
    case .bristol:
      return "Choose the closest Bristol type. Answer only: 1, 2, 3, 4, 5, 6, 7, or unsure."
    case .mixed:
      return "Does it visibly contain more than one stool form? Answer only: yes, no, or unsure."
    case .color:
      return "Choose the main visible stool color. Answer only: brown, yellow, green, red, black, other, or unsure."
    case .red:
      return "Is red material visibly present? Answer only: yes, no, or unsure."
    case .black:
      return "Is unusually black material visibly present? Answer only: yes, no, or unsure."
    case .glossy:
      return "Is there a visibly black glossy or smeared tar-like appearance? Answer only: yes, no, or unsure."
    }
  }

  public var allowedLabels: [String] {
    switch self {
    case .subject: return ["stool", "nonstool", "unsure"]
    case .bristol: return ["1", "2", "3", "4", "5", "6", "7", "unsure"]
    case .mixed, .red, .black, .glossy: return ["yes", "no", "unsure"]
    case .color: return ["brown", "yellow", "green", "red", "black", "other", "unsure"]
    }
  }
}

public enum Qwen3DecomposedParseDisposition: String, Codable, Equatable, Sendable {
  case accepted
  /// A token of length >= 5 that is a strict prefix of exactly one allowed
  /// label for the field (parser v2). Kept distinct from `.accepted` so
  /// evidence stays honest about derivation: the wire text did not spell the
  /// label out, it was unambiguously completed to it.
  case acceptedPrefix = "accepted_prefix"
  case invalid
}

/// `unsure` with `.accepted` (or `.acceptedPrefix`) is a valid explicit
/// abstention. `unsure` with `.invalid` records malformed, missing, or
/// ambiguous wire text without silently repairing it into a semantic answer.
public struct Qwen3DecomposedParsedLabel: Codable, Equatable, Sendable {
  public let field: Qwen3DecomposedField
  public let label: String
  public let disposition: Qwen3DecomposedParseDisposition

  public init(
    field: Qwen3DecomposedField,
    label: String,
    disposition: Qwen3DecomposedParseDisposition
  ) {
    self.field = field
    self.label = label
    self.disposition = disposition
  }

  public var isUsableQualifiedLabel: Bool {
    (disposition == .accepted || disposition == .acceptedPrefix) && label != "unsure"
  }
}

/// Parser v2: exact-match wins first (as in v1); when a token matches no
/// allowed label exactly, an unambiguous-prefix pass then checks whether the
/// token (length >= 5) is a strict prefix of exactly one allowed label for
/// the field. That single label is accepted with `.acceptedPrefix`.
///
/// Ambiguity analysis (current label sets, min length 5): for every field,
/// enumerate the length->=5 strict prefixes of every allowed label and
/// confirm none collides with another label's prefix or full text.
///   - subject   ["stool", "nonstool", "unsure"]: "stool" (len 5) has no
///     length>=5 *strict* prefix of itself. "nonstool" (len 8) yields
///     "nonst"/"nonsto"/"nonstoo" -- each a prefix of "nonstool" only.
///     "unsure" (len 6) yields "unsur" -- a prefix of "unsure" only.
///   - bristol   ["1".."7", "unsure"]: the digits are length 1, too short to
///     ever produce a length>=5 prefix. Only "unsure" -> "unsur" applies.
///   - mixed/red/black/glossy ["yes", "no", "unsure"]: "yes"/"no" are too
///     short. Only "unsure" -> "unsur" applies.
///   - color     ["brown", "yellow", "green", "red", "black", "other",
///     "unsure"]: "brown"/"green"/"black"/"other" are length 5 with no
///     strict length>=5 prefix. "yellow" (len 6) yields "yello" -- a prefix
///     of "yellow" only. "unsure" yields "unsur" -- a prefix of "unsure"
///     only.
/// No field has two labels sharing a length>=5 prefix, so this rule cannot
/// introduce ambiguity against the label sets as they stand today. Adding a
/// new, short-but-similar label to any field later must redo this check.
public enum Qwen3DecomposedLabelParser {
  public static func parse(
    _ rawText: String?,
    for field: Qwen3DecomposedField
  ) -> Qwen3DecomposedParsedLabel {
    parse(rawText, for: field, replaying: Qwen3DecomposedContract.parserVersion)
  }

  /// Replays the exact parser named by an immutable receipt. New inference
  /// always uses the current parser; V1 replay deliberately omits the V2
  /// unambiguous-prefix rule.
  public static func parse(
    _ rawText: String?,
    for field: Qwen3DecomposedField,
    replaying version: String
  ) -> Qwen3DecomposedParsedLabel {
    guard Qwen3DecomposedContract.supportedParserVersions.contains(version)
    else { return invalid(field) }
    guard let rawText else { return invalid(field) }
    guard let unfenced = unwrapOneMarkdownFence(rawText) else { return invalid(field) }
    let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
    for rawToken in unfenced.split(whereSeparator: { $0.isWhitespace }) {
      let token = String(rawToken)
        .trimmingCharacters(in: punctuation)
        .lowercased()
      guard !token.isEmpty else { continue }
      if field.allowedLabels.contains(token) {
        return Qwen3DecomposedParsedLabel(
          field: field,
          label: token,
          disposition: .accepted
        )
      }
      if version == Qwen3DecomposedContract.parserVersion,
        let prefixLabel = unambiguousPrefixMatch(token, in: field.allowedLabels)
      {
        return Qwen3DecomposedParsedLabel(
          field: field,
          label: prefixLabel,
          disposition: .acceptedPrefix
        )
      }
    }
    return invalid(field)
  }

  /// `token` must be length >= 5 and a strict prefix of exactly one label in
  /// `allowedLabels` (i.e. that label is strictly longer than `token` and
  /// starts with it). Returns that label, or nil if the token is too short,
  /// matches no label, or matches more than one.
  private static func unambiguousPrefixMatch(
    _ token: String,
    in allowedLabels: [String]
  ) -> String? {
    guard token.count >= 5 else { return nil }
    let matches = allowedLabels.filter { $0.count > token.count && $0.hasPrefix(token) }
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  private static func invalid(_ field: Qwen3DecomposedField) -> Qwen3DecomposedParsedLabel {
    Qwen3DecomposedParsedLabel(field: field, label: "unsure", disposition: .invalid)
  }

  /// A response may be wrapped by one conventional Markdown fence. Nested,
  /// repeated, unclosed, or trailing-fence forms fail closed rather than being
  /// treated as a prompt- or response-repair opportunity.
  private static func unwrapOneMarkdownFence(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```") else { return trimmed }
    let lines = trimmed.components(separatedBy: .newlines)
    guard lines.count >= 2,
      lines[0].trimmingCharacters(in: .whitespaces).hasPrefix("```")
    else { return nil }
    guard let closingIndex = lines.indices.last(where: {
      lines[$0].trimmingCharacters(in: .whitespaces) == "```"
    }), closingIndex == lines.indices.last
    else { return nil }
    guard closingIndex > 0,
      !lines[1..<closingIndex].contains(where: {
        $0.trimmingCharacters(in: .whitespaces).contains("```")
      })
    else { return nil }
    return lines[1..<closingIndex].joined(separator: "\n")
  }
}

/// Persistable, per-generation evidence. The cache ID is deliberately an
/// opaque caller value: every field must carry a distinct ID and explicitly
/// attest that it began from a fresh nil generation cache.
public struct Qwen3DecomposedRawFieldRecord: Codable, Equatable, Sendable {
  public let field: Qwen3DecomposedField
  public let prompt: String
  public let promptSHA256: String?
  public let analyzedImageSHA256: String
  public let preparedTensorSHA256: String
  public let rawTokenIDs: [Int]
  public let rawText: String?
  public let rawUTF8Base64: String?
  public let rawUTF8SHA256: String?
  public let parsed: Qwen3DecomposedParsedLabel
  public let qualified: Bool
  public let generationCacheID: String
  public let usedFreshGenerationCache: Bool
  public let stopReason: String
  public let latencyMilliseconds: Int
  /// Optional at the generic value-contract layer so historical/source-only
  /// fixtures remain readable. A persisted decomposed receipt admits a field
  /// only when all four counters are present and nonnegative.
  public let mlxActiveMemoryBytes: Int?
  public let mlxCacheMemoryBytes: Int?
  public let mlxPeakMemoryBytes: Int?
  public let hostPeakRSSBytes: Int?
  public let modelCallOrdinal: Int

  public init(
    field: Qwen3DecomposedField,
    prompt: String,
    promptSHA256: String? = nil,
    analyzedImageSHA256: String,
    preparedTensorSHA256: String,
    rawTokenIDs: [Int],
    rawText: String? = nil,
    rawUTF8Base64: String? = nil,
    rawUTF8SHA256: String? = nil,
    parsed: Qwen3DecomposedParsedLabel,
    qualified: Bool,
    generationCacheID: String,
    usedFreshGenerationCache: Bool,
    stopReason: String,
    latencyMilliseconds: Int,
    mlxActiveMemoryBytes: Int? = nil,
    mlxCacheMemoryBytes: Int? = nil,
    mlxPeakMemoryBytes: Int? = nil,
    hostPeakRSSBytes: Int? = nil,
    modelCallOrdinal: Int
  ) {
    self.field = field
    self.prompt = prompt
    self.promptSHA256 = promptSHA256
    self.analyzedImageSHA256 = analyzedImageSHA256
    self.preparedTensorSHA256 = preparedTensorSHA256
    self.rawTokenIDs = rawTokenIDs
    self.rawText = rawText
    self.rawUTF8Base64 = rawUTF8Base64
    self.rawUTF8SHA256 = rawUTF8SHA256
    self.parsed = parsed
    self.qualified = qualified
    self.generationCacheID = generationCacheID
    self.usedFreshGenerationCache = usedFreshGenerationCache
    self.stopReason = stopReason
    self.latencyMilliseconds = latencyMilliseconds
    self.mlxActiveMemoryBytes = mlxActiveMemoryBytes
    self.mlxCacheMemoryBytes = mlxCacheMemoryBytes
    self.mlxPeakMemoryBytes = mlxPeakMemoryBytes
    self.hostPeakRSSBytes = hostPeakRSSBytes
    self.modelCallOrdinal = modelCallOrdinal
  }
}

public enum Qwen3DecomposedRunEvidenceError: Error, Equatable, Sendable {
  case wrongFieldSet
  case fieldOrder
  case wrongPrompt
  case staleOrSharedCache
  case mismatchedIdentity
  case malformedParsedLabel
}

/// The only aggregate passed into decomposed fusion. It makes one source-image
/// and prepared-tensor identity auditable across seven separate generations.
public struct Qwen3DecomposedRunEvidence: Codable, Equatable, Sendable {
  public static let schemaVersion = "qwen3-decomposed-photo-v1"

  public let schemaVersion: String
  public let analyzedImageSHA256: String
  public let preparedTensorSHA256: String
  public let pixelEvidence: HybridPixelEvidence
  public let fields: [Qwen3DecomposedRawFieldRecord]

  public init(
    schemaVersion: String = Self.schemaVersion,
    analyzedImageSHA256: String,
    preparedTensorSHA256: String,
    pixelEvidence: HybridPixelEvidence,
    fields: [Qwen3DecomposedRawFieldRecord]
  ) {
    self.schemaVersion = schemaVersion
    self.analyzedImageSHA256 = analyzedImageSHA256
    self.preparedTensorSHA256 = preparedTensorSHA256
    self.pixelEvidence = pixelEvidence
    self.fields = fields
  }

  public func validate() throws {
    guard schemaVersion == Self.schemaVersion,
      !analyzedImageSHA256.isEmpty,
      !preparedTensorSHA256.isEmpty,
      fields.count == Qwen3DecomposedField.allCases.count,
      Set(fields.map(\.field)) == Set(Qwen3DecomposedField.allCases)
    else { throw Qwen3DecomposedRunEvidenceError.wrongFieldSet }

    for (index, record) in fields.enumerated() {
      let expectedField = Qwen3DecomposedField.allCases[index]
      guard record.field == expectedField,
        record.modelCallOrdinal == index + 1
      else { throw Qwen3DecomposedRunEvidenceError.fieldOrder }
      guard record.prompt == record.field.prompt else {
        throw Qwen3DecomposedRunEvidenceError.wrongPrompt
      }
      guard record.parsed.field == record.field,
        record.parsed.disposition != .invalid || record.parsed.label == "unsure",
        // Both accepted-family dispositions (.accepted, .acceptedPrefix) must
        // resolve to a label the field actually allows; only .invalid is
        // exempt (it is pinned to "unsure" by the previous check).
        record.parsed.disposition == .invalid || record.field.allowedLabels.contains(record.parsed.label)
      else { throw Qwen3DecomposedRunEvidenceError.malformedParsedLabel }
      guard record.analyzedImageSHA256 == analyzedImageSHA256,
        record.preparedTensorSHA256 == preparedTensorSHA256
      else { throw Qwen3DecomposedRunEvidenceError.mismatchedIdentity }
      guard record.usedFreshGenerationCache,
        !record.generationCacheID.isEmpty
      else { throw Qwen3DecomposedRunEvidenceError.staleOrSharedCache }
    }
    guard Set(fields.map(\.generationCacheID)).count == fields.count else {
      throw Qwen3DecomposedRunEvidenceError.staleOrSharedCache
    }
  }

  public func record(for field: Qwen3DecomposedField) -> Qwen3DecomposedRawFieldRecord? {
    fields.first { $0.field == field }
  }
}

public struct Qwen3DecomposedFusedSuggestion: Equatable, Sendable {
  public let suggestion: PhotoSuggestionPayloadV2
  public let canonicalV2JSON: String
}

/// Conservative fusion for the decomposed Qwen3 lane. It never grants the
/// unqualified subject, Bristol, or mixed-form fields semantic authority.
public enum Qwen3DecomposedFusion {
  /// V1 admitted matching negative appearance evidence. V2 temporarily
  /// suppressed it. Both versions can exist in immutable local receipts and
  /// must remain replayable after the active V3 contract is installed.
  public static let legacyCompleteTriStateVersion =
    "gi-qwen3-decomposed-fusion-v1"
  public static let legacyPositiveOnlyVersion =
    "gi-qwen3-decomposed-fusion-v2"
  public static let fusionVersion = "gi-qwen3-decomposed-fusion-v3"
  public static let supportedReplayVersions: Set<String> = [
    legacyCompleteTriStateVersion,
    legacyPositiveOnlyVersion,
    fusionVersion,
  ]

  public static func fuse(
    _ evidence: Qwen3DecomposedRunEvidence
  ) throws -> Qwen3DecomposedFusedSuggestion {
    try fuse(evidence, replaying: fusionVersion)
  }

  /// Replays a hash-bound historical receipt under the exact fusion semantics
  /// named in that receipt. This is validation compatibility, not permission
  /// for a new run to emit an old version.
  public static func fuse(
    _ evidence: Qwen3DecomposedRunEvidence,
    replaying version: String
  ) throws -> Qwen3DecomposedFusedSuggestion {
    guard supportedReplayVersions.contains(version) else {
      throw ObservationParserError.invalidJSON
    }
    try evidence.validate()
    let pixels = evidence.pixelEvidence
    if pixels.quality != .usable {
      return try finish(PhotoSuggestionPayloadV2.technicalAbstention(
        reason: technicalReason(for: pixels.quality)
      ))
    }

    let suggestion = PhotoSuggestionPayloadV2(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .uncertain,
      bristolType: nil,
      form: "unable_to_assess",
      mixedForm: .notSure,
      apparentColor: fusedColor(evidence),
      redAppearingMaterial: fuseAppearance(
        model: usableLabel(.red, evidence),
        pixels: pixels.localizedRed,
        admitsNegative: version != legacyPositiveOnlyVersion
      ),
      blackAppearance: fuseAppearance(
        model: usableLabel(.black, evidence),
        pixels: pixels.localizedBlack,
        admitsNegative: version != legacyPositiveOnlyVersion
      ),
      blackTarryAppearance: fuseGlossy(
        evidence,
        admitsNegative: version != legacyPositiveOnlyVersion
      )
    )
    return try finish(suggestion)
  }

  private static func usableLabel(
    _ field: Qwen3DecomposedField,
    _ evidence: Qwen3DecomposedRunEvidence
  ) -> String? {
    guard let record = evidence.record(for: field),
      record.qualified,
      record.parsed.isUsableQualifiedLabel
    else { return nil }
    return record.parsed.label
  }

  private static func fusedColor(_ evidence: Qwen3DecomposedRunEvidence) -> String? {
    guard let model = usableLabel(.color, evidence),
      evidence.pixelEvidence.baseColorConfidencePPM >= 550_000,
      let pixelBroad = broadColor(for: evidence.pixelEvidence.baseColorCandidate),
      model == pixelBroad
    else { return nil }
    return evidence.pixelEvidence.baseColorCandidate.rawValue
  }

  private static func broadColor(for color: Qwen3HybridWireColor) -> String? {
    switch color {
    case .brown, .lightBrown, .darkBrown: return "brown"
    case .yellow: return "yellow"
    case .green: return "green"
    case .redAppearing: return "red"
    case .blackAppearing: return "black"
    case .orange, .paleOrClayAppearing, .mixed: return "other"
    case .notSure: return nil
    }
  }

  private static func fuseAppearance(
    model: String?,
    pixels: HybridEvidenceStrength,
    admitsNegative: Bool
  ) -> PhotoSuggestionAnswer {
    guard let model else { return .notSure }
    if model == "yes", pixels == .highPositive { return .yes }
    if admitsNegative, model == "no", pixels == .highNegative { return .no }
    return .notSure
  }

  private static func fuseGlossy(
    _ evidence: Qwen3DecomposedRunEvidence,
    admitsNegative: Bool
  ) -> PhotoSuggestionAnswer {
    let pixels = evidence.pixelEvidence
    let black = usableLabel(.black, evidence)
    let glossy = usableLabel(.glossy, evidence)
    if black == "yes", glossy == "yes",
      pixels.localizedBlack == .highPositive,
      pixels.tarryGlossSmear == .highPositive
    { return .yes }
    if admitsNegative, black == "no", glossy == "no",
      pixels.localizedBlack == .highNegative,
      pixels.tarryGlossSmear == .highNegative
    { return .no }
    return .notSure
  }

  private static func technicalReason(
    for quality: HybridPixelQuality
  ) -> PhotoRetakeReason {
    switch quality {
    case .usable: return .other
    case .hardPoorTooDark: return .tooDark
    case .hardPoorOverexposed: return .glare
    case .hardPoorNearBlank, .hardPoorLowContrast: return .other
    case .hardPoorSevereBlur: return .blurred
    }
  }

  private static func finish(
    _ suggestion: PhotoSuggestionPayloadV2
  ) throws -> Qwen3DecomposedFusedSuggestion {
    let canonical = try PhotoSuggestionPayloadV2Parser.canonicalJSON(suggestion)
    guard try PhotoSuggestionPayloadV2Parser.parse(canonical) == suggestion else {
      throw ObservationParserError.invalidJSON
    }
    return Qwen3DecomposedFusedSuggestion(
      suggestion: suggestion,
      canonicalV2JSON: canonical
    )
  }
}
