import XCTest
@testable import GITimelineCore

final class PhotoSuggestionV2Tests: XCTestCase {
  private let valid = """
  {"schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":4,"form":"smooth_formed","mixed_form":"no","apparent_color":"brown","red_appearing_material":"no","black_appearance":"no","black_tarry_appearance":"no"}
  """

  func testStrictElevenKeySchemaRoundTrips() throws {
    let parsed = try PhotoSuggestionPayloadV2Parser.parse(valid)
    XCTAssertEqual(parsed.blackAppearance, .no)
    XCTAssertEqual(parsed.blackTarryAppearance, .no)
    let canonical = try PhotoSuggestionPayloadV2Parser.canonicalJSON(parsed)
    XCTAssertEqual(try PhotoSuggestionPayloadV2Parser.parse(canonical), parsed)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: try XCTUnwrap(canonical.data(using: .utf8))
      ) as? [String: Any]
    )
    XCTAssertEqual(Set(object.keys), PhotoSuggestionPayloadV2Parser.expectedKeys)
    XCTAssertTrue(object["retake_reason"] is NSNull)
  }

  func testUnknownMissingAndDuplicateKeysFailClosed() {
    XCTAssertThrowsError(
      try PhotoSuggestionPayloadV2Parser.parse(
        valid.dropLast() + ",\"diagnosis\":\"none\"}"
      )
    )
    XCTAssertThrowsError(
      try PhotoSuggestionPayloadV2Parser.parse(
        valid.replacingOccurrences(of: "\"black_appearance\":\"no\",", with: "")
      )
    )
    XCTAssertThrowsError(
      try PhotoSuggestionPayloadV2Parser.parse(
        valid.dropLast() + ",\"black_appearance\":\"yes\"}"
      )
    ) {
      XCTAssertEqual($0 as? ObservationParserError, .invalidJSON)
    }
  }

  func testBlackAndTarryAnswersAreIndependentAcrossAllNineCombinations() throws {
    for black in ["yes", "no", "not_sure"] {
      for tarry in ["yes", "no", "not_sure"] {
        let raw = valid
          .replacingOccurrences(
            of: "\"black_appearance\":\"no\"",
            with: "\"black_appearance\":\"\(black)\""
          )
          .replacingOccurrences(
            of: "\"black_tarry_appearance\":\"no\"",
            with: "\"black_tarry_appearance\":\"\(tarry)\""
          )
        let parsed = try PhotoSuggestionPayloadV2Parser.parse(raw)
        XCTAssertEqual(parsed.blackAppearance.rawValue, black)
        XCTAssertEqual(parsed.blackTarryAppearance.rawValue, tarry)
      }
    }
  }

  func testUnusableMustFullyAbstainButUsableNonStoolKeepsAppearance() throws {
    let technical = PhotoSuggestionPayloadV2.technicalAbstention(reason: .tooDark)
    let canonical = try PhotoSuggestionPayloadV2Parser.canonicalJSON(technical)
    XCTAssertEqual(try PhotoSuggestionPayloadV2Parser.parse(canonical), technical)

    for presence in ["non_stool", "uncertain"] {
      let validAbstention = """
      {"schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"\(presence)","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":"red_appearing","red_appearing_material":"yes","black_appearance":"yes","black_tarry_appearance":"no"}
      """
      XCTAssertNoThrow(try PhotoSuggestionPayloadV2Parser.parse(validAbstention))
      XCTAssertThrowsError(
        try PhotoSuggestionPayloadV2Parser.parse(
          validAbstention.replacingOccurrences(
            of: "\"bristol_type\":null",
            with: "\"bristol_type\":4"
          )
        )
      )
    }
  }

  func testHistoricalV1RemainsDistinctAndReadable() throws {
    let historical = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":4,"form":"smooth_formed","mixed_form":"no","apparent_color":"brown","red_appearing_material":"no","black_tarry_appearance":"yes"}
    """
    XCTAssertEqual(
      try FullPrefillPhotoSuggestionV1Parser.parse(historical)
        .blackTarryAppearance,
      .yes
    )
    XCTAssertThrowsError(try PhotoSuggestionPayloadV2Parser.parse(historical))
  }

  func testAppearancePrefillFlagPreservesCompleteTriState() {
    XCTAssertEqual(PhotoSuggestionAnswer.yes.appearancePrefillFlag, .yes)
    XCTAssertEqual(PhotoSuggestionAnswer.no.appearancePrefillFlag, .no)
    XCTAssertEqual(PhotoSuggestionAnswer.notSure.appearancePrefillFlag, .unsure)
  }

  func testAppearanceSuggestionCopyIsExactForYesNoAndNotSure() {
    XCTAssertEqual(
      PhotoAppearanceSuggestionCopy.redBloodLike(.yes),
      "AI suggestion: Possible blood-like red material is visible."
    )
    XCTAssertEqual(
      PhotoAppearanceSuggestionCopy.redBloodLike(.no),
      "AI suggestion: No blood-like red material detected in this photo."
    )
    XCTAssertEqual(
      PhotoAppearanceSuggestionCopy.redBloodLike(.unsure),
      "AI suggestion: Unable to determine whether blood-like red material is visible."
    )
    XCTAssertEqual(
      PhotoAppearanceSuggestionCopy.blackOrTarry(.yes),
      "AI suggestion: Possible black or tar-like appearance is visible."
    )
    XCTAssertEqual(
      PhotoAppearanceSuggestionCopy.blackOrTarry(.no),
      "AI suggestion: No black or tar-like appearance detected in this photo."
    )
    XCTAssertEqual(
      PhotoAppearanceSuggestionCopy.blackOrTarry(.unsure),
      "AI suggestion: Unable to determine whether a black or tar-like appearance is visible."
    )
  }
}
