@preconcurrency import LiteRTLM
import Foundation
import GITimelineCore

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
      #if DEBUG
      case "cpu": engineBackend = .cpu()
      #endif
      default: throw GITimelineError.operationInProgress
      }
      guard config.visionBackend == "cpu" else { throw GITimelineError.operationInProgress }
      let engineConfig = try EngineConfig(
        modelPath: model.modelURL.path,
        backend: engineBackend,
        visionBackend: .cpu(),
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

  #if DEBUG
  func sendProbeImage(path: String, prompt: String) async throws -> String {
    let token: UUID
    do { token = try inferenceGate.beginProbe() }
    catch { throw StagedInferenceError(stage: .generation, underlying: error) }
    defer { inferenceGate.finish(token) }
    let conversation = try await makeConversation()
    return try await sendImage(path: path, prompt: prompt, conversation: conversation)
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
    try await adapter.sendStructuredImage(path: draftURL.path, prompt: Self.prompt)
  }

  func repair(draftURL: URL, errors: String) async throws -> String {
    try await adapter.repair(path: draftURL.path, errors: errors)
  }

  func discardRepairContext(draftURL: URL) async {
    await adapter.discardRepairContext(path: draftURL.path)
  }

  #if DEBUG
  func dominantColorProbe(draftURL: URL) async throws -> String {
    try await adapter.sendProbeImage(path: draftURL.path, prompt: Self.dominantColorPrompt)
  }
  #endif

  #if DEBUG
  static let dominantColorPrompt = "Inspect the image pixels. Return exactly one token: BROWN, GREEN, or OTHER. Return no other text."
  #endif

  static let prompt = """
  You are the visual documentation component of a private gastrointestinal journal. Classify this bowel-movement photograph into neutral, structured visual observations. The user will review your output before saving. You are not diagnosing, determining causes, giving advice, or judging safety.

  Rules: report only visible features. Never diagnose or name any condition. Use only the allowed values below. Lighting, water, and camera processing can change apparent color. If the image is unclear or does not clearly show a bowel movement, set image_usable to false. Bristol reference: 1 hard lumps; 2 lumpy sausage; 3 sausage with cracks; 4 smooth soft sausage; 5 soft blobs; 6 mushy ragged; 7 watery.

  Return ONLY JSON, no code fences, exactly these keys and no others. Valid example:
  {"image_usable": true, "quality_issue": "none", "apparent_bristol_type": 4, "apparent_color": "brown", "form": "smooth_formed", "red_appearing_material": "not_observed", "black_tarry_appearance": "not_observed"}

  Allowed values — quality_issue: none, too_dark, blurred, obstructed, too_far, not_target_image, other. apparent_color: brown, light_brown, dark_brown, green, yellow, orange, red_appearing, black_appearing, pale_or_clay_appearing, mixed, unable_to_assess. form: hard_lumps, lumpy_formed, cracked_formed, smooth_formed, soft_blobs, mushy, watery, mixed, unable_to_assess. red_appearing_material and black_tarry_appearance: not_observed, possible, apparent, unable_to_assess. apparent_bristol_type: integer 1–7, or null.

  Consistency rules you must follow exactly: when image_usable is true, quality_issue must be "none". When image_usable is false: quality_issue must not be "none"; apparent_bristol_type must be null; and apparent_color, form, red_appearing_material, and black_tarry_appearance must all be "unable_to_assess".
  """
}

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

actor UnavailableInferenceService: TimelineInferenceServing {
  func prepare() throws -> EnginePreparationResult { throw GITimelineError.missingModelDescriptor }
  func engineState() -> EngineProcessState { .uninitialized }
  func analyze(draftURL: URL) throws -> String { throw GITimelineError.missingModelDescriptor }
  func repair(draftURL: URL, errors: String) throws -> String { throw GITimelineError.missingModelDescriptor }
  func discardRepairContext(draftURL: URL) {}
}
