import Foundation
import PhotosUI
import SwiftUI
import GITimelineCore

enum ReviewState: String, Sendable {
  case suggested
  case confirmed
  case edited
}

enum ReviewField: String, CaseIterable, Hashable, Sendable {
  case bristolType
  case apparentColor
  case form
  case visibleFeatures
  case imageQuality

  var title: String {
    switch self {
    case .bristolType: "Bristol type"
    case .apparentColor: "Apparent color"
    case .form: "Form"
    case .visibleFeatures: "Visible features"
    case .imageQuality: "Image quality"
    }
  }
}

struct ReviewSession: Sendable {
  let original: VisualObservation
  var reviewed: VisualObservation
  var states: [ReviewField: ReviewState]

  init(observation: VisualObservation) {
    original = observation
    reviewed = observation
    states = Dictionary(uniqueKeysWithValues: ReviewField.allCases.map { ($0, .suggested) })
  }

  var outstandingCount: Int { states.values.filter { $0 == .suggested }.count }
  var isComplete: Bool { outstandingCount == 0 }
  func state(for field: ReviewField) -> ReviewState { states[field] ?? .suggested }
}

enum EntryFlowState: Sendable {
  case empty
  case preparingPhoto(draftID: UUID)
  case reading(draftID: UUID, imageHash: String)
  case reviewing(draftID: UUID, review: ReviewSession)
  case saving(draftID: UUID)
  case saved(entryID: UUID)
  case failed(draftID: UUID?, message: String)
}

@MainActor final class NewEntryViewModel: ObservableObject {
  @Published var selectedItem: PhotosPickerItem?
  @Published var selectedImage: Image?
  @Published var capturedAt = Date()
  @Published var redBlood: SymptomFlag?
  @Published var blackTarry: SymptomFlag?
  @Published var dizziness: SymptomFlag?
  @Published var severePain: SymptomFlag?
  @Published var note = ""
  @Published var reviewedObservation: VisualObservation?
  @Published var statusMessage: String?
  @Published private(set) var flowState: EntryFlowState = .empty
  @Published private(set) var reviewSession: ReviewSession?
  @Published private(set) var isBusy = false
  @Published private(set) var isImportingModel = false
  @Published private(set) var isPreparingModel = false
  @Published private(set) var isModelVerified: Bool
  @Published private(set) var isEngineReady: Bool
  @Published private(set) var initializationSeconds: Double?
  #if DEBUG
  @Published private(set) var selectedDemoFixture: SyntheticFixture?
  #endif

  private var workflow = NewEntryWorkflow()
  private var draft: PreparedDraft?
  private var originalValidatedJSON: String?
  private var analysisTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?
  private let imageStore: ImageStore
  private let store: EntryStoring
  private let inference: TimelineInferenceServing
  private let descriptor: ModelDescriptor?
  private let configuration: InferenceConfiguration
  private let executionLocation: InferenceExecutionLocation
  private let runtimeBadgeOverride: String?
  private let modelLabelOverride: String?
  private let modelImportOperation: @Sendable (ModelDescriptor) async throws -> ModelImportResult
  private let analysisTimeout: Duration
  private let autoAnalysisEnabled: Bool

  init(
    imageStore: ImageStore,
    store: EntryStoring,
    inference: TimelineInferenceServing,
    descriptor: ModelDescriptor?,
    modelVerified: Bool,
    engineReady: Bool = false,
    configuration: InferenceConfiguration,
    executionLocation: InferenceExecutionLocation = .currentAppLocal,
    runtimeBadgeOverride: String? = nil,
    modelLabelOverride: String? = nil,
    modelImportOperation: @escaping @Sendable (ModelDescriptor) async throws -> ModelImportResult = { _ in
      throw GITimelineError.missingModelDescriptor
    },
    analysisTimeout: Duration = .seconds(30),
    autoAnalysisEnabled: Bool = false
  ) {
    self.imageStore = imageStore
    self.store = store
    self.inference = inference
    self.descriptor = descriptor
    self.isModelVerified = modelVerified
    self.isEngineReady = engineReady
    self.configuration = configuration
    self.executionLocation = executionLocation
    self.runtimeBadgeOverride = runtimeBadgeOverride
    self.modelLabelOverride = modelLabelOverride
    self.modelImportOperation = modelImportOperation
    self.analysisTimeout = analysisTimeout
    self.autoAnalysisEnabled = autoAnalysisEnabled
  }

  var canAnalyze: Bool { isModelVerified && isEngineReady && !isImportingModel && !isPreparingModel && workflow.canAnalyze }
  var canSave: Bool {
    guard workflow.canSave else { return false }
    return autoAnalysisEnabled ? (reviewSession?.isComplete == true && isReviewing) : true
  }
  var canReplaceOrClear: Bool { workflow.canReplaceOrClear }
  var canPrepareModel: Bool { descriptor != nil && isModelVerified && !isEngineReady && !isImportingModel && !isPreparingModel && !workflow.isLocked }
  var canImportModel: Bool { descriptor != nil && !isImportingModel && !isPreparingModel && !isEngineReady && !workflow.isLocked }
  var hasAnalysis: Bool { reviewedObservation != nil }
  var currentDraftURL: URL? { draft?.url }
  var outstandingReviewCount: Int { reviewSession?.outstandingCount ?? 0 }
  var savedEntryID: UUID? {
    if case .saved(let entryID) = flowState { return entryID }
    return nil
  }
  var modelLabel: String { modelLabelOverride ?? descriptor?.modelID ?? "No physically accepted model selected" }
  var modelArtifactFilename: String { descriptor?.artifactFilename ?? "No selected artifact" }
  var modelExpectedHashLabel: String { descriptor.map { "\($0.shortSHA256)…" } ?? "Unavailable" }
  var runtimeBadgeLabel: String {
    if let runtimeBadgeOverride { return runtimeBadgeOverride }
    guard let descriptor else { return "UI demo · Gemma not connected" }
    return "\(descriptor.family) · \(executionLocation.displayName)"
  }
  var modelStatusText: String {
    if runtimeBadgeOverride != nil { return "Deterministic interface test — no Gemma model was called." }
    if !isModelVerified { return "No verified selected model is available." }
    return isEngineReady ? "Verified on disk · ready in this process" : "Verified on disk · not initialized in this process"
  }
  var analysisMethodNotice: String? {
    guard configuration.usesLocalPixelBridge else { return nil }
    return "Hackathon bridge: this iPhone creates a coarse local color/shape map, then embedded Gemma organizes low-confidence Bristol, form, and color suggestions. Gemma does not receive the raw photo. Review every field before saving."
  }
  var analyzeUnavailableReason: String? {
    if descriptor == nil { return "Local analysis is not available in this build." }
    if !isModelVerified || !isEngineReady { return "Getting on-device analysis ready…" }
    if workflow.draft == nil { return "Choose a photo to begin." }
    if isImportingModel || isPreparingModel || workflow.isLocked { return "Finish the current operation first." }
    return nil
  }
  var safetyVisible: Bool { SafetyRules.shouldShow(redBlood: redBlood, blackTarry: blackTarry, dizziness: dizziness, severePain: severePain) }

  private var isReviewing: Bool {
    if case .reviewing = flowState { return true }
    return false
  }

  func startAutomaticPreparation() async {
    guard autoAnalysisEnabled, descriptor != nil else { return }
    if isModelVerified, !isEngineReady { await prepareModel() }
    if draft != nil { await beginAutomaticAnalysisIfPossible() }
  }

  func prepareAutomaticRuntime(using runtime: ModelRuntimeCoordinator, retry: Bool = false) async {
    guard autoAnalysisEnabled, descriptor != nil else { return }
    let readiness = retry
      ? await runtime.retryLocalAnalysisPreparation()
      : await runtime.prepareLocalAnalysis()
    switch readiness {
    case .ready:
      isModelVerified = true
      isEngineReady = true
      statusMessage = nil
      if draft != nil, case .reading = flowState { await beginAutomaticAnalysisIfPossible() }
    case .verifying, .preparing:
      statusMessage = "Getting on-device analysis ready…"
    case .failed(let userFacingMessage, _):
      isModelVerified = false
      isEngineReady = false
      statusMessage = userFacingMessage
      if let draft {
        flowState = .failed(draftID: draft.reference.id, message: userFacingMessage)
      }
    }
  }

  func loadSelection() async {
    guard canReplaceOrClear, let item = selectedItem else { return }
    let prepID = workflow.beginPreparation()
    flowState = .preparingPhoto(draftID: prepID)
    isBusy = true
    defer { isBusy = workflow.isLocked }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { throw GITimelineError.invalidImage }
      try installPrepared(data, preparationID: prepID)
      #if DEBUG
      selectedDemoFixture = nil
      #endif
      if autoAnalysisEnabled { await beginAutomaticAnalysisIfPossible() }
    } catch {
      workflow.failPreparation(prepID)
      statusMessage = "That photo couldn’t be prepared. Try another."
      flowState = .failed(draftID: draft?.reference.id, message: statusMessage ?? "Couldn’t prepare that photo.")
    }
  }

  func prepareImageData(_ data: Data) throws {
    guard canReplaceOrClear else { return }
    let prepID = workflow.beginPreparation()
    flowState = .preparingPhoto(draftID: prepID)
    isBusy = true
    defer { isBusy = workflow.isLocked }
    do {
      try installPrepared(data, preparationID: prepID)
      if autoAnalysisEnabled { Task { await self.beginAutomaticAnalysisIfPossible() } }
    } catch {
      workflow.failPreparation(prepID)
      statusMessage = "That photo couldn’t be prepared. Try another."
      flowState = .failed(draftID: draft?.reference.id, message: statusMessage ?? "Couldn’t prepare that photo.")
      throw error
    }
  }

  #if DEBUG
  func prepareDemoFixture(_ fixture: SyntheticFixture) {
    guard canReplaceOrClear else { return }
    do {
      try prepareImageData(fixture.verifiedBundledData())
      selectedDemoFixture = fixture
      if note.isEmpty || DemoDataPolicy.isSyntheticDemoNote(note) {
        note = "\(DemoDataPolicy.notePrefix) · \(fixture.title)"
      }
    } catch {
      statusMessage = "That demo photo couldn’t be prepared."
    }
  }
  #endif

  private func installPrepared(_ data: Data, preparationID: UUID) throws {
    let prepared = try imageStore.prepare(data)
    guard let preview = UIImage(contentsOfFile: prepared.url.path) else {
      imageStore.deleteBestEffort(prepared.url)
      throw GITimelineError.invalidImage
    }
    let old = workflow.finishPreparation(preparationID, prepared: prepared.reference)
    guard workflow.draft?.id == prepared.reference.id else {
      imageStore.deleteBestEffort(prepared.url)
      return
    }
    draft = prepared
    selectedImage = Image(uiImage: preview)
    capturedAt = Date()
    if let old { imageStore.deleteBestEffort(URL(fileURLWithPath: old.path)) }
    reviewedObservation = nil
    reviewSession = nil
    originalValidatedJSON = nil
    statusMessage = nil
    flowState = autoAnalysisEnabled
      ? .reading(draftID: prepared.reference.id, imageHash: prepared.reference.sha256)
      : .empty
  }

  private func beginAutomaticAnalysisIfPossible() async {
    guard autoAnalysisEnabled, let draft else { return }
    flowState = .reading(draftID: draft.reference.id, imageHash: draft.reference.sha256)
    statusMessage = "Reading photo"
    if !isEngineReady {
      if !isModelVerified {
        // App launch owns verification. Keep the immutable draft in the calm
        // hero state; prepareAutomaticRuntime will continue this exact draft.
        statusMessage = "Getting on-device analysis ready…"
        return
      }
      if isModelVerified { await prepareModel() }
      guard isEngineReady else {
        statusMessage = "On-device analysis isn’t ready. Try again."
        flowState = .failed(draftID: draft.reference.id, message: statusMessage ?? "On-device analysis isn’t ready.")
        return
      }
    }
    analyze()
  }

  func analyze() {
    guard canAnalyze, let draft, let attemptID = workflow.beginAttempt() else { return }
    let draftID = draft.reference.id
    let imageHash = draft.reference.sha256
    isBusy = true
    statusMessage = "Reading photo"
    flowState = .reading(draftID: draftID, imageHash: imageHash)
    let visualStart = ContinuousClock.now

    analysisTask?.cancel()
    analysisTask = Task { [weak self] in
      guard let self else { return }
      defer {
        self.isBusy = self.workflow.isLocked
        self.analysisTask = nil
      }
      do {
        let initial = try await self.inference.analyze(draftURL: draft.url)
        try Task.checkCancellation()
        let observation: VisualObservation
        do {
          observation = try ObservationParser.parse(initial)
        } catch {
          let repaired = try await self.inference.repair(draftURL: draft.url, errors: error.localizedDescription)
          try Task.checkCancellation()
          observation = try ObservationParser.parse(repaired)
        }
        await self.inference.discardRepairContext(draftURL: draft.url)
        let elapsed = visualStart.duration(to: .now)
        let minimum = Duration.milliseconds(900)
        if elapsed < minimum { try await Task.sleep(for: minimum - elapsed) }
        guard self.workflow.finishAttempt(attemptID),
          self.draft?.reference.id == draftID,
          self.draft?.reference.sha256 == imageHash,
          case .reading(draftID, imageHash) = self.flowState
        else {
          if self.workflow.analysisWasTimedOut {
            self.statusMessage = "Couldn’t read that photo. Try another."
            self.flowState = .failed(draftID: self.draft?.reference.id, message: self.statusMessage ?? "Couldn’t read that photo.")
          }
          return
        }
        let session = ReviewSession(observation: observation)
        self.reviewedObservation = observation
        self.reviewSession = session
        self.originalValidatedJSON = try? ObservationParser.canonicalJSON(observation)
        self.statusMessage = nil
        self.flowState = .reviewing(draftID: draftID, review: session)
      } catch {
        await self.inference.discardRepairContext(draftURL: draft.url)
        let ownsAttempt = self.workflow.finishAttempt(attemptID)
        guard self.draft?.reference.id == draftID,
          self.draft?.reference.sha256 == imageHash
        else { return }
        if !ownsAttempt {
          guard self.workflow.analysisWasTimedOut else { return }
          self.statusMessage = "Couldn’t read that photo. Try another."
          self.flowState = .failed(draftID: draftID, message: self.statusMessage ?? "Couldn’t read that photo.")
          return
        }
        self.statusMessage = "Couldn’t read that photo. Try another."
        self.flowState = .failed(draftID: draftID, message: self.statusMessage ?? "Couldn’t read that photo.")
      }
    }

    timeoutTask?.cancel()
    let timeout = analysisTimeout
    timeoutTask = Task { [weak self] in
      try? await Task.sleep(for: timeout)
      guard let self, !Task.isCancelled else { return }
      self.workflow.timeoutAttempt(attemptID)
      if self.workflow.analysisWasTimedOut {
        self.statusMessage = "Reading is taking longer than expected."
      }
      self.isBusy = self.workflow.isLocked
    }
  }

  func cancelReading() {
    guard let draft else { return }
    analysisTask?.cancel()
    timeoutTask?.cancel()
    invalidateWorkflowKeepingDraft(draft)
    Task { await inference.discardRepairContext(draftURL: draft.url) }
    isBusy = false
    statusMessage = "Photo kept. You can try again or choose another."
    flowState = .failed(draftID: draft.reference.id, message: statusMessage ?? "Photo kept.")
  }

  func retryAnalysis() {
    guard draft != nil, canReplaceOrClear else { return }
    Task { await beginAutomaticAnalysisIfPossible() }
  }

  private func invalidateWorkflowKeepingDraft(_ currentDraft: PreparedDraft) {
    var fresh = NewEntryWorkflow()
    let preparationID = fresh.beginPreparation()
    _ = fresh.finishPreparation(preparationID, prepared: currentDraft.reference)
    workflow = fresh
  }

  func prepareModel() async {
    guard canPrepareModel else { return }
    isPreparingModel = true
    statusMessage = autoAnalysisEnabled ? "Getting on-device analysis ready…" : "Preparing Gemma"
    defer { isPreparingModel = false }
    do {
      let result = try await inference.prepare()
      initializationSeconds = result.seconds
      isEngineReady = true
      statusMessage = nil
    } catch {
      isEngineReady = false
      statusMessage = autoAnalysisEnabled ? "On-device analysis isn’t ready. Try again." : "Local model preparation failed — you can still save manually"
    }
  }

  func refreshRuntimeReadiness(using runtime: ModelRuntimeCoordinator) async {
    guard let descriptor else { return }
    isModelVerified = (try? await runtime.receipt(for: descriptor)) != nil
    isEngineReady = await runtime.engineState(descriptor) == .ready
  }

  func reviewState(for field: ReviewField) -> ReviewState {
    reviewSession?.state(for: field) ?? .suggested
  }

  func confirmReviewField(_ field: ReviewField) {
    guard var session = reviewSession else { return }
    session.states[field] = fieldWasEdited(field, in: session) ? .edited : .confirmed
    apply(session)
  }

  func updateReview(field: ReviewField, _ change: (VisualObservation) -> VisualObservation) {
    guard var session = reviewSession else { return }
    session.reviewed = change(session.reviewed)
    session.states[field] = fieldWasEdited(field, in: session) ? .edited : .confirmed
    apply(session)
  }

  /// Retained for the developer harness; the normal UI reviews fields individually.
  func updateReview(_ change: (VisualObservation) -> VisualObservation) {
    guard var session = reviewSession else {
      if let reviewedObservation { self.reviewedObservation = change(reviewedObservation) }
      return
    }
    session.reviewed = change(session.reviewed)
    for field in ReviewField.allCases {
      session.states[field] = fieldWasEdited(field, in: session) ? .edited : .confirmed
    }
    apply(session)
  }

  private func apply(_ session: ReviewSession) {
    reviewSession = session
    reviewedObservation = session.reviewed
    if let draft {
      flowState = .reviewing(draftID: draft.reference.id, review: session)
    }
  }

  private func fieldWasEdited(_ field: ReviewField, in session: ReviewSession) -> Bool {
    let lhs = session.original
    let rhs = session.reviewed
    switch field {
    case .bristolType: return lhs.apparentBristolType != rhs.apparentBristolType
    case .apparentColor: return lhs.apparentColor != rhs.apparentColor
    case .form: return lhs.form != rhs.form
    case .visibleFeatures:
      return lhs.redAppearingMaterial != rhs.redAppearingMaterial || lhs.blackTarryAppearance != rhs.blackTarryAppearance
    case .imageQuality:
      return lhs.imageUsable != rhs.imageUsable || lhs.qualityIssue != rhs.qualityIssue
    }
  }

  func save() {
    guard let draft, canSave, workflow.beginSave() else { return }
    isBusy = true
    flowState = .saving(draftID: draft.reference.id)
    do {
      let observationJSON = try reviewedObservation.map(ObservationParser.canonicalJSON)
      let provenance: EntryProvenance = reviewedObservation == nil ? .manual : (observationJSON == originalValidatedJSON ? .ai_unedited : .ai_edited)
      let modelProvenanceJSON = reviewedObservation.flatMap { _ in descriptor.flatMap {
        InferenceProvenanceSnapshot(descriptor: $0, configuration: configuration, executionLocation: executionLocation).canonicalJSON
      } }
      #if DEBUG
      let demoKind = selectedDemoFixture?.rawValue
      #else
      let demoKind: String? = nil
      #endif
      let finalID = UUID()
      let input = EntryInput(
        id: finalID,
        capturedAt: capturedAt,
        draftURL: draft.url,
        imageSHA256: draft.reference.sha256,
        redBlood: redBlood,
        blackTarry: blackTarry,
        dizziness: dizziness,
        severePain: severePain,
        note: note.isEmpty ? nil : note,
        provenance: provenance,
        reviewedAt: reviewedObservation == nil ? nil : Date(),
        originalAIJSON: originalValidatedJSON,
        reviewedJSON: observationJSON,
        modelID: reviewedObservation == nil ? nil : descriptor?.modelID,
        modelProvenanceJSON: modelProvenanceJSON,
        demoKind: demoKind,
        imageFilename: "\(finalID.uuidString).jpg"
      )
      try store.save(input, imageStore: imageStore)
      imageStore.deleteBestEffort(draft.url)
      if autoAnalysisEnabled {
        resetFormContent()
        flowState = .saved(entryID: finalID)
      } else {
        sharedReset()
      }
    } catch {
      statusMessage = error.localizedDescription
      workflow.finishSave()
      isBusy = workflow.isLocked
      flowState = .failed(draftID: draft.reference.id, message: "Couldn’t save this entry. Your review is still here.")
    }
  }

  func retrySave() {
    guard let draft, reviewSession?.isComplete == true else { return }
    flowState = .reviewing(draftID: draft.reference.id, review: reviewSession!)
    save()
  }

  func startAnotherEntry() { sharedReset() }

  func clear() {
    guard canReplaceOrClear else { return }
    analysisTask?.cancel()
    timeoutTask?.cancel()
    if let draft {
      imageStore.deleteBestEffort(draft.url)
      Task { await inference.discardRepairContext(draftURL: draft.url) }
    }
    sharedReset()
  }

  func importStagedModel() async throws -> ModelImportResult {
    guard canImportModel, let descriptor else { throw GITimelineError.missingModelDescriptor }
    isImportingModel = true
    isBusy = true
    defer { isImportingModel = false; isBusy = workflow.isLocked }
    let imported = try await modelImportOperation(descriptor)
    isModelVerified = true
    isEngineReady = false
    return imported
  }

  private func resetFormContent() {
    workflow.reset()
    draft = nil
    selectedItem = nil
    selectedImage = nil
    reviewedObservation = nil
    reviewSession = nil
    originalValidatedJSON = nil
    redBlood = nil
    blackTarry = nil
    dizziness = nil
    severePain = nil
    note = ""
    capturedAt = Date()
    statusMessage = nil
    isBusy = false
    #if DEBUG
    selectedDemoFixture = nil
    #endif
  }

  func sharedReset() {
    resetFormContent()
    flowState = .empty
  }
}
