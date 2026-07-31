public enum SafetyRules {
  public static let message = "Some of the symptoms you reported can require urgent medical assessment. This app cannot determine the cause or severity. Seek urgent medical care. Call emergency services for uncontrolled bleeding, fainting, chest pain, trouble breathing, or other severe symptoms."
  public static func shouldShow(redBlood: SymptomFlag?, blackTarry: SymptomFlag?, dizziness: SymptomFlag?, severePain: SymptomFlag?) -> Bool {
    [redBlood, blackTarry, dizziness, severePain].contains(.yes)
  }
}
