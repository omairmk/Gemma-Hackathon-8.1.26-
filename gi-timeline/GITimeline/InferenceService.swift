@preconcurrency import LiteRTLM
import CoreGraphics
import Foundation
import GITimelineCore
import ImageIO

/// Small, bounded measurements made from the already-sanitized draft image.
/// No pixels, thumbnail, file path, or opaque embedding are sent to Gemma.
struct LocalPixelFacts: Codable, Equatable, Sendable {
  let schemaVersion: String
  let pixelWidth: Int
  let pixelHeight: Int
  let meanLuminance: Double
  let luminanceContrast: Double
  let darkPixelFraction: Double
  let highlightPixelFraction: Double
  let chromaticPixelFraction: Double
  let brownShareOfChromaticPixels: Double
  let greenShareOfChromaticPixels: Double
  let dominantColorHint: String
  let apparentColorHint: String
  let coarseShapeGrid: [String]
  let targetRegionCoverage: Double
  let targetConnectedRegions: Int
  let targetElongation: Double
  let shapeHint: String
  let bristolTypeHint: Int?
  let formHint: String
  let shapeSuggestionConfidence: String
  let qualityHint: String

  var canonicalJSON: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
  }
}

enum LocalPixelFeatureExtractor {
  static func extract(from url: URL) throws -> LocalPixelFacts {
    try Task.checkCancellation()
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { throw GITimelineError.invalidImage }

    let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    guard pixelWidth > 0, pixelHeight > 0 else { throw GITimelineError.invalidImage }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 96,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw GITimelineError.invalidImage
    }

    let width = thumbnail.width
    let height = thumbnail.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard let baseAddress = buffer.baseAddress,
        let context = CGContext(
          data: baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { return false }
      context.interpolationQuality = .medium
      context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drewImage else { throw GITimelineError.invalidImage }
    try Task.checkCancellation()

    var luminanceSum = 0.0
    var luminanceSquaredSum = 0.0
    var darkCount = 0
    var highlightCount = 0
    var chromaticCount = 0
    var brownCount = 0
    var greenCount = 0
    var yellowOrangeCount = 0
    var redCount = 0
    var blueCount = 0

    for index in stride(from: 0, to: pixels.count, by: 4) {
      let red = Double(pixels[index]) / 255
      let green = Double(pixels[index + 1]) / 255
      let blue = Double(pixels[index + 2]) / 255
      let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
      luminanceSum += luminance
      luminanceSquaredSum += luminance * luminance
      if luminance < 0.12 { darkCount += 1 }
      if luminance > 0.92 { highlightCount += 1 }

      let maximum = max(red, green, blue)
      let minimum = min(red, green, blue)
      let delta = maximum - minimum
      let saturation = maximum == 0 ? 0 : delta / maximum
      guard saturation >= 0.18, luminance >= 0.07, luminance <= 0.96 else { continue }
      chromaticCount += 1

      let hue: Double
      if delta == 0 {
        hue = 0
      } else if maximum == red {
        hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
      } else if maximum == green {
        hue = 60 * (((blue - red) / delta) + 2)
      } else {
        hue = 60 * (((red - green) / delta) + 4)
      }
      let normalizedHue = hue < 0 ? hue + 360 : hue
      switch normalizedHue {
      case 10..<45: brownCount += 1
      case 45..<75: yellowOrangeCount += 1
      case 75..<170: greenCount += 1
      case 170..<265: blueCount += 1
      case 345...360, 0..<10: redCount += 1
      default: break
      }
    }

    let sampleCount = max(1, width * height)
    let mean = luminanceSum / Double(sampleCount)
    let variance = max(0, luminanceSquaredSum / Double(sampleCount) - mean * mean)
    let chromaticDenominator = Double(max(1, chromaticCount))
    let chromaticFraction = Double(chromaticCount) / Double(sampleCount)
    let brownShare = Double(brownCount) / chromaticDenominator
    let greenShare = Double(greenCount) / chromaticDenominator
    let yellowOrangeShare = Double(yellowOrangeCount) / chromaticDenominator
    let redShare = Double(redCount) / chromaticDenominator
    let blueShare = Double(blueCount) / chromaticDenominator

    let dominantColorHint: String
    let apparentColorHint: String
    if chromaticFraction >= 0.08, brownShare >= 0.52, brownShare > greenShare + 0.15 {
      dominantColorHint = "brown"
      apparentColorHint = "brown"
    } else if chromaticFraction >= 0.08, greenShare >= 0.52, greenShare > brownShare + 0.15 {
      dominantColorHint = "green"
      apparentColorHint = "green"
    } else {
      dominantColorHint = "other"
      if redShare >= 0.60 { apparentColorHint = "red_appearing" }
      else if yellowOrangeShare >= 0.60 { apparentColorHint = "yellow" }
      else if blueShare >= 0.45 { apparentColorHint = "unable_to_assess" }
      else { apparentColorHint = "unable_to_assess" }
    }

    let darkFraction = Double(darkCount) / Double(sampleCount)
    let highlightFraction = Double(highlightCount) / Double(sampleCount)
    let contrast = sqrt(variance)
    let qualityHint: String
    if mean < 0.10 || darkFraction > 0.82 { qualityHint = "too_dark" }
    else if contrast < 0.025 { qualityHint = "other" }
    else { qualityHint = "none" }

    // Build a deliberately tiny color-symbol map. This is not a neural image
    // embedding: it is a bounded 12x12 description that lets Gemma organize a
    // low-confidence shape suggestion while the broken vision graph is skipped.
    let gridSide = 12
    func gridToken(red: Double, green: Double, blue: Double) -> Character {
      let maximum = max(red, green, blue)
      let minimum = min(red, green, blue)
      let delta = maximum - minimum
      let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
      let saturation = maximum == 0 ? 0 : delta / maximum
      if luminance > 0.86, saturation < 0.16 { return "." }
      if luminance < 0.10 { return "D" }
      guard saturation >= 0.18 else { return "N" }
      let hue: Double
      if delta == 0 { hue = 0 }
      else if maximum == red { hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6)) }
      else if maximum == green { hue = 60 * (((blue - red) / delta) + 2) }
      else { hue = 60 * (((red - green) / delta) + 4) }
      let normalizedHue = hue < 0 ? hue + 360 : hue
      switch normalizedHue {
      case 10..<45: return "B"
      case 45..<75: return "Y"
      case 75..<170: return "G"
      case 170..<265: return "O"
      case 345...360, 0..<10: return "R"
      default: return "O"
      }
    }

    var grid = [Character]()
    grid.reserveCapacity(gridSide * gridSide)
    for gridY in 0..<gridSide {
      for gridX in 0..<gridSide {
        let startX = gridX * width / gridSide
        let endX = max(startX + 1, (gridX + 1) * width / gridSide)
        let startY = gridY * height / gridSide
        let endY = max(startY + 1, (gridY + 1) * height / gridSide)
        var redSum = 0.0
        var greenSum = 0.0
        var blueSum = 0.0
        var count = 0
        for y in startY..<min(height, endY) {
          for x in startX..<min(width, endX) {
            let index = (y * width + x) * 4
            redSum += Double(pixels[index]) / 255
            greenSum += Double(pixels[index + 1]) / 255
            blueSum += Double(pixels[index + 2]) / 255
            count += 1
          }
        }
        let denominator = Double(max(1, count))
        grid.append(gridToken(red: redSum / denominator, green: greenSum / denominator, blue: blueSum / denominator))
      }
    }
    let coarseShapeGrid = (0..<gridSide).map { row in
      String(grid[(row * gridSide)..<((row + 1) * gridSide)])
    }

    let targetToken: Character? = dominantColorHint == "brown" ? "B" : (dominantColorHint == "green" ? "G" : nil)
    var targetMask = [Bool](repeating: false, count: grid.count)
    if let targetToken {
      for index in grid.indices { targetMask[index] = grid[index] == targetToken }
    }
    let targetCount = targetMask.filter { $0 }.count
    var connectedRegions = 0
    var visited = [Bool](repeating: false, count: targetMask.count)
    for start in targetMask.indices where targetMask[start] && !visited[start] {
      connectedRegions += 1
      var queue = [start]
      visited[start] = true
      var cursor = 0
      while cursor < queue.count {
        let current = queue[cursor]
        cursor += 1
        let x = current % gridSide
        let y = current / gridSide
        let neighbors = [
          x > 0 ? current - 1 : -1,
          x + 1 < gridSide ? current + 1 : -1,
          y > 0 ? current - gridSide : -1,
          y + 1 < gridSide ? current + gridSide : -1,
        ]
        for neighbor in neighbors where neighbor >= 0 && targetMask[neighbor] && !visited[neighbor] {
          visited[neighbor] = true
          queue.append(neighbor)
        }
      }
    }

    let targetIndices = targetMask.indices.filter { targetMask[$0] }
    let targetCoverage = Double(targetCount) / Double(grid.count)
    let elongation: Double
    if let minX = targetIndices.map({ $0 % gridSide }).min(),
      let maxX = targetIndices.map({ $0 % gridSide }).max(),
      let minY = targetIndices.map({ $0 / gridSide }).min(),
      let maxY = targetIndices.map({ $0 / gridSide }).max()
    {
      let boxWidth = Double(maxX - minX + 1)
      let boxHeight = Double(maxY - minY + 1)
      elongation = max(boxWidth / boxHeight, boxHeight / boxWidth)
    } else {
      elongation = 0
    }

    let shapeHint: String
    let bristolTypeHint: Int?
    let formHint: String
    if qualityHint != "none" || targetCount < 4 {
      shapeHint = "unable_to_assess"
      bristolTypeHint = nil
      formHint = "unable_to_assess"
    } else if connectedRegions >= 4 {
      shapeHint = "several_separate_regions"
      bristolTypeHint = 5
      formHint = "soft_blobs"
    } else if elongation >= 1.45 {
      shapeHint = "single_elongated_region"
      bristolTypeHint = 4
      formHint = "smooth_formed"
    } else if targetCoverage >= 0.38 {
      shapeHint = "broad_diffuse_region"
      bristolTypeHint = 6
      formHint = "mushy"
    } else {
      shapeHint = "compact_or_irregular_region"
      bristolTypeHint = 5
      formHint = "soft_blobs"
    }

    func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }
    return LocalPixelFacts(
      schemaVersion: "local-pixel-facts-v1",
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      meanLuminance: rounded(mean),
      luminanceContrast: rounded(contrast),
      darkPixelFraction: rounded(darkFraction),
      highlightPixelFraction: rounded(highlightFraction),
      chromaticPixelFraction: rounded(chromaticFraction),
      brownShareOfChromaticPixels: rounded(brownShare),
      greenShareOfChromaticPixels: rounded(greenShare),
      dominantColorHint: dominantColorHint,
      apparentColorHint: apparentColorHint,
      coarseShapeGrid: coarseShapeGrid,
      targetRegionCoverage: rounded(targetCoverage),
      targetConnectedRegions: connectedRegions,
      targetElongation: rounded(elongation),
      shapeHint: shapeHint,
      bristolTypeHint: bristolTypeHint,
      formHint: formHint,
      shapeSuggestionConfidence: "low_hackathon_approximation",
      qualityHint: qualityHint
    )
  }
}

protocol TimelineInferenceServing: Sendable {
  func prepare() async throws -> EnginePreparationResult
  func engineState() async -> EngineProcessState
  func analyze(draftURL: URL) async throws -> String
  func repair(draftURL: URL, errors: String) async throws -> String
  func discardRepairContext(draftURL: URL) async
}

/// Lightweight product-facing facade over the app-scoped runtime registry.
/// It never owns an engine and therefore cannot create a parallel session.
struct CoordinatedInferenceService: TimelineInferenceServing {
  let runtime: ModelRuntimeCoordinator
  let descriptor: ModelDescriptor

  func prepare() async throws -> EnginePreparationResult { try await runtime.prepare(descriptor) }
  func engineState() async -> EngineProcessState { await runtime.engineState(descriptor) }
  func analyze(draftURL: URL) async throws -> String { try await runtime.analyze(descriptor, draftURL: draftURL) }
  func repair(draftURL: URL, errors: String) async throws -> String {
    try await runtime.repair(descriptor, draftURL: draftURL, errors: errors)
  }
  func discardRepairContext(draftURL: URL) async {
    await runtime.discardRepairContext(descriptor, draftURL: draftURL)
  }
}

/// Keeps image inference exclusive across the normal flow and DEBUG lab while
/// an initial structured response may still need its same-conversation repair.
/// A mismatched/stale completion cannot release a newer run.
struct ExclusiveInferenceGate: Sendable {
  private var activeToken: UUID?
  private var structuredDraftPath: String?

  var isIdle: Bool { activeToken == nil }

  mutating func beginStructured(draftPath: String) throws -> UUID {
    guard activeToken == nil else { throw GITimelineError.operationInProgress }
    let token = UUID()
    activeToken = token
    structuredDraftPath = draftPath
    return token
  }

  mutating func beginProbe() throws -> UUID {
    guard activeToken == nil else { throw GITimelineError.operationInProgress }
    let token = UUID()
    activeToken = token
    structuredDraftPath = nil
    return token
  }

  func ownsStructured(token: UUID, draftPath: String) -> Bool {
    activeToken == token && structuredDraftPath == draftPath
  }

  mutating func finish(_ token: UUID) {
    guard activeToken == token else { return }
    activeToken = nil
    structuredDraftPath = nil
  }
}

/// The only owner of a LiteRT-LM Engine and its conversations. Production
/// structured analysis and DEBUG probes both pass through this adapter.
actor LiteRTLMEngineSessionAdapter {
  private let verifiedModel: VerifiedModel
  private let cacheURL: URL
  private let configuration: InferenceConfiguration
  private var engine: Engine?
  private var initializationTask: Task<(Engine, Double), Error>?
  private var processState: EngineProcessState = .uninitialized
  private var inferenceGate = ExclusiveInferenceGate()
  private var pendingRepair: (draftPath: String, conversation: Conversation, token: UUID)?

  init(verifiedModel: VerifiedModel, cacheURL: URL, configuration: InferenceConfiguration) {
    self.verifiedModel = verifiedModel
    self.cacheURL = cacheURL
    self.configuration = configuration
    #if DEBUG || HACKATHON_EMBEDDED_GEMMA
    if configuration.id == InferenceConfiguration.physicalGPUCPUVision70.id {
      ExperimentalFlags.optIntoExperimentalAPIs()
      ExperimentalFlags.visualTokenBudget = 70
    }
    #endif
  }

  func state() -> EngineProcessState { processState }

  func canReleaseForModelChange() -> Bool {
    initializationTask == nil && processState != .initializing && inferenceGate.isIdle
  }

  func prepare() async throws -> EnginePreparationResult {
    if engine != nil, processState == .ready {
      return EnginePreparationResult(seconds: 0, reusedCurrentProcessEngine: true)
    }
    if let initializationTask {
      do {
        let (initialized, seconds) = try await initializationTask.value
        engine = initialized
        processState = .ready
        self.initializationTask = nil
        return EnginePreparationResult(seconds: seconds, reusedCurrentProcessEngine: true)
      } catch {
        self.initializationTask = nil
        let staged = StagedInferenceError(stage: .engineInitialization, underlying: error)
        processState = .failed(staged.localizedDescription)
        throw staged
      }
    }

    processState = .initializing
    let model = verifiedModel
    let config = configuration
    let cache = cacheURL
    let task = Task<(Engine, Double), Error> {
      let clock = ContinuousClock()
      let start = clock.now
      guard model.receipt.matches(model.descriptor),
        FileManager.default.fileExists(atPath: model.modelURL.path)
      else { throw GITimelineError.modelNotVerified }
      let engineBackend: Backend
      switch config.engineBackend {
      case "gpu": engineBackend = .gpu
      #if DEBUG || HACKATHON_EMBEDDED_GEMMA
      case "cpu": engineBackend = .cpu()
      #endif
      default: throw GITimelineError.operationInProgress
      }
      let visionBackend: Backend?
      switch config.visionBackend {
      case "cpu": visionBackend = .cpu()
      #if DEBUG || HACKATHON_EMBEDDED_GEMMA
      case "gpu": visionBackend = .gpu
      #endif
      case "disabled": visionBackend = nil
      default: throw GITimelineError.operationInProgress
      }
      let engineConfig = try EngineConfig(
        modelPath: model.modelURL.path,
        backend: engineBackend,
        visionBackend: visionBackend,
        maxNumTokens: config.maxNumTokens,
        cacheDir: cache.path
      )
      let initialized = Engine(engineConfig: engineConfig)
      try await initialized.initialize()
      return (initialized, start.duration(to: clock.now).secondsDouble)
    }
    initializationTask = task
    do {
      let (initialized, seconds) = try await task.value
      engine = initialized
      processState = .ready
      initializationTask = nil
      return EnginePreparationResult(seconds: seconds, reusedCurrentProcessEngine: false)
    } catch {
      initializationTask = nil
      let staged = StagedInferenceError(stage: .engineInitialization, underlying: error)
      processState = .failed(staged.localizedDescription)
      throw staged
    }
  }

  func sendStructuredImage(path: String, prompt: String) async throws -> String {
    let token: UUID
    do { token = try inferenceGate.beginStructured(draftPath: path) }
    catch { throw StagedInferenceError(stage: .generation, underlying: error) }
    do {
      let conversation = try await makeConversation()
      pendingRepair = (path, conversation, token)
      return try await sendImage(path: path, prompt: prompt, conversation: conversation)
    } catch {
      pendingRepair = nil
      inferenceGate.finish(token)
      throw error
    }
  }

  /// Text-only path for the physical-iPhone hackathon bridge. It uses a fresh
  /// conversation on the same verified Gemma engine and retains that
  /// conversation only when a schema repair may be needed.
  func sendStructuredText(path: String, prompt: String) async throws -> String {
    let token: UUID
    do { token = try inferenceGate.beginStructured(draftPath: path) }
    catch { throw StagedInferenceError(stage: .generation, underlying: error) }
    do {
      let conversation = try await makeConversation()
      pendingRepair = (path, conversation, token)
      do {
        return try await conversation.sendMessage(Message(prompt)).toString
      } catch {
        #if HACKATHON_EMBEDDED_GEMMA
        print("LOCAL_PIXEL_BRIDGE_TEXT_FAIL \(error.localizedDescription)")
        #endif
        throw StagedInferenceError(stage: .generation, underlying: error)
      }
    } catch {
      pendingRepair = nil
      inferenceGate.finish(token)
      throw error
    }
  }

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  func sendProbeImage(path: String, prompt: String) async throws -> String {
    let token: UUID
    do { token = try inferenceGate.beginProbe() }
    catch { throw StagedInferenceError(stage: .generation, underlying: error) }
    defer { inferenceGate.finish(token) }
    let conversation = try await makeConversation()
    return try await sendImage(path: path, prompt: prompt, conversation: conversation)
  }


  func sendProbeText(prompt: String) async throws -> String {
    let token: UUID
    do { token = try inferenceGate.beginProbe() }
    catch { throw StagedInferenceError(stage: .generation, underlying: error) }
    defer { inferenceGate.finish(token) }
    let conversation = try await makeConversation()
    do {
      return try await conversation.sendMessage(Message(prompt)).toString
    } catch {
      throw StagedInferenceError(stage: .generation, underlying: error)
    }
  }
  #endif

  func repair(path: String, errors: String) async throws -> String {
    guard let pendingRepair, pendingRepair.draftPath == path,
      inferenceGate.ownsStructured(token: pendingRepair.token, draftPath: path)
    else {
      throw GITimelineError.missingRepairContext
    }
    self.pendingRepair = nil
    defer { inferenceGate.finish(pendingRepair.token) }
    let prompt = "Your previous reply was not valid JSON with exactly the required keys, allowed values, and consistency rules. Errors: \(errors). Return only the corrected JSON."
    do {
      return try await pendingRepair.conversation.sendMessage(Message(prompt)).toString
    } catch {
      throw StagedInferenceError(stage: .repair, underlying: error)
    }
  }

  func discardRepairContext(path: String) {
    guard let pendingRepair, pendingRepair.draftPath == path else { return }
    self.pendingRepair = nil
    inferenceGate.finish(pendingRepair.token)
  }

  private func makeConversation() async throws -> Conversation {
    guard processState == .ready, let engine else { throw GITimelineError.modelNotVerified }
    do {
      let sampler = try SamplerConfig(
        topK: configuration.topK,
        topP: configuration.topP,
        temperature: configuration.temperature,
        seed: configuration.seed
      )
      return try await engine.createConversation(with: ConversationConfig(samplerConfig: sampler))
    } catch {
      throw StagedInferenceError(stage: .conversationCreation, underlying: error)
    }
  }

  private func sendImage(path: String, prompt: String, conversation: Conversation) async throws -> String {
    do {
      let message = Message(contents: [.imageFile(path), .text(prompt)])
      return try await conversation.sendMessage(message).toString
    } catch {
      throw StagedInferenceError(stage: .imageRequest, underlying: error)
    }
  }
}

actor InferenceService: TimelineInferenceServing {
  let descriptor: ModelDescriptor
  let configuration: InferenceConfiguration
  private let adapter: LiteRTLMEngineSessionAdapter

  init(
    verifiedModel: VerifiedModel,
    configuration: InferenceConfiguration = .deterministicBaseline,
    cacheURL: URL
  ) {
    descriptor = verifiedModel.descriptor
    self.configuration = configuration
    adapter = LiteRTLMEngineSessionAdapter(verifiedModel: verifiedModel, cacheURL: cacheURL, configuration: configuration)
  }

  func prepare() async throws -> EnginePreparationResult { try await adapter.prepare() }
  func engineState() async -> EngineProcessState { await adapter.state() }
  func canReleaseForModelChange() async -> Bool { await adapter.canReleaseForModelChange() }

  func analyze(draftURL: URL) async throws -> String {
    if configuration.usesLocalPixelBridge {
      let facts: LocalPixelFacts
      do { facts = try LocalPixelFeatureExtractor.extract(from: draftURL) }
      catch { throw StagedInferenceError(stage: .imageEncoding, underlying: error) }
      return try await adapter.sendStructuredText(
        path: draftURL.path,
        prompt: Self.localPixelBridgePrompt(facts)
      )
    }
    return try await adapter.sendStructuredImage(path: draftURL.path, prompt: Self.prompt)
  }

  func repair(draftURL: URL, errors: String) async throws -> String {
    try await adapter.repair(path: draftURL.path, errors: errors)
  }

  func discardRepairContext(draftURL: URL) async {
    await adapter.discardRepairContext(path: draftURL.path)
  }

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  func dominantColorProbe(draftURL: URL) async throws -> String {
    if configuration.usesLocalPixelBridge {
      let facts: LocalPixelFacts
      do { facts = try LocalPixelFeatureExtractor.extract(from: draftURL) }
      catch { throw StagedInferenceError(stage: .imageEncoding, underlying: error) }
      return try await adapter.sendProbeText(prompt: Self.localPixelBridgeColorPrompt(facts))
    }
    return try await adapter.sendProbeImage(path: draftURL.path, prompt: Self.dominantColorPrompt)
  }
  #endif

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  static let dominantColorPrompt = "Inspect the image pixels. Return exactly one token: BROWN, GREEN, or OTHER. Return no other text."

  static func localPixelBridgeColorPrompt(_ facts: LocalPixelFacts) -> String {
    """
    You are the embedded Gemma model operating in text-only hackathon bridge mode. You did not receive an image. A bounded local pixel measurement produced the JSON below.
    LOCAL_PIXEL_FACTS: \(facts.canonicalJSON)

    Return exactly BROWN when dominant_color_hint is brown, exactly GREEN when it is green, and exactly OTHER for every other value. Return one token and no punctuation or explanation.
    """
  }
  #endif

  static func localPixelBridgePrompt(_ facts: LocalPixelFacts) -> String {
    """
    You are the embedded Gemma reasoning component of a gastrointestinal journal proof of concept. You did not receive or inspect the photo. The iPhone measured a small set of bounded pixel facts locally; use only those literal facts. The user must review every field before saving. Do not diagnose, determine causes, give advice, or judge safety.

    LOCAL_PIXEL_FACTS: \(facts.canonicalJSON)

    Return ONLY JSON, no code fences, with exactly these keys: image_usable, quality_issue, apparent_bristol_type, apparent_color, form, red_appearing_material, black_tarry_appearance.

    Apply these conservative rules exactly:
    - If quality_hint is "none", set image_usable true, quality_issue "none", apparent_color to apparent_color_hint, apparent_bristol_type to bristol_type_hint (including null), and form to form_hint. Shape/form values are explicitly low-confidence hackathon approximations from the coarse 12x12 map.
    - Otherwise set image_usable false, quality_issue to quality_hint, apparent_bristol_type null, and apparent_color and form to "unable_to_assess".
    - Always set red_appearing_material and black_tarry_appearance to "unable_to_assess" because those cannot be established safely from the local measurements.
    - Use no facts or values that are not present above.

    Valid allowed values: quality_issue is none, too_dark, blurred, obstructed, too_far, not_target_image, or other. apparent_bristol_type is integer 1 through 7 or null. apparent_color is brown, light_brown, dark_brown, green, yellow, orange, red_appearing, black_appearing, pale_or_clay_appearing, mixed, or unable_to_assess. form is hard_lumps, lumpy_formed, cracked_formed, smooth_formed, soft_blobs, mushy, watery, mixed, or unable_to_assess. Both material fields are unable_to_assess for this mode.
    """
  }

  static let prompt = """
  You are the visual documentation component of a private gastrointestinal journal. Classify this bowel-movement photograph into neutral, structured visual observations. The user will review your output before saving. You are not diagnosing, determining causes, giving advice, or judging safety.

  Rules: report only visible features. Never diagnose or name any condition. Use only the allowed values below. Lighting, water, and camera processing can change apparent color. If the image is unclear or does not clearly show a bowel movement, set image_usable to false. Bristol reference: 1 hard lumps; 2 lumpy sausage; 3 sausage with cracks; 4 smooth soft sausage; 5 soft blobs; 6 mushy ragged; 7 watery.

  Return ONLY JSON, no code fences, exactly these keys and no others. Valid example:
  {"image_usable": true, "quality_issue": "none", "apparent_bristol_type": 4, "apparent_color": "brown", "form": "smooth_formed", "red_appearing_material": "not_observed", "black_tarry_appearance": "not_observed"}

  Allowed values — quality_issue: none, too_dark, blurred, obstructed, too_far, not_target_image, other. apparent_color: brown, light_brown, dark_brown, green, yellow, orange, red_appearing, black_appearing, pale_or_clay_appearing, mixed, unable_to_assess. form: hard_lumps, lumpy_formed, cracked_formed, smooth_formed, soft_blobs, mushy, watery, mixed, unable_to_assess. red_appearing_material and black_tarry_appearance: not_observed, possible, apparent, unable_to_assess. apparent_bristol_type: integer 1–7, or null.

  Consistency rules you must follow exactly: when image_usable is true, quality_issue must be "none". When image_usable is false: quality_issue must not be "none"; apparent_bristol_type must be null; and apparent_color, form, red_appearing_material, and black_tarry_appearance must all be "unable_to_assess".
  """
}

#if DEBUG
actor MockInferenceService: TimelineInferenceServing {
  enum Script { case response(String), malformed(String), slow(String, nanoseconds: UInt64) }
  var scripts: [Script]
  private let failPrepare: Bool
  private let prepareDelayNanoseconds: UInt64
  private var state: EngineProcessState

  init(scripts: [Script], failPrepare: Bool = false, initiallyReady: Bool = true, prepareDelayNanoseconds: UInt64 = 0) {
    self.scripts = scripts
    self.failPrepare = failPrepare
    self.prepareDelayNanoseconds = prepareDelayNanoseconds
    state = initiallyReady ? .ready : .uninitialized
  }

  func prepare() async throws -> EnginePreparationResult {
    if prepareDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: prepareDelayNanoseconds) }
    if failPrepare {
      state = .failed("mock prepare failure")
      throw CocoaError(.fileReadCorruptFile)
    }
    let reused = state == .ready
    state = .ready
    return EnginePreparationResult(seconds: 0, reusedCurrentProcessEngine: reused)
  }

  func engineState() -> EngineProcessState { state }

  func analyze(draftURL: URL) async throws -> String {
    guard !scripts.isEmpty else { throw CocoaError(.fileNoSuchFile) }
    switch scripts.removeFirst() {
    case .response(let value), .malformed(let value): return value
    case .slow(let value, let delay): try await Task.sleep(nanoseconds: delay); return value
    }
  }

  func repair(draftURL: URL, errors: String) async throws -> String { try await analyze(draftURL: draftURL) }
  func discardRepairContext(draftURL: URL) {}
}
#endif

actor UnavailableInferenceService: TimelineInferenceServing {
  func prepare() throws -> EnginePreparationResult { throw GITimelineError.missingModelDescriptor }
  func engineState() -> EngineProcessState { .uninitialized }
  func analyze(draftURL: URL) throws -> String { throw GITimelineError.missingModelDescriptor }
  func repair(draftURL: URL, errors: String) throws -> String { throw GITimelineError.missingModelDescriptor }
  func discardRepairContext(draftURL: URL) {}
}
