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
  public private(set) var manualEntryActive = false

  public init() {}
  public var isDraftReady: Bool { draft != nil && preparationID == nil }
  public var hasEntrySource: Bool { isDraftReady || manualEntryActive }
  public var isLocked: Bool { preparationID != nil || engineIsRunning || saveIsRunning }
  public var canAnalyze: Bool { isDraftReady && !manualEntryActive && !engineIsRunning && !saveIsRunning }
  public var canSave: Bool { hasEntrySource && !engineIsRunning && !saveIsRunning }
  public var canReplaceOrClear: Bool { !isLocked }

  @discardableResult public mutating func beginPreparation() -> UUID { let id = UUID(); preparationID = id; return id }
  /// Returns the old draft only when a current preparation successfully replaces it.
  public mutating func finishPreparation(_ id: UUID, prepared: DraftReference) -> DraftReference? {
    guard preparationID == id else { return nil }
    let old = draft; draft = prepared; manualEntryActive = false; preparationID = nil; activeAttemptID = nil; analysisWasTimedOut = false; return old
  }
  public mutating func failPreparation(_ id: UUID) { if preparationID == id { preparationID = nil } }
  /// Activates manual review either with a retained photo after inference
  /// failure, or as an intentional no-photo entry. When `keepingDraft` is
  /// false, UI code should capture and delete the old draft file before this
  /// transition if one exists.
  @discardableResult public mutating func beginManualEntry(keepingDraft: Bool) -> Bool {
    guard !isLocked else { return false }
    if !keepingDraft { draft = nil }
    manualEntryActive = true
    activeAttemptID = nil
    engineAttemptID = nil
    analysisWasTimedOut = false
    return true
  }
  @discardableResult public mutating func beginAttempt() -> UUID? {
    guard canAnalyze else { return nil }; let id = UUID(); activeAttemptID = id; engineAttemptID = id; engineIsRunning = true; analysisWasTimedOut = false; return id
  }
  public mutating func timeoutAttempt(_ id: UUID) { if activeAttemptID == id { activeAttemptID = nil; analysisWasTimedOut = true } }
  /// Abandons a timed-out engine attempt and immediately opens retained-draft
  /// manual entry. The platform layer must cancel its task; a late engine
  /// completion is stale because both attempt identities are revoked here.
  @discardableResult public mutating func timeoutAttemptAndBeginManualEntry(_ id: UUID, keepingDraft: Bool) -> Bool {
    guard activeAttemptID == id, engineAttemptID == id else { return false }
    activeAttemptID = nil
    engineAttemptID = nil
    engineIsRunning = false
    analysisWasTimedOut = true
    if !keepingDraft { draft = nil }
    manualEntryActive = true
    return true
  }
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
  public mutating func reset() { draft = nil; preparationID = nil; activeAttemptID = nil; engineAttemptID = nil; engineIsRunning = false; saveIsRunning = false; analysisWasTimedOut = false; manualEntryActive = false }
}
