import Foundation

public enum JournalExportScope: String, Codable, CaseIterable, Sendable {
  case allEntries = "all_entries"
  case markedForDiscussion = "marked_for_discussion"

  public var displayName: String {
    switch self {
    case .allEntries: return "All entries"
    case .markedForDiscussion: return "Only entries marked for discussion"
    }
  }
}

public struct JournalExportRange: Equatable, Sendable {
  public let from: Date
  public let through: Date
  public init(from: Date, through: Date) { self.from = from; self.through = through }
}

public enum JournalExportPreset: String, CaseIterable, Sendable {
  case sevenDays = "7_days"
  case fourteenDays = "14_days"
  case thirtyDays = "30_days"
  case custom

  public var displayName: String {
    switch self {
    case .sevenDays: return "7 days"
    case .fourteenDays: return "14 days"
    case .thirtyDays: return "30 days"
    case .custom: return "Custom"
    }
  }

  public var dayCount: Int? {
    switch self {
    case .sevenDays: return 7
    case .fourteenDays: return 14
    case .thirtyDays: return 30
    case .custom: return nil
    }
  }
}

public enum JournalPhotoState: Equatable, Sendable {
  case noPhoto
  case available(filename: String)
  case unavailable

  public var hasExpectedPhoto: Bool {
    switch self {
    case .noPhoto: return false
    case .available, .unavailable: return true
    }
  }
}

/// Human-readable model values that may appear in a clinician export. Raw
/// model text, identifiers, prompts, routes, hashes, and runtime details never
/// enter this value.
public struct JournalSuggestedVisual: Equatable, Sendable {
  public let stoolPresence: StoolPresence?
  public let retakeReason: PhotoRetakeReason?
  public let bristolType: Int?
  public let form: String?
  public let mixedForm: ClinicalTriState?
  public let apparentColor: String?
  public let redAppearance: ClinicalTriState?
  public let blackAppearance: ClinicalTriState?
  public let blackTarryAppearance: ClinicalTriState?

  public init(
    stoolPresence: StoolPresence? = nil,
    retakeReason: PhotoRetakeReason? = nil,
    bristolType: Int?,
    form: String? = nil,
    mixedForm: ClinicalTriState?,
    apparentColor: String?,
    redAppearance: ClinicalTriState?,
    blackAppearance: ClinicalTriState? = nil,
    blackTarryAppearance: ClinicalTriState?
  ) {
    self.stoolPresence = stoolPresence
    self.retakeReason = retakeReason
    self.bristolType = bristolType
    self.form = form
    self.mixedForm = mixedForm
    self.apparentColor = apparentColor
    self.redAppearance = redAppearance
    self.blackAppearance = blackAppearance
    self.blackTarryAppearance = blackTarryAppearance
  }
}

public struct JournalExportEntry: Equatable, Sendable {
  public let id: UUID
  public let capturedAt: Date
  public let confirmedBristolType: Int?
  public let mixedForm: ClinicalTriState?
  public let painScore: Int?
  public let urgency: UrgencyLevel?
  public let strainingOrIncomplete: ClinicalTriState?
  public let leakageOrAccident: ClinicalTriState?
  public let redBlood: ClinicalTriState?
  public let blackAppearance: ClinicalTriState?
  public let blackTarry: ClinicalTriState?
  public let dizziness: ClinicalTriState?
  public let severeOrWorseningPain: ClinicalTriState?
  public let note: String?
  public let markedForDiscussionAt: Date?
  public let photoState: JournalPhotoState
  public let photoSHA256: String?
  public let suggestedVisual: JournalSuggestedVisual?
  public let confirmedPhotoUsable: Bool?
  public let initiallyAcceptedPhotoUsable: Bool?
  public let initiallyAcceptedRetakeReason: PhotoRetakeReason?
  public let initiallyAcceptedStoolPresence: StoolPresence?
  public let initiallyAcceptedBristolType: Int?
  public let initiallyAcceptedForm: String?
  public let initiallyAcceptedMixedForm: ClinicalTriState?
  public let initiallyAcceptedApparentColor: String?
  public let initiallyAcceptedRed: ClinicalTriState?
  public let initiallyAcceptedBlackAppearance: ClinicalTriState?
  public let initiallyAcceptedBlackTarry: ClinicalTriState?
  public let confirmedRetakeReason: PhotoRetakeReason?
  public let personConfirmedSubject: Bool?
  public let confirmedStoolPresence: StoolPresence?
  public let confirmedForm: String?
  public let confirmedApparentColor: String?
  public let fieldProvenance: [ConfirmationField: FieldConfirmationProvenance]

  public init(
    id: UUID,
    capturedAt: Date,
    confirmedBristolType: Int?,
    mixedForm: ClinicalTriState? = nil,
    painScore: Int? = nil,
    urgency: UrgencyLevel? = nil,
    strainingOrIncomplete: ClinicalTriState? = nil,
    leakageOrAccident: ClinicalTriState? = nil,
    redBlood: ClinicalTriState? = nil,
    blackAppearance: ClinicalTriState? = nil,
    blackTarry: ClinicalTriState? = nil,
    dizziness: ClinicalTriState? = nil,
    severeOrWorseningPain: ClinicalTriState? = nil,
    note: String? = nil,
    markedForDiscussionAt: Date? = nil,
    photoState: JournalPhotoState = .noPhoto,
    photoSHA256: String? = nil,
    suggestedVisual: JournalSuggestedVisual? = nil,
    confirmedPhotoUsable: Bool? = nil,
    initiallyAcceptedPhotoUsable: Bool? = nil,
    initiallyAcceptedRetakeReason: PhotoRetakeReason? = nil,
    initiallyAcceptedStoolPresence: StoolPresence? = nil,
    initiallyAcceptedBristolType: Int? = nil,
    initiallyAcceptedForm: String? = nil,
    initiallyAcceptedMixedForm: ClinicalTriState? = nil,
    initiallyAcceptedApparentColor: String? = nil,
    initiallyAcceptedRed: ClinicalTriState? = nil,
    initiallyAcceptedBlackAppearance: ClinicalTriState? = nil,
    initiallyAcceptedBlackTarry: ClinicalTriState? = nil,
    confirmedRetakeReason: PhotoRetakeReason? = nil,
    personConfirmedSubject: Bool? = nil,
    confirmedStoolPresence: StoolPresence? = nil,
    confirmedForm: String? = nil,
    confirmedApparentColor: String? = nil,
    fieldProvenance: [ConfirmationField: FieldConfirmationProvenance] = [:]
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.confirmedBristolType = confirmedBristolType
    self.mixedForm = mixedForm
    self.painScore = painScore
    self.urgency = urgency
    self.strainingOrIncomplete = strainingOrIncomplete
    self.leakageOrAccident = leakageOrAccident
    self.redBlood = redBlood
    self.blackAppearance = blackAppearance
    self.blackTarry = blackTarry
    self.dizziness = dizziness
    self.severeOrWorseningPain = severeOrWorseningPain
    self.note = note
    self.markedForDiscussionAt = markedForDiscussionAt
    self.photoState = photoState
    self.photoSHA256 = photoSHA256
    self.suggestedVisual = suggestedVisual
    self.confirmedPhotoUsable = confirmedPhotoUsable
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
    self.confirmedRetakeReason = confirmedRetakeReason
    self.personConfirmedSubject = personConfirmedSubject
    self.confirmedStoolPresence = confirmedStoolPresence
    self.confirmedForm = confirmedForm
    self.confirmedApparentColor = confirmedApparentColor
    self.fieldProvenance = fieldProvenance
  }

  public var isMarkedForDiscussion: Bool { markedForDiscussionAt != nil }
  public var stoolForm: ClinicalStoolForm { ClinicalStoolForm(bristolType: confirmedBristolType) }
}

public struct JournalTreatmentMarker: Equatable, Sendable {
  public let id: UUID
  public let effectiveDate: Date
  public let kind: TreatmentEventKind
  public let name: String
  public let doseOrNote: String?

  public init(id: UUID, effectiveDate: Date, kind: TreatmentEventKind, name: String, doseOrNote: String? = nil) {
    self.id = id; self.effectiveDate = effectiveDate; self.kind = kind; self.name = name; self.doseOrNote = doseOrNote
  }
}

public struct JournalRecordedDataSummary: Equatable, Sendable {
  public let entryCount: Int
  public let confirmedTypeCount: Int
  public let type1To2Count: Int
  public let type3To5Count: Int
  public let type6To7Count: Int
  public let mixedFormConfirmedCount: Int
  public let completeDays: Int
  public let totalDays: Int
  public let entriesOnCompleteDays: Int
  public let completeDayFrequency: Double?

  public var hasCompleteCoverage: Bool { completeDays == totalDays }
}

public struct JournalExportSnapshot: Equatable, Sendable {
  public let range: JournalExportRange
  public let startOfFirstDay: Date
  public let startAfterLastDay: Date
  public let timeZoneIdentifier: String
  public let generatedAt: Date
  public let scope: JournalExportScope
  public let entries: [JournalExportEntry]
  public let treatmentMarkers: [JournalTreatmentMarker]
  public let noBowelMovementDays: [Date]
  public let recordedDataSummary: JournalRecordedDataSummary?

  public var photoBearingEntryCount: Int { entries.filter { $0.photoState.hasExpectedPhoto }.count }
  public var filename: String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return "GI-Journal_\(formatter.string(from: range.from))_to_\(formatter.string(from: range.through)).pdf"
  }
}

public enum JournalExportValidationError: Error, Equatable, LocalizedError, Sendable {
  case startAfterEnd
  case rangeTooLong
  case noEntries
  case noMarkedEntries
  case tooManyPhotos
  case photoIntegrity
  case entryIntegrity

  public var errorDescription: String? {
    switch self {
    case .startAfterEnd: return "The From date must be on or before the Through date."
    case .rangeTooLong: return "Choose a range of 31 days or fewer."
    case .noEntries: return "No entries in these dates. Choose another date range."
    case .noMarkedEntries: return "No marked entries in these dates. Choose another date range or include all entries."
    case .tooManyPhotos: return "This range has more than 50 photos. Choose a shorter range so every available photo can be included."
    case .photoIntegrity: return "One or more attached journal photos could not be verified. Restart and unlock this iPhone, then try again, or choose a range that does not include the affected entry. No PDF was created."
    case .entryIntegrity: return "One or more selected journal entries could not be verified, so no PDF was created. Choose another range or contact product support without sending private journal data."
    }
  }
}

public struct JournalExportBuilder: Sendable {
  public let calendar: Calendar
  public let timeZone: TimeZone

  public init(calendar: Calendar = .current, timeZone: TimeZone = .current) {
    var calendar = calendar
    calendar.timeZone = timeZone
    self.calendar = calendar
    self.timeZone = timeZone
  }

  public func defaultRange(today: Date) -> JournalExportRange {
    range(for: .fourteenDays, endingOn: today)!
  }

  public func range(for preset: JournalExportPreset, endingOn date: Date) -> JournalExportRange? {
    guard let dayCount = preset.dayCount else { return nil }
    let through = calendar.startOfDay(for: date)
    let from = calendar.date(byAdding: .day, value: -(dayCount - 1), to: through)!
    return JournalExportRange(from: from, through: through)
  }

  public func boundaries(for range: JournalExportRange) throws -> (start: Date, end: Date, dayCount: Int) {
    let start = calendar.startOfDay(for: range.from)
    let through = calendar.startOfDay(for: range.through)
    guard start <= through else { throw JournalExportValidationError.startAfterEnd }
    let dayCount = (calendar.dateComponents([.day], from: start, to: through).day ?? 0) + 1
    guard dayCount <= 31 else { throw JournalExportValidationError.rangeTooLong }
    let end = calendar.date(byAdding: .day, value: 1, to: through)!
    return (start, end, dayCount)
  }

  public func matchingEntries(
    in entries: [JournalExportEntry],
    range: JournalExportRange,
    scope: JournalExportScope
  ) throws -> [JournalExportEntry] {
    let boundaries = try boundaries(for: range)
    return entries.filter {
      $0.capturedAt >= boundaries.start && $0.capturedAt < boundaries.end &&
        (scope == .allEntries || $0.isMarkedForDiscussion)
    }.sorted {
      if $0.capturedAt == $1.capturedAt { return $0.id.uuidString < $1.id.uuidString }
      return $0.capturedAt < $1.capturedAt
    }
  }

  public func validate(
    range: JournalExportRange,
    scope: JournalExportScope,
    entries: [JournalExportEntry],
    completions: [DailyCompletionSnapshot] = []
  ) -> JournalExportValidationError? {
    do {
      let boundaries = try boundaries(for: range)
      let matches = try matchingEntries(in: entries, range: range, scope: scope)
      let hasNoBowelMovementDay = completions.contains {
        let day = calendar.startOfDay(for: $0.day)
        return $0.answer == .noBowelMovement && day >= boundaries.start && day < boundaries.end
      }
      guard !matches.isEmpty || (scope == .allEntries && hasNoBowelMovementDay) else {
        return scope == .allEntries ? .noEntries : .noMarkedEntries
      }
      guard matches.filter({ $0.photoState.hasExpectedPhoto }).count <= 50 else { return .tooManyPhotos }
      guard matches.allSatisfy(photoStateIsInternallyConsistent) else { return .photoIntegrity }
      return nil
    } catch let error as JournalExportValidationError {
      return error
    } catch {
      return .startAfterEnd
    }
  }

  public func build(
    range: JournalExportRange,
    scope: JournalExportScope,
    entries: [JournalExportEntry],
    completions: [DailyCompletionSnapshot],
    treatmentMarkers: [JournalTreatmentMarker],
    generatedAt: Date
  ) throws -> JournalExportSnapshot {
    let boundaries = try boundaries(for: range)
    let matches = try matchingEntries(in: entries, range: range, scope: scope)
    let hasNoBowelMovementDay = completions.contains {
      let day = calendar.startOfDay(for: $0.day)
      return $0.answer == .noBowelMovement && day >= boundaries.start && day < boundaries.end
    }
    if matches.isEmpty && !(scope == .allEntries && hasNoBowelMovementDay) {
      throw scope == .allEntries ? JournalExportValidationError.noEntries : JournalExportValidationError.noMarkedEntries
    }
    if matches.filter({ $0.photoState.hasExpectedPhoto }).count > 50 { throw JournalExportValidationError.tooManyPhotos }
    guard matches.allSatisfy(photoStateIsInternallyConsistent) else {
      throw JournalExportValidationError.photoIntegrity
    }

    let markers = treatmentMarkers.filter {
      $0.effectiveDate >= boundaries.start && $0.effectiveDate < boundaries.end
    }.sorted {
      if $0.effectiveDate == $1.effectiveDate { return $0.id.uuidString < $1.id.uuidString }
      return $0.effectiveDate < $1.effectiveDate
    }

    let summary: JournalRecordedDataSummary?
    if scope == .allEntries {
      let confirmed = matches.compactMap(\.confirmedBristolType).filter { (1...7).contains($0) }
      let completeDays = Set(completions.filter {
        ($0.answer == .yes || $0.answer == .noBowelMovement)
          && calendar.startOfDay(for: $0.day) >= boundaries.start
          && calendar.startOfDay(for: $0.day) < boundaries.end
      }.map { calendar.startOfDay(for: $0.day) })
      let entriesOnCompleteDays = matches.filter { completeDays.contains(calendar.startOfDay(for: $0.capturedAt)) }.count
      summary = JournalRecordedDataSummary(
        entryCount: matches.count,
        confirmedTypeCount: confirmed.count,
        type1To2Count: confirmed.filter { (1...2).contains($0) }.count,
        type3To5Count: confirmed.filter { (3...5).contains($0) }.count,
        type6To7Count: confirmed.filter { (6...7).contains($0) }.count,
        mixedFormConfirmedCount: matches.filter { $0.mixedForm == .yes }.count,
        completeDays: completeDays.count,
        totalDays: boundaries.dayCount,
        entriesOnCompleteDays: entriesOnCompleteDays,
        completeDayFrequency: completeDays.isEmpty ? nil : Double(entriesOnCompleteDays) / Double(completeDays.count)
      )
    } else {
      summary = nil
    }

    let noBowelMovementDays = scope == .allEntries ? completions.compactMap { completion -> Date? in
      let day = calendar.startOfDay(for: completion.day)
      guard completion.answer == .noBowelMovement,
        day >= boundaries.start,
        day < boundaries.end
      else { return nil }
      return day
    }.sorted() : []

    return JournalExportSnapshot(
      range: range,
      startOfFirstDay: boundaries.start,
      startAfterLastDay: boundaries.end,
      timeZoneIdentifier: timeZone.identifier,
      generatedAt: generatedAt,
      scope: scope,
      entries: matches,
      treatmentMarkers: markers,
      noBowelMovementDays: noBowelMovementDays,
      recordedDataSummary: summary
    )
  }

  private func photoStateIsInternallyConsistent(_ entry: JournalExportEntry) -> Bool {
    switch entry.photoState {
    case .noPhoto:
      return entry.photoSHA256 == nil
    case .unavailable:
      return false
    case .available(let filename):
      guard filename == "\(entry.id.uuidString).jpg",
        let hash = entry.photoSHA256,
        hash.count == 64,
        hash == hash.lowercased(),
        hash.allSatisfy(\.isHexDigit)
      else { return false }
      return true
    }
  }
}
