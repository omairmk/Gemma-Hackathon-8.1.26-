import Foundation
import PhotosUI
import SwiftUI
import GITimelineCore

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
    analysisTimeout: Duration = .seconds(30)
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
  }
  var canAnalyze: Bool { isModelVerified && isEngineReady && !isImportingModel && !isPreparingModel && workflow.canAnalyze }
  var canSave: Bool { workflow.canSave }
  var canReplaceOrClear: Bool { workflow.canReplaceOrClear }
  var canPrepareModel: Bool { descriptor != nil && isModelVerified && !isEngineReady && !isImportingModel && !isPreparingModel && !workflow.isLocked }
  var canImportModel: Bool { descriptor != nil && !isImportingModel && !isPreparingModel && !isEngineReady && !workflow.isLocked }
  var hasAnalysis: Bool { reviewedObservation != nil }
  var currentDraftURL: URL? { draft?.url }
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
    return isEngineReady
      ? "Verified on disk · ready in this process"
      : "Verified on disk · not initialized in this process"
  }
  var analyzeUnavailableReason: String? {
    if descriptor == nil { return "No Gemma model is selected for this build." }
    if !isModelVerified { return "Import and verify the exact Gemma model first." }
    if !isEngineReady { return "Prepare Gemma before analyzing." }
    if workflow.draft == nil { return "Choose a photo or demo image to analyze." }
    if isImportingModel || isPreparingModel || workflow.isLocked { return "Finish the current operation first." }
    return nil
  }
  var safetyVisible: Bool { SafetyRules.shouldShow(redBlood: redBlood, blackTarry: blackTarry, dizziness: dizziness, severePain: severePain) }

  func loadSelection() async {
    guard canReplaceOrClear, let item = selectedItem else { return }
    let prepID = workflow.beginPreparation(); isBusy = true
    defer { isBusy = workflow.isLocked }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { throw GITimelineError.invalidImage }
      try installPrepared(data, preparationID: prepID)
      #if DEBUG
      selectedDemoFixture = nil
      #endif
    } catch { workflow.failPreparation(prepID); statusMessage = error.localizedDescription }
  }

  func prepareImageData(_ data: Data) throws {
    guard canReplaceOrClear else { return }
    let prepID = workflow.beginPreparation(); isBusy = true
    defer { isBusy = workflow.isLocked }
    do { try installPrepared(data, preparationID: prepID) }
    catch { workflow.failPreparation(prepID); statusMessage = error.localizedDescription; throw error }
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
      statusMessage = "Demo image ready."
    } catch {
      statusMessage = error.localizedDescription
    }
  }
  #endif

  private func installPrepared(_ data: Data, preparationID: UUID) throws {
    let prepared = try imageStore.prepare(data)
    guard let preview = UIImage(contentsOfFile: prepared.url.path) else { imageStore.deleteBestEffort(prepared.url); throw GITimelineError.invalidImage }
    let old = workflow.finishPreparation(preparationID, prepared: prepared.reference)
    guard workflow.draft?.id == prepared.reference.id else { imageStore.deleteBestEffort(prepared.url); return }
    draft = prepared; selectedImage = Image(uiImage: preview)
    if let old { imageStore.deleteBestEffort(URL(fileURLWithPath: old.path)) }
    reviewedObservation = nil; originalValidatedJSON = nil; statusMessage = nil
  }

  func analyze() {
    guard canAnalyze, let draft, let attemptID = workflow.beginAttempt() else { return }
    isBusy = true; statusMessage = "Looking at the image with Gemma"
    Task {
      defer { isBusy = workflow.isLocked }
      do {
        let initial = try await inference.analyze(draftURL: draft.url)
        statusMessage = "Formatting the result"
        let observation: VisualObservation
        do { observation = try ObservationParser.parse(initial) }
        catch {
          let repaired = try await inference.repair(draftURL: draft.url, errors: error.localizedDescription)
          observation = try ObservationParser.parse(repaired)
        }
        await inference.discardRepairContext(draftURL: draft.url)
        guard workflow.finishAttempt(attemptID) else {
          if workflow.analysisWasTimedOut { statusMessage = "AI analysis timed out — you can still save this entry manually" }
          return
        }
        reviewedObservation = observation; originalValidatedJSON = try? ObservationParser.canonicalJSON(observation); statusMessage = nil
      } catch {
        await inference.discardRepairContext(draftURL: draft.url)
        if workflow.finishAttempt(attemptID) {
          statusMessage = "AI analysis unavailable — you can still save this entry manually"
        } else if workflow.analysisWasTimedOut {
          statusMessage = "AI analysis timed out — you can still save this entry manually"
        }
      }
    }
    let timeout = analysisTimeout
    Task { [weak self] in
      try? await Task.sleep(for: timeout)
      guard let self else { return }
      self.workflow.timeoutAttempt(attemptID)
      if self.workflow.analysisWasTimedOut { self.statusMessage = "AI analysis timed out — waiting for the local engine to finish" }
      self.isBusy = self.workflow.isLocked
    }
  }

  func prepareModel() async {
    guard canPrepareModel else { return }
    isPreparingModel = true
    isBusy = true
    statusMessage = "Preparing Gemma"
    defer {
      isPreparingModel = false
      isBusy = workflow.isLocked
    }
    do {
      let result = try await inference.prepare()
      initializationSeconds = result.seconds
      isEngineReady = true
      statusMessage = nil
    } catch {
      isEngineReady = false
      statusMessage = "Local model preparation failed — you can still save manually"
    }
  }

  func refreshRuntimeReadiness(using runtime: ModelRuntimeCoordinator) async {
    guard let descriptor else { return }
    isModelVerified = (try? await runtime.receipt(for: descriptor)) != nil
    isEngineReady = await runtime.engineState(descriptor) == .ready
  }

  func save() {
    guard let draft, workflow.beginSave() else { return }
    isBusy = true
    do {
      let observationJSON = try reviewedObservation.map(ObservationParser.canonicalJSON)
      let provenance: EntryProvenance = reviewedObservation == nil ? .manual : (observationJSON == originalValidatedJSON ? .ai_unedited : .ai_edited)
      let modelProvenanceJSON = reviewedObservation.flatMap { _ in descriptor.flatMap {
        InferenceProvenanceSnapshot(
          descriptor: $0,
          configuration: configuration,
          executionLocation: executionLocation
        ).canonicalJSON
      } }
      #if DEBUG
      let demoKind = selectedDemoFixture?.rawValue
      #else
      let demoKind: String? = nil
      #endif
      let input = EntryInput(id: UUID(), capturedAt: capturedAt, draftURL: draft.url, imageSHA256: draft.reference.sha256, redBlood: redBlood, blackTarry: blackTarry, dizziness: dizziness, severePain: severePain, note: note.isEmpty ? nil : note, provenance: provenance, reviewedAt: reviewedObservation == nil ? nil : Date(), originalAIJSON: originalValidatedJSON, reviewedJSON: observationJSON, modelID: reviewedObservation == nil ? nil : descriptor?.modelID, modelProvenanceJSON: modelProvenanceJSON, demoKind: demoKind, imageFilename: "")
      // Filename must be identical to the copied UUID, so build input once with its final id.
      let finalID = input.id
      let finalInput = EntryInput(id: finalID, capturedAt: input.capturedAt, draftURL: input.draftURL, imageSHA256: input.imageSHA256, redBlood: input.redBlood, blackTarry: input.blackTarry, dizziness: input.dizziness, severePain: input.severePain, note: input.note, provenance: input.provenance, reviewedAt: input.reviewedAt, originalAIJSON: input.originalAIJSON, reviewedJSON: input.reviewedJSON, modelID: input.modelID, modelProvenanceJSON: input.modelProvenanceJSON, demoKind: input.demoKind, imageFilename: "\(finalID.uuidString).jpg")
      try store.save(finalInput, imageStore: imageStore)
      imageStore.deleteBestEffort(draft.url)
      sharedReset()
    } catch { statusMessage = error.localizedDescription; workflow.finishSave(); isBusy = workflow.isLocked }
  }

  func clear() {
    guard canReplaceOrClear else { return }
    if let draft { imageStore.deleteBestEffort(draft.url); Task { await inference.discardRepairContext(draftURL: draft.url) } }
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
  func updateReview(_ change: (VisualObservation) -> VisualObservation) { if let reviewedObservation { self.reviewedObservation = change(reviewedObservation) } }
  func sharedReset() {
    workflow.reset(); draft = nil; selectedItem = nil; selectedImage = nil; reviewedObservation = nil; originalValidatedJSON = nil; redBlood = nil; blackTarry = nil; dizziness = nil; severePain = nil; note = ""; capturedAt = Date(); statusMessage = nil; isBusy = false
    #if DEBUG
    selectedDemoFixture = nil
    #endif
  }
}
