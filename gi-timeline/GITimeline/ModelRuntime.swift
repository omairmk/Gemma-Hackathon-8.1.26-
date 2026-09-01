import Darwin
import Foundation
import GITimelineCore

struct ModelDescriptor: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let family: String
  let modelID: String
  let artifactFilename: String
  let sourceRevision: String
  let sourceURL: String
  let expectedSHA256: String
  let expectedBytes: Int64
  let cacheNamespace: String
  /// An official platform-specific minimum when one is published. `nil` is
  /// deliberate for candidates whose Android memory gate must not be reused
  /// as an iOS requirement.
  let minimumMemoryGB: Int?

  init(
    id: String,
    family: String,
    modelID: String,
    artifactFilename: String,
    sourceRevision: String,
    sourceURL: String,
    expectedSHA256: String,
    expectedBytes: Int64,
    cacheNamespace: String,
    minimumMemoryGB: Int?
  ) throws {
    func isSafeComponent(_ value: String) -> Bool {
      guard let first = value.first, first.isASCII, first.isLetter || first.isNumber else { return false }
      return value.allSatisfy { character in
        character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "_" || character == "-")
      }
    }
    guard isSafeComponent(id), !id.contains(".."),
      isSafeComponent(cacheNamespace), !cacheNamespace.contains(".."),
      isSafeComponent(artifactFilename),
      artifactFilename.hasSuffix(".litertlm"), !artifactFilename.contains(".."),
      sourceRevision.count == 40, sourceRevision.allSatisfy(\.isHexDigit),
      expectedSHA256.count == 64, expectedSHA256.allSatisfy(\.isHexDigit),
      expectedBytes > 0, minimumMemoryGB.map({ $0 > 0 }) ?? true,
      !family.isEmpty, !modelID.isEmpty,
      let parsedSourceURL = URL(string: sourceURL), parsedSourceURL.scheme == "https"
    else { throw GITimelineError.invalidModelDescriptor }
    self.id = id
    self.family = family
    self.modelID = modelID
    self.artifactFilename = artifactFilename
    self.sourceRevision = sourceRevision.lowercased()
    self.sourceURL = sourceURL
    self.expectedSHA256 = expectedSHA256.lowercased()
    self.expectedBytes = expectedBytes
    self.cacheNamespace = cacheNamespace
    self.minimumMemoryGB = minimumMemoryGB
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: values.decode(String.self, forKey: .id),
      family: values.decode(String.self, forKey: .family),
      modelID: values.decode(String.self, forKey: .modelID),
      artifactFilename: values.decode(String.self, forKey: .artifactFilename),
      sourceRevision: values.decode(String.self, forKey: .sourceRevision),
      sourceURL: values.decode(String.self, forKey: .sourceURL),
      expectedSHA256: values.decode(String.self, forKey: .expectedSHA256),
      expectedBytes: values.decode(Int64.self, forKey: .expectedBytes),
      cacheNamespace: values.decode(String.self, forKey: .cacheNamespace),
      minimumMemoryGB: values.decodeIfPresent(Int.self, forKey: .minimumMemoryGB)
    )
  }

  var shortSHA256: String { String(expectedSHA256.prefix(12)) }

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  static let galleryGemma3nE2B = try! ModelDescriptor(
    id: "gallery-gemma-3n-e2b-73b019b6",
    family: "Gemma 3n E2B",
    modelID: "google/gemma-3n-E2B-it-litert-lm",
    artifactFilename: "gemma-3n-E2B-it-int4.litertlm",
    sourceRevision: "73b019b63436d346f68dd9c1dbfd117eb264d888",
    sourceURL: "https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/tree/73b019b63436d346f68dd9c1dbfd117eb264d888",
    expectedSHA256: "6c5f6d8f727e3f4327dbe38731c92c47094a95fccee9c15484465e7d9e01e4d5",
    expectedBytes: 3_388_604_416,
    cacheNamespace: "gallery-gemma-3n-e2b-73b019b6",
    minimumMemoryGB: 6
  )

  static let galleryGemma3nE4B = try! ModelDescriptor(
    id: "gallery-gemma-3n-e4b-3d0179a0",
    family: "Gemma 3n E4B",
    modelID: "google/gemma-3n-E4B-it-litert-lm",
    artifactFilename: "gemma-3n-E4B-it-int4.litertlm",
    sourceRevision: "3d0179a0648381585ab337e170b7517aae8e0ce4",
    sourceURL: "https://huggingface.co/google/gemma-3n-E4B-it-litert-lm/tree/3d0179a0648381585ab337e170b7517aae8e0ce4",
    expectedSHA256: "510f7db80143308f788ded208784b6c8addabe4d465ca32fd5bd80fd43ed4dcb",
    expectedBytes: 4_652_318_720,
    cacheNamespace: "gallery-gemma-3n-e4b-3d0179a0",
    minimumMemoryGB: 8
  )

  #endif

  /// The exact embedded Hackathon artifact. Unlike the exploratory gallery
  /// candidates, this descriptor must also exist in non-Debug Hackathon builds.
  static let liteRTGemma4E4B = try! ModelDescriptor(
    id: "litert-gemma-4-e4b-28299f30",
    family: "Gemma 4 E4B",
    modelID: "litert-community/gemma-4-E4B-it-litert-lm",
    artifactFilename: "gemma-4-E4B-it.litertlm",
    sourceRevision: "28299f30ee4d43294517a4ac93abd6163412f07f",
    sourceURL: "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/tree/28299f30ee4d43294517a4ac93abd6163412f07f",
    expectedSHA256: "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0",
    expectedBytes: 3_659_530_240,
    cacheNamespace: "litert-gemma-4-e4b-28299f30",
    minimumMemoryGB: nil
  )
}

enum AnalysisPipelineVersion {
  static let appStoreRawImageV1 = "app-store-raw-image-v1-cpu-candidate"
  static let rawImageV1 = "gi-observation-raw-v1"
  static let rawImageV2 = "gi-observation-raw-v2"
  static let derivedMapV1 = "gi-local-pixel-bridge-v1"
  static let derivedMapV2 = "gi-local-pixel-bridge-v2"
  /// Stable provenance identifier for full-prefill receipts. Shipping builds
  /// need to validate stored receipts even though the candidate route remains
  /// restricted to internal configurations below.
  static let appStoreRawImageV12SubjectGateTuning =
    "gi-v1-photo-full-prefill-ab-normalization-v1"
  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  /// Engineering-only provenance for the isolated tuning partition. This is
  /// intentionally not a production or locked-holdout pipeline identifier.
  static let derivedMapV3Tuning = "gi-local-pixel-bridge-v3-tuning"
  /// Frozen candidate provenance used only by the one-shot blind-validation
  /// lane. Its extractor behavior is byte-for-byte the v3 tuning behavior,
  /// but its results can never be mistaken for tuning observations.
  static let derivedMapV3BlindValidation = "gi-local-pixel-bridge-v3-blind-validation-v1"
  #endif
}

struct InferenceConfiguration: Codable, Equatable, Sendable {
  let id: String
  let engineBackend: String
  let visionBackend: String
  /// Explicit thread count for the main CPU executor only. Nil preserves the
  /// reviewed LiteRT runtime default and never implies vision-thread control.
  let mainCPUThreadCount: Int?
  /// Legacy/native configuration provenance. The app separately enforces the
  /// shipping product route's one-photo limit.
  let maxNumImages: Int?
  let maxNumTokens: Int
  let topK: Int
  let topP: Float
  let temperature: Float
  let seed: Int
  let promptVersion: String
  let imageMessageForm: String
  /// Conversation-scoped LiteRT visual-token selection captured as explicit
  /// route provenance. Nil means the runtime/model default is used.
  let visualTokenBudget: Int?

  init(
    id: String,
    engineBackend: String,
    visionBackend: String,
    mainCPUThreadCount: Int? = nil,
    maxNumImages: Int? = nil,
    maxNumTokens: Int,
    topK: Int,
    topP: Float,
    temperature: Float,
    seed: Int,
    promptVersion: String,
    imageMessageForm: String,
    visualTokenBudget: Int? = nil
  ) {
    self.id = id
    self.engineBackend = engineBackend
    self.visionBackend = visionBackend
    self.mainCPUThreadCount = mainCPUThreadCount
    self.maxNumImages = maxNumImages
    self.maxNumTokens = maxNumTokens
    self.topK = topK
    self.topP = topP
    self.temperature = temperature
    self.seed = seed
    self.promptVersion = promptVersion
    self.imageMessageForm = imageMessageForm
    self.visualTokenBudget = visualTokenBudget
  }

  var label: String {
    let visual = visualTokenBudget.map { " · visual \($0)" } ?? ""
    let images = maxNumImages.map { " · images \($0)" } ?? ""
    return "\(id) · \(engineBackend)/vision-\(visionBackend) · ctx \(maxNumTokens)\(images)\(visual) · topK \(topK) · temp \(temperature)"
  }

  /// The established physical-iPhone route avoids the unsupported Gemma 4
  /// vision executor. The exact embedded Gemma model receives bounded local
  /// pixel facts as text; the configuration/provenance records that boundary.
  var usesLocalPixelBridge: Bool { visionBackend == "disabled" }

  var usesRawPhotoV1Schema: Bool {
    if id == Self.appStoreRawImageV1.id { return true }
    #if DEBUG || HACKATHON_EMBEDDED_GEMMA
    return id == Self.appStoreRawImageV1GPUMainDiagnostic.id
      || usesFullPrefillCandidate
    #else
    return false
    #endif
  }

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  var usesRawPhotoV12SubjectGateTuning: Bool {
    usesFullPrefillCandidate
  }

  var usesFullPrefillCandidate: Bool {
    id == Self.appStoreRawImageV12SubjectGateTuning.id
      || id == Self.appStoreRawImageFullPrefill280.id
      || id == Self.appStoreRawImageFullPrefill70.id
  }
  #endif

  /// The pre-Library/Caches location can contain a compiled cache from the
  /// historical CPU/text-only route. The shipping raw-photo route must not
  /// treat that configuration-unbound cache as its own; it keeps the files in
  /// place and uses the versioned recreatable cache instead.
  var allowsLegacyApplicationSupportCacheReuse: Bool { !usesRawPhotoV1Schema }

  /// Stable, route-specific provenance. This is assigned from the configuration
  /// that actually ran; it is not accepted from user input or shown in ordinary
  /// UI/PDF content.
  var analysisPipelineVersion: String {
    #if DEBUG || HACKATHON_EMBEDDED_GEMMA
    if usesRawPhotoV12SubjectGateTuning {
      return AnalysisPipelineVersion.appStoreRawImageV12SubjectGateTuning
    }
    #endif
    if usesRawPhotoV1Schema { return AnalysisPipelineVersion.appStoreRawImageV1 }
    if usesLocalPixelBridge {
      #if DEBUG || HACKATHON_EMBEDDED_GEMMA
      if usesTuningPixelExtractorV3 { return AnalysisPipelineVersion.derivedMapV3Tuning }
      if usesBlindValidationPixelExtractorV3 {
        return AnalysisPipelineVersion.derivedMapV3BlindValidation
      }
      #endif
      return usesCandidatePixelExtractor
        ? AnalysisPipelineVersion.derivedMapV2
        : AnalysisPipelineVersion.derivedMapV1
    }
    return usesCandidateRawPrompt
      ? AnalysisPipelineVersion.rawImageV2
      : AnalysisPipelineVersion.rawImageV1
  }

  var usesCandidatePixelExtractor: Bool {
    id == "physical-cpu-local-pixel-bridge-extractor-v2-candidate"
  }

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  var usesTuningPixelExtractorV3: Bool {
    id == "physical-cpu-local-pixel-bridge-extractor-v3-tuning"
  }

  var usesBlindValidationPixelExtractorV3: Bool {
    id == "physical-cpu-local-pixel-bridge-extractor-v3-blind-validation-v1"
  }
  #endif

  var usesCandidateRawPrompt: Bool {
    #if DEBUG
    promptVersion == "gi-observation-v2-debug"
    #else
    false
    #endif
  }

  static let deterministicBaseline = InferenceConfiguration(
    id: "baseline-v1",
    engineBackend: "gpu",
    visionBackend: "cpu",
    maxNumTokens: 2_048,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-observation-v1",
    imageMessageForm: "Message(contents:[Content.imageFile(path),Content.text(prompt)])"
  )

  /// Shipping App Store raw-photo configuration. It reuses the exact full
  /// pinned model and the CPU-text/CPU-vision/70-token route, receiving only
  /// the validated bytes of the app's bounded metadata-free JPEG.
  static let appStoreRawImageV1 = InferenceConfiguration(
    id: "app-store-raw-image-v1-cpu-candidate",
    engineBackend: "cpu",
    visionBackend: "cpu",
    maxNumImages: 1,
    // Gemma 4's 1,024-token prefill chunk and 512-token sliding-local-attention
    // window require at least 1,536 context entries in the native CPU graph.
    maxNumTokens: 1_536,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-photo-v1.2",
    imageMessageForm: "Message(contents:[Content.imageData(validatedSanitizedJPEGBytes),Content.text(gi-photo-v1.2)])",
    visualTokenBudget: 70
  )

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  /// Internal A/B candidate for the exact shipping raw-photo route. The only
  /// runtime variable changed from `appStoreRawImageV1` is the main executor
  /// backend. This symbol is not compiled into the public App Store build.
  static let appStoreRawImageV1GPUMainDiagnostic = InferenceConfiguration(
    id: "diagnostic-app-store-raw-image-v1-gpu-main-cpu-vision70",
    engineBackend: "gpu",
    visionBackend: "cpu",
    maxNumImages: 1,
    maxNumTokens: 1_536,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-photo-v1.2",
    imageMessageForm: "Message(contents:[Content.imageData(validatedSanitizedJPEGBytes),Content.text(gi-photo-v1.2)])",
    visualTokenBudget: 70
  )

  /// Default arm of the one bounded internal comparison. The exact model,
  /// runtime, prompt, schema, sampler and image bytes are shared with the 280
  /// arm; only visualTokenBudget and the cache/config identity differ.
  static let appStoreRawImageV12SubjectGateTuning = InferenceConfiguration(
    id: "gi-v1-photo-full-prefill-normalization-v1-vt140",
    engineBackend: "cpu",
    visionBackend: "cpu",
    maxNumImages: 1,
    maxNumTokens: 1_536,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-photo-v1.4-full-prefill-v1",
    imageMessageForm: "Message(contents:[Content.imageData(validatedSanitizedJPEGBytes),Content.text(gi-photo-v1.4-full-prefill-v1)],responseFormat:gi-photo-full-prefill-v1)",
    visualTokenBudget: 140
  )

  static let appStoreRawImageFullPrefill280 = InferenceConfiguration(
    id: "gi-v1-photo-full-prefill-normalization-v1-vt280",
    engineBackend: "cpu",
    visionBackend: "cpu",
    maxNumImages: 1,
    maxNumTokens: 1_536,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-photo-v1.4-full-prefill-v1",
    imageMessageForm: "Message(contents:[Content.imageData(validatedSanitizedJPEGBytes),Content.text(gi-photo-v1.4-full-prefill-v1)],responseFormat:gi-photo-full-prefill-v1)",
    visualTokenBudget: 280
  )

  /// Conditional internal arm for the already-frozen synthetic ladder. This
  /// is not the public 70-token selector: it retains the exact full-prefill
  /// prompt and constrained schema and is reachable only after 280 and 140
  /// pass their preceding gates.
  static let appStoreRawImageFullPrefill70 = InferenceConfiguration(
    id: "gi-v1-photo-full-prefill-normalization-v1-vt70-diagnostic",
    engineBackend: "cpu",
    visionBackend: "cpu",
    maxNumImages: 1,
    maxNumTokens: 1_536,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-photo-v1.4-full-prefill-v1",
    imageMessageForm: "Message(contents:[Content.imageData(validatedSanitizedJPEGBytes),Content.text(gi-photo-v1.4-full-prefill-v1)],responseFormat:gi-photo-full-prefill-v1)",
    visualTokenBudget: 70
  )

  /// Launch-only selector shared by the diagnostic app and its acceptance
  /// harness. The selector is not compiled into the public App Store build.
  static let internalAppStoreRawImageV1LaunchArgument =
    "--internal-app-store-raw-image-v1"
  static let internalAppStoreRawImageV1CandidateLaunchArgument =
    "--internal-gi-v1-photo-full-prefill-normalized-140"
  static let internalAppStoreRawImageV1Candidate280LaunchArgument =
    "--internal-gi-v1-photo-full-prefill-normalized-280"
  static let internalAppStoreRawImageV1Candidate70LaunchArgument =
    "--internal-gi-v1-photo-full-prefill-normalized-70-diagnostic"
  static let internalAppStoreRawImageV1GPUMainLaunchArgument =
    "--internal-app-store-raw-image-v1-gpu-main-cpu-vision70-ab"

  /// Resolves the only diagnostic override that is permitted to substitute a
  /// public raw-photo configuration. Keeping this resolution beside the
  /// configuration lets unit tests cover the same branch app initialization
  /// uses instead of testing a parallel interpretation of launch arguments.
  static func internalDiagnosticConfiguration(
    arguments: [String]
  ) -> InferenceConfiguration? {
    let cpuSelectorCount = arguments.filter {
      $0 == internalAppStoreRawImageV1LaunchArgument
    }.count
    let gpuMainSelectorCount = arguments.filter {
      $0 == internalAppStoreRawImageV1GPUMainLaunchArgument
    }.count
    let candidateSelectorCount = arguments.filter {
      $0 == internalAppStoreRawImageV1CandidateLaunchArgument
    }.count
    let candidate280SelectorCount = arguments.filter {
      $0 == internalAppStoreRawImageV1Candidate280LaunchArgument
    }.count
    let candidate70SelectorCount = arguments.filter {
      $0 == internalAppStoreRawImageV1Candidate70LaunchArgument
    }.count
    guard cpuSelectorCount <= 1, gpuMainSelectorCount <= 1,
      candidateSelectorCount <= 1, candidate280SelectorCount <= 1,
      candidate70SelectorCount <= 1,
      cpuSelectorCount + gpuMainSelectorCount + candidateSelectorCount
        + candidate280SelectorCount + candidate70SelectorCount == 1
    else { return nil }
    if candidateSelectorCount == 1 {
      return .appStoreRawImageV12SubjectGateTuning
    }
    if candidate280SelectorCount == 1 {
      return .appStoreRawImageFullPrefill280
    }
    if candidate70SelectorCount == 1 {
      return .appStoreRawImageFullPrefill70
    }
    return gpuMainSelectorCount == 1
      ? .appStoreRawImageV1GPUMainDiagnostic
      : .appStoreRawImageV1
  }

  /// The embedded acceptance harness normally follows the build's runtime
  /// default. Its explicit raw-image selector must instead accept the exact
  /// shipping configuration it asked the app-scoped coordinator to use.
  static func embeddedHarnessExpectedConfiguration(
    arguments: [String]
  ) -> InferenceConfiguration {
    internalDiagnosticConfiguration(arguments: arguments) ?? .runtimeDefault
  }
  #endif

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  /// Physical-iPhone experiment that moves only the vision executor away from
  /// the CPU/XNNPACK path that failed to allocate its Gemma 4 image tensors.
  /// Model identity, main backend, context, sampler, prompt, and message shape
  /// remain identical to `deterministicBaseline`.
  static let physicalGPUVision = InferenceConfiguration(
    id: "physical-gpu-vision-v1",
    engineBackend: "gpu",
    visionBackend: "gpu",
    maxNumTokens: 2_048,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-observation-v1",
    imageMessageForm: "Message(contents:[Content.imageFile(path),Content.text(prompt)])"
  )

  /// Current-model-only physical experiment: keep the Gemma vision encoder on
  /// Metal while moving the much larger text engine to CPU to free GPU memory.
  static let physicalCPUGPUVision = InferenceConfiguration(
    id: "physical-cpu-gpu-vision-v1",
    engineBackend: "cpu",
    visionBackend: "gpu",
    maxNumTokens: 2_048,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-observation-v1",
    imageMessageForm: "Message(contents:[Content.imageFile(path),Content.text(prompt)])"
  )

  /// Current E4B model with the proven main/vision backend pair, but using
  /// Gemma 4's supported smallest visual-token budget so LiteRT selects the
  /// `vision_70` graph instead of the failing `vision_280` graph.
  static let physicalGPUCPUVision70 = InferenceConfiguration(
    id: "physical-gpu-cpu-vision70-ctx1024-v1",
    engineBackend: "gpu",
    visionBackend: "cpu",
    maxNumTokens: 1_024,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-observation-v1",
    imageMessageForm: "Message(contents:[Content.imageFile(path),Content.text(prompt)])",
    visualTokenBudget: 70
  )

  /// Time-boxed physical-iPhone bridge for the exact E4B artifact. The phone
  /// measures coarse image quality/color locally and Gemma produces a strict,
  /// conservative review draft without invoking LiteRT's broken vision graph.
  static let physicalCPUVisualBridge = InferenceConfiguration(
    id: "physical-cpu-local-pixel-bridge-ctx2048-v1",
    engineBackend: "cpu",
    visionBackend: "disabled",
    maxNumTokens: 2_048,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-local-pixel-bridge-v1",
    imageMessageForm: "LocalPixelFacts(JSON) -> Message(text); raw image is not sent to Gemma"
  )

  /// One-variable derived-map comparison. The model artifact, engine, sampler,
  /// context, text prompt, and production default remain unchanged; only the
  /// local deterministic extractor/postcondition candidate is selected.
  static let physicalCPUVisualBridgeExtractorV2Candidate = InferenceConfiguration(
    id: "physical-cpu-local-pixel-bridge-extractor-v2-candidate",
    engineBackend: "cpu",
    visionBackend: "disabled",
    maxNumTokens: 2_048,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-local-pixel-bridge-v1",
    imageMessageForm: "LocalPixelFacts(JSON) -> Message(text); raw image is not sent to Gemma"
  )

  /// Isolated tuning-only successor lane. It deliberately starts from the v2
  /// extractor behavior so future threshold work receives distinct v3
  /// provenance without changing the frozen v2 holdout candidate or the
  /// production v1 default.
  static let physicalCPUVisualBridgeExtractorV3TuningCandidate = InferenceConfiguration(
    id: "physical-cpu-local-pixel-bridge-extractor-v3-tuning",
    engineBackend: "cpu",
    visionBackend: "disabled",
    maxNumTokens: 2_048,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-local-pixel-bridge-v1",
    imageMessageForm: "LocalPixelFacts(JSON) -> Message(text); raw image is not sent to Gemma"
  )

  /// Validation-only identity for the already-frozen v3 tuning behavior. All
  /// execution fields intentionally match the tuning configuration; only the
  /// identifier/provenance changes so blind results cannot flow back into the
  /// tuning partition or into the production default.
  static let physicalCPUVisualBridgeExtractorV3BlindValidationCandidate = InferenceConfiguration(
    id: "physical-cpu-local-pixel-bridge-extractor-v3-blind-validation-v1",
    engineBackend: "cpu",
    visionBackend: "disabled",
    maxNumTokens: 2_048,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-local-pixel-bridge-v1",
    imageMessageForm: "LocalPixelFacts(JSON) -> Message(text); raw image is not sent to Gemma"
  )
  #endif

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  /// One-variable simulator experiment after the GPU path failed in Metal
  /// kernel compilation. Model, vision backend, context, sampler, and prompt
  /// remain identical to `deterministicBaseline`.
  static let simulatorCPUFallback = InferenceConfiguration(
    id: "simulator-cpu-v1",
    engineBackend: "cpu",
    visionBackend: "cpu",
    maxNumTokens: 2_048,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-observation-v1",
    imageMessageForm: "Message(contents:[Content.imageFile(path),Content.text(prompt)])"
  )

  #if DEBUG
  /// Simulator-only, one-variable raw-image prompt comparison. It is never the
  /// production default and cannot establish physical-iPhone raw-image vision.
  static let simulatorRawPromptV2Candidate = InferenceConfiguration(
    id: "simulator-cpu-raw-prompt-v2-debug",
    engineBackend: "cpu",
    visionBackend: "cpu",
    maxNumTokens: 2_048,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-observation-v2-debug",
    imageMessageForm: "Message(contents:[Content.imageFile(path),Content.text(prompt)])"
  )
  #endif
  #endif

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  /// Explicit, opt-in physical-device experiment. GPU remains the normal
  /// physical Debug default; this configuration is selected only when the
  /// build defines `PHYSICAL_CPU_ENGINE_FALLBACK` after a recorded GPU failure.
  static let physicalCPUFallback = InferenceConfiguration(
    id: "physical-cpu-engine-fallback-v1",
    engineBackend: "cpu",
    visionBackend: "cpu",
    maxNumTokens: 2_048,
    topK: 1,
    topP: 1,
    temperature: 0,
    seed: 0,
    promptVersion: "gi-observation-v1",
    imageMessageForm: "Message(contents:[Content.imageFile(path),Content.text(prompt)])"
  )
  #endif

  #if APPSTORE_RELEASE
  static let runtimeDefault = appStoreRawImageV1
  #elseif HACKATHON_EMBEDDED_GEMMA && targetEnvironment(simulator)
  static let runtimeDefault = simulatorCPUFallback
  #elseif HACKATHON_EMBEDDED_GEMMA
  static let runtimeDefault = physicalCPUVisualBridge
  #elseif DEBUG && targetEnvironment(simulator)
  static let runtimeDefault = simulatorCPUFallback
  #elseif DEBUG && PHYSICAL_CPU_ENGINE_FALLBACK
  static let runtimeDefault = physicalCPUFallback
  #else
  static let runtimeDefault = deterministicBaseline
  #endif

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  /// Evaluation-only compatibility gate. A candidate may share the prepared
  /// LiteRT session only when every engine and sampler setting is identical,
  /// and only for one of the two frozen one-variable comparisons.
  func permitsEvaluationOverride(_ requested: InferenceConfiguration) -> Bool {
    guard engineBackend == requested.engineBackend,
      visionBackend == requested.visionBackend,
      mainCPUThreadCount == requested.mainCPUThreadCount,
      maxNumImages == requested.maxNumImages,
      maxNumTokens == requested.maxNumTokens,
      topK == requested.topK,
      topP == requested.topP,
      temperature == requested.temperature,
      seed == requested.seed,
      visualTokenBudget == requested.visualTokenBudget,
      imageMessageForm == requested.imageMessageForm
    else { return false }

    if self == requested { return true }
    if self == .physicalCPUVisualBridge,
      requested == .physicalCPUVisualBridgeExtractorV2Candidate
    {
      return promptVersion == requested.promptVersion
        && !usesCandidatePixelExtractor
        && requested.usesCandidatePixelExtractor
    }
    #if DEBUG
    if self == .simulatorCPUFallback,
      requested == .simulatorRawPromptV2Candidate
    {
      return promptVersion != requested.promptVersion
        && !usesCandidateRawPrompt
        && requested.usesCandidateRawPrompt
    }
    #endif
    return false
  }

  /// Dedicated one-candidate lane. The 140-token constrained candidate owns
  /// its own engine/cache/conversation; the prior same-session 70-token
  /// override is deliberately prohibited.
  func permitsRawPhotoV12TuningOverride(
    _ requested: InferenceConfiguration
  ) -> Bool {
    self == requested && requested.usesFullPrefillCandidate
  }

  /// Separate from the frozen holdout override by design. Only the production
  /// v1 bridge may host the exact v3 tuning candidate in the same prepared
  /// session; neither direction can install or promote a configuration.
  func permitsTuningOverride(_ requested: InferenceConfiguration) -> Bool {
    guard self == .physicalCPUVisualBridge,
      requested == .physicalCPUVisualBridgeExtractorV3TuningCandidate,
      engineBackend == requested.engineBackend,
      visionBackend == requested.visionBackend,
      mainCPUThreadCount == requested.mainCPUThreadCount,
      maxNumImages == requested.maxNumImages,
      maxNumTokens == requested.maxNumTokens,
      topK == requested.topK,
      topP == requested.topP,
      temperature == requested.temperature,
      seed == requested.seed,
      visualTokenBudget == requested.visualTokenBudget,
      promptVersion == requested.promptVersion,
      imageMessageForm == requested.imageMessageForm,
      !usesCandidatePixelExtractor,
      !usesTuningPixelExtractorV3,
      requested.usesTuningPixelExtractorV3
    else { return false }
    return true
  }

  /// Dedicated one-shot blind-validation gate. It is deliberately disjoint
  /// from both the historical holdout and tuning APIs and cannot install a
  /// runtime default. Session-affecting fields must exactly match the frozen
  /// v3 tuning candidate so baseline and candidate can share one preparation.
  func permitsBlindValidationOverride(_ requested: InferenceConfiguration) -> Bool {
    guard self == .physicalCPUVisualBridge,
      requested == .physicalCPUVisualBridgeExtractorV3BlindValidationCandidate,
      engineBackend == requested.engineBackend,
      visionBackend == requested.visionBackend,
      mainCPUThreadCount == requested.mainCPUThreadCount,
      maxNumImages == requested.maxNumImages,
      maxNumTokens == requested.maxNumTokens,
      topK == requested.topK,
      topP == requested.topP,
      temperature == requested.temperature,
      seed == requested.seed,
      visualTokenBudget == requested.visualTokenBudget,
      promptVersion == requested.promptVersion,
      imageMessageForm == requested.imageMessageForm,
      !usesCandidatePixelExtractor,
      !usesTuningPixelExtractorV3,
      !usesBlindValidationPixelExtractorV3,
      requested.usesBlindValidationPixelExtractorV3,
      InferenceConfiguration.runtimeDefault != requested
    else { return false }

    let tuning = InferenceConfiguration.physicalCPUVisualBridgeExtractorV3TuningCandidate
    return requested.engineBackend == tuning.engineBackend
      && requested.visionBackend == tuning.visionBackend
      && requested.mainCPUThreadCount == tuning.mainCPUThreadCount
      && requested.maxNumImages == tuning.maxNumImages
      && requested.maxNumTokens == tuning.maxNumTokens
      && requested.topK == tuning.topK
      && requested.topP == tuning.topP
      && requested.temperature == tuning.temperature
      && requested.seed == tuning.seed
      && requested.visualTokenBudget == tuning.visualTokenBudget
      && requested.promptVersion == tuning.promptVersion
      && requested.imageMessageForm == tuning.imageMessageForm
  }
  #endif
}

enum InferenceExecutionLocation: String, Codable, Equatable, Sendable {
  case iPhoneLocal = "IPHONE_LOCAL"
  case simulatorLocal = "SIMULATOR_LOCAL"
  case macLocal = "MAC_LOCAL"
  case cloud = "CLOUD"

  static var currentAppLocal: InferenceExecutionLocation {
    #if targetEnvironment(simulator)
    return .simulatorLocal
    #else
    return .iPhoneLocal
    #endif
  }

  var displayName: String {
    switch self {
    case .iPhoneLocal: return "This iPhone"
    case .simulatorLocal: return "iPhone Simulator"
    case .macLocal: return "Nearby Mac"
    case .cloud: return "Cloud"
    }
  }
}

enum InferenceParsePath: String, Codable, Equatable, Sendable {
  case direct
  case serializationRepair = "serialization_repair"
}

struct InferenceProvenanceSnapshot: Codable, Equatable, Sendable {
  static let pinnedLiteRTLMRevision = "2117fc4314670e00047bc8469783f02a68c33f0c"

  let descriptorID: String
  let family: String
  let modelID: String
  let sourceRevision: String
  let artifactFilename: String
  let expectedSHA256: String
  let configuration: InferenceConfiguration
  let executionLocation: InferenceExecutionLocation?
  let liteRTLMRevision: String?
  let sanitizedImageSHA256: String?
  let suggestedAt: Date?
  let generationStartedAt: Date?
  let generationEndedAt: Date?
  let parsePath: InferenceParsePath?
  let suggestionSchemaVersion: String?
  /// Optional additive seam for the full-prefill candidate. Older provenance
  /// decodes with nil and remains byte-for-byte compatible.
  let fullPrefillNormalization: FullPrefillNormalizationReceiptV1?

  init(
    descriptor: ModelDescriptor,
    configuration: InferenceConfiguration,
    executionLocation: InferenceExecutionLocation = .currentAppLocal,
    sanitizedImageSHA256: String? = nil,
    suggestedAt: Date? = nil,
    generationStartedAt: Date? = nil,
    generationEndedAt: Date? = nil,
    parsePath: InferenceParsePath? = nil,
    suggestionSchemaVersion: String? = nil,
    fullPrefillNormalization: FullPrefillNormalizationReceiptV1? = nil
  ) {
    descriptorID = descriptor.id
    family = descriptor.family
    modelID = descriptor.modelID
    sourceRevision = descriptor.sourceRevision
    artifactFilename = descriptor.artifactFilename
    expectedSHA256 = descriptor.expectedSHA256
    self.configuration = configuration
    self.executionLocation = executionLocation
    liteRTLMRevision = Self.pinnedLiteRTLMRevision
    self.sanitizedImageSHA256 = sanitizedImageSHA256
    self.suggestedAt = suggestedAt
    self.generationStartedAt = generationStartedAt
    self.generationEndedAt = generationEndedAt
    self.parsePath = parsePath
    self.suggestionSchemaVersion = suggestionSchemaVersion
    self.fullPrefillNormalization = fullPrefillNormalization
  }

  func resolvedSuggestion(
    rawResponse: String
  ) throws -> StoredModelVisualSuggestion {
    if let fullPrefillNormalization {
      return .fullPrefillV1(
        try fullPrefillNormalization.validate(rawResponse: rawResponse)
      )
    }
    return try StoredModelVisualSuggestion.parse(rawResponse)
  }

  var canonicalJSON: String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
  }
}

/// A model's storage semantics are part of its verified identity. Runtime code
/// consumes this value instead of inferring mutability from a string path.
struct ModelLocation: Codable, Equatable, Sendable {
  enum Kind: String, Codable, Equatable, Sendable {
    case applicationSupport
    case applicationBundle
  }

  let kind: Kind
  let url: URL

  static func imported(_ url: URL) -> ModelLocation {
    ModelLocation(kind: .applicationSupport, url: url)
  }

  static func bundled(_ url: URL) -> ModelLocation {
    ModelLocation(kind: .applicationBundle, url: url)
  }
}

/// A stable, non-secret build identity used to invalidate the bundled-model
/// verification cache after installing a different app build.
struct ModelAppBuildIdentity: Codable, Equatable, Sendable {
  let bundleIdentifier: String
  let shortVersion: String
  let buildNumber: String

  var cacheKey: String { "\(bundleIdentifier)|\(shortVersion)|\(buildNumber)" }

  static var current: ModelAppBuildIdentity {
    let info = Bundle.main.infoDictionary ?? [:]
    return ModelAppBuildIdentity(
      bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown.bundle",
      shortVersion: info["CFBundleShortVersionString"] as? String ?? "0",
      buildNumber: info["CFBundleVersion"] as? String ?? "0"
    )
  }
}

/// Durable evidence that a file matched one immutable descriptor. Bundled
/// receipts are additionally keyed by app build and location kind so a changed
/// artifact is never trusted merely because an older import was verified.
struct ModelVerificationReceipt: Codable, Equatable, Sendable {
  let descriptorID: String
  let modelID: String
  let sourceRevision: String
  let artifactFilename: String
  let importedBytes: Int64
  let importedSHA256: String
  let verifiedAt: Date
  let locationKind: ModelLocation.Kind?
  let appBuildIdentity: ModelAppBuildIdentity?

  init(
    descriptorID: String,
    modelID: String,
    sourceRevision: String,
    artifactFilename: String,
    importedBytes: Int64,
    importedSHA256: String,
    verifiedAt: Date,
    locationKind: ModelLocation.Kind? = nil,
    appBuildIdentity: ModelAppBuildIdentity? = nil
  ) {
    self.descriptorID = descriptorID
    self.modelID = modelID
    self.sourceRevision = sourceRevision
    self.artifactFilename = artifactFilename
    self.importedBytes = importedBytes
    self.importedSHA256 = importedSHA256
    self.verifiedAt = verifiedAt
    self.locationKind = locationKind
    self.appBuildIdentity = appBuildIdentity
  }

  func matches(_ descriptor: ModelDescriptor) -> Bool {
    descriptorID == descriptor.id
      && modelID == descriptor.modelID
      && sourceRevision == descriptor.sourceRevision
      && artifactFilename == descriptor.artifactFilename
      && importedBytes == descriptor.expectedBytes
      && importedSHA256.caseInsensitiveCompare(descriptor.expectedSHA256) == .orderedSame
  }

  func matches(
    _ descriptor: ModelDescriptor,
    location: ModelLocation,
    appBuildIdentity: ModelAppBuildIdentity
  ) -> Bool {
    matches(descriptor)
      && locationKind == location.kind
      && self.appBuildIdentity == appBuildIdentity
  }
}

/// A capability produced only after a descriptor-matching durable receipt and
/// installed file have been validated by ModelImporter. Runtime construction
/// consumes this value instead of accepting an arbitrary model path.
struct VerifiedModel: Sendable {
  let descriptor: ModelDescriptor
  let location: ModelLocation
  let receipt: ModelVerificationReceipt

  var modelURL: URL { location.url }

  init(validating descriptor: ModelDescriptor, modelURL: URL, receipt: ModelVerificationReceipt) throws {
    try self.init(
      validating: descriptor,
      location: .imported(modelURL),
      receipt: receipt,
      appBuildIdentity: nil
    )
  }

  init(
    validating descriptor: ModelDescriptor,
    location: ModelLocation,
    receipt: ModelVerificationReceipt,
    appBuildIdentity: ModelAppBuildIdentity?
  ) throws {
    guard receipt.matches(descriptor), location.url.lastPathComponent == descriptor.artifactFilename else {
      throw GITimelineError.invalidModelReceipt
    }
    if let appBuildIdentity {
      guard receipt.matches(descriptor, location: location, appBuildIdentity: appBuildIdentity) else {
        throw GITimelineError.invalidModelReceipt
      }
    }
    self.descriptor = descriptor
    self.location = location
    self.receipt = receipt
  }
}

enum LocalAnalysisReadiness: Equatable, Sendable {
  case verifying
  case preparing
  case ready
  case failed(userFacingMessage: String, technicalDetail: String)
}

struct ModelImportResult: Sendable {
  let sourceURL: URL
  let verifiedModel: VerifiedModel

  var modelURL: URL { verifiedModel.modelURL }
  var receipt: ModelVerificationReceipt { verifiedModel.receipt }
}

enum EngineProcessState: Equatable, Sendable {
  case uninitialized
  case initializing
  case ready
  case failed(String)

  var label: String {
    switch self {
    case .uninitialized: return "uninitialized"
    case .initializing: return "initializing"
    case .ready: return "ready"
    case .failed: return "failed"
    }
  }
}

struct EnginePreparationResult: Equatable, Sendable {
  let seconds: Double
  let reusedCurrentProcessEngine: Bool
}

enum InferenceErrorStage: String, Codable, CaseIterable, Sendable {
  case `import`
  case hash
  case engineInitialization = "engine_initialization"
  case imageEncoding = "image_encoding"
  case conversationCreation = "conversation_creation"
  case imageRequest = "image_request"
  case generation
  case parsing
  case repair
  case timeout
  case memoryOrCrash = "memory_or_crash"
  case persistence
}

struct StagedInferenceError: LocalizedError, Sendable {
  let stage: InferenceErrorStage
  let message: String

  init(stage: InferenceErrorStage, underlying: Error) {
    self.stage = stage
    message = underlying.localizedDescription
  }

  var errorDescription: String? { "\(stage.rawValue): \(message)" }
}

#if DEBUG || HACKATHON_EMBEDDED_GEMMA
enum DominantColorResult: String, Codable, CaseIterable, Sendable {
  case brown = "BROWN"
  case green = "GREEN"
  case other = "OTHER"

  static func parse(_ raw: String) throws -> DominantColorResult {
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let result = DominantColorResult(rawValue: token) else {
      throw GITimelineError.invalidDominantColorProbe
    }
    return result
  }
}
#endif

enum ModelCatalog {
  #if DEBUG
  static let debugCandidates: [ModelDescriptor] = [.galleryGemma3nE2B, .galleryGemma3nE4B, .liteRTGemma4E4B]
  /// Hackathon-only normal-flow selection. This is deliberately separate from
  /// the Release acceptance record and must stay behind DEBUG.
  static let debugPOCSelection: ModelDescriptor? = .liteRTGemma4E4B
  #endif

  #if MANUAL_FALLBACK_RELEASE
  /// The public manual fallback selects no model and can never prepare or
  /// invoke one. Its build settings and package validators separately require
  /// the public app bundle to contain no model payload.
  static let releaseSelection: ModelDescriptor? = nil
  #elseif APPSTORE_RELEASE
  /// The public offline build embeds this immutable artifact during its signed
  /// build and will fail its build phase if size or SHA-256 differs.
  static let releaseSelection: ModelDescriptor? = .liteRTGemma4E4B
  #else
  /// Internal model-free Release builds remain unable to infer readiness from a
  /// stray file. Only the explicit App Store configuration selects a model.
  static let releaseSelection: ModelDescriptor? = nil
  #endif

  static var normalFlowSelection: ModelDescriptor? {
    #if MANUAL_FALLBACK_RELEASE
    return nil
    #elseif HACKATHON_EMBEDDED_GEMMA || APPSTORE_RELEASE
    return .liteRTGemma4E4B
    #elseif DEBUG
    return debugPOCSelection
    #else
    return releaseSelection
    #endif
  }
}

/// App-scoped registry for verified model access and per-model engine reuse.
/// Both the normal flow and the DEBUG lab request services here, preventing a
/// second engine/session implementation for the same selected descriptor.
struct RuntimeCoordinatorGate: Sendable {
  enum LeasePurpose: Equatable, Sendable {
    case transient
    case structured(draftPath: String)
  }

  private struct Lease: Sendable {
    let token: UUID
    let descriptorID: String
    let purpose: LeasePurpose
  }

  private(set) var transitionInProgress = false
  private var lease: Lease?
  private var containedCallToken: UUID?
  private var quarantinedToken: UUID?

  var hasLease: Bool { lease != nil }
  var hasUnsettledContainedCall: Bool { containedCallToken != nil }
  var hasQuarantinedOperation: Bool { quarantinedToken != nil }
  var requiresRestartAfterCancellation: Bool { quarantinedToken != nil }

  mutating func beginTransition() throws {
    guard !transitionInProgress, lease == nil else { throw GITimelineError.operationInProgress }
    transitionInProgress = true
  }

  mutating func endTransition() { transitionInProgress = false }

  mutating func acquire(descriptorID: String, purpose: LeasePurpose) throws -> UUID {
    guard !transitionInProgress, lease == nil else { throw GITimelineError.operationInProgress }
    let token = UUID()
    lease = Lease(token: token, descriptorID: descriptorID, purpose: purpose)
    return token
  }

  func structuredToken(descriptorID: String, draftPath: String) -> UUID? {
    guard let lease, lease.descriptorID == descriptorID,
      lease.purpose == .structured(draftPath: draftPath)
    else { return nil }
    return lease.token
  }

  mutating func release(_ token: UUID) {
    guard lease?.token == token, quarantinedToken != token else { return }
    lease = nil
    containedCallToken = nil
    quarantinedToken = nil
  }

  mutating func beginContainedCall(_ token: UUID) -> Bool {
    guard lease?.token == token, containedCallToken == nil, quarantinedToken == nil else {
      return false
    }
    containedCallToken = token
    return true
  }

  mutating func finishContainedCall(_ token: UUID) {
    guard containedCallToken == token else { return }
    containedCallToken = nil
  }

  func permitsRepairContextDiscard(_ token: UUID) -> Bool {
    lease?.token == token && containedCallToken != token && quarantinedToken != token
  }

  mutating func quarantine(_ token: UUID) {
    guard lease?.token == token else { return }
    containedCallToken = nil
    quarantinedToken = token
  }

  func isQuarantined(_ token: UUID) -> Bool {
    quarantinedToken == token
  }
}

enum InferenceCallerContainmentError: Error, Equatable, LocalizedError, Sendable {
  case timedOut
  case timedOutBeforeOperationStarted
  case callerCancelled
  case callerCancelledBeforeOperationStarted
  case deadlineThreadUnavailable

  var requiresQuarantine: Bool {
    switch self {
    case .timedOut, .callerCancelled: return true
    case .timedOutBeforeOperationStarted, .callerCancelledBeforeOperationStarted,
      .deadlineThreadUnavailable: return false
    }
  }

  var errorDescription: String? {
    switch self {
    case .timedOut:
      return "The local inference operation did not return before its containment deadline."
    case .timedOutBeforeOperationStarted:
      return "The local inference containment deadline elapsed before the operation started."
    case .callerCancelled:
      return "The caller stopped waiting before the local inference operation returned."
    case .callerCancelledBeforeOperationStarted:
      return "The caller cancelled before the local inference operation started."
    case .deadlineThreadUnavailable:
      return "The local inference safety deadline could not start."
    }
  }
}

/// Exact lifecycle points originating on the dedicated deadline thread.
/// Observer delivery is asynchronous and best-effort so a diagnostic sink
/// cannot delay containment. Shipping callers leave the observer nil; the
/// internal physical diagnostic uses these stages to distinguish a thread that
/// never started, a wait that never elapsed, and a caller resolution that
/// stalled after the deadline.
enum InferenceDeadlineThreadStage: Equatable, Sendable {
  case threadStarted
  case waitElapsedBeforeLocks
  case containmentCommitted
  case continuationResumeReturned
}

/// Resolves the caller independently of a non-cooperative native operation.
/// A task group is intentionally not used: leaving its scope waits for every
/// child, which would recreate the hang this boundary is meant to contain.
final class InferenceCallerContainmentDisposition: @unchecked Sendable {
  enum State: Equatable, Sendable {
    case active
    case completed
    case contained(InferenceCallerContainmentError)
  }

  private let lock = NSLock()
  private let terminalReporter: @Sendable (InferenceCallerContainmentError) -> Void
  private var storedState: State = .active
  private var didReportTerminal = false

  init(
    terminalReporter: @escaping @Sendable (InferenceCallerContainmentError) -> Void = { _ in }
  ) {
    self.terminalReporter = terminalReporter
  }

  var state: State {
    lock.lock()
    defer { lock.unlock() }
    return storedState
  }

  /// Commits the immutable containment disposition on the OS deadline thread.
  /// This method only takes a short lock; it does not touch actor-isolated
  /// runtime or native engine state and cannot cancel the native operation.
  func commitContainment(_ error: InferenceCallerContainmentError) {
    lock.lock()
    if storedState == .active { storedState = .contained(error) }
    lock.unlock()
  }

  /// Marks a normal operation resolution only if containment did not win.
  /// A native completion arriving after the caller deadline cannot replace the
  /// process-lifetime containment disposition.
  func commitCompletion() {
    lock.lock()
    if storedState == .active { storedState = .completed }
    lock.unlock()
  }

  /// Publishes at most one terminal receipt after the caller continuation has
  /// already been resumed. A slow or unavailable diagnostic sink therefore
  /// cannot delay the containment boundary itself.
  func reportCommittedContainment(_ error: InferenceCallerContainmentError) {
    lock.lock()
    guard storedState == .contained(error), !didReportTerminal else {
      lock.unlock()
      return
    }
    didReportTerminal = true
    lock.unlock()
    terminalReporter(error)
  }
}

private final class InferenceCallerResolution<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private let deadlineWaiter = InferenceDeadlineWaiter()
  private var continuation: CheckedContinuation<Value, Error>?
  private var pendingResult: Result<Value, Error>?
  private var operationTask: Task<Void, Never>?
  private var cancelLateOperationTask = false
  private var operationStartCommitted = false
  private var finished = false

  func install(_ continuation: CheckedContinuation<Value, Error>) {
    lock.lock()
    if let pendingResult {
      self.pendingResult = nil
      lock.unlock()
      continuation.resume(with: pendingResult)
    } else {
      self.continuation = continuation
      lock.unlock()
    }
  }

  func installOperationTask(_ task: Task<Void, Never>) {
    lock.lock()
    let shouldCancel = finished && cancelLateOperationTask
    if !finished { operationTask = task }
    lock.unlock()
    if shouldCancel { task.cancel() }
  }

  func waitForDeadline(seconds: TimeInterval) -> Bool {
    deadlineWaiter.wait(seconds: seconds)
  }

  func markDeadlineThreadStarted() {
    deadlineWaiter.markStarted()
  }

  func waitUntilDeadlineThreadStarted(seconds: TimeInterval) -> Bool {
    deadlineWaiter.waitUntilStarted(seconds: seconds)
  }

  func commitOperationStart() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !finished else { return false }
    operationStartCommitted = true
    return true
  }

  @discardableResult
  func resolveContainment(
    timedOut: Bool,
    cancellingOperation: Bool,
    disposition: InferenceCallerContainmentDisposition?,
    deadlineThreadObserver: (@Sendable (InferenceDeadlineThreadStage) -> Void)? = nil
  ) -> InferenceCallerContainmentError? {
    lock.lock()
    guard !finished else {
      lock.unlock()
      return nil
    }
    let error: InferenceCallerContainmentError
    if timedOut {
      error = operationStartCommitted ? .timedOut : .timedOutBeforeOperationStarted
    } else {
      error = operationStartCommitted ? .callerCancelled : .callerCancelledBeforeOperationStarted
    }
    finished = true
    let continuation = continuation
    self.continuation = nil
    if continuation == nil { pendingResult = .failure(error) }
    cancelLateOperationTask = cancellingOperation
    let taskToCancel = cancellingOperation ? operationTask : nil
    operationTask = nil
    lock.unlock()

    disposition?.commitContainment(error)
    deadlineThreadObserver?(.containmentCommitted)
    deadlineWaiter.disarm()
    taskToCancel?.cancel()
    continuation?.resume(throwing: error)
    deadlineThreadObserver?(.continuationResumeReturned)
    disposition?.reportCommittedContainment(error)
    return error
  }

  @discardableResult
  func resolve(
    _ result: Result<Value, Error>,
    cancellingOperation: Bool = false,
    disposition: InferenceCallerContainmentDisposition? = nil
  ) -> Bool {
    lock.lock()
    guard !finished else {
      lock.unlock()
      return false
    }
    finished = true
    let continuation = continuation
    self.continuation = nil
    if continuation == nil { pendingResult = result }
    cancelLateOperationTask = cancellingOperation
    let taskToCancel = cancellingOperation ? operationTask : nil
    operationTask = nil
    lock.unlock()

    disposition?.commitCompletion()
    deadlineWaiter.disarm()
    taskToCancel?.cancel()
    continuation?.resume(with: result)
    return true
  }
}

/// A Mach continuous-clock deadline runs on the dedicated Foundation Thread
/// itself and does not require a Swift or libdispatch worker to execute a
/// timeout handler. The continuous clock advances while the device sleeps;
/// short absolute-clock waits let successful calls disarm the otherwise
/// sleeping thread promptly.
private final class InferenceDeadlineWaiter: @unchecked Sendable {
  private let condition = NSCondition()
  private var disarmed = false
  private var started = false

  func markStarted() {
    condition.lock()
    started = true
    condition.broadcast()
    condition.unlock()
  }

  func waitUntilStarted(seconds: TimeInterval) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    guard !started else { return true }
    let deadline = Date(timeIntervalSinceNow: max(0, seconds))
    while !started {
      if !condition.wait(until: deadline) {
        return started
      }
    }
    return true
  }

  func wait(seconds: TimeInterval) -> Bool {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let safeSeconds = min(60, max(0, seconds))
    let deadlineTicks = UInt64(
      safeSeconds * 1_000_000_000
        * Double(timebase.denom) / Double(timebase.numer)
    )
    let sliceTicks = UInt64(
      250_000_000.0 * Double(timebase.denom) / Double(timebase.numer)
    )
    let deadline = mach_continuous_time() &+ deadlineTicks
    while true {
      condition.lock()
      let shouldStop = disarmed
      condition.unlock()
      if shouldStop { return false }
      let now = mach_continuous_time()
      if now >= deadline { return true }
      let remainingTicks = deadline &- now
      let absoluteSliceDeadline = mach_absolute_time() &+ min(sliceTicks, remainingTicks)
      _ = mach_wait_until(absoluteSliceDeadline)
    }
  }

  func disarm() {
    condition.lock()
    disarmed = true
    condition.signal()
    condition.unlock()
  }
}

enum InferenceCallerDeadlineRace {
  /// A preparation overrun must release the UI without cancelling or replacing
  /// LiteRT's sole initializer. The coordinator quarantines that engine lease
  /// until process termination instead.
  static let preparationDeadline: Duration = .seconds(30)
  /// Slightly exceeds the native generation deadline so a cooperative
  /// Conversation.cancel() gets a brief chance to unwind without quarantining
  /// an otherwise healthy engine. It still bounds a caller when native code
  /// never returns from generation or cancellation.
  static let structuredDeadline: Duration = .seconds(32)
  /// The one bounded full-prefill comparison uses the same hard 30-second
  /// ceiling as native generation; it cannot report a successful late result.
  static let fullPrefillComparisonDeadline: Duration = .seconds(30)
  private static let telemetryQueue = DispatchQueue(
    label: "GIJournal.InferenceDeadlineTelemetry",
    qos: .utility
  )

  static func emitBestEffortTelemetry(_ callback: (@Sendable () -> Void)?) {
    guard let callback else { return }
    telemetryQueue.async {
      callback()
    }
  }

  static func run<Value: Sendable>(
    deadline: Duration,
    cancelOperationOnContainment: Bool = true,
    containmentDisposition: InferenceCallerContainmentDisposition? = nil,
    onDeadlineThreadStarted: (@Sendable () -> Void)? = nil,
    onDeadline: (@Sendable () -> Void)? = nil,
    deadlineThreadObserver: (@Sendable (InferenceDeadlineThreadStage) -> Void)? = nil,
    beforeOperationCommitForTesting: (@Sendable () -> Void)? = nil,
    operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let resolution = InferenceCallerResolution<Value>()
    let bestEffortDeadlineThreadObserver:
      (@Sendable (InferenceDeadlineThreadStage) -> Void)?
    if let deadlineThreadObserver {
      bestEffortDeadlineThreadObserver = { stage in
        emitBestEffortTelemetry {
          deadlineThreadObserver(stage)
        }
      }
    } else {
      bestEffortDeadlineThreadObserver = nil
    }
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        resolution.install(continuation)
        let components = deadline.components
        let delaySeconds = min(
          60,
          max(
            0,
            Double(components.seconds)
              + Double(components.attoseconds) / 1_000_000_000_000_000_000
          )
        )
        // LiteRT can occupy both Swift's cooperative executor and libdispatch
        // workers while it performs a long CPU vision call. A dedicated Thread
        // keeps the wall-clock deadline independent of both pools. The caller
        // chooses whether containment also requests cooperative Task
        // cancellation; neither choice can preempt synchronous native work.
        let deadlineThread = Thread {
          resolution.markDeadlineThreadStarted()
          bestEffortDeadlineThreadObserver?(.threadStarted)
          // Diagnostic output must never run inline on the containment thread.
          // A blocked stdout/support sink may lose telemetry, but it cannot stop
          // the already-started absolute-clock deadline.
          emitBestEffortTelemetry(onDeadlineThreadStarted)
          guard resolution.waitForDeadline(seconds: delaySeconds) else {
            return
          }
          bestEffortDeadlineThreadObserver?(.waitElapsedBeforeLocks)
          let containment = resolution.resolveContainment(
            timedOut: true,
            cancellingOperation: cancelOperationOnContainment,
            disposition: containmentDisposition,
            deadlineThreadObserver: bestEffortDeadlineThreadObserver
          )
          // Resolve/cancel first. Telemetry is deliberately best-effort so a
          // blocked print, logger, or support sink cannot prevent containment.
          if containment != nil {
            emitBestEffortTelemetry(onDeadline)
          }
        }
        deadlineThread.name = "GIJournal.InferenceDeadline"
        deadlineThread.qualityOfService = .userInteractive
        deadlineThread.start()
        guard resolution.waitUntilDeadlineThreadStarted(seconds: 1) else {
          _ = resolution.resolve(
            .failure(InferenceCallerContainmentError.deadlineThreadUnavailable),
            cancellingOperation: cancelOperationOnContainment,
            disposition: containmentDisposition
          )
          return
        }
        let operationTask = Task.detached(priority: .userInitiated) {
          // Keep the irrevocable start decision beside native invocation. If
          // cancellation wins before this commit, the worker exits without
          // invoking the operation. After it commits, quarantine is required.
          beforeOperationCommitForTesting?()
          guard resolution.commitOperationStart() else { return }
          do {
            _ = resolution.resolve(
              .success(try await operation()),
              disposition: containmentDisposition
            )
          } catch {
            _ = resolution.resolve(
              .failure(error),
              disposition: containmentDisposition
            )
          }
        }
        resolution.installOperationTask(operationTask)
      }
    } onCancel: {
      _ = resolution.resolveContainment(
        timedOut: false,
        cancellingOperation: cancelOperationOnContainment,
        disposition: containmentDisposition
      )
    }
  }
}

#if DEBUG || HACKATHON_EMBEDDED_GEMMA
enum InferencePreparationContainmentTerminal {
  static let timeoutMarker: StaticString =
    "APP_STORE_RAW_IMAGE_V1_PREPARATION_CALLER_TIMEOUT outcome=FAIL deadline_ms=30000 error_class=caller_deadline_contained caller_disposition=contained actor_reconciliation=pending native_work=may_continue restart_required=true"

  /// These fixed path-free writes are intentionally limited to the internal
  /// physical diagnostic. They identify the last deadline-thread boundary
  /// reached without interpolating private state or touching journal storage.
  /// A write is still best-effort: the canonical containment state, not console
  /// output, remains authoritative.
  static func emit(_ stage: InferenceDeadlineThreadStage) {
    switch stage {
    case .threadStarted:
      emitStatic("APP_STORE_RAW_IMAGE_V1_PREPARATION_DEADLINE_THREAD_START")
    case .waitElapsedBeforeLocks:
      emitStatic("APP_STORE_RAW_IMAGE_V1_PREPARATION_DEADLINE_WAIT_ELAPSED_BEFORE_LOCKS")
    case .containmentCommitted:
      emitStatic("APP_STORE_RAW_IMAGE_V1_PREPARATION_DEADLINE_CONTAINMENT_COMMITTED")
    case .continuationResumeReturned:
      emitStatic("APP_STORE_RAW_IMAGE_V1_PREPARATION_DEADLINE_CONTINUATION_RESUME_RETURN")
    }
  }

  /// One small, path-free write runs directly on the already-live deadline
  /// thread after the caller continuation is resumed. This is diagnostic
  /// evidence only: it neither stops Engine.initialize() nor declares that the
  /// native initializer returned.
  static func emit(_ containment: InferenceCallerContainmentError) {
    guard containment == .timedOut else { return }
    emitStatic(timeoutMarker)
  }

  private static func emitStatic(_ marker: StaticString) {
    _ = Darwin.write(STDOUT_FILENO, marker.utf8Start, marker.utf8CodeUnitCount)
    var newline: UInt8 = 10
    withUnsafePointer(to: &newline) { pointer in
      _ = Darwin.write(STDOUT_FILENO, pointer, 1)
    }
  }
}
#endif

enum StructuredInferenceContainment {
  /// Quarantine is the durable state transition. Diagnostic output is
  /// deliberately scheduled only after it and can never delay the caller.
  static func quarantine(
    gate: inout RuntimeCoordinatorGate,
    token: UUID,
    telemetry: (@Sendable () -> Void)? = nil
  ) {
    gate.quarantine(token)
    InferenceCallerDeadlineRace.emitBestEffortTelemetry(telemetry)
  }
}

enum ModelRuntimeEngineCacheMode: String, Sendable {
  case sharedModelCache = "shared_model_cache"
  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  case freshIsolatedDiagnosticCache = "fresh_isolated_diagnostic_cache"
  case freshCachesRootDiagnosticCache = "fresh_caches_root_diagnostic_cache"
  #endif
}

#if DEBUG || HACKATHON_EMBEDDED_GEMMA
struct ModelRuntimeEngineCachePreparation: Equatable, Sendable {
  let mode: ModelRuntimeEngineCacheMode
  let disposition: ModelCacheDisposition
  let backupExcluded: Bool
  let protectionClass: String
}
#endif

struct ModelRuntimeEngineCacheSelection: Equatable, Sendable {
  let url: URL
  let profile: LiteRTEngineCacheProfileV1
  let disposition: ModelCacheDisposition
}

enum ModelRuntimeEngineCachePolicy: Sendable {
  case sharedModelCache
  #if DEBUG || APPSTORE_RELEASE_TESTING
  case sharedModelCacheForTesting(
    cachesDirectory: URL,
    availableCapacityOverride: Int64?,
    legacyApplicationSupportRoot: URL? = nil
  )
  #endif
  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  case freshIsolatedDiagnosticCache(
    runID: UUID,
    baseDirectory: URL? = nil,
    availableCapacityOverride: Int64? = nil
  )
  case freshCachesRootDiagnosticCache(
    runID: UUID,
    baseDirectory: URL? = nil,
    availableCapacityOverride: Int64? = nil,
    replaceExistingDiagnosticRoot: Bool = false
  )
  #endif

  var mode: ModelRuntimeEngineCacheMode {
    switch self {
    case .sharedModelCache:
      return .sharedModelCache
    #if DEBUG || APPSTORE_RELEASE_TESTING
    case .sharedModelCacheForTesting:
      return .sharedModelCache
    #endif
    #if DEBUG || HACKATHON_EMBEDDED_GEMMA
    case .freshIsolatedDiagnosticCache:
      return .freshIsolatedDiagnosticCache
    case .freshCachesRootDiagnosticCache:
      return .freshCachesRootDiagnosticCache
    #endif
    }
  }

  func cacheSelection(
    for descriptor: ModelDescriptor,
    configuration: InferenceConfiguration
  ) throws -> ModelRuntimeEngineCacheSelection {
    let profile = LiteRTEngineCacheProfileV1(
      descriptor: descriptor,
      configuration: configuration
    )
    let resolution: ModelCacheResolution
    switch self {
    case .sharedModelCache:
      resolution = try AppFolders.modelCacheResolution(
        for: descriptor,
        profile: profile,
        allowLegacyApplicationSupportReuse:
          configuration.allowsLegacyApplicationSupportCacheReuse
      )
    #if DEBUG || APPSTORE_RELEASE_TESTING
    case let .sharedModelCacheForTesting(
      cachesDirectory,
      availableCapacityOverride,
      legacyApplicationSupportRoot
    ):
      resolution = try AppFolders.modelCacheResolution(
        for: descriptor,
        profile: profile,
        cachesDirectory: cachesDirectory,
        legacyApplicationSupportRoot: legacyApplicationSupportRoot,
        availableCapacityOverride: availableCapacityOverride,
        allowLegacyApplicationSupportReuse:
          configuration.allowsLegacyApplicationSupportCacheReuse
      )
    #endif
    #if DEBUG || HACKATHON_EMBEDDED_GEMMA
    case let .freshIsolatedDiagnosticCache(
      runID,
      baseDirectory,
      availableCapacityOverride
    ):
      resolution = ModelCacheResolution(
        url: try AppFolders.freshRawImagePreparationCache(
          for: descriptor,
          runID: runID,
          baseDirectory: baseDirectory,
          availableCapacityOverride: availableCapacityOverride
        ),
        disposition: .freshDiagnosticCache
      )
    case let .freshCachesRootDiagnosticCache(
      runID,
      baseDirectory,
      availableCapacityOverride,
      replaceExistingDiagnosticRoot
    ):
      resolution = ModelCacheResolution(
        url: try AppFolders.freshCachesRootRawImagePreparationCache(
          for: descriptor,
          runID: runID,
          baseDirectory: baseDirectory,
          availableCapacityOverride: availableCapacityOverride,
          replaceExistingDiagnosticRoot: replaceExistingDiagnosticRoot
        ),
        disposition: .freshDiagnosticCache
      )
    #endif
    }
    return ModelRuntimeEngineCacheSelection(
      url: resolution.url,
      profile: profile,
      disposition: resolution.disposition
    )
  }

  func cacheURL(
    for descriptor: ModelDescriptor,
    configuration: InferenceConfiguration
  ) throws -> URL {
    try cacheSelection(for: descriptor, configuration: configuration).url
  }
}

actor ModelRuntimeCoordinator {
  private static let preparationRestartMessage =
    "On-device analysis didn’t finish getting ready. Continue manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it."

  private let importer: ModelImporter
  private let configuration: InferenceConfiguration
  private let engineCachePolicy: ModelRuntimeEngineCachePolicy
  private var activeService: (descriptorID: String, service: InferenceService)?
  private var coordinatorGate = RuntimeCoordinatorGate()
  private var resolvedModels: [String: VerifiedModel] = [:]
  private var resolvedEngineCacheSelections: [String: ModelRuntimeEngineCacheSelection] = [:]
  private var verificationTasks: [String: Task<VerifiedModel, Error>] = [:]
  private var localReadiness: LocalAnalysisReadiness = .verifying
  private var localReadinessTask: Task<LocalAnalysisReadiness, Never>?
  private var containmentSettlementWaiters: [CheckedContinuation<Void, Never>] = []

  init(
    importer: ModelImporter = ModelImporter(),
    configuration: InferenceConfiguration = .runtimeDefault,
    engineCachePolicy: ModelRuntimeEngineCachePolicy = .sharedModelCache
  ) {
    self.importer = importer
    self.configuration = configuration
    self.engineCachePolicy = engineCachePolicy
  }

  func configurationSnapshot() -> InferenceConfiguration { configuration }

  func engineCacheModeSnapshot() -> ModelRuntimeEngineCacheMode {
    engineCachePolicy.mode
  }

  /// Resolves and hardens the exact cache directory before a diagnostic emits
  /// an engine-initialization marker. The ordinary service then reuses this
  /// process-local URL, so fresh one-shot policies are never allocated twice.
  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  func prepareEngineCache(
    for descriptor: ModelDescriptor
  ) throws -> ModelRuntimeEngineCachePreparation {
    let selection = try resolveEngineCacheSelection(for: descriptor)
    let url = selection.url
    let backupExcluded = try url.resourceValues(
      forKeys: [.isExcludedFromBackupKey]
    ).isExcludedFromBackup == true
    let protection = try FileManager.default.attributesOfItem(
      atPath: url.path
    )[.protectionKey] as? FileProtectionType
    let protectionClass: String
    switch protection {
    case .complete:
      protectionClass = "complete"
    case .completeUntilFirstUserAuthentication:
      protectionClass = "complete_until_first_user_authentication"
    default:
      protectionClass = "unavailable"
    }
    return ModelRuntimeEngineCachePreparation(
      mode: engineCachePolicy.mode,
      disposition: selection.disposition,
      backupExcluded: backupExcluded,
      protectionClass: protectionClass
    )
  }
  #endif

  func localAnalysisReadiness() -> LocalAnalysisReadiness { localReadiness }

  /// A caller-cancelled native operation can outlive Swift cancellation. Its
  /// engine lease remains quarantined until process termination, so retrying
  /// setup inside this process is intentionally not offered.
  func localAnalysisRequiresFullAppRestart() async -> Bool {
    // A contained lease is only an unsettled reservation: cancellation may
    // still win before native invocation and release it safely. Wait for that
    // disposition, then report only a finalized process-lifetime quarantine.
    if coordinatorGate.hasUnsettledContainedCall {
      await withCheckedContinuation { continuation in
        if coordinatorGate.hasUnsettledContainedCall {
          containmentSettlementWaiters.append(continuation)
        } else {
          continuation.resume()
        }
      }
    }
    return coordinatorGate.requiresRestartAfterCancellation
  }

  private func finishContainedCall(_ token: UUID) {
    coordinatorGate.finishContainedCall(token)
    resumeContainmentSettlementWaitersIfSettled()
  }

  private func quarantineContainedCall(
    _ token: UUID,
    telemetry: (@Sendable () -> Void)? = nil
  ) {
    StructuredInferenceContainment.quarantine(
      gate: &coordinatorGate,
      token: token,
      telemetry: telemetry
    )
    resumeContainmentSettlementWaitersIfSettled()
  }

  private func resumeContainmentSettlementWaitersIfSettled() {
    guard !coordinatorGate.hasUnsettledContainedCall,
      !containmentSettlementWaiters.isEmpty
    else { return }
    let waiters = containmentSettlementWaiters
    containmentSettlementWaiters.removeAll(keepingCapacity: true)
    waiters.forEach { $0.resume() }
  }

  /// Verifies the selected artifact off the actor and prepares exactly the same
  /// app-scoped engine used by analysis and DEBUG diagnostics. Concurrent callers
  /// join one task instead of starting another hash or initialization.
  func prepareLocalAnalysis() async -> LocalAnalysisReadiness {
    if coordinatorGate.hasQuarantinedOperation {
      let failed = preparationRestartReadiness(
        technicalDetail: "Native preparation remains quarantined until process termination."
      )
      localReadiness = failed
      return failed
    }
    if localReadiness == .ready { return .ready }
    if let localReadinessTask {
      let result = await localReadinessTask.value
      localReadiness = result
      return result
    }
    guard let descriptor = ModelCatalog.normalFlowSelection else {
      let failed = LocalAnalysisReadiness.failed(
        userFacingMessage: "On-device analysis is not available in this build.",
        technicalDetail: GITimelineError.missingModelDescriptor.localizedDescription
      )
      localReadiness = failed
      return failed
    }

    localReadiness = .verifying
    let task = Task { [weak self] () -> LocalAnalysisReadiness in
      guard let self else {
        return .failed(userFacingMessage: "Couldn’t get on-device analysis ready.", technicalDetail: "Runtime was released.")
      }
      do {
        _ = try await self.resolveVerifiedModel(for: descriptor)
        await self.setLocalReadiness(.preparing)
        _ = try await self.prepareResolved(descriptor)
        return .ready
      } catch let containment as InferenceCallerContainmentError {
        if await self.localAnalysisRequiresFullAppRestart() {
          return await self.preparationRestartReadiness(
            technicalDetail: containment.localizedDescription
          )
        }
        return .failed(
          userFacingMessage: "Couldn’t get on-device analysis ready. Try again.",
          technicalDetail: containment.localizedDescription
        )
      } catch is CancellationError {
        return .failed(
          userFacingMessage: "On-device analysis setup was interrupted. Try again.",
          technicalDetail: "Preparation cancelled."
        )
      } catch {
        return .failed(
          userFacingMessage: "Couldn’t get on-device analysis ready. Try again.",
          technicalDetail: error.localizedDescription
        )
      }
    }
    localReadinessTask = task
    let result = await task.value
    localReadinessTask = nil
    localReadiness = result
    return result
  }

  func retryLocalAnalysisPreparation() async -> LocalAnalysisReadiness {
    if coordinatorGate.hasQuarantinedOperation {
      let failed = preparationRestartReadiness(
        technicalDetail: "Native preparation remains quarantined until process termination."
      )
      localReadiness = failed
      return failed
    }
    guard localReadinessTask == nil else { return await prepareLocalAnalysis() }
    if let descriptor = ModelCatalog.normalFlowSelection {
      await invalidate(descriptor)
      resolvedModels[descriptor.id] = nil
      verificationTasks[descriptor.id] = nil
    }
    localReadiness = .verifying
    return await prepareLocalAnalysis()
  }

  private func setLocalReadiness(_ value: LocalAnalysisReadiness) {
    localReadiness = value
  }

  private func preparationRestartReadiness(
    technicalDetail: String
  ) -> LocalAnalysisReadiness {
    .failed(
      userFacingMessage: Self.preparationRestartMessage,
      technicalDetail: technicalDetail
    )
  }

  func receipt(for descriptor: ModelDescriptor) async throws -> ModelVerificationReceipt? {
    guard !coordinatorGate.transitionInProgress else { throw GITimelineError.operationInProgress }
    #if HACKATHON_EMBEDDED_GEMMA || APPSTORE_RELEASE
    return try await resolveVerifiedModel(for: descriptor).receipt
    #else
    return try importer.receipt(for: descriptor)
    #endif
  }

  func modelExists(for descriptor: ModelDescriptor) -> Bool {
    guard !coordinatorGate.transitionInProgress else { return false }
    let url: URL?
    #if HACKATHON_EMBEDDED_GEMMA || APPSTORE_RELEASE
    url = try? importer.bundledModelLocation(for: descriptor).url
    #else
    url = try? importer.modelURL(for: descriptor)
    #endif
    guard let url else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  func importModel(_ descriptor: ModelDescriptor) async throws -> ModelImportResult {
    try await beginModelTransition()
    defer { coordinatorGate.endTransition() }
    let worker = importer
    let result = try await Task.detached(priority: .userInitiated) {
      try worker.importModel(descriptor)
    }.value
    resolvedModels[descriptor.id] = result.verifiedModel
    if descriptor.id == ModelCatalog.normalFlowSelection?.id { localReadiness = .verifying }
    return result
  }

  func verifyInstalledModel(_ descriptor: ModelDescriptor) async throws -> VerifiedModel {
    try await beginModelTransition()
    defer { coordinatorGate.endTransition() }
    let worker = importer
    let verified = try await Task.detached(priority: .userInitiated) {
      try worker.verifyInstalledModel(descriptor)
    }.value
    resolvedModels[descriptor.id] = verified
    if descriptor.id == ModelCatalog.normalFlowSelection?.id { localReadiness = .verifying }
    return verified
  }

  func prepare(_ descriptor: ModelDescriptor) async throws -> EnginePreparationResult {
    let isNormalSelection = descriptor.id == ModelCatalog.normalFlowSelection?.id
    if coordinatorGate.hasQuarantinedOperation {
      if isNormalSelection {
        localReadiness = preparationRestartReadiness(
          technicalDetail: "Native preparation remains quarantined until process termination."
        )
      }
      throw GITimelineError.operationInProgress
    }
    do {
      _ = try await resolveVerifiedModel(for: descriptor)
      if isNormalSelection { localReadiness = .preparing }
      let result = try await prepareResolved(descriptor)
      if isNormalSelection { localReadiness = .ready }
      return result
    } catch {
      if isNormalSelection {
        localReadiness = coordinatorGate.hasQuarantinedOperation
          ? preparationRestartReadiness(technicalDetail: error.localizedDescription)
          : .failed(
            userFacingMessage: "Couldn’t get on-device analysis ready. Try again.",
            technicalDetail: error.localizedDescription
          )
      }
      throw error
    }
  }

  private func prepareResolved(_ descriptor: ModelDescriptor) async throws -> EnginePreparationResult {
    let (service, token) = try await acquireServiceLease(for: descriptor, purpose: .transient)
    guard coordinatorGate.beginContainedCall(token) else {
      coordinatorGate.release(token)
      throw GITimelineError.operationInProgress
    }
    #if DEBUG || HACKATHON_EMBEDDED_GEMMA
    let emitsRawPhotoDiagnosticMarkers = configuration.usesRawPhotoV1Schema
    let containmentDisposition = InferenceCallerContainmentDisposition { containment in
      guard emitsRawPhotoDiagnosticMarkers else { return }
      InferencePreparationContainmentTerminal.emit(containment)
    }
    let deadlineThreadObserver: (@Sendable (InferenceDeadlineThreadStage) -> Void)?
    if emitsRawPhotoDiagnosticMarkers {
      deadlineThreadObserver = { stage in
        InferencePreparationContainmentTerminal.emit(stage)
      }
    } else {
      deadlineThreadObserver = nil
    }
    #else
    let containmentDisposition = InferenceCallerContainmentDisposition()
    let deadlineThreadObserver: (@Sendable (InferenceDeadlineThreadStage) -> Void)? = nil
    #endif
    do {
      let result = try await InferenceCallerDeadlineRace.run(
        deadline: InferenceCallerDeadlineRace.preparationDeadline,
        cancelOperationOnContainment: false,
        containmentDisposition: containmentDisposition,
        deadlineThreadObserver: deadlineThreadObserver
      ) {
        try await service.prepare()
      }
      finishContainedCall(token)
      coordinatorGate.release(token)
      return result
    } catch let containment as InferenceCallerContainmentError {
      switch containment {
      case .timedOut, .callerCancelled:
        quarantineContainedCall(token)
        if descriptor.id == ModelCatalog.normalFlowSelection?.id {
          localReadiness = preparationRestartReadiness(
            technicalDetail: containment.localizedDescription
          )
        }
      case .timedOutBeforeOperationStarted, .callerCancelledBeforeOperationStarted,
        .deadlineThreadUnavailable:
        // Native preparation starts only after the deadline thread confirms it
        // is running and the start commit succeeds, so these failures remain
        // safe to retry in-process.
        finishContainedCall(token)
        coordinatorGate.release(token)
      }
      throw containment
    } catch {
      finishContainedCall(token)
      coordinatorGate.release(token)
      throw error
    }
  }

  func engineState(_ descriptor: ModelDescriptor) async -> EngineProcessState {
    // A quarantined native call can remain blocked after its caller deadline.
    // Never wait back through that service/adapter merely to render status.
    guard !coordinatorGate.hasQuarantinedOperation else {
      return .failed("native_operation_quarantined")
    }
    guard let activeService, activeService.descriptorID == descriptor.id else { return .uninitialized }
    return await activeService.service.engineState()
  }

  func analyze(_ descriptor: ModelDescriptor, draftURL: URL) async throws -> String {
    try await performContainedAnalysis(descriptor, draftURL: draftURL) { service in
      try await service.analyze(draftURL: draftURL)
    }
  }

  func analyze(
    _ descriptor: ModelDescriptor,
    draftURL: URL,
    expectedSHA256: String
  ) async throws -> String {
    try await performContainedAnalysis(descriptor, draftURL: draftURL) { service in
      try await service.analyze(
        draftURL: draftURL,
        expectedSHA256: expectedSHA256
      )
    }
  }

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  /// One-shot transport A/B for the isolated raw-photo harness. It deliberately
  /// reuses the exact prepared CPU/CPU service and outer quarantine boundary;
  /// only the pinned Conversation API differs from the shipping call.
  func analyzeSynchronouslyForDiagnostic(
    _ descriptor: ModelDescriptor,
    draftURL: URL,
    expectedSHA256: String
  ) async throws -> String {
    try await performContainedAnalysis(
      descriptor,
      draftURL: draftURL,
      quarantineOnGenerationCancellation: true
    ) { service in
      try await service.analyzeSynchronouslyForDiagnostic(
        draftURL: draftURL,
        expectedSHA256: expectedSHA256
      )
    }
  }
  #endif

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  /// Uses the existing prepared service for one approved frozen evaluation
  /// variant. Normal production configuration remains immutable and this path
  /// cannot accept an engine, sampler, or arbitrary prompt change.
  func analyzeForEvaluation(
    _ descriptor: ModelDescriptor,
    draftURL: URL,
    configuration requested: InferenceConfiguration
  ) async throws -> String {
    guard configuration.permitsEvaluationOverride(requested) else {
      throw GITimelineError.operationInProgress
    }
    return try await performContainedAnalysis(descriptor, draftURL: draftURL) { service in
      try await service.analyzeForEvaluation(
        draftURL: draftURL,
        configuration: requested
      )
    }
  }

  /// Tuning-only counterpart to the frozen evaluation API. Keeping the gate
  /// and service entry point distinct prevents a v3 tuning configuration from
  /// entering the holdout path while retaining the same containment boundary.
  func analyzeForTuning(
    _ descriptor: ModelDescriptor,
    draftURL: URL,
    configuration requested: InferenceConfiguration
  ) async throws -> String {
    guard configuration.permitsTuningOverride(requested) else {
      throw GITimelineError.operationInProgress
    }
    return try await performContainedAnalysis(descriptor, draftURL: draftURL) { service in
      try await service.analyzeForTuning(
        draftURL: draftURL,
        configuration: requested
      )
    }
  }

  /// Raw-photo prompt tuning has its own fixed override and repeats the exact
  /// shipping prepared-JPEG validation. It cannot enter the historical
  /// derived-map tuning or frozen-evaluation lanes.
  func analyzeForRawPhotoV12Tuning(
    _ descriptor: ModelDescriptor,
    draftURL: URL,
    expectedSHA256: String,
    configuration requested: InferenceConfiguration
  ) async throws -> String {
    guard configuration == requested,
      requested.usesFullPrefillCandidate,
      configuration.permitsRawPhotoV12TuningOverride(requested)
    else {
      throw GITimelineError.operationInProgress
    }
    return try await performContainedAnalysis(
      descriptor,
      draftURL: draftURL,
      deadline: InferenceCallerDeadlineRace.fullPrefillComparisonDeadline
    ) { service in
      try await service.analyzeForRawPhotoV12Tuning(
        draftURL: draftURL,
        expectedSHA256: expectedSHA256,
        configuration: requested
      )
    }
  }

  /// Exact-Data, one-call synthetic engineering seam. It is intentionally
  /// separate from every repairable product path and can run only on one of
  /// the three internal full-prefill configurations frozen by the external
  /// runtime plan. Its adapter-owned 30-second cancellation policy settles
  /// before this coordinator releases the lease.
  func runSyntheticVisionExactDataProbe(
    _ descriptor: ModelDescriptor,
    imageData: Data,
    expectedImageSHA256: String,
    promptData: Data,
    responseSchemaData: Data?,
    onModelCallStarted: @escaping @Sendable () -> Void = {},
    configuration requested: InferenceConfiguration
  ) async throws -> SyntheticVisionExactDataProbeReceipt {
    guard configuration == requested,
      requested.usesFullPrefillCandidate,
      configuration.permitsRawPhotoV12TuningOverride(requested)
    else { throw GITimelineError.operationInProgress }
    let (service, token) = try await acquireServiceLease(
      for: descriptor,
      purpose: .transient
    )
    guard coordinatorGate.beginContainedCall(token) else {
      coordinatorGate.release(token)
      throw GITimelineError.operationInProgress
    }
    do {
      let receipt = try await service.runSyntheticVisionExactDataProbe(
        imageData: imageData,
        expectedImageSHA256: expectedImageSHA256,
        promptData: promptData,
        responseSchemaData: responseSchemaData,
        onModelCallStarted: onModelCallStarted
      )
      finishContainedCall(token)
      coordinatorGate.release(token)
      return receipt
    } catch {
      finishContainedCall(token)
      coordinatorGate.release(token)
      throw error
    }
  }

  /// Blind-validation-only entry point. The app-scoped baseline still owns
  /// the prepared service and containment lease; no configuration is stored,
  /// promoted, or installed by this call.
  func analyzeForBlindValidation(
    _ descriptor: ModelDescriptor,
    draftURL: URL,
    configuration requested: InferenceConfiguration
  ) async throws -> String {
    guard configuration.permitsBlindValidationOverride(requested) else {
      throw GITimelineError.operationInProgress
    }
    return try await performContainedAnalysis(descriptor, draftURL: draftURL) { service in
      try await service.analyzeForBlindValidation(
        draftURL: draftURL,
        configuration: requested
      )
    }
  }
  #endif

  /// Both the product path and frozen-evaluation override use this exact lease,
  /// deadline, and quarantine boundary. No diagnostic route can bypass caller
  /// containment while reusing the native session.
  private func performContainedAnalysis(
    _ descriptor: ModelDescriptor,
    draftURL: URL,
    quarantineOnGenerationCancellation: Bool = false,
    deadline: Duration = InferenceCallerDeadlineRace.structuredDeadline,
    operation: @escaping @Sendable (InferenceService) async throws -> String
  ) async throws -> String {
    let emitsRawPhotoDiagnosticMarkers = configuration.usesRawPhotoV1Schema
    let (service, token) = try await acquireServiceLease(
      for: descriptor,
      purpose: .structured(draftPath: draftURL.path)
    )
    guard coordinatorGate.beginContainedCall(token) else {
      coordinatorGate.release(token)
      throw GITimelineError.operationInProgress
    }
    do {
      let response = try await InferenceCallerDeadlineRace.run(
        deadline: deadline,
        onDeadlineThreadStarted: {
          #if DEBUG || HACKATHON_EMBEDDED_GEMMA
          if emitsRawPhotoDiagnosticMarkers {
            print(AppStoreRawImageV1PreparationDiagnosticContract.nativeStageMarker(
              .outerDeadlineThreadStarted
            ))
            fflush(stdout)
          }
          #endif
        },
        onDeadline: {
          #if DEBUG || HACKATHON_EMBEDDED_GEMMA
          if emitsRawPhotoDiagnosticMarkers {
            print(AppStoreRawImageV1PreparationDiagnosticContract.nativeStageMarker(
              .outerDeadlineFired
            ))
            fflush(stdout)
          }
          #endif
        }
      ) {
        try await operation(service)
      }
      finishContainedCall(token)
      return response
    } catch let containment as InferenceCallerContainmentError {
      if containment.requiresQuarantine {
        quarantineStructuredOperation(
          token,
          descriptor: descriptor,
          cause: containment,
          telemetry: {
            #if DEBUG || HACKATHON_EMBEDDED_GEMMA
            if emitsRawPhotoDiagnosticMarkers {
              print(AppStoreRawImageV1PreparationDiagnosticContract.nativeStageMarker(
                .outerDeadlineCaught
              ))
              if quarantineOnGenerationCancellation {
                print(AppStoreRawImageV1PreparationDiagnosticContract.nativeStageMarker(
                  .synchronousQuarantined
                ))
              }
              fflush(stdout)
            }
            #endif
          }
        )
      } else {
        finishContainedCall(token)
        coordinatorGate.release(token)
      }
      throw StagedInferenceError(stage: .timeout, underlying: containment)
    } catch let staged as StagedInferenceError
      where quarantineOnGenerationCancellation && staged.stage == .timeout
    {
      quarantineStructuredOperation(
        token,
        descriptor: descriptor,
        cause: .timedOut,
        telemetry: {
          #if DEBUG || HACKATHON_EMBEDDED_GEMMA
          if emitsRawPhotoDiagnosticMarkers {
            print(AppStoreRawImageV1PreparationDiagnosticContract.nativeStageMarker(
              .synchronousQuarantined
            ))
            fflush(stdout)
          }
          #endif
        }
      )
      throw staged
    } catch is CancellationError where quarantineOnGenerationCancellation {
      quarantineStructuredOperation(
        token,
        descriptor: descriptor,
        cause: .callerCancelled,
        telemetry: {
          #if DEBUG || HACKATHON_EMBEDDED_GEMMA
          if emitsRawPhotoDiagnosticMarkers {
            print(AppStoreRawImageV1PreparationDiagnosticContract.nativeStageMarker(
              .synchronousQuarantined
            ))
            fflush(stdout)
          }
          #endif
        }
      )
      throw CancellationError()
    } catch {
      finishContainedCall(token)
      coordinatorGate.release(token)
      throw error
    }
  }

  func repair(_ descriptor: ModelDescriptor, draftURL: URL, errors: String) async throws -> String {
    guard let token = coordinatorGate.structuredToken(descriptorID: descriptor.id, draftPath: draftURL.path),
      let activeService, activeService.descriptorID == descriptor.id
    else { throw GITimelineError.missingRepairContext }
    guard coordinatorGate.beginContainedCall(token) else {
      throw GITimelineError.operationInProgress
    }
    do {
      let response = try await InferenceCallerDeadlineRace.run(
        deadline: InferenceCallerDeadlineRace.structuredDeadline
      ) {
        try await activeService.service.repair(draftURL: draftURL, errors: errors)
      }
      finishContainedCall(token)
      coordinatorGate.release(token)
      return response
    } catch let containment as InferenceCallerContainmentError {
      if containment.requiresQuarantine {
        quarantineStructuredOperation(token, descriptor: descriptor, cause: containment)
      } else {
        finishContainedCall(token)
        coordinatorGate.release(token)
      }
      throw StagedInferenceError(stage: .timeout, underlying: containment)
    } catch {
      finishContainedCall(token)
      coordinatorGate.release(token)
      throw error
    }
  }

  func discardRepairContext(_ descriptor: ModelDescriptor, draftURL: URL) async {
    guard let token = coordinatorGate.structuredToken(descriptorID: descriptor.id, draftPath: draftURL.path)
    else { return }
    // Cancellation already reaches the detached contained call. Do not await
    // the adapter or release either gate until that call cooperatively unwinds
    // or its caller deadline atomically quarantines this token.
    guard coordinatorGate.permitsRepairContextDiscard(token) else { return }
    defer { coordinatorGate.release(token) }
    guard let activeService, activeService.descriptorID == descriptor.id else { return }
    await activeService.service.discardRepairContext(draftURL: draftURL)
  }

  private func quarantineStructuredOperation(
    _ token: UUID,
    descriptor: ModelDescriptor,
    cause: InferenceCallerContainmentError,
    telemetry: (@Sendable () -> Void)? = nil
  ) {
    quarantineContainedCall(token, telemetry: telemetry)
    if descriptor.id == ModelCatalog.normalFlowSelection?.id {
      localReadiness = .failed(
        userFacingMessage: "On-device analysis didn’t finish. Continue manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it.",
        technicalDetail: cause.localizedDescription
      )
    }
  }

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  func dominantColorProbe(_ descriptor: ModelDescriptor, draftURL: URL) async throws -> String {
    let (service, token) = try await acquireServiceLease(for: descriptor, purpose: .transient)
    defer { coordinatorGate.release(token) }
    return try await service.dominantColorProbe(draftURL: draftURL)
  }
  #endif

  func invalidate(_ descriptor: ModelDescriptor) async {
    guard let activeService, activeService.descriptorID == descriptor.id else { return }
    do { try coordinatorGate.beginTransition() }
    catch { return }
    defer { coordinatorGate.endTransition() }
    let canRelease = await activeService.service.canReleaseForModelChange()
    if canRelease { self.activeService = nil }
  }

  private func beginModelTransition() async throws {
    guard localReadinessTask == nil, verificationTasks.isEmpty else {
      throw GITimelineError.operationInProgress
    }
    try coordinatorGate.beginTransition()
    if let activeService {
      guard await activeService.service.canReleaseForModelChange() else {
        coordinatorGate.endTransition()
        throw GITimelineError.operationInProgress
      }
      self.activeService = nil
    }
    resolvedModels.removeAll()
    resolvedEngineCacheSelections.removeAll()
    verificationTasks.removeAll()
  }

  private func resolveVerifiedModel(for descriptor: ModelDescriptor) async throws -> VerifiedModel {
    guard !coordinatorGate.transitionInProgress else { throw GITimelineError.operationInProgress }
    if let verified = resolvedModels[descriptor.id] { return verified }
    if let task = verificationTasks[descriptor.id] { return try await task.value }
    let worker = importer
    let task = Task.detached(priority: .userInitiated) {
      try worker.resolveVerifiedModel(for: descriptor)
    }
    verificationTasks[descriptor.id] = task
    do {
      let verified = try await task.value
      verificationTasks[descriptor.id] = nil
      resolvedModels[descriptor.id] = verified
      return verified
    } catch {
      verificationTasks[descriptor.id] = nil
      throw error
    }
  }

  private func resolveEngineCacheSelection(
    for descriptor: ModelDescriptor
  ) throws -> ModelRuntimeEngineCacheSelection {
    if engineCachePolicy.mode == .sharedModelCache {
      let resolved = try engineCachePolicy.cacheSelection(
        for: descriptor,
        configuration: configuration
      )
      resolvedEngineCacheSelections[descriptor.id] = resolved
      return resolved
    }
    if let resolved = resolvedEngineCacheSelections[descriptor.id] { return resolved }
    let resolved = try engineCachePolicy.cacheSelection(
      for: descriptor,
      configuration: configuration
    )
    resolvedEngineCacheSelections[descriptor.id] = resolved
    return resolved
  }

  /// Resolves/switches the sole service and installs the coordinator-owned
  /// operation lease before clearing any transition guard or awaiting adapter
  /// work. This closes the coordinator-to-adapter scheduling gap.
  private func acquireServiceLease(
    for descriptor: ModelDescriptor,
    purpose: RuntimeCoordinatorGate.LeasePurpose
  ) async throws -> (InferenceService, UUID) {
    guard !coordinatorGate.transitionInProgress, !coordinatorGate.hasLease else {
      throw GITimelineError.operationInProgress
    }
    let verified = try await resolveVerifiedModel(for: descriptor)

    if let activeService, activeService.descriptorID == descriptor.id {
      let token = try coordinatorGate.acquire(descriptorID: descriptor.id, purpose: purpose)
      return (activeService.service, token)
    }

    if let activeService {
      try coordinatorGate.beginTransition()
      do {
        guard await activeService.service.canReleaseForModelChange() else {
          throw GITimelineError.operationInProgress
        }
        self.activeService = nil
        let cacheSelection = try resolveEngineCacheSelection(for: descriptor)
        let service = InferenceService(
          verifiedModel: verified,
          configuration: configuration,
          cacheURL: cacheSelection.url,
          cacheProfile: cacheSelection.profile,
          cacheMode: engineCachePolicy.mode,
          cacheDisposition: cacheSelection.disposition
        )
        self.activeService = (descriptor.id, service)
        coordinatorGate.endTransition()
        // No actor suspension occurs between clearing the transition and
        // installing the operation lease, so another request cannot interleave.
        let token = try coordinatorGate.acquire(
          descriptorID: descriptor.id,
          purpose: purpose
        )
        return (service, token)
      } catch {
        coordinatorGate.endTransition()
        throw error
      }
    }

    let cacheSelection = try resolveEngineCacheSelection(for: descriptor)
    let service = InferenceService(
      verifiedModel: verified,
      configuration: configuration,
      cacheURL: cacheSelection.url,
      cacheProfile: cacheSelection.profile,
      cacheMode: engineCachePolicy.mode,
      cacheDisposition: cacheSelection.disposition
    )
    activeService = (descriptor.id, service)
    let token = try coordinatorGate.acquire(descriptorID: descriptor.id, purpose: purpose)
    return (service, token)
  }
}

extension Duration {
  var secondsDouble: Double {
    let parts = components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
  }
}
