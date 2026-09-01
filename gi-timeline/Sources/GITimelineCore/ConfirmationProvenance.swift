import Foundation

public enum ConfirmationField: String, Codable, CaseIterable, Sendable {
  case photoUsable = "photo_usable"
  case retakeReason = "retake_reason"
  case stoolPresence = "stool_presence"
  case bristolType = "bristol_type"
  case form
  case mixedForm = "mixed_form"
  case apparentColor = "apparent_color"
  case redMaterial = "red_material"
  case blackAppearance = "black_appearance"
  case blackTarry = "black_tarry"
}

public enum FieldConfirmationProvenance: String, Codable, CaseIterable, Sendable {
  case acceptedUnchanged
  case editedBeforeConfirmation
  case independentPersonAnswer
  case manualNoSuggestion
  case editedAfterConfirmation

  public var displayName: String {
    switch self {
    case .acceptedUnchanged: return "Accepted unchanged"
    case .editedBeforeConfirmation: return "Edited before confirmation"
    case .independentPersonAnswer: return "Answered independently"
    case .manualNoSuggestion: return "Entered manually"
    case .editedAfterConfirmation: return "Edited after confirmation"
    }
  }
}

/// Versioned app-authored confirmation envelope stored in the existing
/// `reviewedJSON` column. This avoids mutating the frozen SwiftData V1 model
/// while preserving a strict separation between a model suggestion and the
/// values a person confirmed with the one final action.
public struct ConfirmedEntrySnapshotV1: Codable, Equatable, Sendable {
  public static let schemaVersion = "gi-confirmed-entry-v1"

  public let schemaVersion: String
  public let confirmedAt: Date
  public let personConfirmedPhotoUsable: Bool?
  /// The value adopted by the one whole-entry confirmation. Later edits may
  /// change `personConfirmedRetakeReason`, but never rewrite this receipt.
  public let initiallyAcceptedPhotoUsable: Bool?
  public let initiallyAcceptedRetakeReason: PhotoRetakeReason?
  public let initiallyAcceptedStoolPresence: StoolPresence?
  public let initiallyAcceptedBristolType: Int?
  public let initiallyAcceptedForm: String?
  public let initiallyAcceptedMixedForm: ClinicalTriState?
  public let initiallyAcceptedApparentColor: String?
  public let initiallyAcceptedRed: SymptomFlag?
  public let initiallyAcceptedBlackAppearance: SymptomFlag?
  public let initiallyAcceptedBlackTarry: SymptomFlag?
  public let personConfirmedRetakeReason: PhotoRetakeReason?
  public let personConfirmedStoolPresence: StoolPresence?
  public let personConfirmedBristolType: Int?
  public let personConfirmedForm: String?
  public let personConfirmedMixedForm: ClinicalTriState?
  public let personConfirmedApparentColor: String?
  public let personConfirmedRed: SymptomFlag?
  public let personConfirmedBlackAppearance: SymptomFlag?
  public let personConfirmedBlackTarry: SymptomFlag?
  public let fieldProvenance: [String: FieldConfirmationProvenance]
  public let personConfirmedSubject: Bool?

  public init(
    schemaVersion: String = Self.schemaVersion,
    confirmedAt: Date,
    personConfirmedPhotoUsable: Bool?,
    initiallyAcceptedPhotoUsable: Bool? = nil,
    initiallyAcceptedRetakeReason: PhotoRetakeReason? = nil,
    initiallyAcceptedStoolPresence: StoolPresence? = nil,
    initiallyAcceptedBristolType: Int? = nil,
    initiallyAcceptedForm: String? = nil,
    initiallyAcceptedMixedForm: ClinicalTriState? = nil,
    initiallyAcceptedApparentColor: String? = nil,
    initiallyAcceptedRed: SymptomFlag? = nil,
    initiallyAcceptedBlackAppearance: SymptomFlag? = nil,
    initiallyAcceptedBlackTarry: SymptomFlag? = nil,
    personConfirmedRetakeReason: PhotoRetakeReason? = nil,
    personConfirmedStoolPresence: StoolPresence? = nil,
    personConfirmedBristolType: Int?,
    personConfirmedForm: String? = nil,
    personConfirmedMixedForm: ClinicalTriState?,
    personConfirmedApparentColor: String?,
    personConfirmedRed: SymptomFlag?,
    personConfirmedBlackAppearance: SymptomFlag? = nil,
    personConfirmedBlackTarry: SymptomFlag?,
    fieldProvenance: [ConfirmationField: FieldConfirmationProvenance],
    personConfirmedSubject: Bool? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.confirmedAt = confirmedAt
    self.personConfirmedPhotoUsable = personConfirmedPhotoUsable
    self.initiallyAcceptedPhotoUsable = initiallyAcceptedPhotoUsable
    self.initiallyAcceptedRetakeReason = initiallyAcceptedRetakeReason
    self.initiallyAcceptedStoolPresence = initiallyAcceptedStoolPresence
    self.initiallyAcceptedBristolType = initiallyAcceptedBristolType
    self.initiallyAcceptedForm = initiallyAcceptedForm
    self.initiallyAcceptedMixedForm = initiallyAcceptedMixedForm
    self.initiallyAcceptedApparentColor = initiallyAcceptedApparentColor
    self.initiallyAcceptedRed = initiallyAcceptedRed
    self.initiallyAcceptedBlackAppearance = initiallyAcceptedBlackAppearance
    self.initiallyAcceptedBlackTarry = initiallyAcceptedBlackTarry
    self.personConfirmedRetakeReason = personConfirmedRetakeReason
    self.personConfirmedStoolPresence = personConfirmedStoolPresence
    self.personConfirmedBristolType = personConfirmedBristolType
    self.personConfirmedForm = personConfirmedForm
    self.personConfirmedMixedForm = personConfirmedMixedForm
    self.personConfirmedApparentColor = personConfirmedApparentColor
    self.personConfirmedRed = personConfirmedRed
    self.personConfirmedBlackAppearance = personConfirmedBlackAppearance
    self.personConfirmedBlackTarry = personConfirmedBlackTarry
    self.personConfirmedSubject = personConfirmedSubject
    self.fieldProvenance = Dictionary(
      uniqueKeysWithValues: fieldProvenance.map { ($0.key.rawValue, $0.value) }
    )
  }

  public var typedFieldProvenance: [ConfirmationField: FieldConfirmationProvenance] {
    Dictionary(uniqueKeysWithValues: fieldProvenance.compactMap { key, value in
      ConfirmationField(rawValue: key).map { ($0, value) }
    })
  }

  public func validate(hasPhoto: Bool, hasModelSuggestion: Bool) throws {
    guard schemaVersion == Self.schemaVersion,
      confirmedAt.timeIntervalSinceReferenceDate.isFinite
    else { throw ObservationParserError.invalidValue("confirmation_schema") }
    if let type = personConfirmedBristolType, !(1...7).contains(type) {
      throw ObservationParserError.invalidValue("person_confirmed_bristol_type")
    }
    if let form = personConfirmedForm, !ObservationParser.forms.contains(form) {
      throw ObservationParserError.invalidValue("person_confirmed_form")
    }
    if let color = personConfirmedApparentColor,
      !ObservationParser.colors.contains(color)
    {
      throw ObservationParserError.invalidValue("person_confirmed_apparent_color")
    }
    if initiallyAcceptedRetakeReason == .notTargetImage {
      throw ObservationParserError.invalidValue("initially_accepted_retake_reason")
    }
    if initiallyAcceptedPhotoUsable == true,
      initiallyAcceptedRetakeReason != nil
    {
      throw ObservationParserError.inconsistent(
        "An initially accepted usable photo requires no retake reason."
      )
    }
    if initiallyAcceptedPhotoUsable == false,
      (initiallyAcceptedRetakeReason == nil
        || initiallyAcceptedRetakeReason == .notTargetImage)
    {
      throw ObservationParserError.inconsistent(
        "An initially accepted unusable photo requires a technical retake reason."
      )
    }
    if let type = initiallyAcceptedBristolType, !(1...7).contains(type) {
      throw ObservationParserError.invalidValue(
        "initially_accepted_bristol_type"
      )
    }
    if let form = initiallyAcceptedForm,
      !ObservationParser.forms.contains(form)
    {
      throw ObservationParserError.invalidValue("initially_accepted_form")
    }
    if let color = initiallyAcceptedApparentColor,
      !ObservationParser.colors.contains(color)
    {
      throw ObservationParserError.invalidValue(
        "initially_accepted_apparent_color"
      )
    }
    let provenanceKeys = Set(fieldProvenance.keys)
    // Explicit historical keysets are intentional. Adding a new
    // ConfirmationField must never make a valid saved V1 envelope fail merely
    // because `allCases` grew.
    let currentV2Keys = Set(ConfirmationField.allCases.map(\.rawValue))
    let currentV1Keys = currentV2Keys.subtracting([
      ConfirmationField.blackAppearance.rawValue,
    ])
    let fullPrefillV2Keys = currentV2Keys.subtracting([
      ConfirmationField.retakeReason.rawValue,
    ])
    let fullPrefillV1Keys = currentV1Keys.subtracting([
      ConfirmationField.retakeReason.rawValue,
    ])
    let legacyKeys = fullPrefillV1Keys.subtracting([
      ConfirmationField.stoolPresence.rawValue,
      ConfirmationField.form.rawValue,
    ])
    guard provenanceKeys == currentV2Keys
      || provenanceKeys == fullPrefillV2Keys
      || provenanceKeys == currentV1Keys
      || provenanceKeys == fullPrefillV1Keys
      || provenanceKeys == legacyKeys
    else {
      throw ObservationParserError.inconsistent("Confirmation provenance must cover every suggested field.")
    }
    if personConfirmedStoolPresence != nil || personConfirmedForm != nil {
      guard provenanceKeys == currentV2Keys
        || provenanceKeys == fullPrefillV2Keys
        || provenanceKeys == currentV1Keys
        || provenanceKeys == fullPrefillV1Keys
      else {
        throw ObservationParserError.inconsistent(
          "A full-prefill confirmation requires subject and form provenance."
        )
      }
      try Self.validateFullPrefillTuple(
        photoUsable: personConfirmedPhotoUsable,
        retakeReason: personConfirmedRetakeReason,
        stoolPresence: personConfirmedStoolPresence,
        bristolType: personConfirmedBristolType,
        form: personConfirmedForm,
        mixedForm: personConfirmedMixedForm,
        apparentColor: personConfirmedApparentColor,
        red: personConfirmedRed,
        blackAppearance: personConfirmedBlackAppearance,
        blackTarry: personConfirmedBlackTarry,
        requiresSeparateBlackAppearance: provenanceKeys.contains(
          ConfirmationField.blackAppearance.rawValue
        ),
        label: "final",
        allowsNoPhotoManualEntry: !hasPhoto && !hasModelSuggestion
      )
    }
    if initiallyAcceptedStoolPresence != nil
      || initiallyAcceptedForm != nil
    {
      try Self.validateFullPrefillTuple(
        photoUsable: initiallyAcceptedPhotoUsable,
        retakeReason: initiallyAcceptedRetakeReason,
        stoolPresence: initiallyAcceptedStoolPresence,
        bristolType: initiallyAcceptedBristolType,
        form: initiallyAcceptedForm,
        mixedForm: initiallyAcceptedMixedForm,
        apparentColor: initiallyAcceptedApparentColor,
        red: initiallyAcceptedRed,
        blackAppearance: initiallyAcceptedBlackAppearance,
        blackTarry: initiallyAcceptedBlackTarry,
        requiresSeparateBlackAppearance: provenanceKeys.contains(
          ConfirmationField.blackAppearance.rawValue
        ),
        label: "initially accepted",
        allowsNoPhotoManualEntry: false
      )
    }
    guard hasPhoto == (personConfirmedPhotoUsable != nil) else {
      throw ObservationParserError.inconsistent("Photo usability must match photo attachment state.")
    }
    if personConfirmedPhotoUsable == true {
      guard personConfirmedRetakeReason == nil else {
        throw ObservationParserError.inconsistent(
          "A usable confirmed photo requires no retake reason."
        )
      }
    } else if personConfirmedPhotoUsable == false,
      provenanceKeys.contains(ConfirmationField.retakeReason.rawValue)
    {
      guard personConfirmedRetakeReason != nil,
        personConfirmedRetakeReason != .notTargetImage
      else {
        throw ObservationParserError.inconsistent(
          "An unusable confirmed photo requires a technical retake reason."
        )
      }
    }
    if personConfirmedPhotoUsable == false {
      guard personConfirmedApparentColor == nil
        || personConfirmedApparentColor == "unable_to_assess"
      else {
        throw ObservationParserError.inconsistent(
          "An absent or unusable photo cannot retain a confirmed apparent color."
        )
      }
    }
    let values = Array(fieldProvenance.values)
    if hasModelSuggestion {
      guard !values.contains(.manualNoSuggestion) else {
        throw ObservationParserError.inconsistent("A model-backed confirmation cannot use manualNoSuggestion provenance.")
      }
    } else {
      guard values.allSatisfy({
        $0 == .manualNoSuggestion || $0 == .editedAfterConfirmation
      }) else {
        throw ObservationParserError.inconsistent("A manual confirmation requires manual provenance.")
      }
    }
  }

  public var canonicalJSON: String? {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
  }

  public func visualObservation(
    original: VisualObservation?,
    hasPhoto: Bool
  ) -> VisualObservation? {
    guard hasPhoto, let usable = personConfirmedPhotoUsable else { return nil }
    guard usable else {
      return VisualObservation(
        imageUsable: false,
        qualityIssue: original?.qualityIssue == "none" ? "other" : (original?.qualityIssue ?? "other"),
        apparentBristolType: nil,
        apparentColor: "unable_to_assess",
        form: "unable_to_assess",
        redAppearingMaterial: "unable_to_assess",
        blackTarryAppearance: "unable_to_assess"
      )
    }
    let form: String
    if let personConfirmedForm {
      form = personConfirmedForm
    } else if let type = personConfirmedBristolType,
      let expected = BristolFormContract.expectedForm(for: type)
    {
      form = expected
    } else if personConfirmedMixedForm == .yes {
      form = "mixed"
    } else {
      form = "unable_to_assess"
    }
    let usesFullPrefillReview = personConfirmedStoolPresence != nil
      && personConfirmedForm != nil
    return VisualObservation(
      imageUsable: true,
      qualityIssue: "none",
      apparentBristolType: personConfirmedBristolType,
      apparentColor: personConfirmedApparentColor ?? "unable_to_assess",
      form: form,
      // New full-prefill records preserve the model payload in originalAIJSON
      // and store the accepted or edited appearance values here. Historical
      // subject-first records retain their independent-answer semantics.
      redAppearingMaterial: usesFullPrefillReview
        ? Self.materialState(from: personConfirmedRed)
        : "unable_to_assess",
      blackTarryAppearance: usesFullPrefillReview
        ? Self.materialState(from: personConfirmedBlackTarry)
        : "unable_to_assess"
    )
  }

  private static func materialState(from answer: SymptomFlag?) -> String {
    switch answer {
    case .yes: return "apparent"
    case .no: return "not_observed"
    case .unsure, nil: return "unable_to_assess"
    }
  }

  private static func validateFullPrefillTuple(
    photoUsable: Bool?,
    retakeReason: PhotoRetakeReason?,
    stoolPresence: StoolPresence?,
    bristolType: Int?,
    form: String?,
    mixedForm: ClinicalTriState?,
    apparentColor: String?,
    red: SymptomFlag?,
    blackAppearance: SymptomFlag?,
    blackTarry: SymptomFlag?,
    requiresSeparateBlackAppearance: Bool,
    label: String,
    allowsNoPhotoManualEntry: Bool
  ) throws {
    guard let stoolPresence, let form, let mixedForm,
      let red, let blackTarry,
      !requiresSeparateBlackAppearance || blackAppearance != nil
    else {
      throw ObservationParserError.inconsistent(
        "The \(label) full-prefill tuple is incomplete."
      )
    }
    if let photoUsable {
      guard photoUsable ? retakeReason == nil
        : (retakeReason != nil && retakeReason != .notTargetImage)
      else {
        throw ObservationParserError.inconsistent(
          "The \(label) photo usability and retake reason disagree."
        )
      }
    } else {
      guard allowsNoPhotoManualEntry, retakeReason == nil else {
        throw ObservationParserError.inconsistent(
          "The \(label) no-photo entry cannot carry photo usability or a retake reason."
        )
      }
    }
    if photoUsable == false {
      guard bristolType == nil,
        form == "unable_to_assess",
        mixedForm == .unsure,
        apparentColor == nil || apparentColor == "unable_to_assess",
        red == .unsure,
        (!requiresSeparateBlackAppearance || blackAppearance == .unsure),
        blackTarry == .unsure
      else {
        throw ObservationParserError.inconsistent(
          "The \(label) dependent fields must abstain."
        )
      }
      return
    }
    if stoolPresence != .stool {
      guard bristolType == nil,
        form == "unable_to_assess",
        mixedForm == .unsure
      else {
        throw ObservationParserError.inconsistent(
          "The \(label) non-stool morphology fields must abstain."
        )
      }
      // Historical V1 combined the black concepts and required every visual
      // dependent to abstain for non-stool/uncertain subjects. Additive V2
      // keeps color, red, unusual-black, and tar-like appearance independently
      // observable when the image itself is usable.
      if !requiresSeparateBlackAppearance {
        guard apparentColor == nil || apparentColor == "unable_to_assess",
          red == .unsure,
          blackTarry == .unsure
        else {
          throw ObservationParserError.inconsistent(
            "The \(label) historical non-stool visual fields must abstain."
          )
        }
      }
      return
    }
    switch mixedForm {
    case .no:
      guard let bristolType,
        BristolFormContract.expectedForm(for: bristolType) == form
      else {
        throw ObservationParserError.inconsistent(
          "The \(label) Bristol type and form disagree."
        )
      }
    case .yes:
      guard bristolType == nil, form == "mixed" else {
        throw ObservationParserError.inconsistent(
          "The \(label) mixed form is inconsistent."
        )
      }
    case .unsure:
      guard bristolType == nil, form == "unable_to_assess" else {
        throw ObservationParserError.inconsistent(
          "The \(label) uncertain form is inconsistent."
        )
      }
    }
  }

  public static func decode(_ raw: String) throws -> ConfirmedEntrySnapshotV1 {
    guard let data = raw.data(using: .utf8) else { throw ObservationParserError.invalidJSON }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do { return try decoder.decode(Self.self, from: data) }
    catch { throw ObservationParserError.invalidJSON }
  }

}

public enum StoredReviewedEntry: Equatable, Sendable {
  case legacyObservation(VisualObservation)
  case confirmedV1(ConfirmedEntrySnapshotV1)

  public static func parse(_ raw: String) throws -> StoredReviewedEntry {
    if raw.contains("\"schemaVersion\":\"\(ConfirmedEntrySnapshotV1.schemaVersion)\"")
      || raw.contains("\"schema_version\":\"\(ConfirmedEntrySnapshotV1.schemaVersion)\"")
    {
      return .confirmedV1(try ConfirmedEntrySnapshotV1.decode(raw))
    }
    return .legacyObservation(try ObservationParser.parse(raw))
  }
}
