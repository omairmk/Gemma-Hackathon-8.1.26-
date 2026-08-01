import Foundation

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

  #if DEBUG
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
  #endif
}

struct InferenceConfiguration: Codable, Equatable, Sendable {
  let id: String
  let engineBackend: String
  let visionBackend: String
  let maxNumTokens: Int
  let topK: Int
  let topP: Float
  let temperature: Float
  let seed: Int
  let promptVersion: String
  let imageMessageForm: String

  var label: String {
    "\(id) · \(engineBackend)/vision-\(visionBackend) · ctx \(maxNumTokens) · topK \(topK) · temp \(temperature)"
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

  #if DEBUG
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
  #endif

  #if DEBUG && targetEnvironment(simulator)
  static let runtimeDefault = simulatorCPUFallback
  #else
  static let runtimeDefault = deterministicBaseline
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

struct InferenceProvenanceSnapshot: Codable, Equatable, Sendable {
  let descriptorID: String
  let family: String
  let modelID: String
  let sourceRevision: String
  let artifactFilename: String
  let expectedSHA256: String
  let configuration: InferenceConfiguration
  let executionLocation: InferenceExecutionLocation?

  init(
    descriptor: ModelDescriptor,
    configuration: InferenceConfiguration,
    executionLocation: InferenceExecutionLocation = .currentAppLocal
  ) {
    descriptorID = descriptor.id
    family = descriptor.family
    modelID = descriptor.modelID
    sourceRevision = descriptor.sourceRevision
    artifactFilename = descriptor.artifactFilename
    expectedSHA256 = descriptor.expectedSHA256
    self.configuration = configuration
    self.executionLocation = executionLocation
  }

  var canonicalJSON: String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
  }
}

/// Durable evidence that an imported file matched one immutable descriptor.
/// Reading this receipt does not rehash a multi-gigabyte model on every view load.
struct ModelVerificationReceipt: Codable, Equatable, Sendable {
  let descriptorID: String
  let modelID: String
  let sourceRevision: String
  let artifactFilename: String
  let importedBytes: Int64
  let importedSHA256: String
  let verifiedAt: Date

  func matches(_ descriptor: ModelDescriptor) -> Bool {
    descriptorID == descriptor.id
      && modelID == descriptor.modelID
      && sourceRevision == descriptor.sourceRevision
      && artifactFilename == descriptor.artifactFilename
      && importedBytes == descriptor.expectedBytes
      && importedSHA256.caseInsensitiveCompare(descriptor.expectedSHA256) == .orderedSame
  }
}

/// A capability produced only after a descriptor-matching durable receipt and
/// installed file have been validated by ModelImporter. Runtime construction
/// consumes this value instead of accepting an arbitrary model path.
struct VerifiedModel: Sendable {
  let descriptor: ModelDescriptor
  let modelURL: URL
  let receipt: ModelVerificationReceipt

  init(validating descriptor: ModelDescriptor, modelURL: URL, receipt: ModelVerificationReceipt) throws {
    guard receipt.matches(descriptor), modelURL.lastPathComponent == descriptor.artifactFilename else {
      throw GITimelineError.invalidModelReceipt
    }
    self.descriptor = descriptor
    self.modelURL = modelURL
    self.receipt = receipt
  }
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

#if DEBUG
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

  /// Remains nil until a physical candidate passes every gate and is recorded in
  /// SELECTED_MODEL.json. Release therefore cannot infer readiness from a file.
  static let releaseSelection: ModelDescriptor? = nil

  static var normalFlowSelection: ModelDescriptor? {
    #if DEBUG
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

  var hasLease: Bool { lease != nil }

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
    guard lease?.token == token else { return }
    lease = nil
  }
}

actor ModelRuntimeCoordinator {
  private let importer: ModelImporter
  private let configuration: InferenceConfiguration
  private var activeService: (descriptorID: String, service: InferenceService)?
  private var coordinatorGate = RuntimeCoordinatorGate()

  init(
    importer: ModelImporter = ModelImporter(),
    configuration: InferenceConfiguration = .runtimeDefault
  ) {
    self.importer = importer
    self.configuration = configuration
  }

  func configurationSnapshot() -> InferenceConfiguration { configuration }

  func receipt(for descriptor: ModelDescriptor) throws -> ModelVerificationReceipt? {
    guard !coordinatorGate.transitionInProgress else { throw GITimelineError.operationInProgress }
    return try importer.receipt(for: descriptor)
  }

  func modelExists(for descriptor: ModelDescriptor) -> Bool {
    guard !coordinatorGate.transitionInProgress else { return false }
    guard let url = try? importer.modelURL(for: descriptor) else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  func importModel(_ descriptor: ModelDescriptor) async throws -> ModelImportResult {
    try await beginModelTransition()
    defer { coordinatorGate.endTransition() }
    let worker = importer
    return try await Task.detached(priority: .userInitiated) {
      try worker.importModel(descriptor)
    }.value
  }

  func verifyInstalledModel(_ descriptor: ModelDescriptor) async throws -> VerifiedModel {
    try await beginModelTransition()
    defer { coordinatorGate.endTransition() }
    let worker = importer
    return try await Task.detached(priority: .userInitiated) {
      try worker.verifyInstalledModel(descriptor)
    }.value
  }

  func prepare(_ descriptor: ModelDescriptor) async throws -> EnginePreparationResult {
    let (service, token) = try await acquireServiceLease(for: descriptor, purpose: .transient)
    defer { coordinatorGate.release(token) }
    return try await service.prepare()
  }

  func engineState(_ descriptor: ModelDescriptor) async -> EngineProcessState {
    guard let activeService, activeService.descriptorID == descriptor.id else { return .uninitialized }
    return await activeService.service.engineState()
  }

  func analyze(_ descriptor: ModelDescriptor, draftURL: URL) async throws -> String {
    let (service, token) = try await acquireServiceLease(
      for: descriptor,
      purpose: .structured(draftPath: draftURL.path)
    )
    do { return try await service.analyze(draftURL: draftURL) }
    catch {
      coordinatorGate.release(token)
      throw error
    }
  }

  func repair(_ descriptor: ModelDescriptor, draftURL: URL, errors: String) async throws -> String {
    guard let token = coordinatorGate.structuredToken(descriptorID: descriptor.id, draftPath: draftURL.path),
      let activeService, activeService.descriptorID == descriptor.id
    else { throw GITimelineError.missingRepairContext }
    defer { coordinatorGate.release(token) }
    return try await activeService.service.repair(draftURL: draftURL, errors: errors)
  }

  func discardRepairContext(_ descriptor: ModelDescriptor, draftURL: URL) async {
    guard let token = coordinatorGate.structuredToken(descriptorID: descriptor.id, draftPath: draftURL.path)
    else { return }
    defer { coordinatorGate.release(token) }
    guard let activeService, activeService.descriptorID == descriptor.id else { return }
    await activeService.service.discardRepairContext(draftURL: draftURL)
  }

  #if DEBUG
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
    try coordinatorGate.beginTransition()
    if let activeService {
      guard await activeService.service.canReleaseForModelChange() else {
        coordinatorGate.endTransition()
        throw GITimelineError.operationInProgress
      }
      self.activeService = nil
    }
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
    guard let verified = try importer.verifiedModel(for: descriptor) else {
      if activeService?.descriptorID == descriptor.id { activeService = nil }
      throw GITimelineError.modelNotVerified
    }

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
        let service = InferenceService(
          verifiedModel: verified,
          configuration: configuration,
          cacheURL: try AppFolders.modelCache(for: descriptor)
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

    let service = InferenceService(
      verifiedModel: verified,
      configuration: configuration,
      cacheURL: try AppFolders.modelCache(for: descriptor)
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
