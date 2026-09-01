import Foundation
import SwiftData
import GITimelineCore

@MainActor protocol EntryStoring: AnyObject {
  func save(_ input: EntryInput, imageStore: ImageStore) throws
  func update(
    _ entry: EntryRecord,
    with input: EntryEditInput,
    baselineFingerprint: String,
    at date: Date
  ) throws
  func expectedUpdateFingerprint(
    for entry: EntryRecord,
    input: EntryEditInput,
    baselineFingerprint: String,
    at date: Date
  ) throws -> String
  @discardableResult
  func delete(_ entry: EntryRecord, imageStore: ImageStore) throws -> EntryDeletionOutcome
  func reconcile(imageStore: ImageStore) async throws
  func setDiscussionMark(_ marked: Bool, for entry: EntryRecord, at date: Date) throws
  func pendingTransactionState(id: UUID, fingerprint: String, imageStore: ImageStore) throws -> EntryPendingTransactionState
}

enum EntryPendingTransactionState: Equatable {
  case absent
  case exactDurable
  case conflictOrIncomplete
}

enum EntryDeletionOutcome: Equatable {
  case completed
  /// The SwiftData row is durably gone and the photo is no longer canonical,
  /// but its protected deletion-queue copy remains for launch reconciliation.
  case recordDeletedPhotoCleanupPending
}

extension EntryStoring {
  func setDiscussionMark(_ marked: Bool, for entry: EntryRecord) throws {
    try setDiscussionMark(marked, for: entry, at: Date())
  }
  func update(_ entry: EntryRecord, with input: EntryEditInput) throws {
    try update(
      entry,
      with: input,
      baselineFingerprint: EntryRecordFingerprint.make(for: entry),
      at: Date()
    )
  }
  func update(_ entry: EntryRecord, with input: EntryEditInput, at date: Date) throws {
    try update(
      entry,
      with: input,
      baselineFingerprint: EntryRecordFingerprint.make(for: entry),
      at: date
    )
  }
}

enum EntryStoreFailurePoint {
  case afterInsertBeforeSave
  case afterUpdateBeforeSave
  case afterDeleteBeforeSave
  case afterMarkBeforeSave
  case afterReconcileBeforeSave
}

@MainActor final class EntryStore: EntryStoring {
  typealias FailureInjector = (EntryStoreFailurePoint) throws -> Void

  private struct PhotoAttachment {
    let draftURL: URL
    let expectedSHA256: String
    let targetURL: URL
  }

  private struct EntryUpdatePlan {
    let input: EntryEditInput
    let reviewedJSON: String?
    let provenance: String
  }

  private let context: ModelContext
  private let failureInjector: FailureInjector?
  private let writeGate: JournalWriteGate

  init(
    context: ModelContext,
    failureInjector: FailureInjector? = nil,
    writeGate: JournalWriteGate? = nil
  ) {
    self.context = context
    self.failureInjector = failureInjector
    self.writeGate = writeGate ?? .app
    context.autosaveEnabled = false
  }

  func save(_ input: EntryInput, imageStore: ImageStore) throws {
    try writeGate.requireWritable()
    if (input.note?.count ?? 0) > 500 { throw GITimelineError.noteTooLong }
    let attachment = try validatedPhotoAttachment(for: input, imageStore: imageStore)
    try validateClinicalAndProvenance(input, hasPhoto: attachment != nil)
    let fingerprint = try EntryTransactionFingerprint.make(for: input)

    // A UUID collision is idempotent only when every canonical saved field and
    // the photo identity match exactly and the canonical photo is durable.
    switch try pendingTransactionState(id: input.id, fingerprint: fingerprint, imageStore: imageStore) {
    case .absent:
      break
    case .exactDurable:
      return
    case .conflictOrIncomplete:
      throw GITimelineError.entryTransactionConflict
    }

    var promotedURL: URL?
    do {
      if let attachment {
        // ImageStore rehashes the staged draft immediately before promotion
        // and the canonical JPEG immediately afterward.
        try imageStore.promoteVerifiedDraft(
          attachment.draftURL,
          to: attachment.targetURL,
          expectedSHA256: attachment.expectedSHA256
        )
        promotedURL = attachment.targetURL
      }
      let entry = EntryRecord(input: input)
      context.insert(entry)
      try clearNoBowelMovementMarker(on: input.capturedAt)
      try failureInjector?(.afterInsertBeforeSave)
      try context.save()
      AppFolders.enforceStoreProtection(requireAllStoreFiles: true)
      if let attachment {
        PrivacyDiagnostics.assertCompleteProtection(at: [
          attachment.targetURL.deletingLastPathComponent(),
          attachment.draftURL.deletingLastPathComponent(),
        ])
      }
    } catch {
      context.rollback() // required: prevents a retry from retaining a phantom insert
      if let promotedURL {
        // The untouched draft remains the recovery source.  Do not delete the
        // promoted copy directly; a queue retry handles an interrupted cleanup.
        imageStore.discardUncommittedPromotion(at: promotedURL)
      }
      throw error
    }
  }

  func update(
    _ entry: EntryRecord,
    with input: EntryEditInput,
    baselineFingerprint: String,
    at date: Date
  ) throws {
    try writeGate.requireWritable()
    guard try EntryRecordFingerprint.make(for: entry) == baselineFingerprint else {
      throw GITimelineError.entryTransactionConflict
    }
    let plan = try validatedUpdatePlan(for: entry, input: input)
    let normalized = plan.input
    do {
      entry.capturedAt = normalized.capturedAt
      entry.redBlood = normalized.redBlood?.rawValue
      entry.blackTarry = normalized.blackTarry?.rawValue
      entry.dizziness = normalized.dizziness?.rawValue
      entry.severePain = normalized.severePain?.rawValue
      entry.note = normalized.note
      entry.painScore = normalized.painScore
      entry.urgency = normalized.urgency?.rawValue
      entry.confirmedBristolType = normalized.confirmedBristolType
      entry.confirmedPhotoUsable = normalized.confirmedPhotoUsable
      entry.mixedForm = normalized.mixedForm?.rawValue
      entry.strainingOrIncomplete = normalized.strainingOrIncomplete?.rawValue
      entry.leakageOrAccident = normalized.leakageOrAccident?.rawValue
      entry.reviewedJSON = plan.reviewedJSON
      entry.provenance = plan.provenance
      entry.updatedAt = date
      try clearNoBowelMovementMarker(on: normalized.capturedAt)
      try failureInjector?(.afterUpdateBeforeSave)
      try context.save()
      AppFolders.enforceStoreProtection(requireAllStoreFiles: true)
    } catch {
      context.rollback()
      throw error
    }
  }

  func expectedUpdateFingerprint(
    for entry: EntryRecord,
    input: EntryEditInput,
    baselineFingerprint: String,
    at date: Date
  ) throws -> String {
    try writeGate.requireWritable()
    guard try EntryRecordFingerprint.make(for: entry) == baselineFingerprint else {
      throw GITimelineError.entryTransactionConflict
    }
    let plan = try validatedUpdatePlan(for: entry, input: input)
    return try EntryRecordFingerprint.make(
      for: entry,
      applying: plan.input,
      reviewedJSON: plan.reviewedJSON,
      provenance: plan.provenance,
      updatedAt: date
    )
  }

  @discardableResult
  func delete(_ entry: EntryRecord, imageStore: ImageStore) throws -> EntryDeletionOutcome {
    try writeGate.requireWritable()
    // Resolve every throwing app-scoped path before mutating SwiftData. After
    // context.save(), diagnostics below are deliberately nonthrowing so a
    // durable delete can never be reported as rolled back.
    let protectionURLs = [
      try imageStore.imagesDirectory(),
      try imageStore.draftsDirectory(),
      try imageStore.deletionQueueDirectory(),
    ]
    let stagedDeletion: StagedImageDeletion?
    switch (entry.imageFilename, entry.imageSHA256) {
    case (nil, nil):
      stagedDeletion = nil
    case let (.some(filename), .some(_)):
      guard let image = imageStore.imageURL(filename: filename) else {
        // Do not remove a record while its possible canonical photo reference
        // is malformed or points outside the protected Images directory.
        throw GITimelineError.invalidPhotoAttachment
      }
      stagedDeletion = try imageStore.stageForDeletion(image)
    default:
      throw GITimelineError.invalidPhotoAttachment
    }

    do {
      context.delete(entry)
      try failureInjector?(.afterDeleteBeforeSave)
      try context.save()
    } catch {
      context.rollback()
      if let stagedDeletion {
        do {
          try imageStore.restore(stagedDeletion)
        } catch {
          // The database rollback leaves the entry intact and the queued photo
          // is preserved for launch reconciliation.  Never discard either copy
          // while recovery is uncertain.
          throw GITimelineError.photoRecoveryRequired
        }
      }
      throw error // the image and visible object are restored on failure
    }
    AppFolders.enforceStoreProtection(requireAllStoreFiles: true)
    PrivacyDiagnostics.assertCompleteProtection(at: protectionURLs)
    let finalizedDeletion = stagedDeletion.map { imageStore.finalize($0) } ?? true
    #if DEBUG
    if let stagedDeletion, finalizedDeletion
    {
      assert(!FileManager.default.fileExists(atPath: stagedDeletion.originalURL.path), "Deleted entry image must be absent.")
    }
    #endif
    return finalizedDeletion ? .completed : .recordDeletedPhotoCleanupPending
  }

  func reconcile(imageStore: ImageStore) async throws {
    try writeGate.requireWritable()
    let entries = try context.fetch(FetchDescriptor<EntryRecord>())
    let folder = try imageStore.imagesDirectory()
    let queue = try imageStore.deletionQueueDirectory()
    PrivacyDiagnostics.assertCompleteProtection(at: [folder, queue, try imageStore.draftsDirectory()])

    // Keep every file referenced by even a malformed legacy record.  A bad
    // hash/reference makes that record unavailable, not eligible for cleanup.
    var protectedFilenames = Set<String>()
    var recordsByFilename: [String: [EntryRecord]] = [:]
    for entry in entries {
      guard let rawFilename = entry.imageFilename else { continue }
      // Even an unsafe legacy path can name a recoverable flat JPEG through
      // its final component.  Protect that potential evidence from orphan
      // cleanup, while still marking the record unavailable below.
      let basename = (rawFilename as NSString).lastPathComponent
      if ImageStore.isSafeImageFilename(basename) {
        protectedFilenames.insert(basename)
      }
      guard ImageStore.isSafeImageFilename(rawFilename) else { continue }
      recordsByFilename[rawFilename, default: []].append(entry)
    }
    let referenced = protectedFilenames
    var ambiguousFilenames = Set(recordsByFilename.compactMap { key, records in
      records.count > 1 ? key : nil
    })

    // An interruption after staging a deletion but before database save leaves
    // the record referring to a queued file.  Restore it only when there is a
    // single clear record and no second canonical copy.
    for queued in try imageStore.queuedImageFilesForReconciliation() {
      await Task.yield()
      let filename = queued.lastPathComponent
      guard referenced.contains(filename) else {
        _ = imageStore.finalizeQueuedImage(at: queued)
        continue
      }
      guard recordsByFilename[filename]?.count == 1,
        let canonical = imageStore.imageURL(filename: filename)
      else {
        ambiguousFilenames.insert(filename)
        continue
      }
      if FileManager.default.fileExists(atPath: canonical.path) {
        // Never choose between a canonical and queued copy automatically.
        ambiguousFilenames.insert(filename)
        continue
      }
      do {
        _ = try imageStore.restoreQueuedImage(named: filename)
      } catch {
        ambiguousFilenames.insert(filename)
      }
    }

    // Clean only clear, direct JPEG orphans.  The operation still moves the
    // file through the queue first, making a crash or failed removal retryable.
    for image in try imageStore.canonicalImageFilesForReconciliation() where !referenced.contains(image.lastPathComponent) {
      await Task.yield()
      do {
        if let staged = try imageStore.stageForDeletion(image) {
          _ = imageStore.finalize(staged)
        }
      } catch {
        // An ambiguous orphan is retained.  Reconciliation must not trade
        // recoverability for tidiness.
      }
    }

    var changed = false
    for entry in entries {
      await Task.yield()
      let unavailable = try imageIsUnavailable(
        for: entry,
        imageStore: imageStore,
        ambiguousFilenames: ambiguousFilenames
      )
      if entry.imageUnavailable != unavailable {
        entry.imageUnavailable = unavailable
        entry.updatedAt = Date()
        changed = true
      }
    }
    if changed {
      do {
        try failureInjector?(.afterReconcileBeforeSave)
        try context.save()
        AppFolders.enforceStoreProtection(requireAllStoreFiles: true)
      } catch {
        // A failed reconciliation write must not leave uncommitted
        // imageUnavailable mutations visible in the context later handed to
        // the journal UI. The caller will block launch and retry instead.
        context.rollback()
        throw error
      }
    }
  }

  func setDiscussionMark(_ marked: Bool, for entry: EntryRecord, at date: Date) throws {
    try writeGate.requireWritable()
    entry.markedForDiscussionAt = marked ? date : nil
    entry.updatedAt = date
    do {
      try failureInjector?(.afterMarkBeforeSave)
      try context.save()
      AppFolders.enforceStoreProtection(requireAllStoreFiles: true)
    } catch {
      context.rollback()
      throw error
    }
  }

  func pendingTransactionState(
    id: UUID,
    fingerprint: String,
    imageStore: ImageStore
  ) throws -> EntryPendingTransactionState {
    let descriptor = FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == id })
    let matches = try context.fetch(descriptor)
    guard matches.count == 1, let entry = matches.first else {
      return matches.isEmpty ? .absent : .conflictOrIncomplete
    }
    guard try EntryTransactionFingerprint.make(for: entry) == fingerprint else {
      return .conflictOrIncomplete
    }
    switch (entry.imageFilename, entry.imageSHA256) {
    case (nil, nil):
      return .exactDurable
    case let (.some(filename), .some(hash)):
      return try imageStore.storedImageIsVerified(filename: filename, expectedSHA256: hash)
        ? .exactDurable
        : .conflictOrIncomplete
    default:
      return .conflictOrIncomplete
    }
  }

  private func validatedPhotoAttachment(for input: EntryInput, imageStore: ImageStore) throws -> PhotoAttachment? {
    let photoPartsPresent = [input.draftURL != nil, input.imageSHA256 != nil, input.imageFilename != nil]
    guard photoPartsPresent.allSatisfy({ $0 }) || photoPartsPresent.allSatisfy({ !$0 }) else {
      throw GITimelineError.invalidPhotoAttachment
    }
    guard let draftURL = input.draftURL,
      let expectedSHA256 = input.imageSHA256,
      let filename = input.imageFilename
    else { return nil }
    guard ImageStore.isValidSHA256(expectedSHA256), ImageStore.isSafeImageFilename(filename) else {
      throw GITimelineError.invalidPhotoAttachment
    }
    let target = try imageStore.promotedURL(for: input.id)
    guard target.lastPathComponent == filename else { throw GITimelineError.invalidPhotoAttachment }
    return PhotoAttachment(draftURL: draftURL, expectedSHA256: expectedSHA256, targetURL: target)
  }

  /// A day cannot simultaneously be an explicit zero-event day and contain a
  /// bowel-movement entry. This mutation shares the entry's database commit,
  /// so a failed save restores the marker with the rest of the transaction.
  private func clearNoBowelMovementMarker(on date: Date) throws {
    let calculator = TreatmentResponseCalculator()
    let key = calculator.dayKey(for: date)
    let descriptor = FetchDescriptor<DailyCompletionRecord>(predicate: #Predicate { $0.dayKey == key })
    let matches = try context.fetch(descriptor)
    guard matches.count <= 1 else { throw ClinicalTimelineStoreError.duplicateDailyCompletion }
    if let marker = matches.first, marker.answer == .noBowelMovement {
      context.delete(marker)
    }
  }

  private func validatedUpdatePlan(
    for entry: EntryRecord,
    input: EntryEditInput
  ) throws -> EntryUpdatePlan {
    guard (input.note?.count ?? 0) <= 500 else { throw GITimelineError.noteTooLong }
    let normalized = input.normalizedForPersistence()
    guard ClinicalValidation.validate(
      confirmedBristolType: normalized.confirmedBristolType,
      painScore: normalized.painScore,
      mixedForm: normalized.mixedForm,
      strainingOrIncomplete: normalized.strainingOrIncomplete,
      leakageOrAccident: normalized.leakageOrAccident
    ).isEmpty else { throw GITimelineError.invalidClinicalEntry }
    guard (normalized.confirmedPhotoUsable != nil) == (entry.imageFilename != nil) else {
      throw GITimelineError.invalidPhotoAttachment
    }

    let reviewedJSON: String?
    let changedConfirmedFields: Bool
    if let existing = entry.confirmedEntrySnapshot {
      var fieldProvenance = existing.typedFieldProvenance
      // Additive provenance keys can exist on manual and legacy envelopes.
      // Only the actual subject/form value tuple identifies a full-prefill
      // confirmation; key presence must never reinterpret an older entry.
      let usesFullPrefillEnvelope =
        existing.personConfirmedStoolPresence != nil
        && existing.personConfirmedForm != nil
      let isProviderNeutralV2 = entry.savedAnalysisSource
        == .onDevicePhotoSuggestion
        && entry.originalModelSuggestion?.fullPrefillV2Suggestion != nil
      let changes: [ConfirmationField: Bool] = [
        .photoUsable: entry.confirmedPhotoUsable != normalized.confirmedPhotoUsable,
        .retakeReason: existing.personConfirmedRetakeReason
          != normalized.retakeReason,
        .stoolPresence: usesFullPrefillEnvelope
          && existing.personConfirmedStoolPresence
            != normalized.stoolPresence,
        .bristolType: entry.effectiveConfirmedBristolType != normalized.confirmedBristolType,
        .form: usesFullPrefillEnvelope
          && existing.personConfirmedForm != normalized.form,
        .mixedForm: entry.mixedFormAnswer != normalized.mixedForm,
        .apparentColor: existing.personConfirmedApparentColor != normalized.apparentColor,
        .redMaterial: entry.redBlood.flatMap(SymptomFlag.init(rawValue:)) != normalized.redBlood,
        .blackAppearance: entry.blackAppearanceAnswer
          != normalized.blackAppearance,
        .blackTarry: entry.blackTarry.flatMap(SymptomFlag.init(rawValue:)) != normalized.blackTarry,
      ]
      for (field, changed) in changes where changed {
        fieldProvenance[field] = .editedAfterConfirmation
      }
      let isCandidate = entry.analysisPipelineVersion
        == "gi-v1-direct-sanitized-jpeg-constrained-v1"
      let isFullPrefill = entry.analysisPipelineVersion
        == "gi-v1-photo-full-prefill-ab-v1"
        || entry.analysisPipelineVersion
          == AnalysisPipelineVersion.appStoreRawImageV12SubjectGateTuning
      if usesFullPrefillEnvelope {
        if entry.imageFilename == nil {
          guard normalized.confirmedPhotoUsable == nil,
            normalized.retakeReason == nil
          else { throw GITimelineError.invalidEntryProvenance }
        } else {
          guard normalized.retakeReason != .notTargetImage,
            (normalized.confirmedPhotoUsable == true
              ? normalized.retakeReason == nil
              : normalized.retakeReason != nil)
          else { throw GITimelineError.invalidEntryProvenance }
        }
      }
      if isCandidate {
        guard normalized.redBlood != nil, normalized.blackTarry != nil,
          existing.personConfirmedSubject == true,
          normalized.confirmedPhotoUsable == true,
          candidateImmutableProvenanceIsValid(entry)
        else { throw GITimelineError.invalidEntryProvenance }
        fieldProvenance[.redMaterial] = .independentPersonAnswer
        fieldProvenance[.blackTarry] = .independentPersonAnswer
      }
      if isFullPrefill {
        guard normalized.redBlood != nil, normalized.blackTarry != nil,
          normalized.stoolPresence != nil,
          normalized.form != nil,
          candidateImmutableProvenanceIsValid(entry)
        else { throw GITimelineError.invalidEntryProvenance }
        if normalized.confirmedPhotoUsable == true,
          normalized.stoolPresence == .stool
        {
          switch normalized.mixedForm {
          case .no:
            guard let type = normalized.confirmedBristolType,
              BristolFormContract.expectedForm(for: type)
                == normalized.form
            else { throw GITimelineError.invalidEntryProvenance }
          case .yes:
            guard normalized.confirmedBristolType == nil,
              normalized.form == "mixed"
            else { throw GITimelineError.invalidEntryProvenance }
          case .unsure:
            guard normalized.confirmedBristolType == nil,
              normalized.form == "unable_to_assess"
            else { throw GITimelineError.invalidEntryProvenance }
          case nil:
            throw GITimelineError.invalidEntryProvenance
          }
        } else {
          guard normalized.confirmedBristolType == nil,
            normalized.form == "unable_to_assess",
            normalized.mixedForm == .unsure,
            normalized.apparentColor == "unable_to_assess",
            normalized.redBlood == .unsure,
            normalized.blackTarry == .unsure
          else { throw GITimelineError.invalidEntryProvenance }
        }
      }
      if isProviderNeutralV2 {
        guard normalized.redBlood != nil,
          normalized.blackAppearance != nil,
          normalized.blackTarry != nil,
          normalized.stoolPresence != nil,
          normalized.form != nil,
          let rawResponse = entry.originalAIJSON,
          let validatedSuggestion = try? validatedProviderNeutralV2Suggestion(
            rawResponse: rawResponse,
            modelProvenanceJSON: entry.modelProvenanceJSON,
            modelID: entry.modelID,
            pipelineVersion: entry.analysisPipelineVersion,
            imageSHA256: entry.imageSHA256
          ),
          validatedSuggestion
            == entry.originalModelSuggestion?.fullPrefillV2Suggestion
        else { throw GITimelineError.invalidEntryProvenance }
        if normalized.confirmedPhotoUsable == false {
          guard normalized.confirmedBristolType == nil,
            normalized.form == "unable_to_assess",
            normalized.mixedForm == .unsure,
            normalized.apparentColor == "unable_to_assess",
            normalized.redBlood == .unsure,
            normalized.blackAppearance == .unsure,
            normalized.blackTarry == .unsure
          else { throw GITimelineError.invalidEntryProvenance }
        } else if normalized.stoolPresence != .stool {
          guard normalized.confirmedBristolType == nil,
            normalized.form == "unable_to_assess",
            normalized.mixedForm == .unsure
          else { throw GITimelineError.invalidEntryProvenance }
        } else {
          switch normalized.mixedForm {
          case .no:
            guard let type = normalized.confirmedBristolType,
              BristolFormContract.expectedForm(for: type) == normalized.form
            else { throw GITimelineError.invalidEntryProvenance }
          case .yes:
            guard normalized.confirmedBristolType == nil,
              normalized.form == "mixed"
            else { throw GITimelineError.invalidEntryProvenance }
          case .unsure:
            guard normalized.confirmedBristolType == nil,
              normalized.form == "unable_to_assess"
            else { throw GITimelineError.invalidEntryProvenance }
          case nil:
            throw GITimelineError.invalidEntryProvenance
          }
        }
      }
      changedConfirmedFields = changes.values.contains(true)
      let hadRetakeReceipt = existing.typedFieldProvenance[.retakeReason]
        != nil
      // A complete additive initial receipt has required nonoptional control
      // and tri-state fields. Its retake, Bristol and color values may
      // legitimately be nil, so they must be preserved as nil rather than
      // individually `??`-falling through to a later edited value. Only an
      // older envelope without this complete receipt uses its then-current
      // confirmation as a one-time legacy baseline.
      let hasCompleteInitialFullPrefillReceipt =
        existing.initiallyAcceptedPhotoUsable != nil
        && existing.initiallyAcceptedStoolPresence != nil
        && existing.initiallyAcceptedForm != nil
        && existing.initiallyAcceptedMixedForm != nil
        && existing.initiallyAcceptedRed != nil
        && existing.initiallyAcceptedBlackTarry != nil
        && (!isProviderNeutralV2
          || existing.initiallyAcceptedBlackAppearance != nil)
      let preservesModelAcceptance = entry.originalAIJSON != nil
      let initiallyAcceptedPhotoUsable = !preservesModelAcceptance ? nil
        : hasCompleteInitialFullPrefillReceipt
        ? existing.initiallyAcceptedPhotoUsable
        : (hadRetakeReceipt ? existing.personConfirmedPhotoUsable : nil)
      let initiallyAcceptedRetakeReason = !preservesModelAcceptance ? nil
        : hasCompleteInitialFullPrefillReceipt
        ? existing.initiallyAcceptedRetakeReason
        : (hadRetakeReceipt ? existing.personConfirmedRetakeReason : nil)
      let initiallyAcceptedStoolPresence = !preservesModelAcceptance ? nil
        : hasCompleteInitialFullPrefillReceipt
        ? existing.initiallyAcceptedStoolPresence
        : (usesFullPrefillEnvelope ? existing.personConfirmedStoolPresence : nil)
      let initiallyAcceptedBristolType = !preservesModelAcceptance ? nil
        : hasCompleteInitialFullPrefillReceipt
        ? existing.initiallyAcceptedBristolType
        : (usesFullPrefillEnvelope ? existing.personConfirmedBristolType : nil)
      let initiallyAcceptedForm = !preservesModelAcceptance ? nil
        : hasCompleteInitialFullPrefillReceipt
        ? existing.initiallyAcceptedForm
        : (usesFullPrefillEnvelope ? existing.personConfirmedForm : nil)
      let initiallyAcceptedMixedForm = !preservesModelAcceptance ? nil
        : hasCompleteInitialFullPrefillReceipt
        ? existing.initiallyAcceptedMixedForm
        : (usesFullPrefillEnvelope ? existing.personConfirmedMixedForm : nil)
      let initiallyAcceptedApparentColor = !preservesModelAcceptance ? nil
        : hasCompleteInitialFullPrefillReceipt
        ? existing.initiallyAcceptedApparentColor
        : (usesFullPrefillEnvelope ? existing.personConfirmedApparentColor : nil)
      let initiallyAcceptedRed = !preservesModelAcceptance ? nil
        : hasCompleteInitialFullPrefillReceipt
        ? existing.initiallyAcceptedRed
        : (usesFullPrefillEnvelope ? existing.personConfirmedRed : nil)
      let initiallyAcceptedBlackAppearance = !preservesModelAcceptance ? nil
        : hasCompleteInitialFullPrefillReceipt
        ? existing.initiallyAcceptedBlackAppearance
        : (isProviderNeutralV2
          ? existing.personConfirmedBlackAppearance : nil)
      let initiallyAcceptedBlackTarry = !preservesModelAcceptance ? nil
        : hasCompleteInitialFullPrefillReceipt
        ? existing.initiallyAcceptedBlackTarry
        : (usesFullPrefillEnvelope ? existing.personConfirmedBlackTarry : nil)
      let updated = ConfirmedEntrySnapshotV1(
        confirmedAt: existing.confirmedAt,
        personConfirmedPhotoUsable: normalized.confirmedPhotoUsable,
        initiallyAcceptedPhotoUsable: initiallyAcceptedPhotoUsable,
        initiallyAcceptedRetakeReason: initiallyAcceptedRetakeReason,
        initiallyAcceptedStoolPresence: initiallyAcceptedStoolPresence,
        initiallyAcceptedBristolType: initiallyAcceptedBristolType,
        initiallyAcceptedForm: initiallyAcceptedForm,
        initiallyAcceptedMixedForm: initiallyAcceptedMixedForm,
        initiallyAcceptedApparentColor: initiallyAcceptedApparentColor,
        initiallyAcceptedRed: initiallyAcceptedRed,
        initiallyAcceptedBlackAppearance: initiallyAcceptedBlackAppearance,
        initiallyAcceptedBlackTarry: initiallyAcceptedBlackTarry,
        personConfirmedRetakeReason: normalized.retakeReason,
        personConfirmedStoolPresence: usesFullPrefillEnvelope
          ? normalized.stoolPresence : existing.personConfirmedStoolPresence,
        personConfirmedBristolType: normalized.confirmedBristolType,
        personConfirmedForm: usesFullPrefillEnvelope
          ? normalized.form
          : existing.personConfirmedForm,
        personConfirmedMixedForm: normalized.mixedForm,
        personConfirmedApparentColor: normalized.apparentColor,
        personConfirmedRed: normalized.redBlood,
        personConfirmedBlackAppearance: isProviderNeutralV2
          || existing.personConfirmedBlackAppearance != nil
          ? normalized.blackAppearance : nil,
        personConfirmedBlackTarry: normalized.blackTarry,
        fieldProvenance: fieldProvenance,
        personConfirmedSubject: existing.personConfirmedSubject
      )
      do {
        try updated.validate(
          hasPhoto: entry.imageFilename != nil,
          hasModelSuggestion: entry.originalAIJSON != nil
        )
      } catch {
        throw GITimelineError.invalidEntryProvenance
      }
      guard let canonical = updated.canonicalJSON else {
        throw GITimelineError.invalidEntryProvenance
      }
      reviewedJSON = canonical
    } else if let originalJSON = entry.originalAIJSON {
      // A nil confirmed envelope is compatible only with the supported legacy
      // observation pair. Never reinterpret malformed or future reviewed
      // payloads as if the record had no prior review.
      let original: VisualObservation
      let priorReviewed: VisualObservation
      do {
        let suggestion = try StoredModelVisualSuggestion.parse(originalJSON)
        guard case .legacy(let legacyOriginal) = suggestion,
          let existingReviewedJSON = entry.reviewedJSON
        else { throw GITimelineError.invalidEntryProvenance }
        original = legacyOriginal
        priorReviewed = try supportedLegacyReviewedObservation(existingReviewedJSON)
      } catch {
        throw GITimelineError.invalidEntryProvenance
      }
      let reviewed = try editedObservation(from: original, input: normalized)
      reviewedJSON = try ObservationParser.canonicalJSON(reviewed)
      changedConfirmedFields = reviewed != priorReviewed
    } else {
      guard entry.provenance == EntryProvenance.manual.rawValue,
        entry.reviewedJSON == nil,
        entry.modelID == nil,
        entry.modelProvenanceJSON == nil
      else { throw GITimelineError.invalidEntryProvenance }
      reviewedJSON = nil
      changedConfirmedFields = false
    }

    let provenance = entry.originalAIJSON != nil && changedConfirmedFields
      ? EntryProvenance.ai_edited.rawValue
      : entry.provenance
    return EntryUpdatePlan(
      input: normalized,
      reviewedJSON: reviewedJSON,
      provenance: provenance
    )
  }

  private func candidateImmutableProvenanceIsValid(_ entry: EntryRecord) -> Bool {
    let isLegacyCandidate = entry.analysisPipelineVersion
      == "gi-v1-direct-sanitized-jpeg-constrained-v1"
    let isFullPrefill = entry.analysisPipelineVersion
      == "gi-v1-photo-full-prefill-ab-v1"
      || entry.analysisPipelineVersion
        == AnalysisPipelineVersion.appStoreRawImageV12SubjectGateTuning
    guard isLegacyCandidate || isFullPrefill,
      entry.analysisSource == AnalysisSource.gemmaRawImage.rawValue,
      let originalJSON = entry.originalAIJSON,
      let imageSHA256 = entry.imageSHA256,
      let modelID = entry.modelID,
      let provenanceJSON = entry.modelProvenanceJSON,
      let provenanceData = provenanceJSON.data(using: .utf8),
      let provenance = try? JSONDecoder().decode(
        InferenceProvenanceSnapshot.self,
        from: provenanceData
      ),
      provenance.modelID == modelID,
      provenance.modelID == ModelDescriptor.liteRTGemma4E4B.modelID,
      provenance.descriptorID == ModelDescriptor.liteRTGemma4E4B.id,
      provenance.expectedSHA256 == ModelDescriptor.liteRTGemma4E4B.expectedSHA256,
      provenance.sanitizedImageSHA256 == imageSHA256,
      provenance.parsePath == .direct,
      provenance.liteRTLMRevision == InferenceProvenanceSnapshot.pinnedLiteRTLMRevision
    else { return false }
    #if DEBUG || HACKATHON_EMBEDDED_GEMMA
    if isFullPrefill {
      guard case .fullPrefillV1 = (try? provenance.resolvedSuggestion(
        rawResponse: originalJSON
      )),
        provenance.suggestionSchemaVersion
          == FullPrefillPhotoSuggestionV1.schemaVersion,
        provenance.configuration.usesFullPrefillCandidate
      else { return false }
      if entry.analysisPipelineVersion
        == AnalysisPipelineVersion.appStoreRawImageV12SubjectGateTuning
      {
        guard provenance.fullPrefillNormalization != nil else { return false }
      }
      return true
    }
    guard let suggestion = try? PhotoSuggestionV1Parser
      .parseConstrainedCandidateOutput(originalJSON),
      suggestion.imageUsable,
      suggestion.stoolPresence == .stool,
      provenance.suggestionSchemaVersion == PhotoSuggestionV1.schemaVersion
    else { return false }
    return provenance.configuration.id == "gi-v1-photo-candidate-cpu140-schema-v1"
      && provenance.configuration.promptVersion
        == "gi-photo-v1.3-subject-first-constrained-v1"
      && provenance.configuration.visualTokenBudget == 140
    #else
    return false
    #endif
  }

  private func supportedLegacyReviewedObservation(_ raw: String) throws -> VisualObservation {
    guard let data = raw.data(using: .utf8),
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(object.keys) == Set([
        "image_usable", "quality_issue", "apparent_bristol_type",
        "apparent_color", "form", "red_appearing_material",
        "black_tarry_appearance",
      ])
    else { throw GITimelineError.invalidEntryProvenance }
    return try ObservationParser.parse(raw)
  }

  private func editedObservation(from original: VisualObservation, input: EntryEditInput) throws -> VisualObservation {
    guard input.confirmedPhotoUsable != false else {
      return VisualObservation(
        imageUsable: false,
        qualityIssue: original.qualityIssue == "none" ? "other" : original.qualityIssue,
        apparentBristolType: nil,
        apparentColor: "unable_to_assess",
        form: "unable_to_assess",
        redAppearingMaterial: "unable_to_assess",
        blackTarryAppearance: "unable_to_assess"
      )
    }
    let form: String
    if let type = input.confirmedBristolType,
      let expected = BristolFormContract.expectedForm(for: type)
    {
      form = expected
    } else {
      form = input.mixedForm == .yes ? "mixed" : "unable_to_assess"
    }
    let color = input.apparentColor ?? original.apparentColor
    guard ObservationParser.colors.contains(color) else { throw GITimelineError.invalidClinicalEntry }
    return VisualObservation(
      imageUsable: true,
      qualityIssue: "none",
      apparentBristolType: input.confirmedBristolType,
      apparentColor: color,
      form: form,
      redAppearingMaterial: materialState(from: input.redBlood),
      blackTarryAppearance: materialState(from: input.blackTarry)
    )
  }

  private func materialState(from flag: SymptomFlag?) -> String {
    switch flag {
    case .no: return "not_observed"
    case .yes: return "apparent"
    case .unsure, nil: return "unable_to_assess"
    }
  }

  private func validateClinicalAndProvenance(_ input: EntryInput, hasPhoto: Bool) throws {
    guard ClinicalValidation.validate(
      confirmedBristolType: input.confirmedBristolType,
      painScore: input.painScore,
      mixedForm: input.mixedForm,
      strainingOrIncomplete: input.strainingOrIncomplete,
      leakageOrAccident: input.leakageOrAccident
    ).isEmpty else { throw GITimelineError.invalidClinicalEntry }
    guard (input.confirmedPhotoUsable != nil) == hasPhoto else {
      throw GITimelineError.invalidPhotoAttachment
    }

    switch input.provenance {
    case .manual:
      guard input.analysisSource == .manual,
        input.analysisPipelineVersion == nil,
        input.originalAIJSON == nil,
        input.modelID == nil,
        input.modelProvenanceJSON == nil
      else { throw GITimelineError.invalidEntryProvenance }
      if input.reviewedAt == nil, input.reviewedJSON == nil {
        // Legacy manual records remain importable without being silently
        // reinterpreted as newly confirmed entries.
        break
      }
      guard let reviewedAt = input.reviewedAt,
        let reviewedJSON = input.reviewedJSON,
        case .confirmedV1(let confirmation) = try? StoredReviewedEntry.parse(reviewedJSON),
        confirmation.confirmedAt == reviewedAt
      else { throw GITimelineError.invalidEntryProvenance }
      do { try confirmation.validate(hasPhoto: hasPhoto, hasModelSuggestion: false) }
      catch { throw GITimelineError.invalidEntryProvenance }
      guard confirmationMatchesInput(confirmation, input: input, hasPhoto: hasPhoto) else {
        throw GITimelineError.invalidEntryProvenance
      }
      guard confirmation.typedFieldProvenance.values.allSatisfy({
        $0 == .manualNoSuggestion
      }) else { throw GITimelineError.invalidEntryProvenance }

    case .ai_unedited, .ai_edited:
      guard hasPhoto,
        let source = input.analysisSource,
        source != .manual,
        input.reviewedAt != nil,
        let originalJSON = input.originalAIJSON,
        !originalJSON.isEmpty,
        let reviewedJSON = input.reviewedJSON,
        !reviewedJSON.isEmpty,
        let pipelineVersion = input.analysisPipelineVersion,
        !pipelineVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        let confirmedPhotoUsable = input.confirmedPhotoUsable
      else { throw GITimelineError.invalidEntryProvenance }

      let originalSuggestion: StoredModelVisualSuggestion
      let reviewed: VisualObservation
      let confirmationSnapshot: ConfirmedEntrySnapshotV1?
      do {
        originalSuggestion = try resolvedModelSuggestion(
          rawResponse: originalJSON,
          modelProvenanceJSON: input.modelProvenanceJSON
        )
        switch try StoredReviewedEntry.parse(reviewedJSON) {
        case .legacyObservation(let observation):
          guard case .legacy = originalSuggestion else {
            throw GITimelineError.invalidEntryProvenance
          }
          confirmationSnapshot = nil
          reviewed = observation
        case .confirmedV1(let confirmation):
          try confirmation.validate(hasPhoto: true, hasModelSuggestion: true)
          guard confirmation.confirmedAt == input.reviewedAt,
            confirmationMatchesInput(confirmation, input: input, hasPhoto: true),
            let observation = confirmation.visualObservation(
              original: originalSuggestion.visualObservation,
              hasPhoto: true
            )
          else { throw GITimelineError.invalidEntryProvenance }
          confirmationSnapshot = confirmation
          reviewed = observation
        }
      } catch {
        throw GITimelineError.invalidEntryProvenance
      }
      let isCandidate = pipelineVersion
        == "gi-v1-direct-sanitized-jpeg-constrained-v1"
      let isFullPrefill = pipelineVersion
        == "gi-v1-photo-full-prefill-ab-v1"
        || pipelineVersion
          == AnalysisPipelineVersion.appStoreRawImageV12SubjectGateTuning
      let isProviderNeutralV2 = source == .onDevicePhotoSuggestion
      if isProviderNeutralV2 {
        guard case .fullPrefillV2 = originalSuggestion else {
          throw GITimelineError.invalidEntryProvenance
        }
      } else if case .fullPrefillV2 = originalSuggestion {
        throw GITimelineError.invalidEntryProvenance
      }
      if isCandidate {
        guard let confirmationSnapshot,
          confirmationSnapshot.personConfirmedSubject == true,
          confirmationSnapshot.personConfirmedPhotoUsable == true,
          confirmedPhotoUsable,
          input.redBlood != nil,
          input.blackTarry != nil,
          case .photoV1(let candidateSuggestion) = originalSuggestion,
          candidateSuggestion.imageUsable,
          candidateSuggestion.stoolPresence == .stool,
          (try? PhotoSuggestionV1Parser.validateConstrainedCandidate(
            candidateSuggestion
          )) != nil,
          confirmationSnapshot.typedFieldProvenance[.redMaterial]
            == .independentPersonAnswer,
          confirmationSnapshot.typedFieldProvenance[.blackTarry]
            == .independentPersonAnswer
        else { throw GITimelineError.invalidEntryProvenance }
      }
      if isFullPrefill {
        guard let confirmationSnapshot,
          confirmationSnapshot.personConfirmedStoolPresence != nil,
          confirmationSnapshot.personConfirmedPhotoUsable
            == confirmedPhotoUsable,
          confirmationSnapshot.personConfirmedForm != nil,
          input.redBlood != nil,
          input.blackTarry != nil,
          case .fullPrefillV1 = originalSuggestion
        else { throw GITimelineError.invalidEntryProvenance }
      }
      if isProviderNeutralV2 {
        let allV2Fields = Set(ConfirmationField.allCases)
        guard let confirmationSnapshot,
          confirmationSnapshot.personConfirmedStoolPresence != nil,
          confirmationSnapshot.personConfirmedPhotoUsable
            == confirmedPhotoUsable,
          confirmationSnapshot.personConfirmedForm != nil,
          input.redBlood != nil,
          input.blackAppearance != nil,
          input.blackTarry != nil,
          confirmationSnapshot.personConfirmedBlackAppearance
            == input.blackAppearance,
          confirmationSnapshot.initiallyAcceptedPhotoUsable
            == confirmationSnapshot.personConfirmedPhotoUsable,
          confirmationSnapshot.initiallyAcceptedRetakeReason
            == confirmationSnapshot.personConfirmedRetakeReason,
          confirmationSnapshot.initiallyAcceptedStoolPresence
            == confirmationSnapshot.personConfirmedStoolPresence,
          confirmationSnapshot.initiallyAcceptedBristolType
            == confirmationSnapshot.personConfirmedBristolType,
          confirmationSnapshot.initiallyAcceptedForm
            == confirmationSnapshot.personConfirmedForm,
          confirmationSnapshot.initiallyAcceptedMixedForm
            == confirmationSnapshot.personConfirmedMixedForm,
          confirmationSnapshot.initiallyAcceptedApparentColor
            == confirmationSnapshot.personConfirmedApparentColor,
          confirmationSnapshot.initiallyAcceptedRed
            == confirmationSnapshot.personConfirmedRed,
          confirmationSnapshot.initiallyAcceptedBlackAppearance
            == confirmationSnapshot.personConfirmedBlackAppearance,
          confirmationSnapshot.initiallyAcceptedBlackTarry
            == confirmationSnapshot.personConfirmedBlackTarry,
          Set(confirmationSnapshot.typedFieldProvenance.keys) == allV2Fields
        else { throw GITimelineError.invalidEntryProvenance }
      }
      // When the photo is usable, its reviewed Bristol suggestion must match
      // the saved clinical field. When it is unusable, the photo observation
      // must abstain; the person may still choose a Bristol type manually for
      // the journal entry as a separate piece of reviewed information.
      let reviewedPhotoFieldsMatch: Bool
      if confirmedPhotoUsable {
        if isProviderNeutralV2,
          confirmationSnapshot?.personConfirmedStoolPresence != .stool
        {
          reviewedPhotoFieldsMatch = reviewed.apparentBristolType == nil
            && reviewed.form == "unable_to_assess"
            && reviewed.apparentColor
              == (confirmationSnapshot?.personConfirmedApparentColor
                ?? "unable_to_assess")
            && reviewed.redAppearingMaterial
              == materialState(from: input.redBlood)
            && reviewed.blackTarryAppearance
              == materialState(from: input.blackTarry)
        } else if isFullPrefill,
          confirmationSnapshot?.personConfirmedStoolPresence != .stool
        {
          reviewedPhotoFieldsMatch = reviewed.apparentBristolType == nil
            && reviewed.apparentColor == "unable_to_assess"
            && reviewed.form == "unable_to_assess"
            && reviewed.redAppearingMaterial == "unable_to_assess"
            && reviewed.blackTarryAppearance == "unable_to_assess"
        } else {
          reviewedPhotoFieldsMatch = reviewed.apparentBristolType
            == input.confirmedBristolType
            && (!isFullPrefill && !isProviderNeutralV2
              || (reviewed.form == confirmationSnapshot?.personConfirmedForm
                && reviewed.redAppearingMaterial == materialState(from: input.redBlood)
                && reviewed.blackTarryAppearance == materialState(from: input.blackTarry)))
        }
      } else {
        reviewedPhotoFieldsMatch = reviewed.apparentBristolType == nil
          && reviewed.apparentColor == "unable_to_assess"
          && reviewed.form == "unable_to_assess"
          && reviewed.redAppearingMaterial == "unable_to_assess"
          && reviewed.blackTarryAppearance == "unable_to_assess"
      }
      guard reviewed.imageUsable == confirmedPhotoUsable,
        reviewedPhotoFieldsMatch
      else { throw GITimelineError.invalidEntryProvenance }
      if let confirmationSnapshot {
        var appearancePolicies = AppearancePrefillPolicy.allKnown
        if isProviderNeutralV2,
          let receiptJSON = input.modelProvenanceJSON,
          let receipt = try? PhotoSuggestionEngineReceipt.decode(receiptJSON),
          receipt.decomposedFieldProvenance?.fusionVersion
            == Qwen3DecomposedFusion.fusionVersion
        {
          // V3 was introduced together with the complete tri-state display
          // contract, so its confirmations have one unambiguous policy.
          appearancePolicies = [.completeTriState]
        }
        let expectedFieldProvenanceCandidates = appearancePolicies.map {
          expectedInitialFieldProvenance(
            suggestion: originalSuggestion,
            confirmation: confirmationSnapshot,
            isCandidate: isCandidate,
            isFullPrefill: isFullPrefill,
            appearancePolicy: $0
          )
        }
        guard expectedFieldProvenanceCandidates.contains(
          confirmationSnapshot.typedFieldProvenance
        ),
          !confirmationSnapshot.typedFieldProvenance.values.contains(.editedAfterConfirmation)
        else { throw GITimelineError.invalidEntryProvenance }
        let anyEdited = confirmationSnapshot.typedFieldProvenance.values.contains(
          .editedBeforeConfirmation
        )
        guard input.provenance == (anyEdited ? .ai_edited : .ai_unedited) else {
          throw GITimelineError.invalidEntryProvenance
        }
      }

      let hasModelID = input.modelID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      let hasModelProvenance = input.modelProvenanceJSON?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      guard hasModelID == hasModelProvenance else { throw GITimelineError.invalidEntryProvenance }
      if source == .onDevicePhotoSuggestion {
        guard case .fullPrefillV2(let storedSuggestion) = originalSuggestion,
          let validatedSuggestion = try? validatedProviderNeutralV2Suggestion(
            rawResponse: originalJSON,
            modelProvenanceJSON: input.modelProvenanceJSON,
            modelID: input.modelID,
            pipelineVersion: pipelineVersion,
            imageSHA256: input.imageSHA256
          ),
          validatedSuggestion == storedSuggestion
        else { throw GITimelineError.invalidEntryProvenance }
      } else if hasModelID {
        guard let modelID = input.modelID,
          let provenanceJSON = input.modelProvenanceJSON,
          let data = provenanceJSON.data(using: .utf8),
          let snapshot = try? JSONDecoder().decode(InferenceProvenanceSnapshot.self, from: data),
          snapshot.modelID == modelID,
          snapshot.configuration.analysisPipelineVersion == pipelineVersion,
          (source == .gemmaDerivedMap) == snapshot.configuration.usesLocalPixelBridge
        else { throw GITimelineError.invalidEntryProvenance }
        let suggestionUsesPhotoV1: Bool
        switch originalSuggestion {
        case .photoV1, .fullPrefillV1: suggestionUsesPhotoV1 = true
        case .fullPrefillV2:
          throw GITimelineError.invalidEntryProvenance
        case .legacy: suggestionUsesPhotoV1 = false
        }
        guard suggestionUsesPhotoV1 == snapshot.configuration.usesRawPhotoV1Schema else {
          throw GITimelineError.invalidEntryProvenance
        }
        if suggestionUsesPhotoV1 {
          let configurationMatches: Bool
          #if DEBUG || HACKATHON_EMBEDDED_GEMMA
          if isFullPrefill {
            configurationMatches = snapshot.configuration.usesFullPrefillCandidate
          } else if isCandidate {
            configurationMatches = snapshot.configuration.id
              == "gi-v1-photo-candidate-cpu140-schema-v1"
          } else {
            configurationMatches = snapshot.configuration == .appStoreRawImageV1
          }
          #else
          guard !isCandidate, !isFullPrefill else {
            throw GITimelineError.invalidEntryProvenance
          }
          configurationMatches = snapshot.configuration == .appStoreRawImageV1
          #endif
          guard source == .gemmaRawImage,
            configurationMatches,
            confirmationSnapshot != nil,
            snapshot.descriptorID == ModelDescriptor.liteRTGemma4E4B.id,
            snapshot.family == ModelDescriptor.liteRTGemma4E4B.family,
            snapshot.modelID == ModelDescriptor.liteRTGemma4E4B.modelID,
            snapshot.sourceRevision == ModelDescriptor.liteRTGemma4E4B.sourceRevision,
            snapshot.artifactFilename == ModelDescriptor.liteRTGemma4E4B.artifactFilename,
            snapshot.expectedSHA256 == ModelDescriptor.liteRTGemma4E4B.expectedSHA256,
            snapshot.sanitizedImageSHA256 == input.imageSHA256,
            let suggestedAt = snapshot.suggestedAt,
            let generationStartedAt = snapshot.generationStartedAt,
            let generationEndedAt = snapshot.generationEndedAt,
            generationStartedAt <= generationEndedAt,
            suggestedAt == generationEndedAt,
            snapshot.parsePath != nil,
            ((!isCandidate && !isFullPrefill) || snapshot.parsePath == .direct),
            snapshot.suggestionSchemaVersion == (isFullPrefill
              ? FullPrefillPhotoSuggestionV1.schemaVersion
              : PhotoSuggestionV1.schemaVersion),
            snapshot.liteRTLMRevision == InferenceProvenanceSnapshot.pinnedLiteRTLMRevision
          else { throw GITimelineError.invalidEntryProvenance }
          if pipelineVersion
            == AnalysisPipelineVersion.appStoreRawImageV12SubjectGateTuning
          {
            guard snapshot.fullPrefillNormalization != nil else {
              throw GITimelineError.invalidEntryProvenance
            }
          }
        }
      } else {
        if case .fullPrefillV2 = originalSuggestion {
          throw GITimelineError.invalidEntryProvenance
        }
        #if DEBUG
        guard input.demoKind?.isEmpty == false else {
          throw GITimelineError.invalidEntryProvenance
        }
        #else
        throw GITimelineError.invalidEntryProvenance
        #endif
      }
    }
  }

  private func resolvedModelSuggestion(
    rawResponse: String,
    modelProvenanceJSON: String?
  ) throws -> StoredModelVisualSuggestion {
    if let modelProvenanceJSON,
      let data = modelProvenanceJSON.data(using: .utf8),
      let provenance = try? JSONDecoder().decode(
        InferenceProvenanceSnapshot.self,
        from: data
      )
    {
      return try provenance.resolvedSuggestion(rawResponse: rawResponse)
    }
    return try StoredModelVisualSuggestion.parse(rawResponse)
  }

  private func validatedProviderNeutralV2Suggestion(
    rawResponse: String,
    modelProvenanceJSON: String?,
    modelID: String?,
    pipelineVersion: String?,
    imageSHA256: String?
  ) throws -> PhotoSuggestionPayloadV2 {
    guard let modelProvenanceJSON,
      let modelID,
      let pipelineVersion,
      let imageSHA256,
      let rawData = rawResponse.data(using: .utf8),
      let receipt = try? PhotoSuggestionEngineReceipt.decode(
        modelProvenanceJSON
      ),
      receipt.canonicalJSON == modelProvenanceJSON,
      receipt.identity.modelID == modelID,
      receipt.identity.analysisPipelineVersion == pipelineVersion,
      receipt.analyzedImageSHA256 == imageSHA256
    else { throw GITimelineError.invalidEntryProvenance }
    do {
      return try receipt.validate(rawOutputUTF8: rawData)
    } catch {
      throw GITimelineError.invalidEntryProvenance
    }
  }

  private func confirmationMatchesInput(
    _ confirmation: ConfirmedEntrySnapshotV1,
    input: EntryInput,
    hasPhoto: Bool
  ) -> Bool {
    confirmation.personConfirmedPhotoUsable == (hasPhoto ? input.confirmedPhotoUsable : nil)
      && confirmation.personConfirmedBristolType == input.confirmedBristolType
      && confirmation.personConfirmedMixedForm == input.mixedForm
      && confirmation.personConfirmedRed == input.redBlood
      && confirmation.personConfirmedBlackAppearance == input.blackAppearance
      && confirmation.personConfirmedBlackTarry == input.blackTarry
  }

  private enum AppearancePrefillPolicy: CaseIterable {
    case completeTriState
    case legacyV9

    static var allKnown: [Self] { [.completeTriState, .legacyV9] }

    func flag(for answer: PhotoSuggestionAnswer) -> SymptomFlag {
      switch self {
      case .completeTriState: answer.appearancePrefillFlag
      case .legacyV9: answer.legacyV9AppearancePrefillFlag
      }
    }
  }

  private func expectedInitialFieldProvenance(
    suggestion: StoredModelVisualSuggestion,
    confirmation: ConfirmedEntrySnapshotV1,
    isCandidate: Bool = false,
    isFullPrefill: Bool = false,
    appearancePolicy: AppearancePrefillPolicy = .completeTriState
  ) -> [ConfirmationField: FieldConfirmationProvenance] {
    if let full = suggestion.fullPrefillV2Suggestion {
      let comparisons: [ConfirmationField: Bool] = [
        .photoUsable: confirmation.personConfirmedPhotoUsable == full.imageUsable,
        .retakeReason:
          confirmation.personConfirmedRetakeReason == full.retakeReason,
        .stoolPresence:
          confirmation.personConfirmedStoolPresence == full.stoolPresence,
        .bristolType:
          confirmation.personConfirmedBristolType == full.bristolType,
        .form: confirmation.personConfirmedForm == full.form,
        .mixedForm: confirmation.personConfirmedMixedForm
          == suggestion.mixedFormSuggestion,
        .apparentColor:
          (confirmation.personConfirmedApparentColor ?? "unable_to_assess")
            == (full.apparentColor ?? "unable_to_assess"),
        .redMaterial: confirmation.personConfirmedRed
          == appearancePolicy.flag(for: full.redAppearingMaterial),
        .blackAppearance: confirmation.personConfirmedBlackAppearance
          == appearancePolicy.flag(for: full.blackAppearance),
        .blackTarry: confirmation.personConfirmedBlackTarry
          == appearancePolicy.flag(for: full.blackTarryAppearance),
      ]
      return Dictionary(
        uniqueKeysWithValues: ConfirmationField.allCases.map { field in
          (field, comparisons[field] == true
            ? FieldConfirmationProvenance.acceptedUnchanged
            : FieldConfirmationProvenance.editedBeforeConfirmation)
        }
      )
    }
    if isFullPrefill, let full = suggestion.fullPrefillSuggestion {
      let comparisons: [ConfirmationField: Bool] = [
        .photoUsable: confirmation.personConfirmedPhotoUsable == full.imageUsable,
        .retakeReason:
          confirmation.personConfirmedRetakeReason == full.retakeReason,
        .stoolPresence: confirmation.personConfirmedStoolPresence == full.stoolPresence,
        .bristolType: confirmation.personConfirmedBristolType == full.bristolType,
        .form: confirmation.personConfirmedForm == full.form,
        .mixedForm: confirmation.personConfirmedMixedForm
          == suggestion.mixedFormSuggestion,
        .apparentColor:
          (confirmation.personConfirmedApparentColor ?? "unable_to_assess")
            == (full.apparentColor ?? "unable_to_assess"),
        .redMaterial: confirmation.personConfirmedRed
          == appearancePolicy.flag(for: full.redAppearingMaterial),
        .blackTarry: confirmation.personConfirmedBlackTarry
          == appearancePolicy.flag(for: full.blackTarryAppearance),
      ]
      let v1Fields = ConfirmationField.allCases.filter {
        $0 != .blackAppearance
      }
      return Dictionary(
        uniqueKeysWithValues: v1Fields.map { field in
          (field, comparisons[field] == true
            ? FieldConfirmationProvenance.acceptedUnchanged
            : FieldConfirmationProvenance.editedBeforeConfirmation)
        }
      )
    }
    let original = suggestion.visualObservation
    let comparisons: [ConfirmationField: Bool] = [
      .photoUsable: confirmation.personConfirmedPhotoUsable == original.imageUsable,
      .retakeReason: true,
      .stoolPresence: true,
      .bristolType: confirmation.personConfirmedBristolType == original.apparentBristolType,
      .form: true,
      .mixedForm: confirmation.personConfirmedMixedForm == suggestion.mixedFormSuggestion,
      .apparentColor: (confirmation.personConfirmedApparentColor ?? "unable_to_assess")
        == original.apparentColor,
      .redMaterial: confirmation.personConfirmedRed == symptomSuggestion(
        fromMaterialState: original.redAppearingMaterial
      ),
      .blackTarry: confirmation.personConfirmedBlackTarry == symptomSuggestion(
        fromMaterialState: original.blackTarryAppearance
      ),
    ]
    let persistedFields = confirmation.typedFieldProvenance.keys
    var result: [ConfirmationField: FieldConfirmationProvenance] = Dictionary(
      uniqueKeysWithValues: persistedFields.map { field in
        (
          field,
          comparisons[field] == true
            ? FieldConfirmationProvenance.acceptedUnchanged
            : FieldConfirmationProvenance.editedBeforeConfirmation
        )
      }
    )
    if isCandidate {
      result[.redMaterial] = .independentPersonAnswer
      result[.blackTarry] = .independentPersonAnswer
    }
    return result
  }

  private func symptomSuggestion(fromMaterialState state: String) -> SymptomFlag {
    switch state {
    case "not_observed": return .no
    case "apparent": return .yes
    case "possible", "unable_to_assess": return .unsure
    default: return .unsure
    }
  }

  private static func confirmedForm(
    bristolType: Int?,
    mixedForm: ClinicalTriState?
  ) -> String? {
    if let bristolType {
      return BristolFormContract.expectedForm(for: bristolType)
    }
    switch mixedForm {
    case .yes: return "mixed"
    case .unsure: return "unable_to_assess"
    case .no, nil: return nil
    }
  }

  private func imageIsUnavailable(
    for entry: EntryRecord,
    imageStore: ImageStore,
    ambiguousFilenames: Set<String>
  ) throws -> Bool {
    // Nil/nil is an intentional no-photo record.  Any partial tuple is kept
    // intact but unavailable, never silently converted or deleted.
    if entry.imageFilename == nil, entry.imageSHA256 == nil { return false }
    guard let filename = entry.imageFilename else { return true }
    guard let expectedSHA256 = entry.imageSHA256,
      ImageStore.isSafeImageFilename(filename),
      ImageStore.isValidSHA256(expectedSHA256),
      !ambiguousFilenames.contains(filename)
    else { return true }
    return try !imageStore.storedImageIsVerified(
      filename: filename,
      expectedSHA256: expectedSHA256
    )
  }
}

struct JournalDataEraseSummary: Equatable {
  let recordsDeleted: Int
  let filesDeleted: Int
  let fileCleanupFailures: Int

  var completedWithoutWarnings: Bool { fileCleanupFailures == 0 }
}

enum JournalDataEraseFailureStage: String, Equatable {
  case database
  case postCommit
  case fileCleanup
  case markerClear
}

/// Every failure emitted after the durable marker commit has this type. The
/// marker remains authoritative, so callers must replace all writable journal
/// UI with an erase-only recovery screen until retry succeeds.
struct JournalDataErasePendingFailure: Error, LocalizedError, Equatable {
  let stage: JournalDataEraseFailureStage
  let recordsDeleted: Int
  let filesDeleted: Int
  let cleanupFailureCount: Int
  let underlyingDescription: String

  var errorDescription: String? {
    switch stage {
    case .database:
      return "Your confirmed erase is still pending. Journal records and files may still be present, and GI Journal will not accept new journal data until retry finishes."
    case .postCommit:
      return "Journal records were erased, but local file cleanup has not finished. GI Journal will not accept new journal data until retry finishes."
    case .fileCleanup:
      return "Journal records were erased and some local files were removed, but cleanup is still pending. GI Journal will not accept new journal data until retry finishes."
    case .markerClear:
      return "Journal data cleanup finished, but GI Journal could not confirm completion locally. New journal data remains blocked until retry clears that protected erase state."
    }
  }
}

/// A protected, non-sensitive write-ahead marker for the explicit erase-all
/// operation. It records only that the person confirmed erase, never journal
/// contents. Keeping it outside the erased journal directories lets launch
/// safely finish a partially completed erase after interruption.
struct JournalDataErasePendingMarker: Codable {
  static let currentVersion = 1

  let version: Int
  let requestedAt: Date
}

@MainActor final class JournalDataErasePendingMarkerStore {
  typealias URLProvider = () throws -> URL

  private let urlProvider: URLProvider
  private let fileManager: FileManager
  private let clearFailureInjector: (() throws -> Void)?

  init(
    urlProvider: @escaping URLProvider,
    fileManager: FileManager,
    clearFailureInjector: (() throws -> Void)? = nil
  ) {
    self.urlProvider = urlProvider
    self.fileManager = fileManager
    self.clearFailureInjector = clearFailureInjector
  }

  func hasPendingErase() throws -> Bool {
    let url = try urlProvider()
    guard fileManager.fileExists(atPath: url.path) else { return false }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let marker = try decoder.decode(JournalDataErasePendingMarker.self, from: Data(contentsOf: url))
    guard marker.version == JournalDataErasePendingMarker.currentVersion else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return true
  }

  func markPending() throws {
    let url = try urlProvider()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(
      JournalDataErasePendingMarker(
        version: JournalDataErasePendingMarker.currentVersion,
        requestedAt: Date()
      )
    )
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    // The atomic complete-protection write is the commit point. Do not throw
    // afterward: the protected parent already inherits backup exclusion, and
    // an extra file-level exclusion is a best-effort hardening detail only.
    try? AppFolders.excludeFromBackup(url)
  }

  func clear() throws {
    let url = try urlProvider()
    guard fileManager.fileExists(atPath: url.path) else { return }
    try clearFailureInjector?()
    try fileManager.removeItem(at: url)
  }
}

/// Deletes every user-authored journal record in one SwiftData save before
/// removing the local photo, draft, and temporary-export files. Model assets
/// are intentionally outside the supplied directory list and are never erased.
@MainActor final class JournalDataEraser {
  typealias DirectoryProvider = () throws -> [URL]
  typealias FailureInjector = () throws -> Void
  typealias PendingMarkerURLProvider = () throws -> URL
  typealias CleanupFailureInjector = (URL) throws -> Void

  private let context: ModelContext
  private let directoryProvider: DirectoryProvider
  private let failureInjector: FailureInjector?
  private let afterDatabaseCommitInjector: FailureInjector?
  private let cleanupFailureInjector: CleanupFailureInjector?
  private let pendingMarkerStore: JournalDataErasePendingMarkerStore
  private let fileManager: FileManager

  init(
    context: ModelContext,
    journalDirectories: @escaping DirectoryProvider = { try AppFolders.journalDataDirectories() },
    fileManager: FileManager = .default,
    failureInjector: FailureInjector? = nil,
    afterDatabaseCommitInjector: FailureInjector? = nil,
    cleanupFailureInjector: CleanupFailureInjector? = nil,
    markerClearFailureInjector: FailureInjector? = nil,
    pendingMarkerURL: @escaping PendingMarkerURLProvider = { try AppFolders.erasePendingMarkerURL() }
  ) {
    self.context = context
    self.directoryProvider = journalDirectories
    self.fileManager = fileManager
    self.failureInjector = failureInjector
    self.afterDatabaseCommitInjector = afterDatabaseCommitInjector
    self.cleanupFailureInjector = cleanupFailureInjector
    self.pendingMarkerStore = JournalDataErasePendingMarkerStore(
      urlProvider: pendingMarkerURL,
      fileManager: fileManager,
      clearFailureInjector: markerClearFailureInjector
    )
    context.autosaveEnabled = false
  }

  func eraseAllJournalData() throws -> JournalDataEraseSummary {
    try eraseAllJournalDataWithPendingMarker()
  }

  /// Returns nil when no confirmed erase was interrupted. When a marker is
  /// present, it completes the exact same erase before normal journal UI is
  /// allowed to appear.
  func resumePendingEraseIfNeeded() throws -> JournalDataEraseSummary? {
    guard try pendingMarkerStore.hasPendingErase() else { return nil }
    return try eraseAllJournalDataWithPendingMarker()
  }

  /// Used only after the person has already confirmed erase and the app is in
  /// its erase-only retry UI. If an earlier unknown failure happened before a
  /// marker could be written, marker absence is not success: restart the full
  /// idempotent erase instead of fabricating an empty completion summary.
  func resumeOrRestartConfirmedErase() throws -> JournalDataEraseSummary {
    if let summary = try resumePendingEraseIfNeeded() { return summary }
    return try eraseAllJournalDataWithPendingMarker()
  }

  func hasPendingErase() throws -> Bool {
    try pendingMarkerStore.hasPendingErase()
  }

  private func eraseAllJournalDataWithPendingMarker() throws -> JournalDataEraseSummary {
    // Resolve the exact, app-scoped cleanup targets before changing the store.
    // If the container cannot provide them, no records are touched.
    let directories = try directoryProvider().map(\.standardizedFileURL)
    let entries = try context.fetch(FetchDescriptor<EntryRecord>())
    let completions = try context.fetch(FetchDescriptor<DailyCompletionRecord>())
    let treatments = try context.fetch(FetchDescriptor<TreatmentEventRecord>())
    let recordCount = entries.count + completions.count + treatments.count

    // The marker is the durable erase intent and must exist before any model
    // mutation. If the process stops at any later point, the next launch
    // completes cleanup instead of resurrecting a draft or export.
    try pendingMarkerStore.markPending()

    do {
      for record in entries { context.delete(record) }
      for record in completions { context.delete(record) }
      for record in treatments { context.delete(record) }
      try failureInjector?()
      try context.save()
    } catch {
      context.rollback()
      throw JournalDataErasePendingFailure(
        stage: .database,
        recordsDeleted: 0,
        filesDeleted: 0,
        cleanupFailureCount: 0,
        underlyingDescription: error.localizedDescription
      )
    }
    // Deliberately outside the transaction catch. This helper is nonthrowing;
    // a future diagnostic added here must never reclassify a durable commit as
    // a precommit database failure.
    AppFolders.enforceStoreProtection(requireAllStoreFiles: true)

    // Test-only interruption point: this intentionally runs outside the
    // transaction catch so a committed database is never rolled back in
    // memory after a post-commit failure.
    do {
      try afterDatabaseCommitInjector?()
    } catch {
      throw JournalDataErasePendingFailure(
        stage: .postCommit,
        recordsDeleted: recordCount,
        filesDeleted: 0,
        cleanupFailureCount: 0,
        underlyingDescription: error.localizedDescription
      )
    }

    var filesDeleted = 0
    var cleanupFailures = 0
    var firstCleanupFailure: Error?
    for directory in directories {
      do {
        try cleanupFailureInjector?(directory)
        filesDeleted += try eraseContents(of: directory)
      } catch {
        // The database transaction has committed. Keep trying the other
        // app-scoped directories and report a retryable cleanup warning.
        cleanupFailures += 1
        if firstCleanupFailure == nil { firstCleanupFailure = error }
      }
    }
    if cleanupFailures > 0 {
      throw JournalDataErasePendingFailure(
        stage: .fileCleanup,
        recordsDeleted: recordCount,
        filesDeleted: filesDeleted,
        cleanupFailureCount: cleanupFailures,
        underlyingDescription: firstCleanupFailure?.localizedDescription ?? "Local file cleanup failed."
      )
    }
    do {
      try pendingMarkerStore.clear()
    } catch {
      throw JournalDataErasePendingFailure(
        stage: .markerClear,
        recordsDeleted: recordCount,
        filesDeleted: filesDeleted,
        cleanupFailureCount: 1,
        underlyingDescription: error.localizedDescription
      )
    }
    return JournalDataEraseSummary(
      recordsDeleted: recordCount,
      filesDeleted: filesDeleted,
      fileCleanupFailures: 0
    )
  }

  private func eraseContents(of directory: URL) throws -> Int {
    guard directory.isFileURL,
      directory.path != "/",
      directory.pathComponents.count > 2
    else { throw CocoaError(.fileNoSuchFile) }
    guard fileManager.fileExists(atPath: directory.path) else { return 0 }
    let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw CocoaError(.fileReadInvalidFileName)
    }
    let children = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isSymbolicLinkKey],
      options: []
    )
    var deleted = 0
    for child in children {
      let normalized = child.standardizedFileURL
      guard normalized.deletingLastPathComponent() == directory else {
        throw CocoaError(.fileReadInvalidFileName)
      }
      try fileManager.removeItem(at: normalized)
      deleted += 1
    }
    return deleted
  }
}

/// Fault-injecting test store that exercises the real EntryStore transaction
/// and its real ModelContext.rollback() paths using an in-memory container.
@MainActor final class FailingEntryStore: EntryStoring {
  private final class FailureState {
    var failNextSave = false
    var failNextDelete = false
    var failNextMark = false
    var rollbackCount = 0
  }

  private let state: FailureState
  private let container: ModelContainer
  private let context: ModelContext
  private let realStore: EntryStore
  private(set) var lastCopiedURL: URL?

  var failNextSave: Bool {
    get { state.failNextSave }
    set { state.failNextSave = newValue }
  }
  var failNextDelete: Bool {
    get { state.failNextDelete }
    set { state.failNextDelete = newValue }
  }
  var failNextMark: Bool {
    get { state.failNextMark }
    set { state.failNextMark = newValue }
  }
  var rollbackCount: Int { state.rollbackCount }
  var records: [EntryRecord] { (try? context.fetch(FetchDescriptor<EntryRecord>())) ?? [] }

  init() throws {
    let state = FailureState()
    let schema = Schema([EntryRecord.self, DailyCompletionRecord.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    let context = ModelContext(container)
    self.state = state
    self.container = container
    self.context = context
    self.realStore = EntryStore(context: context) { point in
      switch point {
      case .afterInsertBeforeSave where state.failNextSave:
        state.failNextSave = false
        state.rollbackCount += 1
        throw CocoaError(.fileWriteUnknown)
      case .afterUpdateBeforeSave where state.failNextSave:
        state.failNextSave = false
        state.rollbackCount += 1
        throw CocoaError(.fileWriteUnknown)
      case .afterDeleteBeforeSave where state.failNextDelete:
        state.failNextDelete = false
        state.rollbackCount += 1
        throw CocoaError(.fileWriteUnknown)
      case .afterMarkBeforeSave where state.failNextMark:
        state.failNextMark = false
        state.rollbackCount += 1
        throw CocoaError(.fileWriteUnknown)
      default:
        break
      }
    }
  }

  func save(_ input: EntryInput, imageStore: ImageStore) throws {
    lastCopiedURL = try imageStore.promotedURL(for: input.id)
    try realStore.save(input, imageStore: imageStore)
  }

  func update(
    _ entry: EntryRecord,
    with input: EntryEditInput,
    baselineFingerprint: String,
    at date: Date
  ) throws {
    try realStore.update(
      entry,
      with: input,
      baselineFingerprint: baselineFingerprint,
      at: date
    )
  }

  func expectedUpdateFingerprint(
    for entry: EntryRecord,
    input: EntryEditInput,
    baselineFingerprint: String,
    at date: Date
  ) throws -> String {
    try realStore.expectedUpdateFingerprint(
      for: entry,
      input: input,
      baselineFingerprint: baselineFingerprint,
      at: date
    )
  }

  @discardableResult
  func delete(_ entry: EntryRecord, imageStore: ImageStore) throws -> EntryDeletionOutcome {
    try realStore.delete(entry, imageStore: imageStore)
  }

  func reconcile(imageStore: ImageStore) async throws {
    try await realStore.reconcile(imageStore: imageStore)
  }

  func setDiscussionMark(_ marked: Bool, for entry: EntryRecord, at date: Date) throws {
    try realStore.setDiscussionMark(marked, for: entry, at: date)
  }

  func pendingTransactionState(
    id: UUID,
    fingerprint: String,
    imageStore: ImageStore
  ) throws -> EntryPendingTransactionState {
    try realStore.pendingTransactionState(id: id, fingerprint: fingerprint, imageStore: imageStore)
  }
}
