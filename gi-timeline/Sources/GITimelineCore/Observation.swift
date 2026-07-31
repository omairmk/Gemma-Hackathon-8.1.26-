import Foundation

public enum SymptomFlag: String, CaseIterable, Codable, Sendable {
  case yes, no, unsure
}

public struct VisualObservation: Codable, Equatable, Sendable {
  public let imageUsable: Bool
  public let qualityIssue: String
  public let apparentBristolType: Int?
  public let apparentColor: String
  public let form: String
  public let redAppearingMaterial: String
  public let blackTarryAppearance: String

  public init(imageUsable: Bool, qualityIssue: String, apparentBristolType: Int?, apparentColor: String, form: String, redAppearingMaterial: String, blackTarryAppearance: String) {
    self.imageUsable = imageUsable
    self.qualityIssue = qualityIssue
    self.apparentBristolType = apparentBristolType
    self.apparentColor = apparentColor
    self.form = form
    self.redAppearingMaterial = redAppearingMaterial
    self.blackTarryAppearance = blackTarryAppearance
  }

  enum CodingKeys: String, CodingKey {
    case imageUsable = "image_usable", qualityIssue = "quality_issue", apparentBristolType = "apparent_bristol_type"
    case apparentColor = "apparent_color", form, redAppearingMaterial = "red_appearing_material", blackTarryAppearance = "black_tarry_appearance"
  }
}

public enum ObservationParserError: Error, Equatable, LocalizedError {
  case invalidJSON
  case unknownKeys([String])
  case missingKeys([String])
  case invalidValue(String)
  case inconsistent(String)

  public var errorDescription: String? {
    switch self {
    case .invalidJSON: return "Response was not valid JSON."
    case .unknownKeys(let keys): return "Unknown keys: \(keys.sorted().joined(separator: ", "))."
    case .missingKeys(let keys): return "Missing keys: \(keys.sorted().joined(separator: ", "))."
    case .invalidValue(let field): return "Invalid value for \(field)."
    case .inconsistent(let message): return message
    }
  }
}

public enum ObservationParser {
  public static let expectedKeys: Set<String> = ["image_usable", "quality_issue", "apparent_bristol_type", "apparent_color", "form", "red_appearing_material", "black_tarry_appearance"]
  public static let qualityIssues: Set<String> = ["none", "too_dark", "blurred", "obstructed", "too_far", "not_target_image", "other"]
  public static let colors: Set<String> = ["brown", "light_brown", "dark_brown", "green", "yellow", "orange", "red_appearing", "black_appearing", "pale_or_clay_appearing", "mixed", "unable_to_assess"]
  public static let forms: Set<String> = ["hard_lumps", "lumpy_formed", "cracked_formed", "smooth_formed", "soft_blobs", "mushy", "watery", "mixed", "unable_to_assess"]
  public static let materialStates: Set<String> = ["not_observed", "possible", "apparent", "unable_to_assess"]

  public static func parse(_ raw: String) throws -> VisualObservation {
    let text = stripAccidentalFences(raw)
    guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data), let dictionary = object as? [String: Any] else { throw ObservationParserError.invalidJSON }
    let keys = Set(dictionary.keys)
    let unknown = keys.subtracting(expectedKeys)
    if !unknown.isEmpty { throw ObservationParserError.unknownKeys(Array(unknown)) }
    let missing = expectedKeys.subtracting(keys)
    if !missing.isEmpty { throw ObservationParserError.missingKeys(Array(missing)) }
    let decoder = JSONDecoder()
    let observation: VisualObservation
    do { observation = try decoder.decode(VisualObservation.self, from: data) } catch { throw ObservationParserError.invalidJSON }
    try validate(observation)
    return observation
  }

  public static func canonicalJSON(_ observation: VisualObservation) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    guard let result = String(data: try encoder.encode(observation), encoding: .utf8) else { throw ObservationParserError.invalidJSON }
    return result
  }

  public static func validate(_ observation: VisualObservation) throws {
    guard qualityIssues.contains(observation.qualityIssue) else { throw ObservationParserError.invalidValue("quality_issue") }
    guard colors.contains(observation.apparentColor) else { throw ObservationParserError.invalidValue("apparent_color") }
    guard forms.contains(observation.form) else { throw ObservationParserError.invalidValue("form") }
    guard materialStates.contains(observation.redAppearingMaterial) else { throw ObservationParserError.invalidValue("red_appearing_material") }
    guard materialStates.contains(observation.blackTarryAppearance) else { throw ObservationParserError.invalidValue("black_tarry_appearance") }
    if let type = observation.apparentBristolType, !(1...7).contains(type) { throw ObservationParserError.invalidValue("apparent_bristol_type") }
    if observation.imageUsable {
      guard observation.qualityIssue == "none" else { throw ObservationParserError.inconsistent("Usable image requires quality_issue none.") }
    } else {
      guard observation.qualityIssue != "none" else { throw ObservationParserError.inconsistent("Unusable image requires a non-none quality issue.") }
      guard observation.apparentBristolType == nil else { throw ObservationParserError.inconsistent("Unusable image requires null Bristol type.") }
      guard observation.apparentColor == "unable_to_assess", observation.form == "unable_to_assess", observation.redAppearingMaterial == "unable_to_assess", observation.blackTarryAppearance == "unable_to_assess" else { throw ObservationParserError.inconsistent("Unusable image requires unable_to_assess observations.") }
    }
  }

  private static func stripAccidentalFences(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("```") {
      value = value.replacingOccurrences(of: "```json", with: "", options: [.caseInsensitive]).replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return value
  }
}
