import CryptoKit
import Foundation
import SwiftData
import GITimelineCore

@Model final class EntryRecord {
  @Attribute(.unique) var id: UUID
  var capturedAt: Date
  var imageFilename: String?
  var imageSHA256: String?
  var redBlood: String?
  var blackTarry: String?
  var dizziness: String?
  var severePain: String?
  var note: String?
  // Schema-only fields. The app deliberately exposes no UI for these.
  var painScore: Int?
  var urgency: String?
  var bm24h: Int?
  // Additive clinical fields. Nil remains valid for every legacy record.
  var confirmedBristolType: Int?
  var confirmedPhotoUsable: Bool?
  var mixedForm: String?
  var strainingOrIncomplete: String?
  var leakageOrAccident: String?
  var analysisSource: String?
  var analysisPipelineVersion: String?
  var markedForDiscussionAt: Date?
  var provenance: String
  var reviewedAt: Date?
  var originalAIJSON: String?
  var reviewedJSON: String?
  var modelID: String?
  var modelProvenanceJSON: String?
  /// Immutable app-authored marker for bundled DEBUG fixtures. User-editable
  /// notes are never used to decide what Reset Demo may delete.
  var demoKind: String?
  var imageUnavailable: Bool
  var createdAt: Date
  var updatedAt: Date

  init(input: EntryInput) {
    id = input.id; capturedAt = input.capturedAt; imageFilename = input.imageFilename; imageSHA256 = input.imageSHA256
    redBlood = input.redBlood?.rawValue; blackTarry = input.blackTarry?.rawValue; dizziness = input.dizziness?.rawValue; severePain = input.severePain?.rawValue
    note = input.note; painScore = input.painScore; urgency = input.urgency?.rawValue
    confirmedBristolType = input.confirmedBristolType; confirmedPhotoUsable = input.confirmedPhotoUsable
    mixedForm = input.mixedForm?.rawValue; strainingOrIncomplete = input.strainingOrIncomplete?.rawValue; leakageOrAccident = input.leakageOrAccident?.rawValue
    analysisSource = input.analysisSource?.rawValue; analysisPipelineVersion = input.analysisPipelineVersion; markedForDiscussionAt = input.markedForDiscussionAt
    provenance = input.provenance.rawValue; reviewedAt = input.reviewedAt; originalAIJSON = input.originalAIJSON; reviewedJSON = input.reviewedJSON; modelID = input.modelID; modelProvenanceJSON = input.modelProvenanceJSON; demoKind = input.demoKind
    imageUnavailable = false; createdAt = Date(); updatedAt = Date()
  }

  var originalModelSuggestion: StoredModelVisualSuggestion? {
    guard let rawResponse = originalAIJSON else { return nil }
    if let inferenceProvenance {
      return try? inferenceProvenance.resolvedSuggestion(
        rawResponse: rawResponse
      )
    }
    return try? StoredModelVisualSuggestion.parse(rawResponse)
  }
  var originalObservation: VisualObservation? { originalModelSuggestion?.visualObservation }
  var confirmedEntrySnapshot: ConfirmedEntrySnapshotV1? {
    guard let reviewedJSON,
      case .confirmedV1(let snapshot) = try? StoredReviewedEntry.parse(reviewedJSON)
    else { return nil }
    return snapshot
  }
  var observation: VisualObservation? {
    guard let reviewedJSON, let stored = try? StoredReviewedEntry.parse(reviewedJSON) else {
      return nil
    }
    switch stored {
    case .legacyObservation(let observation): return observation
    case .confirmedV1(let confirmation):
      return confirmation.visualObservation(
        original: originalObservation,
        hasPhoto: imageFilename != nil
      )
    }
  }
  /// New records use the explicit field. Legacy records fall back read-only to
  /// reviewed JSON and are never rewritten as part of the fallback.
  var effectiveConfirmedBristolType: Int? { confirmedBristolType ?? observation?.apparentBristolType }
  var confirmedStoolForm: ClinicalStoolForm { ClinicalStoolForm(bristolType: effectiveConfirmedBristolType) }
  var confirmedConsistency: StoolConsistency {
    ClinicalValidation.consistency(for: effectiveConfirmedBristolType)
  }
  var mixedFormAnswer: ClinicalTriState? { mixedForm.flatMap(ClinicalTriState.init(rawValue:)) }
  /// Additive V2 value stored inside the reviewedJSON confirmation envelope,
  /// avoiding a destructive SwiftData migration. Historical V1 entries return
  /// nil because their combined black/tarry answer cannot be split safely.
  var blackAppearanceAnswer: SymptomFlag? {
    confirmedEntrySnapshot?.personConfirmedBlackAppearance
  }
  var strainingOrIncompleteAnswer: ClinicalTriState? { strainingOrIncomplete.flatMap(ClinicalTriState.init(rawValue:)) }
  var leakageOrAccidentAnswer: ClinicalTriState? { leakageOrAccident.flatMap(ClinicalTriState.init(rawValue:)) }
  var urgencyLevel: UrgencyLevel? { urgency.flatMap(UrgencyLevel.init(rawValue:)) }
  var savedAnalysisSource: AnalysisSource? { analysisSource.flatMap(AnalysisSource.init(rawValue:)) }
  var requiresSafetyGuidance: Bool {
    SafetyRules.shouldShow(
      redBlood: redBlood.flatMap(SymptomFlag.init(rawValue:)),
      blackTarry: blackTarry.flatMap(SymptomFlag.init(rawValue:)),
      dizziness: dizziness.flatMap(SymptomFlag.init(rawValue:)),
      severePain: severePain.flatMap(SymptomFlag.init(rawValue:))
    )
  }
  var isMarkedForDiscussion: Bool { markedForDiscussionAt != nil }
  var inferenceProvenance: InferenceProvenanceSnapshot? {
    modelProvenanceJSON?.data(using: .utf8).flatMap { try? JSONDecoder().decode(InferenceProvenanceSnapshot.self, from: $0) }
  }
  var isUIDemoProvider: Bool {
    provenance != EntryProvenance.manual.rawValue && modelID == nil
  }
  var savedRuntimeLabel: String? {
    if isUIDemoProvider { return "UI demo · Gemma not connected" }
    guard let inferenceProvenance else { return modelID }
    if let location = inferenceProvenance.executionLocation {
      return "\(inferenceProvenance.family) · \(location.displayName)"
    }
    return inferenceProvenance.family
  }
  var reportedSymptomSummary: String {
    let flags = [("Visible red appearance", redBlood), ("Black or tar-like appearance", blackTarry), ("Dizziness", dizziness), ("Severe pain", severePain)]
    return flags.compactMap { label, value in value.map { "\(label): \($0)" } }.joined(separator: " · ")
  }
  @available(*, deprecated, renamed: "reportedSymptomSummary")
  var flagSummary: String { reportedSymptomSummary }
}

enum EntryProvenance: String { case manual, ai_unedited, ai_edited }

struct EntryInput {
  let id: UUID
  let capturedAt: Date
  let draftURL: URL?
  let imageSHA256: String?
  let redBlood: GITimelineCore.SymptomFlag?
  let blackAppearance: GITimelineCore.SymptomFlag?
  let blackTarry: GITimelineCore.SymptomFlag?
  let dizziness: GITimelineCore.SymptomFlag?
  let severePain: GITimelineCore.SymptomFlag?
  let note: String?
  let painScore: Int?
  let urgency: UrgencyLevel?
  let confirmedBristolType: Int?
  let confirmedPhotoUsable: Bool?
  let mixedForm: ClinicalTriState?
  let strainingOrIncomplete: ClinicalTriState?
  let leakageOrAccident: ClinicalTriState?
  let analysisSource: AnalysisSource?
  let analysisPipelineVersion: String?
  let markedForDiscussionAt: Date?
  let provenance: EntryProvenance
  let reviewedAt: Date?
  let originalAIJSON: String?
  let reviewedJSON: String?
  let modelID: String?
  let modelProvenanceJSON: String?
  let demoKind: String?
  let imageFilename: String?

  init(
    id: UUID,
    capturedAt: Date,
    draftURL: URL?,
    imageSHA256: String?,
    redBlood: GITimelineCore.SymptomFlag?,
    blackAppearance: GITimelineCore.SymptomFlag? = nil,
    blackTarry: GITimelineCore.SymptomFlag?,
    dizziness: GITimelineCore.SymptomFlag?,
    severePain: GITimelineCore.SymptomFlag?,
    note: String?,
    painScore: Int? = nil,
    urgency: UrgencyLevel? = nil,
    confirmedBristolType: Int? = nil,
    confirmedPhotoUsable: Bool? = nil,
    mixedForm: ClinicalTriState? = nil,
    strainingOrIncomplete: ClinicalTriState? = nil,
    leakageOrAccident: ClinicalTriState? = nil,
    analysisSource: AnalysisSource? = nil,
    analysisPipelineVersion: String? = nil,
    markedForDiscussionAt: Date? = nil,
    provenance: EntryProvenance,
    reviewedAt: Date?,
    originalAIJSON: String?,
    reviewedJSON: String?,
    modelID: String?,
    modelProvenanceJSON: String?,
    demoKind: String?,
    imageFilename: String?
  ) {
    self.id = id; self.capturedAt = capturedAt; self.draftURL = draftURL; self.imageSHA256 = imageSHA256
    self.redBlood = redBlood; self.blackAppearance = blackAppearance; self.blackTarry = blackTarry; self.dizziness = dizziness; self.severePain = severePain; self.note = note
    self.painScore = painScore; self.urgency = urgency; self.confirmedBristolType = confirmedBristolType; self.confirmedPhotoUsable = confirmedPhotoUsable
    self.mixedForm = mixedForm; self.strainingOrIncomplete = strainingOrIncomplete; self.leakageOrAccident = leakageOrAccident
    self.analysisSource = analysisSource; self.analysisPipelineVersion = analysisPipelineVersion; self.markedForDiscussionAt = markedForDiscussionAt
    self.provenance = provenance; self.reviewedAt = reviewedAt; self.originalAIJSON = originalAIJSON; self.reviewedJSON = reviewedJSON
    self.modelID = modelID; self.modelProvenanceJSON = modelProvenanceJSON; self.demoKind = demoKind; self.imageFilename = imageFilename
  }
}

/// Mutable, user-reviewed fields for an existing record. Photo identity and
/// immutable model provenance are intentionally absent so an edit cannot turn
/// into an unsafe delete/recreate or silently replace its evidence source.
struct EntryEditInput: Codable, Equatable {
  var capturedAt: Date
  var redBlood: SymptomFlag?
  var blackAppearance: SymptomFlag?
  var blackTarry: SymptomFlag?
  var dizziness: SymptomFlag?
  var severePain: SymptomFlag?
  var note: String?
  var painScore: Int?
  var urgency: UrgencyLevel?
  var confirmedBristolType: Int?
  var confirmedPhotoUsable: Bool?
  var retakeReason: PhotoRetakeReason?
  var stoolPresence: StoolPresence?
  var form: String?
  var mixedForm: ClinicalTriState?
  var strainingOrIncomplete: ClinicalTriState?
  var leakageOrAccident: ClinicalTriState?
  var apparentColor: String?

  init(entry: EntryRecord) {
    capturedAt = entry.capturedAt
    let requiresIndependentReanswer = entry.analysisPipelineVersion
      == "gi-v1-direct-sanitized-jpeg-constrained-v1"
    redBlood = requiresIndependentReanswer
      ? nil : entry.redBlood.flatMap(SymptomFlag.init(rawValue:))
    blackAppearance = requiresIndependentReanswer
      ? nil : entry.blackAppearanceAnswer
    blackTarry = requiresIndependentReanswer
      ? nil : entry.blackTarry.flatMap(SymptomFlag.init(rawValue:))
    dizziness = entry.dizziness.flatMap(SymptomFlag.init(rawValue:))
    severePain = entry.severePain.flatMap(SymptomFlag.init(rawValue:))
    note = entry.note
    painScore = entry.painScore
    urgency = entry.urgencyLevel
    confirmedBristolType = entry.effectiveConfirmedBristolType
    confirmedPhotoUsable = entry.confirmedPhotoUsable
    retakeReason = entry.confirmedEntrySnapshot?.personConfirmedRetakeReason
    stoolPresence = entry.confirmedEntrySnapshot?.personConfirmedStoolPresence
    form = entry.confirmedEntrySnapshot?.personConfirmedForm
    if confirmedPhotoUsable == false, retakeReason == nil {
      // Older envelopes predate the explicit technical reason. Preserve their
      // editability without claiming that the model supplied a reason.
      retakeReason = .other
    }
    mixedForm = entry.mixedFormAnswer
    strainingOrIncomplete = entry.strainingOrIncompleteAnswer
    leakageOrAccident = entry.leakageOrAccidentAnswer
    apparentColor = entry.confirmedEntrySnapshot?.personConfirmedApparentColor
      ?? entry.observation?.apparentColor
  }

  /// Hashes only the editable, person-reviewed values. The JSON draft stores
  /// this hash alongside the input so a malformed or partially replaced file
  /// cannot be accepted as an authoritative unfinished edit.
  func canonicalSHA256() throws -> String {
    let normalized = normalizedForPersistence()
    struct Payload: Codable {
      let schemaVersion: Int
      let capturedAtBits: UInt64
      let redBlood: String?
      let blackAppearance: String?
      let blackTarry: String?
      let dizziness: String?
      let severePain: String?
      let note: String?
      let painScore: Int?
      let urgency: String?
      let confirmedBristolType: Int?
      let confirmedPhotoUsable: Bool?
      let retakeReason: String?
      let stoolPresence: String?
      let form: String?
      let mixedForm: String?
      let strainingOrIncomplete: String?
      let leakageOrAccident: String?
      let apparentColor: String?
    }
    return try Self.hexSHA256(
      Payload(
        schemaVersion: 2,
        capturedAtBits: normalized.capturedAt.timeIntervalSinceReferenceDate.bitPattern,
        redBlood: normalized.redBlood?.rawValue,
        blackAppearance: normalized.blackAppearance?.rawValue,
        blackTarry: normalized.blackTarry?.rawValue,
        dizziness: normalized.dizziness?.rawValue,
        severePain: normalized.severePain?.rawValue,
        note: normalized.note,
        painScore: normalized.painScore,
        urgency: normalized.urgency?.rawValue,
        confirmedBristolType: normalized.confirmedBristolType,
        confirmedPhotoUsable: normalized.confirmedPhotoUsable,
        retakeReason: normalized.retakeReason?.rawValue,
        stoolPresence: normalized.stoolPresence?.rawValue,
        form: normalized.form,
        mixedForm: normalized.mixedForm?.rawValue,
        strainingOrIncomplete: normalized.strainingOrIncomplete?.rawValue,
        leakageOrAccident: normalized.leakageOrAccident?.rawValue,
        apparentColor: normalized.apparentColor
      )
    )
  }

  /// Version-3 edit drafts include the full editable tuple and retake reason,
  /// but predate the independent unusual-black field. Preserve their exact
  /// canonical hash read-only; every new draft uses schema version 2 above.
  func legacyCanonicalSHA256WithoutBlackAppearance() throws -> String {
    let normalized = normalizedForPersistence()
    struct Payload: Codable {
      let schemaVersion: Int
      let capturedAtBits: UInt64
      let redBlood: String?
      let blackTarry: String?
      let dizziness: String?
      let severePain: String?
      let note: String?
      let painScore: Int?
      let urgency: String?
      let confirmedBristolType: Int?
      let confirmedPhotoUsable: Bool?
      let retakeReason: String?
      let stoolPresence: String?
      let form: String?
      let mixedForm: String?
      let strainingOrIncomplete: String?
      let leakageOrAccident: String?
      let apparentColor: String?
    }
    return try Self.hexSHA256(Payload(
      schemaVersion: 1,
      capturedAtBits: normalized.capturedAt.timeIntervalSinceReferenceDate.bitPattern,
      redBlood: normalized.redBlood?.rawValue,
      blackTarry: normalized.blackTarry?.rawValue,
      dizziness: normalized.dizziness?.rawValue,
      severePain: normalized.severePain?.rawValue,
      note: normalized.note,
      painScore: normalized.painScore,
      urgency: normalized.urgency?.rawValue,
      confirmedBristolType: normalized.confirmedBristolType,
      confirmedPhotoUsable: normalized.confirmedPhotoUsable,
      retakeReason: normalized.retakeReason?.rawValue,
      stoolPresence: normalized.stoolPresence?.rawValue,
      form: normalized.form,
      mixedForm: normalized.mixedForm?.rawValue,
      strainingOrIncomplete: normalized.strainingOrIncomplete?.rawValue,
      leakageOrAccident: normalized.leakageOrAccident?.rawValue,
      apparentColor: normalized.apparentColor
    ))
  }

  /// Version-1/2 edit drafts predate editable retake/subject/form values. Their hash is
  /// still accepted read-only so an app update cannot strand a valid local
  /// unfinished edit. Every newly written draft uses `canonicalSHA256()`.
  func legacyCanonicalSHA256WithoutRetakeReason() throws -> String {
    var normalized = self
    let trimmed = normalized.note?.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    normalized.note = trimmed?.isEmpty == true ? nil : trimmed
    if normalized.confirmedPhotoUsable == false {
      normalized.apparentColor = "unable_to_assess"
    }
    struct Payload: Codable {
      let schemaVersion: Int
      let capturedAtBits: UInt64
      let redBlood: String?
      let blackTarry: String?
      let dizziness: String?
      let severePain: String?
      let note: String?
      let painScore: Int?
      let urgency: String?
      let confirmedBristolType: Int?
      let confirmedPhotoUsable: Bool?
      let mixedForm: String?
      let strainingOrIncomplete: String?
      let leakageOrAccident: String?
      let apparentColor: String?
    }
    return try Self.hexSHA256(Payload(
      schemaVersion: 1,
      capturedAtBits: normalized.capturedAt.timeIntervalSinceReferenceDate.bitPattern,
      redBlood: normalized.redBlood?.rawValue,
      blackTarry: normalized.blackTarry?.rawValue,
      dizziness: normalized.dizziness?.rawValue,
      severePain: normalized.severePain?.rawValue,
      note: normalized.note,
      painScore: normalized.painScore,
      urgency: normalized.urgency?.rawValue,
      confirmedBristolType: normalized.confirmedBristolType,
      confirmedPhotoUsable: normalized.confirmedPhotoUsable,
      mixedForm: normalized.mixedForm?.rawValue,
      strainingOrIncomplete: normalized.strainingOrIncomplete?.rawValue,
      leakageOrAccident: normalized.leakageOrAccident?.rawValue,
      apparentColor: normalized.apparentColor
    ))
  }

  /// Normalizes only values whose persisted meaning is deterministic. Red and
  /// black/tarry answers are deliberately independent person observations and
  /// are never cleared when photo usability changes.
  func normalizedForPersistence() -> EntryEditInput {
    var normalized = self
    let trimmed = normalized.note?.trimmingCharacters(in: .whitespacesAndNewlines)
    normalized.note = trimmed?.isEmpty == true ? nil : trimmed
    if normalized.confirmedPhotoUsable == false {
      normalized.apparentColor = "unable_to_assess"
      if normalized.retakeReason == nil { normalized.retakeReason = .other }
    } else {
      normalized.retakeReason = nil
    }
    let hasFullPrefillTuple = normalized.stoolPresence != nil
      && normalized.form != nil
    if hasFullPrefillTuple && normalized.confirmedPhotoUsable == false {
      normalized.confirmedBristolType = nil
      normalized.form = "unable_to_assess"
      normalized.mixedForm = .unsure
      normalized.apparentColor = "unable_to_assess"
      normalized.redBlood = .unsure
      if normalized.blackAppearance != nil {
        normalized.blackAppearance = .unsure
      }
      normalized.blackTarry = .unsure
      normalized.strainingOrIncomplete = nil
      normalized.leakageOrAccident = nil
    } else if hasFullPrefillTuple && normalized.stoolPresence != .stool {
      normalized.confirmedBristolType = nil
      normalized.form = "unable_to_assess"
      normalized.mixedForm = .unsure
      normalized.strainingOrIncomplete = nil
      normalized.leakageOrAccident = nil
      // V2 (and the complete manual sheet) carries an independent
      // unusual-black answer. For those records a usable non-stool photo may
      // still support color/red/black/tar appearance observations. Historical
      // V1 has no separate black field and retains its stricter abstention.
      if normalized.blackAppearance == nil {
        normalized.apparentColor = "unable_to_assess"
        normalized.redBlood = .unsure
        normalized.blackTarry = .unsure
      }
    }
    return normalized
  }

  private static func hexSHA256<T: Encodable>(_ payload: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return SHA256.hash(data: try encoder.encode(payload))
      .map { String(format: "%02x", $0) }.joined()
  }

}

/// A hash of every persisted field in one saved entry. Edit drafts retain only
/// this digest, never the photo path/bytes or stored model output used to make
/// it. A mismatch means the saved row changed after the editor opened and the
/// old draft must not overwrite it.
enum EntryRecordFingerprint {
  private struct Payload: Codable {
    let schemaVersion: Int
    let id: UUID
    let capturedAtBits: UInt64
    let imageFilename: String?
    let imageSHA256: String?
    let redBlood: String?
    let blackTarry: String?
    let dizziness: String?
    let severePain: String?
    let note: String?
    let painScore: Int?
    let urgency: String?
    let bm24h: Int?
    let confirmedBristolType: Int?
    let confirmedPhotoUsable: Bool?
    let mixedForm: String?
    let strainingOrIncomplete: String?
    let leakageOrAccident: String?
    let analysisSource: String?
    let analysisPipelineVersion: String?
    let markedForDiscussionAtBits: UInt64?
    let provenance: String
    let reviewedAtBits: UInt64?
    let originalAIJSON: String?
    let reviewedJSON: String?
    let modelID: String?
    let modelProvenanceJSON: String?
    let demoKind: String?
    let imageUnavailable: Bool
    let createdAtBits: UInt64
    let updatedAtBits: UInt64
  }

  static func make(for record: EntryRecord) throws -> String {
    let payload = Payload(
      schemaVersion: 1,
      id: record.id,
      capturedAtBits: bits(record.capturedAt),
      imageFilename: record.imageFilename,
      imageSHA256: record.imageSHA256,
      redBlood: record.redBlood,
      blackTarry: record.blackTarry,
      dizziness: record.dizziness,
      severePain: record.severePain,
      note: record.note,
      painScore: record.painScore,
      urgency: record.urgency,
      bm24h: record.bm24h,
      confirmedBristolType: record.confirmedBristolType,
      confirmedPhotoUsable: record.confirmedPhotoUsable,
      mixedForm: record.mixedForm,
      strainingOrIncomplete: record.strainingOrIncomplete,
      leakageOrAccident: record.leakageOrAccident,
      analysisSource: record.analysisSource,
      analysisPipelineVersion: record.analysisPipelineVersion,
      markedForDiscussionAtBits: record.markedForDiscussionAt.map(bits),
      provenance: record.provenance,
      reviewedAtBits: record.reviewedAt.map(bits),
      originalAIJSON: record.originalAIJSON,
      reviewedJSON: record.reviewedJSON,
      modelID: record.modelID,
      modelProvenanceJSON: record.modelProvenanceJSON,
      demoKind: record.demoKind,
      imageUnavailable: record.imageUnavailable,
      createdAtBits: bits(record.createdAt),
      updatedAtBits: bits(record.updatedAt)
    )
    return try hash(payload)
  }

  /// Predicts the exact durable row produced by an already validated update.
  /// This is written into the pending marker before the SwiftData commit so a
  /// restart can distinguish that exact commit from any unrelated row change.
  static func make(
    for record: EntryRecord,
    applying input: EntryEditInput,
    reviewedJSON: String?,
    provenance: String,
    updatedAt: Date
  ) throws -> String {
    let normalized = input.normalizedForPersistence()
    return try hash(Payload(
      schemaVersion: 1,
      id: record.id,
      capturedAtBits: bits(normalized.capturedAt),
      imageFilename: record.imageFilename,
      imageSHA256: record.imageSHA256,
      redBlood: normalized.redBlood?.rawValue,
      blackTarry: normalized.blackTarry?.rawValue,
      dizziness: normalized.dizziness?.rawValue,
      severePain: normalized.severePain?.rawValue,
      note: normalized.note,
      painScore: normalized.painScore,
      urgency: normalized.urgency?.rawValue,
      bm24h: record.bm24h,
      confirmedBristolType: normalized.confirmedBristolType,
      confirmedPhotoUsable: normalized.confirmedPhotoUsable,
      mixedForm: normalized.mixedForm?.rawValue,
      strainingOrIncomplete: normalized.strainingOrIncomplete?.rawValue,
      leakageOrAccident: normalized.leakageOrAccident?.rawValue,
      analysisSource: record.analysisSource,
      analysisPipelineVersion: record.analysisPipelineVersion,
      markedForDiscussionAtBits: record.markedForDiscussionAt.map(bits),
      provenance: provenance,
      reviewedAtBits: record.reviewedAt.map(bits),
      originalAIJSON: record.originalAIJSON,
      reviewedJSON: reviewedJSON,
      modelID: record.modelID,
      modelProvenanceJSON: record.modelProvenanceJSON,
      demoKind: record.demoKind,
      imageUnavailable: record.imageUnavailable,
      createdAtBits: bits(record.createdAt),
      updatedAtBits: bits(updatedAt)
    ))
  }

  private static func hash(_ payload: Payload) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return SHA256.hash(data: try encoder.encode(payload))
      .map { String(format: "%02x", $0) }.joined()
  }

  private static func bits(_ date: Date) -> UInt64 {
    date.timeIntervalSinceReferenceDate.bitPattern
  }
}

/// Stable identity for one exact save payload. This deliberately excludes
/// draft paths and sanctioned mutable state (discussion mark plus availability
/// timestamps), while including every immutable field copied from EntryInput
/// into EntryRecord plus the canonical photo filename/hash pair. A UUID match
/// alone is never enough for idempotency.
enum EntryTransactionFingerprint {
  private struct Payload: Codable {
    let schemaVersion: Int
    let id: UUID
    let capturedAtBits: UInt64
    let imageFilename: String?
    let imageSHA256: String?
    let redBlood: String?
    let blackTarry: String?
    let dizziness: String?
    let severePain: String?
    let note: String?
    let painScore: Int?
    let urgency: String?
    let bm24h: Int?
    let confirmedBristolType: Int?
    let confirmedPhotoUsable: Bool?
    let mixedForm: String?
    let strainingOrIncomplete: String?
    let leakageOrAccident: String?
    let analysisSource: String?
    let analysisPipelineVersion: String?
    let provenance: String
    let reviewedAtBits: UInt64?
    let originalAIJSON: String?
    let reviewedJSON: String?
    let modelID: String?
    let modelProvenanceJSON: String?
    let demoKind: String?
  }

  static func make(for input: EntryInput) throws -> String {
    try make(
      Payload(
        schemaVersion: 1,
        id: input.id,
        capturedAtBits: dateBits(input.capturedAt),
        imageFilename: input.imageFilename,
        imageSHA256: input.imageSHA256,
        redBlood: input.redBlood?.rawValue,
        blackTarry: input.blackTarry?.rawValue,
        dizziness: input.dizziness?.rawValue,
        severePain: input.severePain?.rawValue,
        note: input.note,
        painScore: input.painScore,
        urgency: input.urgency?.rawValue,
        bm24h: nil,
        confirmedBristolType: input.confirmedBristolType,
        confirmedPhotoUsable: input.confirmedPhotoUsable,
        mixedForm: input.mixedForm?.rawValue,
        strainingOrIncomplete: input.strainingOrIncomplete?.rawValue,
        leakageOrAccident: input.leakageOrAccident?.rawValue,
        analysisSource: input.analysisSource?.rawValue,
        analysisPipelineVersion: input.analysisPipelineVersion,
        provenance: input.provenance.rawValue,
        reviewedAtBits: input.reviewedAt.map(dateBits),
        originalAIJSON: input.originalAIJSON,
        reviewedJSON: input.reviewedJSON,
        modelID: input.modelID,
        modelProvenanceJSON: input.modelProvenanceJSON,
        demoKind: input.demoKind
      )
    )
  }

  static func make(for record: EntryRecord) throws -> String {
    try make(
      Payload(
        schemaVersion: 1,
        id: record.id,
        capturedAtBits: dateBits(record.capturedAt),
        imageFilename: record.imageFilename,
        imageSHA256: record.imageSHA256,
        redBlood: record.redBlood,
        blackTarry: record.blackTarry,
        dizziness: record.dizziness,
        severePain: record.severePain,
        note: record.note,
        painScore: record.painScore,
        urgency: record.urgency,
        bm24h: record.bm24h,
        confirmedBristolType: record.confirmedBristolType,
        confirmedPhotoUsable: record.confirmedPhotoUsable,
        mixedForm: record.mixedForm,
        strainingOrIncomplete: record.strainingOrIncomplete,
        leakageOrAccident: record.leakageOrAccident,
        analysisSource: record.analysisSource,
        analysisPipelineVersion: record.analysisPipelineVersion,
        provenance: record.provenance,
        reviewedAtBits: record.reviewedAt.map(dateBits),
        originalAIJSON: record.originalAIJSON,
        reviewedJSON: record.reviewedJSON,
        modelID: record.modelID,
        modelProvenanceJSON: record.modelProvenanceJSON,
        demoKind: record.demoKind
      )
    )
  }

  private static func make(_ payload: Payload) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let bytes = try encoder.encode(payload)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  private static func dateBits(_ date: Date) -> UInt64 {
    date.timeIntervalSinceReferenceDate.bitPattern
  }
}
