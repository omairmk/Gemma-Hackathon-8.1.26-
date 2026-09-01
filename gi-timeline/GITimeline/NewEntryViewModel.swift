import Foundation
import PhotosUI
import SwiftUI
import GITimelineCore

enum ReviewState: String, Sendable, Equatable {
  case suggested
  case confirmed
  case edited
}

enum PhotoSubjectConfirmation: String, Codable, CaseIterable, Sendable {
  case yes
  case no
  case notClear = "not_clear"
}

enum ReviewField: String, CaseIterable, Hashable, Sendable {
  case bristolType
  case mixedForm
  case photoUsable

  var title: String {
    switch self {
    case .bristolType: "Bristol type"
    case .mixedForm: "Mixed form"
    case .photoUsable: "Photo usability"
    }
  }
}

struct ReviewSession: Sendable, Equatable {
  let original: VisualObservation
  var reviewed: VisualObservation
  let originalMixedForm: ClinicalTriState
  var reviewedMixedForm: ClinicalTriState?
  var states: [ReviewField: ReviewState]

  init(observation: VisualObservation) {
    original = observation
    reviewed = observation
    originalMixedForm = ClinicalValidation.initialMixedFormSuggestion(from: observation) ?? .unsure
    reviewedMixedForm = originalMixedForm
    // Gemma prefills one editable entry. The person's final Save action is the
    // single confirmation; no per-field confirmation taps are required.
    states = Dictionary(uniqueKeysWithValues: ReviewField.allCases.map { ($0, .confirmed) })
  }

  var outstandingCount: Int { states.values.filter { $0 == .suggested }.count }
  var isComplete: Bool { outstandingCount == 0 }
  func state(for field: ReviewField) -> ReviewState { states[field] ?? .suggested }
}

enum EntryFlowState: Sendable, Equatable {
  case empty
  case preparingPhoto(draftID: UUID)
  case confirmingSubject(draftID: UUID)
  case reading(draftID: UUID, imageHash: String)
  case reviewing(draftID: UUID, review: ReviewSession)
  case manual(draftID: UUID?)
  case saving(draftID: UUID?)
  case saved(entryID: UUID)
  case failed(draftID: UUID?, message: String)
}

private enum DraftSnapshotPersistenceError: LocalizedError {
  case couldNotProtect

  var errorDescription: String? {
    "Your unfinished entry could not be protected locally. The previous draft was kept unchanged."
  }
}

/// Mutable form state that must be restored exactly if a proposed photo cannot
/// first acquire a durable snapshot. The image file itself is staged outside
/// this value and is removed only after restoring this state.
private struct NewEntryDraftPresentationState {
  let workflow: NewEntryWorkflow
  let flowState: EntryFlowState
  let isBusy: Bool
  let draft: PreparedDraft?
  let selectedItem: PhotosPickerItem?
  let selectedImage: Image?
  let capturedAt: Date
  let confirmedStoolPresence: StoolPresence?
  let confirmedBristolType: Int?
  let confirmedForm: String?
  let confirmedApparentColor: String?
  let confirmedPhotoUsable: Bool?
  let confirmedRetakeReason: PhotoRetakeReason?
  let subjectConfirmation: PhotoSubjectConfirmation?
  let mixedForm: ClinicalTriState?
  let painScore: Int?
  let urgency: UrgencyLevel?
  let strainingOrIncomplete: ClinicalTriState?
  let leakageOrAccident: ClinicalTriState?
  let redBlood: SymptomFlag?
  let blackAppearance: SymptomFlag?
  let blackTarry: SymptomFlag?
  let dizziness: SymptomFlag?
  let severePain: SymptomFlag?
  let note: String
  let reviewedObservation: VisualObservation?
  let reviewSession: ReviewSession?
  let originalValidatedJSON: String?
  let fullPrefillNormalization: FullPrefillNormalizationReceiptV1?
  let photoSuggestionEngineReceiptJSON: String?
  let aiReadHints: [String: String]
  let photoQualityRecommendation: PhotoQualityRecommendation?
  let retainedLowQualityManualReview: Bool
  let modelSuggestedImageSHA256: String?
  let modelSuggestedAt: Date?
  let generationStartedAt: Date?
  let generationEndedAt: Date?
  let inferenceParsePath: InferenceParsePath?
  let analysisSource: AnalysisSource
  let analysisPipelineVersion: String?
  let didChooseBristolType: Bool
  let didChooseMixedForm: Bool
  let didReviewPhotoUsability: Bool
  let manualEntryCapturedAtBaseline: Date?
  let pendingEntryID: UUID?
  let pendingEntryFingerprint: String?
  let pendingReviewedAt: Date?
  let statusMessage: String?
}

/// Identifies the exact automatic-photo state that asked the provider-neutral
/// engine to initialize. Native initialization may outlive Swift task
/// cancellation, so its completion is useful only while this exact draft is
/// still at the automatic-reading boundary.
private struct PhotoSuggestionPreparationContext: Equatable {
  let token: UUID
  let draftID: UUID
  let imageHash: String
}

/// Authorizes exactly one queued automatic-analysis start for the retained
/// photo. Lifecycle transitions revoke it before they publish manual state, so
/// a task that was queued before the transition cannot recreate Reading.
private struct AutomaticAnalysisContext: Equatable {
  let token: UUID
  let draftID: UUID
  let imageHash: String
}

/// A PhotosPicker transfer can also outlive the privacy boundary that started
/// it. The token lets its eventual data be retained manually without allowing
/// a stale transfer to install into a later entry.
private struct PhotoTransferContext {
  let token: UUID
  let preparationID: UUID
  /// Captured before the workflow enters `.preparingPhoto`. It remains the
  /// foreground rollback target; delayed/manualized completion promotes the
  /// then-current manual presentation so later edits are never lost.
  let previousPresentationState: NewEntryDraftPresentationState
}

private struct PhotoTransferCompletion {
  let retainingManualDraft: Bool
  let rollbackPresentationState: NewEntryDraftPresentationState
}

@MainActor final class NewEntryViewModel: ObservableObject {
  @Published var selectedItem: PhotosPickerItem?
  @Published var selectedImage: Image?
  @Published var capturedAt = Date() { didSet { persistDraftSnapshotIfPossible() } }
  @Published var confirmedStoolPresence: StoolPresence? {
    didSet { persistDraftSnapshotIfPossible() }
  }
  @Published var confirmedBristolType: Int? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var confirmedForm: String? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var confirmedApparentColor: String? {
    didSet { persistDraftSnapshotIfPossible() }
  }
  @Published var confirmedPhotoUsable: Bool? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var confirmedRetakeReason: PhotoRetakeReason? {
    didSet { persistDraftSnapshotIfPossible() }
  }
  @Published var subjectConfirmation: PhotoSubjectConfirmation? {
    didSet { persistDraftSnapshotIfPossible() }
  }
  @Published var mixedForm: ClinicalTriState? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var painScore: Int? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var urgency: UrgencyLevel? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var strainingOrIncomplete: ClinicalTriState? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var leakageOrAccident: ClinicalTriState? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var redBlood: SymptomFlag? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var blackAppearance: SymptomFlag? {
    didSet { persistDraftSnapshotIfPossible() }
  }
  @Published var blackTarry: SymptomFlag? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var dizziness: SymptomFlag? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var severePain: SymptomFlag? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var note = "" { didSet { persistDraftSnapshotIfPossible() } }
  @Published var reviewedObservation: VisualObservation? { didSet { persistDraftSnapshotIfPossible() } }
  @Published var statusMessage: String?
  @Published private(set) var flowState: EntryFlowState = .empty
  @Published private(set) var reviewSession: ReviewSession?
  @Published private(set) var isBusy = false
  @Published private(set) var isImportingModel = false
  @Published private(set) var isPreparingModel = false
  @Published private(set) var isModelVerified: Bool
  @Published private(set) var isEngineReady: Bool
  @Published private(set) var initializationSeconds: Double?
  @Published private(set) var analysisSource: AnalysisSource = .manual
  @Published private(set) var analysisPipelineVersion: String?
  @Published private(set) var draftRestorationNotice: String?
  @Published private(set) var canDiscardUnavailableDraft = false
  @Published private(set) var savedSafetyGuidance: SafetyGuidance = .none
  /// True whenever a local recovery record exists but cannot be safely read or
  /// cleaned. While set, no normal entry action may overwrite that record.
  @Published private(set) var isDraftRecoveryBlocked = false
  /// Set only when cancelling the coordinated native runtime quarantines the
  /// process. A later photo may still be logged manually, but another model
  /// request must wait for a genuinely new app process.
  @Published private(set) var requiresFullAppRestart = false
  /// Per-category AI-suggestion text for the provider-neutral (V2) photo
  /// review only. The text records the model's original appearance answer and
  /// remains unchanged when the person edits the associated control. Keyed by
  /// control: "apparentColor", "redMaterial", "blackAppearance",
  /// "blackTarry", "bristol", "subject", "mixedForm". Ephemeral: derived
  /// fresh from each provider-neutral analysis and cleared wherever that
  /// analysis state is cleared; never persisted in the draft snapshot.
  @Published private(set) var aiReadHints: [String: String] = [:]
  /// Deterministic, pre-model quality advice for the exact retained photo.
  /// Hard advice owns the existing failure/manual continuation surface;
  /// borderline advice remains lightweight while automatic analysis proceeds.
  @Published private(set) var photoQualityRecommendation:
    PhotoQualityRecommendation? = nil
  #if DEBUG
  @Published private(set) var selectedDemoFixture: SyntheticFixture?
  #endif

  private var workflow = NewEntryWorkflow()
  private var draft: PreparedDraft?
  private var originalValidatedJSON: String?
  private var fullPrefillNormalization: FullPrefillNormalizationReceiptV1?
  private var photoSuggestionEngineReceiptJSON: String?
  private var modelSuggestion: StoredModelVisualSuggestion?
  private var modelSuggestedImageSHA256: String?
  private var modelSuggestedAt: Date?
  private var generationStartedAt: Date?
  private var generationEndedAt: Date?
  private var inferenceParsePath: InferenceParsePath?
  private var analysisTask: Task<Void, Never>?
  private var analysisTaskID: UUID?
  private var timeoutTask: Task<Void, Never>?
  private var photoSuggestionPreparation: PhotoSuggestionPreparationContext?
  private var photoSuggestionPreparationTask: Task<PhotoSuggestionEngineIdentity, Error>?
  private var photoSuggestionPreparationDeadlineTask: Task<Void, Never>?
  private var automaticAnalysisContext: AutomaticAnalysisContext?
  private var photoTransfer: PhotoTransferContext?
  private var photoTransferDeadlineTask: Task<Void, Never>?
  private var manualPhotoTransferToken: UUID?
  private let imageStore: ImageStore
  private let draftSnapshotStore: DraftSnapshotStore
  private let store: EntryStoring
  private let inference: TimelineInferenceServing
  private let photoSuggestionEngine: PhotoSuggestionEngine?
  private var preparedPhotoSuggestionEngineIdentity: PhotoSuggestionEngineIdentity?
  private let descriptor: ModelDescriptor?
  private let configuration: InferenceConfiguration
  private let executionLocation: InferenceExecutionLocation
  private let runtimeBadgeOverride: String?
  private let modelLabelOverride: String?
  private let modelImportOperation: @Sendable (ModelDescriptor) async throws -> ModelImportResult
  private let analysisTimeout: Duration
  private let preparationTimeout: Duration
  private let preparationHandoff: @Sendable () async -> Void
  private let automaticAnalysisHandoff: @Sendable () async -> Void
  private let autoAnalysisEnabled: Bool
  private var didChooseBristolType = false
  private var didChooseMixedForm = false
  private var didReviewPhotoUsability = false
  /// Durable presentation choice made after a deterministic hard-quality
  /// stop. This is deliberately separate from the recommendation itself,
  /// which is dismissed when the complete manual form opens.
  private var retainedLowQualityManualReview = false
  private var suppressDraftSnapshotPersistence = false
  /// Persisted inside every meaningful draft before the first database save.
  /// It survives a process interruption between database commit and cleanup.
  private var pendingEntryID: UUID?
  private var pendingEntryFingerprint: String?
  private var pendingReviewedAt: Date?
  private let postCommitCleanupInterruption: @MainActor () -> Bool
  /// Separates a person-edited no-photo timestamp from the default timestamp
  /// assigned when the otherwise pristine manual form opens.
  private var manualEntryCapturedAtBaseline: Date?

  init(
    imageStore: ImageStore,
    draftSnapshotStore: DraftSnapshotStore? = nil,
    store: EntryStoring,
    inference: TimelineInferenceServing,
    photoSuggestionEngine: PhotoSuggestionEngine? = nil,
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
    preparationTimeout: Duration = .seconds(15),
    preparationHandoff: @escaping @Sendable () async -> Void = {},
    automaticAnalysisHandoff: @escaping @Sendable () async -> Void = {},
    autoAnalysisEnabled: Bool = false,
    postCommitCleanupInterruption: @escaping @MainActor () -> Bool = { false }
  ) {
    self.imageStore = imageStore
    self.draftSnapshotStore = draftSnapshotStore ?? DraftSnapshotStore(imageStore: imageStore)
    self.store = store
    self.inference = inference
    self.photoSuggestionEngine = photoSuggestionEngine
    self.descriptor = descriptor
    self.isModelVerified = modelVerified
    self.isEngineReady = engineReady
    self.configuration = configuration
    self.executionLocation = executionLocation
    self.runtimeBadgeOverride = runtimeBadgeOverride
    self.modelLabelOverride = modelLabelOverride
    self.modelImportOperation = modelImportOperation
    self.analysisTimeout = analysisTimeout
    self.preparationTimeout = preparationTimeout
    self.preparationHandoff = preparationHandoff
    self.automaticAnalysisHandoff = automaticAnalysisHandoff
    self.autoAnalysisEnabled = autoAnalysisEnabled
    self.postCommitCleanupInterruption = postCommitCleanupInterruption
  }

  deinit {
    photoSuggestionPreparationTask?.cancel()
    photoSuggestionPreparationDeadlineTask?.cancel()
    photoTransferDeadlineTask?.cancel()
  }

  /// Reopens only a complete, hash-validated local draft. A request that was
  /// interrupted while Gemma was reading is restored as manual review rather
  /// than being re-run or allowed to overwrite newer user input.
  func restoreUnfinishedDraftIfAvailable() {
    handleDraftRestoreResult(draftSnapshotStore.restore())
  }

  private func handleDraftRestoreResult(_ result: DraftSnapshotRestoreResult) {
    switch result {
    case .none:
      draftRestorationNotice = nil
      canDiscardUnavailableDraft = false
      isDraftRecoveryBlocked = false
      return
    case .temporarilyUnavailable(let message):
      draftRestorationNotice = message
      canDiscardUnavailableDraft = false
      isDraftRecoveryBlocked = true
      return
    case .unavailable(let message):
      draftRestorationNotice = message
      canDiscardUnavailableDraft = true
      isDraftRecoveryBlocked = true
      return
    case .pendingTransaction(let snapshot):
      guard let pendingEntryID = snapshot.pendingEntryID,
        let pendingEntryFingerprint = snapshot.pendingEntryFingerprint
      else {
        blockCommittedDraftCleanup(
          "GI Journal found an incomplete local save transaction and kept its transaction files unchanged."
        )
        return
      }
      do {
        switch try store.pendingTransactionState(
          id: pendingEntryID,
          fingerprint: pendingEntryFingerprint,
          imageStore: imageStore
        ) {
        case .exactDurable:
          do {
            try draftSnapshotStore.finishCommittedTransactionCleanup(snapshot)
            draftRestorationNotice = nil
            canDiscardUnavailableDraft = false
            isDraftRecoveryBlocked = false
          } catch {
            blockCommittedDraftCleanup(
              "Your exact saved entry is safe, but its unfinished-draft cleanup could not finish. Try reopening the unfinished entry; unrelated local files were not removed."
            )
          }
        case .absent:
          // The process stopped before commit. Only now require and validate
          // the referenced draft JPEG for ordinary unfinished-entry restore.
          handleDraftRestoreResult(draftSnapshotStore.materializePendingDraft(snapshot))
        case .conflictOrIncomplete:
          blockCommittedDraftCleanup(
            "A saved entry with this local transaction identity did not exactly match the pending draft. The saved entry and pending draft were left unchanged."
          )
        }
      } catch {
        blockCommittedDraftCleanup(
          "GI Journal could not verify a saved journal transaction before reopening its local draft. The local transaction files were kept unchanged."
        )
      }
      return
    case .restored(let snapshot, let url, let image):
      withDraftSnapshotPersistenceSuppressed {
        photoQualityRecommendation = snapshot.photoQualityRecommendation
        retainedLowQualityManualReview =
          snapshot.retainedLowQualityManualReview == true
        let restoredModelBackedDraft = snapshot.analysisSource != .manual
          || snapshot.originalValidatedJSON != nil
          || snapshot.review != nil
          || snapshot.reviewedObservation != nil
          || snapshot.analysisPipelineVersion != nil
        var restoredWorkflow = NewEntryWorkflow()
        let reference: DraftReference?
        if let snapshotDraft = snapshot.draft,
          let url,
          let image
        {
          let photoReference = DraftReference(id: snapshotDraft.id, path: url.path, sha256: snapshotDraft.sha256)
          let preparationID = restoredWorkflow.beginPreparation()
          _ = restoredWorkflow.finishPreparation(preparationID, prepared: photoReference)
          draft = PreparedDraft(reference: photoReference, url: url)
          selectedImage = Image(uiImage: image)
          manualEntryCapturedAtBaseline = nil
          reference = photoReference
        } else {
          _ = restoredWorkflow.beginManualEntry(keepingDraft: false)
          draft = nil
          selectedImage = nil
          manualEntryCapturedAtBaseline = snapshot.capturedAt
          reference = nil
        }
        workflow = restoredWorkflow
        capturedAt = snapshot.capturedAt
        confirmedStoolPresence = snapshot.confirmedStoolPresence
        confirmedBristolType = snapshot.confirmedBristolType
        confirmedForm = snapshot.confirmedForm
        confirmedApparentColor = snapshot.confirmedApparentColor
          ?? snapshot.review?.reviewed.apparentColor
        confirmedPhotoUsable = snapshot.confirmedPhotoUsable
        confirmedRetakeReason = snapshot.confirmedRetakeReason
        subjectConfirmation = snapshot.subjectConfirmation
        mixedForm = snapshot.mixedForm
        painScore = snapshot.painScore
        urgency = snapshot.urgency
        strainingOrIncomplete = snapshot.strainingOrIncomplete
        leakageOrAccident = snapshot.leakageOrAccident
        redBlood = snapshot.redBlood
        blackAppearance = snapshot.blackAppearance
        blackTarry = snapshot.blackTarry
        dizziness = snapshot.dizziness
        severePain = snapshot.severePain
        note = snapshot.note
        originalValidatedJSON = snapshot.originalValidatedJSON
        fullPrefillNormalization = snapshot.fullPrefillNormalization
        photoSuggestionEngineReceiptJSON =
          snapshot.photoSuggestionEngineReceiptJSON
        modelSuggestion = snapshot.originalValidatedJSON.flatMap { raw in
          try? Self.resolvedModelSuggestion(
            raw: raw,
            normalization: snapshot.fullPrefillNormalization
          )
        }
        if snapshot.analysisSource == .onDevicePhotoSuggestion,
          let raw = snapshot.originalValidatedJSON,
          let rawData = raw.data(using: .utf8),
          let receiptJSON = snapshot.photoSuggestionEngineReceiptJSON,
          let receipt = try? PhotoSuggestionEngineReceipt.decode(receiptJSON),
          let fused = modelSuggestion?.fullPrefillV2Suggestion,
          (try? receipt.validate(rawOutputUTF8: rawData)) == fused
        {
          aiReadHints = Self.deriveAIReadHints(
            receipt: receipt,
            fused: fused
          )
        } else {
          aiReadHints = [:]
        }
        modelSuggestedImageSHA256 = snapshot.modelSuggestedImageSHA256
        modelSuggestedAt = snapshot.modelSuggestedAt
        generationStartedAt = snapshot.generationStartedAt
        generationEndedAt = snapshot.generationEndedAt
        inferenceParsePath = snapshot.inferenceParsePath.flatMap(InferenceParsePath.init(rawValue:))
        analysisSource = snapshot.analysisSource
        analysisPipelineVersion = snapshot.analysisPipelineVersion
        didChooseBristolType = snapshot.didChooseBristolType
        didChooseMixedForm = snapshot.didChooseMixedForm
        didReviewPhotoUsability = snapshot.didReviewPhotoUsability
        pendingEntryID = snapshot.pendingEntryID
        pendingEntryFingerprint = snapshot.pendingEntryFingerprint
        pendingReviewedAt = snapshot.pendingReviewedAt

        #if MANUAL_FALLBACK_RELEASE
        // A prior unfinished suggestion may still exist after an in-place
        // update. Keep its photo and person-entered nonvisual context, but do
        // not relabel prior model-prefilled visual values as manual input.
        // The person must enter the complete visual tuple again.
        if reference != nil { _ = workflow.beginManualEntry(keepingDraft: true) }
        let retainedStrainingOrIncomplete = strainingOrIncomplete
        let retainedLeakageOrAccident = leakageOrAccident
        reviewSession = nil
        reviewedObservation = nil
        resetModelSuggestionState()
        if restoredModelBackedDraft {
          resetPhotoReview()
          strainingOrIncomplete = retainedStrainingOrIncomplete
          leakageOrAccident = retainedLeakageOrAccident
          redBlood = nil
          blackAppearance = nil
          blackTarry = nil
        }
        analysisSource = .manual
        analysisPipelineVersion = nil
        // A public manual build never exposes the provider-neutral quality
        // card, including after an in-place update from an internal build.
        photoQualityRecommendation = nil
        flowState = .manual(draftID: reference?.id)
        #else
        if let recommendation = photoQualityRecommendation,
          recommendation.severity == .hard,
          let reference
        {
          _ = workflow.beginManualEntry(keepingDraft: true)
          reviewSession = nil
          reviewedObservation = nil
          flowState = .failed(
            draftID: reference.id,
            message: recommendation.message
          )
        } else if let storedReview = snapshot.review, let reference {
          var session = ReviewSession(observation: storedReview.original)
          session.reviewed = storedReview.reviewed
          session.reviewedMixedForm = storedReview.reviewedMixedForm
          session.states = Dictionary(uniqueKeysWithValues: ReviewField.allCases.compactMap { field in
            storedReview.states[field.rawValue].flatMap { ReviewState(rawValue: $0) }.map { (field, $0) }
          })
          for field in ReviewField.allCases where session.states[field] == .suggested {
            session.states[field] = .confirmed
          }
          reviewSession = session
          reviewedObservation = storedReview.reviewed
          flowState = .reviewing(draftID: reference.id, review: session)
        } else if let reference, usesFullPrefillCandidate {
          // Resume the same retained photo at the automatic analysis boundary.
          // The complete suggestion sheet appears only after one model result.
          reviewSession = nil
          reviewedObservation = nil
          flowState = .reading(
            draftID: reference.id,
            imageHash: reference.sha256
          )
        } else {
          if reference != nil { _ = workflow.beginManualEntry(keepingDraft: true) }
          reviewSession = nil
          reviewedObservation = snapshot.reviewedObservation
          flowState = .manual(draftID: reference?.id)
        }
        #endif
        statusMessage = photoQualityRecommendation?.severity == .hard
          ? photoQualityRecommendation?.message
          : "Your unfinished entry is ready to continue."
      }
      draftRestorationNotice = nil
      canDiscardUnavailableDraft = false
      isDraftRecoveryBlocked = false
    }
  }

  /// Explicit retry used after device unlock and automatically by the view
  /// when protected data becomes available again.
  func retryDraftRestoration() {
    guard isDraftRecoveryBlocked else { return }
    restoreUnfinishedDraftIfAvailable()
  }

  func discardUnrestorableDraft() {
    guard isDraftRecoveryBlocked, canDiscardUnavailableDraft else { return }
    do {
      try draftSnapshotStore.discardAllUnfinishedDraftFiles()
      draftRestorationNotice = nil
      canDiscardUnavailableDraft = false
      isDraftRecoveryBlocked = false
      pendingEntryID = nil
      pendingEntryFingerprint = nil
      pendingReviewedAt = nil
      sharedReset()
    } catch {
      draftRestorationNotice = "GI Journal could not confirm that every unfinished-draft file was removed. Local cleanup remains pending; try discarding again. \(error.localizedDescription)"
      canDiscardUnavailableDraft = true
      isDraftRecoveryBlocked = true
    }
  }

  func dismissDraftRestorationNotice() {
    draftRestorationNotice = nil
  }

  private func blockCommittedDraftCleanup(_ message: String) {
    draftRestorationNotice = message
    canDiscardUnavailableDraft = false
    isDraftRecoveryBlocked = true
  }

  var canAnalyze: Bool {
    #if MANUAL_FALLBACK_RELEASE
    return false
    #else
    !isDraftRecoveryBlocked && isModelVerified && isEngineReady && !requiresFullAppRestart
      && !isImportingModel && !isPreparingModel
      && reviewSession == nil && originalValidatedJSON == nil && modelSuggestion == nil
      && workflow.canAnalyze
    #endif
  }
  var usesPublicManualFallback: Bool {
    #if MANUAL_FALLBACK_RELEASE
    true
    #else
    false
    #endif
  }
  var usesSubjectFirstCandidate: Bool {
    false
  }
  var usesFullPrefillCandidate: Bool {
    #if DEBUG || HACKATHON_EMBEDDED_GEMMA
    configuration.usesFullPrefillCandidate
    #else
    false
    #endif
  }
  private var usesProviderNeutralPhotoEngine: Bool {
    photoSuggestionEngine != nil
  }
  var usesProviderNeutralPhotoReview: Bool {
    photoSuggestionEngine != nil
      || analysisSource == .onDevicePhotoSuggestion
      || modelSuggestion?.fullPrefillV2Suggestion != nil
  }
  /// A provider-neutral engine failure still uses the complete editable photo
  /// tuple. It has no model suggestion or AI provenance, but it must not fall
  /// back to the legacy partial manual sheet. The public manual build remains
  /// on its existing dedicated presentation contract.
  var usesProviderNeutralManualPhotoReview: Bool {
    #if MANUAL_FALLBACK_RELEASE
    false
    #else
    workflow.manualEntryActive
      && draft != nil
      && !hasAnalysis
      && (usesProviderNeutralPhotoReview || retainedLowQualityManualReview)
    #endif
  }
  private var usesCompleteVisualReview: Bool {
    usesFullPrefillCandidate || usesProviderNeutralPhotoReview
      || usesPublicManualFallback
  }
  var canSave: Bool {
    guard !isDraftRecoveryBlocked,
      workflow.canSave,
      didChooseBristolType,
      didChooseMixedForm,
      mixedForm != nil
    else { return false }
    if usesPublicManualFallback {
      guard analysisSource == .manual,
        reviewSession == nil,
        manualVisualReviewIsConsistent
      else { return false }
    } else if usesFullPrefillCandidate || usesProviderNeutralPhotoReview {
      if reviewSession != nil, analysisSource != .manual {
        guard draft != nil,
          confirmedStoolPresence != nil,
          confirmedPhotoUsable != nil,
          (confirmedPhotoUsable == true) == (confirmedRetakeReason == nil),
          confirmedForm != nil,
          redBlood != nil,
          (!usesProviderNeutralPhotoReview || blackAppearance != nil),
          blackTarry != nil,
          (modelSuggestion?.fullPrefillSuggestion != nil
            || modelSuggestion?.fullPrefillV2Suggestion != nil),
          fullPrefillReviewIsConsistent
        else { return false }
      } else {
        // A failed model call retains the photo and uses the ordinary manual
        // entry contract; no model values or provenance are invented.
        guard analysisSource == .manual,
          manualVisualReviewIsConsistent
        else { return false }
      }
    } else {
      guard redBlood != nil, blackTarry != nil else { return false }
    }
    if draft != nil, !didReviewPhotoUsability { return false }
    guard ClinicalValidation.validate(
      confirmedBristolType: confirmedBristolType,
      painScore: painScore,
      mixedForm: mixedForm,
      strainingOrIncomplete: strainingOrIncomplete,
      leakageOrAccident: leakageOrAccident
    ).isEmpty else { return false }
    return reviewSession != nil || workflow.manualEntryActive
  }
  var canReplaceOrClear: Bool { !isDraftRecoveryBlocked && workflow.canReplaceOrClear }
  var canPrepareModel: Bool {
    #if MANUAL_FALLBACK_RELEASE
    return false
    #else
    !isDraftRecoveryBlocked && descriptor != nil && isModelVerified && !isEngineReady
      && !requiresFullAppRestart && !isImportingModel && !isPreparingModel && !workflow.isLocked
    #endif
  }
  var canImportModel: Bool {
    #if MANUAL_FALLBACK_RELEASE
    return false
    #else
    !isDraftRecoveryBlocked && descriptor != nil && !requiresFullAppRestart
      && !isImportingModel && !isPreparingModel && !isEngineReady && !workflow.isLocked
    #endif
  }
  var hasAnalysis: Bool {
    #if MANUAL_FALLBACK_RELEASE
    false
    #else
    reviewedObservation != nil
    #endif
  }
  var suggestedStoolPresence: StoolPresence? {
    modelSuggestion?.stoolPresenceSuggestion
  }
  var suggestedBristolType: Int? { reviewSession?.original.apparentBristolType }
  var suggestedForm: String? { modelSuggestion?.formSuggestion }
  var suggestedMixedForm: ClinicalTriState? { modelSuggestion?.mixedFormSuggestion }
  var suggestedRedMaterial: SymptomFlag? {
    modelSuggestion.map { Self.symptomSuggestion(fromMaterialState: $0.visualObservation.redAppearingMaterial) }
  }
  var suggestedBlackTarry: SymptomFlag? {
    modelSuggestion.map { Self.symptomSuggestion(fromMaterialState: $0.visualObservation.blackTarryAppearance) }
  }
  var redSuggestionHint: String? {
    guard let suggestedRedMaterial else { return nil }
    return PhotoAppearanceSuggestionCopy.redBloodLike(suggestedRedMaterial)
  }
  var blackSuggestionHint: String? {
    guard let suggestedBlackTarry else { return nil }
    return PhotoAppearanceSuggestionCopy.blackOrTarry(suggestedBlackTarry)
  }
  var apparentColor: String? {
    confirmedApparentColor ?? reviewSession?.reviewed.apparentColor
  }
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
    return "On-device suggestion: GI Journal used a simplified picture summary created on this iPhone. The full photo did not leave your device and was not sent to Gemma. Review the prefilled entry, change anything that is not right, then confirm it once."
  }
  var analyzeUnavailableReason: String? {
    if photoQualityRecommendation?.severity == .hard {
      return photoQualityRecommendation?.message
    }
    if descriptor == nil, photoSuggestionEngine == nil {
      return "Local analysis is not available in this build."
    }
    if !isModelVerified || !isEngineReady { return "Getting on-device analysis ready…" }
    if workflow.draft == nil { return "Choose a photo to begin." }
    if isImportingModel || isPreparingModel || workflow.isLocked { return "Finish the current operation first." }
    return nil
  }
  private var fullPrefillReviewIsConsistent: Bool {
    guard let confirmedPhotoUsable, let confirmedStoolPresence,
      let confirmedForm, let mixedForm
    else { return false }
    let separatesBlackAppearance =
      modelSuggestion?.fullPrefillV2Suggestion != nil
    if separatesBlackAppearance, blackAppearance == nil { return false }
    guard confirmedPhotoUsable
      ? confirmedRetakeReason == nil
      : confirmedRetakeReason != nil
    else { return false }
    if !confirmedPhotoUsable {
      return confirmedBristolType == nil
        && confirmedForm == "unable_to_assess"
        && mixedForm == .unsure
        && reviewSession?.reviewed.apparentColor == "unable_to_assess"
        && redBlood == .unsure
        && (!separatesBlackAppearance || blackAppearance == .unsure)
        && blackTarry == .unsure
    }
    if confirmedStoolPresence != .stool {
      let morphologyAbstains = confirmedBristolType == nil
        && confirmedForm == "unable_to_assess"
        && mixedForm == .unsure
      if separatesBlackAppearance { return morphologyAbstains }
      return morphologyAbstains
        && reviewSession?.reviewed.apparentColor == "unable_to_assess"
        && redBlood == .unsure
        && blackTarry == .unsure
    }
    switch mixedForm {
    case .no:
      guard let confirmedBristolType else { return false }
      return BristolFormContract.expectedForm(for: confirmedBristolType)
        == confirmedForm
    case .yes:
      return confirmedBristolType == nil && confirmedForm == "mixed"
    case .unsure:
      return confirmedBristolType == nil
        && confirmedForm == "unable_to_assess"
    }
  }

  /// Complete, human-entered visual tuple used only by the public manual
  /// fallback. No-photo entries leave photo usability/retake absent; an
  /// unusable photo or a non-stool/uncertain subject deterministically clears
  /// fields that cannot be supported by that observation.
  private var manualVisualReviewIsConsistent: Bool {
      guard let confirmedStoolPresence,
      let confirmedForm,
      let mixedForm,
      let apparentColor,
      redBlood != nil,
      blackAppearance != nil,
      blackTarry != nil
    else { return false }
    if draft == nil {
      guard confirmedPhotoUsable == nil,
        confirmedRetakeReason == nil
      else { return false }
    } else {
      guard let confirmedPhotoUsable,
        confirmedPhotoUsable
          ? confirmedRetakeReason == nil
          : confirmedRetakeReason != nil
      else { return false }
    }
    if confirmedPhotoUsable == false {
      return confirmedBristolType == nil
        && confirmedForm == "unable_to_assess"
        && mixedForm == .unsure
        && apparentColor == "unable_to_assess"
        && redBlood == .unsure
        && blackAppearance == .unsure
        && blackTarry == .unsure
    }
    if confirmedStoolPresence != .stool {
      return confirmedBristolType == nil
        && confirmedForm == "unable_to_assess"
        && mixedForm == .unsure
    }
    switch mixedForm {
    case .no:
      guard let confirmedBristolType else { return false }
      return BristolFormContract.expectedForm(for: confirmedBristolType)
        == confirmedForm
    case .yes:
      return confirmedBristolType == nil && confirmedForm == "mixed"
    case .unsure:
      return confirmedBristolType == nil
        && confirmedForm == "unable_to_assess"
    }
  }

  func startAutomaticPreparation() async {
    guard !usesPublicManualFallback,
      autoAnalysisEnabled,
      photoQualityRecommendation?.shouldRunQwen != false,
      descriptor != nil || photoSuggestionEngine != nil
    else { return }
    if photoSuggestionEngine != nil {
      // Provider-neutral setup is scoped to an actual retained photo. Starting
      // it before selection would leave no draft identity to bind its late
      // result to, and a photo replacement could otherwise inherit readiness
      // from the wrong lifecycle boundary.
      if draft != nil { await beginAutomaticAnalysisNowIfPossible() }
      return
    }
    if isModelVerified, !isEngineReady { await prepareModel() }
    if draft != nil { await beginAutomaticAnalysisNowIfPossible() }
  }

  /// Begins provider-neutral initialization without awaiting a native
  /// initializer that may ignore cancellation. Completion and deadline are
  /// both independently guarded by the draft token below.
  private func startPhotoSuggestionEnginePreparation(
    _ engine: PhotoSuggestionEngine
  ) {
    guard !isPreparingModel,
      !requiresFullAppRestart,
      let draft,
      case .reading(let draftID, let imageHash) = flowState,
      draftID == draft.reference.id,
      imageHash == draft.reference.sha256
    else { return }

    let context = PhotoSuggestionPreparationContext(
      token: UUID(),
      draftID: draftID,
      imageHash: imageHash
    )
    photoSuggestionPreparation = context
    isPreparingModel = true
    statusMessage = "Getting on-device analysis ready…"

    let preparationTask = Task { try await engine.prepare() }
    photoSuggestionPreparationTask = preparationTask
    photoSuggestionPreparationDeadlineTask = Task { [weak self] in
      try? await Task.sleep(for: self?.preparationTimeout ?? .seconds(15))
      guard !Task.isCancelled else { return }
      self?.expirePhotoSuggestionEnginePreparation(context)
    }
    Task { [weak self, preparationTask] in
      do {
        let identity = try await preparationTask.value
        guard !Task.isCancelled else { return }
        self?.finishPhotoSuggestionEnginePreparation(context, identity: identity)
      } catch {
        guard !Task.isCancelled else { return }
        self?.failPhotoSuggestionEnginePreparation(context)
      }
    }
  }

  private func preparationContextMatches(
    _ context: PhotoSuggestionPreparationContext
  ) -> Bool {
    guard photoSuggestionPreparation == context,
      draft?.reference.id == context.draftID,
      draft?.reference.sha256 == context.imageHash,
      case .reading(let draftID, let imageHash) = flowState
    else { return false }
    return draftID == context.draftID && imageHash == context.imageHash
  }

  private func finishPhotoSuggestionEnginePreparation(
    _ context: PhotoSuggestionPreparationContext,
    identity: PhotoSuggestionEngineIdentity
  ) {
    guard preparationContextMatches(context) else { return }
    photoSuggestionPreparationDeadlineTask?.cancel()
    photoSuggestionPreparationDeadlineTask = nil
    photoSuggestionPreparationTask = nil
    photoSuggestionPreparation = nil
    isPreparingModel = false
    preparedPhotoSuggestionEngineIdentity = identity
    isModelVerified = true
    isEngineReady = true
    statusMessage = nil
    guard let automaticAnalysisContext,
      automaticAnalysisContext.draftID == context.draftID,
      automaticAnalysisContext.imageHash == context.imageHash
    else { return }
    let handoff = preparationHandoff
    Task { [weak self] in
      await handoff()
      await self?.beginAutomaticAnalysisIfPossible(
        expectedContext: automaticAnalysisContext
      )
    }
  }

  private func failPhotoSuggestionEnginePreparation(
    _ context: PhotoSuggestionPreparationContext
  ) {
    guard preparationContextMatches(context) else { return }
    photoSuggestionPreparationDeadlineTask?.cancel()
    photoSuggestionPreparationDeadlineTask = nil
    photoSuggestionPreparationTask = nil
    photoSuggestionPreparation = nil
    isPreparingModel = false
    preparedPhotoSuggestionEngineIdentity = nil
    isModelVerified = false
    isEngineReady = false
    handlePreparationFailure(
      draftID: context.draftID,
      requiresFullAppRestart: false,
      message: "On-device photo suggestions are unavailable. Continue with the prefilled Not sure form."
    )
  }

  private func expirePhotoSuggestionEnginePreparation(
    _ context: PhotoSuggestionPreparationContext
  ) {
    guard preparationContextMatches(context) else { return }
    photoSuggestionPreparationTask?.cancel()
    photoSuggestionPreparationDeadlineTask?.cancel()
    photoSuggestionPreparationDeadlineTask = nil
    photoSuggestionPreparationTask = nil
    photoSuggestionPreparation = nil
    isPreparingModel = false
    preparedPhotoSuggestionEngineIdentity = nil
    isModelVerified = false
    isEngineReady = false
    handlePreparationFailure(
      draftID: context.draftID,
      requiresFullAppRestart: false,
      message: "On-device photo suggestions took too long. Your photo is still here. Continue manually."
    )
  }

  /// Revoke the completion authority before changing the draft, workflow, or
  /// privacy state. Cancellation remains advisory for a native initializer;
  /// the token check is what quarantines a late success or failure.
  private func invalidatePhotoSuggestionEnginePreparation() {
    automaticAnalysisContext = nil
    guard photoSuggestionPreparation != nil else { return }
    photoSuggestionPreparationTask?.cancel()
    photoSuggestionPreparationDeadlineTask?.cancel()
    photoSuggestionPreparationTask = nil
    photoSuggestionPreparationDeadlineTask = nil
    photoSuggestionPreparation = nil
    isPreparingModel = false
  }

  private func automaticAnalysisContextMatches(
    _ context: AutomaticAnalysisContext
  ) -> Bool {
    guard automaticAnalysisContext == context,
      !usesPublicManualFallback,
      autoAnalysisEnabled,
      !workflow.manualEntryActive,
      draft?.reference.id == context.draftID,
      draft?.reference.sha256 == context.imageHash,
      case .reading(let draftID, let imageHash) = flowState
    else { return false }
    return draftID == context.draftID && imageHash == context.imageHash
  }

  private func grantAutomaticAnalysisContextIfPossible() -> AutomaticAnalysisContext? {
    guard !usesPublicManualFallback,
      autoAnalysisEnabled,
      !workflow.manualEntryActive,
      let draft,
      case .reading(let draftID, let imageHash) = flowState,
      draftID == draft.reference.id,
      imageHash == draft.reference.sha256
    else { return nil }
    let context = AutomaticAnalysisContext(
      token: UUID(),
      draftID: draftID,
      imageHash: imageHash
    )
    automaticAnalysisContext = context
    return context
  }

  /// Captures the automatic boundary before scheduling. A privacy transition
  /// can then revoke this context before the task gets a chance to mutate the
  /// visible reading/status state.
  private func queueAutomaticAnalysisIfPossible() {
    guard let context = grantAutomaticAnalysisContextIfPossible() else { return }
    queueAutomaticAnalysis(context)
  }

  private func queueAutomaticAnalysis(_ context: AutomaticAnalysisContext) {
    let handoff = automaticAnalysisHandoff
    Task { [weak self] in
      await handoff()
      await self?.beginAutomaticAnalysisIfPossible(expectedContext: context)
    }
  }

  private func beginAutomaticAnalysisNowIfPossible() async {
    guard let context = grantAutomaticAnalysisContextIfPossible() else { return }
    await beginAutomaticAnalysisIfPossible(expectedContext: context)
  }

  func prepareAutomaticRuntime(using runtime: ModelRuntimeCoordinator, retry: Bool = false) async {
    guard !usesPublicManualFallback,
      autoAnalysisEnabled,
      photoQualityRecommendation?.shouldRunQwen != false,
      descriptor != nil
    else { return }
    let preparationDraftID = draft?.reference.id
    let readiness = retry
      ? await runtime.retryLocalAnalysisPreparation()
      : await runtime.prepareLocalAnalysis()
    switch readiness {
    case .ready:
      isModelVerified = true
      isEngineReady = true
      requiresFullAppRestart = false
      statusMessage = nil
      if draft != nil, case .reading = flowState {
        await beginAutomaticAnalysisNowIfPossible()
      }
    case .verifying, .preparing:
      statusMessage = "Getting on-device analysis ready…"
    case .failed(let userFacingMessage, _):
      isModelVerified = false
      isEngineReady = false
      let requiresFullAppRestart = await runtime.localAnalysisRequiresFullAppRestart()
      let message = requiresFullAppRestart
        ? "On-device analysis didn’t finish getting ready. Continue manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it."
        : userFacingMessage
      handlePreparationFailure(
        draftID: preparationDraftID,
        requiresFullAppRestart: requiresFullAppRestart,
        message: message
      )
    }
  }

  func loadSelection() async {
    #if INTERNAL_QWEN3_QA
    Self.qaAppendSaveDiagnostic(
      "LOAD_SELECTION_ENTER \(Date()) canReplaceOrClear=\(canReplaceOrClear) itemNil=\(selectedItem == nil)")
    #endif
    guard canReplaceOrClear, let item = selectedItem else { return }
    await loadPhotoTransfer {
      try await item.loadTransferable(type: Data.self)
    }
  }

  #if DEBUG
  /// Injectable transfer seam for lifecycle tests. Production selection always
  /// calls `loadSelection()`, which supplies PhotosPicker's own transfer.
  func loadPhotoDataForTesting(
    _ transfer: @escaping @Sendable () async throws -> Data?
  ) async {
    await loadPhotoTransfer(transfer)
  }
  #endif

  private func loadPhotoTransfer(
    _ transfer: @escaping @Sendable () async throws -> Data?
  ) async {
    guard canReplaceOrClear else { return }
    let previousState = draftPresentationState()
    invalidatePhotoTransfer()
    invalidatePhotoSuggestionEnginePreparation()
    let preparationID = workflow.beginPreparation()
    let context = PhotoTransferContext(
      token: UUID(),
      preparationID: preparationID,
      previousPresentationState: previousState
    )
    photoTransfer = context
    manualPhotoTransferToken = nil
    flowState = .preparingPhoto(draftID: preparationID)
    isBusy = true
    photoTransferDeadlineTask = Task { [weak self] in
      try? await Task.sleep(for: self?.preparationTimeout ?? .seconds(15))
      guard !Task.isCancelled else { return }
      self?.transitionPhotoTransferToManual(
        context,
        message: "Photo selection took too long. Continue manually; if the selected photo finishes loading, it will stay manual."
      )
    }
    var restoredExistingPresentation = false
    defer {
      if !restoredExistingPresentation { isBusy = workflow.isLocked }
    }

    var completion: PhotoTransferCompletion?
    do {
      guard let data = try await transfer() else { throw GITimelineError.invalidImage }
      guard let transferCompletion = completePhotoTransfer(context) else { return }
      completion = transferCompletion
      #if INTERNAL_QWEN3_QA
      Self.qaAppendSaveDiagnostic("LOAD_SELECTION_DATA \(Date()) bytes=\(data.count)")
      #endif
      try installPrepared(
        data,
        preparationID: preparationID,
        retainingManualDraft: transferCompletion.retainingManualDraft,
        rollbackState: transferCompletion.rollbackPresentationState
      )
      #if DEBUG
      selectedDemoFixture = nil
      #endif
      #if INTERNAL_QWEN3_QA
      Self.qaAppendSaveDiagnostic(
        "LOAD_SELECTION_INSTALLED \(Date()) autoAnalysisEnabled=\(autoAnalysisEnabled) draftURLNil=\(currentDraftURL == nil)")
      #endif
      if autoAnalysisEnabled, !transferCompletion.retainingManualDraft {
        queueAutomaticAnalysisIfPossible()
      }
    } catch {
      // A staging failure happens after `completePhotoTransfer` consumed the
      // context. Retain that already-decided disposition so the error still
      // clears normal preparation or preserves the manual fallback; only a
      // transfer failure itself consumes the live context here.
      guard let transferCompletion = completion ?? completePhotoTransfer(context) else {
        return
      }
      #if INTERNAL_QWEN3_QA
      Self.qaAppendSaveDiagnostic("LOAD_SELECTION_FAILED \(Date()) \(String(reflecting: error))")
      #endif
      let rollbackState = transferCompletion.rollbackPresentationState
      restoreDraftPresentationState(
        rollbackState,
        resolvingPreparation: preparationID
      )
      if rollbackState.draft != nil || rollbackState.workflow.manualEntryActive {
        restoredExistingPresentation = true
        // Replacement is transactional: the prior card, actions, review
        // values, note, image bytes, and flow remain exactly as they were.
      } else {
        handlePhotoPreparationFailure(error, preparationID: preparationID)
      }
    }
  }

  /// Marks a transfer's data as manual-only. We intentionally do not rely on
  /// cancellation stopping PhotosPicker; its eventual bytes may still be the
  /// person's selected photo, but must never restart automatic analysis.
  private func transitionPhotoTransferToManual(
    _ context: PhotoTransferContext,
    message: String
  ) {
    guard photoTransfer?.token == context.token,
      manualPhotoTransferToken != context.token
    else { return }
    manualPhotoTransferToken = context.token
    photoTransferDeadlineTask?.cancel()
    photoTransferDeadlineTask = nil
    workflow.failPreparation(context.preparationID)
    let keepsPhoto = draft != nil
    guard workflow.beginManualEntry(keepingDraft: keepsPhoto) else { return }

    if let currentDraft = draft {
      presentManualFallback(for: currentDraft.reference.id)
    } else {
      withDraftSnapshotPersistenceSuppressed {
        reviewedObservation = nil
        reviewSession = nil
        resetModelSuggestionState()
        analysisSource = .manual
        analysisPipelineVersion = nil
        manualEntryCapturedAtBaseline = manualEntryCapturedAtBaseline ?? capturedAt
        flowState = .manual(draftID: nil)
        isBusy = false
      }
    }
    statusMessage = message
    persistDraftSnapshotIfPossible()
  }

  /// Returns whether the transfer crossed a background/deadline boundary.
  /// A stale or explicitly cleared transfer returns nil and its bytes are
  /// discarded without touching the current entry.
  private func completePhotoTransfer(_ context: PhotoTransferContext) -> PhotoTransferCompletion? {
    guard photoTransfer?.token == context.token else { return nil }
    photoTransferDeadlineTask?.cancel()
    photoTransferDeadlineTask = nil
    photoTransfer = nil
    let retainingManualDraft = manualPhotoTransferToken == context.token
    // Once a delayed picker has crossed into manual fallback, the person may
    // keep editing while PhotosUI still owns the transfer. Those edits are the
    // rollback boundary for any later decode or persistence failure. A normal
    // foreground replacement continues to use its pre-transfer boundary.
    let rollbackPresentationState = retainingManualDraft
      ? draftPresentationState()
      : context.previousPresentationState
    manualPhotoTransferToken = nil
    return PhotoTransferCompletion(
      retainingManualDraft: retainingManualDraft,
      rollbackPresentationState: rollbackPresentationState
    )
  }

  private func invalidatePhotoTransfer() {
    photoTransferDeadlineTask?.cancel()
    photoTransferDeadlineTask = nil
    photoTransfer = nil
    manualPhotoTransferToken = nil
  }

  func prepareImageData(_ data: Data) throws {
    guard canReplaceOrClear else { return }
    let previousState = draftPresentationState()
    invalidatePhotoTransfer()
    invalidatePhotoSuggestionEnginePreparation()
    let prepID = workflow.beginPreparation()
    flowState = .preparingPhoto(draftID: prepID)
    isBusy = true
    var restoredExistingPresentation = false
    defer {
      if !restoredExistingPresentation { isBusy = workflow.isLocked }
    }
    do {
      try installPrepared(
        data,
        preparationID: prepID,
        rollbackState: previousState
      )
      if autoAnalysisEnabled { queueAutomaticAnalysisIfPossible() }
    } catch {
      restoreDraftPresentationState(
        previousState,
        resolvingPreparation: prepID
      )
      if previousState.draft == nil,
        !previousState.workflow.manualEntryActive
      {
        handlePhotoPreparationFailure(error, preparationID: prepID)
      } else {
        restoredExistingPresentation = true
      }
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

  private func installPrepared(
    _ data: Data,
    preparationID: UUID,
    retainingManualDraft: Bool = false,
    rollbackState: NewEntryDraftPresentationState
  ) throws {
    let prepared = try imageStore.prepare(data)
    guard let preview = UIImage(contentsOfFile: prepared.url.path) else {
      imageStore.deleteBestEffort(prepared.url)
      throw GITimelineError.invalidImage
    }
    let qualityRecommendation: PhotoQualityRecommendation?
    do {
      qualityRecommendation = !retainingManualDraft
        && autoAnalysisEnabled
        && !usesPublicManualFallback
        ? try imageStore.photoQualityRecommendation(for: prepared)
        : nil
    } catch {
      imageStore.deleteBestEffort(prepared.url)
      throw error
    }
    let effectivePreparationID: UUID
    if retainingManualDraft {
      effectivePreparationID = workflow.beginPreparation()
    } else {
      effectivePreparationID = preparationID
    }
    let old = workflow.finishPreparation(effectivePreparationID, prepared: prepared.reference)
    guard workflow.draft?.id == prepared.reference.id else {
      imageStore.deleteBestEffort(prepared.url)
      return
    }
    withDraftSnapshotPersistenceSuppressed {
      draft = prepared
      selectedImage = Image(uiImage: preview)
      if !retainingManualDraft { manualEntryCapturedAtBaseline = nil }
      if !retainingManualDraft { capturedAt = Date() }
      reviewedObservation = nil
      reviewSession = nil
      resetModelSuggestionState()
      // A newly installed photo never inherits answers reviewed against the
      // prior one, including when its transfer finished after manual fallback.
      resetPhotoReview()
      photoQualityRecommendation = qualityRecommendation
      redBlood = nil
      blackAppearance = nil
      blackTarry = nil
      pendingEntryID = nil
      pendingEntryFingerprint = nil
      pendingReviewedAt = nil
      statusMessage = retainingManualDraft
        ? "Photo kept. Enter the details yourself before saving."
        : qualityRecommendation?.severity == .hard
          ? qualityRecommendation?.message
          : nil
      #if MANUAL_FALLBACK_RELEASE
      _ = workflow.beginManualEntry(keepingDraft: true)
      flowState = .manual(draftID: prepared.reference.id)
      #else
      if let qualityRecommendation,
        qualityRecommendation.severity == .hard
      {
        _ = workflow.beginManualEntry(keepingDraft: true)
        prefillConservativeManualFallback()
        confirmedPhotoUsable = false
        confirmedRetakeReason = qualityRecommendation.retakeReason
        didReviewPhotoUsability = true
        flowState = .failed(
          draftID: prepared.reference.id,
          message: qualityRecommendation.message
        )
      } else if retainingManualDraft {
        _ = workflow.beginManualEntry(keepingDraft: true)
        flowState = .manual(draftID: prepared.reference.id)
      } else if usesSubjectFirstCandidate {
        flowState = .confirmingSubject(draftID: prepared.reference.id)
      } else {
        flowState = autoAnalysisEnabled
          ? .reading(draftID: prepared.reference.id, imageHash: prepared.reference.sha256)
          : .empty
      }
      #endif
    }
    // Establish the new, atomically-written recovery record before releasing
    // the replaced photo. A termination here therefore retains one complete
    // draft rather than leaving an orphaned JPEG.
    guard persistDraftSnapshotIfPossible() else {
      restoreDraftPresentationState(
        rollbackState,
        resolvingPreparation: effectivePreparationID
      )
      imageStore.deleteBestEffort(prepared.url)
      throw DraftSnapshotPersistenceError.couldNotProtect
    }
    if let old { imageStore.deleteBestEffort(URL(fileURLWithPath: old.path)) }
  }

  /// Records the person's subject decision before any candidate runtime work.
  /// Only Yes keeps the sanitized photo eligible for one Gemma call.
  @discardableResult
  func chooseSubjectConfirmation(_ answer: PhotoSubjectConfirmation) -> Bool {
    guard usesSubjectFirstCandidate, let draft, canReplaceOrClear,
      case .confirmingSubject(let activeDraftID) = flowState,
      activeDraftID == draft.reference.id
    else { return false }

    if answer != .yes {
      return transitionCandidatePhotoToManual(
        subjectAnswer: answer,
        message: nil
      )
    }

    let previousState = draftPresentationState()
    withDraftSnapshotPersistenceSuppressed {
      subjectConfirmation = .yes
      // Candidate compatibility mirror: this is the person's answer to the
      // exact subject question, never a value copied from Gemma.
      confirmedPhotoUsable = true
      didReviewPhotoUsability = true
      redBlood = nil
      blackAppearance = nil
      blackTarry = nil
      statusMessage = "Getting on-device analysis ready…"
      flowState = .reading(
        draftID: draft.reference.id,
        imageHash: draft.reference.sha256
      )
    }
    guard persistDraftSnapshotIfPossible() else {
      let failure = statusMessage
      restoreDraftPresentationState(
        previousState,
        resolvingPreparation: UUID()
      )
      statusMessage = failure
      return false
    }
    return true
  }

  func continueAfterSubjectConfirmation(
    using runtime: ModelRuntimeCoordinator
  ) async {
    guard usesSubjectFirstCandidate, subjectConfirmation == .yes,
      draft != nil, autoAnalysisEnabled
    else { return }
    if !isEngineReady {
      await prepareAutomaticRuntime(using: runtime)
    } else {
      await beginAutomaticAnalysisNowIfPossible()
    }
  }

  /// Persists a no-photo manual draft before releasing the unrelated or
  /// unusable staged JPEG. A failed snapshot write restores the prior photo
  /// state and does not delete any bytes.
  @discardableResult
  private func transitionCandidatePhotoToManual(
    subjectAnswer: PhotoSubjectConfirmation?,
    message: String?
  ) -> Bool {
    guard usesSubjectFirstCandidate, let oldDraft = draft, !workflow.isLocked
    else { return false }
    let previousState = draftPresentationState()
    guard workflow.beginManualEntry(keepingDraft: false) else { return false }
    withDraftSnapshotPersistenceSuppressed {
      draft = nil
      selectedItem = nil
      selectedImage = nil
      reviewedObservation = nil
      reviewSession = nil
      resetModelSuggestionState()
      // Detaching a photo invalidates only photo-derived review. Preserve the
      // person's notes and symptom context; those values are unrelated to a
      // failed/declined photo analysis and must not be erased.
      let existingStrainingOrIncomplete = strainingOrIncomplete
      let existingLeakageOrAccident = leakageOrAccident
      resetPhotoReview()
      strainingOrIncomplete = existingStrainingOrIncomplete
      leakageOrAccident = existingLeakageOrAccident
      subjectConfirmation = subjectAnswer
      manualEntryCapturedAtBaseline = capturedAt
      analysisSource = .manual
      analysisPipelineVersion = nil
      pendingEntryID = nil
      pendingEntryFingerprint = nil
      pendingReviewedAt = nil
      statusMessage = message
      flowState = .manual(draftID: nil)
      isBusy = false
    }
    guard persistDraftSnapshotIfPossible() else {
      let failure = statusMessage
      restoreDraftPresentationState(previousState, resolvingPreparation: UUID())
      statusMessage = failure
      return false
    }
    imageStore.deleteBestEffort(oldDraft.url)
    Task { await inference.discardRepairContext(draftURL: oldDraft.url) }
    return true
  }

  private func handlePhotoPreparationFailure(_ error: Error, preparationID: UUID) {
    workflow.failPreparation(preparationID)
    if error is DraftSnapshotPersistenceError {
      statusMessage = error.localizedDescription
      return
    }
    statusMessage = "That photo couldn’t be prepared. Try another."
    flowState = .failed(draftID: draft?.reference.id, message: statusMessage ?? "Couldn’t prepare that photo.")
  }

  private func draftPresentationState() -> NewEntryDraftPresentationState {
    NewEntryDraftPresentationState(
      workflow: workflow,
      flowState: flowState,
      isBusy: isBusy,
      draft: draft,
      selectedItem: selectedItem,
      selectedImage: selectedImage,
      capturedAt: capturedAt,
      confirmedStoolPresence: confirmedStoolPresence,
      confirmedBristolType: confirmedBristolType,
      confirmedForm: confirmedForm,
      confirmedApparentColor: confirmedApparentColor,
      confirmedPhotoUsable: confirmedPhotoUsable,
      confirmedRetakeReason: confirmedRetakeReason,
      subjectConfirmation: subjectConfirmation,
      mixedForm: mixedForm,
      painScore: painScore,
      urgency: urgency,
      strainingOrIncomplete: strainingOrIncomplete,
      leakageOrAccident: leakageOrAccident,
      redBlood: redBlood,
      blackAppearance: blackAppearance,
      blackTarry: blackTarry,
      dizziness: dizziness,
      severePain: severePain,
      note: note,
      reviewedObservation: reviewedObservation,
      reviewSession: reviewSession,
      originalValidatedJSON: originalValidatedJSON,
      fullPrefillNormalization: fullPrefillNormalization,
      photoSuggestionEngineReceiptJSON: photoSuggestionEngineReceiptJSON,
      aiReadHints: aiReadHints,
      photoQualityRecommendation: photoQualityRecommendation,
      retainedLowQualityManualReview: retainedLowQualityManualReview,
      modelSuggestedImageSHA256: modelSuggestedImageSHA256,
      modelSuggestedAt: modelSuggestedAt,
      generationStartedAt: generationStartedAt,
      generationEndedAt: generationEndedAt,
      inferenceParsePath: inferenceParsePath,
      analysisSource: analysisSource,
      analysisPipelineVersion: analysisPipelineVersion,
      didChooseBristolType: didChooseBristolType,
      didChooseMixedForm: didChooseMixedForm,
      didReviewPhotoUsability: didReviewPhotoUsability,
      manualEntryCapturedAtBaseline: manualEntryCapturedAtBaseline,
      pendingEntryID: pendingEntryID,
      pendingEntryFingerprint: pendingEntryFingerprint,
      pendingReviewedAt: pendingReviewedAt,
      statusMessage: statusMessage
    )
  }

  private func restoreDraftPresentationState(
    _ state: NewEntryDraftPresentationState,
    resolvingPreparation _: UUID
  ) {
    withDraftSnapshotPersistenceSuppressed {
      workflow = state.workflow
      draft = state.draft
      selectedItem = state.selectedItem
      selectedImage = state.selectedImage
      capturedAt = state.capturedAt
      confirmedStoolPresence = state.confirmedStoolPresence
      confirmedBristolType = state.confirmedBristolType
      confirmedForm = state.confirmedForm
      confirmedApparentColor = state.confirmedApparentColor
      confirmedPhotoUsable = state.confirmedPhotoUsable
      confirmedRetakeReason = state.confirmedRetakeReason
      subjectConfirmation = state.subjectConfirmation
      mixedForm = state.mixedForm
      painScore = state.painScore
      urgency = state.urgency
      strainingOrIncomplete = state.strainingOrIncomplete
      leakageOrAccident = state.leakageOrAccident
      redBlood = state.redBlood
      blackAppearance = state.blackAppearance
      blackTarry = state.blackTarry
      dizziness = state.dizziness
      severePain = state.severePain
      note = state.note
      reviewedObservation = state.reviewedObservation
      reviewSession = state.reviewSession
      originalValidatedJSON = state.originalValidatedJSON
      fullPrefillNormalization = state.fullPrefillNormalization
      photoSuggestionEngineReceiptJSON =
        state.photoSuggestionEngineReceiptJSON
      aiReadHints = state.aiReadHints
      photoQualityRecommendation = state.photoQualityRecommendation
      retainedLowQualityManualReview = state.retainedLowQualityManualReview
      modelSuggestion = state.originalValidatedJSON.flatMap { raw in
        try? Self.resolvedModelSuggestion(
          raw: raw,
          normalization: state.fullPrefillNormalization
        )
      }
      modelSuggestedImageSHA256 = state.modelSuggestedImageSHA256
      modelSuggestedAt = state.modelSuggestedAt
      generationStartedAt = state.generationStartedAt
      generationEndedAt = state.generationEndedAt
      inferenceParsePath = state.inferenceParsePath
      analysisSource = state.analysisSource
      analysisPipelineVersion = state.analysisPipelineVersion
      didChooseBristolType = state.didChooseBristolType
      didChooseMixedForm = state.didChooseMixedForm
      didReviewPhotoUsability = state.didReviewPhotoUsability
      manualEntryCapturedAtBaseline = state.manualEntryCapturedAtBaseline
      pendingEntryID = state.pendingEntryID
      pendingEntryFingerprint = state.pendingEntryFingerprint
      pendingReviewedAt = state.pendingReviewedAt
      statusMessage = state.statusMessage
      flowState = state.flowState
      isBusy = state.isBusy
    }
  }

  private func beginAutomaticAnalysisIfPossible(
    expectedContext: AutomaticAnalysisContext
  ) async {
    #if INTERNAL_QWEN3_QA
    Self.qaAppendSaveDiagnostic(
      "BEGIN_ANALYSIS_ENTER \(Date()) manualFallback=\(usesPublicManualFallback) autoEnabled=\(autoAnalysisEnabled) draftNil=\(draft == nil) engineReady=\(isEngineReady) engineNil=\(photoSuggestionEngine == nil) restartRequired=\(requiresFullAppRestart)")
    #endif
    guard automaticAnalysisContextMatches(expectedContext), let draft else { return }
    if usesSubjectFirstCandidate, subjectConfirmation != .yes {
      flowState = .confirmingSubject(draftID: draft.reference.id)
      statusMessage = nil
      return
    }
    flowState = .reading(draftID: draft.reference.id, imageHash: draft.reference.sha256)
    statusMessage = "Reading photo"
    guard !requiresFullAppRestart else {
      activateManualFallback(requiresFullAppRestart: true)
      return
    }
    if !isEngineReady {
      if let photoSuggestionEngine {
        startPhotoSuggestionEnginePreparation(photoSuggestionEngine)
        // Preparation owns its own success, failure, and deadline transition.
        // Do not await a possibly non-cooperative native initializer here;
        // while its token remains current, the retained draft stays at the
        // reading boundary and its completion will start one analysis.
        return
      }
      if !isModelVerified {
        // App launch owns verification. Keep the immutable draft in the calm
        // hero state; prepareAutomaticRuntime will continue this exact draft.
        statusMessage = "Getting on-device analysis ready…"
        return
      }
      if isModelVerified, photoSuggestionEngine == nil { await prepareModel() }
      guard isEngineReady else {
        if case .manual = flowState { return }
        activateManualFallback()
        return
      }
    }
    analyze()
  }

  func analyze() {
    guard canAnalyze, let draft, let attemptID = workflow.beginAttempt() else { return }
    if let photoSuggestionEngine {
      analyze(
        with: photoSuggestionEngine,
        draft: draft,
        attemptID: attemptID
      )
      return
    }
    let draftID = draft.reference.id
    let imageHash = draft.reference.sha256
    isBusy = true
    statusMessage = "Reading photo"
    flowState = .reading(draftID: draftID, imageHash: imageHash)
    let visualStart = ContinuousClock.now
    let generationStart = Date()

    analysisTask?.cancel()
    let analysisTaskID = UUID()
    self.analysisTaskID = analysisTaskID
    analysisTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.analysisTaskID == analysisTaskID {
          self.isBusy = self.workflow.isLocked
          self.analysisTask = nil
          self.analysisTaskID = nil
        }
      }
      do {
        let initial = try await self.inference.analyze(
          draftURL: draft.url,
          expectedSHA256: imageHash
        )
        try Task.checkCancellation()
        let parsedSuggestion: ParsedModelSuggestion
        let parsePath: InferenceParsePath
        do {
          parsedSuggestion = try self.parseModelSuggestion(initial)
          parsePath = .direct
        } catch {
          if self.usesFullPrefillCandidate { throw error }
          let repaired = try await self.inference.repair(draftURL: draft.url, errors: error.localizedDescription)
          try Task.checkCancellation()
          parsedSuggestion = try self.parseModelSuggestion(repaired)
          parsePath = .serializationRepair
        }
        let storedSuggestion = parsedSuggestion.suggestion
        let generationEnd = Date()
        let observation = storedSuggestion.visualObservation
        await self.inference.discardRepairContext(draftURL: draft.url)
        let elapsed = visualStart.duration(to: .now)
        let minimum = Duration.milliseconds(900)
        if elapsed < minimum { try await Task.sleep(for: minimum - elapsed) }
        guard self.workflow.finishAttempt(attemptID),
          self.draft?.reference.id == draftID,
          self.draft?.reference.sha256 == imageHash,
          case .reading(draftID, imageHash) = self.flowState
        else {
          if self.workflow.analysisWasTimedOut,
            case .reading = self.flowState
          {
            self.activateManualFallback()
          }
          return
        }
        let fullPrefill = storedSuggestion.fullPrefillSuggestion
        let session = ReviewSession(observation: observation)
        self.withDraftSnapshotPersistenceSuppressed {
          self.modelSuggestion = storedSuggestion
          self.reviewedObservation = observation
          self.reviewSession = session
          self.confirmedStoolPresence = fullPrefill?.stoolPresence
          self.confirmedBristolType = fullPrefill?.bristolType
            ?? observation.apparentBristolType
          self.confirmedForm = fullPrefill?.form ?? observation.form
          self.confirmedApparentColor = fullPrefill?.apparentColor
            ?? observation.apparentColor
          self.mixedForm = storedSuggestion.mixedFormSuggestion
          self.confirmedPhotoUsable = fullPrefill?.imageUsable
            ?? observation.imageUsable
          let suggestedRetake = storedSuggestion.retakeReasonSuggestion
          self.confirmedRetakeReason = suggestedRetake == .notTargetImage
            ? .other : suggestedRetake
          self.redBlood = Self.symptomSuggestion(
            fromMaterialState: observation.redAppearingMaterial
          )
          self.blackTarry = Self.symptomSuggestion(
            fromMaterialState: observation.blackTarryAppearance
          )
          self.didChooseBristolType = true
          self.didChooseMixedForm = true
          self.didReviewPhotoUsability = true
          self.analysisSource = self.configuration.usesLocalPixelBridge ? .gemmaDerivedMap : .gemmaRawImage
          self.analysisPipelineVersion = self.configuration.analysisPipelineVersion
          self.originalValidatedJSON = self.usesFullPrefillCandidate
            ? initial
            : (try? self.canonicalModelSuggestion(storedSuggestion))
          self.fullPrefillNormalization = parsedSuggestion.normalization
          self.modelSuggestedImageSHA256 = imageHash
          self.modelSuggestedAt = generationEnd
          self.generationStartedAt = generationStart
          self.generationEndedAt = generationEnd
          self.inferenceParsePath = parsePath
          self.statusMessage = nil
          self.flowState = .reviewing(draftID: draftID, review: session)
        }
        self.persistDraftSnapshotIfPossible()
      } catch {
        await self.inference.discardRepairContext(draftURL: draft.url)
        let ownsAttempt = self.workflow.finishAttempt(attemptID)
        guard self.draft?.reference.id == draftID,
          self.draft?.reference.sha256 == imageHash
        else { return }
        if !ownsAttempt {
          guard self.workflow.analysisWasTimedOut,
            case .reading = self.flowState
          else { return }
          self.activateManualFallback()
          return
        }
        self.activateManualFallback()
      }
    }

    timeoutTask?.cancel()
    let timeout = analysisTimeout
    timeoutTask = Task { [weak self] in
      try? await Task.sleep(for: timeout)
      guard let self, !Task.isCancelled else { return }
      guard self.workflow.timeoutAttemptAndBeginManualEntry(attemptID, keepingDraft: true) else { return }
      let cancelledAnalysisTask = self.analysisTask
      cancelledAnalysisTask?.cancel()
      guard self.draft?.reference.id == draftID,
        self.draft?.reference.sha256 == imageHash
      else { return }
      // The workflow already owns the manual transition. Publish it before
      // awaiting actor-backed runtime status so a blocked native call cannot
      // leave the UI saying "Reading photo" past the product deadline.
      self.presentManualFallback(for: draftID)
      // Await only the Swift caller boundary, which is independently bounded;
      // native work may remain quarantined behind it. This ensures the status
      // query observes a final safe-release versus quarantine disposition.
      await cancelledAnalysisTask?.value
      let originalDraftStillAttached = self.draft?.reference.id == draftID
        && self.draft?.reference.sha256 == imageHash
      let candidateNoPhotoFallbackStillActive: Bool
      if self.usesSubjectFirstCandidate, self.draft == nil,
        case .manual(let activeDraftID) = self.flowState,
        activeDraftID == nil
      {
        candidateNoPhotoFallbackStillActive = true
      } else {
        candidateNoPhotoFallbackStillActive = false
      }
      guard originalDraftStillAttached || candidateNoPhotoFallbackStillActive else {
        return
      }
      let requiresFullAppRestart = await self.inference.requiresFullAppRestartAfterCancellation()
      if requiresFullAppRestart {
        self.markRestartRequiredForManualFallback(draftID: draftID)
      }
      await self.inference.discardRepairContext(draftURL: draft.url)
    }
  }

  /// One stable AI-suggestion label per appearance/assessment control for the
  /// provider-neutral (V2) photo review. Yes, No, and Not sure all remain
  /// visibly unconfirmed and editable until the single whole-entry save.
  private static func deriveAIReadHints(
    receipt: PhotoSuggestionEngineReceipt,
    fused: PhotoSuggestionPayloadV2
  ) -> [String: String] {
    var hints: [String: String] = [:]

    hints["redMaterial"] = PhotoAppearanceSuggestionCopy.redBloodLike(
      fused.redAppearingMaterial.appearancePrefillFlag
    )
    hints["blackAppearance"] = PhotoAppearanceSuggestionCopy.blackOrTarry(
      fused.blackAppearance.appearancePrefillFlag
    )
    hints["blackTarry"] = PhotoAppearanceSuggestionCopy.blackOrTarry(
      fused.blackTarryAppearance.appearancePrefillFlag
    )

    // Apparent color already shows as a confirmable suggestion whenever the
    // fused value is non-nil, so a hint is only additive when fusion could
    // not settle on one. Only a QUALIFIED, validly-parsed (accepted, usable)
    // raw color read may be surfaced — never an unqualified or
    // forced-not-sure field, and never a synthesized guess.
    if fused.apparentColor == nil,
      let colorRecord = receipt.decomposedFieldProvenance?.runEvidence.fields
        .first(where: { $0.field == .color }),
      colorRecord.qualified,
      colorRecord.parsed.isUsableQualifiedLabel
    {
      hints["apparentColor"] =
        "AI read: \(colorRecord.parsed.label.capitalized) — low confidence, appearance only"
    }

    // Subject, Bristol, and mixed-form model heads are unqualified by policy
    // (Qwen3DecomposedContract.forcedNotSureFields): never synthesize a value
    // hint for them, only this static, non-diagnostic reminder.
    let staticHint = "Photo AI cannot assess this yet — answer from what you saw."
    hints["subject"] = staticHint
    hints["bristol"] = staticHint
    hints["mixedForm"] = staticHint

    return hints
  }

  private func analyze(
    with engine: PhotoSuggestionEngine,
    draft: PreparedDraft,
    attemptID: UUID
  ) {
    let draftID = draft.reference.id
    let imageHash = draft.reference.sha256
    let requestID = UUID()
    isBusy = true
    statusMessage = "Reading photo"
    flowState = .reading(draftID: draftID, imageHash: imageHash)

    analysisTask?.cancel()
    analysisTaskID = requestID
    analysisTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.analysisTaskID == requestID {
          self.isBusy = self.workflow.isLocked
          self.analysisTask = nil
          self.analysisTaskID = nil
        }
      }
      do {
        let input = try self.imageStore.preparedPhotoSuggestionInput(
          for: draft,
          requestID: requestID
        )
        let run = try await engine.suggest(input)
        try Task.checkCancellation()
        let validatedSuggestion = try run.receipt.validate(
          rawOutputUTF8: run.rawOutputUTF8
        )
        guard run.receipt.requestID == requestID,
          run.receipt.analyzedImageSHA256 == input.sha256,
          run.receipt.analyzedPixelWidth == input.pixelWidth,
          run.receipt.analyzedPixelHeight == input.pixelHeight,
          run.receipt.identity == self.preparedPhotoSuggestionEngineIdentity,
          run.suggestion == validatedSuggestion,
          run.canonicalParsedJSON == run.receipt.canonicalParsedJSON,
          run.canonicalParsedJSON
            == (try PhotoSuggestionPayloadV2Parser.canonicalJSON(
              validatedSuggestion
            )),
          let receiptJSON = run.receipt.canonicalJSON,
          let rawOutput = String(data: run.rawOutputUTF8, encoding: .utf8)
        else { throw PhotoSuggestionEngineReceiptError.invalidReceipt }

        guard self.workflow.finishAttempt(attemptID),
          self.draft?.reference.id == draftID,
          self.draft?.reference.sha256 == imageHash,
          case .reading(draftID, imageHash) = self.flowState
        else { return }

        let storedSuggestion = StoredModelVisualSuggestion.fullPrefillV2(
          validatedSuggestion
        )
        let observation = storedSuggestion.visualObservation
        let session = ReviewSession(observation: observation)
        self.withDraftSnapshotPersistenceSuppressed {
          self.modelSuggestion = storedSuggestion
          self.reviewedObservation = observation
          self.reviewSession = session
          self.confirmedStoolPresence = validatedSuggestion.stoolPresence
          self.confirmedBristolType = validatedSuggestion.bristolType
          self.confirmedForm = validatedSuggestion.form
          self.confirmedApparentColor = validatedSuggestion.apparentColor
            ?? "unable_to_assess"
          self.mixedForm = storedSuggestion.mixedFormSuggestion
          self.confirmedPhotoUsable = validatedSuggestion.imageUsable
          self.confirmedRetakeReason = validatedSuggestion.retakeReason
          self.redBlood = validatedSuggestion.redAppearingMaterial.appearancePrefillFlag
          self.blackAppearance = validatedSuggestion.blackAppearance.appearancePrefillFlag
          self.blackTarry = validatedSuggestion.blackTarryAppearance.appearancePrefillFlag
          self.didChooseBristolType = true
          self.didChooseMixedForm = true
          self.didReviewPhotoUsability = true
          self.analysisSource = .onDevicePhotoSuggestion
          self.analysisPipelineVersion =
            run.receipt.identity.analysisPipelineVersion
          self.originalValidatedJSON = rawOutput
          self.fullPrefillNormalization = nil
          self.photoSuggestionEngineReceiptJSON = receiptJSON
          self.aiReadHints = (try? PhotoSuggestionEngineReceipt.decode(receiptJSON))
            .map {
              Self.deriveAIReadHints(receipt: $0, fused: validatedSuggestion)
            } ?? [:]
          self.modelSuggestedImageSHA256 = imageHash
          self.modelSuggestedAt = run.receipt.endedAt
          self.generationStartedAt = run.receipt.startedAt
          self.generationEndedAt = run.receipt.endedAt
          self.inferenceParsePath = .direct
          self.statusMessage = nil
          self.flowState = .reviewing(draftID: draftID, review: session)
        }
        self.persistDraftSnapshotIfPossible()
      } catch {
        let ownsAttempt = self.workflow.finishAttempt(attemptID)
        guard self.draft?.reference.id == draftID,
          self.draft?.reference.sha256 == imageHash
        else { return }
        if !ownsAttempt {
          guard self.workflow.analysisWasTimedOut,
            case .reading = self.flowState
          else { return }
          self.activateManualFallback()
          return
        }
        let requiresRestart = (error as? PhotoSuggestionEngineError)?
          .requiresFullAppRestart == true
        self.activateManualFallback(
          requiresFullAppRestart: requiresRestart
        )
      }
    }

    timeoutTask?.cancel()
    let timeout = analysisTimeout
    timeoutTask = Task { [weak self] in
      try? await Task.sleep(for: timeout)
      guard let self, !Task.isCancelled else { return }
      guard self.workflow.timeoutAttemptAndBeginManualEntry(
        attemptID,
        keepingDraft: true
      ) else { return }
      let cancelledTask = self.analysisTask
      cancelledTask?.cancel()
      guard self.draft?.reference.id == draftID,
        self.draft?.reference.sha256 == imageHash
      else { return }
      self.presentManualFallback(for: draftID)
      let disposition = await engine.cancel(requestID: requestID)
      await cancelledTask?.value
      guard self.draft?.reference.id == draftID else { return }
      if disposition == .fullAppRestartRequired {
        self.markRestartRequiredForManualFallback(draftID: draftID)
      }
    }
  }

  private struct ParsedModelSuggestion {
    let suggestion: StoredModelVisualSuggestion
    let normalization: FullPrefillNormalizationReceiptV1?
  }

  private func parseModelSuggestion(_ raw: String) throws -> ParsedModelSuggestion {
    if configuration.usesRawPhotoV1Schema {
      #if DEBUG || HACKATHON_EMBEDDED_GEMMA
      if configuration.usesFullPrefillCandidate {
        let normalized = try FullPrefillDependentFieldAbstentionV1
          .parseAndNormalize(raw)
        return ParsedModelSuggestion(
          suggestion: .fullPrefillV1(normalized.normalizedSuggestion),
          normalization: FullPrefillNormalizationReceiptV1(result: normalized)
        )
      }
      #endif
      return ParsedModelSuggestion(
        suggestion: .photoV1(try PhotoSuggestionV1Parser.parse(raw)),
        normalization: nil
      )
    }
    return ParsedModelSuggestion(
      suggestion: .legacy(try ObservationParser.parse(raw)),
      normalization: nil
    )
  }

  private static func resolvedModelSuggestion(
    raw: String,
    normalization: FullPrefillNormalizationReceiptV1?
  ) throws -> StoredModelVisualSuggestion {
    if let normalization {
      return .fullPrefillV1(
        try normalization.validate(rawResponse: raw)
      )
    }
    return try StoredModelVisualSuggestion.parse(raw)
  }

  private func canonicalModelSuggestion(
    _ suggestion: StoredModelVisualSuggestion
  ) throws -> String {
    switch suggestion {
    case .legacy(let observation):
      return try ObservationParser.canonicalJSON(observation)
    case .photoV1(let raw):
      return try PhotoSuggestionV1Parser.canonicalJSON(raw)
    case .fullPrefillV1(let raw):
      return try FullPrefillPhotoSuggestionV1Parser.canonicalJSON(raw)
    case .fullPrefillV2(let raw):
      return try PhotoSuggestionPayloadV2Parser.canonicalJSON(raw)
    }
  }

  func cancelReading() {
    guard let draft else { return }
    invalidatePhotoSuggestionEnginePreparation()
    let cancelledAnalysisTask = analysisTask
    let cancelledRequestID = analysisTaskID
    cancelledAnalysisTask?.cancel()
    timeoutTask?.cancel()
    invalidateWorkflowKeepingDraft(draft)
    guard workflow.beginManualEntry(keepingDraft: true) else { return }
    let draftID = draft.reference.id
    presentManualFallback(for: draftID)
    Task {
      let requiresFullAppRestart: Bool
      if let photoSuggestionEngine, let cancelledRequestID {
        let disposition = await photoSuggestionEngine.cancel(
          requestID: cancelledRequestID
        )
        await cancelledAnalysisTask?.value
        requiresFullAppRestart = disposition == .fullAppRestartRequired
      } else {
        await cancelledAnalysisTask?.value
        requiresFullAppRestart = await inference
          .requiresFullAppRestartAfterCancellation()
        await inference.discardRepairContext(draftURL: draft.url)
      }
      guard self.draft?.reference.id == draftID else { return }
      if requiresFullAppRestart {
        self.markRestartRequiredForManualFallback(draftID: draftID)
      }
    }
  }

  /// An in-flight provider request must never continue across an app privacy
  /// boundary. Review/manual/saved states are intentionally left untouched.
  func handleAppBecameInactive() {
    switch flowState {
    case .reading:
      invalidatePhotoSuggestionEnginePreparation()
      cancelReading()
    case .preparingPhoto(let preparationID):
      guard let photoTransfer,
        photoTransfer.preparationID == preparationID
      else { return }
      invalidatePhotoSuggestionEnginePreparation()
      transitionPhotoTransferToManual(
        photoTransfer,
        message: "Photo selection was interrupted. Continue manually; if the selected photo finishes loading, it will stay manual."
      )
    default:
      return
    }
  }

  func retryAnalysis() {
    guard !usesPublicManualFallback else { return }
    guard let draft, canReplaceOrClear else { return }
    if let recommendation = photoQualityRecommendation,
      recommendation.severity == .hard
    {
      statusMessage = recommendation.message
      flowState = .failed(
        draftID: draft.reference.id,
        message: recommendation.message
      )
      return
    }
    invalidatePhotoSuggestionEnginePreparation()
    invalidateWorkflowKeepingDraft(draft)
    flowState = .reading(draftID: draft.reference.id, imageHash: draft.reference.sha256)
    statusMessage = "Reading photo"
    queueAutomaticAnalysisIfPossible()
  }

  /// Opens the same required review form without relying on a model result.
  /// A photo is retained after suggestion failure; the start-screen path has
  /// no photo and therefore creates a fully manual record.
  func enterManualMode() {
    guard canReplaceOrClear else { return }
    invalidatePhotoSuggestionEnginePreparation()
    analysisTask?.cancel()
    timeoutTask?.cancel()
    if usesSubjectFirstCandidate, draft != nil {
      _ = transitionCandidatePhotoToManual(
        subjectAnswer: subjectConfirmation,
        message: "Enter the details manually. The photo was not attached."
      )
      return
    }
    let keepsPhoto = draft != nil
    guard workflow.beginManualEntry(keepingDraft: keepsPhoto) else { return }
    withDraftSnapshotPersistenceSuppressed {
      if !keepsPhoto { manualEntryCapturedAtBaseline = capturedAt }
      reviewedObservation = nil
      reviewSession = nil
      resetModelSuggestionState()
      resetClinicalReview()
      analysisSource = .manual
      analysisPipelineVersion = nil
      statusMessage = keepsPhoto
        ? "Photo kept. Enter the details yourself before saving."
        : nil
      flowState = .manual(draftID: draft?.reference.id)
      isBusy = false
    }
    persistDraftSnapshotIfPossible()
  }

  /// Secondary action for a deterministic hard-quality stop. The already
  /// retained photo and draft stay untouched; only the presentation advances
  /// from the retake choice to the existing complete manual form.
  func keepLowQualityPhotoAndContinueManually() {
    guard let recommendation = photoQualityRecommendation,
      recommendation.severity == .hard,
      let draft,
      workflow.manualEntryActive,
      canReplaceOrClear
    else { return }
    photoQualityRecommendation = nil
    retainedLowQualityManualReview = true
    statusMessage = "Photo kept. Continue manually; the photo will remain with the saved entry and PDF."
    flowState = .manual(draftID: draft.reference.id)
    persistDraftSnapshotIfPossible()
  }

  /// Borderline advice is optional and never blocks analysis or saving.
  func keepBorderlinePhoto() {
    guard photoQualityRecommendation?.severity == .borderline else { return }
    photoQualityRecommendation = nil
    persistDraftSnapshotIfPossible()
  }

  /// A failed/invalid/timed-out model result never supplies provenance or a
  /// confident visual default. It leaves the retained photo attached and
  /// opens a complete conservative tuple; photo usability/retake still require
  /// an explicit person choice because failure cannot establish either.
  private func prefillConservativeManualFallback() {
    confirmedStoolPresence = .uncertain
    confirmedBristolType = nil
    confirmedForm = "unable_to_assess"
    confirmedApparentColor = "unable_to_assess"
    confirmedPhotoUsable = nil
    confirmedRetakeReason = nil
    mixedForm = .unsure
    redBlood = .unsure
    blackAppearance = .unsure
    blackTarry = .unsure
    didChooseBristolType = true
    didChooseMixedForm = true
    didReviewPhotoUsability = false
  }

  private func activateManualFallback(requiresFullAppRestart: Bool = false) {
    if usesSubjectFirstCandidate {
      let message = requiresFullAppRestart
        ? "On-device analysis didn’t finish. Enter the details manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it."
        : "We couldn’t prepare a reliable suggestion. Enter the details manually."
      _ = transitionCandidatePhotoToManual(
        subjectAnswer: subjectConfirmation,
        message: message
      )
      if requiresFullAppRestart { self.requiresFullAppRestart = true }
      return
    }
    guard let draft, workflow.beginManualEntry(keepingDraft: true) else { return }
    presentManualFallback(for: draft.reference.id, requiresFullAppRestart: requiresFullAppRestart)
  }

  private func presentManualFallback(for draftID: UUID, requiresFullAppRestart: Bool = false) {
    automaticAnalysisContext = nil
    if usesSubjectFirstCandidate {
      let message = requiresFullAppRestart
        ? "On-device analysis didn’t finish. Enter the details manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it."
        : "We couldn’t prepare a reliable suggestion. Enter the details manually."
      _ = transitionCandidatePhotoToManual(
        subjectAnswer: subjectConfirmation,
        message: message
      )
      if requiresFullAppRestart { self.requiresFullAppRestart = true }
      return
    }
    if requiresFullAppRestart { self.requiresFullAppRestart = true }
    withDraftSnapshotPersistenceSuppressed {
      reviewedObservation = nil
      reviewSession = nil
      resetModelSuggestionState()
      resetPhotoReview()
      prefillConservativeManualFallback()
      analysisSource = .manual
      analysisPipelineVersion = nil
      statusMessage = requiresFullAppRestart
        ? "On-device analysis didn’t finish. Your photo is still here. Continue manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it."
        : "We couldn’t prepare a suggestion. Your photo is still here. Choose the closest stool type yourself to continue."
      flowState = .manual(draftID: draftID)
      isBusy = false
    }
    persistDraftSnapshotIfPossible()
  }

  private func markRestartRequiredForManualFallback(draftID: UUID) {
    if usesSubjectFirstCandidate, draft == nil,
      case .manual(let activeDraftID) = flowState,
      activeDraftID == nil
    {
      requiresFullAppRestart = true
      statusMessage = "On-device analysis didn’t finish. Enter the details manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it."
      persistDraftSnapshotIfPossible()
      return
    }
    guard draft?.reference.id == draftID,
      case .manual(let activeDraftID) = flowState,
      activeDraftID == draftID
    else { return }
    requiresFullAppRestart = true
    statusMessage = "On-device analysis didn’t finish. Your photo is still here. Continue manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it."
    persistDraftSnapshotIfPossible()
  }

  private func handlePreparationFailure(
    draftID: UUID?,
    requiresFullAppRestart: Bool,
    message: String
  ) {
    if requiresFullAppRestart { self.requiresFullAppRestart = true }
    guard let draftID else {
      if draft == nil { statusMessage = message }
      return
    }
    guard draft?.reference.id == draftID else { return }
    switch flowState {
    case .manual(let activeDraftID) where activeDraftID == draftID:
      if requiresFullAppRestart {
        markRestartRequiredForManualFallback(draftID: draftID)
      } else {
        statusMessage = message
        persistDraftSnapshotIfPossible()
      }
    case .reading(let activeDraftID, _) where activeDraftID == draftID:
      activateManualFallback(requiresFullAppRestart: requiresFullAppRestart)
    default:
      // A stale preparation result must not reinitialize a newer review,
      // replacement photo, saved entry, or manually edited form.
      return
    }
  }

  #if DEBUG
  var hasTrackedAnalysisTaskForTesting: Bool { analysisTask != nil }
  #endif

  private func invalidateWorkflowKeepingDraft(_ currentDraft: PreparedDraft) {
    var fresh = NewEntryWorkflow()
    let preparationID = fresh.beginPreparation()
    _ = fresh.finishPreparation(preparationID, prepared: currentDraft.reference)
    workflow = fresh
  }

  func prepareModel() async {
    guard canPrepareModel else { return }
    let preparationDraftID = draft?.reference.id
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
      let requiresFullAppRestart = await inference.requiresFullAppRestartAfterCancellation()
      let message = requiresFullAppRestart
        ? "On-device analysis didn’t finish getting ready. Continue manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it."
        : "Local model preparation failed — you can still save manually"
      if autoAnalysisEnabled {
        handlePreparationFailure(
          draftID: preparationDraftID,
          requiresFullAppRestart: requiresFullAppRestart,
          message: message
        )
      } else {
        if requiresFullAppRestart { self.requiresFullAppRestart = true }
        statusMessage = message
      }
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
    guard let original = reviewSession?.original else { return }
    switch field {
    case .bristolType:
      updateConfirmedBristolType(original.apparentBristolType)
    case .mixedForm:
      updateMixedForm(ClinicalValidation.initialMixedFormSuggestion(from: original))
    case .photoUsable:
      updateConfirmedPhotoUsable(original.imageUsable)
    }
  }

  /// Compatibility hook for the developer harness. Ordinary UI edits only
  /// the three essential clinical review fields through the typed methods.
  func updateReview(field: ReviewField, _ change: (VisualObservation) -> VisualObservation) {
    guard var session = reviewSession else { return }
    withDraftSnapshotPersistenceSuppressed {
      session.reviewed = change(session.reviewed)
      switch field {
      case .bristolType:
        confirmedBristolType = session.reviewed.apparentBristolType
        didChooseBristolType = true
      case .mixedForm:
        mixedForm = ClinicalValidation.initialMixedFormSuggestion(from: session.reviewed)
        session.reviewedMixedForm = mixedForm
        didChooseMixedForm = true
      case .photoUsable:
        confirmedPhotoUsable = session.reviewed.imageUsable
        didReviewPhotoUsability = true
      }
      session.states[field] = fieldWasEdited(field, in: session) ? .edited : .confirmed
      apply(session)
    }
    persistDraftSnapshotIfPossible()
  }

  /// Retained for the developer harness; the normal UI reviews fields individually.
  func updateReview(_ change: (VisualObservation) -> VisualObservation) {
    guard var session = reviewSession else {
      if let reviewedObservation { self.reviewedObservation = change(reviewedObservation) }
      return
    }
    withDraftSnapshotPersistenceSuppressed {
      session.reviewed = change(session.reviewed)
      confirmedBristolType = session.reviewed.apparentBristolType
      confirmedPhotoUsable = session.reviewed.imageUsable
      mixedForm = ClinicalValidation.initialMixedFormSuggestion(from: session.reviewed)
      redBlood = Self.symptomSuggestion(
        fromMaterialState: session.reviewed.redAppearingMaterial
      )
      blackTarry = Self.symptomSuggestion(
        fromMaterialState: session.reviewed.blackTarryAppearance
      )
      session.reviewedMixedForm = mixedForm
      didChooseBristolType = true
      didChooseMixedForm = true
      didReviewPhotoUsability = true
      for field in ReviewField.allCases {
        session.states[field] = fieldWasEdited(field, in: session) ? .edited : .confirmed
      }
      apply(session)
    }
    persistDraftSnapshotIfPossible()
  }

  func updateConfirmedBristolType(_ type: Int?) {
    withDraftSnapshotPersistenceSuppressed {
      confirmedBristolType = type
      didChooseBristolType = true
      if usesCompleteVisualReview {
        if let type, let form = BristolFormContract.expectedForm(for: type) {
          confirmedForm = form
          mixedForm = .no
        } else {
          confirmedForm = "unable_to_assess"
          mixedForm = .unsure
        }
        didChooseMixedForm = true
      }
      switch ClinicalValidation.conditionalQuestion(for: type) {
      case .strainingOrIncomplete:
        leakageOrAccident = nil
      case .leakageOrAccident:
        strainingOrIncomplete = nil
      case nil:
        strainingOrIncomplete = nil
        leakageOrAccident = nil
      }
      updateEssentialReviewState(.bristolType)
    }
    persistDraftSnapshotIfPossible()
  }

  func chooseDifferentBristolType() {
    guard var session = reviewSession else { return }
    withDraftSnapshotPersistenceSuppressed {
      confirmedBristolType = nil
      didChooseBristolType = false
      strainingOrIncomplete = nil
      leakageOrAccident = nil
      session.reviewed = clinicallyReviewedObservation(from: session.original)
      session.states[.bristolType] = .suggested
      apply(session)
    }
    persistDraftSnapshotIfPossible()
  }

  func updateMixedForm(_ answer: ClinicalTriState?) {
    withDraftSnapshotPersistenceSuppressed {
      mixedForm = answer
      didChooseMixedForm = answer != nil
      if usesCompleteVisualReview {
        switch answer {
        case .yes:
          confirmedBristolType = nil
          confirmedForm = "mixed"
          didChooseBristolType = true
        case .unsure:
          confirmedBristolType = nil
          confirmedForm = "unable_to_assess"
          didChooseBristolType = true
        case .no, nil:
          break
        }
      }
      updateEssentialReviewState(.mixedForm)
    }
    persistDraftSnapshotIfPossible()
  }

  func updateConfirmedPhotoUsable(_ usable: Bool?) {
    withDraftSnapshotPersistenceSuppressed {
      confirmedPhotoUsable = usable
      if usable == true { confirmedRetakeReason = nil }
      if usable == false, confirmedRetakeReason == nil {
        confirmedRetakeReason = .other
      }
      didReviewPhotoUsability = usable != nil
      if usable == false, reviewSession != nil {
        redBlood = .unsure
        blackTarry = .unsure
        if usesProviderNeutralPhotoReview {
          blackAppearance = .unsure
        }
      }
      if usesCompleteVisualReview, usable == false {
        confirmedStoolPresence = .uncertain
        confirmedBristolType = nil
        confirmedForm = "unable_to_assess"
        confirmedApparentColor = "unable_to_assess"
        mixedForm = .unsure
        blackAppearance = .unsure
        strainingOrIncomplete = nil
        leakageOrAccident = nil
        didChooseBristolType = true
        didChooseMixedForm = true
        if var session = reviewSession {
          session.reviewed = VisualObservation(
            imageUsable: false,
            qualityIssue: session.original.qualityIssue == "none"
              ? "other" : session.original.qualityIssue,
            apparentBristolType: nil,
            apparentColor: "unable_to_assess",
            form: "unable_to_assess",
            redAppearingMaterial: "unable_to_assess",
            blackTarryAppearance: "unable_to_assess"
          )
          apply(session)
        }
      }
      updateEssentialReviewState(.photoUsable)
    }
    persistDraftSnapshotIfPossible()
  }

  func updateRetakeReason(_ reason: PhotoRetakeReason?) {
    withDraftSnapshotPersistenceSuppressed {
      confirmedRetakeReason = reason
      if reason != nil {
        confirmedPhotoUsable = false
        confirmedStoolPresence = .uncertain
        confirmedBristolType = nil
        confirmedForm = "unable_to_assess"
        confirmedApparentColor = "unable_to_assess"
        mixedForm = .unsure
        redBlood = .unsure
        blackAppearance = .unsure
        blackTarry = .unsure
        strainingOrIncomplete = nil
        leakageOrAccident = nil
        didReviewPhotoUsability = true
        didChooseBristolType = true
        didChooseMixedForm = true
        if var session = reviewSession {
          session.reviewed = clinicallyReviewedObservation(from: session.original)
          apply(session)
        }
      } else if confirmedPhotoUsable == false {
        confirmedPhotoUsable = true
      }
      updateEssentialReviewState(.photoUsable)
    }
    persistDraftSnapshotIfPossible()
  }

  func updateStoolPresence(_ presence: StoolPresence?) {
    withDraftSnapshotPersistenceSuppressed {
      confirmedStoolPresence = presence
      if usesCompleteVisualReview, presence != .stool {
        confirmedBristolType = nil
        confirmedForm = "unable_to_assess"
        mixedForm = .unsure
        if !usesProviderNeutralPhotoReview {
          confirmedApparentColor = "unable_to_assess"
          redBlood = .unsure
          blackAppearance = .unsure
          blackTarry = .unsure
        }
        strainingOrIncomplete = nil
        leakageOrAccident = nil
        didChooseBristolType = true
        didChooseMixedForm = true
      }
      if var session = reviewSession {
        session.reviewed = clinicallyReviewedObservation(from: session.original)
        apply(session)
      }
    }
    persistDraftSnapshotIfPossible()
  }

  func updateConfirmedForm(_ form: String?) {
    guard form == nil || ObservationParser.forms.contains(form!) else { return }
    withDraftSnapshotPersistenceSuppressed {
      confirmedForm = form
      if usesCompleteVisualReview {
        switch form {
        case "mixed":
          confirmedBristolType = nil
          mixedForm = .yes
        case "unable_to_assess", nil:
          confirmedBristolType = nil
          mixedForm = .unsure
        default:
          confirmedBristolType = Self.bristolType(for: form)
          mixedForm = .no
        }
        didChooseBristolType = true
        didChooseMixedForm = true
      }
      updateEssentialReviewState(.bristolType)
      updateEssentialReviewState(.mixedForm)
    }
    persistDraftSnapshotIfPossible()
  }

  func updateApparentColor(_ color: String?) {
    guard color == nil || ObservationParser.colors.contains(color!) else {
      return
    }
    confirmedApparentColor = color
    guard var session = reviewSession else {
      persistDraftSnapshotIfPossible()
      return
    }
    let current = session.reviewed
    session.reviewed = VisualObservation(
      imageUsable: current.imageUsable,
      qualityIssue: current.qualityIssue,
      apparentBristolType: current.apparentBristolType,
      apparentColor: color ?? "unable_to_assess",
      form: current.form,
      redAppearingMaterial: current.redAppearingMaterial,
      blackTarryAppearance: current.blackTarryAppearance
    )
    apply(session)
    persistDraftSnapshotIfPossible()
  }

  private func updateEssentialReviewState(_ field: ReviewField) {
    guard var session = reviewSession else { return }
    session.reviewed = clinicallyReviewedObservation(from: session.original)
    session.reviewedMixedForm = mixedForm
    session.states[field] = fieldWasEdited(field, in: session) ? .edited : .confirmed
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
    switch field {
    case .bristolType:
      return session.original.apparentBristolType != confirmedBristolType
    case .mixedForm:
      return session.originalMixedForm != session.reviewedMixedForm
    case .photoUsable:
      return session.original.imageUsable != confirmedPhotoUsable
    }
  }

  private func clinicallyReviewedObservation(from original: VisualObservation) -> VisualObservation {
    guard confirmedPhotoUsable != false,
      !usesFullPrefillCandidate || usesProviderNeutralPhotoReview
        || confirmedStoolPresence == .stool
    else {
      return VisualObservation(
        imageUsable: false,
        qualityIssue: confirmedPhotoUsable == false
          ? (original.qualityIssue == "none" ? "other" : original.qualityIssue)
          : "not_target_image",
        apparentBristolType: nil,
        apparentColor: "unable_to_assess",
        form: "unable_to_assess",
        redAppearingMaterial: "unable_to_assess",
        blackTarryAppearance: "unable_to_assess"
      )
    }
    let form: String
    if usesFullPrefillCandidate || usesProviderNeutralPhotoReview,
      let confirmedForm
    {
      form = confirmedForm
    } else if let confirmedBristolType,
      let expected = BristolFormContract.expectedForm(for: confirmedBristolType)
    {
      form = expected
    } else {
      form = mixedForm == .yes ? "mixed" : "unable_to_assess"
    }
    return VisualObservation(
      imageUsable: true,
      qualityIssue: "none",
      apparentBristolType: confirmedBristolType,
      apparentColor: confirmedApparentColor
        ?? reviewSession?.reviewed.apparentColor
        ?? original.apparentColor,
      form: form,
      redAppearingMaterial: Self.materialState(from: redBlood),
      blackTarryAppearance: Self.materialState(from: blackTarry)
    )
  }

  private static func bristolType(for form: String?) -> Int? {
    switch form {
    case "hard_lumps": return 1
    case "lumpy_formed": return 2
    case "cracked_formed": return 3
    case "smooth_formed": return 4
    case "soft_blobs": return 5
    case "mushy": return 6
    case "watery": return 7
    default: return nil
    }
  }

  private static func symptomSuggestion(fromMaterialState state: String) -> SymptomFlag {
    switch state {
    case "not_observed": return .no
    case "apparent": return .yes
    case "possible", "unable_to_assess": return .unsure
    default: return .unsure
    }
  }

  private static func materialState(from flag: SymptomFlag?) -> String {
    switch flag {
    case .no: return "not_observed"
    case .yes: return "apparent"
    case .unsure, nil: return "unable_to_assess"
    }
  }

  private func confirmationFieldProvenance(
    isManual: Bool
  ) -> [ConfirmationField: FieldConfirmationProvenance] {
    let v1Fields = ConfirmationField.allCases.filter {
      $0 != .blackAppearance
    }
    let legacyFields = v1Fields.filter {
      $0 != .retakeReason && $0 != .stoolPresence && $0 != .form
    }
    guard !isManual, let suggestion = modelSuggestion else {
      let manualFields = usesPublicManualFallback
        || usesProviderNeutralPhotoEngine
        ? ConfirmationField.allCases : legacyFields
      return Dictionary(
        uniqueKeysWithValues: manualFields.map {
          ($0, .manualNoSuggestion)
        }
      )
    }
    let original = suggestion.visualObservation
    if let fullPrefillV2 = suggestion.fullPrefillV2Suggestion {
      let comparisons: [ConfirmationField: Bool] = [
        .photoUsable: confirmedPhotoUsable == fullPrefillV2.imageUsable,
        .retakeReason: confirmedRetakeReason == fullPrefillV2.retakeReason,
        .stoolPresence: confirmedStoolPresence == fullPrefillV2.stoolPresence,
        .bristolType: confirmedBristolType == fullPrefillV2.bristolType,
        .form: confirmedForm == fullPrefillV2.form,
        .mixedForm: mixedForm == suggestion.mixedFormSuggestion,
        .apparentColor:
          (apparentColor ?? "unable_to_assess")
            == (fullPrefillV2.apparentColor ?? "unable_to_assess"),
        .redMaterial: redBlood == fullPrefillV2.redAppearingMaterial.appearancePrefillFlag,
        .blackAppearance: blackAppearance == fullPrefillV2.blackAppearance.appearancePrefillFlag,
        .blackTarry: blackTarry == fullPrefillV2.blackTarryAppearance.appearancePrefillFlag,
      ]
      return Dictionary(
        uniqueKeysWithValues: ConfirmationField.allCases.map { field in
          (field, comparisons[field] == true
            ? .acceptedUnchanged : .editedBeforeConfirmation)
        }
      )
    }
    if usesFullPrefillCandidate,
      let fullPrefill = suggestion.fullPrefillSuggestion
    {
      let comparisons: [ConfirmationField: Bool] = [
        .photoUsable: confirmedPhotoUsable == fullPrefill.imageUsable,
        .retakeReason: confirmedRetakeReason == fullPrefill.retakeReason,
        .stoolPresence: confirmedStoolPresence == fullPrefill.stoolPresence,
        .bristolType: confirmedBristolType == fullPrefill.bristolType,
        .form: confirmedForm == fullPrefill.form,
        .mixedForm: mixedForm == suggestion.mixedFormSuggestion,
        .apparentColor:
          (reviewSession?.reviewed.apparentColor ?? "unable_to_assess")
            == (fullPrefill.apparentColor ?? "unable_to_assess"),
        .redMaterial: redBlood == fullPrefill.redAppearingMaterial.appearancePrefillFlag,
        .blackTarry: blackTarry == fullPrefill.blackTarryAppearance.appearancePrefillFlag,
      ]
      return Dictionary(
        uniqueKeysWithValues: v1Fields.map { field in
          (field, comparisons[field] == true
            ? .acceptedUnchanged : .editedBeforeConfirmation)
        }
      )
    }
    let comparisons: [ConfirmationField: Bool] = [
      .photoUsable: confirmedPhotoUsable == original.imageUsable,
      .retakeReason: true,
      .stoolPresence: true,
      .bristolType: confirmedBristolType == original.apparentBristolType,
      .form: true,
      .mixedForm: mixedForm == suggestion.mixedFormSuggestion,
      .apparentColor: (reviewSession?.reviewed.apparentColor ?? "unable_to_assess")
        == original.apparentColor,
      .redMaterial: redBlood == Self.symptomSuggestion(
        fromMaterialState: original.redAppearingMaterial
      ),
      .blackTarry: blackTarry == Self.symptomSuggestion(
        fromMaterialState: original.blackTarryAppearance
      ),
    ]
    return Dictionary(uniqueKeysWithValues: legacyFields.map { field in
      (field, comparisons[field] == true ? .acceptedUnchanged : .editedBeforeConfirmation)
    })
  }

  func save() {
    guard canSave, workflow.beginSave() else { return }
    // Save freezes the accepted manual draft before writing its transaction
    // snapshot. A PhotosPicker transfer may ignore cancellation and finish
    // later, but it no longer has authority to replace this retryable draft.
    invalidatePhotoTransfer()
    isBusy = true
    flowState = .saving(draftID: draft?.reference.id)
    var entryCommitted = false
    do {
      let isManual = analysisSource == .manual || reviewSession == nil
      if !isManual {
        guard let draft,
          modelSuggestedImageSHA256 == draft.reference.sha256
        else { throw GITimelineError.invalidEntryProvenance }
      }
      let safetyGuidance = SafetyRules.guidance(
        redBlood: redBlood,
        blackTarry: blackTarry
      )
      let fieldProvenance = confirmationFieldProvenance(isManual: isManual)
      let anyEdited = fieldProvenance.values.contains(.editedBeforeConfirmation)
      let provenance: EntryProvenance = isManual ? .manual : (anyEdited ? .ai_edited : .ai_unedited)
      #if DEBUG
      let demoKind = selectedDemoFixture?.rawValue
      #else
      let demoKind: String? = nil
      #endif
      let finalID = pendingEntryID ?? UUID()
      // JSON's ISO-8601 strategy persists whole seconds. Create the immutable
      // transaction timestamp at that same precision so a relaunch cannot
      // silently change the fingerprint merely by decoding the snapshot.
      let reviewedAt = pendingReviewedAt ?? Date(
        timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)
      )
      let usesProviderNeutralV2Suggestion = !isManual
        && modelSuggestion?.fullPrefillV2Suggestion != nil
      let recordsEngineBackedManualTuple = isManual
        && usesProviderNeutralPhotoEngine
      let recordsCompleteVisualTuple = usesPublicManualFallback
        || recordsEngineBackedManualTuple
        || (!isManual
          && (usesFullPrefillCandidate || usesProviderNeutralV2Suggestion))
      let recordsSeparateBlackAppearance = usesPublicManualFallback
        || recordsEngineBackedManualTuple
        || usesProviderNeutralV2Suggestion
      let confirmation = ConfirmedEntrySnapshotV1(
        confirmedAt: reviewedAt,
        personConfirmedPhotoUsable: draft == nil ? nil : confirmedPhotoUsable,
        initiallyAcceptedPhotoUsable: !isManual
          && recordsCompleteVisualTuple && draft != nil
          ? confirmedPhotoUsable : nil,
        initiallyAcceptedRetakeReason: !isManual
          && recordsCompleteVisualTuple && draft != nil
          ? confirmedRetakeReason : nil,
        initiallyAcceptedStoolPresence: !isManual
          && recordsCompleteVisualTuple ? confirmedStoolPresence : nil,
        initiallyAcceptedBristolType: !isManual
          && recordsCompleteVisualTuple ? confirmedBristolType : nil,
        initiallyAcceptedForm: !isManual
          && recordsCompleteVisualTuple ? confirmedForm : nil,
        initiallyAcceptedMixedForm: !isManual
          && recordsCompleteVisualTuple ? mixedForm : nil,
        initiallyAcceptedApparentColor: !isManual
          && recordsCompleteVisualTuple ? apparentColor : nil,
        initiallyAcceptedRed: !isManual
          && recordsCompleteVisualTuple ? redBlood : nil,
        initiallyAcceptedBlackAppearance: usesProviderNeutralV2Suggestion
          ? blackAppearance : nil,
        initiallyAcceptedBlackTarry: !isManual
          && recordsCompleteVisualTuple ? blackTarry : nil,
        personConfirmedRetakeReason: recordsCompleteVisualTuple && draft != nil
          ? confirmedRetakeReason : nil,
        personConfirmedStoolPresence: recordsCompleteVisualTuple
          ? confirmedStoolPresence : nil,
        personConfirmedBristolType: confirmedBristolType,
        personConfirmedForm: recordsCompleteVisualTuple
          ? confirmedForm : nil,
        personConfirmedMixedForm: mixedForm,
        personConfirmedApparentColor: recordsCompleteVisualTuple
          ? apparentColor
          : (isManual ? nil : reviewSession?.reviewed.apparentColor),
        personConfirmedRed: redBlood,
        personConfirmedBlackAppearance: recordsSeparateBlackAppearance
          ? blackAppearance : nil,
        personConfirmedBlackTarry: blackTarry,
        fieldProvenance: fieldProvenance,
        personConfirmedSubject: nil
      )
      try confirmation.validate(hasPhoto: draft != nil, hasModelSuggestion: !isManual)
      guard let confirmationJSON = confirmation.canonicalJSON else {
        throw GITimelineError.invalidEntryProvenance
      }
      let modelProvenanceJSON: String?
      let persistedModelID: String?
      if isManual {
        modelProvenanceJSON = nil
        persistedModelID = nil
      } else if usesProviderNeutralV2Suggestion {
        guard let receiptJSON = photoSuggestionEngineReceiptJSON,
          let rawOutput = originalValidatedJSON?.data(using: .utf8),
          let receipt = try? PhotoSuggestionEngineReceipt.decode(receiptJSON),
          (try? receipt.validate(rawOutputUTF8: rawOutput)) != nil,
          receipt.analyzedImageSHA256 == draft?.reference.sha256,
          receipt.identity.analysisPipelineVersion == analysisPipelineVersion
        else { throw GITimelineError.invalidEntryProvenance }
        modelProvenanceJSON = receiptJSON
        persistedModelID = receipt.identity.modelID
      } else {
        modelProvenanceJSON = descriptor.flatMap {
          InferenceProvenanceSnapshot(
            descriptor: $0,
            configuration: configuration,
            executionLocation: executionLocation,
            sanitizedImageSHA256: modelSuggestedImageSHA256,
            suggestedAt: modelSuggestedAt,
            generationStartedAt: generationStartedAt,
            generationEndedAt: generationEndedAt,
            parsePath: inferenceParsePath,
            suggestionSchemaVersion: usesFullPrefillCandidate
              ? FullPrefillPhotoSuggestionV1.schemaVersion
              : (configuration.usesRawPhotoV1Schema
                ? PhotoSuggestionV1.schemaVersion
                : configuration.promptVersion),
            fullPrefillNormalization: fullPrefillNormalization
          ).canonicalJSON
        }
        persistedModelID = descriptor?.modelID
      }
      let input = EntryInput(
        id: finalID,
        capturedAt: capturedAt,
        draftURL: draft?.url,
        imageSHA256: draft?.reference.sha256,
        redBlood: redBlood,
        blackAppearance: recordsSeparateBlackAppearance
          ? blackAppearance : nil,
        blackTarry: blackTarry,
        dizziness: dizziness,
        severePain: severePain,
        note: note.isEmpty ? nil : note,
        painScore: painScore,
        urgency: urgency,
        confirmedBristolType: confirmedBristolType,
        confirmedPhotoUsable: draft == nil ? nil : confirmedPhotoUsable,
        mixedForm: mixedForm,
        strainingOrIncomplete: strainingOrIncomplete,
        leakageOrAccident: leakageOrAccident,
        analysisSource: analysisSource,
        analysisPipelineVersion: isManual ? nil : analysisPipelineVersion,
        provenance: provenance,
        reviewedAt: reviewedAt,
        originalAIJSON: isManual ? nil : originalValidatedJSON,
        reviewedJSON: confirmationJSON,
        modelID: persistedModelID,
        modelProvenanceJSON: modelProvenanceJSON,
        demoKind: demoKind,
        imageFilename: draft == nil ? nil : "\(finalID.uuidString).jpg"
      )
      let fingerprint = try EntryTransactionFingerprint.make(for: input)
      pendingEntryID = finalID
      pendingEntryFingerprint = fingerprint
      pendingReviewedAt = reviewedAt
      // This write-ahead snapshot binds the exact immutable EntryInput payload
      // (not merely its UUID) before SwiftData can commit.
      let transactionSnapshot = makeDraftSnapshot(for: draft)
      try draftSnapshotStore.save(transactionSnapshot)
      try store.save(input, imageStore: imageStore)
      entryCommitted = true
      guard try store.pendingTransactionState(
        id: finalID,
        fingerprint: fingerprint,
        imageStore: imageStore
      ) == .exactDurable else {
        throw GITimelineError.photoRecoveryRequired
      }
      // Deterministic test hook that leaves the durable record and snapshot in
      // place exactly as a process termination would, before cleanup begins.
      if postCommitCleanupInterruption() { return }
      // Delete only this transaction's verified draft first and its snapshot
      // last. Either crash boundary is safe to retry at cold launch.
      try draftSnapshotStore.finishCommittedTransactionCleanup(transactionSnapshot)
      withDraftSnapshotPersistenceSuppressed {
        resetFormContent()
        savedSafetyGuidance = safetyGuidance
        flowState = .saved(entryID: finalID)
      }
    } catch {
      if entryCommitted {
        // The entry is canonical. Leave the stable pending snapshot in place
        // and make cleanup retryable rather than reporting a false failed save.
        #if INTERNAL_QWEN3_QA
        Self.qaAppendSaveDiagnostic("SAVE_CLEANUP_ERROR \(Date()) \(String(reflecting: error))")
        #endif
        statusMessage = "Your entry was saved, but unfinished-draft cleanup could not finish. Try saving again to retry cleanup."
        workflow.finishSave()
        isBusy = workflow.isLocked
        flowState = .failed(draftID: draft?.reference.id, message: statusMessage ?? "Your entry was saved, but cleanup needs retry.")
        return
      }
      #if INTERNAL_QWEN3_QA
      Self.qaAppendSaveDiagnostic("SAVE_ERROR \(Date()) \(String(reflecting: error))")
      #endif
      statusMessage = error.localizedDescription
      workflow.finishSave()
      isBusy = workflow.isLocked
      flowState = .failed(draftID: draft?.reference.id, message: "Couldn’t save this entry. Your review is still here.")
    }
  }

  #if INTERNAL_QWEN3_QA
  // Evidence-only: written beside the physical-evidence journal so the host
  // can copy it with devicectl; never compiled outside INTERNAL_QWEN3_QA.
  private static func qaAppendSaveDiagnostic(_ line: String) {
    guard let base = try? FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ) else { return }
    let dir = base.appendingPathComponent("Qwen3DecomposedPhysicalQA", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("save-error.log")
    let data = Data((line + "\n").utf8)
    if let handle = try? FileHandle(forWritingTo: url) {
      defer { try? handle.close() }
      try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: url)
    }
  }
  #endif

  func retrySave() {
    if let reviewSession, let draft {
      flowState = .reviewing(draftID: draft.reference.id, review: reviewSession)
    } else {
      flowState = .manual(draftID: draft?.reference.id)
    }
    guard canSave else { return }
    save()
  }

  func startAnotherEntry() {
    guard !isDraftRecoveryBlocked else { return }
    sharedReset()
  }

  func resetAfterJournalErase() {
    invalidatePhotoSuggestionEnginePreparation()
    invalidatePhotoTransfer()
    analysisTask?.cancel()
    timeoutTask?.cancel()
    // This notification is posted only after JournalDataEraser has verified
    // all directories and cleared its marker. These calls merely release any
    // now-stale in-memory references; the eraser is the durable authority.
    draftSnapshotStore.removeSnapshot()
    if let draft {
      imageStore.deleteBestEffort(draft.url)
      Task { await inference.discardRepairContext(draftURL: draft.url) }
    }
    sharedReset()
  }

  func clear() {
    guard canReplaceOrClear else { return }
    invalidatePhotoSuggestionEnginePreparation()
    invalidatePhotoTransfer()
    analysisTask?.cancel()
    timeoutTask?.cancel()
    do {
      try draftSnapshotStore.discardAllUnfinishedDraftFiles()
    } catch {
      draftRestorationNotice = "GI Journal could not confirm that your unfinished entry was fully removed. The form remains blocked while local cleanup is pending; try discarding again. \(error.localizedDescription)"
      canDiscardUnavailableDraft = true
      isDraftRecoveryBlocked = true
      return
    }
    if let draft {
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
    invalidatePhotoSuggestionEnginePreparation()
    invalidatePhotoTransfer()
    workflow.reset()
    draft = nil
    selectedItem = nil
    selectedImage = nil
    reviewedObservation = nil
    reviewSession = nil
    resetModelSuggestionState()
    photoQualityRecommendation = nil
    pendingEntryID = nil
    pendingEntryFingerprint = nil
    pendingReviewedAt = nil
    manualEntryCapturedAtBaseline = nil
    resetClinicalReview()
    capturedAt = Date()
    statusMessage = nil
    isBusy = false
    #if DEBUG
    selectedDemoFixture = nil
    #endif
  }

  private func resetClinicalReview() {
    resetPhotoReview()
    painScore = nil
    urgency = nil
    redBlood = nil
    blackAppearance = nil
    blackTarry = nil
    dizziness = nil
    severePain = nil
    note = ""
  }

  private func resetModelSuggestionState() {
    originalValidatedJSON = nil
    fullPrefillNormalization = nil
    photoSuggestionEngineReceiptJSON = nil
    modelSuggestion = nil
    modelSuggestedImageSHA256 = nil
    modelSuggestedAt = nil
    generationStartedAt = nil
    generationEndedAt = nil
    inferenceParsePath = nil
    aiReadHints = [:]
  }

  /// Replacing or attaching a photo invalidates only photo-derived review.
  /// Human-entered symptom context and notes remain untouched.
  private func resetPhotoReview() {
    confirmedStoolPresence = nil
    confirmedBristolType = nil
    confirmedForm = nil
    confirmedApparentColor = nil
    confirmedPhotoUsable = nil
    confirmedRetakeReason = nil
    subjectConfirmation = nil
    mixedForm = nil
    strainingOrIncomplete = nil
    leakageOrAccident = nil
    didChooseBristolType = false
    didChooseMixedForm = false
    didReviewPhotoUsability = false
    retainedLowQualityManualReview = false
    analysisSource = .manual
    analysisPipelineVersion = nil
  }

  @discardableResult
  private func persistDraftSnapshotIfPossible() -> Bool {
    guard !suppressDraftSnapshotPersistence, !isDraftRecoveryBlocked else { return false }
    guard draft != nil || workflow.manualEntryActive else { return true }
    if draft == nil, !hasMeaningfulManualDraftContent {
      // A pristine no-photo form is not a draft. Removing an older recovery
      // record here also prevents restoring values a person just cleared.
      return draftSnapshotStore.removeSnapshot()
    }
    do {
      try persistCurrentDraftSnapshot()
      return true
    } catch {
      statusMessage = "Your unfinished entry could not be protected locally. \(error.localizedDescription)"
      return false
    }
  }

  private func persistCurrentDraftSnapshot() throws {
    guard draft != nil || workflow.manualEntryActive else { return }
    try draftSnapshotStore.save(makeDraftSnapshot(for: draft))
  }

  private var hasMeaningfulManualDraftContent: Bool {
    guard draft == nil, workflow.manualEntryActive else { return false }
    if let baseline = manualEntryCapturedAtBaseline, capturedAt != baseline { return true }
    return confirmedBristolType != nil
      || confirmedStoolPresence != nil
      || confirmedForm != nil
      || confirmedApparentColor != nil
      || confirmedPhotoUsable != nil
      || subjectConfirmation != nil
      || mixedForm != nil
      || painScore != nil
      || urgency != nil
      || strainingOrIncomplete != nil
      || leakageOrAccident != nil
      || redBlood != nil
      || blackAppearance != nil
      || blackTarry != nil
      || dizziness != nil
      || severePain != nil
      || !note.isEmpty
  }

  private func makeDraftSnapshot(for draft: PreparedDraft?) -> DraftSnapshot {
    let review = reviewSession.map {
      DraftSnapshot.Review(
        original: $0.original,
        reviewed: $0.reviewed,
        originalMixedForm: $0.originalMixedForm,
        reviewedMixedForm: $0.reviewedMixedForm,
        states: Dictionary(uniqueKeysWithValues: $0.states.map { ($0.key.rawValue, $0.value.rawValue) })
      )
    }
    return DraftSnapshot(
      version: DraftSnapshot.currentVersion,
      pendingEntryID: pendingEntryID,
      pendingEntryFingerprint: pendingEntryFingerprint,
      pendingReviewedAt: pendingReviewedAt,
      draft: draft.map { .init(id: $0.reference.id, filename: $0.url.lastPathComponent, sha256: $0.reference.sha256) },
      capturedAt: capturedAt,
      confirmedStoolPresence: confirmedStoolPresence,
      confirmedBristolType: confirmedBristolType,
      confirmedForm: confirmedForm,
      confirmedApparentColor: confirmedApparentColor,
      confirmedPhotoUsable: confirmedPhotoUsable,
      confirmedRetakeReason: confirmedRetakeReason,
      subjectConfirmation: subjectConfirmation,
      mixedForm: mixedForm,
      painScore: painScore,
      urgency: urgency,
      strainingOrIncomplete: strainingOrIncomplete,
      leakageOrAccident: leakageOrAccident,
      redBlood: redBlood,
      blackAppearance: blackAppearance,
      blackTarry: blackTarry,
      dizziness: dizziness,
      severePain: severePain,
      note: note,
      reviewedObservation: reviewedObservation,
      review: review,
      originalValidatedJSON: originalValidatedJSON,
      fullPrefillNormalization: fullPrefillNormalization,
      photoSuggestionEngineReceiptJSON: photoSuggestionEngineReceiptJSON,
      photoQualityRecommendation: photoQualityRecommendation,
      retainedLowQualityManualReview:
        retainedLowQualityManualReview ? true : nil,
      modelSuggestedImageSHA256: modelSuggestedImageSHA256,
      modelSuggestedAt: modelSuggestedAt,
      generationStartedAt: generationStartedAt,
      generationEndedAt: generationEndedAt,
      inferenceParsePath: inferenceParsePath?.rawValue,
      analysisSource: analysisSource,
      analysisPipelineVersion: analysisPipelineVersion,
      didChooseBristolType: didChooseBristolType,
      didChooseMixedForm: didChooseMixedForm,
      didReviewPhotoUsability: didReviewPhotoUsability
    )
  }

  private func withDraftSnapshotPersistenceSuppressed(_ body: () -> Void) {
    suppressDraftSnapshotPersistence = true
    defer { suppressDraftSnapshotPersistence = false }
    body()
  }

  func sharedReset() {
    invalidatePhotoSuggestionEnginePreparation()
    invalidatePhotoTransfer()
    withDraftSnapshotPersistenceSuppressed {
      resetFormContent()
      savedSafetyGuidance = .none
      flowState = .empty
    }
  }
}
