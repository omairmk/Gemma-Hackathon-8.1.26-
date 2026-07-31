@preconcurrency import LiteRTLM
import Foundation
import GITimelineCore

protocol TimelineInferenceServing: Sendable {
  func prepare() async throws
  func analyze(draftURL: URL) async throws -> String
  func repair(draftURL: URL, errors: String) async throws -> String
  func discardRepairContext(draftURL: URL) async
}

actor InferenceService: TimelineInferenceServing {
  static let modelID = "litert-community/gemma-4-E4B-it-litert-lm"
  private var engine: Engine?
  private var pendingRepair: (draftPath: String, conversation: Conversation)?
  private let modelURL: URL
  private let cacheURL: URL

  init(modelURL: URL, cacheURL: URL) { self.modelURL = modelURL; self.cacheURL = cacheURL }

  func prepare() async throws { _ = try await initializedEngine() }

  func analyze(draftURL: URL) async throws -> String {
    let engine = try await initializedEngine()
    let conversation = try await makeConversation(engine: engine)
    pendingRepair = (draftURL.path, conversation)
    do {
      let response = try await conversation.sendMessage(Message(of: .imageFile(draftURL.path), .text(Self.prompt)))
      return response.toString
    } catch {
      pendingRepair = nil
      throw error
    }
  }

  func repair(draftURL: URL, errors: String) async throws -> String {
    guard let pendingRepair, pendingRepair.draftPath == draftURL.path else { throw GITimelineError.missingRepairContext }
    self.pendingRepair = nil
    let prompt = "Your previous reply was not valid JSON with exactly the required keys, allowed values, and consistency rules. Errors: \(errors). Return only the corrected JSON."
    return try await pendingRepair.conversation.sendMessage(Message(prompt)).toString
  }

  func discardRepairContext(draftURL: URL) {
    if pendingRepair?.draftPath == draftURL.path { pendingRepair = nil }
  }

  private func makeConversation(engine: Engine) async throws -> Conversation {
    // Each analysis gets a fresh conversation; its one optional repair stays in that conversation.
    let sampler = try SamplerConfig(topK: 1, topP: 1, temperature: 0, seed: 0)
    return try await engine.createConversation(with: ConversationConfig(samplerConfig: sampler))
  }

  private func initializedEngine() async throws -> Engine {
    if let engine { return engine }
    let config = try EngineConfig(modelPath: modelURL.path, backend: .gpu, visionBackend: .cpu(), maxNumTokens: 2048, cacheDir: cacheURL.path)
    let newEngine = Engine(engineConfig: config)
    try await newEngine.initialize()
    engine = newEngine
    return newEngine
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

actor MockInferenceService: TimelineInferenceServing {
  enum Script { case response(String), malformed(String), slow(String, nanoseconds: UInt64) }
  var scripts: [Script]
  private let failPrepare: Bool
  init(scripts: [Script], failPrepare: Bool = false) { self.scripts = scripts; self.failPrepare = failPrepare }
  func prepare() throws { if failPrepare { throw CocoaError(.fileReadCorruptFile) } }
  func analyze(draftURL: URL) async throws -> String {
    guard !scripts.isEmpty else { throw CocoaError(.fileNoSuchFile) }
    switch scripts.removeFirst() { case .response(let value), .malformed(let value): return value; case .slow(let value, let delay): try await Task.sleep(nanoseconds: delay); return value }
  }
  func repair(draftURL: URL, errors: String) async throws -> String { try await analyze(draftURL: draftURL) }
  func discardRepairContext(draftURL: URL) {}
}
