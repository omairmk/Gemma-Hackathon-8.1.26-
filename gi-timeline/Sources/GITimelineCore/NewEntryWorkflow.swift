import Foundation

public struct DraftReference: Equatable, Sendable {
  public let id: UUID
  public let path: String
  public let sha256: String
  public init(id: UUID = UUID(), path: String, sha256: String) { self.id = id; self.path = path; self.sha256 = sha256 }
}

/// Platform-neutral state machine. UI code owns I/O; this owns only identity and locks.
public struct NewEntryWorkflow: Sendable {
  public private(set) var draft: DraftReference?
  public private(set) var preparationID: UUID?
  public private(set) var activeAttemptID: UUID?
  public private(set) var engineAttemptID: UUID?
  public private(set) var engineIsRunning = false
  public private(set) var saveIsRunning = false
  public private(set) var analysisWasTimedOut = false

  public init() {}
  public var isDraftReady: Bool { draft != nil && preparationID == nil }
  public var isLocked: Bool { preparationID != nil || engineIsRunning || saveIsRunning }
  public var canAnalyze: Bool { isDraftReady && !engineIsRunning && !saveIsRunning }
  public var canSave: Bool { isDraftReady && !engineIsRunning && !saveIsRunning }
  public var canReplaceOrClear: Bool { !isLocked }

  @discardableResult public mutating func beginPreparation() -> UUID { let id = UUID(); preparationID = id; return id }
  /// Returns the old draft only when a current preparation successfully replaces it.
  public mutating func finishPreparation(_ id: UUID, prepared: DraftReference) -> DraftReference? {
    guard preparationID == id else { return nil }
    let old = draft; draft = prepared; preparationID = nil; activeAttemptID = nil; analysisWasTimedOut = false; return old
  }
  public mutating func failPreparation(_ id: UUID) { if preparationID == id { preparationID = nil } }
  @discardableResult public mutating func beginAttempt() -> UUID? {
    guard canAnalyze else { return nil }; let id = UUID(); activeAttemptID = id; engineAttemptID = id; engineIsRunning = true; analysisWasTimedOut = false; return id
  }
  public mutating func timeoutAttempt(_ id: UUID) { if activeAttemptID == id { activeAttemptID = nil; analysisWasTimedOut = true } }
  public mutating func finishAttempt(_ id: UUID) -> Bool {
    guard engineAttemptID == id else { return false }
    engineAttemptID = nil
    let current = activeAttemptID == id
    engineIsRunning = false
    if current { activeAttemptID = nil }
    return current && !analysisWasTimedOut
  }
  public mutating func beginSave() -> Bool { guard canSave else { return false }; saveIsRunning = true; return true }
  public mutating func finishSave() { saveIsRunning = false }
  public mutating func reset() { draft = nil; preparationID = nil; activeAttemptID = nil; engineAttemptID = nil; engineIsRunning = false; saveIsRunning = false; analysisWasTimedOut = false }
}
