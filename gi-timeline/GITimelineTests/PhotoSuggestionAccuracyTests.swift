import CoreImage
import CryptoKit
import GITimelineCore
import ImageIO
import UIKit
import XCTest
@testable import GITimeline

@MainActor
final class PhotoSuggestionAccuracyTests: XCTestCase {
  func testPipelineIdentifiersFollowActualConfigurationAndCandidatesAreNotDefaults() {
    XCTAssertEqual(InferenceConfiguration.deterministicBaseline.analysisPipelineVersion, AnalysisPipelineVersion.rawImageV1)
    XCTAssertEqual(InferenceConfiguration.simulatorRawPromptV2Candidate.analysisPipelineVersion, AnalysisPipelineVersion.rawImageV2)
    XCTAssertEqual(InferenceConfiguration.physicalCPUVisualBridge.analysisPipelineVersion, AnalysisPipelineVersion.derivedMapV1)
    XCTAssertEqual(InferenceConfiguration.physicalCPUVisualBridgeExtractorV2Candidate.analysisPipelineVersion, AnalysisPipelineVersion.derivedMapV2)
    XCTAssertNotEqual(InferenceConfiguration.runtimeDefault, .simulatorRawPromptV2Candidate)
    XCTAssertNotEqual(InferenceConfiguration.runtimeDefault, .physicalCPUVisualBridgeExtractorV2Candidate)
  }

  func testRawPromptV2IsSimulatorDebugOnlyOrderedAndConservative() {
    let prompt = InferenceService.rawPromptV2Debug
    let subject = prompt.range(of: "Relevant-subject gate")
    let quality = prompt.range(of: "Capture-quality gate")
    let bristol = prompt.range(of: "Bristol/form observation")
    let serialization = prompt.range(of: "Strict serialization")
    XCTAssertNotNil(subject)
    XCTAssertNotNil(quality)
    XCTAssertNotNil(bristol)
    XCTAssertNotNil(serialization)
    XCTAssertLessThan(subject!.lowerBound, quality!.lowerBound)
    XCTAssertLessThan(quality!.lowerBound, bristol!.lowerBound)
    XCTAssertLessThan(bristol!.lowerBound, serialization!.lowerBound)
    XCTAssertTrue(prompt.contains("Non-target format example"))
    XCTAssertTrue(prompt.contains("\"apparent_bristol_type\":6"))
    XCTAssertFalse(prompt.contains("\"apparent_bristol_type\":4"), "The candidate must not retain the brown/Type-4 anchoring example.")
    XCTAssertTrue(prompt.contains("both material fields are unable_to_assess"))
  }

  func testImagePreparationIsDeterministicMetadataFreeAndExplicitSRGB() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = makeImageStore(root: root)
    let source = render(.brownOrganic)

    let first = try store.prepare(source)
    let second = try store.prepare(source)
    XCTAssertEqual(first.reference.sha256, second.reference.sha256)

    for draft in [first, second] {
      let data = try Data(contentsOf: draft.url)
      XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), draft.reference.sha256)
      let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
      XCTAssertNil(properties[kCGImagePropertyExifDictionary])
      XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
      XCTAssertEqual(properties[kCGImagePropertyColorModel] as? String, kCGImagePropertyColorModelRGB as String)
      XCTAssertTrue((properties[kCGImagePropertyProfileName] as? String)?.localizedCaseInsensitiveContains("sRGB") == true)
    }
  }

  func testBaselineRemainsInstalledWhileCandidateKeepsOrganicTypeFourContentDependence() throws {
    let extraction = try extract(.brownOrganic, variant: .candidateV2)
    XCTAssertEqual(extraction.diagnostics.analysisPipelineVersion, AnalysisPipelineVersion.derivedMapV2)
    XCTAssertEqual(extraction.diagnostics.colorSpace, "sRGB")
    XCTAssertEqual(extraction.diagnostics.gridSide, 12)
    XCTAssertEqual(extraction.facts.qualityHint, "none")
    XCTAssertEqual(extraction.facts.bristolTypeHint, 4)
    XCTAssertEqual(extraction.facts.formHint, "smooth_formed")
    XCTAssertTrue(extraction.diagnostics.roiFullFrameAgreement)
  }

  func testCandidateAbstainsOnBrownBlockGreenControlDarknessGlareCropDistantBlurAndAmbiguity() throws {
    let controls: [SyntheticControl] = [
      .brownBlock,
      .greenOrganic,
      .dark,
      .glare,
      .cropped,
      .distant,
      .blurred,
      .brownGreenAmbiguous,
    ]

    for control in controls {
      let extraction = try extract(control, variant: .candidateV2)
      XCTAssertNotEqual(extraction.facts.qualityHint, "none", "\(control) must produce retake/manual guidance.")
      XCTAssertNil(extraction.facts.bristolTypeHint, "\(control) must abstain instead of forcing a type.")
      XCTAssertEqual(extraction.facts.formHint, "unable_to_assess")
      let expected = DerivedMapPostconditions.expectedObservation(for: extraction.facts)
      XCTAssertFalse(expected.imageUsable)
      XCTAssertEqual(expected.redAppearingMaterial, "unable_to_assess")
      XCTAssertEqual(expected.blackTarryAppearance, "unable_to_assess")
    }
  }

  func testRouteAwarePostconditionsRejectExtractorOverrideAndRedBlackClaims() throws {
    let extraction = try extract(.brownOrganic, variant: .candidateV2)
    let expected = DerivedMapPostconditions.expectedObservation(for: extraction.facts)
    XCTAssertNoThrow(try DerivedMapPostconditions.validate(expected, against: extraction.facts))

    let override = VisualObservation(
      imageUsable: expected.imageUsable,
      qualityIssue: expected.qualityIssue,
      apparentBristolType: 6,
      apparentColor: expected.apparentColor,
      form: "mushy",
      redAppearingMaterial: "unable_to_assess",
      blackTarryAppearance: "unable_to_assess"
    )
    XCTAssertThrowsError(try DerivedMapPostconditions.validate(override, against: extraction.facts)) {
      XCTAssertEqual($0 as? DerivedMapPostconditionError, .extractorOverride("apparent_bristol_type"))
    }

    let redClaim = VisualObservation(
      imageUsable: expected.imageUsable,
      qualityIssue: expected.qualityIssue,
      apparentBristolType: expected.apparentBristolType,
      apparentColor: expected.apparentColor,
      form: expected.form,
      redAppearingMaterial: "not_observed",
      blackTarryAppearance: "unable_to_assess"
    )
    XCTAssertThrowsError(try DerivedMapPostconditions.validate(redClaim, against: extraction.facts)) {
      XCTAssertEqual($0 as? DerivedMapPostconditionError, .redOrBlackAssessment)
    }
  }

  func testFrozenEvaluationOverrideAcceptsOnlySessionEquivalentOneVariableCandidates() {
    let baseline = InferenceConfiguration.physicalCPUVisualBridge
    let candidate = InferenceConfiguration.physicalCPUVisualBridgeExtractorV2Candidate
    XCTAssertTrue(baseline.permitsEvaluationOverride(baseline))
    XCTAssertTrue(baseline.permitsEvaluationOverride(candidate))
    XCTAssertTrue(
      InferenceConfiguration.simulatorCPUFallback.permitsEvaluationOverride(.simulatorRawPromptV2Candidate)
    )

    func changing(
      engineBackend: String = candidate.engineBackend,
      maxNumTokens: Int = candidate.maxNumTokens,
      topK: Int = candidate.topK,
      imageMessageForm: String = candidate.imageMessageForm
    ) -> InferenceConfiguration {
      InferenceConfiguration(
        id: candidate.id,
        engineBackend: engineBackend,
        visionBackend: candidate.visionBackend,
        maxNumTokens: maxNumTokens,
        topK: topK,
        topP: candidate.topP,
        temperature: candidate.temperature,
        seed: candidate.seed,
        promptVersion: candidate.promptVersion,
        imageMessageForm: imageMessageForm
      )
    }

    XCTAssertFalse(baseline.permitsEvaluationOverride(changing(engineBackend: "gpu")))
    XCTAssertFalse(baseline.permitsEvaluationOverride(changing(maxNumTokens: 1_024)))
    XCTAssertFalse(baseline.permitsEvaluationOverride(changing(topK: 2)))
    XCTAssertFalse(baseline.permitsEvaluationOverride(changing(imageMessageForm: "different-shape")))
    XCTAssertFalse(candidate.permitsEvaluationOverride(baseline), "The candidate cannot become a new mutable default.")
  }

  func testPreparedEvaluationSessionPreparesAndFinallyInvalidatesExactlyOnce() async throws {
    let runtime = CountingPhotoEvaluationSessionRuntime()
    let value = try await PhotoEvaluationPreparedSession.run(
      runtime: runtime,
      descriptor: .liteRTGemma4E4B
    ) {
      "baseline-and-candidate-complete"
    }
    XCTAssertEqual(value, "baseline-and-candidate-complete")
    var counts = await runtime.counts()
    XCTAssertEqual(counts.prepare, 1)
    XCTAssertEqual(counts.invalidate, 1)

    let failingRuntime = CountingPhotoEvaluationSessionRuntime()
    do {
      let _: Void = try await PhotoEvaluationPreparedSession.run(
        runtime: failingRuntime,
        descriptor: .liteRTGemma4E4B
      ) {
        throw EvaluationSessionTestError.expected
      }
      XCTFail("Synthetic pipeline failure must escape the session wrapper.")
    } catch EvaluationSessionTestError.expected {
      // Expected.
    }
    counts = await failingRuntime.counts()
    XCTAssertEqual(counts.prepare, 1)
    XCTAssertEqual(counts.invalidate, 1, "Failure cleanup must also release the one prepared session exactly once.")
  }

  func testBaselineAndCandidateProvenanceStayDistinctWhileSharingSanitizedInput() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let prepared = try makeImageStore(root: root).prepare(render(.brownOrganic))
    let baseline = try LocalPixelFeatureExtractor.extractDetailed(from: prepared.url, variant: .baselineV1)
    let candidate = try LocalPixelFeatureExtractor.extractDetailed(from: prepared.url, variant: .candidateV2)

    XCTAssertEqual(baseline.diagnostics.sanitizedImageSHA256, candidate.diagnostics.sanitizedImageSHA256)
    XCTAssertEqual(baseline.diagnostics.analysisPipelineVersion, AnalysisPipelineVersion.derivedMapV1)
    XCTAssertEqual(candidate.diagnostics.analysisPipelineVersion, AnalysisPipelineVersion.derivedMapV2)
    XCTAssertFalse(InferenceConfiguration.runtimeDefault.usesCandidatePixelExtractor)
  }

  func testEvaluationOverrideTimeoutQuarantinesTheSharedLeaseAgainstCandidateWork() async throws {
    XCTAssertTrue(
      InferenceConfiguration.physicalCPUVisualBridge.permitsEvaluationOverride(
        .physicalCPUVisualBridgeExtractorV2Candidate
      )
    )
    var gate = RuntimeCoordinatorGate()
    let token = try gate.acquire(
      descriptorID: ModelDescriptor.liteRTGemma4E4B.id,
      purpose: .structured(draftPath: "/synthetic/frozen-holdout.jpg")
    )
    XCTAssertTrue(gate.beginContainedCall(token))
    let probe = EvaluationOverrideNonCooperativeProbe()
    let operation = Task {
      try await InferenceCallerDeadlineRace.run(deadline: .milliseconds(20)) {
        await probe.value()
      }
    }
    await probe.waitUntilStarted()
    defer { probe.finish() }

    do {
      _ = try await operation.value
      XCTFail("The synthetic native stall must reach caller containment.")
    } catch {
      XCTAssertEqual(error as? InferenceCallerContainmentError, .timedOut)
      gate.quarantine(token)
    }
    XCTAssertTrue(gate.hasQuarantinedOperation)
    XCTAssertThrowsError(
      try gate.acquire(
        descriptorID: ModelDescriptor.liteRTGemma4E4B.id,
        purpose: .structured(draftPath: "/synthetic/candidate.jpg")
      )
    )
  }

  func testDerivedMapV3TuningConfigurationCannotEnterHoldoutOrBecomeDefault() throws {
    let baseline = InferenceConfiguration.physicalCPUVisualBridge
    let holdoutCandidate = InferenceConfiguration.physicalCPUVisualBridgeExtractorV2Candidate
    let tuningCandidate = InferenceConfiguration.physicalCPUVisualBridgeExtractorV3TuningCandidate
    let runtimeDefaultBefore = InferenceConfiguration.runtimeDefault

    XCTAssertEqual(tuningCandidate.analysisPipelineVersion, AnalysisPipelineVersion.derivedMapV3Tuning)
    XCTAssertTrue(baseline.permitsTuningOverride(tuningCandidate))
    XCTAssertFalse(baseline.permitsEvaluationOverride(tuningCandidate))
    XCTAssertFalse(baseline.permitsTuningOverride(holdoutCandidate))
    XCTAssertFalse(tuningCandidate.permitsTuningOverride(baseline))
    XCTAssertNotEqual(runtimeDefaultBefore, tuningCandidate)

    let extraction = try extract(.brownOrganic, variant: .candidateV3Tuning)
    XCTAssertEqual(extraction.diagnostics.analysisPipelineVersion, AnalysisPipelineVersion.derivedMapV3Tuning)
    XCTAssertEqual(extraction.facts.schemaVersion, "local-pixel-facts-v3-tuning")
    XCTAssertEqual(extraction.facts.shapeSuggestionConfidence, "tuning_only_fixture_candidate_v3")
    XCTAssertEqual(InferenceConfiguration.runtimeDefault, runtimeDefaultBefore)
  }

  func testDerivedMapV3TuningSelectsOnlyNamedTuningPartitionAndFailsClosedOnDrift() throws {
    let frozenData = try Data(contentsOf: tuningManifestURL())
    let frozenHash = SHA256.hash(data: frozenData).map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(frozenHash, DerivedMapTuningV3Contract.frozenManifestSHA256)
    XCTAssertFalse(try XCTUnwrap(String(data: frozenData, encoding: .utf8)).contains("holdout"))

    let manifest = try DerivedMapTuningV3Manifest.decodeAndValidate(frozenData)
    let selected = try DerivedMapTuningV3Contract.tuningFixtures(
      from: manifest,
      requestedRoute: .derivedMapIPhone
    )
    XCTAssertEqual(selected.map(\.id), DerivedMapTuningV3Contract.expectedFixtureIDs)
    XCTAssertTrue(selected.allSatisfy { $0.partition == .tuning })
    XCTAssertFalse(selected.contains { $0.id.hasPrefix("h") })

    XCTAssertNoThrow(try DerivedMapTuningV3Contract.validateManifestHash(
      DerivedMapTuningV3Contract.frozenManifestSHA256
    ))
    XCTAssertThrowsError(try DerivedMapTuningV3Contract.validateManifestHash(
      String(repeating: "0", count: 64)
    )) {
      XCTAssertEqual($0 as? DerivedMapTuningV3Error, .manifestHashDrift)
    }
    XCTAssertThrowsError(try DerivedMapTuningV3Contract.tuningFixtures(
      from: manifest,
      requestedRoute: .rawImageSimulator
    )) {
      XCTAssertEqual($0 as? DerivedMapTuningV3Error, .routeDrift)
    }

    XCTAssertThrowsError(try DerivedMapTuningV3Manifest.decodeAndValidate(
      tuningManifestData(partitionDriftID: "t12-type4-cold-start")
    )) {
      XCTAssertEqual($0 as? DerivedMapTuningV3Error, .partitionDrift)
    }
    XCTAssertThrowsError(try DerivedMapTuningV3Manifest.decodeAndValidate(
      tuningManifestData(routeDriftID: "t12-type4-cold-start")
    )) {
      XCTAssertEqual($0 as? DerivedMapTuningV3Error, .routeDrift)
    }
    XCTAssertThrowsError(try DerivedMapTuningV3Manifest.decodeAndValidate(
      tuningManifestData(appendingUnexpectedFixture: true)
    )) {
      XCTAssertEqual($0 as? DerivedMapTuningV3Error, .fixtureSetMismatch)
    }

    XCTAssertNoThrow(try DerivedMapTuningV3Contract.validateLaunch(
      arguments: [DerivedMapTuningV3Contract.launchArgument]
    ))
    XCTAssertThrowsError(try DerivedMapTuningV3Contract.validateLaunch(
      arguments: [
        DerivedMapTuningV3Contract.launchArgument,
        PhotoSuggestionEvaluationHarness.derivedMapIPhoneLaunchArgument,
      ]
    )) {
      XCTAssertEqual($0 as? DerivedMapTuningV3Error, .launchConflict)
    }
  }

  func testDerivedMapV3TuningMetricsCannotProduceComparatorOrAdoptionOutput() throws {
    let runtimeDefaultBefore = InferenceConfiguration.runtimeDefault
    let baseline = DerivedMapTuningV3Contract.expectedFixtureIDs.map {
      tuningResult(id: $0, pipeline: AnalysisPipelineVersion.derivedMapV1, suggestion: 5)
    }
    let candidate = DerivedMapTuningV3Contract.expectedFixtureIDs.map {
      tuningResult(id: $0, pipeline: AnalysisPipelineVersion.derivedMapV3Tuning, suggestion: 4)
    }
    let metrics = try DerivedMapTuningV3Contract.engineeringMetrics(
      baselineResults: baseline,
      candidateResults: candidate
    )
    XCTAssertEqual(metrics.lane, DerivedMapTuningV3Contract.lane)
    XCTAssertEqual(metrics.baseline.fixtureCount, 12)
    XCTAssertEqual(metrics.candidate.fixtureCount, 12)
    XCTAssertEqual(InferenceConfiguration.runtimeDefault, runtimeDefaultBefore)

    let encoded = try JSONEncoder().encode(metrics)
    let json = try XCTUnwrap(String(data: encoded, encoding: .utf8)?.lowercased())
    for prohibited in ["adopt", "eligible", "decision", "recommendation", "holdout"] {
      XCTAssertFalse(json.contains(prohibited), "Tuning metrics must not emit \(prohibited).")
    }

    XCTAssertThrowsError(try PhotoCandidateComparator.compare(
      baseline: baseline,
      candidate: candidate,
      limits: PhotoCandidateResourceLimits(
        maximumLatencyMilliseconds: 1_000,
        maximumPeakMemoryBytes: 10_000
      )
    )) {
      guard let comparisonError = $0 as? PhotoSuggestionEvaluationError,
        case .tuningResultInHoldoutComparison = comparisonError
      else {
        return XCTFail("The locked-holdout comparator must reject every tuning result.")
      }
    }
  }

  func testDerivedMapV3TuningMetricsRejectPairedSubstitutedFrozenHash() {
    let substitutedID = DerivedMapTuningV3Contract.expectedFixtureIDs[0]
    let substitutedHash = String(repeating: "0", count: 64)
    let baseline = DerivedMapTuningV3Contract.expectedFixtureIDs.map {
      tuningResult(
        id: $0,
        pipeline: AnalysisPipelineVersion.derivedMapV1,
        suggestion: 5,
        sanitizedImageSHA256Override: $0 == substitutedID ? substitutedHash : nil
      )
    }
    let candidate = DerivedMapTuningV3Contract.expectedFixtureIDs.map {
      tuningResult(
        id: $0,
        pipeline: AnalysisPipelineVersion.derivedMapV3Tuning,
        suggestion: 4,
        sanitizedImageSHA256Override: $0 == substitutedID ? substitutedHash : nil
      )
    }

    XCTAssertThrowsError(try DerivedMapTuningV3Contract.engineeringMetrics(
      baselineResults: baseline,
      candidateResults: candidate
    )) {
      XCTAssertEqual($0 as? DerivedMapTuningV3Error, .fixtureSetMismatch)
    }
  }

  func testDerivedMapV3TuningMetricsRejectPairedSubstitutedReferenceFields() {
    let substitutedID = DerivedMapTuningV3Contract.expectedFixtureIDs[0]
    let baseline = DerivedMapTuningV3Contract.expectedFixtureIDs.map {
      tuningResult(
        id: $0,
        pipeline: AnalysisPipelineVersion.derivedMapV1,
        suggestion: 5,
        referenceBristolTypeOverride: $0 == substitutedID ? 2 : nil,
        referenceFormOverride: $0 == substitutedID ? "lumpy_sausage" : nil,
        expectedAbstentionOverride: $0 == substitutedID ? true : nil
      )
    }
    let candidate = DerivedMapTuningV3Contract.expectedFixtureIDs.map {
      tuningResult(
        id: $0,
        pipeline: AnalysisPipelineVersion.derivedMapV3Tuning,
        suggestion: 4,
        referenceBristolTypeOverride: $0 == substitutedID ? 2 : nil,
        referenceFormOverride: $0 == substitutedID ? "lumpy_sausage" : nil,
        expectedAbstentionOverride: $0 == substitutedID ? true : nil
      )
    }

    XCTAssertThrowsError(try DerivedMapTuningV3Contract.engineeringMetrics(
      baselineResults: baseline,
      candidateResults: candidate
    )) {
      XCTAssertEqual($0 as? DerivedMapTuningV3Error, .fixtureSetMismatch)
    }
  }

  func testDerivedMapV3TuningCompletionVocabularyRecordsMetricsWithoutClaimingPass() {
    XCTAssertEqual(
      DerivedMapTuningV3Contract.runCompleteConsoleMarker,
      "PHOTO_TUNING_V3_RUN_COMPLETE"
    )
    XCTAssertEqual(
      DerivedMapTuningV3Contract.metricsRecordedStatus,
      "TUNING_V3_ENGINEERING_METRICS_RECORDED"
    )
    XCTAssertEqual(
      DerivedMapTuningV3Contract.incompleteRunStatus,
      "TUNING_V3_RUN_INCOMPLETE"
    )
    XCTAssertFalse(DerivedMapTuningV3Contract.runCompleteConsoleMarker.contains("PASS"))
    XCTAssertFalse(DerivedMapTuningV3Contract.metricsRecordedStatus.contains("PASS"))
  }

  func testBlindValidationV1ManifestHashFixtureSetAndLaunchAreDistinctAndFrozen() throws {
    let data = try Data(contentsOf: blindValidationManifestURL())
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(hash, DerivedMapBlindValidationV1Contract.frozenManifestSHA256)
    XCTAssertNoThrow(try DerivedMapBlindValidationV1Contract.validateManifestHash(hash))
    XCTAssertThrowsError(try DerivedMapBlindValidationV1Contract.validateManifestHash(
      String(repeating: "0", count: 64)
    )) {
      XCTAssertEqual($0 as? DerivedMapBlindValidationV1Error, .manifestHashDrift)
    }

    let manifest = try DerivedMapBlindValidationV1Manifest.decodeAndValidate(data)
    XCTAssertEqual(manifest.fixtures.map(\.id), DerivedMapBlindValidationV1Contract.expectedFixtureIDs)
    XCTAssertEqual(manifest.fixtures.count, 16)
    XCTAssertTrue(manifest.fixtures.allSatisfy { $0.partition == .holdout })
    XCTAssertTrue(manifest.fixtures.allSatisfy {
      $0.routes == [.rawImageSimulator, .derivedMapIPhone]
    })
    XCTAssertTrue(manifest.fixtures.allSatisfy { !$0.id.hasPrefix("t") })

    let manifestRoot = blindValidationManifestURL().deletingLastPathComponent()
    let permittedStructuralExifKeys: Set<String> = [
      "ColorSpace", "PixelXDimension", "PixelYDimension",
    ]
    for fixture in manifest.fixtures {
      let assetData = try Data(contentsOf: manifestRoot.appendingPathComponent(fixture.asset))
      XCTAssertEqual(
        SHA256.hash(data: assetData).map { String(format: "%02x", $0) }.joined(),
        fixture.sanitizedImageSHA256,
        fixture.id
      )
      let source = try XCTUnwrap(CGImageSourceCreateWithData(assetData as CFData, nil))
      XCTAssertEqual(CGImageSourceGetType(source), "public.jpeg" as CFString)
      let properties = try XCTUnwrap(
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
      )
      XCTAssertNil(properties[kCGImagePropertyGPSDictionary], fixture.id)
      XCTAssertNil(properties[kCGImagePropertyTIFFDictionary], fixture.id)
      XCTAssertNil(properties[kCGImagePropertyIPTCDictionary], fixture.id)
      XCTAssertEqual(
        properties[kCGImagePropertyColorModel] as? String,
        kCGImagePropertyColorModelRGB as String,
        fixture.id
      )
      XCTAssertTrue(
        (properties[kCGImagePropertyProfileName] as? String)?
          .localizedCaseInsensitiveContains("sRGB") == true,
        fixture.id
      )
      let exifKeys = Set(
        ((properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:])
          .keys.map { $0 as String }
      )
      XCTAssertTrue(exifKeys.isSubset(of: permittedStructuralExifKeys), fixture.id)
    }

    XCTAssertNoThrow(try DerivedMapBlindValidationV1Contract.validateLaunch(
      arguments: [DerivedMapBlindValidationV1Contract.launchArgument]
    ))
    XCTAssertThrowsError(try DerivedMapBlindValidationV1Contract.validateLaunch(
      arguments: [
        DerivedMapBlindValidationV1Contract.launchArgument,
        DerivedMapTuningV3Contract.launchArgument,
      ]
    )) {
      XCTAssertEqual($0 as? DerivedMapBlindValidationV1Error, .launchConflict)
    }
  }

  func testBlindValidationLaunchIsolatesJournalAndUsesDistinctTerminalMarkers() throws {
    let arguments = [DerivedMapBlindValidationV1Contract.launchArgument]
    XCTAssertTrue(AppEvaluationLaunchPolicy.isBlindValidation(arguments))
    XCTAssertTrue(AppEvaluationLaunchPolicy.isolatesJournal(arguments))
    XCTAssertFalse(AppEvaluationLaunchPolicy.isTuning(arguments))

    XCTAssertEqual(
      try DerivedMapBlindValidationV1Contract.consoleMarker(
        for: DerivedMapBlindValidationV1Contract.eligibleStatus
      ),
      DerivedMapBlindValidationV1Contract.eligibleStatus
    )
    XCTAssertEqual(
      try DerivedMapBlindValidationV1Contract.consoleMarker(
        for: DerivedMapBlindValidationV1Contract.rejectedStatus
      ),
      DerivedMapBlindValidationV1Contract.rejectedStatus
    )
    XCTAssertEqual(
      try DerivedMapBlindValidationV1Contract.consoleMarker(
        for: DerivedMapBlindValidationV1Contract.incompleteStatus
      ),
      DerivedMapBlindValidationV1Contract.incompleteStatus
    )
    XCTAssertThrowsError(try DerivedMapBlindValidationV1Contract.consoleMarker(for: nil))
  }

  func testBlindValidationConsumptionPersistsBeforePreparationAndRefusesRelaunch() throws {
    let root = temporaryRoot()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let markerURL = root.appendingPathComponent("blind-validation-v1-consumed.json")
    let firstRunID = UUID(uuidString: "45C72B98-FEE4-4B5F-8C08-C27615A5554A")!
    var protectedURL: URL?

    try DerivedMapBlindValidationV1ConsumptionStore.consume(
      runID: firstRunID,
      at: markerURL,
      fileManager: .default,
      protect: { protectedURL = $0 }
    )

    XCTAssertEqual(protectedURL, markerURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
    let firstData = try Data(contentsOf: markerURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let marker = try decoder.decode(DerivedMapBlindValidationV1Consumption.self, from: firstData)
    XCTAssertEqual(marker.runID, firstRunID)
    XCTAssertEqual(marker.lane, DerivedMapBlindValidationV1Contract.lane)
    XCTAssertEqual(marker.manifestSHA256, DerivedMapBlindValidationV1Contract.frozenManifestSHA256)
    XCTAssertEqual(marker.fixtureIDs, DerivedMapBlindValidationV1Contract.expectedFixtureIDs)
    XCTAssertEqual(
      marker.state,
      "CONSUMED_BEFORE_FIRST_MODEL_PREPARATION; RERUN_FORBIDDEN"
    )

    XCTAssertThrowsError(try DerivedMapBlindValidationV1ConsumptionStore.consume(
      runID: UUID(),
      at: markerURL,
      fileManager: .default,
      protect: { _ in XCTFail("A refused relaunch must not reprotect or replace the marker.") }
    )) {
      XCTAssertEqual($0 as? DerivedMapBlindValidationV1Error, .alreadyConsumed)
    }
    XCTAssertEqual(try Data(contentsOf: markerURL), firstData)
  }

  func testBlindValidationCandidateIsFrozenV3BehaviorWithValidationOnlyProvenance() throws {
    let baseline = InferenceConfiguration.physicalCPUVisualBridge
    let tuning = InferenceConfiguration.physicalCPUVisualBridgeExtractorV3TuningCandidate
    let validation = InferenceConfiguration.physicalCPUVisualBridgeExtractorV3BlindValidationCandidate
    XCTAssertTrue(baseline.permitsBlindValidationOverride(validation))
    XCTAssertFalse(baseline.permitsTuningOverride(validation))
    XCTAssertFalse(baseline.permitsEvaluationOverride(validation))
    XCTAssertNotEqual(InferenceConfiguration.runtimeDefault, validation)
    XCTAssertEqual(validation.analysisPipelineVersion, AnalysisPipelineVersion.derivedMapV3BlindValidation)

    XCTAssertEqual(validation.engineBackend, tuning.engineBackend)
    XCTAssertEqual(validation.visionBackend, tuning.visionBackend)
    XCTAssertEqual(validation.maxNumTokens, tuning.maxNumTokens)
    XCTAssertEqual(validation.topK, tuning.topK)
    XCTAssertEqual(validation.topP, tuning.topP)
    XCTAssertEqual(validation.temperature, tuning.temperature)
    XCTAssertEqual(validation.seed, tuning.seed)
    XCTAssertEqual(validation.promptVersion, tuning.promptVersion)
    XCTAssertEqual(validation.imageMessageForm, tuning.imageMessageForm)

    let tuningExtraction = try extract(.brownOrganic, variant: .candidateV3Tuning)
    let validationExtraction = try extract(.brownOrganic, variant: .candidateV3BlindValidation)
    XCTAssertEqual(tuningExtraction.facts, validationExtraction.facts)
    XCTAssertEqual(
      tuningExtraction.diagnostics.v3TuningMetrics,
      validationExtraction.diagnostics.v3TuningMetrics
    )
    XCTAssertEqual(
      tuningExtraction.diagnostics.v3TuningRule,
      validationExtraction.diagnostics.v3TuningRule
    )
    XCTAssertEqual(
      tuningExtraction.diagnostics.v3TuningAbstentionReason,
      validationExtraction.diagnostics.v3TuningAbstentionReason
    )
    XCTAssertEqual(
      validationExtraction.diagnostics.analysisPipelineVersion,
      AnalysisPipelineVersion.derivedMapV3BlindValidation
    )
  }

  func testBlindValidationV1PredeclaredGatesAllowOnlyCleanImprovement() throws {
    let baseline = DerivedMapBlindValidationV1Contract.expectedFixtures.enumerated().map {
      index, expected in
      blindValidationResult(
        expected: expected,
        pipeline: AnalysisPipelineVersion.derivedMapV1,
        suggestion: index < 8 ? 4 : (index == 8 ? 4 : nil),
        latencyMilliseconds: 100,
        peakMemoryBytes: 1_000
      )
    }
    let candidate = DerivedMapBlindValidationV1Contract.expectedFixtures.enumerated().map {
      index, expected in
      blindValidationResult(
        expected: expected,
        pipeline: AnalysisPipelineVersion.derivedMapV3BlindValidation,
        suggestion: index < 8 ? expected.referenceBristolType : (index == 8 ? 4 : nil),
        latencyMilliseconds: 105,
        peakMemoryBytes: 1_000
      )
    }
    let accepted = try DerivedMapBlindValidationV1Contract.decision(
      baselineResults: baseline,
      candidateResults: candidate
    )
    XCTAssertTrue(accepted.eligibleForManualPromotionReview)
    XCTAssertTrue(accepted.reasons.isEmpty)
    XCTAssertEqual(accepted.candidate.correctAbstentionCount, 7)
    XCTAssertGreaterThan(
      accepted.candidate.exactAgreementCount,
      accepted.baseline.exactAgreementCount
    )

    var repaired = candidate
    let first = repaired[0]
    repaired[0] = PhotoSuggestionEvaluationResult(
      fixture: first.fixture,
      pipelineVersion: first.pipelineVersion,
      promptVersion: first.promptVersion,
      suggestedBristolType: first.suggestedBristolType,
      suggestedForm: first.suggestedForm,
      abstained: first.abstained,
      strictJSONValid: true,
      parsePath: .repaired,
      latencyMilliseconds: first.latencyMilliseconds,
      peakMemoryBytes: first.peakMemoryBytes,
      observedImageUsable: first.observedImageUsable,
      observedQualityIssue: first.observedQualityIssue
    )
    let rejected = try DerivedMapBlindValidationV1Contract.decision(
      baselineResults: baseline,
      candidateResults: repaired
    )
    XCTAssertFalse(rejected.eligibleForManualPromotionReview)
    XCTAssertTrue(rejected.reasons.contains("At least one result required repair."))
  }

  func testBlindValidationV1RejectsTargetCoverageRegressionDespiteExactImprovement() throws {
    let baseline = DerivedMapBlindValidationV1Contract.expectedFixtures.enumerated().map {
      index, expected in
      blindValidationResult(
        expected: expected,
        pipeline: AnalysisPipelineVersion.derivedMapV1,
        suggestion: index < 8 ? 1 : (index == 8 ? 4 : nil),
        latencyMilliseconds: 100,
        peakMemoryBytes: 1_000
      )
    }
    let candidate = DerivedMapBlindValidationV1Contract.expectedFixtures.enumerated().map {
      index, expected in
      blindValidationResult(
        expected: expected,
        pipeline: AnalysisPipelineVersion.derivedMapV3BlindValidation,
        suggestion: index < 3 ? expected.referenceBristolType : (index == 8 ? 4 : nil),
        latencyMilliseconds: 100,
        peakMemoryBytes: 1_000
      )
    }

    let decision = try DerivedMapBlindValidationV1Contract.decision(
      baselineResults: baseline,
      candidateResults: candidate
    )

    XCTAssertGreaterThan(
      decision.candidate.exactAgreementCount,
      decision.baseline.exactAgreementCount
    )
    XCTAssertLessThan(
      decision.candidate.labeledCoverageCount,
      decision.baseline.labeledCoverageCount
    )
    XCTAssertFalse(decision.eligibleForManualPromotionReview)
    XCTAssertEqual(decision.reasons, ["Candidate target coverage regressed from baseline."])
  }

  func testDerivedMapV3TuningRuntimeAndModelContractFailClosed() throws {
    let candidate = InferenceConfiguration.physicalCPUVisualBridgeExtractorV3TuningCandidate
    let changedCandidate = InferenceConfiguration(
      id: candidate.id,
      engineBackend: candidate.engineBackend,
      visionBackend: candidate.visionBackend,
      maxNumTokens: candidate.maxNumTokens,
      topK: 2,
      topP: candidate.topP,
      temperature: candidate.temperature,
      seed: candidate.seed,
      promptVersion: candidate.promptVersion,
      imageMessageForm: candidate.imageMessageForm
    )
    XCTAssertThrowsError(try DerivedMapTuningV3Contract.validateRuntimeContract(
      baseline: .physicalCPUVisualBridge,
      candidate: changedCandidate,
      descriptor: .liteRTGemma4E4B
    )) {
      XCTAssertEqual($0 as? DerivedMapTuningV3Error, .configurationDrift)
    }

    let descriptor = ModelDescriptor.liteRTGemma4E4B
    let changedDescriptor = try ModelDescriptor(
      id: descriptor.id,
      family: descriptor.family,
      modelID: descriptor.modelID,
      artifactFilename: descriptor.artifactFilename,
      sourceRevision: descriptor.sourceRevision,
      sourceURL: descriptor.sourceURL,
      expectedSHA256: String(repeating: "f", count: 64),
      expectedBytes: descriptor.expectedBytes,
      cacheNamespace: descriptor.cacheNamespace,
      minimumMemoryGB: descriptor.minimumMemoryGB
    )
    XCTAssertThrowsError(try DerivedMapTuningV3Contract.validateRuntimeContract(
      baseline: .physicalCPUVisualBridge,
      candidate: candidate,
      descriptor: changedDescriptor
    )) {
      XCTAssertEqual($0 as? DerivedMapTuningV3Error, .modelDrift)
    }

    let badReceipt = ModelVerificationReceipt(
      descriptorID: descriptor.id,
      modelID: descriptor.modelID,
      sourceRevision: descriptor.sourceRevision,
      artifactFilename: descriptor.artifactFilename,
      importedBytes: descriptor.expectedBytes,
      importedSHA256: String(repeating: "0", count: 64),
      verifiedAt: Date(),
      locationKind: .applicationBundle,
      appBuildIdentity: .current
    )
    XCTAssertThrowsError(try DerivedMapTuningV3Contract.validateReceipt(badReceipt)) {
      XCTAssertEqual($0 as? DerivedMapTuningV3Error, .modelDrift)
    }
  }

  func testDerivedMapV3TuningSessionRunsBaselineThenCandidateOnOnePreparedIdentity() async throws {
    let runtime = CountingPhotoEvaluationSessionRuntime()
    let analysisSpy = DerivedMapTuningV3AnalysisSessionSpy()
    let execution = try await DerivedMapTuningV3Session.run(
      runtime: runtime,
      descriptor: .liteRTGemma4E4B,
      baseline: .physicalCPUVisualBridge,
      candidate: .physicalCPUVisualBridgeExtractorV3TuningCandidate
    ) { phases in
      let baseline = try await phases.runBaselineAnalysis { sessionIdentity in
        try await analysisSpy.analyze(.baseline, sessionIdentity: sessionIdentity)
      }
      let candidate = try await phases.runCandidateAnalysis { sessionIdentity in
        try await analysisSpy.analyze(.candidate, sessionIdentity: sessionIdentity)
      }
      return (
        output: "\(baseline)-\(candidate)",
        identity: phases.sessionIdentity,
        phase: phases.phase,
        baselineCount: phases.baselineAnalysisCount,
        candidateCount: phases.candidateAnalysisCount
      )
    }
    XCTAssertEqual(execution.output, "baseline-candidate")
    XCTAssertEqual(execution.phase, .candidateComplete)
    XCTAssertEqual(execution.baselineCount, 1)
    XCTAssertEqual(execution.candidateCount, 1)
    let events = await analysisSpy.events()
    XCTAssertEqual(events.map(\.lane), [.baseline, .candidate])
    XCTAssertEqual(Set(events.map(\.sessionIdentity)), Set([execution.identity]))
    var counts = await runtime.counts()
    XCTAssertEqual(counts.prepare, 1)
    XCTAssertEqual(counts.invalidate, 1)

    let secondSessionRuntime = CountingPhotoEvaluationSessionRuntime()
    do {
      let _: String = try await DerivedMapTuningV3Session.run(
        runtime: secondSessionRuntime,
        descriptor: .liteRTGemma4E4B,
        baseline: .physicalCPUVisualBridge,
        candidate: .physicalCPUVisualBridgeExtractorV3TuningCandidate
      ) { phases in
        try await phases.runBaselineAnalysis { sessionIdentity in
          try await analysisSpy.analyze(.baseline, sessionIdentity: sessionIdentity)
        }
      }
      XCTFail("A second prepared session must not be accepted as the candidate continuation.")
    } catch DerivedMapTuningV3Error.sessionPhaseDrift {
      // Expected: the spy was already bound to the first prepared identity.
    }
    counts = await secondSessionRuntime.counts()
    XCTAssertEqual(counts.prepare, 1)
    XCTAssertEqual(counts.invalidate, 1)

    let failingRuntime = CountingPhotoEvaluationSessionRuntime()
    do {
      let _: Void = try await DerivedMapTuningV3Session.run(
        runtime: failingRuntime,
        descriptor: .liteRTGemma4E4B,
        baseline: .physicalCPUVisualBridge,
        candidate: .physicalCPUVisualBridgeExtractorV3TuningCandidate
      ) { _ in
        throw EvaluationSessionTestError.expected
      }
      XCTFail("The tuning operation failure must escape.")
    } catch EvaluationSessionTestError.expected {
      // Expected.
    }
    counts = await failingRuntime.counts()
    XCTAssertEqual(counts.prepare, 1)
    XCTAssertEqual(counts.invalidate, 1)
  }

  /// These are intentionally overfit assertions for one synthetic, non-health
  /// exemplar per supported class. Passing them is not clinical validation and
  /// cannot make v3 eligible for production or locked-holdout use.
  func testDerivedMapV3TuningSingleSyntheticExemplarsHaveFrozenHashesAndExpectedOutputs() throws {
    XCTAssertEqual(
      Set(LocalPixelV3TuningRule.allCases.map(\.bristolType)),
      Set([1, 3, 4, 5, 7]),
      "Types 2 and 6 must remain unsupported rather than nearest-neighbor coerced."
    )

    for expectation in v3TuningAssetExpectations {
      let url = tuningAssetURL(expectation.filename)
      let data = try Data(contentsOf: url)
      let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      XCTAssertEqual(hash, expectation.sha256, expectation.id)

      let extraction = try LocalPixelFeatureExtractor.extractDetailed(
        from: url,
        variant: .candidateV3Tuning
      )
      XCTAssertEqual(extraction.diagnostics.sanitizedImageSHA256, expectation.sha256, expectation.id)
      XCTAssertEqual(extraction.diagnostics.analysisPipelineVersion, AnalysisPipelineVersion.derivedMapV3Tuning)
      XCTAssertEqual(extraction.facts.schemaVersion, "local-pixel-facts-v3-tuning")
      XCTAssertEqual(extraction.facts.qualityHint, expectation.qualityHint, expectation.id)
      XCTAssertEqual(extraction.facts.bristolTypeHint, expectation.bristolType, expectation.id)
      XCTAssertEqual(extraction.facts.formHint, expectation.form, expectation.id)
      XCTAssertEqual(extraction.diagnostics.v3TuningRule, expectation.rule, expectation.id)
      XCTAssertNotNil(extraction.diagnostics.v3TuningMetrics, expectation.id)

      if expectation.bristolType == nil {
        XCTAssertNotEqual(extraction.facts.qualityHint, "none", expectation.id)
        XCTAssertEqual(extraction.facts.apparentColorHint, "unable_to_assess", expectation.id)
        XCTAssertEqual(extraction.facts.formHint, "unable_to_assess", expectation.id)
        XCTAssertNotNil(extraction.diagnostics.v3TuningAbstentionReason, expectation.id)
        XCTAssertFalse(DerivedMapPostconditions.expectedObservation(for: extraction.facts).imageUsable)
      } else {
        XCTAssertEqual(extraction.facts.qualityHint, "none", expectation.id)
        XCTAssertEqual(extraction.facts.apparentColorHint, "brown", expectation.id)
        XCTAssertNil(extraction.diagnostics.v3TuningAbstentionReason, expectation.id)
      }
    }
  }

  func testDerivedMapV3TuningNonTargetAndQualityAssetsHardFailEveryFalsePositiveAfterMildPerturbation() throws {
    for expectation in v3TuningAssetExpectations where expectation.bristolType == nil {
      let source = try Data(contentsOf: tuningAssetURL(expectation.filename))
      for (name, data) in [
        ("jpeg75", try recompressedJPEG(source, quality: 0.75)),
        ("mirrored", try horizontallyMirroredJPEG(source)),
      ] {
        let extraction = try extractV3TuningData(data)
        XCTAssertNil(
          extraction.facts.bristolTypeHint,
          "\(expectation.id)/\(name) is a hard false-positive failure."
        )
        XCTAssertNotEqual(extraction.facts.qualityHint, "none", "\(expectation.id)/\(name)")
        XCTAssertEqual(extraction.facts.formHint, "unable_to_assess", "\(expectation.id)/\(name)")
      }
    }
  }

  func testDerivedMapV3TuningMildTargetPerturbationsNeverChangeToAnotherClass() throws {
    for expectation in v3TuningAssetExpectations where expectation.bristolType != nil {
      let source = try Data(contentsOf: tuningAssetURL(expectation.filename))
      for (name, data) in [
        ("jpeg75", try recompressedJPEG(source, quality: 0.75)),
        ("mirrored", try horizontallyMirroredJPEG(source)),
      ] {
        let extraction = try extractV3TuningData(data)
        XCTAssertTrue(
          extraction.facts.bristolTypeHint == nil
            || extraction.facts.bristolTypeHint == expectation.bristolType,
          "\(expectation.id)/\(name) changed to a different non-null class."
        )
        if extraction.facts.bristolTypeHint != nil {
          XCTAssertEqual(extraction.facts.formHint, expectation.form, "\(expectation.id)/\(name)")
        }
      }
    }
  }

  func testDerivedMapV3TuningSevereDerivedPerturbationsAbstainInsteadOfChangingClass() throws {
    let source = try Data(contentsOf: tuningAssetURL("t12-type4-cold-start.jpg"))
    let perturbations = [
      ("dark", try filteredJPEG(source, filterName: "CIColorControls", parameters: ["inputBrightness": -0.75])),
      ("greenHue", try filteredJPEG(source, filterName: "CIHueAdjust", parameters: ["inputAngle": 2.0])),
      ("blur", try filteredJPEG(source, filterName: "CIGaussianBlur", parameters: ["inputRadius": 42.0])),
      ("glare", try glareOverlaidJPEG(source)),
    ]

    for (name, data) in perturbations {
      let extraction = try extractV3TuningData(data)
      XCTAssertNil(extraction.facts.bristolTypeHint, "Severe \(name) must abstain.")
      XCTAssertNotEqual(extraction.facts.qualityHint, "none", "Severe \(name) must fail closed.")
      XCTAssertEqual(extraction.facts.formHint, "unable_to_assess")
    }
  }

  func testDerivedMapV3TuningRuleBoundariesAndAmbiguityFailClosed() {
    let type4Core = v3Metrics(
      targetCoverage: 0.21,
      elongation: 2.50,
      compactness: 0.50,
      solidityProxy: 0.86,
      subjectLuminanceMean: 0.35,
      subjectLuminanceStandardDeviation: 0.048,
      subjectSaturationMean: 0.62,
      subjectSaturationStandardDeviation: 0.073
    )
    XCTAssertEqual(
      LocalPixelFeatureExtractor.matchingV3TuningRules(for: type4Core),
      [.type4SmoothFormed]
    )

    let outsideType4Core = v3Metrics(
      targetCoverage: 0.21,
      elongation: 2.50,
      compactness: 0.50,
      solidityProxy: 0.86,
      subjectLuminanceMean: 0.35,
      subjectLuminanceStandardDeviation: 0.061,
      subjectSaturationMean: 0.62,
      subjectSaturationStandardDeviation: 0.073
    )
    XCTAssertTrue(LocalPixelFeatureExtractor.matchingV3TuningRules(for: outsideType4Core).isEmpty)
    XCTAssertNil(LocalPixelFeatureExtractor.resolveV3TuningMatches([]))
    XCTAssertNil(LocalPixelFeatureExtractor.resolveV3TuningMatches([
      .type3CrackedFormed,
      .type4SmoothFormed,
    ]))
  }

  private struct V3TuningAssetExpectation {
    let id: String
    let filename: String
    let sha256: String
    let qualityHint: String
    let bristolType: Int?
    let form: String
    let rule: LocalPixelV3TuningRule?
  }

  private var v3TuningAssetExpectations: [V3TuningAssetExpectation] {
    [
      V3TuningAssetExpectation(
        id: "t01-type1-brown-lumps",
        filename: "t01-type1-brown-lumps.jpg",
        sha256: "e83ba8778ea30d947cca0802dc22342547c001961d6d19b5bb82b3d8d07cd05e",
        qualityHint: "none",
        bristolType: 1,
        form: "hard_lumps",
        rule: .type1HardLumps
      ),
      V3TuningAssetExpectation(
        id: "t02-type3-cracked-formed",
        filename: "t02-type3-cracked-formed.jpg",
        sha256: "7ab0aef66c9dd7e1723a17271be858c0b762ab9c32795c3b1473fd19e28ef116",
        qualityHint: "none",
        bristolType: 3,
        form: "cracked_formed",
        rule: .type3CrackedFormed
      ),
      V3TuningAssetExpectation(
        id: "t03-type5-soft-blobs",
        filename: "t03-type5-soft-blobs.jpg",
        sha256: "984910bae71e8753d9904ee20e46fa7e00719bafc83278ce45fd06e84a2e4403",
        qualityHint: "none",
        bristolType: 5,
        form: "soft_blobs",
        rule: .type5SoftBlobs
      ),
      V3TuningAssetExpectation(
        id: "t04-type7-watery-pool",
        filename: "t04-type7-watery-pool.jpg",
        sha256: "769a6ef45f1b7cfc641d59f3a91e32b731b4442fe350ed76a348ae931b309949",
        qualityHint: "none",
        bristolType: 7,
        form: "watery",
        rule: .type7Watery
      ),
      V3TuningAssetExpectation(
        id: "t05-mixed-hard-loose",
        filename: "t05-mixed-hard-loose.jpg",
        sha256: "f04cf1524eeb87d90055b954a3a4e047965c24f5f5b9769abcb711d3a68efc23",
        qualityHint: "other",
        bristolType: nil,
        form: "unable_to_assess",
        rule: nil
      ),
      V3TuningAssetExpectation(
        id: "t06-severe-darkness",
        filename: "t06-severe-darkness.jpg",
        sha256: "5baa425c2afac1ca3ebda872f74a0c47cf1580afcdb3435017bf2586ed85055b",
        qualityHint: "too_dark",
        bristolType: nil,
        form: "unable_to_assess",
        rule: nil
      ),
      V3TuningAssetExpectation(
        id: "t07-severe-glare",
        filename: "t07-severe-glare.jpg",
        sha256: "c663e73094172a742f981b24f0e9e03ba748e11ac4ceceade80555ca2cac151a",
        qualityHint: "other",
        bristolType: nil,
        form: "unable_to_assess",
        rule: nil
      ),
      V3TuningAssetExpectation(
        id: "t08-brown-wood-block",
        filename: "t08-brown-wood-block.jpg",
        sha256: "1f13896180c5b3f3f4fcc9cd2c632c2eb5349d490dc7f8141b6fc3f68b4d32ed",
        qualityHint: "not_target_image",
        bristolType: nil,
        form: "unable_to_assess",
        rule: nil
      ),
      V3TuningAssetExpectation(
        id: "t09-red-capsule",
        filename: "t09-red-capsule.jpg",
        sha256: "acf3e57b8236eab4a88de33d34aa2961f2ca25e18f9774e9788b17ea61cd54cc",
        qualityHint: "not_target_image",
        bristolType: nil,
        form: "unable_to_assess",
        rule: nil
      ),
      V3TuningAssetExpectation(
        id: "t10-patterned-rug",
        filename: "t10-patterned-rug.jpg",
        sha256: "430d359f20988c60a947a9de7f42d45679100f78bbc4976f4499704764b09fe0",
        qualityHint: "not_target_image",
        bristolType: nil,
        form: "unable_to_assess",
        rule: nil
      ),
      V3TuningAssetExpectation(
        id: "t11-green-smooth-prop",
        filename: "t11-green-smooth-prop.jpg",
        sha256: "0eadcccc35f56b0b9bdd7f1bb092267ab9b4fc2b0c67a7f8f2080c34b9dd0a14",
        qualityHint: "not_target_image",
        bristolType: nil,
        form: "unable_to_assess",
        rule: nil
      ),
      V3TuningAssetExpectation(
        id: "t12-type4-cold-start",
        filename: "t12-type4-cold-start.jpg",
        sha256: "023ca013c9ce4eddbc6cb12a6647c5c14e3f5ad1255c8919a3ca5f4161deb3bc",
        qualityHint: "none",
        bristolType: 4,
        form: "smooth_formed",
        rule: .type4SmoothFormed
      ),
    ]
  }

  private func tuningAssetURL(_ filename: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("work/photo-evaluation/assets", isDirectory: true)
      .appendingPathComponent(filename)
  }

  private func tuningManifestURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("work/photo-evaluation", isDirectory: true)
      .appendingPathComponent(DerivedMapTuningV3Contract.manifestFilename)
  }

  private func blindValidationManifestURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("work/photo-evaluation/blind-validation-v1", isDirectory: true)
      .appendingPathComponent(DerivedMapBlindValidationV1Contract.manifestFilename)
  }

  private func extractV3TuningData(_ data: Data) throws -> LocalPixelExtraction {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("v3-tuning-perturbation.jpg")
    try data.write(to: url, options: .atomic)
    return try LocalPixelFeatureExtractor.extractDetailed(from: url, variant: .candidateV3Tuning)
  }

  private func recompressedJPEG(_ data: Data, quality: CGFloat) throws -> Data {
    let image = try XCTUnwrap(UIImage(data: data))
    return try XCTUnwrap(image.jpegData(compressionQuality: quality))
  }

  private func horizontallyMirroredJPEG(_ data: Data) throws -> Data {
    let image = try XCTUnwrap(UIImage(data: data))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.preferredRange = .standard
    let mirrored = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
      context.cgContext.translateBy(x: image.size.width, y: 0)
      context.cgContext.scaleBy(x: -1, y: 1)
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }
    return try XCTUnwrap(mirrored.jpegData(compressionQuality: 0.92))
  }

  private func filteredJPEG(
    _ data: Data,
    filterName: String,
    parameters: [String: Any]
  ) throws -> Data {
    let input = try XCTUnwrap(CIImage(data: data))
    let filter = try XCTUnwrap(CIFilter(name: filterName))
    filter.setValue(input, forKey: kCIInputImageKey)
    for (key, value) in parameters { filter.setValue(value, forKey: key) }
    let output = try XCTUnwrap(filter.outputImage).cropped(to: input.extent)
    let context = CIContext(options: [.cacheIntermediates: false])
    let cgImage = try XCTUnwrap(context.createCGImage(output, from: input.extent))
    return try XCTUnwrap(UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92))
  }

  private func glareOverlaidJPEG(_ data: Data) throws -> Data {
    let image = try XCTUnwrap(UIImage(data: data))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.preferredRange = .standard
    let overlaid = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
      image.draw(in: CGRect(origin: .zero, size: image.size))
      UIColor.white.setFill()
      context.cgContext.fillEllipse(in: CGRect(
        x: image.size.width * 0.34,
        y: image.size.height * 0.39,
        width: image.size.width * 0.42,
        height: image.size.height * 0.24
      ))
    }
    return try XCTUnwrap(overlaid.jpegData(compressionQuality: 0.92))
  }

  private func v3Metrics(
    componentCount: Int = 1,
    targetCoverage: Double,
    elongation: Double,
    compactness: Double,
    solidityProxy: Double,
    subjectLuminanceMean: Double,
    subjectLuminanceStandardDeviation: Double,
    subjectSaturationMean: Double,
    subjectSaturationStandardDeviation: Double
  ) -> LocalPixelV3TuningMetrics {
    LocalPixelV3TuningMetrics(
      componentCount: componentCount,
      targetCoverage: targetCoverage,
      largestComponentCoverage: targetCoverage,
      componentDominance: 1,
      secondToLargestAreaRatio: 0,
      elongation: elongation,
      compactness: compactness,
      solidityProxy: solidityProxy,
      boundingEdgeFraction: 0.03,
      patternTransitionRate: 0.03,
      sharpness: 0.03,
      subjectLuminanceMean: subjectLuminanceMean,
      subjectLuminanceStandardDeviation: subjectLuminanceStandardDeviation,
      subjectSaturationMean: subjectSaturationMean,
      subjectSaturationStandardDeviation: subjectSaturationStandardDeviation,
      subjectBoundingBoxHighlightFraction: 0,
      subjectHueEntropy: 0,
      brownShare: 1,
      greenShare: 0,
      colorMargin: 1,
      meanLuminance: 0.76,
      darkFraction: 0,
      edgeTouchDetected: true
    )
  }

  private enum SyntheticControl {
    case brownOrganic
    case brownBlock
    case greenOrganic
    case dark
    case glare
    case cropped
    case distant
    case blurred
    case brownGreenAmbiguous

  }

  private func tuningResult(
    id: String,
    pipeline: String,
    suggestion: Int?,
    sanitizedImageSHA256Override: String? = nil,
    referenceBristolTypeOverride: Int? = nil,
    referenceFormOverride: String? = nil,
    expectedAbstentionOverride: Bool? = nil
  ) -> PhotoSuggestionEvaluationResult {
    guard let expected = DerivedMapTuningV3Contract.expectedFixtures.first(where: {
      $0.id == id
    }) else {
      preconditionFailure("Unknown frozen tuning fixture \(id)")
    }
    return PhotoSuggestionEvaluationResult(
      fixture: PhotoEvaluationFixture(
        id: id,
        partition: .tuning,
        sanitizedImageSHA256: sanitizedImageSHA256Override
          ?? expected.sanitizedImageSHA256,
        route: .derivedMapIPhone,
        referenceBristolType: referenceBristolTypeOverride
          ?? expected.referenceBristolType,
        referenceForm: referenceFormOverride ?? expected.referenceForm,
        expectedAbstention: expectedAbstentionOverride
          ?? expected.expectedAbstention
      ),
      pipelineVersion: pipeline,
      promptVersion: "gi-local-pixel-bridge-v1",
      suggestedBristolType: suggestion,
      suggestedForm: suggestion.flatMap(BristolFormContract.expectedForm(for:))
        ?? "unable_to_assess",
      abstained: suggestion == nil,
      strictJSONValid: true,
      parsePath: .direct,
      latencyMilliseconds: 10,
      peakMemoryBytes: 1_000
    )
  }

  private func blindValidationResult(
    expected: DerivedMapBlindValidationV1Contract.ExpectedFixture,
    pipeline: String,
    suggestion: Int?,
    latencyMilliseconds: Double,
    peakMemoryBytes: UInt64
  ) -> PhotoSuggestionEvaluationResult {
    PhotoSuggestionEvaluationResult(
      fixture: PhotoEvaluationFixture(
        id: expected.id,
        partition: .holdout,
        sanitizedImageSHA256: expected.sanitizedImageSHA256,
        route: .derivedMapIPhone,
        referenceBristolType: expected.referenceBristolType,
        referenceForm: expected.referenceForm,
        expectedAbstention: expected.expectedAbstention,
        expectedImageUsable: expected.expectedQualityIssue == "none",
        expectedQualityIssue: expected.expectedQualityIssue
      ),
      pipelineVersion: pipeline,
      promptVersion: InferenceConfiguration.physicalCPUVisualBridge.promptVersion,
      suggestedBristolType: suggestion,
      suggestedForm: suggestion.flatMap(BristolFormContract.expectedForm(for:))
        ?? "unable_to_assess",
      abstained: suggestion == nil,
      strictJSONValid: true,
      parsePath: .direct,
      latencyMilliseconds: latencyMilliseconds,
      peakMemoryBytes: peakMemoryBytes,
      observedImageUsable: suggestion != nil,
      observedQualityIssue: suggestion != nil
        ? "none"
        : (expected.expectedAbstention ? expected.expectedQualityIssue : "other")
    )
  }

  private func tuningManifestData(
    partitionDriftID: String? = nil,
    routeDriftID: String? = nil,
    appendingUnexpectedFixture: Bool = false
  ) throws -> Data {
    var fixtures: [[String: Any]] = DerivedMapTuningV3Contract.expectedFixtures.map { expected in
      var fixture: [String: Any] = [
        "id": expected.id,
        "partition": expected.id == partitionDriftID ? "holdout" : "tuning",
        "route": expected.id == routeDriftID
          ? PhotoEvaluationRoute.rawImageSimulator.rawValue
          : PhotoEvaluationRoute.derivedMapIPhone.rawValue,
        "asset": "assets/\(expected.id).jpg",
        "sanitized_image_sha256": expected.sanitizedImageSHA256,
        "reference_bristol_type": expected.referenceBristolType ?? NSNull(),
        "reference_form": expected.referenceForm,
        "expected_abstention": expected.expectedAbstention,
      ]
      if expected.id == partitionDriftID || expected.id == routeDriftID {
        fixture["reference_bristol_type"] = "must-not-decode"
      }
      return fixture
    }
    if appendingUnexpectedFixture {
      fixtures.append([
        "id": "h01-forbidden-entry",
        "partition": "holdout",
        "route": PhotoEvaluationRoute.derivedMapIPhone.rawValue,
        "asset": "assets/h01-forbidden-entry.jpg",
        "sanitized_image_sha256": String(repeating: "b", count: 64),
        "reference_bristol_type": "must-not-decode",
        "reference_form": "must-not-decode",
        "expected_abstention": true,
      ])
    }
    let manifest: [String: Any] = [
      "manifest_version": DerivedMapTuningV3Contract.frozenManifestVersion,
      "frozen_at_utc": DerivedMapTuningV3Contract.frozenAtUTC,
      "lane": DerivedMapTuningV3Contract.lane,
      "route": PhotoEvaluationRoute.derivedMapIPhone.rawValue,
      "partition": "tuning",
      "asset_contract": [
        "source_category": "synthetic_non_health",
        "contains_real_health_photos": false,
        "asset_format": DerivedMapTuningV3Contract.assetFormat,
        "hash_field": "sanitized_image_sha256",
        "limitations": "Synthetic only",
      ],
      "pipelines": [
        "baseline": AnalysisPipelineVersion.derivedMapV1,
        "candidate": AnalysisPipelineVersion.derivedMapV3Tuning,
      ],
      "fixtures": fixtures,
    ]
    return try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
  }

  private func extract(
    _ control: SyntheticControl,
    variant: LocalPixelExtractorVariant
  ) throws -> LocalPixelExtraction {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let prepared = try makeImageStore(root: root).prepare(render(control))
    return try LocalPixelFeatureExtractor.extractDetailed(from: prepared.url, variant: variant)
  }

  private func render(_ control: SyntheticControl) -> Data {
    let size = CGSize(width: 640, height: 480)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.preferredRange = .standard
    let base = UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor(red: 0.91, green: 0.88, blue: 0.82, alpha: 1).setFill()
      context.fill(CGRect(origin: .zero, size: size))
      switch control {
      case .brownOrganic, .blurred:
        UIColor(red: 0.48, green: 0.25, blue: 0.10, alpha: 1).setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 100, y: 180, width: 440, height: 120))
      case .brownBlock:
        UIColor(red: 0.48, green: 0.25, blue: 0.10, alpha: 1).setFill()
        context.fill(CGRect(x: 95, y: 175, width: 450, height: 130))
      case .greenOrganic:
        UIColor(red: 0.25, green: 0.48, blue: 0.17, alpha: 1).setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 100, y: 180, width: 440, height: 120))
      case .dark:
        UIColor(white: 0.025, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
        UIColor(red: 0.08, green: 0.04, blue: 0.02, alpha: 1).setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 100, y: 180, width: 440, height: 120))
      case .glare:
        UIColor(red: 0.48, green: 0.25, blue: 0.10, alpha: 1).setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 100, y: 160, width: 440, height: 160))
        UIColor.white.setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 190, y: 130, width: 270, height: 220))
      case .cropped:
        UIColor(red: 0.48, green: 0.25, blue: 0.10, alpha: 1).setFill()
        context.cgContext.fillEllipse(in: CGRect(x: -190, y: 130, width: 500, height: 220))
      case .distant:
        UIColor(red: 0.48, green: 0.25, blue: 0.10, alpha: 1).setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 300, y: 232, width: 40, height: 16))
      case .brownGreenAmbiguous:
        UIColor(red: 0.48, green: 0.25, blue: 0.10, alpha: 1).setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 80, y: 150, width: 320, height: 180))
        UIColor(red: 0.25, green: 0.48, blue: 0.17, alpha: 0.95).setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 250, y: 150, width: 320, height: 180))
      }
    }

    let output: UIImage
    if control == .blurred,
      let input = CIImage(image: base),
      let filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: input, kCIInputRadiusKey: 28]),
      let blurred = filter.outputImage,
      let cgImage = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any]).createCGImage(blurred, from: input.extent)
    {
      output = UIImage(cgImage: cgImage)
    } else {
      output = base
    }
    return output.jpegData(compressionQuality: 0.9)!
  }

  private func makeImageStore(root: URL) -> ImageStore {
    ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("PhotoSuggestionAccuracyTests-\(UUID().uuidString)", isDirectory: true)
  }
}

private enum EvaluationSessionTestError: Error {
  case expected
}

private actor DerivedMapTuningV3AnalysisSessionSpy {
  enum Lane: Equatable, Sendable {
    case baseline
    case candidate
  }

  struct Event: Equatable, Sendable {
    let lane: Lane
    let sessionIdentity: UUID
  }

  private var boundSessionIdentity: UUID?
  private var recordedEvents: [Event] = []

  func analyze(_ lane: Lane, sessionIdentity: UUID) throws -> String {
    if let boundSessionIdentity {
      guard boundSessionIdentity == sessionIdentity else {
        throw DerivedMapTuningV3Error.sessionPhaseDrift
      }
    } else {
      boundSessionIdentity = sessionIdentity
    }
    recordedEvents.append(Event(lane: lane, sessionIdentity: sessionIdentity))
    return lane == .baseline ? "baseline" : "candidate"
  }

  func events() -> [Event] { recordedEvents }
}

private actor CountingPhotoEvaluationSessionRuntime: PhotoEvaluationSessionRuntime {
  private var prepareCallCount = 0
  private var invalidateCallCount = 0

  func prepare(_ descriptor: ModelDescriptor) -> EnginePreparationResult {
    prepareCallCount += 1
    return EnginePreparationResult(seconds: 0, reusedCurrentProcessEngine: false)
  }

  func invalidate(_ descriptor: ModelDescriptor) {
    invalidateCallCount += 1
  }

  func counts() -> (prepare: Int, invalidate: Int) {
    (prepareCallCount, invalidateCallCount)
  }
}

private final class EvaluationOverrideNonCooperativeProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var valueContinuation: CheckedContinuation<String, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var hasStarted = false

  func value() async -> String {
    await withCheckedContinuation { continuation in
      lock.lock()
      valueContinuation = continuation
      hasStarted = true
      let waiters = startWaiters
      startWaiters.removeAll()
      lock.unlock()
      waiters.forEach { $0.resume() }
    }
  }

  func waitUntilStarted() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if hasStarted {
        lock.unlock()
        continuation.resume()
      } else {
        startWaiters.append(continuation)
        lock.unlock()
      }
    }
  }

  func finish() {
    lock.lock()
    let continuation = valueContinuation
    valueContinuation = nil
    lock.unlock()
    continuation?.resume(returning: "late")
  }
}
