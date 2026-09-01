import CryptoKit
import Foundation

public enum StoolPresence: String, Codable, CaseIterable, Sendable {
  case stool
  case nonStool = "non_stool"
  case uncertain
}

public enum PhotoSuggestionAnswer: String, Codable, CaseIterable, Sendable {
  case yes
  case no
  case notSure = "not_sure"
}

public enum PhotoRetakeReason: String, Codable, CaseIterable, Sendable {
  case tooDark = "too_dark"
  case blurred
  case obstructed
  case tooFar = "too_far"
  case glare
  case notTargetImage = "not_target_image"
  case other

  public var displayName: String {
    switch self {
    case .tooDark: return "Too dark"
    case .blurred: return "Blurred"
    case .obstructed: return "Obstructed"
    case .tooFar: return "Too far away"
    case .glare: return "Glare"
    case .notTargetImage: return "Different subject"
    case .other: return "Other technical issue"
    }
  }
}

/// The strict output contract for the separately qualified raw-image route.
/// This type is intentionally independent from the legacy seven-key bridge
/// schema so old evidence and saved entries are never silently relabeled.
public struct PhotoSuggestionV1: Codable, Equatable, Sendable {
  public static let schemaVersion = "gi-photo-v1"

  public let schemaVersion: String
  public let imageUsable: Bool
  public let retakeReason: PhotoRetakeReason?
  public let stoolPresence: StoolPresence
  public let bristolType: Int?
  public let mixedForm: PhotoSuggestionAnswer
  public let apparentColor: String?
  public let redAppearingMaterial: PhotoSuggestionAnswer
  public let blackTarryAppearance: PhotoSuggestionAnswer

  public init(
    schemaVersion: String = Self.schemaVersion,
    imageUsable: Bool,
    retakeReason: PhotoRetakeReason?,
    stoolPresence: StoolPresence,
    bristolType: Int?,
    mixedForm: PhotoSuggestionAnswer,
    apparentColor: String?,
    redAppearingMaterial: PhotoSuggestionAnswer,
    blackTarryAppearance: PhotoSuggestionAnswer
  ) {
    self.schemaVersion = schemaVersion
    self.imageUsable = imageUsable
    self.retakeReason = retakeReason
    self.stoolPresence = stoolPresence
    self.bristolType = bristolType
    self.mixedForm = mixedForm
    self.apparentColor = apparentColor
    self.redAppearingMaterial = redAppearingMaterial
    self.blackTarryAppearance = blackTarryAppearance
  }

  /// Canonical no-model result for a deterministic technical-quality stop.
  /// This preserves the same nine-key contract while making no statement
  /// about stool, red material, black material, blood, tar, or diagnosis.
  public static func technicalAbstention(
    reason: PhotoRetakeReason
  ) -> PhotoSuggestionV1 {
    PhotoSuggestionV1(
      imageUsable: false,
      retakeReason: reason,
      stoolPresence: .uncertain,
      bristolType: nil,
      mixedForm: .notSure,
      apparentColor: nil,
      redAppearingMaterial: .notSure,
      blackTarryAppearance: .notSure
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(imageUsable, forKey: .imageUsable)
    if let retakeReason { try container.encode(retakeReason, forKey: .retakeReason) }
    else { try container.encodeNil(forKey: .retakeReason) }
    try container.encode(stoolPresence, forKey: .stoolPresence)
    if let bristolType { try container.encode(bristolType, forKey: .bristolType) }
    else { try container.encodeNil(forKey: .bristolType) }
    try container.encode(mixedForm, forKey: .mixedForm)
    if let apparentColor { try container.encode(apparentColor, forKey: .apparentColor) }
    else { try container.encodeNil(forKey: .apparentColor) }
    try container.encode(redAppearingMaterial, forKey: .redAppearingMaterial)
    try container.encode(blackTarryAppearance, forKey: .blackTarryAppearance)
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case imageUsable = "image_usable"
    case retakeReason = "retake_reason"
    case stoolPresence = "stool_presence"
    case bristolType = "bristol_type"
    case mixedForm = "mixed_form"
    case apparentColor = "apparent_color"
    case redAppearingMaterial = "red_appearing_material"
    case blackTarryAppearance = "black_tarry_appearance"
  }
}

public enum PhotoSuggestionV1Parser {
  public static let expectedKeys: Set<String> = [
    "schema_version", "image_usable", "retake_reason", "stool_presence",
    "bristol_type", "mixed_form", "apparent_color",
    "red_appearing_material", "black_tarry_appearance",
  ]

  public static let colors: Set<String> = [
    "brown", "light_brown", "dark_brown", "green", "yellow", "orange",
    "red_appearing", "black_appearing", "pale_or_clay_appearing", "mixed",
  ]

  public static func parse(_ raw: String) throws -> PhotoSuggestionV1 {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard JSONTopLevelKeyScanner.hasUniqueKeys(in: text),
      let data = text.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else { throw ObservationParserError.invalidJSON }

    let keys = Set(dictionary.keys)
    let unknown = keys.subtracting(expectedKeys)
    if !unknown.isEmpty { throw ObservationParserError.unknownKeys(Array(unknown)) }
    let missing = expectedKeys.subtracting(keys)
    if !missing.isEmpty { throw ObservationParserError.missingKeys(Array(missing)) }

    let suggestion: PhotoSuggestionV1
    do { suggestion = try JSONDecoder().decode(PhotoSuggestionV1.self, from: data) }
    catch { throw ObservationParserError.invalidJSON }
    try validate(suggestion)
    return suggestion
  }

  /// Current raw-photo generation uses stool_presence for subject identity and
  /// reserves retake_reason for technical capture problems. Keep the broader
  /// decoder above for already-saved V1 JSON so an app update never makes an
  /// older entry unreadable.
  public static func parseCurrentRawOutput(_ raw: String) throws -> PhotoSuggestionV1 {
    let suggestion = try parse(raw)
    guard suggestion.retakeReason != .notTargetImage else {
      throw ObservationParserError.invalidValue("retake_reason")
    }
    return suggestion
  }

  /// The bounded V1 candidate uses the complete appearance-only tri-state:
  /// yes, no, or not sure. Technical/unusable outputs must still fully
  /// abstain under `validate(_:)`.
  public static func parseConstrainedCandidateOutput(
    _ raw: String
  ) throws -> PhotoSuggestionV1 {
    let suggestion = try parseCurrentRawOutput(raw)
    try validateConstrainedCandidate(suggestion)
    return suggestion
  }

  public static func validateConstrainedCandidate(
    _ suggestion: PhotoSuggestionV1
  ) throws {
    try validate(suggestion)
    guard suggestion.retakeReason != .notTargetImage else {
      throw ObservationParserError.invalidValue("retake_reason")
    }
  }

  public static func canonicalJSON(_ suggestion: PhotoSuggestionV1) throws -> String {
    try validate(suggestion)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let value = String(data: try encoder.encode(suggestion), encoding: .utf8) else {
      throw ObservationParserError.invalidJSON
    }
    return value
  }

  public static func validate(_ suggestion: PhotoSuggestionV1) throws {
    guard suggestion.schemaVersion == PhotoSuggestionV1.schemaVersion else {
      throw ObservationParserError.invalidValue("schema_version")
    }
    if let type = suggestion.bristolType, !(1...7).contains(type) {
      throw ObservationParserError.invalidValue("bristol_type")
    }
    if let color = suggestion.apparentColor, !colors.contains(color) {
      throw ObservationParserError.invalidValue("apparent_color")
    }

    if suggestion.imageUsable {
      guard suggestion.retakeReason == nil else {
        throw ObservationParserError.inconsistent("A usable image requires a null retake_reason.")
      }
    } else {
      guard suggestion.retakeReason != nil else {
        throw ObservationParserError.inconsistent("An unusable image requires a retake_reason.")
      }
      guard suggestion.stoolPresence == .uncertain else {
        throw ObservationParserError.inconsistent(
          "An unusable image requires uncertain stool_presence."
        )
      }
      try requireAbstention(suggestion, reason: "An unusable image")
      return
    }

    guard suggestion.stoolPresence == .stool else {
      try requireAbstention(suggestion, reason: "A non-stool or uncertain image")
      return
    }

    // A mixed/uncertain morphology must not be coerced to one nearest type,
    // while a confident non-mixed suggestion must name the supported type.
    switch suggestion.mixedForm {
    case .no:
      guard suggestion.bristolType != nil else {
        throw ObservationParserError.inconsistent(
          "A non-mixed form requires a Bristol type."
        )
      }
    case .yes, .notSure:
      guard suggestion.bristolType == nil else {
        throw ObservationParserError.inconsistent(
          "A mixed or uncertain form requires a null Bristol type."
        )
      }
    }
  }

  private static func requireAbstention(
    _ suggestion: PhotoSuggestionV1,
    reason: String
  ) throws {
    guard suggestion.bristolType == nil,
      suggestion.mixedForm == .notSure,
      suggestion.apparentColor == nil,
      suggestion.redAppearingMaterial == .notSure,
      suggestion.blackTarryAppearance == .notSure
    else {
      throw ObservationParserError.inconsistent(
        "\(reason) requires null Bristol/color and not_sure mixed/red/black suggestions."
      )
    }
  }

}

/// The shipping-candidate review contract. It is separate from the historical
/// nine-key `gi-photo-v1` payload so already-saved suggestions remain readable
/// after adding an explicit, model-produced form value.
public struct FullPrefillPhotoSuggestionV1: Codable, Equatable, Sendable {
  public static let schemaVersion = "gi-photo-full-prefill-v1"

  public let schemaVersion: String
  public let imageUsable: Bool
  public let retakeReason: PhotoRetakeReason?
  public let stoolPresence: StoolPresence
  public let bristolType: Int?
  public let form: String
  public let mixedForm: PhotoSuggestionAnswer
  public let apparentColor: String?
  public let redAppearingMaterial: PhotoSuggestionAnswer
  public let blackTarryAppearance: PhotoSuggestionAnswer

  public init(
    schemaVersion: String = Self.schemaVersion,
    imageUsable: Bool,
    retakeReason: PhotoRetakeReason?,
    stoolPresence: StoolPresence,
    bristolType: Int?,
    form: String,
    mixedForm: PhotoSuggestionAnswer,
    apparentColor: String?,
    redAppearingMaterial: PhotoSuggestionAnswer,
    blackTarryAppearance: PhotoSuggestionAnswer
  ) {
    self.schemaVersion = schemaVersion
    self.imageUsable = imageUsable
    self.retakeReason = retakeReason
    self.stoolPresence = stoolPresence
    self.bristolType = bristolType
    self.form = form
    self.mixedForm = mixedForm
    self.apparentColor = apparentColor
    self.redAppearingMaterial = redAppearingMaterial
    self.blackTarryAppearance = blackTarryAppearance
  }

  public static func technicalAbstention(
    reason: PhotoRetakeReason
  ) -> FullPrefillPhotoSuggestionV1 {
    FullPrefillPhotoSuggestionV1(
      imageUsable: false,
      retakeReason: reason,
      stoolPresence: .uncertain,
      bristolType: nil,
      form: "unable_to_assess",
      mixedForm: .notSure,
      apparentColor: nil,
      redAppearingMaterial: .notSure,
      blackTarryAppearance: .notSure
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(imageUsable, forKey: .imageUsable)
    if let retakeReason { try container.encode(retakeReason, forKey: .retakeReason) }
    else { try container.encodeNil(forKey: .retakeReason) }
    try container.encode(stoolPresence, forKey: .stoolPresence)
    if let bristolType { try container.encode(bristolType, forKey: .bristolType) }
    else { try container.encodeNil(forKey: .bristolType) }
    try container.encode(form, forKey: .form)
    try container.encode(mixedForm, forKey: .mixedForm)
    if let apparentColor { try container.encode(apparentColor, forKey: .apparentColor) }
    else { try container.encodeNil(forKey: .apparentColor) }
    try container.encode(redAppearingMaterial, forKey: .redAppearingMaterial)
    try container.encode(blackTarryAppearance, forKey: .blackTarryAppearance)
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case imageUsable = "image_usable"
    case retakeReason = "retake_reason"
    case stoolPresence = "stool_presence"
    case bristolType = "bristol_type"
    case form
    case mixedForm = "mixed_form"
    case apparentColor = "apparent_color"
    case redAppearingMaterial = "red_appearing_material"
    case blackTarryAppearance = "black_tarry_appearance"
  }
}

public enum FullPrefillPhotoSuggestionV1Parser {
  public static let expectedKeys: Set<String> = [
    "schema_version", "image_usable", "retake_reason", "stool_presence",
    "bristol_type", "form", "mixed_form", "apparent_color",
    "red_appearing_material", "black_tarry_appearance",
  ]

  public static func parse(_ raw: String) throws -> FullPrefillPhotoSuggestionV1 {
    let suggestion = try decodeStructurally(raw)
    try validate(suggestion)
    return suggestion
  }

  /// Decodes the exact ten-key primitive contract without applying any
  /// cross-field closure. The dependent-field normalizer calls this first so
  /// missing/unknown/duplicate keys, invalid primitive types, invalid enums,
  /// ranges, and schema versions always fail rather than being repaired.
  fileprivate static func decodeStructurally(
    _ raw: String
  ) throws -> FullPrefillPhotoSuggestionV1 {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard JSONTopLevelKeyScanner.hasUniqueKeys(in: text),
      let data = text.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else { throw ObservationParserError.invalidJSON }

    let keys = Set(dictionary.keys)
    let unknown = keys.subtracting(expectedKeys)
    if !unknown.isEmpty { throw ObservationParserError.unknownKeys(Array(unknown)) }
    let missing = expectedKeys.subtracting(keys)
    if !missing.isEmpty { throw ObservationParserError.missingKeys(Array(missing)) }

    let suggestion: FullPrefillPhotoSuggestionV1
    do { suggestion = try JSONDecoder().decode(SelfDecodingBox.self, from: data).value }
    catch { throw ObservationParserError.invalidJSON }
    try validatePrimitiveContract(suggestion)
    return suggestion
  }

  public static func canonicalJSON(_ suggestion: FullPrefillPhotoSuggestionV1) throws -> String {
    try validate(suggestion)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let value = String(data: try encoder.encode(suggestion), encoding: .utf8) else {
      throw ObservationParserError.invalidJSON
    }
    return value
  }

  public static func validate(_ suggestion: FullPrefillPhotoSuggestionV1) throws {
    try validatePrimitiveContract(suggestion)

    if suggestion.imageUsable {
      guard suggestion.retakeReason == nil else {
        throw ObservationParserError.inconsistent(
          "A usable image requires a null retake_reason."
        )
      }
    } else {
      guard suggestion.retakeReason != nil,
        suggestion.stoolPresence == .uncertain
      else {
        throw ObservationParserError.inconsistent(
          "An unusable image requires a technical reason and uncertain subject."
        )
      }
      try requireAbstention(suggestion, reason: "An unusable image")
      return
    }

    guard suggestion.stoolPresence == .stool else {
      try requireAbstention(suggestion, reason: "A non-stool or uncertain image")
      return
    }

    switch suggestion.mixedForm {
    case .no:
      guard let type = suggestion.bristolType,
        BristolFormContract.expectedForm(for: type) == suggestion.form
      else {
        throw ObservationParserError.inconsistent(
          "A single-form suggestion requires matching Bristol and form values."
        )
      }
    case .yes:
      guard suggestion.bristolType == nil, suggestion.form == "mixed" else {
        throw ObservationParserError.inconsistent(
          "A mixed suggestion requires null Bristol and form mixed."
        )
      }
    case .notSure:
      guard suggestion.bristolType == nil,
        suggestion.form == "unable_to_assess"
      else {
        throw ObservationParserError.inconsistent(
          "An uncertain form requires null Bristol and unable_to_assess form."
        )
      }
    }
  }

  private static func validatePrimitiveContract(
    _ suggestion: FullPrefillPhotoSuggestionV1
  ) throws {
    guard suggestion.schemaVersion == FullPrefillPhotoSuggestionV1.schemaVersion else {
      throw ObservationParserError.invalidValue("schema_version")
    }
    if let type = suggestion.bristolType, !(1...7).contains(type) {
      throw ObservationParserError.invalidValue("bristol_type")
    }
    guard ObservationParser.forms.contains(suggestion.form) else {
      throw ObservationParserError.invalidValue("form")
    }
    if let color = suggestion.apparentColor,
      !PhotoSuggestionV1Parser.colors.contains(color)
    {
      throw ObservationParserError.invalidValue("apparent_color")
    }
    guard suggestion.retakeReason != .notTargetImage else {
      throw ObservationParserError.invalidValue("retake_reason")
    }
  }

  private static func requireAbstention(
    _ suggestion: FullPrefillPhotoSuggestionV1,
    reason: String
  ) throws {
    guard suggestion.bristolType == nil,
      suggestion.form == "unable_to_assess",
      suggestion.mixedForm == .notSure,
      suggestion.apparentColor == nil,
      suggestion.redAppearingMaterial == .notSure,
      suggestion.blackTarryAppearance == .notSure
    else {
      throw ObservationParserError.inconsistent(
        "\(reason) requires null Bristol/color and not-sure appearance values."
      )
    }
  }

  /// A named box avoids depending on synthesized decoding at the parse site
  /// while retaining the struct's explicit null-preserving encoder.
  private struct SelfDecodingBox: Decodable {
    let value: FullPrefillPhotoSuggestionV1

    init(from decoder: Decoder) throws {
      let values = try decoder.container(
        keyedBy: FullPrefillPhotoSuggestionV1.CodingKeys.self
      )
      value = FullPrefillPhotoSuggestionV1(
        schemaVersion: try values.decode(
          String.self,
          forKey: .schemaVersion
        ),
        imageUsable: try values.decode(Bool.self, forKey: .imageUsable),
        retakeReason: try values.decodeIfPresent(
          PhotoRetakeReason.self,
          forKey: .retakeReason
        ),
        stoolPresence: try values.decode(
          StoolPresence.self,
          forKey: .stoolPresence
        ),
        bristolType: try values.decodeIfPresent(Int.self, forKey: .bristolType),
        form: try values.decode(String.self, forKey: .form),
        mixedForm: try values.decode(
          PhotoSuggestionAnswer.self,
          forKey: .mixedForm
        ),
        apparentColor: try values.decodeIfPresent(
          String.self,
          forKey: .apparentColor
        ),
        redAppearingMaterial: try values.decode(
          PhotoSuggestionAnswer.self,
          forKey: .redAppearingMaterial
        ),
        blackTarryAppearance: try values.decode(
          PhotoSuggestionAnswer.self,
          forKey: .blackTarryAppearance
        )
      )
    }
  }
}

/// The only authorized semantics-preserving correction for the full-prefill
/// route. It never changes the three controlling fields and can only replace
/// dependent stool-detail values with conservative abstentions.
public enum FullPrefillDependentFieldAbstentionV1 {
  public static let policyVersion = "gi-photo-dependent-field-abstention-v1"
  public static let dependentFieldOrder = [
    "bristol_type", "form", "mixed_form", "apparent_color",
    "red_appearing_material", "black_tarry_appearance",
  ]

  public struct Result: Equatable, Sendable {
    public let rawResponse: String
    public let rawResponseSHA256: String
    public let normalizedSuggestion: FullPrefillPhotoSuggestionV1
    public let normalizedCanonicalJSON: String
    public let normalizedCanonicalSHA256: String
    public let rawCrossFieldContradiction: Bool
    public let normalizationOccurred: Bool
    public let normalizedFields: [String]
    public let normalizationPolicyVersion: String
  }

  public static func parseAndNormalize(_ raw: String) throws -> Result {
    let decoded = try FullPrefillPhotoSuggestionV1Parser.decodeStructurally(raw)
    let rawCrossFieldContradiction = try hasRawCrossFieldContradiction(decoded)

    let shouldAbstain: Bool
    if decoded.imageUsable {
      guard decoded.retakeReason == nil else {
        throw ObservationParserError.inconsistent(
          "A usable image requires a null retake_reason."
        )
      }
      shouldAbstain = decoded.stoolPresence != .stool
    } else {
      guard decoded.retakeReason != nil,
        decoded.stoolPresence == .uncertain
      else {
        throw ObservationParserError.inconsistent(
          "An unusable image requires a technical reason and uncertain subject."
        )
      }
      shouldAbstain = true
    }

    let normalized: FullPrefillPhotoSuggestionV1
    if shouldAbstain {
      normalized = FullPrefillPhotoSuggestionV1(
        imageUsable: decoded.imageUsable,
        retakeReason: decoded.retakeReason,
        stoolPresence: decoded.stoolPresence,
        bristolType: nil,
        form: "unable_to_assess",
        mixedForm: .notSure,
        apparentColor: nil,
        redAppearingMaterial: .notSure,
        blackTarryAppearance: .notSure
      )
    } else {
      // A usable stool result receives no normalization. Its entire semantic
      // contract remains subject to the ordinary hard validation below.
      normalized = decoded
    }
    try FullPrefillPhotoSuggestionV1Parser.validate(normalized)

    let normalizedFields = shouldAbstain
      ? changedDependentFields(from: decoded, to: normalized)
      : []
    let canonical = try FullPrefillPhotoSuggestionV1Parser.canonicalJSON(
      normalized
    )
    return Result(
      rawResponse: raw,
      rawResponseSHA256: sha256(raw),
      normalizedSuggestion: normalized,
      normalizedCanonicalJSON: canonical,
      normalizedCanonicalSHA256: sha256(canonical),
      rawCrossFieldContradiction: rawCrossFieldContradiction,
      normalizationOccurred: !normalizedFields.isEmpty,
      normalizedFields: normalizedFields,
      normalizationPolicyVersion: policyVersion
    )
  }

  public static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  /// Reports primitive-valid raw cross-field inconsistency independently from
  /// whether the abstention policy ultimately changes any dependent field.
  public static func rawCrossFieldContradiction(in raw: String) throws -> Bool {
    try hasRawCrossFieldContradiction(
      FullPrefillPhotoSuggestionV1Parser.decodeStructurally(raw)
    )
  }

  private static func hasRawCrossFieldContradiction(
    _ suggestion: FullPrefillPhotoSuggestionV1
  ) throws -> Bool {
    do {
      try FullPrefillPhotoSuggestionV1Parser.validate(suggestion)
      return false
    } catch ObservationParserError.inconsistent(_) {
      return true
    }
  }

  private static func changedDependentFields(
    from original: FullPrefillPhotoSuggestionV1,
    to normalized: FullPrefillPhotoSuggestionV1
  ) -> [String] {
    let changed: [String: Bool] = [
      "bristol_type": original.bristolType != normalized.bristolType,
      "form": original.form != normalized.form,
      "mixed_form": original.mixedForm != normalized.mixedForm,
      "apparent_color": original.apparentColor != normalized.apparentColor,
      "red_appearing_material":
        original.redAppearingMaterial != normalized.redAppearingMaterial,
      "black_tarry_appearance":
        original.blackTarryAppearance != normalized.blackTarryAppearance,
    ]
    return dependentFieldOrder.filter { changed[$0] == true }
  }
}

/// Additive receipt stored with existing draft/model provenance. It binds the
/// byte-exact raw response to the canonical normalized suggestion without
/// adding a persistence-model column or relabeling the original output.
public struct FullPrefillNormalizationReceiptV1: Codable, Equatable, Sendable {
  public let normalizationPolicyVersion: String
  public let rawResponseSHA256: String
  public let normalizedCanonicalSHA256: String
  public let normalizationOccurred: Bool
  public let normalizedFields: [String]
  public let normalizedSuggestionJSON: String

  public init(result: FullPrefillDependentFieldAbstentionV1.Result) {
    normalizationPolicyVersion = result.normalizationPolicyVersion
    rawResponseSHA256 = result.rawResponseSHA256
    normalizedCanonicalSHA256 = result.normalizedCanonicalSHA256
    normalizationOccurred = result.normalizationOccurred
    normalizedFields = result.normalizedFields
    normalizedSuggestionJSON = result.normalizedCanonicalJSON
  }

  @discardableResult
  public func validate(
    rawResponse: String
  ) throws -> FullPrefillPhotoSuggestionV1 {
    let recomputed = try FullPrefillDependentFieldAbstentionV1
      .parseAndNormalize(rawResponse)
    guard normalizationPolicyVersion == recomputed.normalizationPolicyVersion,
      rawResponseSHA256 == recomputed.rawResponseSHA256,
      normalizedCanonicalSHA256 == recomputed.normalizedCanonicalSHA256,
      normalizationOccurred == recomputed.normalizationOccurred,
      normalizedFields == recomputed.normalizedFields,
      normalizedSuggestionJSON == recomputed.normalizedCanonicalJSON
    else { throw ObservationParserError.invalidValue("normalization_receipt") }
    return recomputed.normalizedSuggestion
  }
}

/// A same-conversation repair may fix serialization only. Every recognizable
/// semantic value must remain identical. A missing, null, wrongly typed, or
/// invalid semantic field may become only its conservative abstention value.
public enum PhotoSuggestionV1RepairPolicy {
  public static func validate(
    originalRaw: String,
    repaired: PhotoSuggestionV1
  ) throws {
    guard let object = singleJSONObject(in: originalRaw),
      JSONTopLevelKeyScanner.hasUniqueKeys(in: object),
      let data = object.data(using: .utf8),
      let original = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw ObservationParserError.inconsistent(
        "A response without exactly one JSON object cannot receive a semantics-changing repair."
      )
    }

    try requireSameAnswer(
      original["mixed_form"], repaired: repaired.mixedForm, field: "mixed_form"
    )
    try requireSameAnswer(
      original["red_appearing_material"],
      repaired: repaired.redAppearingMaterial,
      field: "red_appearing_material"
    )
    try requireSameAnswer(
      original["black_tarry_appearance"],
      repaired: repaired.blackTarryAppearance,
      field: "black_tarry_appearance"
    )

    let originalType = integralNumber(original["bristol_type"])
    guard repaired.bristolType == originalType else {
      throw ObservationParserError.inconsistent(
        "A serialization repair cannot invent or change a Bristol type."
      )
    }
    let originalColor = (original["apparent_color"] as? String).flatMap {
      PhotoSuggestionV1Parser.colors.contains($0) ? $0 : nil
    }
    guard repaired.apparentColor == originalColor else {
      throw ObservationParserError.inconsistent(
        "A serialization repair cannot invent or change an apparent color."
      )
    }

    let originalImageUsable = original["image_usable"] as? Bool
    guard repaired.imageUsable == (originalImageUsable ?? false) else {
      throw ObservationParserError.inconsistent(
        "A serialization repair cannot invent or change image usability."
      )
    }
    let originalPresence = (original["stool_presence"] as? String)
      .flatMap(StoolPresence.init(rawValue:))
    guard repaired.stoolPresence == (originalPresence ?? .uncertain) else {
      throw ObservationParserError.inconsistent(
        "A serialization repair cannot invent or change stool presence."
      )
    }

    let originalRetakeReason: PhotoRetakeReason?
    if original["retake_reason"] is NSNull {
      originalRetakeReason = nil
    } else {
      originalRetakeReason = (original["retake_reason"] as? String)
        .flatMap(PhotoRetakeReason.init(rawValue:))
    }
    let requiredRetakeReason = originalRetakeReason
      ?? (repaired.imageUsable ? nil : .other)
    guard repaired.retakeReason == requiredRetakeReason else {
      throw ObservationParserError.inconsistent(
        "A serialization repair cannot invent or change the retake reason."
      )
    }
  }

  private static func requireSameAnswer(
    _ originalValue: Any?,
    repaired: PhotoSuggestionAnswer,
    field: String
  ) throws {
    guard let raw = originalValue as? String,
      let original = PhotoSuggestionAnswer(rawValue: raw)
    else {
      guard repaired == .notSure else {
        throw ObservationParserError.inconsistent(
          "A serialization repair cannot invent a confident \(field) value."
        )
      }
      return
    }
    guard repaired == original else {
      throw ObservationParserError.inconsistent(
        "A serialization repair cannot change the \(field) value."
      )
    }
  }

  private static func integralNumber(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return nil }
    let double = number.doubleValue
    guard double.isFinite, double.rounded(.towardZero) == double else { return nil }
    return number.intValue
  }

  /// Direct parsing stays exact and rejects any wrapper. This extractor is
  /// used only to compare an initial response with a same-conversation
  /// serialization repair. It accepts exactly one balanced JSON object and
  /// rejects zero, multiple, or malformed objects before semantic comparison.
  private static func singleJSONObject(in raw: String) -> String? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var objectRange: Range<String.Index>?
    var objectStart: String.Index?
    var depth = 0
    var isInsideString = false
    var isEscaping = false

    for index in text.indices {
      let character = text[index]
      guard let start = objectStart else {
        if character == "}" { return nil }
        if character == "{" {
          guard objectRange == nil else { return nil }
          objectStart = index
          depth = 1
          isInsideString = false
          isEscaping = false
        }
        continue
      }

      if isInsideString {
        if isEscaping {
          isEscaping = false
        } else if character == "\\" {
          isEscaping = true
        } else if character == "\"" {
          isInsideString = false
        }
        continue
      }

      if character == "\"" {
        isInsideString = true
      } else if character == "{" {
        depth += 1
      } else if character == "}" {
        depth -= 1
        guard depth >= 0 else { return nil }
        if depth == 0 {
          objectRange = start..<text.index(after: index)
          objectStart = nil
        }
      }
    }

    guard objectStart == nil, let objectRange else { return nil }
    return String(text[objectRange])
  }
}

/// Foundation's JSON decoders retain only one value when an object repeats a
/// member name. Scan the top-level object first so the nine-key contract cannot
/// be made ambiguous, including when equivalent names use JSON Unicode escapes.
struct JSONTopLevelKeyScanner {
  private let bytes: [UInt8]
  private var index = 0

  static func hasUniqueKeys(in text: String) -> Bool {
    var scanner = Self(bytes: Array(text.utf8))
    return scanner.scanTopLevelObject()
  }

  private mutating func scanTopLevelObject() -> Bool {
    skipWhitespace()
    guard consume(0x7B) else { return false } // {

    var keys = Set<String>()
    skipWhitespace()
    if consume(0x7D) { // }
      skipWhitespace()
      return index == bytes.count
    }

    while true {
      skipWhitespace()
      guard let key = consumeString(), keys.insert(key).inserted else { return false }
      skipWhitespace()
      guard consume(0x3A), skipValue() else { return false } // :
      skipWhitespace()

      if consume(0x7D) { // }
        skipWhitespace()
        return index == bytes.count
      }
      guard consume(0x2C) else { return false } // ,
    }
  }

  private mutating func skipValue() -> Bool {
    skipWhitespace()
    guard index < bytes.count else { return false }

    switch bytes[index] {
    case 0x22: return consumeString() != nil // "
    case 0x7B: return skipObject() // {
    case 0x5B: return skipArray() // [
    case 0x74: return consumeLiteral([0x74, 0x72, 0x75, 0x65]) // true
    case 0x66: return consumeLiteral([0x66, 0x61, 0x6C, 0x73, 0x65]) // false
    case 0x6E: return consumeLiteral([0x6E, 0x75, 0x6C, 0x6C]) // null
    default: return skipNumber()
    }
  }

  private mutating func skipObject() -> Bool {
    guard consume(0x7B) else { return false } // {
    skipWhitespace()
    if consume(0x7D) { return true } // }

    while true {
      skipWhitespace()
      guard consumeString() != nil else { return false }
      skipWhitespace()
      guard consume(0x3A), skipValue() else { return false } // :
      skipWhitespace()
      if consume(0x7D) { return true } // }
      guard consume(0x2C) else { return false } // ,
    }
  }

  private mutating func skipArray() -> Bool {
    guard consume(0x5B) else { return false } // [
    skipWhitespace()
    if consume(0x5D) { return true } // ]

    while true {
      guard skipValue() else { return false }
      skipWhitespace()
      if consume(0x5D) { return true } // ]
      guard consume(0x2C) else { return false } // ,
    }
  }

  private mutating func consumeString() -> String? {
    let start = index
    guard consume(0x22) else { return nil } // "

    while index < bytes.count {
      let byte = bytes[index]
      if byte == 0x22 { // "
        index += 1
        return try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
      }
      if byte < 0x20 { return nil }
      if byte == 0x5C { // backslash
        index += 1
        guard index < bytes.count else { return nil }
        if bytes[index] == 0x75 { // u
          guard index + 4 < bytes.count,
            bytes[(index + 1)...(index + 4)].allSatisfy(Self.isHexDigit)
          else { return nil }
          index += 5
        } else {
          guard [0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(bytes[index])
          else { return nil }
          index += 1
        }
      } else {
        index += 1
      }
    }
    return nil
  }

  private mutating func skipNumber() -> Bool {
    let start = index
    _ = consume(0x2D) // -
    guard index < bytes.count else { return false }

    if consume(0x30) { // 0
      if index < bytes.count, Self.isDigit(bytes[index]) { return false }
    } else {
      guard index < bytes.count, (0x31...0x39).contains(bytes[index]) else { return false }
      index += 1
      while index < bytes.count, Self.isDigit(bytes[index]) { index += 1 }
    }

    if consume(0x2E) { // .
      guard index < bytes.count, Self.isDigit(bytes[index]) else { return false }
      while index < bytes.count, Self.isDigit(bytes[index]) { index += 1 }
    }

    if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 { // e/E
      index += 1
      if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
      guard index < bytes.count, Self.isDigit(bytes[index]) else { return false }
      while index < bytes.count, Self.isDigit(bytes[index]) { index += 1 }
    }
    return index > start
  }

  private mutating func consumeLiteral(_ literal: [UInt8]) -> Bool {
    guard index + literal.count <= bytes.count,
      Array(bytes[index..<(index + literal.count)]) == literal
    else { return false }
    index += literal.count
    return true
  }

  private mutating func consume(_ byte: UInt8) -> Bool {
    guard index < bytes.count, bytes[index] == byte else { return false }
    index += 1
    return true
  }

  private mutating func skipWhitespace() {
    while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
      index += 1
    }
  }

  private static func isDigit(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte)
  }

  private static func isHexDigit(_ byte: UInt8) -> Bool {
    isDigit(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
  }
}

public enum StoredModelVisualSuggestion: Equatable, Sendable {
  case legacy(VisualObservation)
  case photoV1(PhotoSuggestionV1)
  case fullPrefillV1(FullPrefillPhotoSuggestionV1)
  case fullPrefillV2(PhotoSuggestionPayloadV2)

  public static func parse(_ raw: String) throws -> StoredModelVisualSuggestion {
    if raw.contains(
      "\"schema_version\":\"\(PhotoSuggestionPayloadV2.schemaVersion)\""
    ) {
      return .fullPrefillV2(try PhotoSuggestionPayloadV2Parser.parse(raw))
    }
    if raw.contains(
      "\"schema_version\":\"\(FullPrefillPhotoSuggestionV1.schemaVersion)\""
    ) {
      return .fullPrefillV1(try FullPrefillPhotoSuggestionV1Parser.parse(raw))
    }
    if raw.contains("\"schema_version\"") {
      return .photoV1(try PhotoSuggestionV1Parser.parse(raw))
    }
    return .legacy(try ObservationParser.parse(raw))
  }

  public var photoV1Suggestion: PhotoSuggestionV1? {
    guard case .photoV1(let suggestion) = self else { return nil }
    return suggestion
  }

  public var fullPrefillSuggestion: FullPrefillPhotoSuggestionV1? {
    guard case .fullPrefillV1(let suggestion) = self else { return nil }
    return suggestion
  }

  public var fullPrefillV2Suggestion: PhotoSuggestionPayloadV2? {
    guard case .fullPrefillV2(let suggestion) = self else { return nil }
    return suggestion
  }

  public var blackAppearanceSuggestion: PhotoSuggestionAnswer? {
    fullPrefillV2Suggestion?.blackAppearance
  }

  public var retakeReasonSuggestion: PhotoRetakeReason? {
    switch self {
    case .legacy: return nil
    case .photoV1(let suggestion): return suggestion.retakeReason
    case .fullPrefillV1(let suggestion): return suggestion.retakeReason
    case .fullPrefillV2(let suggestion): return suggestion.retakeReason
    }
  }

  public var stoolPresenceSuggestion: StoolPresence? {
    switch self {
    case .legacy: return nil
    case .photoV1(let suggestion): return suggestion.stoolPresence
    case .fullPrefillV1(let suggestion): return suggestion.stoolPresence
    case .fullPrefillV2(let suggestion): return suggestion.stoolPresence
    }
  }

  public var formSuggestion: String {
    switch self {
    case .legacy(let observation): return observation.form
    case .photoV1: return visualObservation.form
    case .fullPrefillV1(let suggestion): return suggestion.form
    case .fullPrefillV2(let suggestion): return suggestion.form
    }
  }

  public var visualObservation: VisualObservation {
    switch self {
    case .legacy(let observation):
      return observation
    case .photoV1(let suggestion):
      let usableStool = suggestion.imageUsable && suggestion.stoolPresence == .stool
      let qualityIssue: String
      if usableStool {
        qualityIssue = "none"
      } else if suggestion.stoolPresence == .nonStool {
        qualityIssue = "not_target_image"
      } else {
        switch suggestion.retakeReason {
        case .tooDark: qualityIssue = "too_dark"
        case .blurred: qualityIssue = "blurred"
        case .obstructed, .glare: qualityIssue = "obstructed"
        case .tooFar: qualityIssue = "too_far"
        case .notTargetImage: qualityIssue = "not_target_image"
        case .other, nil: qualityIssue = "other"
        }
      }
      let form: String
      if let type = suggestion.bristolType,
        let expected = BristolFormContract.expectedForm(for: type)
      {
        form = expected
      } else if suggestion.mixedForm == .yes {
        form = "mixed"
      } else {
        form = "unable_to_assess"
      }
      return VisualObservation(
        imageUsable: usableStool,
        qualityIssue: qualityIssue,
        apparentBristolType: usableStool ? suggestion.bristolType : nil,
        apparentColor: usableStool ? (suggestion.apparentColor ?? "unable_to_assess") : "unable_to_assess",
        form: usableStool ? form : "unable_to_assess",
        redAppearingMaterial: usableStool ? materialState(suggestion.redAppearingMaterial) : "unable_to_assess",
        blackTarryAppearance: usableStool ? materialState(suggestion.blackTarryAppearance) : "unable_to_assess"
      )
    case .fullPrefillV1(let suggestion):
      let usableStool = suggestion.imageUsable && suggestion.stoolPresence == .stool
      let qualityIssue: String
      if usableStool {
        qualityIssue = "none"
      } else if suggestion.stoolPresence == .nonStool {
        qualityIssue = "not_target_image"
      } else {
        switch suggestion.retakeReason {
        case .tooDark: qualityIssue = "too_dark"
        case .blurred: qualityIssue = "blurred"
        case .obstructed, .glare: qualityIssue = "obstructed"
        case .tooFar: qualityIssue = "too_far"
        case .notTargetImage: qualityIssue = "not_target_image"
        case .other, nil: qualityIssue = "other"
        }
      }
      return VisualObservation(
        imageUsable: usableStool,
        qualityIssue: qualityIssue,
        apparentBristolType: usableStool ? suggestion.bristolType : nil,
        apparentColor: usableStool
          ? (suggestion.apparentColor ?? "unable_to_assess")
          : "unable_to_assess",
        form: usableStool ? suggestion.form : "unable_to_assess",
        redAppearingMaterial: usableStool
          ? materialState(suggestion.redAppearingMaterial)
          : "unable_to_assess",
        blackTarryAppearance: usableStool
          ? materialState(suggestion.blackTarryAppearance)
          : "unable_to_assess"
      )
    case .fullPrefillV2(let suggestion):
      let qualityIssue: String
      if suggestion.imageUsable {
        qualityIssue = "none"
      } else {
        switch suggestion.retakeReason {
        case .tooDark: qualityIssue = "too_dark"
        case .blurred: qualityIssue = "blurred"
        case .obstructed, .glare: qualityIssue = "obstructed"
        case .tooFar: qualityIssue = "too_far"
        case .notTargetImage: qualityIssue = "not_target_image"
        case .other, nil: qualityIssue = "other"
        }
      }
      return VisualObservation(
        imageUsable: suggestion.imageUsable,
        qualityIssue: qualityIssue,
        apparentBristolType: suggestion.stoolPresence == .stool
          ? suggestion.bristolType : nil,
        apparentColor: suggestion.imageUsable
          ? (suggestion.apparentColor ?? "unable_to_assess")
          : "unable_to_assess",
        form: suggestion.stoolPresence == .stool
          ? suggestion.form : "unable_to_assess",
        redAppearingMaterial: suggestion.imageUsable
          ? materialState(suggestion.redAppearingMaterial)
          : "unable_to_assess",
        blackTarryAppearance: suggestion.imageUsable
          ? materialState(suggestion.blackTarryAppearance)
          : "unable_to_assess"
      )
    }
  }

  public var mixedFormSuggestion: ClinicalTriState {
    switch self {
    case .legacy(let observation):
      return ClinicalValidation.initialMixedFormSuggestion(from: observation) ?? .unsure
    case .photoV1(let suggestion):
      switch suggestion.mixedForm {
      case .yes: return .yes
      case .no: return .no
      case .notSure: return .unsure
      }
    case .fullPrefillV1(let suggestion):
      switch suggestion.mixedForm {
      case .yes: return .yes
      case .no: return .no
      case .notSure: return .unsure
      }
    case .fullPrefillV2(let suggestion):
      switch suggestion.mixedForm {
      case .yes: return .yes
      case .no: return .no
      case .notSure: return .unsure
      }
    }
  }

  private func materialState(_ answer: PhotoSuggestionAnswer) -> String {
    switch answer {
    case .yes: return "apparent"
    case .no: return "not_observed"
    case .notSure: return "unable_to_assess"
    }
  }
}
