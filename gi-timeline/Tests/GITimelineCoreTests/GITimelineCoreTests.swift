import XCTest
@testable import GITimelineCore

final class GITimelineCoreTests: XCTestCase {
  private let valid = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
  private let unusable = "{\"image_usable\":false,\"quality_issue\":\"blurred\",\"apparent_bristol_type\":null,\"apparent_color\":\"unable_to_assess\",\"form\":\"unable_to_assess\",\"red_appearing_material\":\"unable_to_assess\",\"black_tarry_appearance\":\"unable_to_assess\"}"
  func testEmbeddedExampleValidates() throws { XCTAssertEqual(try ObservationParser.parse(valid).apparentColor, "brown") }
  func testAccidentalFenceIsStripped() throws { XCTAssertEqual(try ObservationParser.parse("```json\n\(valid)\n```").form, "smooth_formed") }
  func testUnknownKeyRejected() { XCTAssertThrowsError(try ObservationParser.parse(valid.dropLast() + ",\"extra\":1}")) { XCTAssertEqual($0 as? ObservationParserError, .unknownKeys(["extra"])) } }
  func testMissingKeyRejected() { XCTAssertThrowsError(try ObservationParser.parse(valid.replacingOccurrences(of: ",\"black_tarry_appearance\":\"not_observed\"", with: ""))) }
  func testInvalidEnumsAndBristolRangeRejected() {
    XCTAssertThrowsError(try ObservationParser.parse(valid.replacingOccurrences(of: "\"brown\"", with: "\"purple\"")))
    XCTAssertThrowsError(try ObservationParser.parse(valid.replacingOccurrences(of: ":4,", with: ":8,")))
  }
  func testCrossFieldRulesBothDirections() {
    XCTAssertThrowsError(try ObservationParser.parse(valid.replacingOccurrences(of: "\"none\"", with: "\"too_dark\"")))
    XCTAssertThrowsError(try ObservationParser.parse("{\"image_usable\":false,\"quality_issue\":\"blurred\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"mushy\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"))
    XCTAssertNoThrow(try ObservationParser.parse(unusable))
    XCTAssertThrowsError(try ObservationParser.parse(unusable.replacingOccurrences(of: "\"blurred\"", with: "\"none\"")))
  }
  func testSafetyRulesTruthTable() {
    let values: [SymptomFlag?] = [nil, .no, .unsure, .yes]
    for redBlood in values { for blackTarry in values { for dizziness in values { for severePain in values {
      let flags = [redBlood, blackTarry, dizziness, severePain]
      XCTAssertEqual(
        SafetyRules.shouldShow(redBlood: redBlood, blackTarry: blackTarry, dizziness: dizziness, severePain: severePain),
        flags.contains(.yes)
      )
    } } } }
  }
  func testEnablementRequiresPreparedDraftAndSaveLocksEveryMutation() {
    var state = NewEntryWorkflow()
    XCTAssertFalse(state.canAnalyze); XCTAssertFalse(state.canSave)
    let prep = state.beginPreparation(); XCTAssertTrue(state.isLocked)
    _ = state.finishPreparation(prep, prepared: .init(path: "/draft", sha256: "hash"))
    XCTAssertTrue(state.canAnalyze); XCTAssertTrue(state.canSave)
    XCTAssertTrue(state.beginSave()); XCTAssertFalse(state.canAnalyze); XCTAssertFalse(state.canSave); XCTAssertFalse(state.canReplaceOrClear)
    state.finishSave(); XCTAssertTrue(state.canSave)
  }
  func testTimeoutInvalidatesButKeepsLocksUntilCompletion() {
    var state = NewEntryWorkflow(); let prep = state.beginPreparation(); _ = state.finishPreparation(prep, prepared: .init(path: "/draft", sha256: "hash")); let attempt = state.beginAttempt()!
    state.timeoutAttempt(attempt); XCTAssertTrue(state.isLocked); XCTAssertFalse(state.canSave); XCTAssertFalse(state.finishAttempt(attempt)); XCTAssertTrue(state.canSave)
  }
  func testRetryAndStaleAttemptAreDistinct() {
    var state = NewEntryWorkflow(); let prep = state.beginPreparation(); _ = state.finishPreparation(prep, prepared: .init(path: "/draft", sha256: "hash")); let first = state.beginAttempt()!; XCTAssertTrue(state.finishAttempt(first)); let retry = state.beginAttempt()!; XCTAssertNotEqual(first, retry); XCTAssertFalse(state.finishAttempt(first)); XCTAssertTrue(state.isLocked); XCTAssertFalse(state.canSave); XCTAssertTrue(state.finishAttempt(retry))
  }
  func testOutOfOrderPreparationIsIgnored() {
    var state = NewEntryWorkflow(); let first = state.beginPreparation(); let second = state.beginPreparation(); XCTAssertNil(state.finishPreparation(first, prepared: .init(path: "/old", sha256: "a"))); XCTAssertNil(state.finishPreparation(second, prepared: .init(path: "/new", sha256: "b"))); XCTAssertEqual(state.draft?.path, "/new")
  }
  func testFailedReplacementKeepsPriorDraft() {
    var state = NewEntryWorkflow(); let first = state.beginPreparation(); _ = state.finishPreparation(first, prepared: .init(path: "/kept", sha256: "a"))
    let replacement = state.beginPreparation(); state.failPreparation(replacement)
    XCTAssertEqual(state.draft?.path, "/kept"); XCTAssertTrue(state.canSave)
  }
  func testSharedResetClearsAllEligibilityAndIdentity() {
    var state = NewEntryWorkflow(); let prep = state.beginPreparation(); _ = state.finishPreparation(prep, prepared: .init(path: "/draft", sha256: "hash")); _ = state.beginSave(); state.reset()
    XCTAssertNil(state.draft); XCTAssertNil(state.preparationID); XCTAssertNil(state.activeAttemptID); XCTAssertNil(state.engineAttemptID); XCTAssertFalse(state.isLocked); XCTAssertFalse(state.canSave)
  }
  func testCanonicalJSONRoundTrips() throws {
    for source in [valid, unusable] {
      let observation = try ObservationParser.parse(source)
      let canonical = try ObservationParser.canonicalJSON(observation)
      XCTAssertEqual(try ObservationParser.parse(canonical), observation)
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(canonical.utf8)) as? [String: Any])
      XCTAssertEqual(Set(object.keys), ObservationParser.expectedKeys)
    }
    XCTAssertTrue(try ObservationParser.canonicalJSON(ObservationParser.parse(unusable)).contains("\"apparent_bristol_type\":null"))
  }
}
