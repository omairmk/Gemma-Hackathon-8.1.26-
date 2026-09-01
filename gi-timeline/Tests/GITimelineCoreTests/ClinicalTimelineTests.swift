import XCTest
@testable import GITimelineCore

final class ClinicalTimelineTests: XCTestCase {
  private let timeZone = TimeZone(identifier: "America/New_York")!

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = timeZone
    return calendar
  }

  private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
  }

  func testConfirmedBristolProjectionIsExact() {
    XCTAssertEqual(ClinicalStoolForm(bristolType: 1).consistency, .hard)
    XCTAssertEqual(ClinicalStoolForm(bristolType: 2).consistency, .hard)
    XCTAssertEqual(ClinicalStoolForm(bristolType: 3).consistency, .formed)
    XCTAssertEqual(ClinicalStoolForm(bristolType: 4).consistency, .formed)
    XCTAssertEqual(ClinicalStoolForm(bristolType: 5).consistency, .soft)
    XCTAssertEqual(ClinicalStoolForm(bristolType: 6).consistency, .loose)
    XCTAssertEqual(ClinicalStoolForm(bristolType: 7).consistency, .watery)
    XCTAssertEqual(ClinicalStoolForm(bristolType: nil).consistency, .unableToAssess)
    XCTAssertEqual(ClinicalValidation.consistency(for: 4), .formed)
  }

  func testDayKeyReconstructsTheSelectedCalendarDateAfterTimeZoneChange() throws {
    let original = TreatmentResponseCalculator(calendar: calendar, timeZone: timeZone)
    let key = original.dayKey(for: date("2024-03-10T16:00:00Z"))
    XCTAssertEqual(key, "2024-03-10")

    var travelledCalendar = Calendar(identifier: .gregorian)
    travelledCalendar.locale = Locale(identifier: "en_US_POSIX")
    let travelledTimeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))
    travelledCalendar.timeZone = travelledTimeZone
    let travelled = TreatmentResponseCalculator(calendar: travelledCalendar, timeZone: travelledTimeZone)
    let reconstructed = try XCTUnwrap(travelled.localDayStart(forDayKey: key))

    XCTAssertEqual(travelled.dayKey(for: reconstructed), "2024-03-10")
    XCTAssertEqual(reconstructed, date("2024-03-10T10:00:00Z"))
    XCTAssertNil(travelled.localDayStart(forDayKey: "2024-02-30"))
    XCTAssertNil(travelled.localDayStart(forDayKey: "2024-2-03"))
  }

  func testManualWorkflowSupportsNoPhotoAndRetainedPhotoFallback() {
    var noPhoto = NewEntryWorkflow()
    XCTAssertTrue(noPhoto.beginManualEntry(keepingDraft: false))
    XCTAssertTrue(noPhoto.manualEntryActive)
    XCTAssertNil(noPhoto.draft)
    XCTAssertTrue(noPhoto.canSave)
    XCTAssertFalse(noPhoto.canAnalyze)

    var retained = NewEntryWorkflow()
    let preparation = retained.beginPreparation()
    let draft = DraftReference(path: "/retained.jpg", sha256: "hash")
    _ = retained.finishPreparation(preparation, prepared: draft)
    XCTAssertTrue(retained.beginManualEntry(keepingDraft: true))
    XCTAssertEqual(retained.draft, draft)
    XCTAssertTrue(retained.canSave)
    XCTAssertFalse(retained.canAnalyze)
    let replacement = retained.beginPreparation()
    let newDraft = DraftReference(path: "/replacement.jpg", sha256: "new")
    XCTAssertEqual(retained.finishPreparation(replacement, prepared: newDraft), draft)
    XCTAssertFalse(retained.manualEntryActive)
  }

  func testLegacyMixedFormCreatesOnlyInitialSuggestion() {
    let observation = VisualObservation(
      imageUsable: true,
      qualityIssue: "none",
      apparentBristolType: nil,
      apparentColor: "mixed",
      form: "mixed",
      redAppearingMaterial: "unable_to_assess",
      blackTarryAppearance: "unable_to_assess"
    )
    XCTAssertEqual(ClinicalValidation.initialMixedFormSuggestion(from: observation), .yes)
  }

  func testPainAndConditionalValidationAndClearing() {
    XCTAssertTrue(ClinicalValidation.validate(confirmedBristolType: 4, painScore: 0, mixedForm: .no, strainingOrIncomplete: .no, leakageOrAccident: nil).isEmpty)
    XCTAssertTrue(ClinicalValidation.validate(confirmedBristolType: 7, painScore: 10, mixedForm: .unsure, strainingOrIncomplete: nil, leakageOrAccident: .yes).isEmpty)
    XCTAssertTrue(ClinicalValidation.validate(confirmedBristolType: 4, painScore: -1, mixedForm: .no, strainingOrIncomplete: .no, leakageOrAccident: nil).contains(.invalidPainScore))
    XCTAssertTrue(ClinicalValidation.validate(confirmedBristolType: 7, painScore: 11, mixedForm: .no, strainingOrIncomplete: nil, leakageOrAccident: .no).contains(.invalidPainScore))
    XCTAssertTrue(ClinicalValidation.validate(confirmedBristolType: 5, painScore: nil, mixedForm: nil, strainingOrIncomplete: nil, leakageOrAccident: nil).isEmpty)
    XCTAssertTrue(ClinicalValidation.validate(confirmedBristolType: 6, painScore: nil, mixedForm: nil, strainingOrIncomplete: nil, leakageOrAccident: nil).isEmpty)
    XCTAssertTrue(ClinicalValidation.validate(confirmedBristolType: 5, painScore: nil, mixedForm: nil, strainingOrIncomplete: nil, leakageOrAccident: .yes).contains(.irrelevantLeakageOrAccident))

    var draft = ClinicalEntryDraft(confirmedBristolType: 4, strainingOrIncomplete: .yes, leakageOrAccident: nil)
    draft.updateConfirmedBristolType(6)
    XCTAssertNil(draft.strainingOrIncomplete)
    draft.leakageOrAccident = .yes
    draft.updateConfirmedBristolType(3)
    XCTAssertNil(draft.leakageOrAccident)
  }

  func testTreatmentWindowsUseLocalDaysAcrossDSTAndExcludeTransition() {
    let calculator = TreatmentResponseCalculator(calendar: calendar, timeZone: timeZone)
    let event = TreatmentEventSnapshot(id: UUID(), kind: .changedDose, name: "Synthetic", effectiveDate: date("2024-03-11T16:00:00Z"))
    let entryBefore = ClinicalEntrySnapshot(id: UUID(), capturedAt: date("2024-03-10T16:00:00Z"), confirmedBristolType: 4)
    let entryTransition = ClinicalEntrySnapshot(id: UUID(), capturedAt: date("2024-03-11T13:00:00Z"), confirmedBristolType: 6)
    let entryAfter = ClinicalEntrySnapshot(id: UUID(), capturedAt: date("2024-03-12T13:00:00Z"), confirmedBristolType: 7)
    let result = calculator.compare(event: event, entries: [entryBefore, entryTransition, entryAfter], completions: [], today: date("2024-03-13T16:00:00Z"))

    XCTAssertEqual(result.before.entriesRecorded, 1)
    XCTAssertEqual(result.transitionEntryCount, 1)
    XCTAssertEqual(result.after.entriesRecorded, 1)
    XCTAssertEqual(result.after.interval.totalDays, 2)
    XCTAssertTrue(result.after.interval.isPartial)
    XCTAssertNotEqual(result.before.interval.end.timeIntervalSince(result.before.interval.start), 7 * 86_400)
  }

  func testCompleteDayFrequencyUsesOnlyEntriesOnExplicitlyCompleteDaysIncludingZero() {
    let calculator = TreatmentResponseCalculator(calendar: calendar, timeZone: timeZone)
    let start = calendar.startOfDay(for: date("2024-11-02T16:00:00Z"))
    let end = calendar.date(byAdding: .day, value: 3, to: start)!
    let interval = LocalDayInterval(start: start, end: end, totalDays: 3, isPartial: false)
    let day1Entry = ClinicalEntrySnapshot(id: UUID(), capturedAt: calendar.date(byAdding: .hour, value: 12, to: start)!, confirmedBristolType: 4)
    let day2 = calendar.date(byAdding: .day, value: 1, to: start)!
    let day2Uncounted = ClinicalEntrySnapshot(id: UUID(), capturedAt: calendar.date(byAdding: .hour, value: 12, to: day2)!, confirmedBristolType: 6)
    let day3 = calendar.date(byAdding: .day, value: 2, to: start)!
    let summary = calculator.summarize(
      interval: interval,
      entries: [day1Entry, day2Uncounted],
      completions: [.init(day: start, answer: .yes), .init(day: day2, answer: .no), .init(day: day3, answer: .yes)]
    )
    XCTAssertEqual(summary.completeDays, 2)
    XCTAssertEqual(summary.entriesOnCompleteDays, 1)
    XCTAssertEqual(summary.completeDayFrequency, 0.5)
    XCTAssertEqual(summary.entryCountLabel, "Recorded bowel movements")
  }

  func testEmptySummaryHasNoNaNAndCountsCorrectionsFromConfirmedTypes() {
    let calculator = TreatmentResponseCalculator(calendar: calendar, timeZone: timeZone)
    let start = calendar.startOfDay(for: date("2024-01-01T12:00:00Z"))
    let interval = LocalDayInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!, totalDays: 1, isPartial: false)
    let empty = calculator.summarize(interval: interval, entries: [], completions: [])
    XCTAssertNil(empty.completeDayFrequency)
    XCTAssertNil(empty.bristolGroups.percentage(for: 0))
    XCTAssertEqual(empty.completeDayFrequencyLabel, "Insufficient complete-day data")

    let corrected = ClinicalEntrySnapshot(id: UUID(), capturedAt: start, confirmedBristolType: 6, suggestedBristolType: 4, hasOriginalAIObservation: true)
    let unconfirmed = ClinicalEntrySnapshot(id: UUID(), capturedAt: start, confirmedBristolType: nil, suggestedBristolType: 4)
    let aiAbstainedThenConfirmed = ClinicalEntrySnapshot(id: UUID(), capturedAt: start, confirmedBristolType: 5, suggestedBristolType: nil, hasOriginalAIObservation: true)
    let manual = ClinicalEntrySnapshot(id: UUID(), capturedAt: start, confirmedBristolType: 3, suggestedBristolType: nil)
    let summary = calculator.summarize(interval: interval, entries: [corrected, unconfirmed, aiAbstainedThenConfirmed, manual], completions: [])
    XCTAssertEqual(summary.bristolCorrectionCount, 2)
    XCTAssertEqual(summary.bristolGroups.denominator, 3)
  }
}
