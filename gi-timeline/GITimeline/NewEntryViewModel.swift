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
  @Published private(set) var isModelReady: Bool

  private var workflow = NewEntryWorkflow()
  private var draft: PreparedDraft?
  private var originalValidatedJSON: String?
  private let imageStore: ImageStore
  private let store: EntryStoring
  private let inference: TimelineInferenceServing
  private let analysisTimeout: Duration
  private var hasStartedInference = false

  init(imageStore: ImageStore, store: EntryStoring, inference: TimelineInferenceServing, modelReady: Bool, analysisTimeout: Duration = .seconds(30)) {
    self.imageStore = imageStore
    self.store = store
    self.inference = inference
    self.isModelReady = modelReady
    self.analysisTimeout = analysisTimeout
  }
  var canAnalyze: Bool { isModelReady && !isImportingModel && workflow.canAnalyze }
  var canSave: Bool { !isImportingModel && workflow.canSave }
  var canReplaceOrClear: Bool { !isImportingModel && workflow.canReplaceOrClear }
  var canImportModel: Bool { !isImportingModel && !hasStartedInference && !workflow.isLocked }
  var hasAnalysis: Bool { reviewedObservation != nil }
  var currentDraftURL: URL? { draft?.url }
  var safetyVisible: Bool { SafetyRules.shouldShow(redBlood: redBlood, blackTarry: blackTarry, dizziness: dizziness, severePain: severePain) }

  func loadSelection() async {
    guard canReplaceOrClear, let item = selectedItem else { return }
    let prepID = workflow.beginPreparation(); isBusy = true
    defer { isBusy = workflow.isLocked }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { throw GITimelineError.invalidImage }
      try installPrepared(data, preparationID: prepID)
    } catch { workflow.failPreparation(prepID); statusMessage = error.localizedDescription }
  }

  func prepareImageData(_ data: Data) throws {
    guard canReplaceOrClear else { return }
    let prepID = workflow.beginPreparation(); isBusy = true
    defer { isBusy = workflow.isLocked }
    do { try installPrepared(data, preparationID: prepID) }
    catch { workflow.failPreparation(prepID); statusMessage = error.localizedDescription; throw error }
  }

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
    isBusy = true; statusMessage = "Analyzing on this iPhone — no network used"
    Task {
      defer { isBusy = workflow.isLocked }
      do {
        try await inference.prepare()
        hasStartedInference = true
        let initial = try await inference.analyze(draftURL: draft.url)
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

  func save() {
    guard let draft, workflow.beginSave() else { return }
    isBusy = true
    do {
      let observationJSON = try reviewedObservation.map(ObservationParser.canonicalJSON)
      let provenance: EntryProvenance = reviewedObservation == nil ? .manual : (observationJSON == originalValidatedJSON ? .ai_unedited : .ai_edited)
      let input = EntryInput(id: UUID(), capturedAt: capturedAt, draftURL: draft.url, imageSHA256: draft.reference.sha256, redBlood: redBlood, blackTarry: blackTarry, dizziness: dizziness, severePain: severePain, note: note.isEmpty ? nil : note, provenance: provenance, reviewedAt: reviewedObservation == nil ? nil : Date(), originalAIJSON: originalValidatedJSON, reviewedJSON: observationJSON, modelID: reviewedObservation == nil ? nil : InferenceService.modelID, imageFilename: "")
      // Filename must be identical to the copied UUID, so build input once with its final id.
      let finalID = input.id
      let finalInput = EntryInput(id: finalID, capturedAt: input.capturedAt, draftURL: input.draftURL, imageSHA256: input.imageSHA256, redBlood: input.redBlood, blackTarry: input.blackTarry, dizziness: input.dizziness, severePain: input.severePain, note: input.note, provenance: input.provenance, reviewedAt: input.reviewedAt, originalAIJSON: input.originalAIJSON, reviewedJSON: input.reviewedJSON, modelID: input.modelID, imageFilename: "\(finalID.uuidString).jpg")
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
  func importStagedModel(expectedSHA256: String) async throws -> URL {
    guard canImportModel else { throw GITimelineError.operationInProgress }
    isImportingModel = true
    isBusy = true
    defer { isImportingModel = false; isBusy = workflow.isLocked }
    let imported = try await Task.detached(priority: .userInitiated) {
      try ModelImporter().importE4B(expectedSHA256: expectedSHA256)
    }.value
    isModelReady = true
    return imported
  }
  func updateReview(_ change: (VisualObservation) -> VisualObservation) { if let reviewedObservation { self.reviewedObservation = change(reviewedObservation) } }
  func sharedReset() {
    workflow.reset(); draft = nil; selectedItem = nil; selectedImage = nil; reviewedObservation = nil; originalValidatedJSON = nil; redBlood = nil; blackTarry = nil; dizziness = nil; severePain = nil; note = ""; capturedAt = Date(); statusMessage = nil; isBusy = false
  }
}
