import XCTest
@testable import GITimelineCore

final class JournalExportTests: XCTestCase {
  private let timeZone = TimeZone(identifier: "America/New_York")!
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }
  private var builder: JournalExportBuilder { .init(calendar: calendar, timeZone: timeZone) }
  private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

  func testInclusiveRangeAcrossDSTIncludesBothFullLocalDays() throws {
    let range = JournalExportRange(from: date("2024-03-09T17:00:00Z"), through: date("2024-03-10T16:00:00Z"))
    let boundaries = try builder.boundaries(for: range)
    XCTAssertEqual(boundaries.dayCount, 2)
    XCTAssertEqual(boundaries.end.timeIntervalSince(boundaries.start), 47 * 3_600)

    let atStart = JournalExportEntry(id: UUID(), capturedAt: boundaries.start, confirmedBristolType: 4)
    let atLastMoment = JournalExportEntry(id: UUID(), capturedAt: boundaries.end.addingTimeInterval(-0.001), confirmedBristolType: 5)
    let atEnd = JournalExportEntry(id: UUID(), capturedAt: boundaries.end, confirmedBristolType: 6)
    XCTAssertEqual(try builder.matchingEntries(in: [atEnd, atLastMoment, atStart], range: range, scope: .allEntries).map(\.id), [atStart.id, atLastMoment.id])
  }

  func testAllAndMarkedFilteringIsStableAndDoesNotMutateMarks() throws {
    let range = JournalExportRange(from: date("2024-01-01T15:00:00Z"), through: date("2024-01-02T15:00:00Z"))
    let later = JournalExportEntry(id: UUID(), capturedAt: date("2024-01-02T13:00:00Z"), confirmedBristolType: 6)
    let markedDate = date("2024-01-01T16:00:00Z")
    let earlierMarked = JournalExportEntry(id: UUID(), capturedAt: date("2024-01-01T14:00:00Z"), confirmedBristolType: 4, markedForDiscussionAt: markedDate)
    let all = try builder.matchingEntries(in: [later, earlierMarked], range: range, scope: .allEntries)
    let marked = try builder.matchingEntries(in: [later, earlierMarked], range: range, scope: .markedForDiscussion)
    XCTAssertEqual(all.map(\.id), [earlierMarked.id, later.id])
    XCTAssertEqual(marked.map(\.id), [earlierMarked.id])
    XCTAssertEqual(marked.first?.markedForDiscussionAt, markedDate)
  }

  func testRangeValidationAndDefaultRangeUseInclusiveLocalDays() throws {
    let today = date("2024-11-03T17:00:00Z")
    let defaultRange = builder.defaultRange(today: today)
    XCTAssertEqual(try builder.boundaries(for: defaultRange).dayCount, 14)
    for (preset, expectedDays) in [
      (JournalExportPreset.sevenDays, 7),
      (.fourteenDays, 14),
      (.thirtyDays, 30),
    ] {
      let range = try XCTUnwrap(builder.range(for: preset, endingOn: today))
      XCTAssertEqual(try builder.boundaries(for: range).dayCount, expectedDays)
      XCTAssertEqual(calendar.startOfDay(for: range.through), calendar.startOfDay(for: today))
    }
    XCTAssertNil(builder.range(for: .custom, endingOn: today))
    let start = calendar.startOfDay(for: today)
    let day31 = calendar.date(byAdding: .day, value: 30, to: start)!
    let day32 = calendar.date(byAdding: .day, value: 31, to: start)!
    XCTAssertEqual(try builder.boundaries(for: .init(from: start, through: day31)).dayCount, 31)
    XCTAssertThrowsError(try builder.boundaries(for: .init(from: start, through: day32))) { XCTAssertEqual($0 as? JournalExportValidationError, .rangeTooLong) }
    XCTAssertThrowsError(try builder.boundaries(for: .init(from: day31, through: start))) { XCTAssertEqual($0 as? JournalExportValidationError, .startAfterEnd) }
  }

  func testPhotoIntegrityAppliesOnlyToSelectedEntriesAndRejectsPartialTuples() throws {
    let day = calendar.startOfDay(for: date("2024-01-03T15:00:00Z"))
    let range = JournalExportRange(from: day, through: day)
    let selectedID = UUID()
    let selected = JournalExportEntry(
      id: selectedID,
      capturedAt: day,
      confirmedBristolType: 4,
      markedForDiscussionAt: day,
      photoState: .available(filename: "\(selectedID.uuidString).jpg"),
      photoSHA256: String(repeating: "a", count: 64)
    )
    let unselectedUnavailable = JournalExportEntry(
      id: UUID(),
      capturedAt: day,
      confirmedBristolType: 6,
      photoState: .unavailable
    )
    let snapshot = try builder.build(
      range: range,
      scope: .markedForDiscussion,
      entries: [selected, unselectedUnavailable],
      completions: [],
      treatmentMarkers: [],
      generatedAt: day
    )
    XCTAssertEqual(snapshot.entries.map(\.id), [selectedID])

    let partial = JournalExportEntry(
      id: UUID(),
      capturedAt: day,
      confirmedBristolType: 4,
      photoState: .noPhoto,
      photoSHA256: String(repeating: "b", count: 64)
    )
    XCTAssertEqual(builder.validate(range: range, scope: .allEntries, entries: [partial]), .photoIntegrity)
    XCTAssertThrowsError(
      try builder.build(
        range: range,
        scope: .allEntries,
        entries: [partial],
        completions: [],
        treatmentMarkers: [],
        generatedAt: day
      )
    ) { error in
      XCTAssertEqual(error as? JournalExportValidationError, .photoIntegrity)
    }
  }

  func testMarkedSnapshotHasNoFullPeriodAggregateAndPhotoLimitIsExplicit() throws {
    let start = calendar.startOfDay(for: date("2024-01-01T15:00:00Z"))
    let range = JournalExportRange(from: start, through: start)
    let entries = (0..<51).map { index in
      let id = UUID()
      return JournalExportEntry(
        id: id,
        capturedAt: start.addingTimeInterval(Double(index)),
        confirmedBristolType: 4,
        markedForDiscussionAt: start,
        photoState: .available(filename: "\(id.uuidString).jpg"),
        photoSHA256: String(repeating: "0", count: 64)
      )
    }
    XCTAssertEqual(builder.validate(range: range, scope: .markedForDiscussion, entries: entries), .tooManyPhotos)
    let one = Array(entries.prefix(1))
    let snapshot = try builder.build(range: range, scope: .markedForDiscussion, entries: one, completions: [], treatmentMarkers: [], generatedAt: start)
    XCTAssertNil(snapshot.recordedDataSummary)
    XCTAssertEqual(snapshot.entries.count, 1)
  }

  func testEmptyScopeMessagesAreDifferentAndSnapshotSurfaceHasNoTechnicalFields() throws {
    let start = calendar.startOfDay(for: date("2024-01-01T15:00:00Z"))
    let range = JournalExportRange(from: start, through: start)
    let unmarked = JournalExportEntry(id: UUID(), capturedAt: start, confirmedBristolType: 4, note: "Visible note")
    XCTAssertEqual(builder.validate(range: range, scope: .markedForDiscussion, entries: [unmarked]), .noMarkedEntries)
    XCTAssertEqual(builder.validate(range: range, scope: .allEntries, entries: []), .noEntries)

    let snapshot = try builder.build(range: range, scope: .allEntries, entries: [unmarked], completions: [], treatmentMarkers: [], generatedAt: start)
    let labels = Mirror(reflecting: snapshot.entries[0]).children.compactMap(\.label).joined(separator: " ")
    for forbidden in ["JSON", "prompt", "pipeline", "model"] {
      XCTAssertFalse(labels.localizedCaseInsensitiveContains(forbidden))
    }
  }

  func testNoBowelMovementDayCanProduceAnAllEntriesSnapshotWithoutBowelMovements() throws {
    let day = calendar.startOfDay(for: date("2024-01-03T15:00:00Z"))
    let range = JournalExportRange(from: day, through: day)
    let completions = [DailyCompletionSnapshot(day: day, answer: .noBowelMovement)]

    XCTAssertNil(
      builder.validate(
        range: range,
        scope: .allEntries,
        entries: [],
        completions: completions
      )
    )
    XCTAssertEqual(
      builder.validate(
        range: range,
        scope: .markedForDiscussion,
        entries: [],
        completions: completions
      ),
      .noMarkedEntries
    )

    let snapshot = try builder.build(
      range: range,
      scope: .allEntries,
      entries: [],
      completions: completions,
      treatmentMarkers: [],
      generatedAt: day
    )
    XCTAssertTrue(snapshot.entries.isEmpty)
    XCTAssertEqual(snapshot.noBowelMovementDays, [day])
    XCTAssertEqual(snapshot.recordedDataSummary?.entryCount, 0)
    XCTAssertEqual(snapshot.recordedDataSummary?.completeDays, 1)
    XCTAssertEqual(snapshot.recordedDataSummary?.completeDayFrequency, 0)

    XCTAssertThrowsError(
      try builder.build(
        range: range,
        scope: .markedForDiscussion,
        entries: [],
        completions: completions,
        treatmentMarkers: [],
        generatedAt: day
      )
    ) { error in
      XCTAssertEqual(error as? JournalExportValidationError, .noMarkedEntries)
    }
  }
}
