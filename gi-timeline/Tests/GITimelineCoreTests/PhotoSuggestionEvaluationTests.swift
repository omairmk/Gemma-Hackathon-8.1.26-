import XCTest
@testable import GITimelineCore

final class PhotoSuggestionEvaluationTests: XCTestCase {
  func testBristolFormContractAcceptsExactPairsAndConservativeNullRules() throws {
    for (type, form) in BristolFormContract.expectedForms {
      XCTAssertNoThrow(try BristolFormContract.validate(bristolType: type, form: form))
    }
    XCTAssertNoThrow(try BristolFormContract.validate(bristolType: nil, form: "mixed"))
    XCTAssertNoThrow(try BristolFormContract.validate(bristolType: nil, form: "unable_to_assess"))
  }

  func testBristolFormContractRejectsEveryContradictoryPair() {
    for type in 1...7 {
      for form in ObservationParser.forms where form != BristolFormContract.expectedForm(for: type) {
        XCTAssertThrowsError(try BristolFormContract.validate(bristolType: type, form: form), "Type \(type) unexpectedly accepted \(form)")
      }
    }
    for form in ObservationParser.forms.subtracting(["mixed", "unable_to_assess"]) {
      XCTAssertThrowsError(try BristolFormContract.validate(bristolType: nil, form: form))
    }
  }

  func testObservationParserRejectsSpecificFormWithNullTypeAndAcceptsMixed() throws {
    let invalid = json(type: nil, form: "smooth_formed")
    XCTAssertThrowsError(try ObservationParser.parse(invalid))
    XCTAssertNoThrow(try ObservationParser.parse(json(type: nil, form: "mixed")))
  }

  func testMetricsCountAgreementAbstentionRepairsResourcesAndCorrections() throws {
    let results = [
      result(id: "a", reference: 4, suggestion: 4, form: "smooth_formed", latency: 20, memory: 100, correction: false),
      result(id: "b", reference: 6, suggestion: 7, form: "watery", parse: .repaired, latency: 30, memory: 120, correction: true),
      result(id: "c", reference: nil, suggestion: nil, form: "unable_to_assess", expectedAbstention: true, abstained: true, latency: 10, memory: 90),
    ]

    let metrics = try PhotoSuggestionEvaluator.report(results: results)

    XCTAssertEqual(metrics.route, .derivedMapIPhone)
    XCTAssertEqual(metrics.fixtureCount, 3)
    XCTAssertEqual(metrics.referenceLabeledCount, 2)
    XCTAssertEqual(metrics.exactAgreementCount, 1)
    XCTAssertEqual(metrics.withinOneAgreementCount, 2)
    XCTAssertEqual(metrics.groupedAgreementCount, 2)
    XCTAssertEqual(metrics.correctAbstentionCount, 1)
    XCTAssertEqual(metrics.coverageCount, 2)
    XCTAssertEqual(metrics.strictJSONValidCount, 3)
    XCTAssertEqual(metrics.directParseCount, 2)
    XCTAssertEqual(metrics.repairedParseCount, 1)
    XCTAssertEqual(metrics.correctionCount, 1)
    XCTAssertEqual(metrics.correctionEvaluableCount, 2)
    XCTAssertEqual(metrics.meanLatencyMilliseconds, 20)
    XCTAssertEqual(metrics.maximumLatencyMilliseconds, 30)
    XCTAssertEqual(metrics.peakMemoryBytes, 120)
    XCTAssertEqual(metrics.failureCount, 0)
    XCTAssertEqual(metrics.crashCount, 0)
    XCTAssertEqual(metrics.exactAgreement, 0.5)
    XCTAssertEqual(metrics.correctAbstention, 1)
  }

  func testEmptyMetricDenominatorsAreNilRatherThanNaN() throws {
    let metrics = try PhotoSuggestionEvaluator.report(results: [
      result(id: "only", reference: nil, suggestion: nil, form: "unable_to_assess", expectedAbstention: false, abstained: true),
    ])

    XCTAssertNil(metrics.exactAgreement)
    XCTAssertNil(metrics.withinOneAgreement)
    XCTAssertNil(metrics.groupedAgreement)
    XCTAssertNil(metrics.correctAbstention)
    XCTAssertNil(metrics.correctionRate)
  }

  func testQualityLabeledAbstentionRequiresUnusableImageAndMatchingIssue() throws {
    let results = [
      result(
        id: "correct-blur",
        reference: nil,
        suggestion: nil,
        form: "unable_to_assess",
        expectedAbstention: true,
        abstained: true,
        expectedImageUsable: false,
        expectedQualityIssue: "blurred",
        observedImageUsable: false,
        observedQualityIssue: "blurred"
      ),
      result(
        id: "wrong-usability",
        reference: nil,
        suggestion: nil,
        form: "unable_to_assess",
        expectedAbstention: true,
        abstained: true,
        expectedImageUsable: false,
        expectedQualityIssue: "blurred",
        observedImageUsable: true,
        observedQualityIssue: "blurred"
      ),
      result(
        id: "wrong-issue",
        reference: nil,
        suggestion: nil,
        form: "unable_to_assess",
        expectedAbstention: true,
        abstained: true,
        expectedImageUsable: false,
        expectedQualityIssue: "blurred",
        observedImageUsable: false,
        observedQualityIssue: "not_target_image"
      ),
      result(
        id: "missing-observation",
        reference: nil,
        suggestion: nil,
        form: "unable_to_assess",
        expectedAbstention: true,
        abstained: true,
        expectedImageUsable: false,
        expectedQualityIssue: "blurred"
      ),
    ]

    let metrics = try PhotoSuggestionEvaluator.report(results: results)

    XCTAssertEqual(metrics.expectedAbstentionCount, 4)
    XCTAssertEqual(metrics.correctAbstentionCount, 1)
  }

  func testLegacyEvaluationResultWithoutQualityFieldsRemainsDecodable() throws {
    let legacy = result(
      id: "legacy-control",
      reference: nil,
      suggestion: nil,
      form: "unable_to_assess",
      expectedAbstention: true,
      abstained: true
    )
    let data = try JSONEncoder().encode(legacy)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertFalse(json.contains("expectedImageUsable"))
    XCTAssertFalse(json.contains("expectedQualityIssue"))
    XCTAssertFalse(json.contains("observedImageUsable"))
    XCTAssertFalse(json.contains("observedQualityIssue"))

    let decoded = try JSONDecoder().decode(PhotoSuggestionEvaluationResult.self, from: data)
    XCTAssertNil(decoded.fixture.expectedImageUsable)
    XCTAssertNil(decoded.fixture.expectedQualityIssue)
    XCTAssertNil(decoded.observedImageUsable)
    XCTAssertNil(decoded.observedQualityIssue)
    XCTAssertEqual(try PhotoSuggestionEvaluator.report(results: [decoded]).correctAbstentionCount, 1)
  }

  func testSingleReportRejectsMixedRoutesAndSeparatedReportsKeepTiersApart() throws {
    let derived = result(id: "derived", reference: 4, suggestion: 4, form: "smooth_formed")
    let raw = result(
      id: "raw",
      route: .rawImageSimulator,
      pipeline: "gi-observation-raw-v1",
      prompt: "gi-observation-v1",
      reference: 4,
      suggestion: 4,
      form: "smooth_formed"
    )

    XCTAssertThrowsError(try PhotoSuggestionEvaluator.report(results: [derived, raw])) {
      XCTAssertEqual($0 as? PhotoSuggestionEvaluationError, .mixedRoutes)
    }
    let separated = try PhotoSuggestionEvaluator.routeSeparatedReports(results: [derived, raw])
    XCTAssertEqual(separated[.derivedMapIPhone]?.first?.fixtureCount, 1)
    XCTAssertEqual(separated[.rawImageSimulator]?.first?.fixtureCount, 1)
    XCTAssertEqual(separated.count, 2)
  }

  func testCandidateAdoptsOnlyOnIdenticalHoldoutWithStrictImprovementAndNoRegressions() throws {
    let baseline = holdoutBaseline()
    let candidate = [
      result(id: "target-4", partition: .holdout, pipeline: "candidate", reference: 4, suggestion: 4, form: "smooth_formed", latency: 80, memory: 900),
      result(id: "target-6", partition: .holdout, pipeline: "candidate", reference: 6, suggestion: 6, form: "mushy", latency: 85, memory: 950),
      result(id: "control", partition: .holdout, pipeline: "candidate", reference: nil, suggestion: nil, form: "unable_to_assess", expectedAbstention: true, abstained: true, latency: 70, memory: 800),
    ]

    let decision = try PhotoCandidateComparator.compare(
      baseline: baseline,
      candidate: candidate,
      limits: PhotoCandidateResourceLimits(maximumLatencyMilliseconds: 150, maximumPeakMemoryBytes: 2_000)
    )

    XCTAssertTrue(decision.adopted, decision.reasons.joined(separator: " | "))
    XCTAssertTrue(decision.reasons.isEmpty)
    XCTAssertEqual(decision.baseline.exactAgreementCount, 1)
    XCTAssertEqual(decision.candidate.exactAgreementCount, 2)
  }

  func testCandidateRejectsAbstentionRegressionEvenWhenExactAgreementImproves() throws {
    let baseline = holdoutBaseline()
    let candidate = [
      result(id: "target-4", partition: .holdout, pipeline: "candidate", reference: 4, suggestion: 4, form: "smooth_formed", latency: 80, memory: 900),
      result(id: "target-6", partition: .holdout, pipeline: "candidate", reference: 6, suggestion: 6, form: "mushy", latency: 85, memory: 950),
      result(id: "control", partition: .holdout, pipeline: "candidate", reference: nil, suggestion: 4, form: "smooth_formed", expectedAbstention: true, abstained: false, latency: 70, memory: 800),
    ]

    let decision = try PhotoCandidateComparator.compare(
      baseline: baseline,
      candidate: candidate,
      limits: PhotoCandidateResourceLimits(maximumLatencyMilliseconds: 150, maximumPeakMemoryBytes: 2_000)
    )

    XCTAssertFalse(decision.adopted)
    XCTAssertTrue(decision.reasons.contains("Correct abstention regressed."))
  }

  func testCandidateComparisonRejectsChangedSanitizedHash() {
    let baseline = holdoutBaseline()
    var candidate = baseline.map {
      result(
        id: $0.fixture.id,
        partition: .holdout,
        hash: $0.fixture.id == "control" ? "changed-hash" : $0.fixture.sanitizedImageSHA256,
        pipeline: "candidate",
        reference: $0.fixture.referenceBristolType,
        suggestion: $0.suggestedBristolType,
        form: $0.suggestedForm,
        expectedAbstention: $0.fixture.expectedAbstention,
        abstained: $0.abstained,
        latency: 80,
        memory: 900
      )
    }
    candidate[0] = result(id: "target-4", partition: .holdout, pipeline: "candidate", reference: 4, suggestion: 4, form: "smooth_formed", latency: 80, memory: 900)

    XCTAssertThrowsError(try PhotoCandidateComparator.compare(
      baseline: baseline,
      candidate: candidate,
      limits: PhotoCandidateResourceLimits(maximumLatencyMilliseconds: 150, maximumPeakMemoryBytes: 2_000)
    )) {
      XCTAssertEqual($0 as? PhotoSuggestionEvaluationError, .sanitizedHashMismatch("control"))
    }
  }

  func testFrozenManifestDecodesValidatesAndProjectsOneNamedRoute() throws {
    let manifest = try PhotoEvaluationManifest.decodeAndValidate(manifestData())

    XCTAssertTrue(manifest.frozenBeforeAccuracyCodeChanges)
    XCTAssertFalse(manifest.assetContract.containsRealHealthPhotos)
    XCTAssertEqual(manifest.fixtures(for: .rawImageSimulator, partition: .tuning).map(\.id), ["t01"])
    let holdout = try XCTUnwrap(manifest.fixtures(for: .derivedMapIPhone, partition: .holdout).first)
    let evaluationFixture = holdout.evaluationFixture(for: .derivedMapIPhone)
    XCTAssertEqual(evaluationFixture.route, .derivedMapIPhone)
    XCTAssertEqual(evaluationFixture.expectedImageUsable, false)
    XCTAssertEqual(evaluationFixture.expectedQualityIssue, "not_target_image")
    XCTAssertEqual(holdout.referenceBristolType, nil)
    XCTAssertTrue(holdout.expectedAbstention)
  }

  func testFrozenManifestRejectsTraversalEvenForAHashedJPEG() {
    XCTAssertThrowsError(try PhotoEvaluationManifest.decodeAndValidate(
      manifestData(tuningAsset: "assets/../private.jpg")
    )) {
      XCTAssertEqual($0 as? PhotoEvaluationManifestError, .unsafeAssetPath("t01"))
    }
  }

  private func holdoutBaseline() -> [PhotoSuggestionEvaluationResult] {
    [
      result(id: "target-4", partition: .holdout, pipeline: "baseline", reference: 4, suggestion: 5, form: "soft_blobs", latency: 100, memory: 1_000),
      result(id: "target-6", partition: .holdout, pipeline: "baseline", reference: 6, suggestion: 6, form: "mushy", latency: 100, memory: 1_000),
      result(id: "control", partition: .holdout, pipeline: "baseline", reference: nil, suggestion: nil, form: "unable_to_assess", expectedAbstention: true, abstained: true, latency: 100, memory: 1_000),
    ]
  }

  private func result(
    id: String,
    route: PhotoEvaluationRoute = .derivedMapIPhone,
    partition: PhotoEvaluationPartition = .holdout,
    hash: String? = nil,
    pipeline: String = "gi-local-pixel-bridge-v1",
    prompt: String = "gi-local-pixel-bridge-v1",
    reference: Int?,
    suggestion: Int?,
    form: String,
    expectedAbstention: Bool = false,
    abstained: Bool = false,
    strictJSON: Bool = true,
    parse: PhotoParsePath = .direct,
    latency: Double? = nil,
    memory: UInt64? = nil,
    failure: String? = nil,
    crashed: Bool = false,
    correction: Bool? = nil,
    expectedImageUsable: Bool? = nil,
    expectedQualityIssue: String? = nil,
    observedImageUsable: Bool? = nil,
    observedQualityIssue: String? = nil
  ) -> PhotoSuggestionEvaluationResult {
    let fixture = PhotoEvaluationFixture(
      id: id,
      partition: partition,
      sanitizedImageSHA256: hash ?? "hash-\(id)",
      route: route,
      referenceBristolType: reference,
      referenceForm: reference.flatMap(BristolFormContract.expectedForm(for:)) ?? "unable_to_assess",
      expectedAbstention: expectedAbstention,
      expectedImageUsable: expectedImageUsable,
      expectedQualityIssue: expectedQualityIssue
    )
    return PhotoSuggestionEvaluationResult(
      fixture: fixture,
      pipelineVersion: pipeline,
      promptVersion: prompt,
      suggestedBristolType: suggestion,
      suggestedForm: form,
      abstained: abstained,
      strictJSONValid: strictJSON,
      parsePath: parse,
      latencyMilliseconds: latency,
      peakMemoryBytes: memory,
      failureDescription: failure,
      crashed: crashed,
      userConfirmedCorrection: correction,
      observedImageUsable: observedImageUsable,
      observedQualityIssue: observedQualityIssue
    )
  }

  private func json(type: Int?, form: String) -> String {
    let typeValue = type.map(String.init) ?? "null"
    return "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":\(typeValue),\"apparent_color\":\"brown\",\"form\":\"\(form)\",\"red_appearing_material\":\"unable_to_assess\",\"black_tarry_appearance\":\"unable_to_assess\"}"
  }

  private func manifestData(tuningAsset: String = "assets/t01.jpg") -> Data {
    let hash = String(repeating: "a", count: 64)
    return Data("""
    {
      "manifest_version":"test-v1",
      "frozen_at_utc":"2026-08-02T01:00:30Z",
      "frozen_before_accuracy_code_changes":true,
      "asset_contract":{
        "source_category":"synthetic_non_health",
        "contains_real_health_photos":false,
        "asset_format":"metadata-stripped JPEG",
        "hash_field":"sanitized_image_sha256",
        "reference_label_name":"reference label",
        "limitations":"Construction labels only."
      },
      "pipelines":{
        "RAW_IMAGE_SIMULATOR":{"baseline":"raw-v1","candidate":"raw-v2","candidate_status":"debug"},
        "DERIVED_MAP_IPHONE":{"baseline":"map-v1","candidate":"map-v2","candidate_status":"not adopted"}
      },
      "fixtures":[
        {"id":"t01","partition":"tuning","asset":"\(tuningAsset)","sanitized_image_sha256":"\(hash)","routes":["RAW_IMAGE_SIMULATOR","DERIVED_MAP_IPHONE"],"reference_target":"target_like","reference_bristol_type":4,"reference_form":"smooth_formed","expected_abstention":false,"expected_quality_issue":"none","run_condition":"warm"},
        {"id":"h01","partition":"holdout","asset":"assets/h01.jpg","sanitized_image_sha256":"\(hash)","routes":["RAW_IMAGE_SIMULATOR","DERIVED_MAP_IPHONE"],"reference_target":"non_target","reference_bristol_type":null,"reference_form":"unable_to_assess","expected_abstention":true,"expected_quality_issue":"not_target_image","run_condition":"warm"}
      ]
    }
    """.utf8)
  }
}
