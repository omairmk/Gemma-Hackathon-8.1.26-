public enum SafetyGuidance: String, Codable, Equatable, Sendable {
  case none
  case contactClinician
  case uncertain
}

public enum SafetyRules {
  public static let message = "You recorded red material that may have been blood or black/tar-like stool. Contact your clinician promptly. If bleeding is heavy or you feel faint, lightheaded, short of breath, confused, or severely unwell, seek urgent medical help."
  public static let uncertainMessage = "You recorded that you were not sure about red material or a black/tar-like appearance. Contact your clinician if you remain unsure."

  public static func guidance(
    redBlood: SymptomFlag?,
    blackTarry: SymptomFlag?
  ) -> SafetyGuidance {
    if redBlood == .yes || blackTarry == .yes { return .contactClinician }
    if redBlood == .unsure || blackTarry == .unsure { return .uncertain }
    return .none
  }

  public static func shouldShow(
    redBlood: SymptomFlag?,
    blackTarry: SymptomFlag?,
    dizziness: SymptomFlag? = nil,
    severePain: SymptomFlag? = nil
  ) -> Bool {
    guidance(redBlood: redBlood, blackTarry: blackTarry) != .none
  }
}

/// Exact, appearance-only copy for an editable photo suggestion. These
/// strings describe what the photo model returned; they do not diagnose
/// bleeding, melena, or any underlying condition.
public enum PhotoAppearanceSuggestionCopy {
  public static func redBloodLike(_ answer: SymptomFlag) -> String {
    switch answer {
    case .yes:
      return "AI suggestion: Possible blood-like red material is visible."
    case .no:
      return "AI suggestion: No blood-like red material detected in this photo."
    case .unsure:
      return "AI suggestion: Unable to determine whether blood-like red material is visible."
    }
  }

  public static func blackOrTarry(_ answer: SymptomFlag) -> String {
    switch answer {
    case .yes:
      return "AI suggestion: Possible black or tar-like appearance is visible."
    case .no:
      return "AI suggestion: No black or tar-like appearance detected in this photo."
    case .unsure:
      return "AI suggestion: Unable to determine whether a black or tar-like appearance is visible."
    }
  }
}

public extension PhotoSuggestionAnswer {
  /// Maps the model's complete appearance-only tri-state answer to the
  /// editable, visibly unconfirmed review control. Invalid or unusable model
  /// output is normalized to `.notSure` before this boundary.
  var appearancePrefillFlag: SymptomFlag {
    switch self {
    case .yes: return .yes
    case .no: return .no
    case .notSure: return .unsure
    }
  }

  /// Historical V9 display policy used only to validate or migrate records
  /// that were durably written before the complete tri-state contract. New
  /// suggestions must use `appearancePrefillFlag`.
  var legacyV9AppearancePrefillFlag: SymptomFlag {
    switch self {
    case .yes: return .yes
    case .no, .notSure: return .unsure
    }
  }
}
