import Foundation
import XCTest
@testable import GITimelineCore

final class PhotoSuggestionHybridTests: XCTestCase {
  private let canonical = "{\"s\":\"yes\",\"f\":\"smooth_formed\",\"m\":\"no\",\"c\":\"brown\",\"r\":\"no\",\"b\":\"no\",\"g\":\"no\"}"

  func testCompactParserPreservesRawExtractedAndCanonicalBytes() throws {
    let result = try Qwen3HybridWireParser.parse(rawUTF8: Data(canonical.utf8))
    XCTAssertEqual(Qwen3HybridWireParser.parserVersion, "q3h2-parser-v1")
    XCTAssertEqual(result.payload.f, .smoothFormed)
    XCTAssertEqual(result.extractedObjectUTF8, Data(canonical.utf8))
    XCTAssertEqual(result.canonicalObject, canonical)
    XCTAssertTrue(result.formatCompliant)
    XCTAssertEqual(result.rawSHA256.count, 64)
  }

  func testOnlyOneBalancedObjectAndWhitespaceEnvelopeAreAccepted() throws {
    XCTAssertNoThrow(try Qwen3HybridWireParser.parse(rawUTF8: Data((canonical + "\n").utf8)))
    for wrapper in ["prefix \(canonical)", "```\(canonical)```", canonical + canonical] {
      XCTAssertThrowsError(try Qwen3HybridWireParser.parse(rawUTF8: Data(wrapper.utf8)))
    }
  }

  func testEnvelopeAndSchemaMutationsFailClosedWithoutRepair() {
    let mutations: [String] = [
      canonical + canonical,
      "{prefix}" + canonical,
      canonical + " }}",
      canonical + " }",
      "{\"s\":\"yes\",\"s\":\"no\"}",
      "\u{FEFF}" + canonical,
    ]
    for mutation in mutations {
      XCTAssertThrowsError(
        try Qwen3HybridWireParser.parse(rawUTF8: Data(mutation.utf8)),
        mutation
      )
    }
  }

  func testPartialFieldsBecomeNotSureWithoutInventingOrRepairing() throws {
    let partial = "{\"s\":true,\"f\":\"smooth_formed\",\"m\":\"maybe\",\"c\":\"brown\",\"r\":\"no\",\"b\":\"no\",\"g\":\"no\",\"x\":\"ignored\"}"
    let result = try Qwen3HybridWireParser.parse(rawUTF8: Data(partial.utf8))
    XCTAssertEqual(result.payload.s, .notSure)
    XCTAssertEqual(result.payload.f, .smoothFormed)
    XCTAssertEqual(result.payload.m, .notSure)
    XCTAssertFalse(result.formatCompliant)
  }

  func testDerivativeIsExactCentered512AspectFitWithNeutralPadding() throws {
    let source = try frame(width: 4, height: 2, color: (10, 20, 30))
    let prepared = try HybridImagePreparer.prepare(
      heldSourceImageData: Data("held-image".utf8), decodedRGBA: source
    )
    XCTAssertEqual(prepared.rgba.count, 512 * 512 * 4)
    XCTAssertEqual(
      prepared.provenance.contentRect,
      HybridContentRect(x: 0, y: 128, width: 512, height: 256)
    )
    XCTAssertEqual(prepared.provenance.derivativeBytesPerRow, 2048)
    XCTAssertEqual(prepared.provenance.paddingRGBA, [128, 128, 128, 255])
    XCTAssertEqual(pixel(prepared.rgba, width: 512, x: 0, y: 0), [128, 128, 128, 255])
    XCTAssertEqual(pixel(prepared.rgba, width: 512, x: 0, y: 128), [10, 20, 30, 255])
    XCTAssertEqual(prepared.provenance.policy, HybridDerivativeProvenance.policy)
  }

  func testHostOnly768And1024PreparationLeaveTheApp512OverloadByteIdentical() throws {
    let source = try frame(width: 4, height: 2, color: (10, 20, 30))
    let held = Data("held-image".utf8)
    let app512 = try HybridImagePreparer.prepare(
      heldSourceImageData: held, decodedRGBA: source
    )
    let explicit512 = try HybridImagePreparer.prepare(
      heldSourceImageData: held, decodedRGBA: source, hostOnlyCanvasSize: 512
    )
    let host768 = try HybridImagePreparer.prepare(
      heldSourceImageData: held, decodedRGBA: source, hostOnlyCanvasSize: 768
    )
    let internalQA1024 = try HybridImagePreparer.prepare(
      heldSourceImageData: held, decodedRGBA: source, hostOnlyCanvasSize: 1024
    )

    XCTAssertEqual(app512, explicit512)
    XCTAssertEqual(host768.rgba.count, 768 * 768 * 4)
    XCTAssertEqual(
      host768.provenance.contentRect,
      HybridContentRect(x: 0, y: 192, width: 768, height: 384)
    )
    XCTAssertEqual(host768.provenance.derivativeBytesPerRow, 768 * 4)
    XCTAssertNotEqual(host768.provenance.derivativeRGBASHA256, app512.provenance.derivativeRGBASHA256)
    XCTAssertEqual(internalQA1024.rgba.count, 1024 * 1024 * 4)
    XCTAssertEqual(
      internalQA1024.provenance.contentRect,
      HybridContentRect(x: 0, y: 256, width: 1024, height: 512)
    )
    XCTAssertEqual(internalQA1024.provenance.derivativeBytesPerRow, 1024 * 4)
    XCTAssertNotEqual(
      internalQA1024.provenance.derivativeRGBASHA256,
      app512.provenance.derivativeRGBASHA256
    )
    XCTAssertThrowsError(
      try HybridImagePreparer.prepare(
        heldSourceImageData: held, decodedRGBA: source, hostOnlyCanvasSize: 640
      )
    ) { XCTAssertEqual($0 as? HybridImagePreparationError, .invalidHostOnlyCanvasSize) }
  }

  func testDarkBrownHighChromaCannotCountAsBlack() throws {
    var image = try frame(width: 80, height: 80, color: (128, 128, 128))
    image = try painting(image, x: 10, y: 15, width: 60, height: 50, color: (70, 35, 15))
    let evidence = HybridPixelAnalyzer.evaluate(image)
    XCTAssertEqual(evidence.baseColorCandidate, .darkBrown)
    XCTAssertEqual(evidence.localizedBlack, .highNegative)
    XCTAssertEqual(evidence.blackLowChromaPixelFractionPPM, 0)
  }

  func testLocalizedRedBlackAndTarryTruthTablesUsePixelsOnly() throws {
    var red = try frame(width: 100, height: 100, color: (128, 128, 128))
    red = try painting(red, x: 15, y: 25, width: 70, height: 50, color: (115, 70, 35))
    red = try painting(red, x: 20, y: 35, width: 20, height: 20, color: (220, 10, 10))
    let redEvidence = HybridPixelAnalyzer.evaluate(red)
    XCTAssertEqual(redEvidence.localizedRed, .highPositive)
    XCTAssertEqual(redEvidence.baseColorCandidate, .brown)

    var tarry = try frame(width: 100, height: 100, color: (128, 128, 128))
    tarry = try painting(tarry, x: 10, y: 20, width: 80, height: 60, color: (115, 70, 35))
    tarry = try painting(tarry, x: 10, y: 40, width: 80, height: 20, color: (12, 12, 12))
    tarry = try painting(tarry, x: 20, y: 45, width: 20, height: 1, color: (230, 230, 230))
    let tarryEvidence = HybridPixelAnalyzer.evaluate(tarry)
    XCTAssertEqual(tarryEvidence.localizedBlack, .highPositive)
    XCTAssertEqual(tarryEvidence.tarryGlossSmear, .highPositive)
    XCTAssertEqual(tarryEvidence.baseColorCandidate, .brown)

    var unrelatedGloss = try frame(width: 100, height: 100, color: (128, 128, 128))
    unrelatedGloss = try painting(
      unrelatedGloss, x: 10, y: 40, width: 80, height: 20, color: (12, 12, 12)
    )
    unrelatedGloss = try painting(
      unrelatedGloss, x: 10, y: 10, width: 20, height: 2, color: (230, 230, 230)
    )
    XCTAssertEqual(
      HybridPixelAnalyzer.evaluate(unrelatedGloss).tarryGlossSmear,
      .highNegative
    )
  }

  func testQualityGatesCoverDarkOverexposedBlankLowContrastAndBlur() throws {
    XCTAssertEqual(
      HybridPixelAnalyzer.evaluate(try frame(width: 80, height: 80, color: (8, 8, 8))).quality,
      .hardPoorTooDark
    )
    XCTAssertEqual(
      HybridPixelAnalyzer.evaluate(try frame(width: 80, height: 80, color: (252, 252, 252))).quality,
      .hardPoorOverexposed
    )
    XCTAssertEqual(
      HybridPixelAnalyzer.evaluate(try frame(width: 80, height: 80, color: (128, 128, 128))).quality,
      .hardPoorNearBlank
    )
    var lowContrast = try frame(width: 80, height: 80, color: (128, 128, 128))
    lowContrast = try painting(
      lowContrast, x: 10, y: 15, width: 60, height: 50, color: (146, 146, 146)
    )
    XCTAssertEqual(HybridPixelAnalyzer.evaluate(lowContrast).quality, .hardPoorLowContrast)
    XCTAssertEqual(
      HybridPixelAnalyzer.evaluate(try blurredSpot(width: 96, height: 96)).quality,
      .hardPoorSevereBlur
    )
  }

  func testFusionRequiresAgreementAndConflictsBecomeNotSure() throws {
    let raw = try Qwen3HybridWireParser.parse(rawUTF8: Data(canonical.utf8)).payload
    let disagreement = try fused(
      raw: raw, red: .highPositive, black: .highNegative, tarry: .highNegative
    )
    XCTAssertEqual(disagreement.redAppearingMaterial, .notSure)
    XCTAssertEqual(disagreement.blackAppearance, .no)
    XCTAssertEqual(disagreement.blackTarryAppearance, .no)

    let agreedNo = try fused(
      raw: raw, red: .highNegative, black: .highNegative, tarry: .highNegative
    )
    XCTAssertEqual(agreedNo.redAppearingMaterial, .no)
    XCTAssertEqual(agreedNo.blackAppearance, .no)

    let rawYes = Qwen3HybridWirePayload(
      s: .yes, f: .smoothFormed, m: .no, c: .brown,
      r: .yes, b: .yes, g: .yes
    )
    let agreedYes = try fused(
      raw: rawYes, red: .highPositive, black: .highPositive, tarry: .highPositive
    )
    XCTAssertEqual(agreedYes.redAppearingMaterial, .yes)
    XCTAssertEqual(agreedYes.blackAppearance, .yes)
    XCTAssertEqual(agreedYes.blackTarryAppearance, .yes)

    let blackConflict = try fused(
      raw: rawYes, red: .highPositive, black: .highNegative, tarry: .highPositive
    )
    XCTAssertEqual(blackConflict.blackAppearance, .notSure)
    XCTAssertEqual(blackConflict.blackTarryAppearance, .notSure)

    let ambiguous = try fused(
      raw: rawYes, red: .ambiguous, black: .ambiguous, tarry: .ambiguous
    )
    XCTAssertEqual(ambiguous.redAppearingMaterial, .notSure)
    XCTAssertEqual(ambiguous.blackAppearance, .notSure)
    XCTAssertEqual(ambiguous.blackTarryAppearance, .notSure)
  }

  func testWarningTruthTableRequiresRawAndDeterministicAgreement() throws {
    for rawValue in Qwen3HybridTriState.allCases {
      for evidence: HybridEvidenceStrength in [.highPositive, .highNegative, .ambiguous] {
        let raw = Qwen3HybridWirePayload(s: .yes, f: .smoothFormed, m: .no, c: .brown,
          r: rawValue, b: rawValue, g: rawValue)
        let value = try fused(raw: raw, red: evidence, black: evidence, tarry: evidence)
        let expected: PhotoSuggestionAnswer = rawValue == .yes && evidence == .highPositive ? .yes
          : rawValue == .no && evidence == .highNegative ? .no : .notSure
        XCTAssertEqual(value.redAppearingMaterial, expected)
        XCTAssertEqual(value.blackAppearance, expected)
        XCTAssertEqual(value.blackTarryAppearance, expected)
      }
    }
  }

  func testMixedFormIsIndependentFromFormWhenStoolPresent() throws {
    let mixedNo = Qwen3HybridWirePayload(s: .yes, f: .notSure, m: .no, c: .brown, r: .no, b: .no, g: .no)
    let noValue = try fused(raw: mixedNo, red: .highNegative, black: .highNegative, tarry: .highNegative)
    XCTAssertEqual(noValue.mixedForm, .no)
    XCTAssertNil(noValue.bristolType)
    let mixedUnknown = Qwen3HybridWirePayload(s: .yes, f: .smoothFormed, m: .notSure, c: .brown, r: .no, b: .no, g: .no)
    let unknownValue = try fused(raw: mixedUnknown, red: .highNegative, black: .highNegative, tarry: .highNegative)
    XCTAssertEqual(unknownValue.mixedForm, .notSure)
    XCTAssertEqual(unknownValue.bristolType, 4)
  }

  func testBaseColorRequiresExactRawPixelAgreement() throws {
    let raw = Qwen3HybridWirePayload(
      s: .yes, f: .smoothFormed, m: .no, c: .darkBrown,
      r: .no, b: .no, g: .no
    )
    let agreement = try fused(
      raw: raw, pixels: evidence(baseColor: .darkBrown),
      red: .highNegative, black: .highNegative, tarry: .highNegative
    )
    XCTAssertEqual(agreement.apparentColor, "dark_brown")
    let conflict = try fused(
      raw: raw, pixels: evidence(baseColor: .blackAppearing),
      red: .highNegative, black: .highNegative, tarry: .highNegative
    )
    XCTAssertEqual(conflict.apparentColor, "black_appearing")
  }

  func testInvalidRawPreservesOnlyDeterministicSafetyEvidence() throws {
    for quality in [
      HybridPixelQuality.usable,
      .hardPoorTooDark,
      .hardPoorOverexposed,
      .hardPoorNearBlank,
      .hardPoorLowContrast,
      .hardPoorSevereBlur,
    ] {
      let pixels = evidence(
        quality: quality,
        red: .highPositive,
        black: .highNegative,
        tarry: .highNegative
      )
      guard case let .suggestion(result) = try HybridFusion.fuse(raw: nil, pixels: pixels) else {
        return XCTFail("missing raw must preserve deterministic suggestion")
      }
      XCTAssertEqual(result.suggestion.stoolPresence, .uncertain)
      XCTAssertNil(result.suggestion.bristolType)
      XCTAssertEqual(result.suggestion.form, "unable_to_assess")
      XCTAssertEqual(result.suggestion.mixedForm, .notSure)
      XCTAssertEqual(result.suggestion.redAppearingMaterial, .notSure)
      XCTAssertEqual(result.suggestion.blackAppearance, .notSure)
      if quality == .usable {
        XCTAssertEqual(result.origin, .deterministicNoRawEvidence)
      } else {
        XCTAssertEqual(result.origin, .deterministicHardPoor)
      }
    }
  }

  func testNonStoolForcesOnlyModelMorphologyToNotSure() throws {
    let raw = Qwen3HybridWirePayload(
      s: .no, f: .notSure, m: .notSure, c: .brown,
      r: .yes, b: .yes, g: .yes
    )
    let result = try fused(
      raw: raw, red: .highPositive, black: .highPositive, tarry: .highPositive
    )
    XCTAssertEqual(result.stoolPresence, .nonStool)
    XCTAssertNil(result.bristolType)
    XCTAssertEqual(result.apparentColor, "brown")
    XCTAssertEqual(result.redAppearingMaterial, .yes)
    XCTAssertEqual(result.blackAppearance, .yes)
    XCTAssertEqual(result.blackTarryAppearance, .yes)
  }

  func testHardPoorDeterministicUsabilityStopsFusion() throws {
    let rawUsable = try Qwen3HybridWireParser.parse(
      rawUTF8: Data(canonical.utf8)
    ).payload
    let outcome = try HybridFusion.fuse(
      raw: rawUsable,
      pixels: evidence(quality: .hardPoorTooDark)
    )
    guard case .suggestion(let fused) = outcome else {
      return XCTFail("expected technical abstention")
    }
    XCTAssertFalse(fused.suggestion.imageUsable)
    XCTAssertEqual(fused.suggestion.retakeReason, .tooDark)
    XCTAssertEqual(fused.origin, .deterministicHardPoor)
  }

  func testDecomposedFieldsKeepExactPromptsAndLabels() {
    XCTAssertEqual(Qwen3DecomposedField.allCases, [
      .subject, .bristol, .mixed, .color, .red, .black, .glossy,
    ])
    XCTAssertEqual(
      Qwen3DecomposedField.subject.prompt,
      "Does this image show stool? Answer only: stool, nonstool, or unsure."
    )
    XCTAssertEqual(
      Qwen3DecomposedField.bristol.prompt,
      "Choose the closest Bristol type. Answer only: 1, 2, 3, 4, 5, 6, 7, or unsure."
    )
    XCTAssertEqual(
      Qwen3DecomposedField.mixed.prompt,
      "Does it visibly contain more than one stool form? Answer only: yes, no, or unsure."
    )
    XCTAssertEqual(
      Qwen3DecomposedField.color.prompt,
      "Choose the main visible stool color. Answer only: brown, yellow, green, red, black, other, or unsure."
    )
    XCTAssertEqual(
      Qwen3DecomposedField.red.prompt,
      "Is red material visibly present? Answer only: yes, no, or unsure."
    )
    XCTAssertEqual(
      Qwen3DecomposedField.black.prompt,
      "Is unusually black material visibly present? Answer only: yes, no, or unsure."
    )
    XCTAssertEqual(
      Qwen3DecomposedField.glossy.prompt,
      "Is there a visibly black glossy or smeared tar-like appearance? Answer only: yes, no, or unsure."
    )
    XCTAssertEqual(Qwen3DecomposedField.subject.allowedLabels, ["stool", "nonstool", "unsure"])
    XCTAssertEqual(Qwen3DecomposedField.bristol.allowedLabels, ["1", "2", "3", "4", "5", "6", "7", "unsure"])
    XCTAssertEqual(Qwen3DecomposedField.color.allowedLabels, ["brown", "yellow", "green", "red", "black", "other", "unsure"])
    for field in [Qwen3DecomposedField.mixed, .red, .black, .glossy] {
      XCTAssertEqual(field.allowedLabels, ["yes", "no", "unsure"])
    }
  }

  func testDecomposedParserAcceptsExactFirstLabelForEveryField() {
    for field in Qwen3DecomposedField.allCases {
      let label = field.allowedLabels[0]
      let result = Qwen3DecomposedLabelParser.parse(
        "  - \(label.uppercased()). extra prose \(field.allowedLabels.last!)  ",
        for: field
      )
      XCTAssertEqual(result.field, field)
      XCTAssertEqual(result.label, label)
      XCTAssertEqual(result.disposition, .accepted)
    }
    let fenced = Qwen3DecomposedLabelParser.parse(
      "```answer\nGREEN!\n```",
      for: .color
    )
    XCTAssertEqual(fenced.label, "green")
    XCTAssertEqual(fenced.disposition, .accepted)
    let list = Qwen3DecomposedLabelParser.parse("- yes\n- no", for: .red)
    XCTAssertEqual(list.label, "yes")
  }

  func testDecomposedParserRejectsFragmentsAmbiguityAndBrokenFences() {
    for (text, field) in [
      // "stoo" is length 4, below the length-5 floor for prefix acceptance,
      // so it still fails closed rather than being read as truncated "stool".
      ("stoo", Qwen3DecomposedField.subject),
      ("non-stool", .subject),
      ("yes/no", .red),
      ("```\nyes\n```\n```", .red),
      ("```\nyes", .red),
      ("", .black),
    ] {
      let result = Qwen3DecomposedLabelParser.parse(text, for: field)
      XCTAssertEqual(result.label, "unsure", text)
      XCTAssertEqual(result.disposition, .invalid, text)
    }
    XCTAssertEqual(
      Qwen3DecomposedLabelParser.parse(nil, for: .glossy).disposition,
      .invalid
    )
  }

  /// Parser v2: a token of length >= 5 that is a strict prefix of exactly
  /// one allowed label for the field parses to that label with
  /// `.acceptedPrefix`, not `.accepted` and not `.invalid`. Covers the
  /// documented on-device truncation fingerprint ("nonst" then a natural
  /// EOS, see PhotoSuggestionHybrid.swift ~:943) plus the other real
  /// unambiguous prefixes across every field's label set.
  func testDecomposedParserAcceptsUnambiguousLengthFivePrefixes() {
    for (text, field, expectedLabel) in [
      ("nonst", Qwen3DecomposedField.subject, "nonstool"),
      ("nonsto", .subject, "nonstool"),
      ("nonstoo", .subject, "nonstool"),
      ("yello", .color, "yellow"),
      ("unsur", .color, "unsure"),
      ("unsur", .bristol, "unsure"),
      ("unsur", .red, "unsure"),
      ("unsur", .black, "unsure"),
      ("unsur", .glossy, "unsure"),
      ("unsur", .mixed, "unsure"),
    ] {
      let result = Qwen3DecomposedLabelParser.parse(text, for: field)
      XCTAssertEqual(result.field, field, text)
      XCTAssertEqual(result.label, expectedLabel, text)
      XCTAssertEqual(result.disposition, .acceptedPrefix, text)
      // "unsure" is a valid explicit abstention, not a usable qualified
      // answer, even when reached via prefix completion; only the
      // non-"unsure" completions (nonstool, yellow) are usable.
      XCTAssertEqual(result.isUsableQualifiedLabel, expectedLabel != "unsure", text)
    }

    // Below the length-5 floor, an otherwise-unambiguous fragment still
    // fails closed rather than being completed.
    XCTAssertEqual(
      Qwen3DecomposedLabelParser.parse("unsu", for: .subject).disposition,
      .invalid
    )

    // Exact matches still take priority over prefix completion and remain
    // plain `.accepted`, never `.acceptedPrefix`.
    XCTAssertEqual(
      Qwen3DecomposedLabelParser.parse("nonstool", for: .subject),
      Qwen3DecomposedParsedLabel(field: .subject, label: "nonstool", disposition: .accepted)
    )

    let legacy = Qwen3DecomposedLabelParser.parse(
      "nonst",
      for: .subject,
      replaying: Qwen3DecomposedContract.legacyParserVersion
    )
    XCTAssertEqual(legacy.label, "unsure")
    XCTAssertEqual(legacy.disposition, .invalid)
    XCTAssertEqual(
      Qwen3DecomposedLabelParser.parse(
        "nonstool",
        for: .subject,
        replaying: Qwen3DecomposedContract.legacyParserVersion
      ).disposition,
      .accepted
    )
  }

  func testDecomposedEvidenceRequiresIndependentFreshFieldRecords() throws {
    XCTAssertNoThrow(try decomposedEvidence().validate())
    XCTAssertThrowsError(
      try decomposedEvidence(cacheIDs: Array(repeating: "shared-cache", count: 7)).validate()
    ) { XCTAssertEqual($0 as? Qwen3DecomposedRunEvidenceError, .staleOrSharedCache) }
    XCTAssertThrowsError(
      try decomposedEvidence(ordinals: [1, 2, 3, 4, 5, 6, 6]).validate()
    ) { XCTAssertEqual($0 as? Qwen3DecomposedRunEvidenceError, .fieldOrder) }
    XCTAssertThrowsError(
      try decomposedEvidence(preparedTensorForRed: "different-tensor").validate()
    ) { XCTAssertEqual($0 as? Qwen3DecomposedRunEvidenceError, .mismatchedIdentity) }
  }

  func testDecomposedFusionForcesUnqualifiedSubjectMorphologyToNotSure() throws {
    let result = try Qwen3DecomposedFusion.fuse(decomposedEvidence(
      qualified: Set(Qwen3DecomposedField.allCases),
      labels: [.subject: "stool", .bristol: "4", .mixed: "no"]
    )).suggestion
    XCTAssertEqual(result.stoolPresence, .uncertain)
    XCTAssertNil(result.bristolType)
    XCTAssertEqual(result.form, "unable_to_assess")
    XCTAssertEqual(result.mixedForm, .notSure)
  }

  func testDecomposedFusionRequiresQualifiedPixelColorAgreement() throws {
    let agreement = try Qwen3DecomposedFusion.fuse(decomposedEvidence(
      baseColor: .darkBrown,
      qualified: [.color],
      labels: [.color: "brown"]
    )).suggestion
    XCTAssertEqual(agreement.apparentColor, "dark_brown")

    let disagreement = try Qwen3DecomposedFusion.fuse(decomposedEvidence(
      baseColor: .green,
      qualified: [.color],
      labels: [.color: "brown"]
    )).suggestion
    XCTAssertNil(disagreement.apparentColor)

    let unqualified = try Qwen3DecomposedFusion.fuse(decomposedEvidence(
      baseColor: .brown,
      labels: [.color: "brown"]
    )).suggestion
    XCTAssertNil(unqualified.apparentColor)
  }

  func testDecomposedFusionNeverSuppressesStrongPositiveWarningsToNo() throws {
    let suppressedNo = try Qwen3DecomposedFusion.fuse(decomposedEvidence(
      red: .highPositive,
      black: .highPositive,
      qualified: [.red, .black],
      labels: [.red: "no", .black: "no"]
    )).suggestion
    XCTAssertEqual(suppressedNo.redAppearingMaterial, .notSure)
    XCTAssertEqual(suppressedNo.blackAppearance, .notSure)

    let agreed = try Qwen3DecomposedFusion.fuse(decomposedEvidence(
      red: .highPositive,
      black: .highPositive,
      qualified: [.red, .black],
      labels: [.red: "yes", .black: "yes"]
    )).suggestion
    XCTAssertEqual(agreed.redAppearingMaterial, .yes)
    XCTAssertEqual(agreed.blackAppearance, .yes)
  }

  func testDecomposedFusionNegativeAppearanceAgreementReturnsNo() throws {
    let evidence = decomposedEvidence(
      red: .highNegative,
      black: .highNegative,
      tarry: .highNegative,
      qualified: [.red, .black, .glossy],
      labels: [.red: "no", .black: "no", .glossy: "no"]
    )
    let result = try Qwen3DecomposedFusion.fuse(evidence).suggestion

    XCTAssertEqual(result.redAppearingMaterial, .no)
    XCTAssertEqual(result.blackAppearance, .no)
    XCTAssertEqual(result.blackTarryAppearance, .no)

    let legacyComplete = try Qwen3DecomposedFusion.fuse(
      evidence,
      replaying: Qwen3DecomposedFusion.legacyCompleteTriStateVersion
    ).suggestion
    XCTAssertEqual(legacyComplete, result)

    let legacyPositiveOnly = try Qwen3DecomposedFusion.fuse(
      evidence,
      replaying: Qwen3DecomposedFusion.legacyPositiveOnlyVersion
    ).suggestion
    XCTAssertEqual(legacyPositiveOnly.redAppearingMaterial, .notSure)
    XCTAssertEqual(legacyPositiveOnly.blackAppearance, .notSure)
    XCTAssertEqual(legacyPositiveOnly.blackTarryAppearance, .notSure)

    XCTAssertThrowsError(
      try Qwen3DecomposedFusion.fuse(evidence, replaying: "unknown")
    )
  }

  func testDecomposedGlossyYesRequiresQualifiedBlackAndCompatiblePixels() throws {
    let yes = try Qwen3DecomposedFusion.fuse(decomposedEvidence(
      black: .highPositive,
      tarry: .highPositive,
      qualified: [.black, .glossy],
      labels: [.black: "yes", .glossy: "yes"]
    )).suggestion
    XCTAssertEqual(yes.blackTarryAppearance, .yes)

    let noBlackQualification = try Qwen3DecomposedFusion.fuse(decomposedEvidence(
      black: .highPositive,
      tarry: .highPositive,
      qualified: [.glossy],
      labels: [.black: "yes", .glossy: "yes"]
    )).suggestion
    XCTAssertEqual(noBlackQualification.blackTarryAppearance, .notSure)

    let noGloss = try Qwen3DecomposedFusion.fuse(decomposedEvidence(
      black: .highPositive,
      tarry: .highNegative,
      qualified: [.black, .glossy],
      labels: [.black: "yes", .glossy: "yes"]
    )).suggestion
    XCTAssertEqual(noGloss.blackTarryAppearance, .notSure)
  }

  func testDecomposedAllUnqualifiedFallsBackAndCanonicalizesV2() throws {
    let result = try Qwen3DecomposedFusion.fuse(decomposedEvidence(
      labels: [.color: "brown", .red: "yes", .black: "yes", .glossy: "yes"]
    ))
    XCTAssertNil(result.suggestion.apparentColor)
    XCTAssertEqual(result.suggestion.redAppearingMaterial, .notSure)
    XCTAssertEqual(result.suggestion.blackAppearance, .notSure)
    XCTAssertEqual(result.suggestion.blackTarryAppearance, .notSure)
    XCTAssertEqual(
      try PhotoSuggestionPayloadV2Parser.parse(result.canonicalV2JSON),
      result.suggestion
    )
  }

  func testDecomposedPoorQualityUsesExistingTechnicalAbstention() throws {
    let result = try Qwen3DecomposedFusion.fuse(decomposedEvidence(
      quality: .hardPoorTooDark,
      qualified: Set(Qwen3DecomposedField.allCases),
      labels: [.color: "brown", .red: "yes", .black: "yes", .glossy: "yes"]
    )).suggestion
    XCTAssertFalse(result.imageUsable)
    XCTAssertEqual(result.retakeReason, .tooDark)
    XCTAssertEqual(result.stoolPresence, .uncertain)
    XCTAssertNil(result.apparentColor)
    XCTAssertEqual(result.redAppearingMaterial, .notSure)
  }

  private func decomposedEvidence(
    quality: HybridPixelQuality = .usable,
    baseColor: Qwen3HybridWireColor = .brown,
    colorConfidence: Int = 800_000,
    red: HybridEvidenceStrength = .highNegative,
    black: HybridEvidenceStrength = .highNegative,
    tarry: HybridEvidenceStrength = .highNegative,
    qualified: Set<Qwen3DecomposedField> = [],
    labels: [Qwen3DecomposedField: String] = [:],
    cacheIDs: [String]? = nil,
    ordinals: [Int]? = nil,
    preparedTensorForRed: String? = nil
  ) -> Qwen3DecomposedRunEvidence {
    let imageSHA = "image-sha"
    let tensorSHA = "tensor-sha"
    let fields = Qwen3DecomposedField.allCases.enumerated().map { index, field in
      let raw = labels[field] ?? "unsure"
      return Qwen3DecomposedRawFieldRecord(
        field: field,
        prompt: field.prompt,
        promptSHA256: "prompt-\(index + 1)",
        analyzedImageSHA256: imageSHA,
        preparedTensorSHA256: field == .red ? (preparedTensorForRed ?? tensorSHA) : tensorSHA,
        rawTokenIDs: [index + 1],
        rawText: raw,
        rawUTF8Base64: Data(raw.utf8).base64EncodedString(),
        rawUTF8SHA256: "raw-\(index + 1)",
        parsed: Qwen3DecomposedLabelParser.parse(raw, for: field),
        qualified: qualified.contains(field),
        generationCacheID: cacheIDs?[index] ?? "fresh-nil-\(index + 1)",
        usedFreshGenerationCache: true,
        stopReason: "eos",
        latencyMilliseconds: index + 1,
        modelCallOrdinal: ordinals?[index] ?? index + 1
      )
    }
    var pixels = evidence(
      quality: quality,
      baseColor: baseColor,
      red: red,
      black: black,
      tarry: tarry
    )
    pixels = HybridPixelEvidence(
      schemaVersion: pixels.schemaVersion,
      thresholdVersion: pixels.thresholdVersion,
      quality: pixels.quality,
      baseColorCandidate: pixels.baseColorCandidate,
      baseColorConfidencePPM: colorConfidence,
      localizedRed: pixels.localizedRed,
      localizedBlack: pixels.localizedBlack,
      tarryGlossSmear: pixels.tarryGlossSmear,
      darkPixelFractionPPM: pixels.darkPixelFractionPPM,
      overexposedPixelFractionPPM: pixels.overexposedPixelFractionPPM,
      foregroundFractionPPM: pixels.foregroundFractionPPM,
      foregroundComponentCount: pixels.foregroundComponentCount,
      largestForegroundRegionFractionPPM: pixels.largestForegroundRegionFractionPPM,
      largestForegroundSolidityPPM: pixels.largestForegroundSolidityPPM,
      redPixelFractionPPM: pixels.redPixelFractionPPM,
      blackLowChromaPixelFractionPPM: pixels.blackLowChromaPixelFractionPPM,
      largestRedRegionFractionPPM: pixels.largestRedRegionFractionPPM,
      largestBlackRegionFractionPPM: pixels.largestBlackRegionFractionPPM,
      largestBlackRegionElongationNumerator: pixels.largestBlackRegionElongationNumerator,
      largestBlackRegionElongationDenominator: pixels.largestBlackRegionElongationDenominator,
      componentLocalGlossFractionPPM: pixels.componentLocalGlossFractionPPM,
      strongEdgeFractionPPM: pixels.strongEdgeFractionPPM,
      lumaRange: pixels.lumaRange,
      edgeMean: pixels.edgeMean
    )
    return Qwen3DecomposedRunEvidence(
      analyzedImageSHA256: imageSHA,
      preparedTensorSHA256: tensorSHA,
      pixelEvidence: pixels,
      fields: fields
    )
  }

  private func fused(
    raw: Qwen3HybridWirePayload,
    pixels: HybridPixelEvidence? = nil,
    red: HybridEvidenceStrength,
    black: HybridEvidenceStrength,
    tarry: HybridEvidenceStrength
  ) throws -> PhotoSuggestionPayloadV2 {
    let outcome = try HybridFusion.fuse(
      raw: raw,
      pixels: pixels ?? evidence(red: red, black: black, tarry: tarry)
    )
    guard case .suggestion(let fused) = outcome else {
      throw XCTSkip("unexpected manual fallback")
    }
    return fused.suggestion
  }

  private func evidence(
    quality: HybridPixelQuality = .usable,
    baseColor: Qwen3HybridWireColor = .brown,
    red: HybridEvidenceStrength = .highNegative,
    black: HybridEvidenceStrength = .highNegative,
    tarry: HybridEvidenceStrength = .highNegative
  ) -> HybridPixelEvidence {
    HybridPixelEvidence(
      schemaVersion: HybridPixelEvidence.schemaVersion,
      thresholdVersion: HybridPixelEvidence.thresholdVersion,
      quality: quality,
      baseColorCandidate: baseColor,
      baseColorConfidencePPM: 800_000,
      localizedRed: red,
      localizedBlack: black,
      tarryGlossSmear: tarry,
      darkPixelFractionPPM: quality == .hardPoorTooDark ? 900_000 : 0,
      overexposedPixelFractionPPM: quality == .hardPoorOverexposed ? 900_000 : 0,
      foregroundFractionPPM: 500_000,
      foregroundComponentCount: 1,
      largestForegroundRegionFractionPPM: 500_000,
      largestForegroundSolidityPPM: 800_000,
      redPixelFractionPPM: 0,
      blackLowChromaPixelFractionPPM: 0,
      largestRedRegionFractionPPM: 0,
      largestBlackRegionFractionPPM: 0,
      largestBlackRegionElongationNumerator: 1,
      largestBlackRegionElongationDenominator: 1,
      componentLocalGlossFractionPPM: 0,
      strongEdgeFractionPPM: 20_000,
      lumaRange: 100,
      edgeMean: 4
    )
  }

  private func frame(
    width: Int, height: Int, color: (UInt8, UInt8, UInt8)
  ) throws -> HybridRGBAFrame {
    var bytes = Data(count: width * height * 4)
    bytes.withUnsafeMutableBytes { raw in
      let values = raw.bindMemory(to: UInt8.self)
      for index in 0..<(width * height) {
        values[index * 4] = color.0
        values[index * 4 + 1] = color.1
        values[index * 4 + 2] = color.2
        values[index * 4 + 3] = 255
      }
    }
    return try HybridRGBAFrame(width: width, height: height, rgba: bytes)
  }

  private func painting(
    _ frame: HybridRGBAFrame,
    x: Int, y: Int, width: Int, height: Int,
    color: (UInt8, UInt8, UInt8)
  ) throws -> HybridRGBAFrame {
    var bytes = frame.rgba
    bytes.withUnsafeMutableBytes { raw in
      let values = raw.bindMemory(to: UInt8.self)
      for row in y..<(y + height) {
        for column in x..<(x + width) {
          let index = (row * frame.width + column) * 4
          values[index] = color.0
          values[index + 1] = color.1
          values[index + 2] = color.2
          values[index + 3] = 255
        }
      }
    }
    return try HybridRGBAFrame(width: frame.width, height: frame.height, rgba: bytes)
  }

  private func blurredSpot(width: Int, height: Int) throws -> HybridRGBAFrame {
    var bytes = Data(count: width * height * 4)
    let centerX = width / 2
    let centerY = height / 2
    let maximumDistance = max(1, min(width, height) / 2)
    bytes.withUnsafeMutableBytes { raw in
      let values = raw.bindMemory(to: UInt8.self)
      for y in 0..<height {
        for x in 0..<width {
          let distance = max(abs(x - centerX), abs(y - centerY))
          let lift = max(0, 70 * (maximumDistance - distance) / maximumDistance)
          let value = UInt8(128 + lift)
          let index = (y * width + x) * 4
          values[index] = value
          values[index + 1] = value
          values[index + 2] = value
          values[index + 3] = 255
        }
      }
    }
    return try HybridRGBAFrame(width: width, height: height, rgba: bytes)
  }

  private func pixel(_ data: Data, width: Int, x: Int, y: Int) -> [UInt8] {
    let bytes = [UInt8](data)
    let index = (y * width + x) * 4
    return Array(bytes[index..<(index + 4)])
  }
}
