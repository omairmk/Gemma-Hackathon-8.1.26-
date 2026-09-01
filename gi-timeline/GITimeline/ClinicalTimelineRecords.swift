import Foundation
import SwiftData
import GITimelineCore

@Model final class DailyCompletionRecord {
  @Attribute(.unique) var dayKey: String
  var dayStart: Date
  var answerRawValue: String
  var createdAt: Date
  var updatedAt: Date

  init(dayKey: String, dayStart: Date, answer: DailyCompletionAnswer, now: Date = Date()) {
    self.dayKey = dayKey
    self.dayStart = dayStart
    self.answerRawValue = answer.rawValue
    self.createdAt = now
    self.updatedAt = now
  }

  var answer: DailyCompletionAnswer? { DailyCompletionAnswer(rawValue: answerRawValue) }
  var snapshot: DailyCompletionSnapshot? {
    guard let answer else { return nil }
    let calculator = TreatmentResponseCalculator()
    return .init(day: calculator.localDayStart(forDayKey: dayKey) ?? dayStart, answer: answer)
  }
}

@Model final class TreatmentEventRecord {
  @Attribute(.unique) var id: UUID
  var effectiveDate: Date
  var kindRawValue: String
  var name: String
  var doseOrNote: String?
  var createdAt: Date
  var updatedAt: Date

  init(id: UUID = UUID(), effectiveDate: Date, kind: TreatmentEventKind, name: String, doseOrNote: String? = nil, now: Date = Date()) {
    self.id = id
    self.effectiveDate = effectiveDate
    self.kindRawValue = kind.rawValue
    self.name = name
    self.doseOrNote = doseOrNote
    self.createdAt = now
    self.updatedAt = now
  }

  var kind: TreatmentEventKind? { TreatmentEventKind(rawValue: kindRawValue) }
  var snapshot: TreatmentEventSnapshot? {
    kind.map { .init(id: id, kind: $0, name: name, doseOrNote: doseOrNote, effectiveDate: effectiveDate) }
  }
}

enum ClinicalTimelineStoreError: Error, LocalizedError, Equatable {
  case emptyTreatmentName
  case duplicateDailyCompletion
  case bowelMovementAlreadyRecorded

  var errorDescription: String? {
    switch self {
    case .emptyTreatmentName:
      return "Enter a name for the treatment change."
    case .duplicateDailyCompletion:
      return "GI Journal found more than one local daily answer for this day and left them unchanged."
    case .bowelMovementAlreadyRecorded:
      return "That date already has a bowel movement entry. No-bowel-movement was not recorded."
    }
  }
}

enum ClinicalTimelineStoreFailurePoint {
  case afterTreatmentUpdateBeforeSave
  case afterTreatmentDeleteBeforeSave
}

@MainActor final class ClinicalTimelineStore {
  typealias FailureInjector = (ClinicalTimelineStoreFailurePoint) throws -> Void

  private let context: ModelContext
  private let calculator: TreatmentResponseCalculator
  private let failureInjector: FailureInjector?
  private let writeGate: JournalWriteGate

  init(
    context: ModelContext,
    calendar: Calendar = .current,
    timeZone: TimeZone = .current,
    failureInjector: FailureInjector? = nil,
    writeGate: JournalWriteGate? = nil
  ) {
    self.context = context
    self.calculator = TreatmentResponseCalculator(calendar: calendar, timeZone: timeZone)
    self.failureInjector = failureInjector
    self.writeGate = writeGate ?? .app
    context.autosaveEnabled = false
  }

  /// A nil answer is the one supported representation of "Not answered" and
  /// removes any persisted answer for that local day.
  func setDailyCompletion(_ answer: DailyCompletionAnswer?, for date: Date, now: Date = Date()) throws {
    try writeGate.requireWritable()
    let key = calculator.dayKey(for: date)
    let descriptor = FetchDescriptor<DailyCompletionRecord>(predicate: #Predicate { $0.dayKey == key })
    let existing = try context.fetch(descriptor)
    // A unique key prevents this in a healthy current store. If a damaged or
    // legacy store nevertheless exposes duplicates, never choose one or
    // silently delete the others while answering a day.
    guard existing.count <= 1 else {
      throw ClinicalTimelineStoreError.duplicateDailyCompletion
    }
    do {
      if let answer {
        let record = existing.first ?? DailyCompletionRecord(dayKey: key, dayStart: calculator.localDayStart(for: date), answer: answer, now: now)
        if existing.isEmpty { context.insert(record) }
        record.dayStart = calculator.localDayStart(for: date)
        record.answerRawValue = answer.rawValue
        record.updatedAt = now
      } else {
        for record in existing { context.delete(record) }
      }
      try context.save()
      AppFolders.enforceStoreProtection(requireAllStoreFiles: true)
    } catch {
      context.rollback()
      throw error
    }
  }

  /// Adds or removes an explicit zero-event marker for one local calendar day.
  /// A legacy yes/no answer is never interpreted as zero automatically; an
  /// explicit user request to record no bowel movement replaces that older
  /// single-day answer. Removing a marker never deletes a legacy answer.
  func setNoBowelMovement(_ recorded: Bool, for date: Date, now: Date = Date()) throws {
    try writeGate.requireWritable()
    let start = calculator.localDayStart(for: date)
    guard let end = calculator.calendar.date(byAdding: .day, value: 1, to: start) else {
      throw CocoaError(.validationMissingMandatoryProperty)
    }
    if recorded {
      let entryDescriptor = FetchDescriptor<EntryRecord>(
        predicate: #Predicate { $0.capturedAt >= start && $0.capturedAt < end }
      )
      guard try context.fetchCount(entryDescriptor) == 0 else {
        throw ClinicalTimelineStoreError.bowelMovementAlreadyRecorded
      }
      try setDailyCompletion(.noBowelMovement, for: date, now: now)
    } else {
      let key = calculator.dayKey(for: date)
      let descriptor = FetchDescriptor<DailyCompletionRecord>(predicate: #Predicate { $0.dayKey == key })
      let existing = try context.fetch(descriptor)
      guard existing.count <= 1 else { throw ClinicalTimelineStoreError.duplicateDailyCompletion }
      guard existing.first?.answer == .noBowelMovement else { return }
      try setDailyCompletion(nil, for: date, now: now)
    }
  }

  @discardableResult
  func addTreatmentEvent(
    kind: TreatmentEventKind,
    name: String,
    doseOrNote: String?,
    effectiveDate: Date,
    now: Date = Date()
  ) throws -> TreatmentEventRecord {
    try writeGate.requireWritable()
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw ClinicalTimelineStoreError.emptyTreatmentName }
    let trimmedNote = doseOrNote?.trimmingCharacters(in: .whitespacesAndNewlines)
    let record = TreatmentEventRecord(
      effectiveDate: calculator.localDayStart(for: effectiveDate),
      kind: kind,
      name: trimmedName,
      doseOrNote: trimmedNote?.isEmpty == true ? nil : trimmedNote,
      now: now
    )
    context.insert(record)
    do {
      try context.save()
      AppFolders.enforceStoreProtection(requireAllStoreFiles: true)
      return record
    } catch {
      context.rollback()
      throw error
    }
  }

  @discardableResult
  func updateTreatmentEvent(
    _ record: TreatmentEventRecord,
    kind: TreatmentEventKind,
    name: String,
    doseOrNote: String?,
    effectiveDate: Date,
    now: Date = Date()
  ) throws -> TreatmentEventRecord {
    try writeGate.requireWritable()
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw ClinicalTimelineStoreError.emptyTreatmentName }
    let trimmedNote = doseOrNote?.trimmingCharacters(in: .whitespacesAndNewlines)

    do {
      record.kindRawValue = kind.rawValue
      record.name = trimmedName
      record.doseOrNote = trimmedNote?.isEmpty == true ? nil : trimmedNote
      record.effectiveDate = calculator.localDayStart(for: effectiveDate)
      record.updatedAt = now
      try failureInjector?(.afterTreatmentUpdateBeforeSave)
      try context.save()
      AppFolders.enforceStoreProtection(requireAllStoreFiles: true)
      return record
    } catch {
      context.rollback()
      throw error
    }
  }

  func deleteTreatmentEvent(_ record: TreatmentEventRecord) throws {
    try writeGate.requireWritable()
    do {
      context.delete(record)
      try failureInjector?(.afterTreatmentDeleteBeforeSave)
      try context.save()
      AppFolders.enforceStoreProtection(requireAllStoreFiles: true)
    } catch {
      context.rollback()
      throw error
    }
  }
}
