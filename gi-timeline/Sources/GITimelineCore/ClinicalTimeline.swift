import Foundation

public enum AnalysisSource: String, Codable, CaseIterable, Sendable {
  case manual
  case gemmaRawImage = "gemma_raw_image"
  case gemmaDerivedMap = "gemma_derived_map"
  case onDevicePhotoSuggestion = "on_device_photo_suggestion"
}

public enum StoolConsistency: String, Codable, CaseIterable, Sendable {
  case hard, formed, soft, loose, watery
  case unableToAssess = "unable_to_assess"
}

public enum ClinicalStoolForm: String, Codable, CaseIterable, Sendable {
  case type1, type2, type3, type4, type5, type6, type7
  case unableToAssess = "unable_to_assess"

  public init(bristolType: Int?) {
    switch bristolType {
    case 1: self = .type1
    case 2: self = .type2
    case 3: self = .type3
    case 4: self = .type4
    case 5: self = .type5
    case 6: self = .type6
    case 7: self = .type7
    default: self = .unableToAssess
    }
  }

  public var bristolType: Int? {
    switch self {
    case .type1: return 1
    case .type2: return 2
    case .type3: return 3
    case .type4: return 4
    case .type5: return 5
    case .type6: return 6
    case .type7: return 7
    case .unableToAssess: return nil
    }
  }

  public var consistency: StoolConsistency {
    switch self {
    case .type1, .type2: return .hard
    case .type3, .type4: return .formed
    case .type5: return .soft
    case .type6: return .loose
    case .type7: return .watery
    case .unableToAssess: return .unableToAssess
    }
  }

  public var displayName: String {
    switch self {
    case .type1: return "Type 1 - separate hard lumps"
    case .type2: return "Type 2 - firm and lumpy"
    case .type3: return "Type 3 - formed with surface cracks"
    case .type4: return "Type 4 - smooth and formed"
    case .type5: return "Type 5 - soft pieces with clear edges"
    case .type6: return "Type 6 - mushy or fluffy pieces"
    case .type7: return "Type 7 - watery, with no solid pieces"
    case .unableToAssess: return "Unable to tell"
    }
  }
}

public enum UrgencyLevel: String, Codable, CaseIterable, Sendable {
  case none, moderate, severe

  public var displayName: String {
    switch self {
    case .none: return "No urgency"
    case .moderate: return "Had to hurry"
    case .severe: return "Could not wait"
    }
  }
}

public enum ClinicalTriState: String, Codable, CaseIterable, Sendable {
  case no, unsure, yes

  public var displayName: String {
    switch self {
    case .no: return "No"
    case .unsure: return "Not sure"
    case .yes: return "Yes"
    }
  }
}

public enum DailyCompletionAnswer: String, Codable, CaseIterable, Sendable {
  case yes, no
  /// A distinct, explicit zero-event marker. Existing yes/no values retain
  /// their legacy "daily completeness" meaning and are never reinterpreted.
  case noBowelMovement = "no_bowel_movement"

  public var displayName: String {
    switch self {
    case .yes: return "Yes"
    case .no: return "No"
    case .noBowelMovement: return "No bowel movement"
    }
  }
}

public enum ConditionalQuestion: String, Codable, Sendable {
  case strainingOrIncomplete = "straining_or_incomplete"
  case leakageOrAccident = "leakage_or_accident"
}

public enum ClinicalValidationError: Error, Equatable, LocalizedError, Sendable {
  case invalidBristolType
  case invalidPainScore
  case missingMixedForm
  case missingStrainingOrIncomplete
  case missingLeakageOrAccident
  case irrelevantStrainingOrIncomplete
  case irrelevantLeakageOrAccident

  public var errorDescription: String? {
    switch self {
    case .invalidBristolType: return "Choose a stool type from 1 through 7, or Unable to tell."
    case .invalidPainScore: return "Pain must be from 0 through 10."
    case .missingMixedForm: return "Answer the mixed-form question."
    case .missingStrainingOrIncomplete: return "Answer the straining or incomplete-emptying question."
    case .missingLeakageOrAccident: return "Answer the leakage or accident question."
    case .irrelevantStrainingOrIncomplete: return "Clear the straining answer when the confirmed type is loose or watery."
    case .irrelevantLeakageOrAccident: return "Clear the leakage answer when the confirmed type is hard, formed, or soft."
    }
  }
}

public enum ClinicalValidation {
  public static func initialMixedFormSuggestion(from observation: VisualObservation) -> ClinicalTriState? {
    observation.form == "mixed" ? .yes : .no
  }

  public static func consistency(for confirmedBristolType: Int?) -> StoolConsistency {
    return ClinicalStoolForm(bristolType: confirmedBristolType).consistency
  }

  public static func conditionalQuestion(for confirmedBristolType: Int?) -> ConditionalQuestion? {
    guard let confirmedBristolType else { return nil }
    return confirmedBristolType <= 5 ? .strainingOrIncomplete : .leakageOrAccident
  }

  public static func validate(
    confirmedBristolType: Int?,
    painScore: Int?,
    mixedForm: ClinicalTriState?,
    strainingOrIncomplete: ClinicalTriState?,
    leakageOrAccident: ClinicalTriState?
  ) -> [ClinicalValidationError] {
    var errors: [ClinicalValidationError] = []
    if let confirmedBristolType, !(1...7).contains(confirmedBristolType) { errors.append(.invalidBristolType) }
    // Context that cannot be inferred from a photo remains optional. A nil
    // value means "not recorded"; it must never be silently converted to No.
    if let painScore, !(0...10).contains(painScore) { errors.append(.invalidPainScore) }
    switch conditionalQuestion(for: confirmedBristolType) {
    case .strainingOrIncomplete:
      if leakageOrAccident != nil { errors.append(.irrelevantLeakageOrAccident) }
    case .leakageOrAccident:
      if strainingOrIncomplete != nil { errors.append(.irrelevantStrainingOrIncomplete) }
    case nil:
      if strainingOrIncomplete != nil { errors.append(.irrelevantStrainingOrIncomplete) }
      if leakageOrAccident != nil { errors.append(.irrelevantLeakageOrAccident) }
    }
    return errors
  }
}

public struct ClinicalEntryDraft: Equatable, Sendable {
  public var confirmedBristolType: Int?
  public var confirmedPhotoUsable: Bool?
  public var mixedForm: ClinicalTriState?
  public var painScore: Int?
  public var urgency: UrgencyLevel?
  public var strainingOrIncomplete: ClinicalTriState?
  public var leakageOrAccident: ClinicalTriState?

  public init(
    confirmedBristolType: Int? = nil,
    confirmedPhotoUsable: Bool? = nil,
    mixedForm: ClinicalTriState? = nil,
    painScore: Int? = nil,
    urgency: UrgencyLevel? = nil,
    strainingOrIncomplete: ClinicalTriState? = nil,
    leakageOrAccident: ClinicalTriState? = nil
  ) {
    self.confirmedBristolType = confirmedBristolType
    self.confirmedPhotoUsable = confirmedPhotoUsable
    self.mixedForm = mixedForm
    self.painScore = painScore
    self.urgency = urgency
    self.strainingOrIncomplete = strainingOrIncomplete
    self.leakageOrAccident = leakageOrAccident
  }

  public mutating func updateConfirmedBristolType(_ type: Int?) {
    confirmedBristolType = type
    switch ClinicalValidation.conditionalQuestion(for: type) {
    case .strainingOrIncomplete: leakageOrAccident = nil
    case .leakageOrAccident: strainingOrIncomplete = nil
    case nil:
      strainingOrIncomplete = nil
      leakageOrAccident = nil
    }
  }

  public var validationErrors: [ClinicalValidationError] {
    ClinicalValidation.validate(
      confirmedBristolType: confirmedBristolType,
      painScore: painScore,
      mixedForm: mixedForm,
      strainingOrIncomplete: strainingOrIncomplete,
      leakageOrAccident: leakageOrAccident
    )
  }
}

public enum TreatmentEventKind: String, Codable, CaseIterable, Sendable {
  case startedTreatment = "started_treatment"
  case stoppedTreatment = "stopped_treatment"
  case changedDose = "changed_dose"
  case beganFiber = "began_fiber"
  case changedDiet = "changed_diet"
  case startedAntibiotics = "started_antibiotics"
  case beganAntidiarrheal = "began_antidiarrheal"
  case beganLaxative = "began_laxative"
  case other

  public var displayName: String {
    switch self {
    case .startedTreatment: return "Started treatment"
    case .stoppedTreatment: return "Stopped treatment"
    case .changedDose: return "Changed dose"
    case .beganFiber: return "Began fiber"
    case .changedDiet: return "Changed diet"
    case .startedAntibiotics: return "Started antibiotics"
    case .beganAntidiarrheal: return "Began antidiarrheal"
    case .beganLaxative: return "Began laxative"
    case .other: return "Other"
    }
  }
}

public struct ClinicalEntrySnapshot: Equatable, Sendable {
  public let id: UUID
  public let capturedAt: Date
  public let confirmedBristolType: Int?
  public let suggestedBristolType: Int?
  public let hasOriginalAIObservation: Bool
  public let confirmedPhotoUsable: Bool?
  public let mixedForm: ClinicalTriState?
  public let painScore: Int?
  public let urgency: UrgencyLevel?
  public let strainingOrIncomplete: ClinicalTriState?
  public let leakageOrAccident: ClinicalTriState?
  public let redBlood: ClinicalTriState?
  public let blackTarry: ClinicalTriState?

  public init(
    id: UUID,
    capturedAt: Date,
    confirmedBristolType: Int?,
    suggestedBristolType: Int? = nil,
    hasOriginalAIObservation: Bool = false,
    confirmedPhotoUsable: Bool? = nil,
    mixedForm: ClinicalTriState? = nil,
    painScore: Int? = nil,
    urgency: UrgencyLevel? = nil,
    strainingOrIncomplete: ClinicalTriState? = nil,
    leakageOrAccident: ClinicalTriState? = nil,
    redBlood: ClinicalTriState? = nil,
    blackTarry: ClinicalTriState? = nil
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.confirmedBristolType = confirmedBristolType
    self.suggestedBristolType = suggestedBristolType
    self.hasOriginalAIObservation = hasOriginalAIObservation
    self.confirmedPhotoUsable = confirmedPhotoUsable
    self.mixedForm = mixedForm
    self.painScore = painScore
    self.urgency = urgency
    self.strainingOrIncomplete = strainingOrIncomplete
    self.leakageOrAccident = leakageOrAccident
    self.redBlood = redBlood
    self.blackTarry = blackTarry
  }
}

public struct DailyCompletionSnapshot: Equatable, Sendable {
  public let day: Date
  public let answer: DailyCompletionAnswer
  public init(day: Date, answer: DailyCompletionAnswer) { self.day = day; self.answer = answer }
}

public struct TreatmentEventSnapshot: Equatable, Sendable {
  public let id: UUID
  public let kind: TreatmentEventKind
  public let name: String
  public let doseOrNote: String?
  public let effectiveDate: Date

  public init(id: UUID, kind: TreatmentEventKind, name: String, doseOrNote: String? = nil, effectiveDate: Date) {
    self.id = id; self.kind = kind; self.name = name; self.doseOrNote = doseOrNote; self.effectiveDate = effectiveDate
  }
}

public struct LocalDayInterval: Equatable, Sendable {
  public let start: Date
  public let end: Date
  public let totalDays: Int
  public let isPartial: Bool

  public init(start: Date, end: Date, totalDays: Int, isPartial: Bool) {
    self.start = start; self.end = end; self.totalDays = totalDays; self.isPartial = isPartial
  }

  public func contains(_ date: Date) -> Bool { date >= start && date < end }
}

public struct CountWithDenominator: Equatable, Sendable {
  public let count: Int
  public let denominator: Int
  public init(count: Int, denominator: Int) { self.count = count; self.denominator = denominator }
}

public struct BristolGroupSummary: Equatable, Sendable {
  public let type1To2: Int
  public let type3To5: Int
  public let type6To7: Int
  public let denominator: Int

  public func percentage(for count: Int) -> Double? {
    guard denominator > 0 else { return nil }
    return Double(count) / Double(denominator) * 100
  }
}

public struct ConsistencyCountSummary: Equatable, Sendable {
  public let hard: Int
  public let formed: Int
  public let soft: Int
  public let loose: Int
  public let watery: Int
  public let mixedConfirmed: Int
}

public struct TreatmentWindowSummary: Equatable, Sendable {
  public let interval: LocalDayInterval
  public let entriesRecorded: Int
  public let completeDays: Int
  public let entriesOnCompleteDays: Int
  public let completeDayFrequency: Double?
  public let bristolGroups: BristolGroupSummary
  public let consistencies: ConsistencyCountSummary
  public let medianPain: Double?
  public let painDenominator: Int
  public let severeUrgency: CountWithDenominator
  public let strainingYes: CountWithDenominator
  public let leakageYes: CountWithDenominator
  public let redBloodYes: CountWithDenominator
  public let redBloodUnsure: CountWithDenominator
  public let blackTarryYes: CountWithDenominator
  public let blackTarryUnsure: CountWithDenominator
  public let unusablePhotoCount: Int
  public let bristolCorrectionCount: Int

  public var hasCompleteCoverage: Bool { interval.totalDays > 0 && completeDays == interval.totalDays }
  public var entryCountLabel: String { hasCompleteCoverage ? "Bowel movements" : "Recorded bowel movements" }
  public var completeDayFrequencyLabel: String {
    completeDayFrequency == nil ? "Insufficient complete-day data" : "Recorded bowel movements per confirmed-complete day"
  }
}

public struct TreatmentResponseComparison: Equatable, Sendable {
  public let event: TreatmentEventSnapshot
  public let before: TreatmentWindowSummary
  public let transitionDate: Date
  public let transitionEntryCount: Int
  public let after: TreatmentWindowSummary

  public static let disclaimer = "This journal summarizes user-recorded observations. It does not diagnose a condition, measure inflammation, recommend treatment, or replace clinician assessment."
}

public struct TreatmentResponseCalculator: Sendable {
  public let calendar: Calendar
  public let timeZone: TimeZone

  public init(calendar: Calendar = .current, timeZone: TimeZone = .current) {
    var calendar = calendar
    calendar.timeZone = timeZone
    self.calendar = calendar
    self.timeZone = timeZone
  }

  public func localDayStart(for date: Date) -> Date { calendar.startOfDay(for: date) }

  public func dayKey(for date: Date) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }

  /// Reconstructs the start of a recorded local calendar date in this
  /// calculator's time zone. A day key is date-only identity: it must keep the
  /// date the person selected even if the device later changes time zones.
  public func localDayStart(forDayKey dayKey: String) -> Date? {
    let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
      parts[0].count == 4,
      parts[1].count == 2,
      parts[2].count == 2,
      parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return nil }

    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = timeZone
    components.year = year
    components.month = month
    components.day = day
    guard let date = calendar.date(from: components), self.dayKey(for: date) == dayKey else {
      return nil
    }
    return calendar.startOfDay(for: date)
  }

  public func compare(
    event: TreatmentEventSnapshot,
    entries: [ClinicalEntrySnapshot],
    completions: [DailyCompletionSnapshot],
    today: Date
  ) -> TreatmentResponseComparison {
    let transition = localDayStart(for: event.effectiveDate)
    let beforeStart = calendar.date(byAdding: .day, value: -7, to: transition)!
    let afterStart = calendar.date(byAdding: .day, value: 1, to: transition)!
    let fixedAfterEnd = calendar.date(byAdding: .day, value: 8, to: transition)!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: localDayStart(for: today))!
    let observedAfterEnd = max(afterStart, min(fixedAfterEnd, tomorrow))
    let beforeInterval = LocalDayInterval(start: beforeStart, end: transition, totalDays: 7, isPartial: false)
    let observedAfterDays = max(0, calendar.dateComponents([.day], from: afterStart, to: observedAfterEnd).day ?? 0)
    let afterInterval = LocalDayInterval(start: afterStart, end: observedAfterEnd, totalDays: observedAfterDays, isPartial: observedAfterEnd < fixedAfterEnd)
    let transitionEnd = calendar.date(byAdding: .day, value: 1, to: transition)!
    return TreatmentResponseComparison(
      event: event,
      before: summarize(interval: beforeInterval, entries: entries, completions: completions),
      transitionDate: transition,
      transitionEntryCount: entries.filter { $0.capturedAt >= transition && $0.capturedAt < transitionEnd }.count,
      after: summarize(interval: afterInterval, entries: entries, completions: completions)
    )
  }

  public func summarize(
    interval: LocalDayInterval,
    entries: [ClinicalEntrySnapshot],
    completions: [DailyCompletionSnapshot]
  ) -> TreatmentWindowSummary {
    let included = entries.filter { interval.contains($0.capturedAt) }
    let completeDays = Set(completions.lazy.filter {
      ($0.answer == .yes || $0.answer == .noBowelMovement)
        && interval.contains(localDayStart(for: $0.day))
    }.map { localDayStart(for: $0.day) })
    let entriesOnCompleteDays = included.filter { completeDays.contains(localDayStart(for: $0.capturedAt)) }.count
    let frequency = completeDays.isEmpty ? nil : Double(entriesOnCompleteDays) / Double(completeDays.count)

    let confirmedTypes = included.compactMap(\.confirmedBristolType).filter { (1...7).contains($0) }
    let group12 = confirmedTypes.filter { (1...2).contains($0) }.count
    let group35 = confirmedTypes.filter { (3...5).contains($0) }.count
    let group67 = confirmedTypes.filter { (6...7).contains($0) }.count
    let consistencyValues = confirmedTypes.map { ClinicalStoolForm(bristolType: $0).consistency }
    let pains = included.compactMap(\.painScore).sorted()
    let urgencyValues = included.compactMap(\.urgency)
    let strainingValues = included.filter { ($0.confirmedBristolType.map { (1...5).contains($0) }) == true }.compactMap(\.strainingOrIncomplete)
    let leakageValues = included.filter { ($0.confirmedBristolType.map { (6...7).contains($0) }) == true }.compactMap(\.leakageOrAccident)
    let redValues = included.compactMap(\.redBlood)
    let blackValues = included.compactMap(\.blackTarry)

    return TreatmentWindowSummary(
      interval: interval,
      entriesRecorded: included.count,
      completeDays: completeDays.count,
      entriesOnCompleteDays: entriesOnCompleteDays,
      completeDayFrequency: frequency,
      bristolGroups: .init(type1To2: group12, type3To5: group35, type6To7: group67, denominator: confirmedTypes.count),
      consistencies: .init(
        hard: consistencyValues.filter { $0 == .hard }.count,
        formed: consistencyValues.filter { $0 == .formed }.count,
        soft: consistencyValues.filter { $0 == .soft }.count,
        loose: consistencyValues.filter { $0 == .loose }.count,
        watery: consistencyValues.filter { $0 == .watery }.count,
        mixedConfirmed: included.filter { $0.mixedForm == .yes }.count
      ),
      medianPain: median(pains),
      painDenominator: pains.count,
      severeUrgency: .init(count: urgencyValues.filter { $0 == .severe }.count, denominator: urgencyValues.count),
      strainingYes: .init(count: strainingValues.filter { $0 == .yes }.count, denominator: strainingValues.count),
      leakageYes: .init(count: leakageValues.filter { $0 == .yes }.count, denominator: leakageValues.count),
      redBloodYes: .init(count: redValues.filter { $0 == .yes }.count, denominator: redValues.count),
      redBloodUnsure: .init(count: redValues.filter { $0 == .unsure }.count, denominator: redValues.count),
      blackTarryYes: .init(count: blackValues.filter { $0 == .yes }.count, denominator: blackValues.count),
      blackTarryUnsure: .init(count: blackValues.filter { $0 == .unsure }.count, denominator: blackValues.count),
      unusablePhotoCount: included.filter { $0.confirmedPhotoUsable == false }.count,
      bristolCorrectionCount: included.filter {
        $0.hasOriginalAIObservation && $0.suggestedBristolType != $0.confirmedBristolType
      }.count
    )
  }

  private func median(_ values: [Int]) -> Double? {
    guard !values.isEmpty else { return nil }
    let middle = values.count / 2
    if values.count.isMultiple(of: 2) { return Double(values[middle - 1] + values[middle]) / 2 }
    return Double(values[middle])
  }
}
