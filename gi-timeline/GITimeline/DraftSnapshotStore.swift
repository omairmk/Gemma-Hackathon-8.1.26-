import CryptoKit
import Darwin
import Foundation
import UIKit
import GITimelineCore

/// The only durable representation of an unfinished entry. It intentionally
/// contains a relative reference to the already-sanitized draft JPEG, never
/// image bytes, absolute paths, or a model prompt/response payload.
struct DraftSnapshot: Codable, Equatable {
  /// Version 1 did not carry a save transaction identity. Version 2 adds the
  /// optional identity while continuing to decode version-1 snapshots, which
  /// are rewritten lazily the next time the person changes the draft.
  static let legacyVersion = 1
  static let transactionVersion = 2
  static let timedSuggestionVersion = 3
  static let validatedSuggestionVersion = 4
  static let subjectFirstVersion = 5
  static let fullPrefillVersion = 6
  static let normalizationReceiptVersion = 7
  /// V8 introduced the provider-neutral on-device engine and its receipt.
  /// Its complete tri-state appearance values remain valid as written.
  static let providerNeutralVersion = 8
  /// V9 enforced the superseded rule that a model `no` displayed as Not sure.
  static let safetyPrefillVersion = 9
  /// V10 adopts the complete Yes / No / Not sure appearance-prefill contract.
  static let currentVersion = 10

  struct DraftFile: Codable, Equatable {
    let id: UUID
    let filename: String
    let sha256: String
  }

  struct Review: Codable, Equatable {
    let original: VisualObservation
    let reviewed: VisualObservation
    let originalMixedForm: ClinicalTriState
    let reviewedMixedForm: ClinicalTriState?
    let states: [String: String]
  }

  let version: Int
  /// Written before a save reaches SwiftData. If the app is terminated after
  /// the record commits but before draft cleanup, launch can recognize the
  /// already-committed entry instead of offering a second save.
  let pendingEntryID: UUID?
  /// SHA-256 of the complete immutable EntryInput-backed payload, including
  /// the canonical photo filename/hash pair. It is always paired with the
  /// pending UUID in v2 and compared against the fetched EntryRecord.
  let pendingEntryFingerprint: String?
  /// Whole-entry confirmation time is part of every new saved payload and
  /// must not drift across a retry. Legacy manual snapshots may keep this nil.
  let pendingReviewedAt: Date?
  /// A photo draft is optional because a person may intentionally begin a
  /// manual entry with "Continue without a photo." No-photo snapshots carry
  /// the same user-entered clinical fields but never invent a photo reference.
  let draft: DraftFile?
  let capturedAt: Date
  var confirmedStoolPresence: StoolPresence? = nil
  let confirmedBristolType: Int?
  var confirmedForm: String? = nil
  /// Additive manual-review value. Historical snapshots decode it as nil;
  /// model-backed snapshots continue to keep their reviewed color in Review.
  var confirmedApparentColor: String? = nil
  let confirmedPhotoUsable: Bool?
  var confirmedRetakeReason: PhotoRetakeReason? = nil
  /// Optional and backward-readable. Nil is the only valid initial state for
  /// the one bounded candidate; legacy snapshots simply decode it as absent.
  let subjectConfirmation: PhotoSubjectConfirmation?
  let mixedForm: ClinicalTriState?
  let painScore: Int?
  let urgency: UrgencyLevel?
  let strainingOrIncomplete: ClinicalTriState?
  let leakageOrAccident: ClinicalTriState?
  /// Not `let`: a decoded V9 automatic prefill may be upgraded by
  /// `migratedForAppearancePrefill()` before it is shown again.
  var redBlood: SymptomFlag?
  var blackAppearance: SymptomFlag? = nil
  /// Not `let`: see `redBlood` above.
  var blackTarry: SymptomFlag?
  let dizziness: SymptomFlag?
  let severePain: SymptomFlag?
  let note: String
  let reviewedObservation: VisualObservation?
  let review: Review?
  let originalValidatedJSON: String?
  /// Additive receipt for V7 full-prefill drafts. The raw response remains in
  /// originalValidatedJSON; the normalized canonical suggestion lives here.
  var fullPrefillNormalization: FullPrefillNormalizationReceiptV1? = nil
  /// Additive V8 provider-neutral receipt. Historical Gemma drafts continue
  /// to use their existing provenance snapshot/normalization fields.
  var photoSuggestionEngineReceiptJSON: String? = nil
  /// Additive deterministic preflight presentation. Nil remains the complete
  /// representation for historical snapshots and for a recommendation the
  /// person already dismissed. No prompt or model output is stored here.
  var photoQualityRecommendation: PhotoQualityRecommendation? = nil
  /// Set only after the person chooses to keep a deterministic hard-quality
  /// photo and continue in the complete manual photo form. The original
  /// recommendation is cleared at that boundary, so this additive marker
  /// preserves the chosen presentation across an interrupted draft/relaunch.
  var retainedLowQualityManualReview: Bool? = nil
  let modelSuggestedImageSHA256: String?
  let modelSuggestedAt: Date?
  let generationStartedAt: Date?
  let generationEndedAt: Date?
  let inferenceParsePath: String?
  let analysisSource: AnalysisSource
  let analysisPipelineVersion: String?
  let didChooseBristolType: Bool
  let didChooseMixedForm: Bool
  let didReviewPhotoUsability: Bool

  func validateStructure() throws {
    guard version == Self.legacyVersion
      || version == Self.transactionVersion
      || version == Self.timedSuggestionVersion
      || version == Self.validatedSuggestionVersion
      || version == Self.subjectFirstVersion
      || version == Self.fullPrefillVersion
      || version == Self.normalizationReceiptVersion
      || version == Self.providerNeutralVersion
      || version == Self.safetyPrefillVersion
      || version == Self.currentVersion
    else {
      throw DraftSnapshotError.unsupportedVersion
    }
    if version == Self.legacyVersion {
      guard pendingEntryID == nil,
        pendingEntryFingerprint == nil,
        pendingReviewedAt == nil
      else { throw DraftSnapshotError.invalidContents }
    } else {
      switch (pendingEntryID, pendingEntryFingerprint) {
      case (nil, nil):
        guard pendingReviewedAt == nil else { throw DraftSnapshotError.invalidContents }
      case (.some(_), .some(let fingerprint)):
        guard fingerprint.count == 64,
          fingerprint == fingerprint.lowercased(),
          fingerprint.allSatisfy(\.isHexDigit)
        else { throw DraftSnapshotError.invalidContents }
        if version == Self.transactionVersion {
          guard (analysisSource == .manual) == (pendingReviewedAt == nil) else {
            throw DraftSnapshotError.invalidContents
          }
        } else {
          guard pendingReviewedAt != nil else { throw DraftSnapshotError.invalidContents }
        }
      default:
        throw DraftSnapshotError.invalidContents
      }
    }
    if let draft {
      guard draft.filename == (draft.filename as NSString).lastPathComponent,
        draft.filename.hasSuffix(".jpg"),
        UUID(uuidString: String(draft.filename.dropLast(4))) == draft.id,
        draft.sha256.count == 64,
        draft.sha256.allSatisfy({ $0.isHexDigit })
      else { throw DraftSnapshotError.invalidReference }
    } else {
      // A no-photo manual entry may retain values the person observed
      // directly, but it cannot claim photo usability or model-derived state.
      guard confirmedPhotoUsable == nil,
        confirmedRetakeReason == nil,
        reviewedObservation == nil,
        review == nil,
        originalValidatedJSON == nil,
        fullPrefillNormalization == nil,
        photoSuggestionEngineReceiptJSON == nil,
        photoQualityRecommendation == nil,
        modelSuggestedImageSHA256 == nil,
        modelSuggestedAt == nil,
        generationStartedAt == nil,
        generationEndedAt == nil,
        inferenceParsePath == nil,
        analysisSource == .manual,
        analysisPipelineVersion == nil,
        didReviewPhotoUsability == false
      else { throw DraftSnapshotError.invalidContents }
    }
    if let recommendation = photoQualityRecommendation {
      let expectedReason: PhotoRetakeReason = switch recommendation.issue {
      case .severeBlur: .blurred
      case .tooDark: .tooDark
      case .overexposedGlare: .glare
      case .nearBlank: .other
      case .veryLowContrast: .obstructed
      }
      guard draft != nil, recommendation.retakeReason == expectedReason else {
        throw DraftSnapshotError.invalidContents
      }
    }
    if retainedLowQualityManualReview == true {
      guard draft != nil,
        analysisSource == .manual,
        photoQualityRecommendation == nil,
        didReviewPhotoUsability,
        confirmedPhotoUsable != nil,
        confirmedStoolPresence != nil,
        confirmedForm != nil,
        confirmedApparentColor != nil,
        mixedForm != nil,
        redBlood != nil,
        blackAppearance != nil,
        blackTarry != nil
      else { throw DraftSnapshotError.invalidContents }
    }
    guard note.count <= 500 else { throw DraftSnapshotError.invalidContents }
    if let confirmedForm,
      !ObservationParser.forms.contains(confirmedForm)
    {
      throw DraftSnapshotError.invalidContents
    }
    if let confirmedApparentColor,
      !ObservationParser.colors.contains(confirmedApparentColor)
    {
      throw DraftSnapshotError.invalidContents
    }
    if analysisSource == .manual {
      guard modelSuggestedImageSHA256 == nil,
        modelSuggestedAt == nil,
        generationStartedAt == nil,
        generationEndedAt == nil,
        inferenceParsePath == nil,
        fullPrefillNormalization == nil,
        photoSuggestionEngineReceiptJSON == nil
      else { throw DraftSnapshotError.invalidContents }
    } else if version == Self.validatedSuggestionVersion
      || version == Self.subjectFirstVersion
      || version == Self.fullPrefillVersion
      || version == Self.normalizationReceiptVersion
      || version == Self.providerNeutralVersion
      || version == Self.safetyPrefillVersion
      || version == Self.currentVersion
    {
      guard let draft,
        originalValidatedJSON != nil,
        modelSuggestedImageSHA256 == draft.sha256,
        modelSuggestedImageSHA256?.count == 64,
        modelSuggestedImageSHA256?.allSatisfy(\.isHexDigit) == true,
        modelSuggestedAt != nil,
        generationStartedAt != nil,
        generationEndedAt != nil,
        inferenceParsePath.flatMap(InferenceParsePath.init(rawValue:)) != nil
      else { throw DraftSnapshotError.invalidContents }
      guard let modelSuggestedAt, let generationStartedAt, let generationEndedAt,
        generationStartedAt <= generationEndedAt,
        modelSuggestedAt == generationEndedAt
      else { throw DraftSnapshotError.invalidContents }
    } else {
      let timingValues = [modelSuggestedAt, generationStartedAt, generationEndedAt]
      guard timingValues.allSatisfy({ $0 == nil })
        || timingValues.allSatisfy({ $0 != nil })
      else { throw DraftSnapshotError.invalidContents }
      if let inferenceParsePath {
        guard InferenceParsePath(rawValue: inferenceParsePath) != nil else {
          throw DraftSnapshotError.invalidContents
        }
      }
    }
    if let reviewedObservation { try ObservationParser.validate(reviewedObservation) }
    if let review {
      try ObservationParser.validate(review.original)
      try ObservationParser.validate(review.reviewed)
      guard Set(review.states.keys) == Set(ReviewField.allCases.map(\.rawValue)),
        review.states.values.allSatisfy({ ReviewState(rawValue: $0) != nil })
      else { throw DraftSnapshotError.invalidContents }
    }
    if analysisPipelineVersion == "gi-v1-direct-sanitized-jpeg-constrained-v1" {
      guard version == Self.subjectFirstVersion
        || version == Self.normalizationReceiptVersion
        || version == Self.providerNeutralVersion
        || version == Self.safetyPrefillVersion
        || version == Self.currentVersion,
        draft != nil,
        subjectConfirmation == .yes,
        confirmedPhotoUsable == true
      else { throw DraftSnapshotError.invalidContents }
    }
    if analysisPipelineVersion == "gi-v1-photo-full-prefill-ab-v1" {
      guard version == Self.fullPrefillVersion
        || version == Self.normalizationReceiptVersion
        || version == Self.providerNeutralVersion
        || version == Self.safetyPrefillVersion
        || version == Self.currentVersion,
        draft != nil,
        subjectConfirmation == nil,
        confirmedStoolPresence != nil,
        confirmedForm != nil,
        confirmedPhotoUsable != nil,
        (confirmedPhotoUsable == true) == (confirmedRetakeReason == nil),
        redBlood != nil,
        blackTarry != nil,
        let originalValidatedJSON,
        (try? StoredModelVisualSuggestion.parse(originalValidatedJSON)
          .fullPrefillSuggestion) != nil
      else { throw DraftSnapshotError.invalidContents }
    }
    if analysisPipelineVersion
      == AnalysisPipelineVersion.appStoreRawImageV12SubjectGateTuning
    {
      guard version == Self.normalizationReceiptVersion
        || version == Self.providerNeutralVersion
        || version == Self.safetyPrefillVersion
        || version == Self.currentVersion,
        draft != nil,
        subjectConfirmation == nil,
        confirmedStoolPresence != nil,
        confirmedForm != nil,
        confirmedPhotoUsable != nil,
        redBlood != nil,
        blackTarry != nil,
        let rawResponse = originalValidatedJSON,
        let fullPrefillNormalization,
        (try? fullPrefillNormalization.validate(rawResponse: rawResponse)) != nil
      else { throw DraftSnapshotError.invalidContents }
    } else if analysisPipelineVersion != "gi-v1-photo-full-prefill-ab-v1" {
      guard fullPrefillNormalization == nil else {
        throw DraftSnapshotError.invalidContents
      }
    }
    if analysisSource == .onDevicePhotoSuggestion {
      guard version == Self.providerNeutralVersion
        || version == Self.safetyPrefillVersion
        || version == Self.currentVersion,
        let draft,
        let analysisPipelineVersion,
        let rawResponse = originalValidatedJSON,
        let rawData = rawResponse.data(using: .utf8),
        let receiptJSON = photoSuggestionEngineReceiptJSON,
        let receipt = try? PhotoSuggestionEngineReceipt.decode(receiptJSON),
        (try? receipt.validate(rawOutputUTF8: rawData)) != nil,
        receipt.analyzedImageSHA256 == draft.sha256,
        receipt.identity.analysisPipelineVersion == analysisPipelineVersion,
        receipt.startedAt == generationStartedAt,
        receipt.endedAt == generationEndedAt,
        receipt.endedAt == modelSuggestedAt,
        fullPrefillNormalization == nil
      else { throw DraftSnapshotError.invalidContents }
    } else {
      guard photoSuggestionEngineReceiptJSON == nil else {
        throw DraftSnapshotError.invalidContents
      }
    }
  }

  /// Upgrades only the automatic V9 appearance prefill. A stored value that
  /// differs from V9's automatic value is a person's edit and is preserved.
  /// V8 and earlier already used the same complete tri-state mapping as V10,
  /// so rewriting those values would risk erasing an edit with no benefit.
  /// The raw fused canonical value is untouched -- it always lives in
  /// `originalValidatedJSON`/the receipt, never here. Snapshots already at
  /// `currentVersion`, manual entries, and photo-less entries are unaffected.
  mutating func migratedForAppearancePrefill() {
    guard version == Self.safetyPrefillVersion,
      analysisSource != .manual,
      let originalValidatedJSON
    else { return }
    let parsed: StoredModelVisualSuggestion
    if let fullPrefillNormalization,
      let normalized = try? fullPrefillNormalization.validate(
        rawResponse: originalValidatedJSON
      )
    {
      parsed = .fullPrefillV1(normalized)
    } else if let stored = try? StoredModelVisualSuggestion.parse(
      originalValidatedJSON
    ) {
      parsed = stored
    } else {
      // Validation already rejects an unauthenticated provider-neutral raw
      // response. Preserve legacy display values rather than guessing if an
      // older normalized candidate cannot be replayed here.
      return
    }

    func migrate(
      _ stored: inout SymptomFlag?,
      from answer: PhotoSuggestionAnswer
    ) {
      guard stored == answer.legacyV9AppearancePrefillFlag else { return }
      stored = answer.appearancePrefillFlag
    }
    if let v2 = parsed.fullPrefillV2Suggestion {
      migrate(&redBlood, from: v2.redAppearingMaterial)
      migrate(&blackAppearance, from: v2.blackAppearance)
      migrate(&blackTarry, from: v2.blackTarryAppearance)
      return
    }
    if let v1 = parsed.fullPrefillSuggestion {
      migrate(&redBlood, from: v1.redAppearingMaterial)
      migrate(&blackTarry, from: v1.blackTarryAppearance)
      // V1 full-prefill payloads carry no blackAppearance field; leave it as
      // decoded (always nil for this pipeline; see validateStructure()).
    }
  }
}

enum DraftSnapshotError: Error, LocalizedError, Equatable {
  case unsupportedVersion
  case invalidReference
  case invalidContents
  case missingDraftFile
  case draftHashMismatch
  case unreadableDraftImage

  var errorDescription: String? {
    switch self {
    case .unsupportedVersion: "This unfinished draft was created by an unsupported app version."
    case .invalidReference: "This unfinished draft has an invalid local photo reference."
    case .invalidContents: "This unfinished draft could not be validated safely."
    case .missingDraftFile: "The local photo for this unfinished draft is missing."
    case .draftHashMismatch: "The local photo for this unfinished draft no longer matches its saved record."
    case .unreadableDraftImage: "The local photo for this unfinished draft could not be opened."
    }
  }
}

enum DraftSnapshotRestoreResult {
  case none
  case restored(DraftSnapshot, URL?, UIImage?)
  /// Exposes validated transaction metadata before attempting to read its
  /// draft JPEG. A committed exact-match record can therefore finish cleanup
  /// even if the draft was already deleted before a process interruption.
  case pendingTransaction(DraftSnapshot)
  /// File protection can make an otherwise valid local snapshot unavailable
  /// until the person unlocks the device. This is never a reason to discard.
  case temporarilyUnavailable(String)
  case unavailable(String)
}

@MainActor final class DraftSnapshotStore {
  typealias SaveFailureInjector = @MainActor () throws -> Void
  typealias DataReader = @MainActor (URL) throws -> Data
  typealias DirectoryContents = @MainActor (URL) throws -> [URL]
  typealias ItemRemover = @MainActor (URL) throws -> Void
  typealias BackupExcluder = @MainActor (URL) throws -> Void

  private let imageStore: ImageStore
  private let fileManager: FileManager
  private let protectedDataIsAvailable: @MainActor () -> Bool
  private let saveFailureInjector: SaveFailureInjector?
  private let dataReader: DataReader
  private let directoryContents: DirectoryContents
  private let itemRemover: ItemRemover
  private let backupExcluder: BackupExcluder
  private let writeGate: JournalWriteGate
  private let filename = "active-draft.v1.json"

  init(
    imageStore: ImageStore,
    fileManager: FileManager = .default,
    protectedDataIsAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
    saveFailureInjector: SaveFailureInjector? = nil,
    dataReader: DataReader? = nil,
    directoryContents: DirectoryContents? = nil,
    itemRemover: ItemRemover? = nil,
    backupExcluder: BackupExcluder? = nil,
    writeGate: JournalWriteGate? = nil
  ) {
    self.imageStore = imageStore
    self.fileManager = fileManager
    self.protectedDataIsAvailable = protectedDataIsAvailable
    self.saveFailureInjector = saveFailureInjector
    self.dataReader = dataReader ?? { try Data(contentsOf: $0) }
    self.directoryContents = directoryContents ?? {
      try fileManager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
    }
    self.itemRemover = itemRemover ?? { try fileManager.removeItem(at: $0) }
    self.backupExcluder = backupExcluder ?? AppFolders.excludeFromBackup
    self.writeGate = writeGate ?? .app
  }

  func save(_ snapshot: DraftSnapshot) throws {
    try writeGate.requireWritable()
    try snapshot.validateStructure()
    try saveFailureInjector?()
    let url = try snapshotURL()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(snapshot)
    // Stage the complete payload in the same directory, apply both protection
    // policies to that concrete file, then atomically replace the public
    // snapshot name. If either precommit policy fails, the prior snapshot is
    // unchanged and callers may safely retain their prior draft state.
    let staged = url.deletingLastPathComponent().appendingPathComponent(
      ".active-draft.v1.\(UUID().uuidString).tmp",
      isDirectory: false
    )
    defer { try? fileManager.removeItem(at: staged) }
    try data.write(to: staged, options: [.atomic, .completeFileProtection])
    try backupExcluder(staged)
    let renameStatus = staged.path.withCString { source in
      url.path.withCString { destination in
        Darwin.rename(source, destination)
      }
    }
    let renameErrno = errno
    guard renameStatus == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(renameErrno))
    }
  }

  func restore() -> DraftSnapshotRestoreResult {
    guard protectedDataIsAvailable() else {
      return temporarilyUnavailableResult()
    }
    do {
      let snapshotURL = try snapshotURL()
      guard fileManager.fileExists(atPath: snapshotURL.path) else {
        return try orphanedDraftFiles().isEmpty ? .none : .unavailable(
          "An unfinished photo was retained safely, but its local draft record is missing. It was not added to your journal."
        )
      }
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      var snapshot = try decoder.decode(DraftSnapshot.self, from: dataReader(snapshotURL))
      try snapshot.validateStructure()
      snapshot.migratedForAppearancePrefill()
      if snapshot.pendingEntryID != nil {
        return .pendingTransaction(snapshot)
      }
      return try materialize(snapshot)
    } catch {
      if isProtectedDataReadFailure(error) { return temporarilyUnavailableResult() }
      return .unavailable(
        "An unfinished draft could not be reopened safely. Its local files were kept unchanged. \(error.localizedDescription)"
      )
    }
  }

  /// Called only after a pending transaction was proven absent. At that point
  /// its snapshot represents an unfinished entry and the referenced JPEG must
  /// still pass the ordinary hash/image checks before UI restoration.
  func materializePendingDraft(_ snapshot: DraftSnapshot) -> DraftSnapshotRestoreResult {
    do {
      try snapshot.validateStructure()
      return try materialize(snapshot)
    } catch {
      if isProtectedDataReadFailure(error) { return temporarilyUnavailableResult() }
      return .unavailable(
        "An unfinished draft could not be reopened safely. Its local files were kept unchanged. \(error.localizedDescription)"
      )
    }
  }

  /// Finishes a proven committed transaction in a crash-idempotent order:
  /// remove only its exact hash-verified draft, then remove the snapshot last.
  /// A missing referenced draft means the first boundary already completed.
  func finishCommittedTransactionCleanup(_ snapshot: DraftSnapshot) throws {
    try writeGate.requireWritable()
    try snapshot.validateStructure()
    guard snapshot.pendingEntryID != nil, snapshot.pendingEntryFingerprint != nil else {
      throw DraftSnapshotError.invalidContents
    }
    if let draft = snapshot.draft {
      let draftURL = try imageStore.draftsDirectory().appendingPathComponent(draft.filename, isDirectory: false)
      if fileManager.fileExists(atPath: draftURL.path) {
        let bytes = try dataReader(draftURL)
        guard Self.hexSHA256(bytes) == draft.sha256 else {
          // A different file at the same local name is not ours to delete.
          throw DraftSnapshotError.draftHashMismatch
        }
        try itemRemover(draftURL)
        guard !fileManager.fileExists(atPath: draftURL.path) else {
          throw CocoaError(.fileWriteUnknown)
        }
      }
    }
    guard removeSnapshot() else { throw CocoaError(.fileWriteUnknown) }
  }

  /// Called only after a successful save, a person explicitly clears the form,
  /// or the existing erase-all workflow has removed journal data.
  @discardableResult
  func removeSnapshot() -> Bool {
    do {
      try writeGate.requireWritable()
    } catch {
      return false
    }
    guard let url = try? snapshotURL() else { return false }
    guard fileManager.fileExists(atPath: url.path) else { return true }
    do {
      try itemRemover(url)
      return !fileManager.fileExists(atPath: url.path)
    } catch {
      return false
    }
  }

  /// Deliberately destructive cleanup for the explicit "discard unfinished
  /// draft" choice. This never touches saved journal photos.
  func discardAllUnfinishedDraftFiles() throws {
    try writeGate.requireWritable()
    let directory = try imageStore.draftsDirectory().standardizedFileURL
    let snapshot = try snapshotURL().standardizedFileURL
    let files = try directoryContents(directory)
    let draftJPEGs = files.map(\.standardizedFileURL).filter {
      $0.deletingLastPathComponent() == directory
        && $0.pathExtension.lowercased() == "jpg"
    }
    // Keep the recovery record until every draft photo has been confirmed
    // removed. A partial failure therefore remains explicitly retryable.
    for file in draftJPEGs {
      try itemRemover(file)
    }
    if fileManager.fileExists(atPath: snapshot.path) {
      try itemRemover(snapshot)
    }
    let remaining = try directoryContents(directory).map(\.standardizedFileURL)
    guard !fileManager.fileExists(atPath: snapshot.path),
      remaining.contains(where: { $0.deletingLastPathComponent() == directory && $0.pathExtension.lowercased() == "jpg" }) == false
    else { throw CocoaError(.fileWriteUnknown) }
  }

  private func materialize(_ snapshot: DraftSnapshot) throws -> DraftSnapshotRestoreResult {
    guard let draft = snapshot.draft else {
      // Do not sweep unrelated photo drafts while restoring a valid manual
      // entry. Those files require their own explicit recovery decision.
      return .restored(snapshot, nil, nil)
    }
    let draftURL = try imageStore.draftsDirectory().appendingPathComponent(draft.filename)
    guard fileManager.fileExists(atPath: draftURL.path) else { throw DraftSnapshotError.missingDraftFile }
    let data = try dataReader(draftURL)
    guard Self.hexSHA256(data) == draft.sha256 else { throw DraftSnapshotError.draftHashMismatch }
    guard let image = UIImage(data: data) else { throw DraftSnapshotError.unreadableDraftImage }
    pruneOrphans(keeping: draft.filename)
    return .restored(snapshot, draftURL, image)
  }

  /// A valid snapshot is authoritative. Old draft JPEGs are therefore safe to
  /// remove only after its referenced image has been restored and verified.
  private func pruneOrphans(keeping filename: String) {
    // Restoration itself is read-only and remains useful during recovery, but
    // orphan pruning is a mutation. A pre-erase or marker-blocked store must
    // preserve every non-authoritative JPEG unchanged.
    guard (try? writeGate.requireWritable()) != nil,
      let directory = try? imageStore.draftsDirectory(),
      let files = try? directoryContents(directory)
    else { return }
    for file in files where file.pathExtension.lowercased() == "jpg" && file.lastPathComponent != filename {
      try? itemRemover(file)
    }
  }

  private func orphanedDraftFiles() throws -> [URL] {
    let directory = try imageStore.draftsDirectory()
    return try directoryContents(directory).filter { $0.pathExtension.lowercased() == "jpg" }
  }

  private func temporarilyUnavailableResult() -> DraftSnapshotRestoreResult {
    .temporarilyUnavailable(
      "Your unfinished entry is still protected on this device. Unlock your iPhone, then try reopening it."
    )
  }

  private func isProtectedDataReadFailure(_ error: Error) -> Bool {
    if !protectedDataIsAvailable() { return true }
    let cocoa = error as NSError
    if cocoa.domain == NSCocoaErrorDomain,
      cocoa.code == CocoaError.Code.fileReadNoPermission.rawValue
    {
      return true
    }
    if cocoa.domain == NSPOSIXErrorDomain,
      cocoa.code == 1 || cocoa.code == 13
    {
      return true
    }
    if let underlying = cocoa.userInfo[NSUnderlyingErrorKey] as? NSError,
      underlying.domain == NSPOSIXErrorDomain,
      underlying.code == 1 || underlying.code == 13
    {
      return true
    }
    return false
  }

  private func snapshotURL() throws -> URL {
    try imageStore.draftsDirectory().appendingPathComponent(filename, isDirectory: false)
  }

  private static func hexSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

// MARK: - Existing-entry edit drafts

/// The only persisted payload for an unfinished local existing-entry edit. It intentionally
/// contains person-editable values plus hashes; it cannot contain a photo
/// reference, image bytes, original model response, or provenance payload.
struct EntryEditDraftSnapshot: Codable, Equatable {
  static let retakeReasonVersion = 3
  static let currentVersion = 4

  let version: Int
  let entryID: UUID
  let baselineRecordFingerprint: String
  let inputHash: String
  var pendingSave: Bool
  var expectedPostSaveRecordFingerprint: String?
  let input: EntryEditInput

  init(
    entryID: UUID,
    baselineRecordFingerprint: String,
    input: EntryEditInput,
    pendingSave: Bool,
    expectedPostSaveRecordFingerprint: String? = nil
  ) throws {
    self.version = Self.currentVersion
    self.entryID = entryID
    self.baselineRecordFingerprint = baselineRecordFingerprint
    self.inputHash = try input.canonicalSHA256()
    self.pendingSave = pendingSave
    self.expectedPostSaveRecordFingerprint = expectedPostSaveRecordFingerprint
    self.input = input
    try validate(expectedEntryID: entryID)
  }

  func validate(expectedEntryID: UUID) throws {
    let isLegacyNonpending = version == 1
      && !pendingSave && expectedPostSaveRecordFingerprint == nil
    let isLegacyProofPair = version == 2
      && (pendingSave == (expectedPostSaveRecordFingerprint != nil))
    let isRetakeReasonVersion = version == Self.retakeReasonVersion
      && (pendingSave == (expectedPostSaveRecordFingerprint != nil))
    let isCurrent = version == Self.currentVersion
      && (pendingSave == (expectedPostSaveRecordFingerprint != nil))
    let expectedInputHash: String
    if version <= 2 {
      expectedInputHash = try input.legacyCanonicalSHA256WithoutRetakeReason()
    } else if version == Self.retakeReasonVersion {
      expectedInputHash = try input.legacyCanonicalSHA256WithoutBlackAppearance()
    } else {
      expectedInputHash = try input.canonicalSHA256()
    }
    guard (isLegacyNonpending || isLegacyProofPair
      || isRetakeReasonVersion || isCurrent),
      entryID == expectedEntryID,
      Self.isSHA256(baselineRecordFingerprint),
      Self.isSHA256(inputHash),
      expectedPostSaveRecordFingerprint.map(Self.isSHA256) ?? true,
      expectedInputHash == inputHash
    else { throw EntryEditDraftError.invalidContents }
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy(\.isHexDigit)
  }
}

enum EntryEditDraftError: Error, LocalizedError, Equatable {
  case invalidContents
  case protectedDataUnavailable
  case conflict
  case cleanupFailed

  var errorDescription: String? {
    switch self {
    case .invalidContents:
      "This unfinished edit could not be validated safely. The saved journal entry was not changed."
    case .protectedDataUnavailable:
      "This unfinished edit is protected until the iPhone is unlocked. The saved journal entry was not changed."
    case .conflict:
      "This journal entry changed after editing began. The older unfinished edit was kept but was not applied."
    case .cleanupFailed:
      "The journal change is saved, but GI Journal could not finish removing its unfinished-edit marker."
    }
  }
}

enum EntryEditDraftResumeResult: Equatable {
  case none
  case resumed(EntryEditDraftSnapshot)
  /// The row already contains the pending input, so the interrupted save was
  /// committed and the marker was removed without showing stale form values.
  case committedCleanupFinished
  case committedCleanupPending(String)
  case temporarilyUnavailable(String)
  case unavailable(String)
  case conflict(String)
}

/// Protected, backup-excluded, one-file-per-entry persistence for an editor
/// session. A pending-save bit provides a write-ahead boundary around the
/// SwiftData update, while row and input hashes make restart resumption
/// idempotent without a schema migration.
@MainActor final class EntryEditDraftStore {
  typealias DirectoryProvider = @MainActor () throws -> URL
  typealias DataReader = @MainActor (URL) throws -> Data
  typealias ItemRemover = @MainActor (URL) throws -> Void

  private let directoryProvider: DirectoryProvider
  private let fileManager: FileManager
  private let protectedDataIsAvailable: @MainActor () -> Bool
  private let dataReader: DataReader
  private let itemRemover: ItemRemover
  private let writeGate: JournalWriteGate

  init(
    directoryProvider: @escaping DirectoryProvider = { try AppFolders.entryEditDrafts() },
    fileManager: FileManager = .default,
    protectedDataIsAvailable: @escaping @MainActor () -> Bool = {
      UIApplication.shared.isProtectedDataAvailable
    },
    dataReader: DataReader? = nil,
    itemRemover: ItemRemover? = nil,
    writeGate: JournalWriteGate? = nil
  ) {
    self.directoryProvider = directoryProvider
    self.fileManager = fileManager
    self.protectedDataIsAvailable = protectedDataIsAvailable
    self.dataReader = dataReader ?? { try Data(contentsOf: $0) }
    self.itemRemover = itemRemover ?? { try fileManager.removeItem(at: $0) }
    self.writeGate = writeGate ?? .app
  }

  func save(
    input: EntryEditInput,
    entryID: UUID,
    baselineRecordFingerprint: String,
    pendingSave: Bool,
    expectedPostSaveRecordFingerprint: String? = nil
  ) throws {
    try writeGate.requireWritable()
    guard protectedDataIsAvailable() else {
      throw EntryEditDraftError.protectedDataUnavailable
    }
    let snapshot = try EntryEditDraftSnapshot(
      entryID: entryID,
      baselineRecordFingerprint: baselineRecordFingerprint,
      input: input,
      pendingSave: pendingSave,
      expectedPostSaveRecordFingerprint: expectedPostSaveRecordFingerprint
    )
    try write(snapshot)
  }

  /// Resolves both interruption sides. Baseline equality proves the database
  /// update did not commit. Exact expected-row equality proves that it did.
  /// Anything else is a conflict and leaves the unfinished local edit untouched.
  func resume(for entry: EntryRecord) -> EntryEditDraftResumeResult {
    guard protectedDataIsAvailable() else {
      return .temporarilyUnavailable(
        EntryEditDraftError.protectedDataUnavailable.localizedDescription
      )
    }
    do {
      let url = try snapshotURL(for: entry.id)
      guard fileManager.fileExists(atPath: url.path) else { return .none }
      let decoder = JSONDecoder()
      let snapshot = try decoder.decode(
        EntryEditDraftSnapshot.self,
        from: dataReader(url)
      )
      try snapshot.validate(expectedEntryID: entry.id)
      let currentFingerprint = try EntryRecordFingerprint.make(for: entry)

      if currentFingerprint == snapshot.baselineRecordFingerprint {
        if snapshot.pendingSave {
          var retryable = snapshot
          retryable.pendingSave = false
          retryable.expectedPostSaveRecordFingerprint = nil
          try write(retryable)
          return .resumed(retryable)
        }
        return .resumed(snapshot)
      }

      if snapshot.pendingSave,
        currentFingerprint == snapshot.expectedPostSaveRecordFingerprint
      {
        guard remove(entryID: entry.id) else {
          return .committedCleanupPending(
            EntryEditDraftError.cleanupFailed.localizedDescription
          )
        }
        return .committedCleanupFinished
      }
      return .conflict(EntryEditDraftError.conflict.localizedDescription)
    } catch {
      if isProtectedDataReadFailure(error) {
        return .temporarilyUnavailable(
          EntryEditDraftError.protectedDataUnavailable.localizedDescription
        )
      }
      return .unavailable(
        "\(EntryEditDraftError.invalidContents.localizedDescription) \(error.localizedDescription)"
      )
    }
  }

  /// Returns true only when the exact per-entry marker is absent after the
  /// operation. Callers must not dismiss Cancel/Close before this succeeds.
  @discardableResult
  func remove(entryID: UUID) -> Bool {
    do {
      try writeGate.requireWritable()
      guard protectedDataIsAvailable() else { return false }
      let url = try snapshotURL(for: entryID)
      guard fileManager.fileExists(atPath: url.path) else { return true }
      try itemRemover(url)
      return !fileManager.fileExists(atPath: url.path)
    } catch {
      return false
    }
  }

  /// Centralizes the Cancel/Close invariant: presentation dismissal is not
  /// invoked unless the exact unfinished local edit marker is confirmed gone.
  @discardableResult
  func removeBeforeDismiss(entryID: UUID, dismiss: () -> Void) -> Bool {
    guard remove(entryID: entryID) else { return false }
    dismiss()
    return true
  }

  func snapshotExists(entryID: UUID) -> Bool {
    guard let url = try? snapshotURL(for: entryID) else { return false }
    return fileManager.fileExists(atPath: url.path)
  }

  private func write(_ snapshot: EntryEditDraftSnapshot) throws {
    try snapshot.validate(expectedEntryID: snapshot.entryID)
    let url = try snapshotURL(for: snapshot.entryID)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(snapshot)
    // Complete protection participates in the atomic replacement. The parent
    // directory is already excluded from backup; file-level exclusion is
    // best-effort after the commit so a successful write is never reported as
    // failed because of post-commit metadata hardening.
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    try? AppFolders.excludeFromBackup(url)
  }

  private func snapshotURL(for entryID: UUID) throws -> URL {
    let directory = try directoryProvider().standardizedFileURL
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true,
      values.isSymbolicLink != true,
      (try? fileManager.destinationOfSymbolicLink(atPath: directory.path)) == nil
    else { throw EntryEditDraftError.invalidContents }
    try AppFolders.excludeFromBackup(directory)
    try AppFolders.protect(directory)
    let url = directory.appendingPathComponent(
      "\(entryID.uuidString.lowercased()).v1.json",
      isDirectory: false
    ).standardizedFileURL
    guard url.deletingLastPathComponent() == directory else {
      throw EntryEditDraftError.invalidContents
    }
    return url
  }

  private func isProtectedDataReadFailure(_ error: Error) -> Bool {
    if !protectedDataIsAvailable() { return true }
    let cocoa = error as NSError
    if cocoa.domain == NSCocoaErrorDomain,
      cocoa.code == CocoaError.Code.fileReadNoPermission.rawValue
    { return true }
    if cocoa.domain == NSPOSIXErrorDomain,
      cocoa.code == 1 || cocoa.code == 13
    { return true }
    if let underlying = cocoa.userInfo[NSUnderlyingErrorKey] as? NSError,
      underlying.domain == NSPOSIXErrorDomain,
      underlying.code == 1 || underlying.code == 13
    { return true }
    return false
  }
}
