import CoreGraphics
import CryptoKit
import Foundation
import GITimelineCore
import ImageIO
import UniformTypeIdentifiers

private enum ToolError: LocalizedError {
  case usage
  case invalidImage
  case writeFailed(String)

  var errorDescription: String? {
    switch self {
    case .usage:
      return "usage: Qwen3HostEvidenceFuse preflight --canvas-size <512|768|1024> | prepare --input <image> --output-dir <dir> [--canvas-size <512|768|1024>] | fuse --input <json> --output <json> | parse-subset --input <json> --output <json>"
    case .invalidImage:
      return "could not decode the first image frame as a CoreGraphics image"
    case .writeFailed(let path):
      return "could not write \(path)"
    }
  }
}

private func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func canonicalSRGBRGBA(_ image: CGImage) throws -> HybridRGBAFrame {
  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  var rgba = Data(count: image.width * image.height * 4)
  let rendered = rgba.withUnsafeMutableBytes { raw -> Bool in
    guard let context = CGContext(
      data: raw.baseAddress,
      width: image.width,
      height: image.height,
      bitsPerComponent: 8,
      bytesPerRow: image.width * 4,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }
    context.interpolationQuality = .none
    context.translateBy(x: 0, y: CGFloat(image.height))
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return true
  }
  guard rendered else { throw ToolError.invalidImage }
  return try HybridRGBAFrame(width: image.width, height: image.height, rgba: rgba)
}

private func writePNG(frame: HybridRGBAFrame, to url: URL) throws {
  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
  guard let provider = CGDataProvider(data: frame.rgba as CFData),
    let image = CGImage(
      width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: frame.width * 4, space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent
    ),
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil
    )
  else { throw ToolError.writeFailed(url.path) }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { throw ToolError.writeFailed(url.path) }
}

private struct Prompt: Codable {
  let field: String
  let prompt: String
  let promptSHA256: String
}

/// Host preparation can prove the exact source and derivative bytes plus the
/// processor shape requested by a profile. Actual tensor identity, actual
/// processor frame, latency, memory, and thermal state intentionally remain
/// runtime-only evidence and are not fabricated here.
private struct HostPreprocessingEvidence: Codable {
  let requestedProfile: String
  let effectiveProfile: String
  let preprocessingVersion: String
  let sourcePixelWidth: Int
  let sourcePixelHeight: Int
  let effectiveSourcePixelWidth: Int
  let effectiveSourcePixelHeight: Int
  let derivativePixelWidth: Int
  let derivativePixelHeight: Int
  let derivativeContentPixelWidth: Int
  let derivativeContentPixelHeight: Int
  // Optional so v2 host artifacts produced before deterministic-derivative
  // provenance was added remain decodable for replay.
  let deterministicDerivativePixelWidth: Int?
  let deterministicDerivativePixelHeight: Int?
  let deterministicDerivativeRGBASHA256: String?
  let sourceWasUpscaled: Bool
  let pixelBudget: Int
  let expectedFrameT: Int
  let expectedFrameH: Int
  let expectedFrameW: Int
  let postMergeVisualTokenCount: Int
  let sourceImageSHA256: String
  let derivativeRGBASHA256: String
}

private struct PreparationArtifact: Codable {
  let schemaVersion: String
  let route: String
  let qualification: String
  let preprocessingVersion: String
  let sourceImageSHA256: String
  let sourceImageBytes: Int
  let decodedWidth: Int
  let decodedHeight: Int
  let derivative: HybridDerivativeProvenance
  let derivativePNGPath: String
  let derivativePNGSHA256: String
  let pixelEvidence: HybridPixelEvidence
  let prompts: [Prompt]
  // Optional preserves replay decoding for v1 preparation artifacts.
  let preprocessingEvidence: HostPreprocessingEvidence?
}

private struct FieldInput: Codable {
  let field: String
  let rawText: String?
  let rawTokenIDs: [Int]
  let latencyMilliseconds: Int
  let stopReason: String
}

private struct FusionInput: Codable {
  let preparation: PreparationArtifact
  let fields: [FieldInput]
}

private struct SubsetParserInput: Codable {
  let fields: [SubsetParserField]
}

private struct SubsetParserField: Codable {
  let field: String
  let rawText: String?
}

private struct SubsetParserRecord: Codable {
  let field: String
  let invoked: Bool
  let parsed: Qwen3DecomposedParsedLabel
}

private struct SubsetParserArtifact: Codable {
  let schemaVersion: String
  let route: String
  let qualification: String
  let parserVersion: String
  let promptSetVersion: String
  let promptSetSHA256: String
  let records: [SubsetParserRecord]
}

private struct FusionArtifact: Codable {
  let schemaVersion: String
  let route: String
  let qualification: String
  let parserVersion: String
  let fusionVersion: String
  let promptSetVersion: String
  let promptSetSHA256: String
  let runEvidence: Qwen3DecomposedRunEvidence
  let fusedCanonicalJSON: String
}

private func requiredValue(_ name: String, from arguments: [String]) throws -> String {
  guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
    throw ToolError.usage
  }
  return arguments[index + 1]
}

private func requestedCanvasSize(_ arguments: [String]) throws -> Int {
  let raw = try requiredValue("--canvas-size", from: arguments)
  guard let value = Int(raw), [512, 768, 1024].contains(value) else { throw ToolError.usage }
  return value
}

private func optionalCanvasSize(_ arguments: [String]) throws -> Int {
  guard arguments.contains("--canvas-size") else { return 512 }
  return try requestedCanvasSize(arguments)
}

private struct HostProfile {
  let canvasSize: Int
  let preprocessingVersion: String
  let qualification: String
  let pixelBudget: Int
  let expectedPatchEdge: Int
  let postMergeVisualTokenCount: Int
  let derivativeFilename: String
}

private func hostProfile(canvasSize: Int) throws -> HostProfile {
  switch canvasSize {
  case 512:
    return HostProfile(
      canvasSize: 512,
      preprocessingVersion: "qwen3vl-hybrid-512-v2-preprocessing-evidence",
      qualification: "NOT_DEVICE_QUALIFIED; app-derived shared Swift 512 preprocessing only",
      pixelBudget: 512 * 512,
      expectedPatchEdge: 32,
      postMergeVisualTokenCount: 256,
      derivativeFilename: "app-derived-512.png"
    )
  case 768:
    return HostProfile(
      canvasSize: 768,
      preprocessingVersion: "host-only-qwen3vl-hybrid-768-v1",
      qualification: "HOST_ONLY_768_PREPARATION_NOT_APP_OR_DEVICE_EQUIVALENT",
      pixelBudget: 768 * 768,
      expectedPatchEdge: 48,
      postMergeVisualTokenCount: 576,
      derivativeFilename: "host-only-768.png"
    )
  case 1024:
    return HostProfile(
      canvasSize: 1024,
      preprocessingVersion: "qwen3vl-hybrid-1024-qa-v1",
      qualification: "NOT_DEVICE_QUALIFIED; internal-QA shared Swift 1024 preparation only",
      pixelBudget: 1024 * 1024,
      expectedPatchEdge: 64,
      postMergeVisualTokenCount: 1024,
      derivativeFilename: "internal-qa-1024.png"
    )
  default:
    throw ToolError.usage
  }
}

private func preflight(arguments: [String]) throws {
  let canvasSize = try requestedCanvasSize(arguments)
  let profile = try hostProfile(canvasSize: canvasSize)
  let payload: [String: Any] = [
    "schemaVersion": "qwen3-host-dev-ab-preflight-v2",
    "canvasSize": canvasSize,
    "requestedProfile": String(canvasSize),
    "effectiveProfile": String(canvasSize),
    "preprocessingVersion": profile.preprocessingVersion,
    "pixelBudget": profile.pixelBudget,
    "expectedFrame": ["t": 1, "h": profile.expectedPatchEdge, "w": profile.expectedPatchEdge],
    "postMergeVisualTokenCount": profile.postMergeVisualTokenCount,
    "qualification": profile.qualification,
    "supported": true,
  ]
  let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
  print(String(decoding: data, as: UTF8.self))
}

private func prepare(arguments: [String]) throws {
  let inputURL = URL(fileURLWithPath: try requiredValue("--input", from: arguments))
  let outputDirectory = URL(fileURLWithPath: try requiredValue("--output-dir", from: arguments))
  let canvasSize = try optionalCanvasSize(arguments)
  let profile = try hostProfile(canvasSize: canvasSize)
  try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
  let source = try Data(contentsOf: inputURL, options: [.mappedIfSafe])
  guard let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
    let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
  else { throw ToolError.invalidImage }
  let decoded = try canonicalSRGBRGBA(image)
  let baselinePrepared = try HybridImagePreparer.prepare(
    heldSourceImageData: source, decodedRGBA: decoded
  )
  let prepared = canvasSize == HybridImagePreparer.canvasSize
    ? baselinePrepared
    : try HybridImagePreparer.prepare(
      heldSourceImageData: source,
      decodedRGBA: decoded,
      hostOnlyCanvasSize: canvasSize
    )
  let derivativeFrame = try HybridRGBAFrame(
    width: canvasSize, height: canvasSize, rgba: prepared.rgba
  )
  let deterministicFrame = try HybridRGBAFrame(
    width: HybridImagePreparer.canvasSize,
    height: HybridImagePreparer.canvasSize,
    rgba: baselinePrepared.rgba
  )
  let pngURL = outputDirectory.appendingPathComponent(profile.derivativeFilename)
  try writePNG(frame: derivativeFrame, to: pngURL)
  let prompts = Qwen3DecomposedField.allCases.map {
    Prompt(field: $0.rawValue, prompt: $0.prompt, promptSHA256: Qwen3DecomposedContract.promptSHA256(for: $0))
  }
  let provenance = prepared.provenance
  let preprocessingEvidence = HostPreprocessingEvidence(
    requestedProfile: String(canvasSize),
    effectiveProfile: String(canvasSize),
    preprocessingVersion: profile.preprocessingVersion,
    sourcePixelWidth: provenance.decodedWidth,
    sourcePixelHeight: provenance.decodedHeight,
    effectiveSourcePixelWidth: min(provenance.decodedWidth, provenance.contentRect.width),
    effectiveSourcePixelHeight: min(provenance.decodedHeight, provenance.contentRect.height),
    derivativePixelWidth: provenance.derivativeWidth,
    derivativePixelHeight: provenance.derivativeHeight,
    derivativeContentPixelWidth: provenance.contentRect.width,
    derivativeContentPixelHeight: provenance.contentRect.height,
    deterministicDerivativePixelWidth: baselinePrepared.provenance.derivativeWidth,
    deterministicDerivativePixelHeight: baselinePrepared.provenance.derivativeHeight,
    deterministicDerivativeRGBASHA256: baselinePrepared.provenance.derivativeRGBASHA256,
    sourceWasUpscaled: provenance.contentRect.width > provenance.decodedWidth
      || provenance.contentRect.height > provenance.decodedHeight,
    pixelBudget: profile.pixelBudget,
    expectedFrameT: 1,
    expectedFrameH: profile.expectedPatchEdge,
    expectedFrameW: profile.expectedPatchEdge,
    postMergeVisualTokenCount: profile.postMergeVisualTokenCount,
    sourceImageSHA256: sha256(source),
    derivativeRGBASHA256: provenance.derivativeRGBASHA256
  )
  let artifact = PreparationArtifact(
    schemaVersion: "qwen3-host-semantic-proxy-preparation-v2",
    route: "host_python_mlx_semantic_proxy",
    qualification: profile.qualification,
    preprocessingVersion: profile.preprocessingVersion,
    sourceImageSHA256: sha256(source),
    sourceImageBytes: source.count,
    decodedWidth: image.width,
    decodedHeight: image.height,
    derivative: prepared.provenance,
    derivativePNGPath: pngURL.path,
    derivativePNGSHA256: sha256(try Data(contentsOf: pngURL)),
    pixelEvidence: HybridPixelAnalyzer.evaluate(deterministicFrame),
    prompts: prompts,
    preprocessingEvidence: preprocessingEvidence
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  print(String(decoding: try encoder.encode(artifact), as: UTF8.self))
}

private func parseSubset(arguments: [String]) throws {
  let inputURL = URL(fileURLWithPath: try requiredValue("--input", from: arguments))
  let outputURL = URL(fileURLWithPath: try requiredValue("--output", from: arguments))
  let decoded = try JSONDecoder().decode(SubsetParserInput.self, from: Data(contentsOf: inputURL))
  guard !decoded.fields.isEmpty else { throw ToolError.usage }
  var inputByField: [Qwen3DecomposedField: SubsetParserField] = [:]
  for record in decoded.fields {
    guard let field = Qwen3DecomposedField(rawValue: record.field), inputByField[field] == nil else {
      throw ToolError.usage
    }
    inputByField[field] = record
  }
  let records = Qwen3DecomposedField.allCases.map { field in
    let input = inputByField[field]
    return SubsetParserRecord(
      field: field.rawValue,
      invoked: input != nil,
      parsed: Qwen3DecomposedLabelParser.parse(input?.rawText, for: field)
    )
  }
  let artifact = SubsetParserArtifact(
    schemaVersion: "qwen3-host-dev-ab-shared-parser-subset-v1",
    route: "host_python_mlx_dev_ab",
    qualification: "NOT_DEVICE_QUALIFIED; shared Swift parser receipt, not app/device qualification",
    parserVersion: Qwen3DecomposedContract.parserVersion,
    promptSetVersion: Qwen3DecomposedContract.promptSetVersion,
    promptSetSHA256: Qwen3DecomposedContract.promptSetSHA256,
    records: records
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(artifact).write(to: outputURL, options: .atomic)
}

private func fuse(arguments: [String]) throws {
  let inputURL = URL(fileURLWithPath: try requiredValue("--input", from: arguments))
  let outputURL = URL(fileURLWithPath: try requiredValue("--output", from: arguments))
  let decoded = try JSONDecoder().decode(FusionInput.self, from: Data(contentsOf: inputURL))
  let byField = Dictionary(uniqueKeysWithValues: decoded.fields.map { ($0.field, $0) })
  guard byField.count == Qwen3DecomposedField.allCases.count else { throw ToolError.usage }
  let evidenceFields = try Qwen3DecomposedField.allCases.enumerated().map { index, field in
    guard let input = byField[field.rawValue] else { throw ToolError.usage }
    let rawData = input.rawText.map { Data($0.utf8) }
    return Qwen3DecomposedRawFieldRecord(
      field: field,
      prompt: field.prompt,
      promptSHA256: Qwen3DecomposedContract.promptSHA256(for: field),
      analyzedImageSHA256: decoded.preparation.sourceImageSHA256,
      preparedTensorSHA256: decoded.preparation.derivative.derivativeRGBASHA256,
      rawTokenIDs: input.rawTokenIDs,
      rawText: input.rawText,
      rawUTF8Base64: rawData?.base64EncodedString(),
      rawUTF8SHA256: rawData.map(sha256),
      parsed: Qwen3DecomposedLabelParser.parse(input.rawText, for: field),
      // Host MLX Python is not the app's Swift MLX runtime. Keep this false so
      // exact app fusion cannot admit proxy model labels as clinical prefill.
      qualified: false,
      generationCacheID: "host-proxy-fresh-cache-\(index + 1)",
      usedFreshGenerationCache: true,
      stopReason: input.stopReason,
      latencyMilliseconds: input.latencyMilliseconds,
      modelCallOrdinal: index + 1
    )
  }
  let evidence = Qwen3DecomposedRunEvidence(
    analyzedImageSHA256: decoded.preparation.sourceImageSHA256,
    preparedTensorSHA256: decoded.preparation.derivative.derivativeRGBASHA256,
    pixelEvidence: decoded.preparation.pixelEvidence,
    fields: evidenceFields
  )
  let fused = try Qwen3DecomposedFusion.fuse(evidence)
  let artifact = FusionArtifact(
    schemaVersion: "qwen3-host-semantic-proxy-evidence-v1",
    route: "host_python_mlx_semantic_proxy",
    qualification: "NOT_DEVICE_QUALIFIED; model labels forced unqualified before exact shared fusion",
    parserVersion: Qwen3DecomposedContract.parserVersion,
    fusionVersion: Qwen3DecomposedFusion.fusionVersion,
    promptSetVersion: Qwen3DecomposedContract.promptSetVersion,
    promptSetSHA256: Qwen3DecomposedContract.promptSetSHA256,
    runEvidence: evidence,
    fusedCanonicalJSON: fused.canonicalV2JSON
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(artifact).write(to: outputURL, options: .atomic)
}

do {
  let arguments = Array(CommandLine.arguments.dropFirst())
  guard let command = arguments.first else { throw ToolError.usage }
  switch command {
  case "preflight": try preflight(arguments: Array(arguments.dropFirst()))
  case "prepare": try prepare(arguments: Array(arguments.dropFirst()))
  case "fuse": try fuse(arguments: Array(arguments.dropFirst()))
  case "parse-subset": try parseSubset(arguments: Array(arguments.dropFirst()))
  default: throw ToolError.usage
  }
} catch {
  FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
  exit(2)
}
