import XCTest
@testable import GITimelineCore

final class PhotoSuggestionV1Tests: XCTestCase {
  private let valid = """
  {"schema_version":"gi-photo-v1","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":4,"mixed_form":"no","apparent_color":"brown","red_appearing_material":"no","black_tarry_appearance":"no"}
  """

  func testStrictSchemaParsesAndRoundTripsEveryRequiredKey() throws {
    let parsed = try PhotoSuggestionV1Parser.parse(valid)
    XCTAssertEqual(parsed.bristolType, 4)
    XCTAssertEqual(parsed.stoolPresence, .stool)
    XCTAssertEqual(parsed.redAppearingMaterial, .no)
    let canonical = try PhotoSuggestionV1Parser.canonicalJSON(parsed)
    XCTAssertEqual(try PhotoSuggestionV1Parser.parse(canonical), parsed)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: XCTUnwrap(canonical.data(using: .utf8))) as? [String: Any]
    )
    XCTAssertEqual(Set(object.keys), PhotoSuggestionV1Parser.expectedKeys)
    XCTAssertTrue(object["retake_reason"] is NSNull)
  }

  func testUnknownAndMissingKeysAreRejected() {
    XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse(valid.dropLast() + ",\"diagnosis\":\"none\"}")) {
      guard case ObservationParserError.unknownKeys(let keys) = $0 else {
        return XCTFail("Expected unknownKeys, got \($0)")
      }
      XCTAssertEqual(keys, ["diagnosis"])
    }
    XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse(
      valid.replacingOccurrences(of: "\"retake_reason\":null,", with: "")
    )) {
      guard case ObservationParserError.missingKeys(let keys) = $0 else {
        return XCTFail("Expected missingKeys, got \($0)")
      }
      XCTAssertEqual(keys, ["retake_reason"])
    }
  }

  func testDirectParseRejectsMarkdownFences() {
    XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse("```json\n\(valid)\n```")) {
      XCTAssertEqual($0 as? ObservationParserError, .invalidJSON)
    }
  }

  func testUnsupportedPlainRedApparentColorRemainsStrictlyRejected() {
    let unsupported = valid.replacingOccurrences(
      of: "\"apparent_color\":\"brown\"",
      with: "\"apparent_color\":\"red\""
    )
    XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse(unsupported)) {
      XCTAssertEqual(
        $0 as? ObservationParserError,
        .invalidValue("apparent_color")
      )
    }
  }

  func testDirectParseRejectsDuplicateSemanticKeys() {
    let objectPrefix = String(valid.dropLast())
    let duplicates = [
      objectPrefix + ",\"bristol_type\":5}",
      objectPrefix + ",\"red_appearing_material\":\"yes\"}",
      objectPrefix + ",\"black_tarry_appearance\":\"yes\"}",
      objectPrefix + ",\"\\u0062ristol_type\":4}",
    ]

    for duplicate in duplicates {
      XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse(duplicate)) {
        XCTAssertEqual($0 as? ObservationParserError, .invalidJSON)
      }
    }
  }

  func testUnusableNonStoolAndUncertainImagesMustAbstain() throws {
    let validUnusable = """
    {"schema_version":"gi-photo-v1","image_usable":false,"retake_reason":"too_dark","stool_presence":"uncertain","bristol_type":null,"mixed_form":"not_sure","apparent_color":null,"red_appearing_material":"not_sure","black_tarry_appearance":"not_sure"}
    """
    XCTAssertNoThrow(try PhotoSuggestionV1Parser.parse(validUnusable))

    for presence in ["stool", "non_stool"] {
      let invalidUnusable = """
      {"schema_version":"gi-photo-v1","image_usable":false,"retake_reason":"too_dark","stool_presence":"\(presence)","bristol_type":null,"mixed_form":"not_sure","apparent_color":null,"red_appearing_material":"not_sure","black_tarry_appearance":"not_sure"}
      """
      XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse(invalidUnusable))
    }

    for presence in ["non_stool", "uncertain"] {
      let invalid = """
      {"schema_version":"gi-photo-v1","image_usable":true,"retake_reason":null,"stool_presence":"\(presence)","bristol_type":4,"mixed_form":"no","apparent_color":"brown","red_appearing_material":"no","black_tarry_appearance":"no"}
      """
      XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse(invalid))
    }
  }

  func testCurrentRawOutputRejectsSubjectClassificationAsRetakeReasonButLegacyDecodeSurvives() throws {
    let legacy = """
    {"schema_version":"gi-photo-v1","image_usable":false,"retake_reason":"not_target_image","stool_presence":"uncertain","bristol_type":null,"mixed_form":"not_sure","apparent_color":null,"red_appearing_material":"not_sure","black_tarry_appearance":"not_sure"}
    """

    XCTAssertNoThrow(try PhotoSuggestionV1Parser.parse(legacy))
    XCTAssertThrowsError(try PhotoSuggestionV1Parser.parseCurrentRawOutput(legacy)) {
      XCTAssertEqual($0 as? ObservationParserError, .invalidValue("retake_reason"))
    }
  }

  func testCandidateMaterialVocabularyAcceptsYesNoAndNotSure() throws {
    XCTAssertNoThrow(try PhotoSuggestionV1Parser.parse(valid))
    let negative = try PhotoSuggestionV1Parser.parseConstrainedCandidateOutput(valid)
    XCTAssertEqual(negative.redAppearingMaterial, .no)
    XCTAssertEqual(negative.blackTarryAppearance, .no)

    let candidate = valid
      .replacingOccurrences(
        of: "\"red_appearing_material\":\"no\"",
        with: "\"red_appearing_material\":\"yes\""
      )
      .replacingOccurrences(
        of: "\"black_tarry_appearance\":\"no\"",
        with: "\"black_tarry_appearance\":\"not_sure\""
      )
    let parsed = try PhotoSuggestionV1Parser.parseConstrainedCandidateOutput(
      candidate
    )
    XCTAssertEqual(parsed.redAppearingMaterial, .yes)
    XCTAssertEqual(parsed.blackTarryAppearance, .notSure)
  }

  func testTechnicalAbstentionIsCanonicalAndFullyConservative() throws {
    for reason in [
      PhotoRetakeReason.tooDark, .glare, .blurred, .other,
    ] {
      let suggestion = PhotoSuggestionV1.technicalAbstention(reason: reason)
      XCTAssertFalse(suggestion.imageUsable)
      XCTAssertEqual(suggestion.retakeReason, reason)
      XCTAssertEqual(suggestion.stoolPresence, .uncertain)
      XCTAssertNil(suggestion.bristolType)
      XCTAssertNil(suggestion.apparentColor)
      XCTAssertEqual(suggestion.mixedForm, .notSure)
      XCTAssertEqual(suggestion.redAppearingMaterial, .notSure)
      XCTAssertEqual(suggestion.blackTarryAppearance, .notSure)
      let canonical = try PhotoSuggestionV1Parser.canonicalJSON(suggestion)
      XCTAssertEqual(
        try PhotoSuggestionV1Parser.parseConstrainedCandidateOutput(canonical),
        suggestion
      )
    }
  }

  func testWeakImageCannotMapToConfidentNo() {
    let invalid = """
    {"schema_version":"gi-photo-v1","image_usable":false,"retake_reason":"blurred","stool_presence":"uncertain","bristol_type":null,"mixed_form":"not_sure","apparent_color":null,"red_appearing_material":"no","black_tarry_appearance":"no"}
    """
    XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse(invalid))
  }

  func testMixedOrUncertainMorphologyDoesNotForceNearestBristolType() {
    for mixed in ["yes", "not_sure"] {
      let invalid = """
      {"schema_version":"gi-photo-v1","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":5,"mixed_form":"\(mixed)","apparent_color":"mixed","red_appearing_material":"not_sure","black_tarry_appearance":"not_sure"}
      """
      XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse(invalid))
    }

    let missingTypeForConfidentSingleForm = """
    {"schema_version":"gi-photo-v1","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":null,"mixed_form":"no","apparent_color":"brown","red_appearing_material":"no","black_tarry_appearance":"no"}
    """
    XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse(missingTypeForConfidentSingleForm))
  }

  func testRepairCannotInventUsabilityPresenceTypeOrMaterialAnswers() {
    let confident = suggestion()

    for original in [
      "{\"image_usable\":\"true\",\"stool_presence\":\"stool\",\"bristol_type\":4,\"mixed_form\":\"no\",\"apparent_color\":\"brown\",\"red_appearing_material\":\"no\",\"black_tarry_appearance\":\"no\",\"retake_reason\":null}",
      "{\"stool_presence\":\"stool\",\"bristol_type\":4,\"mixed_form\":\"no\",\"apparent_color\":\"brown\",\"red_appearing_material\":\"no\",\"black_tarry_appearance\":\"no\",\"retake_reason\":null}",
    ] {
      XCTAssertThrowsError(try PhotoSuggestionV1RepairPolicy.validate(originalRaw: original, repaired: confident))
    }

    let repairedStool = suggestion()
    for original in [
      "{\"image_usable\":true,\"bristol_type\":4,\"mixed_form\":\"no\",\"apparent_color\":\"brown\",\"red_appearing_material\":\"no\",\"black_tarry_appearance\":\"no\",\"retake_reason\":null}",
      "{\"image_usable\":true,\"stool_presence\":\"invalid\",\"bristol_type\":4,\"mixed_form\":\"no\",\"apparent_color\":\"brown\",\"red_appearing_material\":\"no\",\"black_tarry_appearance\":\"no\",\"retake_reason\":null}",
      "{\"image_usable\":true,\"stool_presence\":\"uncertain\",\"bristol_type\":4,\"mixed_form\":\"no\",\"apparent_color\":\"brown\",\"red_appearing_material\":\"no\",\"black_tarry_appearance\":\"no\",\"retake_reason\":null}",
    ] {
      XCTAssertThrowsError(try PhotoSuggestionV1RepairPolicy.validate(originalRaw: original, repaired: repairedStool))
    }

    let repairedType = suggestion(bristolType: 4)
    for original in [
      "{\"image_usable\":true,\"stool_presence\":\"stool\",\"bristol_type\":true,\"mixed_form\":\"no\",\"apparent_color\":\"brown\",\"red_appearing_material\":\"no\",\"black_tarry_appearance\":\"no\",\"retake_reason\":null}",
      "{\"image_usable\":true,\"stool_presence\":\"stool\",\"bristol_type\":4.5,\"mixed_form\":\"no\",\"apparent_color\":\"brown\",\"red_appearing_material\":\"no\",\"black_tarry_appearance\":\"no\",\"retake_reason\":null}",
    ] {
      XCTAssertThrowsError(try PhotoSuggestionV1RepairPolicy.validate(originalRaw: original, repaired: repairedType))
    }
  }

  func testRepairAllowsOnlyConservativeAbstentionForMissingSemanticFields() {
    let repaired = suggestion(
      imageUsable: false,
      retakeReason: .other,
      stoolPresence: .uncertain,
      bristolType: nil,
      mixedForm: .notSure,
      apparentColor: nil,
      red: .notSure,
      black: .notSure
    )
    XCTAssertNoThrow(
      try PhotoSuggestionV1RepairPolicy.validate(
        originalRaw: "{\"schema_version\":\"gi-photo-v1\"}",
        repaired: repaired
      )
    )
  }

  func testFencedSerializationRepairMayPreserveExactSemantics() throws {
    let repaired = try PhotoSuggestionV1Parser.parse(valid)
    let fenced = "```json\n\(valid)\n```"
    XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse(fenced))
    XCTAssertNoThrow(
      try PhotoSuggestionV1RepairPolicy.validate(originalRaw: fenced, repaired: repaired)
    )
  }

  func testSingleProseWrappedObjectMayReceiveSerializationOnlyRepair() throws {
    let repaired = try PhotoSuggestionV1Parser.parse(valid)
    let wrapped = "Here is the requested object:\n\(valid)\nDone."
    XCTAssertThrowsError(try PhotoSuggestionV1Parser.parse(wrapped))
    XCTAssertNoThrow(
      try PhotoSuggestionV1RepairPolicy.validate(originalRaw: wrapped, repaired: repaired)
    )

    let changed = suggestion(bristolType: 5)
    XCTAssertThrowsError(
      try PhotoSuggestionV1RepairPolicy.validate(originalRaw: wrapped, repaired: changed)
    )
  }

  func testSerializationRepairRejectsDuplicateSemanticKeys() throws {
    let repaired = try PhotoSuggestionV1Parser.parse(valid)
    let objectPrefix = String(valid.dropLast())
    let duplicates = [
      objectPrefix + ",\"bristol_type\":4}",
      objectPrefix + ",\"red_appearing_material\":\"no\"}",
      objectPrefix + ",\"black_tarry_appearance\":\"no\"}",
      objectPrefix + ",\"\\u0062ristol_type\":4}",
    ]

    for duplicate in duplicates {
      XCTAssertThrowsError(
        try PhotoSuggestionV1RepairPolicy.validate(
          originalRaw: "Prose before \(duplicate) prose after",
          repaired: repaired
        )
      )
    }
  }

  func testSerializationRepairRejectsZeroMultipleAndMalformedObjects() throws {
    let repaired = try PhotoSuggestionV1Parser.parse(valid)
    for original in [
      "No JSON was returned.",
      "\(valid)\n\(valid)",
      "Before {\"schema_version\":\"gi-photo-v1\" after",
      "Before } \(valid)",
    ] {
      XCTAssertThrowsError(
        try PhotoSuggestionV1RepairPolicy.validate(originalRaw: original, repaired: repaired),
        "Unexpected repair acceptance for: \(original)"
      )
    }
  }

  func testRepairCannotChangeRecognizedRetakeReason() {
    let original = """
    {"schema_version":"gi-photo-v1","image_usable":false,"retake_reason":"too_dark","stool_presence":"uncertain","bristol_type":null,"mixed_form":"not_sure","apparent_color":null,"red_appearing_material":"not_sure","black_tarry_appearance":"not_sure"}
    """
    let changed = suggestion(
      imageUsable: false,
      retakeReason: .blurred,
      stoolPresence: .uncertain,
      bristolType: nil,
      mixedForm: .notSure,
      apparentColor: nil,
      red: .notSure,
      black: .notSure
    )
    let exact = suggestion(
      imageUsable: false,
      retakeReason: .tooDark,
      stoolPresence: .uncertain,
      bristolType: nil,
      mixedForm: .notSure,
      apparentColor: nil,
      red: .notSure,
      black: .notSure
    )
    XCTAssertNoThrow(try PhotoSuggestionV1RepairPolicy.validate(originalRaw: original, repaired: exact))
    XCTAssertThrowsError(try PhotoSuggestionV1RepairPolicy.validate(originalRaw: original, repaired: changed))
  }

  func testRawSuggestionMapsConservativelyIntoLegacyReviewPresentation() throws {
    let stored = try StoredModelVisualSuggestion.parse(valid)
    XCTAssertEqual(stored.visualObservation.apparentBristolType, 4)
    XCTAssertEqual(stored.visualObservation.form, "smooth_formed")
    XCTAssertEqual(stored.mixedFormSuggestion, .no)

    let nonStool = try StoredModelVisualSuggestion.parse("""
    {"schema_version":"gi-photo-v1","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"mixed_form":"not_sure","apparent_color":null,"red_appearing_material":"not_sure","black_tarry_appearance":"not_sure"}
    """)
    XCTAssertFalse(nonStool.visualObservation.imageUsable)
    XCTAssertEqual(nonStool.visualObservation.qualityIssue, "not_target_image")
    XCTAssertNil(nonStool.visualObservation.apparentBristolType)
  }

  func testFullPrefillSchemaRoundTripsEveryEditablePhotoField() throws {
    let raw = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":5,"form":"soft_blobs","mixed_form":"no","apparent_color":"dark_brown","red_appearing_material":"yes","black_tarry_appearance":"not_sure"}
    """
    let suggestion = try FullPrefillPhotoSuggestionV1Parser.parse(raw)
    XCTAssertEqual(suggestion.stoolPresence, .stool)
    XCTAssertEqual(suggestion.bristolType, 5)
    XCTAssertEqual(suggestion.form, "soft_blobs")
    XCTAssertEqual(suggestion.mixedForm, .no)
    XCTAssertEqual(suggestion.apparentColor, "dark_brown")
    XCTAssertEqual(suggestion.redAppearingMaterial, .yes)
    XCTAssertEqual(suggestion.blackTarryAppearance, .notSure)

    let canonical = try FullPrefillPhotoSuggestionV1Parser.canonicalJSON(suggestion)
    XCTAssertEqual(try FullPrefillPhotoSuggestionV1Parser.parse(canonical), suggestion)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: XCTUnwrap(canonical.data(using: .utf8))
      ) as? [String: Any]
    )
    XCTAssertEqual(Set(object.keys), FullPrefillPhotoSuggestionV1Parser.expectedKeys)
    XCTAssertEqual(object.count, 10)
  }

  func testDependentFieldNormalizationClosesNonStoolContradictionsOnly() throws {
    let raw = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":4,"form":"smooth_formed","mixed_form":"no","apparent_color":"brown","red_appearing_material":"yes","black_tarry_appearance":"no"}
    """
    let result = try FullPrefillDependentFieldAbstentionV1
      .parseAndNormalize(raw)

    XCTAssertEqual(result.rawResponse, raw)
    XCTAssertTrue(result.normalizationOccurred)
    XCTAssertEqual(
      result.normalizedFields,
      FullPrefillDependentFieldAbstentionV1.dependentFieldOrder
    )
    XCTAssertTrue(result.normalizedSuggestion.imageUsable)
    XCTAssertNil(result.normalizedSuggestion.retakeReason)
    XCTAssertEqual(result.normalizedSuggestion.stoolPresence, .nonStool)
    assertFullPrefillAbstention(result.normalizedSuggestion)
  }

  func testDependentFieldNormalizationClosesUncertainSubjectIdentically() throws {
    let raw = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"uncertain","bristol_type":7,"form":"watery","mixed_form":"no","apparent_color":"black_appearing","red_appearing_material":"no","black_tarry_appearance":"yes"}
    """
    let result = try FullPrefillDependentFieldAbstentionV1
      .parseAndNormalize(raw)
    XCTAssertTrue(result.normalizedSuggestion.imageUsable)
    XCTAssertNil(result.normalizedSuggestion.retakeReason)
    XCTAssertEqual(result.normalizedSuggestion.stoolPresence, .uncertain)
    XCTAssertEqual(
      result.normalizedFields,
      FullPrefillDependentFieldAbstentionV1.dependentFieldOrder
    )
    assertFullPrefillAbstention(result.normalizedSuggestion)
  }

  func testDependentFieldNormalizationClosesUnusableImageWithTechnicalReason() throws {
    let raw = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":false,"retake_reason":"glare","stool_presence":"uncertain","bristol_type":2,"form":"lumpy_formed","mixed_form":"no","apparent_color":"dark_brown","red_appearing_material":"yes","black_tarry_appearance":"no"}
    """
    let result = try FullPrefillDependentFieldAbstentionV1
      .parseAndNormalize(raw)
    XCTAssertFalse(result.normalizedSuggestion.imageUsable)
    XCTAssertEqual(result.normalizedSuggestion.retakeReason, .glare)
    XCTAssertEqual(result.normalizedSuggestion.stoolPresence, .uncertain)
    assertFullPrefillAbstention(result.normalizedSuggestion)
  }

  func testDependentFieldNormalizationFailsClosedForInvalidControllingFields() {
    let missingReason = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":false,"retake_reason":null,"stool_presence":"uncertain","bristol_type":4,"form":"smooth_formed","mixed_form":"no","apparent_color":"brown","red_appearing_material":"no","black_tarry_appearance":"no"}
    """
    let wrongUnusableSubject = missingReason
      .replacingOccurrences(of: "\"retake_reason\":null", with: "\"retake_reason\":\"blurred\"")
      .replacingOccurrences(of: "\"stool_presence\":\"uncertain\"", with: "\"stool_presence\":\"non_stool\"")
    let usableWithReason = missingReason
      .replacingOccurrences(of: "\"image_usable\":false", with: "\"image_usable\":true")
      .replacingOccurrences(of: "\"retake_reason\":null", with: "\"retake_reason\":\"glare\"")

    for raw in [missingReason, wrongUnusableSubject, usableWithReason] {
      XCTAssertThrowsError(
        try FullPrefillDependentFieldAbstentionV1.parseAndNormalize(raw)
      )
    }
  }

  func testDependentFieldNormalizationLeavesUsableStoolContradictionsHard() {
    let mismatched = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":5,"form":"smooth_formed","mixed_form":"no","apparent_color":"brown","red_appearing_material":"no","black_tarry_appearance":"no"}
    """
    XCTAssertThrowsError(
      try FullPrefillDependentFieldAbstentionV1.parseAndNormalize(mismatched)
    )
  }

  func testDependentFieldNormalizationRejectsStructuralDefectsBeforeClosure() {
    let base = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":4,"form":"smooth_formed","mixed_form":"no","apparent_color":"brown","red_appearing_material":"no","black_tarry_appearance":"no"}
    """
    let cases = [
      String(base.dropLast()) + ",\"unknown\":false}",
      base.replacingOccurrences(of: "\"form\":\"smooth_formed\",", with: ""),
      base.replacingOccurrences(of: "\"image_usable\":true", with: "\"image_usable\":1"),
      base.replacingOccurrences(of: "\"bristol_type\":4", with: "\"bristol_type\":8"),
      base.replacingOccurrences(of: "\"form\":\"smooth_formed\"", with: "\"form\":\"invented\""),
      base.replacingOccurrences(of: "\"schema_version\":\"gi-photo-full-prefill-v1\"", with: "\"schema_version\":\"wrong\""),
      base.replacingOccurrences(of: "\"stool_presence\":\"non_stool\"", with: "\"stool_presence\":\"non_stool\",\"stool_presence\":\"uncertain\""),
    ]
    for raw in cases {
      XCTAssertThrowsError(
        try FullPrefillDependentFieldAbstentionV1.parseAndNormalize(raw),
        "Structural defect must fail before normalization: \(raw)"
      )
    }
  }

  func testDependentFieldNormalizationIsIdempotentAndPreservesExactRawBytes() throws {
    let raw = "  {\"schema_version\":\"gi-photo-full-prefill-v1\",\"image_usable\":true,\"retake_reason\":null,\"stool_presence\":\"non_stool\",\"bristol_type\":4,\"form\":\"smooth_formed\",\"mixed_form\":\"no\",\"apparent_color\":\"brown\",\"red_appearing_material\":\"yes\",\"black_tarry_appearance\":\"no\"}\n"
    let first = try FullPrefillDependentFieldAbstentionV1
      .parseAndNormalize(raw)
    let second = try FullPrefillDependentFieldAbstentionV1
      .parseAndNormalize(first.normalizedCanonicalJSON)

    XCTAssertEqual(first.rawResponse, raw)
    XCTAssertEqual(
      first.rawResponseSHA256,
      "1624e1e5d059906df33e60c6ddb49c82596be7fa27e84f8482ff4dec075ecd6d"
    )
    XCTAssertNotEqual(first.rawResponse, first.normalizedCanonicalJSON)
    XCTAssertNotEqual(first.rawResponseSHA256, first.normalizedCanonicalSHA256)
    XCTAssertEqual(second.normalizedSuggestion, first.normalizedSuggestion)
    XCTAssertEqual(second.normalizedCanonicalJSON, first.normalizedCanonicalJSON)
    XCTAssertFalse(second.normalizationOccurred)
    XCTAssertEqual(second.normalizedFields, [])

    let receipt = FullPrefillNormalizationReceiptV1(result: first)
    XCTAssertEqual(try receipt.validate(rawResponse: raw), first.normalizedSuggestion)
    XCTAssertThrowsError(try receipt.validate(rawResponse: raw + " "))

    let encoded = try JSONEncoder().encode(receipt)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    for (key, mutation) in [
      ("normalizationOccurred", false as Any),
      ("normalizedFields", ["form"] as Any),
      ("normalizedCanonicalSHA256", String(repeating: "0", count: 64) as Any),
      ("normalizationPolicyVersion", "forged-policy" as Any),
    ] {
      let original = object[key]
      object[key] = mutation
      let mutatedData = try JSONSerialization.data(withJSONObject: object)
      let mutated = try JSONDecoder().decode(
        FullPrefillNormalizationReceiptV1.self,
        from: mutatedData
      )
      XCTAssertThrowsError(try mutated.validate(rawResponse: raw), "Mutation \(key) must fail")
      object[key] = original
    }
  }

  func testFullPrefillRejectsMismatchedBristolFormAndUnknownKeys() {
    let mismatched = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":5,"form":"smooth_formed","mixed_form":"no","apparent_color":"brown","red_appearing_material":"no","black_tarry_appearance":"no"}
    """
    XCTAssertThrowsError(try FullPrefillPhotoSuggestionV1Parser.parse(mismatched))

    let unknown = String(mismatched.dropLast()) + ",\"diagnosis\":\"none\"}"
    XCTAssertThrowsError(try FullPrefillPhotoSuggestionV1Parser.parse(unknown)) {
      guard case ObservationParserError.unknownKeys(let keys) = $0 else {
        return XCTFail("Expected unknownKeys, got \($0)")
      }
      XCTAssertEqual(keys, ["diagnosis"])
    }
  }

  func testFullPrefillTechnicalAbstentionStillPrefillsConservativeValues() throws {
    for reason in [PhotoRetakeReason.tooDark, .glare, .blurred, .other] {
      let suggestion = FullPrefillPhotoSuggestionV1.technicalAbstention(
        reason: reason
      )
      XCTAssertFalse(suggestion.imageUsable)
      XCTAssertEqual(suggestion.stoolPresence, .uncertain)
      XCTAssertNil(suggestion.bristolType)
      XCTAssertEqual(suggestion.form, "unable_to_assess")
      XCTAssertEqual(suggestion.mixedForm, .notSure)
      XCTAssertNil(suggestion.apparentColor)
      XCTAssertEqual(suggestion.redAppearingMaterial, .notSure)
      XCTAssertEqual(suggestion.blackTarryAppearance, .notSure)
      XCTAssertNoThrow(
        try FullPrefillPhotoSuggestionV1Parser.canonicalJSON(suggestion)
      )
    }
  }

  private func assertFullPrefillAbstention(
    _ suggestion: FullPrefillPhotoSuggestionV1,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertNil(suggestion.bristolType, file: file, line: line)
    XCTAssertEqual(suggestion.form, "unable_to_assess", file: file, line: line)
    XCTAssertEqual(suggestion.mixedForm, .notSure, file: file, line: line)
    XCTAssertNil(suggestion.apparentColor, file: file, line: line)
    XCTAssertEqual(suggestion.redAppearingMaterial, .notSure, file: file, line: line)
    XCTAssertEqual(suggestion.blackTarryAppearance, .notSure, file: file, line: line)
  }

  func testFullPrefillConfirmationPreservesOriginalSeparatelyFromEditedFinalValues() throws {
    let original = FullPrefillPhotoSuggestionV1(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .stool,
      bristolType: 4,
      form: "smooth_formed",
      mixedForm: .no,
      apparentColor: "brown",
      redAppearingMaterial: .yes,
      blackTarryAppearance: .notSure
    )
    let originalJSON = try FullPrefillPhotoSuggestionV1Parser.canonicalJSON(original)
    let storedOriginal = try StoredModelVisualSuggestion.parse(originalJSON)
    XCTAssertEqual(storedOriginal.fullPrefillSuggestion, original)

    let reviewed = ConfirmedEntrySnapshotV1(
      confirmedAt: Date(timeIntervalSince1970: 1_725_000_000),
      personConfirmedPhotoUsable: true,
      personConfirmedStoolPresence: .stool,
      personConfirmedBristolType: 5,
      personConfirmedForm: "soft_blobs",
      personConfirmedMixedForm: .no,
      personConfirmedApparentColor: "dark_brown",
      personConfirmedRed: .no,
      personConfirmedBlackTarry: .unsure,
      fieldProvenance: [
        .photoUsable: .acceptedUnchanged,
        .stoolPresence: .acceptedUnchanged,
        .bristolType: .editedBeforeConfirmation,
        .form: .editedBeforeConfirmation,
        .mixedForm: .acceptedUnchanged,
        .apparentColor: .editedBeforeConfirmation,
        .redMaterial: .editedBeforeConfirmation,
        .blackTarry: .acceptedUnchanged,
      ]
    )
    try reviewed.validate(hasPhoto: true, hasModelSuggestion: true)
    let finalObservation = try XCTUnwrap(reviewed.visualObservation(
      original: storedOriginal.visualObservation,
      hasPhoto: true
    ))
    XCTAssertEqual(finalObservation.apparentBristolType, 5)
    XCTAssertEqual(finalObservation.form, "soft_blobs")
    XCTAssertEqual(finalObservation.apparentColor, "dark_brown")
    XCTAssertEqual(finalObservation.redAppearingMaterial, "not_observed")
    XCTAssertEqual(finalObservation.blackTarryAppearance, "unable_to_assess")
    XCTAssertEqual(
      try FullPrefillPhotoSuggestionV1Parser.parse(originalJSON),
      original,
      "The immutable Gemma payload must not be rewritten when final values are edited."
    )
  }

  func testConfirmationEnvelopeSeparatesPersonValuesAndFieldProvenance() throws {
    let confirmedAt = Date(timeIntervalSince1970: 1_725_000_000)
    let envelope = ConfirmedEntrySnapshotV1(
      confirmedAt: confirmedAt,
      personConfirmedPhotoUsable: true,
      personConfirmedBristolType: 5,
      personConfirmedMixedForm: .no,
      personConfirmedApparentColor: "dark_brown",
      personConfirmedRed: .no,
      personConfirmedBlackTarry: .unsure,
      fieldProvenance: [
        .photoUsable: .acceptedUnchanged,
        .bristolType: .editedBeforeConfirmation,
        .mixedForm: .acceptedUnchanged,
        .apparentColor: .editedBeforeConfirmation,
        .redMaterial: .independentPersonAnswer,
        .blackTarry: .independentPersonAnswer,
      ],
      personConfirmedSubject: true
    )
    try envelope.validate(hasPhoto: true, hasModelSuggestion: true)
    let json = try XCTUnwrap(envelope.canonicalJSON)
    let decoded = try ConfirmedEntrySnapshotV1.decode(json)
    XCTAssertEqual(decoded.confirmedAt, confirmedAt)
    XCTAssertEqual(decoded.personConfirmedSubject, true)
    XCTAssertEqual(decoded.typedFieldProvenance[.bristolType], .editedBeforeConfirmation)
    XCTAssertEqual(
      decoded.typedFieldProvenance[.redMaterial],
      .independentPersonAnswer
    )
    let original = try PhotoSuggestionV1Parser.parse(valid)
    let reviewed = try XCTUnwrap(decoded.visualObservation(
      original: StoredModelVisualSuggestion.photoV1(original).visualObservation,
      hasPhoto: true
    ))
    XCTAssertEqual(reviewed.redAppearingMaterial, "unable_to_assess")
    XCTAssertEqual(reviewed.blackTarryAppearance, "unable_to_assess")
    XCTAssertEqual(try StoredReviewedEntry.parse(json), .confirmedV1(decoded))
  }

  func testManualConfirmationRequiresManualNoSuggestionProvenance() throws {
    let manual = ConfirmedEntrySnapshotV1(
      confirmedAt: Date(timeIntervalSince1970: 1_725_000_000),
      personConfirmedPhotoUsable: nil,
      personConfirmedBristolType: 4,
      personConfirmedMixedForm: .no,
      personConfirmedApparentColor: nil,
      personConfirmedRed: .unsure,
      personConfirmedBlackTarry: .no,
      fieldProvenance: Dictionary(
        uniqueKeysWithValues: ConfirmationField.allCases.map { ($0, .manualNoSuggestion) }
      )
    )
    XCTAssertNoThrow(try manual.validate(hasPhoto: false, hasModelSuggestion: false))
    XCTAssertThrowsError(try manual.validate(hasPhoto: false, hasModelSuggestion: true))
  }

  func testUnusableConfirmedPhotoCannotRetainApparentColor() {
    let confirmation = ConfirmedEntrySnapshotV1(
      confirmedAt: Date(timeIntervalSince1970: 1_725_000_000),
      personConfirmedPhotoUsable: false,
      personConfirmedBristolType: 4,
      personConfirmedMixedForm: .no,
      personConfirmedApparentColor: "brown",
      personConfirmedRed: .unsure,
      personConfirmedBlackTarry: .no,
      fieldProvenance: Dictionary(
        uniqueKeysWithValues: ConfirmationField.allCases.map { ($0, .acceptedUnchanged) }
      )
    )
    XCTAssertThrowsError(try confirmation.validate(hasPhoto: true, hasModelSuggestion: true))
  }

  private func suggestion(
    imageUsable: Bool = true,
    retakeReason: PhotoRetakeReason? = nil,
    stoolPresence: StoolPresence = .stool,
    bristolType: Int? = 4,
    mixedForm: PhotoSuggestionAnswer = .no,
    apparentColor: String? = "brown",
    red: PhotoSuggestionAnswer = .no,
    black: PhotoSuggestionAnswer = .no
  ) -> PhotoSuggestionV1 {
    PhotoSuggestionV1(
      imageUsable: imageUsable,
      retakeReason: retakeReason,
      stoolPresence: stoolPresence,
      bristolType: bristolType,
      mixedForm: mixedForm,
      apparentColor: apparentColor,
      redAppearingMaterial: red,
      blackTarryAppearance: black
    )
  }
}
