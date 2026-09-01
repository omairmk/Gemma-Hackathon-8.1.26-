import Foundation

/// Additive provider-neutral photo contract. V1 remains frozen because it has
/// one combined black/tarry field; V2 preserves two independently editable
/// visual answers without relabeling historical entries.
public struct PhotoSuggestionPayloadV2: Codable, Equatable, Sendable {
  public static let schemaVersion = "gi-photo-full-prefill-v2"

  public let schemaVersion: String
  public let imageUsable: Bool
  public let retakeReason: PhotoRetakeReason?
  public let stoolPresence: StoolPresence
  public let bristolType: Int?
  public let form: String
  public let mixedForm: PhotoSuggestionAnswer
  public let apparentColor: String?
  public let redAppearingMaterial: PhotoSuggestionAnswer
  public let blackAppearance: PhotoSuggestionAnswer
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
    blackAppearance: PhotoSuggestionAnswer,
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
    self.blackAppearance = blackAppearance
    self.blackTarryAppearance = blackTarryAppearance
  }

  public static func technicalAbstention(
    reason: PhotoRetakeReason
  ) -> PhotoSuggestionPayloadV2 {
    PhotoSuggestionPayloadV2(
      imageUsable: false,
      retakeReason: reason,
      stoolPresence: .uncertain,
      bristolType: nil,
      form: "unable_to_assess",
      mixedForm: .notSure,
      apparentColor: nil,
      redAppearingMaterial: .notSure,
      blackAppearance: .notSure,
      blackTarryAppearance: .notSure
    )
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(schemaVersion, forKey: .schemaVersion)
    try values.encode(imageUsable, forKey: .imageUsable)
    if let retakeReason { try values.encode(retakeReason, forKey: .retakeReason) }
    else { try values.encodeNil(forKey: .retakeReason) }
    try values.encode(stoolPresence, forKey: .stoolPresence)
    if let bristolType { try values.encode(bristolType, forKey: .bristolType) }
    else { try values.encodeNil(forKey: .bristolType) }
    try values.encode(form, forKey: .form)
    try values.encode(mixedForm, forKey: .mixedForm)
    if let apparentColor { try values.encode(apparentColor, forKey: .apparentColor) }
    else { try values.encodeNil(forKey: .apparentColor) }
    try values.encode(redAppearingMaterial, forKey: .redAppearingMaterial)
    try values.encode(blackAppearance, forKey: .blackAppearance)
    try values.encode(blackTarryAppearance, forKey: .blackTarryAppearance)
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
    case blackAppearance = "black_appearance"
    case blackTarryAppearance = "black_tarry_appearance"
  }
}

public enum PhotoSuggestionPayloadV2Parser {
  public static let parserVersion = "gi-photo-full-prefill-v2-parser-v1"
  public static let expectedKeys: Set<String> = [
    "schema_version", "image_usable", "retake_reason", "stool_presence",
    "bristol_type", "form", "mixed_form", "apparent_color",
    "red_appearing_material", "black_appearance", "black_tarry_appearance",
  ]

  public static func parse(_ raw: String) throws -> PhotoSuggestionPayloadV2 {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard JSONTopLevelKeyScanner.hasUniqueKeys(in: text),
      let data = text.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else { throw ObservationParserError.invalidJSON }

    let keys = Set(dictionary.keys)
    let unknown = keys.subtracting(expectedKeys)
    if !unknown.isEmpty {
      throw ObservationParserError.unknownKeys(Array(unknown).sorted())
    }
    let missing = expectedKeys.subtracting(keys)
    if !missing.isEmpty {
      throw ObservationParserError.missingKeys(Array(missing).sorted())
    }

    let suggestion: PhotoSuggestionPayloadV2
    do {
      suggestion = try JSONDecoder().decode(SelfDecodingBox.self, from: data).value
    } catch {
      throw ObservationParserError.invalidJSON
    }
    try validate(suggestion)
    return suggestion
  }

  public static func canonicalJSON(
    _ suggestion: PhotoSuggestionPayloadV2
  ) throws -> String {
    try validate(suggestion)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let value = String(
      data: try encoder.encode(suggestion),
      encoding: .utf8
    ) else { throw ObservationParserError.invalidJSON }
    return value
  }

  public static func validate(_ suggestion: PhotoSuggestionPayloadV2) throws {
    guard suggestion.schemaVersion == PhotoSuggestionPayloadV2.schemaVersion else {
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
      try requireMorphologyAbstention(
        suggestion,
        reason: "A non-stool or uncertain image"
      )
      return
    }

    switch suggestion.mixedForm {
    case .no:
      if let type = suggestion.bristolType,
        BristolFormContract.expectedForm(for: type) == suggestion.form {
        break
      }
      guard suggestion.bristolType == nil, suggestion.form == "unable_to_assess" else {
        throw ObservationParserError.inconsistent(
          "A known single form requires matching Bristol/form; an unknown single form abstains."
        )
      }
    case .yes:
      guard suggestion.bristolType == nil, suggestion.form == "mixed" else {
        throw ObservationParserError.inconsistent(
          "A mixed suggestion requires null Bristol and form mixed."
        )
      }
    case .notSure:
      if suggestion.bristolType == nil, suggestion.form == "unable_to_assess" { break }
      guard let type = suggestion.bristolType,
        BristolFormContract.expectedForm(for: type) == suggestion.form else {
        throw ObservationParserError.inconsistent(
          "An uncertain mixed flag requires either unknown form or matching Bristol/form."
        )
      }
    }
  }

  private static func requireAbstention(
    _ suggestion: PhotoSuggestionPayloadV2,
    reason: String
  ) throws {
    guard suggestion.bristolType == nil,
      suggestion.form == "unable_to_assess",
      suggestion.mixedForm == .notSure,
      suggestion.apparentColor == nil,
      suggestion.redAppearingMaterial == .notSure,
      suggestion.blackAppearance == .notSure,
      suggestion.blackTarryAppearance == .notSure
    else {
      throw ObservationParserError.inconsistent(
        "\(reason) requires null Bristol/color and not-sure appearance values."
      )
    }
  }

  private static func requireMorphologyAbstention(
    _ suggestion: PhotoSuggestionPayloadV2,
    reason: String
  ) throws {
    guard suggestion.bristolType == nil,
      suggestion.form == "unable_to_assess",
      suggestion.mixedForm == .notSure
    else {
      throw ObservationParserError.inconsistent(
        "\(reason) requires null Bristol and not-sure form values."
      )
    }
  }

  private struct SelfDecodingBox: Decodable {
    let value: PhotoSuggestionPayloadV2

    init(from decoder: Decoder) throws {
      let values = try decoder.container(
        keyedBy: PhotoSuggestionPayloadV2.CodingKeys.self
      )
      value = PhotoSuggestionPayloadV2(
        schemaVersion: try values.decode(String.self, forKey: .schemaVersion),
        imageUsable: try values.decode(Bool.self, forKey: .imageUsable),
        retakeReason: try values.decodeIfPresent(
          PhotoRetakeReason.self,
          forKey: .retakeReason
        ),
        stoolPresence: try values.decode(StoolPresence.self, forKey: .stoolPresence),
        bristolType: try values.decodeIfPresent(Int.self, forKey: .bristolType),
        form: try values.decode(String.self, forKey: .form),
        mixedForm: try values.decode(PhotoSuggestionAnswer.self, forKey: .mixedForm),
        apparentColor: try values.decodeIfPresent(String.self, forKey: .apparentColor),
        redAppearingMaterial: try values.decode(
          PhotoSuggestionAnswer.self,
          forKey: .redAppearingMaterial
        ),
        blackAppearance: try values.decode(
          PhotoSuggestionAnswer.self,
          forKey: .blackAppearance
        ),
        blackTarryAppearance: try values.decode(
          PhotoSuggestionAnswer.self,
          forKey: .blackTarryAppearance
        )
      )
    }
  }
}
