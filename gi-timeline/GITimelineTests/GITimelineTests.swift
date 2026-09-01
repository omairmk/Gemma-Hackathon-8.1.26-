import CryptoKit
import ImageIO
import GITimelineCore
import PDFKit
import SwiftData
import UIKit
import XCTest
@testable import GITimeline

@MainActor final class GITimelineTests: XCTestCase {
  private let valid = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"

  func testRepairDoubleFailureKeepsDraftAndAllowsCleanManualSave() async throws {
    let harness = try makeHarness(scripts: [.malformed("not json"), .malformed("still not json")])
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draft = try XCTUnwrap(harness.viewModel.currentDraftURL)

    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)

    XCTAssertNil(harness.viewModel.reviewedObservation)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draft.path))
    XCTAssertFalse(harness.viewModel.canSave)
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Inference failure must enter manual review.")
    }
    XCTAssertEqual(harness.viewModel.statusMessage, "We couldn’t prepare a suggestion. Your photo is still here. Choose the closest stool type yourself to continue.")

    completeRequiredReview(harness.viewModel)
    XCTAssertTrue(harness.viewModel.canSave)
    harness.viewModel.save()
    let entry = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertEqual(entry.provenance, EntryProvenance.manual.rawValue)
    XCTAssertNil(entry.originalAIJSON)
    guard case .confirmedV1(let confirmation) = try StoredReviewedEntry.parse(
      XCTUnwrap(entry.reviewedJSON)
    ) else { return XCTFail("A new manual save must retain its whole-entry confirmation envelope.") }
    XCTAssertTrue(confirmation.typedFieldProvenance.values.allSatisfy { $0 == .manualNoSuggestion })
    XCTAssertFalse(FileManager.default.fileExists(atPath: draft.path))
  }

  func testMalformedInitialResponseValidRepairProducesReviewAndRetainsDraft() async throws {
    let harness = try makeHarness(scripts: [.malformed("not json"), .response(valid)])
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draft = try XCTUnwrap(harness.viewModel.currentDraftURL)

    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)

    let observation = try XCTUnwrap(harness.viewModel.reviewedObservation)
    XCTAssertEqual(observation.apparentColor, "brown")
    XCTAssertEqual(harness.viewModel.currentDraftURL, draft)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draft.path))
    XCTAssertEqual(harness.viewModel.suggestedRedMaterial, .no)
    XCTAssertEqual(harness.viewModel.suggestedBlackTarry, .no)
    XCTAssertEqual(harness.viewModel.redBlood, .no)
    XCTAssertEqual(harness.viewModel.blackTarry, .no)
    XCTAssertEqual(
      harness.viewModel.redSuggestionHint,
      "AI suggestion: No blood-like red material detected in this photo."
    )
    XCTAssertEqual(
      harness.viewModel.blackSuggestionHint,
      "AI suggestion: No black or tar-like appearance detected in this photo."
    )
    XCTAssertTrue(harness.viewModel.canSave)
    XCTAssertEqual(harness.viewModel.outstandingReviewCount, 0)
    XCTAssertNil(harness.viewModel.statusMessage)
  }

  func testInferenceFailurePreservesDraftAndContinuesManuallyOnSameDraft() async throws {
    let harness = try makeHarness(scripts: [
      .malformed("not json"),
      .malformed("still not json"),
    ])
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draft = try XCTUnwrap(harness.viewModel.currentDraftURL)

    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    XCTAssertNil(harness.viewModel.reviewedObservation)
    XCTAssertEqual(harness.viewModel.currentDraftURL, draft)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draft.path))
    XCTAssertFalse(harness.viewModel.canAnalyze)
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Inference failure must activate manual review.")
    }
    completeRequiredReview(harness.viewModel)
    XCTAssertTrue(harness.viewModel.canSave)
    harness.viewModel.save()
    XCTAssertEqual(harness.store.records.first?.savedAnalysisSource, .manual)
  }

  func testSaveFailureRollsBackCopyKeepsDraftAndRetryCreatesExactlyOne() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draft = try XCTUnwrap(harness.viewModel.currentDraftURL)
    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)
    harness.viewModel.note = "kept state"
    harness.store.failNextSave = true

    harness.viewModel.save()

    XCTAssertEqual(harness.store.records.count, 0)
    XCTAssertEqual(harness.store.rollbackCount, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draft.path))
    XCTAssertFalse(harness.store.lastCopiedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? true)
    XCTAssertEqual(harness.viewModel.note, "kept state")
    XCTAssertTrue(harness.viewModel.canSave)

    harness.viewModel.save()
    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertEqual(harness.store.records.first?.note, "kept state")
    XCTAssertNil(harness.viewModel.currentDraftURL)
    XCTAssertFalse(harness.viewModel.canSave)
  }

  func testSuccessfulSaveResetsFormAndStartsFreshSecondEntry() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData(color: .brown))
    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)
    harness.viewModel.redBlood = .yes
    harness.viewModel.save()
    XCTAssertNil(harness.viewModel.redBlood)
    XCTAssertEqual(harness.store.records.count, 1)

    harness.viewModel.startAnotherEntry()
    try harness.viewModel.prepareImageData(imageData(color: .green))
    XCTAssertNil(harness.viewModel.redBlood)
    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)
    harness.viewModel.save()
    XCTAssertEqual(harness.store.records.count, 2)
    XCTAssertNotEqual(harness.store.records[0].id, harness.store.records[1].id)
    XCTAssertEqual(HistoryPresentation.manualAnalysisText, "Entered by you without a photo suggestion.")
  }

  func testModelFreeManualSaveShowsSuccessBeforeStartingAnotherEntry() throws {
    let harness = try makeHarness(autoAnalysisEnabled: false)
    defer { harness.cleanup() }
    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)

    harness.viewModel.save()

    let savedID = try XCTUnwrap(harness.store.records.first?.id)
    guard case .saved(let visibleID) = harness.viewModel.flowState else {
      return XCTFail("A successful model-free manual save must show the saved state.")
    }
    XCTAssertEqual(visibleID, savedID)
    XCTAssertFalse(harness.viewModel.canSave)

    harness.viewModel.startAnotherEntry()
    guard case .empty = harness.viewModel.flowState else {
      return XCTFail("Add another must start a fresh entry after the saved state.")
    }
  }

  func testReviewedProvenanceTimestampAndNilSymptomsPersist() async throws {
    let harness = try makeHarness(scripts: [.response(valid)])
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    XCTAssertNotNil(harness.viewModel.reviewedObservation)
    completeRequiredReview(harness.viewModel, bristolType: 5)
    harness.viewModel.save()

    let entry = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(entry.provenance, EntryProvenance.ai_edited.rawValue)
    XCTAssertNotNil(entry.reviewedAt)
    XCTAssertNotEqual(entry.originalAIJSON, entry.reviewedJSON)
    guard case .confirmedV1(let confirmation) = try StoredReviewedEntry.parse(
      XCTUnwrap(entry.reviewedJSON)
    ) else { return XCTFail("Expected a whole-entry confirmation envelope.") }
    XCTAssertEqual(confirmation.typedFieldProvenance[.bristolType], .editedBeforeConfirmation)
    let provenanceData = try XCTUnwrap(entry.modelProvenanceJSON?.data(using: .utf8))
    let modelProvenance = try JSONDecoder().decode(InferenceProvenanceSnapshot.self, from: provenanceData)
    XCTAssertEqual(modelProvenance.descriptorID, ModelDescriptor.galleryGemma3nE2B.id)
    XCTAssertEqual(modelProvenance.configuration, .deterministicBaseline)
    XCTAssertEqual(entry.redBlood, SymptomFlag.no.rawValue); XCTAssertEqual(entry.blackTarry, SymptomFlag.no.rawValue); XCTAssertNil(entry.dizziness); XCTAssertNil(entry.severePain)
    XCTAssertFalse(entry.reportedSymptomSummary.isEmpty)
    XCTAssertEqual(HistoryPresentation.reportedValue(entry.redBlood), "No")
    XCTAssertEqual(HistoryPresentation.reportedValue(entry.note), "Not recorded")
  }

  func testUneditedAnalysisGetsUneditedProvenance() async throws {
    let harness = try makeHarness(scripts: [.response(valid)])
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    completeRequiredReview(harness.viewModel)
    harness.viewModel.save()
    let entry = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(entry.provenance, EntryProvenance.ai_unedited.rawValue)
    guard case .confirmedV1(let confirmation) = try StoredReviewedEntry.parse(
      XCTUnwrap(entry.reviewedJSON)
    ) else { return XCTFail("Expected a whole-entry confirmation envelope.") }
    XCTAssertTrue(confirmation.typedFieldProvenance.values.allSatisfy { $0 == .acceptedUnchanged })
    XCTAssertEqual(entry.originalObservation?.apparentColor, "brown")
    XCTAssertEqual(entry.originalObservation?.redAppearingMaterial, "not_observed")
    XCTAssertEqual(entry.originalObservation?.blackTarryAppearance, "not_observed")
    XCTAssertEqual(entry.observation?.apparentColor, "brown")
    XCTAssertEqual(entry.observation?.redAppearingMaterial, "unable_to_assess")
    XCTAssertEqual(entry.observation?.blackTarryAppearance, "unable_to_assess")
  }

  func testEditedUnusableReviewRequiresManualBristolAndPersistsPhotoAbstention() async throws {
    let harness = try makeHarness(scripts: [.response(valid)])
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    harness.viewModel.updateReview { _ in
      VisualObservation(
        imageUsable: false,
        qualityIssue: "other",
        apparentBristolType: nil,
        apparentColor: "unable_to_assess",
        form: "unable_to_assess",
        redAppearingMaterial: "unable_to_assess",
        blackTarryAppearance: "unable_to_assess"
      )
    }
    XCTAssertNil(harness.viewModel.confirmedBristolType)
    XCTAssertEqual(harness.viewModel.redBlood, .unsure)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)
    XCTAssertTrue(
      harness.viewModel.canSave,
      "A complete unusable-photo review may be confirmed with appearance fields at Not sure."
    )
    harness.viewModel.updateConfirmedBristolType(4)
    completeRequiredContext(harness.viewModel)
    XCTAssertTrue(harness.viewModel.canSave, "A person can choose the Bristol type while retaining the unusable-photo review.")
    harness.viewModel.save()

    let entry = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(entry.provenance, EntryProvenance.ai_edited.rawValue)
    guard case .confirmedV1(let confirmation) = try StoredReviewedEntry.parse(
      XCTUnwrap(entry.reviewedJSON)
    ) else { return XCTFail("Expected a whole-entry confirmation envelope.") }
    XCTAssertEqual(confirmation.personConfirmedPhotoUsable, false)
    XCTAssertEqual(confirmation.personConfirmedBristolType, 4)
    XCTAssertNil(confirmation.personConfirmedRetakeReason)
    XCTAssertNil(confirmation.initiallyAcceptedPhotoUsable)
    XCTAssertNil(confirmation.initiallyAcceptedRetakeReason)
    XCTAssertNil(confirmation.typedFieldProvenance[.retakeReason])
    XCTAssertNil(confirmation.typedFieldProvenance[.stoolPresence])
    XCTAssertNil(confirmation.typedFieldProvenance[.form])
    let reopened = try XCTUnwrap(entry.observation)
    XCTAssertFalse(reopened.imageUsable)
    XCTAssertNil(reopened.apparentBristolType)
    XCTAssertEqual(reopened.qualityIssue, "other")
    XCTAssertEqual(reopened.apparentColor, "unable_to_assess")
    XCTAssertEqual(reopened.form, "unable_to_assess")
    XCTAssertEqual(reopened.redAppearingMaterial, "unable_to_assess")
    XCTAssertEqual(reopened.blackTarryAppearance, "unable_to_assess")
  }

  func testSavedAIProvenanceRecordsExplicitSimulatorCPUExecution() async throws {
    let harness = try makeHarness(
      scripts: [.response(valid)],
      descriptor: .liteRTGemma4E4B,
      configuration: .simulatorCPUFallback,
      executionLocation: .simulatorLocal
    )
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    completeRequiredReview(harness.viewModel)
    harness.viewModel.save()

    let entry = try XCTUnwrap(harness.store.records.first)
    let provenanceData = try XCTUnwrap(entry.modelProvenanceJSON?.data(using: .utf8))
    let provenance = try JSONDecoder().decode(InferenceProvenanceSnapshot.self, from: provenanceData)
    XCTAssertEqual(entry.modelID, ModelDescriptor.liteRTGemma4E4B.modelID)
    XCTAssertEqual(provenance.descriptorID, ModelDescriptor.liteRTGemma4E4B.id)
    XCTAssertEqual(provenance.configuration, .simulatorCPUFallback)
    XCTAssertEqual(provenance.executionLocation, .simulatorLocal)
  }

  func testRuntimeBadgeAndAnalyzeUnavailableReasonsReflectReadiness() throws {
    let disconnected = try makeHarness(modelReady: false, descriptor: nil)
    defer { disconnected.cleanup() }
    XCTAssertEqual(disconnected.viewModel.runtimeBadgeLabel, "UI demo · Gemma not connected")
    XCTAssertEqual(disconnected.viewModel.analyzeUnavailableReason, "Local analysis is not available in this build.")

    let unverified = try makeHarness(
      modelReady: false,
      modelVerified: false,
      descriptor: .liteRTGemma4E4B,
      configuration: .simulatorCPUFallback,
      executionLocation: .simulatorLocal
    )
    defer { unverified.cleanup() }
    XCTAssertEqual(unverified.viewModel.runtimeBadgeLabel, "Gemma 4 E4B · iPhone Simulator")
    XCTAssertEqual(unverified.viewModel.analyzeUnavailableReason, "Getting on-device analysis ready…")

    let unprepared = try makeHarness(
      modelReady: false,
      modelVerified: true,
      descriptor: .liteRTGemma4E4B,
      configuration: .simulatorCPUFallback,
      executionLocation: .simulatorLocal
    )
    defer { unprepared.cleanup() }
    XCTAssertEqual(unprepared.viewModel.analyzeUnavailableReason, "Getting on-device analysis ready…")

    let ready = try makeHarness(
      descriptor: .liteRTGemma4E4B,
      configuration: .simulatorCPUFallback,
      executionLocation: .simulatorLocal
    )
    defer { ready.cleanup() }
    XCTAssertEqual(ready.viewModel.analyzeUnavailableReason, "Choose a photo to begin.")
    try ready.viewModel.prepareImageData(imageData())
    XCTAssertNil(ready.viewModel.analyzeUnavailableReason)
  }

  func testUIDemoAttributionAndResetMarkerDoNotTrustEditableNote() async throws {
    let demo = try makeHarness(scripts: [.response(valid)], descriptor: nil)
    defer { demo.cleanup() }
    demo.viewModel.prepareDemoFixture(.brown)
    demo.viewModel.analyze()
    await waitForAnalysis(demo.viewModel)
    completeRequiredReview(demo.viewModel)
    demo.viewModel.save()

    let demoEntry = try XCTUnwrap(demo.store.records.first)
    XCTAssertEqual(demoEntry.demoKind, SyntheticFixture.brown.rawValue)
    XCTAssertTrue(DemoDataPolicy.isSyntheticDemo(demoEntry))
    XCTAssertTrue(demoEntry.isUIDemoProvider)
    XCTAssertEqual(demoEntry.savedRuntimeLabel, "UI demo · Gemma not connected")

    let manual = try makeHarness()
    defer { manual.cleanup() }
    try manual.viewModel.prepareImageData(imageData())
    manual.viewModel.enterManualMode()
    completeRequiredReview(manual.viewModel)
    manual.viewModel.note = "\(DemoDataPolicy.notePrefix) typed by a person"
    manual.viewModel.save()
    let manualEntry = try XCTUnwrap(manual.store.records.first)
    XCTAssertNil(manualEntry.demoKind)
    XCTAssertFalse(DemoDataPolicy.isSyntheticDemo(manualEntry))
  }

  func testTimeoutImmediatelyEntersManualModeAndDiscardsLateResult() async throws {
    let harness = try makeHarness(scripts: [.slow(valid, nanoseconds: 80_000_000)], analysisTimeout: .milliseconds(10))
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    XCTAssertFalse(harness.viewModel.canImportModel)

    harness.viewModel.analyze()
    XCTAssertFalse(harness.viewModel.canAnalyze)
    XCTAssertFalse(harness.viewModel.canSave)
    XCTAssertFalse(harness.viewModel.canImportModel)
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertFalse(harness.viewModel.isBusy)
    XCTAssertNil(harness.viewModel.reviewedObservation)
    XCTAssertFalse(harness.viewModel.canSave)
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Timed-out inference must immediately enter retained-draft manual review.")
    }
    completeRequiredReview(harness.viewModel)
    XCTAssertTrue(harness.viewModel.canSave)
    XCTAssertFalse(harness.viewModel.canImportModel)
    XCTAssertEqual(harness.viewModel.statusMessage, "We couldn’t prepare a suggestion. Your photo is still here. Choose the closest stool type yourself to continue.")

    try await Task.sleep(for: .milliseconds(100))
    XCTAssertNil(harness.viewModel.reviewedObservation, "A late result must not replace manual review")
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A late completion must leave the manual state intact.")
    }
  }

  func testCoordinatedCancellationFallbackRequiresFullAppRestartButKeepsManualEntry() async throws {
    let harness = try makeHarness(
      scripts: [.slow(valid, nanoseconds: 80_000_000)],
      analysisTimeout: .milliseconds(10),
      requiresFullAppRestartAfterCancellation: true
    )
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())

    harness.viewModel.analyze()
    for _ in 0..<100 where !harness.viewModel.requiresFullAppRestart {
      try await Task.sleep(for: .milliseconds(10))
    }

    XCTAssertTrue(harness.viewModel.requiresFullAppRestart)
    XCTAssertFalse(harness.viewModel.canAnalyze)
    XCTAssertEqual(
      harness.viewModel.statusMessage,
      "On-device analysis didn’t finish. Your photo is still here. Continue manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it."
    )
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A quarantined model call must retain the photo and enter manual review.")
    }
    completeRequiredReview(harness.viewModel)
    XCTAssertTrue(harness.viewModel.canSave)
  }

  func testManualCancellationWaitsForSafeSettlementBeforeClassifyingRestart() async throws {
    let inference = SettlementAwareInferenceService(finalRequiresRestart: false)
    let harness = try makeHarness(
      inference: inference,
      analysisTimeout: .seconds(2)
    )
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()
    for _ in 0..<100 {
      if await inference.hasStarted() { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    let didStart = await inference.hasStarted()
    XCTAssertTrue(didStart)

    harness.viewModel.cancelReading()
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Cancellation must publish the retained-draft manual form immediately.")
    }
    XCTAssertFalse(harness.viewModel.requiresFullAppRestart)

    for _ in 0..<100 {
      if await inference.queryCount() > 0 { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let didSettle = await inference.hasSettled()
    let queryCount = await inference.queryCount()
    let queriedEarly = await inference.wasQueriedBeforeSettlement()
    XCTAssertTrue(didSettle)
    XCTAssertEqual(queryCount, 1)
    XCTAssertFalse(queriedEarly)
    XCTAssertFalse(harness.viewModel.requiresFullAppRestart)
    XCTAssertEqual(
      harness.viewModel.statusMessage,
      "We couldn’t prepare a suggestion. Your photo is still here. Choose the closest stool type yourself to continue."
    )
  }

  func testTimedOutCancellationUpgradesOnlyAfterQuarantineSettlement() async throws {
    let inference = SettlementAwareInferenceService(finalRequiresRestart: true)
    let harness = try makeHarness(
      inference: inference,
      analysisTimeout: .milliseconds(100)
    )
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()
    for _ in 0..<100 {
      if await inference.hasStarted() { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    let didStart = await inference.hasStarted()
    XCTAssertTrue(didStart)

    for _ in 0..<150 where !harness.viewModel.requiresFullAppRestart {
      try await Task.sleep(for: .milliseconds(10))
    }
    let didSettle = await inference.hasSettled()
    let queryCount = await inference.queryCount()
    let queriedEarly = await inference.wasQueriedBeforeSettlement()
    XCTAssertTrue(didSettle)
    XCTAssertEqual(queryCount, 1)
    XCTAssertFalse(queriedEarly)
    XCTAssertTrue(harness.viewModel.requiresFullAppRestart)
    XCTAssertFalse(harness.viewModel.canAnalyze)
    XCTAssertEqual(
      harness.viewModel.statusMessage,
      "On-device analysis didn’t finish. Your photo is still here. Continue manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it."
    )
  }

  func testFullPrefillTimeoutAppliesRestartRequirementAndRetainsPhoto() async throws {
    let inference = SettlementAwareInferenceService(finalRequiresRestart: true)
    let harness = try makeHarness(
      inference: inference,
      analysisTimeout: .milliseconds(100),
      descriptor: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV12SubjectGateTuning,
      autoAnalysisEnabled: false
    )
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let retainedDraft = try XCTUnwrap(harness.viewModel.currentDraftURL)
    harness.viewModel.analyze()

    for _ in 0..<150 where !harness.viewModel.requiresFullAppRestart {
      try await Task.sleep(for: .milliseconds(10))
    }

    let didSettle = await inference.hasSettled()
    let queryCount = await inference.queryCount()
    let queriedEarly = await inference.wasQueriedBeforeSettlement()
    XCTAssertTrue(didSettle)
    XCTAssertEqual(queryCount, 1)
    XCTAssertFalse(queriedEarly)
    XCTAssertTrue(harness.viewModel.requiresFullAppRestart)
    XCTAssertEqual(harness.viewModel.currentDraftURL, retainedDraft)
    guard case .manual(let draftID) = harness.viewModel.flowState else {
      return XCTFail("Candidate timeout must retain the photo in manual entry.")
    }
    XCTAssertNotNil(draftID)
    XCTAssertEqual(
      harness.viewModel.statusMessage,
      "On-device analysis didn’t finish. Your photo is still here. Continue manually. To try photo suggestions again, fully quit GI Journal from the App Switcher, then reopen it."
    )
  }

  func testLateCancelledAnalysisCannotClearNewAnalysisTaskHandle() async throws {
    let harness = try makeHarness(
      scripts: [
        .nonCooperativeSlow(valid, nanoseconds: 80_000_000),
        .slow(valid, nanoseconds: 500_000_000),
      ],
      analysisTimeout: .seconds(2)
    )
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())

    harness.viewModel.analyze()
    try await Task.sleep(for: .milliseconds(10))
    harness.viewModel.cancelReading()
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()

    try await Task.sleep(for: .milliseconds(150))
    XCTAssertTrue(harness.viewModel.isBusy)
    XCTAssertTrue(
      harness.viewModel.hasTrackedAnalysisTaskForTesting,
      "A late cancelled task must not erase the handle owned by a newer analysis."
    )
    harness.viewModel.cancelReading()
  }

  func testMissingOrUninitializableModelKeepsImportAvailable() async throws {
    let missing = try makeHarness(modelReady: false)
    defer { missing.cleanup() }
    try missing.viewModel.prepareImageData(imageData())
    XCTAssertFalse(missing.viewModel.canAnalyze)
    XCTAssertTrue(missing.viewModel.canImportModel)
    missing.viewModel.analyze()
    XCTAssertFalse(missing.viewModel.isBusy)
    XCTAssertTrue(missing.viewModel.canImportModel)

    let corrupt = try makeHarness(scripts: [.response(valid)], failPrepare: true)
    defer { corrupt.cleanup() }
    try corrupt.viewModel.prepareImageData(imageData())
    await corrupt.viewModel.prepareModel()
    XCTAssertNil(corrupt.viewModel.reviewedObservation)
    XCTAssertTrue(corrupt.viewModel.canImportModel)
    corrupt.viewModel.enterManualMode()
    completeRequiredReview(corrupt.viewModel)
    XCTAssertTrue(corrupt.viewModel.canSave)
    XCTAssertEqual(corrupt.viewModel.statusMessage, "Photo kept. Enter the details yourself before saving.")
  }

  func testDeleteFailureKeepsEntryAndImageThenSuccessRemovesBoth() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)
    harness.viewModel.save()
    let entry = try XCTUnwrap(harness.store.records.first)
    let imageURL = try XCTUnwrap(harness.imageStore.imageURL(filename: entry.imageFilename))
    XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))

    let deletion = HistoryDeletionCoordinator(store: harness.store, imageStore: harness.imageStore)
    harness.store.failNextDelete = true
    deletion.request(entry)
    deletion.confirm()
    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
    XCTAssertNil(deletion.pendingDelete)
    XCTAssertNotNil(deletion.errorMessage)

    deletion.setAlertPresented(false)
    deletion.request(entry)
    deletion.confirm()
    XCTAssertEqual(harness.store.records.count, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
    XCTAssertNil(deletion.errorMessage)
  }

  func testReconciliationDeletesOrphanAndMarksMissingImage() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let images = try imageStore.imagesDirectory()
    let orphan = images.appendingPathComponent("orphan.jpg")
    try Data("orphan".utf8).write(to: orphan)

    let schema = Schema([EntryRecord.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    let context = ModelContext(container)
    let input = EntryInput(id: UUID(), capturedAt: Date(), draftURL: root.appendingPathComponent("unused"), imageSHA256: "hash", redBlood: nil, blackTarry: nil, dizziness: nil, severePain: nil, note: nil, provenance: .manual, reviewedAt: nil, originalAIJSON: nil, reviewedJSON: nil, modelID: nil, modelProvenanceJSON: nil, demoKind: nil, imageFilename: "missing.jpg")
    let entry = EntryRecord(input: input)
    context.insert(entry); try context.save()

    try await EntryStore(context: context).reconcile(imageStore: imageStore)

    XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    XCTAssertTrue(entry.imageUnavailable)
  }

  func testSanitizedImageIsBoundedAndMetadataFree() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let prepared = try store.prepare(imageData(size: CGSize(width: 1800, height: 1200)))
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(prepared.url as CFURL, nil))
    let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelWidth] as? Int ?? .max, 1024)
    XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelHeight] as? Int ?? .max, 1024)
    XCTAssertNil(properties[kCGImagePropertyExifDictionary])
    XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    XCTAssertEqual(properties[kCGImagePropertyColorModel] as? String, kCGImagePropertyColorModelRGB as String)
  }

  func testDescriptorRejectsUnsafeIdentityAndPathComponents() throws {
    XCTAssertThrowsError(try ModelDescriptor(
      id: "../escape",
      family: "Test",
      modelID: "official/test",
      artifactFilename: "../model.litertlm",
      sourceRevision: String(repeating: "a", count: 40),
      sourceURL: "https://example.invalid/model",
      expectedSHA256: String(repeating: "b", count: 64),
      expectedBytes: 1,
      cacheNamespace: "../cache",
      minimumMemoryGB: 1
    ))
    XCTAssertNoThrow(try tinyDescriptor(data: Data("safe".utf8)))
  }

  func testGemma4E4BDescriptorMatchesPinnedArtifact() {
    let descriptor = ModelDescriptor.liteRTGemma4E4B
    XCTAssertEqual(descriptor.modelID, "litert-community/gemma-4-E4B-it-litert-lm")
    XCTAssertEqual(descriptor.artifactFilename, "gemma-4-E4B-it.litertlm")
    XCTAssertEqual(descriptor.sourceRevision, "28299f30ee4d43294517a4ac93abd6163412f07f")
    XCTAssertEqual(descriptor.expectedBytes, 3_659_530_240)
    XCTAssertEqual(descriptor.expectedSHA256, "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0")
    XCTAssertNil(descriptor.minimumMemoryGB)
    XCTAssertTrue(ModelCatalog.debugCandidates.contains(descriptor))
    XCTAssertEqual(ModelCatalog.debugPOCSelection, descriptor)
    XCTAssertEqual(ModelCatalog.normalFlowSelection, descriptor)
    XCTAssertNil(ModelCatalog.releaseSelection)
  }

  func testSimulatorCPUFallbackChangesOnlyMainBackend() {
    let baseline = InferenceConfiguration.deterministicBaseline
    let fallback = InferenceConfiguration.simulatorCPUFallback
    XCTAssertEqual(fallback.engineBackend, "cpu")
    XCTAssertEqual(baseline.visionBackend, fallback.visionBackend)
    XCTAssertEqual(baseline.maxNumTokens, fallback.maxNumTokens)
    XCTAssertEqual(baseline.topK, fallback.topK)
    XCTAssertEqual(baseline.topP, fallback.topP)
    XCTAssertEqual(baseline.temperature, fallback.temperature)
    XCTAssertEqual(baseline.seed, fallback.seed)
    XCTAssertEqual(baseline.promptVersion, fallback.promptVersion)
    XCTAssertEqual(baseline.imageMessageForm, fallback.imageMessageForm)
    XCTAssertEqual(InferenceConfiguration.runtimeDefault, fallback)
  }

  func testPhysicalCPUFallbackChangesOnlyMainBackendAndIsExplicitlyNamed() {
    let baseline = InferenceConfiguration.deterministicBaseline
    let fallback = InferenceConfiguration.physicalCPUFallback
    XCTAssertEqual(fallback.id, "physical-cpu-engine-fallback-v1")
    XCTAssertEqual(fallback.engineBackend, "cpu")
    XCTAssertEqual(baseline.visionBackend, fallback.visionBackend)
    XCTAssertEqual(baseline.maxNumTokens, fallback.maxNumTokens)
    XCTAssertEqual(baseline.topK, fallback.topK)
    XCTAssertEqual(baseline.topP, fallback.topP)
    XCTAssertEqual(baseline.temperature, fallback.temperature)
    XCTAssertEqual(baseline.seed, fallback.seed)
    XCTAssertEqual(baseline.promptVersion, fallback.promptVersion)
    XCTAssertEqual(baseline.imageMessageForm, fallback.imageMessageForm)
  }

  func testPhysicalGPUVisionChangesOnlyVisionBackendAndIsExplicitlyNamed() {
    let baseline = InferenceConfiguration.deterministicBaseline
    let experiment = InferenceConfiguration.physicalGPUVision
    XCTAssertEqual(experiment.id, "physical-gpu-vision-v1")
    XCTAssertEqual(experiment.engineBackend, baseline.engineBackend)
    XCTAssertEqual(experiment.visionBackend, "gpu")
    XCTAssertEqual(experiment.maxNumTokens, baseline.maxNumTokens)
    XCTAssertEqual(experiment.topK, baseline.topK)
    XCTAssertEqual(experiment.topP, baseline.topP)
    XCTAssertEqual(experiment.temperature, baseline.temperature)
    XCTAssertEqual(experiment.seed, baseline.seed)
    XCTAssertEqual(experiment.promptVersion, baseline.promptVersion)
    XCTAssertEqual(experiment.imageMessageForm, baseline.imageMessageForm)
  }

  func testPhysicalRawImageDiagnosticLaunchArgumentIsExactAndIsolated() {
    let argument = PhysicalRawImageDiagnosticContract.launchArgument
    let controlArgument = PhysicalRawImageDiagnosticContract.controlLaunchArgument
    let structuredControlArgument =
      PhysicalRawImageDiagnosticContract.structuredControlLaunchArgument
    let malformedNearMatch = "\(argument)-extra"
    XCTAssertEqual(argument, "--run-physical-raw-image-one-shot")
    XCTAssertEqual(controlArgument, "--run-physical-raw-image-control-one-shot")
    XCTAssertEqual(
      structuredControlArgument,
      "--run-physical-raw-image-control-structured-one-shot"
    )
    XCTAssertTrue(PhysicalRawImageDiagnosticContract.isRequested(in: ["GITimeline", argument]))
    XCTAssertTrue(PhysicalRawImageDiagnosticContract.isRequested(
      in: ["GITimeline", controlArgument]
    ))
    XCTAssertTrue(PhysicalRawImageDiagnosticContract.isRequested(
      in: ["GITimeline", structuredControlArgument]
    ))
    XCTAssertEqual(
      PhysicalRawImageDiagnosticContract.requestedFixtureID(in: ["GITimeline", argument]),
      "brown"
    )
    XCTAssertEqual(
      PhysicalRawImageDiagnosticContract.requestedFixtureID(
        in: ["GITimeline", controlArgument]
      ),
      "control"
    )
    XCTAssertEqual(
      PhysicalRawImageDiagnosticContract.requestedRequest(
        in: ["GITimeline", structuredControlArgument]
      ),
      .controlStructuredObservation
    )
    XCTAssertFalse(PhysicalRawImageDiagnosticContract.isRequested(in: ["GITimeline"]))
    XCTAssertFalse(PhysicalRawImageDiagnosticContract.isRequested(
      in: ["GITimeline", malformedNearMatch]
    ))
    XCTAssertTrue(PhysicalRawImageDiagnosticContract.hasAnyPhysicalRawLaunchArgument(
      in: ["GITimeline", malformedNearMatch]
    ))
    XCTAssertFalse(PhysicalRawImageDiagnosticContract.isRequested(
      in: ["GITimeline", structuredControlArgument, malformedNearMatch]
    ))
    XCTAssertFalse(PhysicalRawImageDiagnosticContract.isRequested(in: ["GITimeline", "--run-embedded-gemma-smoke"]))
    XCTAssertFalse(PhysicalRawImageDiagnosticContract.isRequested(
      in: ["GITimeline", argument, controlArgument]
    ))
    XCTAssertFalse(PhysicalRawImageDiagnosticContract.isRequested(
      in: ["GITimeline", structuredControlArgument, PhysicalRawImageSuiteContract.launchArgument]
    ))
    XCTAssertFalse(PhysicalRawImageDiagnosticContract.isRequested(
      in: ["GITimeline", structuredControlArgument, "--run-embedded-gemma-normal-flow"]
    ))
    XCTAssertTrue(PhysicalRawImageDiagnosticContract.hasAnyPhysicalRawLaunchArgument(
      in: ["GITimeline", structuredControlArgument, "--run-embedded-gemma-normal-flow"]
    ))
  }

  func testPhysicalRawImageDiagnosticPinsRawVisionConfigurationWithoutChangingDefault() {
    let configuration = PhysicalRawImageDiagnosticContract.configuration
    XCTAssertEqual(configuration, .physicalGPUCPUVision70)
    XCTAssertNotEqual(configuration, .runtimeDefault)
    XCTAssertFalse(configuration.usesLocalPixelBridge)
    XCTAssertEqual(configuration.engineBackend, "gpu")
    XCTAssertEqual(configuration.visionBackend, "cpu")
    XCTAssertEqual(configuration.maxNumTokens, 1_024)
    XCTAssertEqual(configuration.topK, 1)
    XCTAssertEqual(configuration.topP, 1)
    XCTAssertEqual(configuration.temperature, 0)
    XCTAssertEqual(configuration.seed, 0)
    XCTAssertEqual(configuration.promptVersion, "gi-observation-v1")
    XCTAssertTrue(configuration.imageMessageForm.contains("imageFile"))
    XCTAssertEqual(PhysicalRawImageDiagnosticContract.visualTokenBudget, 70)
    XCTAssertEqual(PhysicalRawImageDiagnosticContract.descriptor, .liteRTGemma4E4B)
    XCTAssertEqual(PhysicalRawImageDiagnosticContract.fixtureID, SyntheticFixture.brown.rawValue)
    XCTAssertEqual(
      PhysicalRawImageDiagnosticContract.bundledBrownFixtureSHA256,
      SyntheticFixture.brown.bundledSHA256
    )
    XCTAssertEqual(PhysicalRawImageDiagnosticContract.controlFixtureID, SyntheticFixture.control.rawValue)
    XCTAssertEqual(
      PhysicalRawImageDiagnosticContract.bundledControlFixtureSHA256,
      SyntheticFixture.control.bundledSHA256
    )
    XCTAssertEqual(
      PhysicalRawImageDiagnosticContract.sanitizedControlFixtureSHA256,
      "6d6ab9a6dd5d692bbc53c4a76c71faaa4b32c767c23101a207cf508dfccd1d1d"
    )
  }

  func testShippingRawPhotoConfigurationPinsValidatedImageDataTransport() {
    let configuration = InferenceConfiguration.appStoreRawImageV1
    XCTAssertEqual(configuration.id, "app-store-raw-image-v1-cpu-candidate")
    XCTAssertEqual(configuration.engineBackend, "cpu")
    XCTAssertEqual(configuration.visionBackend, "cpu")
    XCTAssertEqual(configuration.maxNumTokens, 1_536)
    XCTAssertTrue(configuration.usesRawPhotoV1Schema)
    XCTAssertFalse(configuration.usesLocalPixelBridge)
    XCTAssertEqual(configuration.promptVersion, "gi-photo-v1.2")
    XCTAssertEqual(configuration.visualTokenBudget, 70)
    XCTAssertTrue(configuration.imageMessageForm.contains("Content.imageData(validatedSanitizedJPEGBytes)"))
    XCTAssertFalse(configuration.imageMessageForm.contains("imageFile"))
    XCTAssertTrue(InferenceService.rawPhotoV1Prompt.contains(
      "Create one conservative, editable GI-journal suggestion from visible pixels only."
    ))
    XCTAssertTrue(InferenceService.rawPhotoV1Prompt.contains(
      "Empty toilets, water, paper, food, skin, pets, and household objects are non_stool or uncertain"
    ))
    XCTAssertTrue(InferenceService.rawPhotoV1Prompt.contains(
      "Unusable/non_stool/uncertain must abstain as above."
    ))
    XCTAssertFalse(InferenceService.rawPhotoV1Prompt.contains(
      "glare, not_target_image, other"
    ))
    XCTAssertEqual(
      hexSHA256(Data(InferenceService.rawPhotoV1Prompt.utf8)),
      "4521ad89076fadb29ade73a863318c99f6d2827984a46bcd7cfb18502648e563",
      "Changing the shipping prompt requires an explicit prompt-version bump and new evidence."
    )
  }

  func testShippingRawPhotoContextCoversOneCompactBoundedRepair() {
    let configuration = InferenceConfiguration.appStoreRawImageV1
    let contract = AppStoreRawPhotoGenerationBudgetContract.self
    let adversarialError = "Unknown keys: \(String(repeating: "model_controlled_", count: 1_000))"
    let boundedPrompt = contract.repairPrompt(
      configuration: configuration,
      untrustedErrorSummary: adversarialError
    )

    XCTAssertEqual(contract.promptSHA256(InferenceService.rawPhotoV1Prompt), contract.reviewedPromptSHA256)
    XCTAssertEqual(contract.measuredPromptTokens, 489)
    XCTAssertEqual(contract.conservativeRenderedPromptWithImagePlaceholderTokens, 502)
    XCTAssertEqual(contract.maximumVisualEmbeddings, 70)
    XCTAssertEqual(contract.maximumOutputTokensPerTurn, 128)
    XCTAssertEqual(contract.reviewedMaximumCanonicalJSONTokens, 80)
    XCTAssertEqual(contract.measuredRepairPromptTokens, 11)
    XCTAssertEqual(boundedPrompt, "Invalid JSON. Return corrected nine-key JSON only.")
    XCTAssertFalse(contract.reviewedRepairPrompt.contains("model_controlled_"))
    XCTAssertTrue(contract.reviewedRepairPrompt.unicodeScalars.allSatisfy(\.isASCII))
    XCTAssertEqual(contract.conservativeMaximumRepairPromptTokens, 50)
    XCTAssertEqual(contract.maximumFirstRequestTokens, 701)
    XCTAssertEqual(contract.maximumRepairSessionTokens, 1_007)
    XCTAssertEqual(contract.reviewedEngineContextTokens, 1_536)
    XCTAssertLessThan(contract.maximumRepairSessionTokens, configuration.maxNumTokens)
    XCTAssertEqual(BoundedGenerationPolicy.structured.maximumOutputTokens, 256)
    XCTAssertEqual(BoundedGenerationPolicy.rawPhoto.maximumOutputTokens, 128)
    XCTAssertEqual(BoundedGenerationPolicy.structured(for: configuration), .rawPhoto)
    XCTAssertEqual(BoundedGenerationPolicy.structured(for: .deterministicBaseline), .structured)
    XCTAssertEqual(BoundedGenerationPolicy.probe.maximumOutputTokens, 16)
    XCTAssertTrue(contract.accepts(
      configuration: configuration,
      policy: .rawPhoto,
      prompt: InferenceService.rawPhotoV1Prompt
    ))
    XCTAssertFalse(contract.accepts(
      configuration: configuration,
      policy: .rawPhoto,
      prompt: InferenceService.rawPhotoV1Prompt + " "
    ))
    XCTAssertFalse(contract.accepts(
      configuration: configuration,
      policy: .structured,
      prompt: InferenceService.rawPhotoV1Prompt
    ))

    let undersized = InferenceConfiguration(
      id: configuration.id,
      engineBackend: configuration.engineBackend,
      visionBackend: configuration.visionBackend,
      maxNumTokens: 1_006,
      topK: configuration.topK,
      topP: configuration.topP,
      temperature: configuration.temperature,
      seed: configuration.seed,
      promptVersion: configuration.promptVersion,
      imageMessageForm: configuration.imageMessageForm,
      visualTokenBudget: configuration.visualTokenBudget
    )
    XCTAssertFalse(contract.accepts(
      configuration: undersized,
      policy: .rawPhoto,
      prompt: InferenceService.rawPhotoV1Prompt
    ))
  }

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  func testEmbeddedHarnessHonorsExplicitShippingRawPhotoSelector() {
    let selector = InferenceConfiguration.internalAppStoreRawImageV1LaunchArgument
    XCTAssertEqual(selector, "--internal-app-store-raw-image-v1")
    XCTAssertEqual(
      InferenceConfiguration.internalDiagnosticConfiguration(
        arguments: ["GITimeline", selector]
      ),
      .appStoreRawImageV1
    )
    XCTAssertNil(
      InferenceConfiguration.internalDiagnosticConfiguration(
        arguments: ["GITimeline", "--run-embedded-gemma-normal-flow"]
      )
    )
    XCTAssertEqual(
      InferenceConfiguration.embeddedHarnessExpectedConfiguration(
        arguments: ["GITimeline", selector, "--run-embedded-gemma-normal-flow"]
      ),
      .appStoreRawImageV1
    )
    XCTAssertEqual(
      InferenceConfiguration.embeddedHarnessExpectedConfiguration(
        arguments: ["GITimeline", "--run-embedded-gemma-normal-flow"]
      ),
      .runtimeDefault
    )
  }

  func testGPUMainRawPhotoDiagnosticChangesOnlyMainBackend() {
    let control = InferenceConfiguration.appStoreRawImageV1
    let candidate = InferenceConfiguration.appStoreRawImageV1GPUMainDiagnostic

    XCTAssertEqual(control.engineBackend, "cpu")
    XCTAssertEqual(candidate.engineBackend, "gpu")
    XCTAssertNotEqual(candidate.id, control.id)
    XCTAssertEqual(candidate.visionBackend, control.visionBackend)
    XCTAssertEqual(candidate.maxNumTokens, control.maxNumTokens)
    XCTAssertEqual(candidate.topK, control.topK)
    XCTAssertEqual(candidate.topP, control.topP)
    XCTAssertEqual(candidate.temperature, control.temperature)
    XCTAssertEqual(candidate.seed, control.seed)
    XCTAssertEqual(candidate.promptVersion, control.promptVersion)
    XCTAssertEqual(candidate.imageMessageForm, control.imageMessageForm)
    XCTAssertEqual(candidate.visualTokenBudget, control.visualTokenBudget)
    XCTAssertTrue(candidate.usesRawPhotoV1Schema)
    XCTAssertFalse(candidate.usesLocalPixelBridge)

    XCTAssertEqual(control.id, "app-store-raw-image-v1-cpu-candidate")
    XCTAssertEqual(control.engineBackend, "cpu")
    XCTAssertNotEqual(InferenceConfiguration.runtimeDefault, candidate)
    XCTAssertEqual(
      InferenceConfiguration.embeddedHarnessExpectedConfiguration(
        arguments: ["GITimeline"]
      ),
      .runtimeDefault
    )
  }

  func testGPUMainRawPhotoDiagnosticSelectorsFailClosedAndStayIsolated() {
    let cpuSelector = InferenceConfiguration.internalAppStoreRawImageV1LaunchArgument
    let gpuSelector =
      InferenceConfiguration.internalAppStoreRawImageV1GPUMainLaunchArgument
    let cpuDiagnostic = AppStoreRawImageV1PreparationDiagnosticContract.launchArgument
    let gpuDiagnostic =
      AppStoreRawImageV1PreparationDiagnosticContract.gpuMainLaunchArgument
    let validGPUArguments = ["GITimeline", gpuSelector, gpuDiagnostic]

    XCTAssertEqual(
      InferenceConfiguration.internalDiagnosticConfiguration(
        arguments: ["GITimeline", gpuSelector]
      ),
      .appStoreRawImageV1GPUMainDiagnostic
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.requestedConfiguration(
        in: validGPUArguments
      ),
      .appStoreRawImageV1GPUMainDiagnostic
    )
    XCTAssertTrue(
      AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
        in: validGPUArguments
      )
    )
    XCTAssertTrue(
      AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
        in: validGPUArguments + [
          AppStoreRawImageV1PreparationDiagnosticContract
            .directImageDataLaunchArgument
        ]
      )
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.cacheMode(
        in: validGPUArguments
      ),
      .sharedModelCache
    )
    XCTAssertTrue(AppEvaluationLaunchPolicy.isolatesJournal(validGPUArguments))

    for invalid in [
      ["GITimeline", gpuSelector, cpuDiagnostic],
      ["GITimeline", cpuSelector, gpuDiagnostic],
      ["GITimeline", cpuSelector, gpuSelector, gpuDiagnostic],
      ["GITimeline", gpuSelector, gpuSelector, gpuDiagnostic],
      validGPUArguments + [cpuDiagnostic],
    ] {
      XCTAssertNil(
        AppStoreRawImageV1PreparationDiagnosticContract.requestedConfiguration(
          in: invalid
        )
      )
      XCTAssertFalse(
        AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(in: invalid)
      )
    }
    for invalid in [
      validGPUArguments + [
        AppStoreRawImageV1PreparationDiagnosticContract.freshCacheLaunchArgument
      ],
      validGPUArguments + [gpuDiagnostic + "-extra"],
    ] {
      XCTAssertFalse(
        AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(in: invalid)
      )
    }
    XCTAssertTrue(AppEvaluationLaunchPolicy.isolatesJournal(
      ["GITimeline", gpuDiagnostic + "-extra"]
    ))
    XCTAssertNil(InferenceConfiguration.internalDiagnosticConfiguration(
      arguments: ["GITimeline"]
    ))
  }

  func testGPUMainRawPhotoDiagnosticUsesDistinctV5CacheProfile() throws {
    let contract = AppStoreRawImageV1PreparationDiagnosticContract.self
    let cpuProfile = contract.cacheProfile(for: .appStoreRawImageV1)
    let gpuProfile = contract.cacheProfile(for: .appStoreRawImageV1GPUMainDiagnostic)
    let cpuSHA256 = try cpuProfile.sha256
    let gpuSHA256 = try gpuProfile.sha256
    let cpuSchema = try AppFolders.liteRTCacheSchema(for: cpuProfile)
    let gpuSchema = try AppFolders.liteRTCacheSchema(for: gpuProfile)

    XCTAssertEqual(cpuProfile.engineBackend, "cpu")
    XCTAssertEqual(gpuProfile.engineBackend, "gpu")
    XCTAssertEqual(InferenceConfiguration.appStoreRawImageV1GPUMainDiagnostic.maxNumTokens, 1_536)
    XCTAssertFalse(cpuProfile.matches(
      descriptor: contract.descriptor,
      configuration: .appStoreRawImageV1GPUMainDiagnostic
    ))
    XCTAssertFalse(gpuProfile.matches(
      descriptor: contract.descriptor,
      configuration: .appStoreRawImageV1
    ))
    XCTAssertEqual(
      gpuSHA256,
      "87f0c19b3ce88608e11429f5312fd1ce6bfdca4cafdd66a430000c85a048c96f"
    )
    XCTAssertNotEqual(cpuSHA256, gpuSHA256)
    XCTAssertNotEqual(cpuSchema, gpuSchema)
    XCTAssertEqual(
      gpuSchema,
      "litert-\(AppFolders.liteRTLMRevision)-v5-\(gpuSHA256)"
    )

    let marker = contract.configurationMarker(
      .appStoreRawImageV1GPUMainDiagnostic,
      expected: .appStoreRawImageV1GPUMainDiagnostic,
      selectorPresent: true,
      cacheMode: .sharedModelCache,
      idleTimerDisabled: true
    )
    XCTAssertTrue(marker.contains("config_match=true"))
    XCTAssertTrue(marker.contains("backend=gpu"))
    XCTAssertTrue(marker.contains("vision=cpu"))
    XCTAssertEqual(
      marker.split(separator: " ").filter { $0 == "output_cap_tokens=128" }.count,
      1
    )
    XCTAssertTrue(marker.contains("cache_profile_sha256=\(gpuSHA256)"))
    XCTAssertTrue(marker.contains(
      "cache_schema=litert-\(AppFolders.liteRTLMRevision)-v5-"
    ))
    XCTAssertFalse(marker.contains(cpuSHA256))
  }

  func testRawPhotoPreparationDiagnosticRequiresSelectorAndUsesSanitizedMarkers() {
    let selector = InferenceConfiguration.internalAppStoreRawImageV1LaunchArgument
    let diagnostic = AppStoreRawImageV1PreparationDiagnosticContract.launchArgument
    let validArguments = ["GITimeline", selector, diagnostic]
    let freshCache =
      AppStoreRawImageV1PreparationDiagnosticContract.freshCacheLaunchArgument
    let cachesRoot =
      AppStoreRawImageV1PreparationDiagnosticContract.cachesRootLaunchArgument
    let directImage =
      AppStoreRawImageV1PreparationDiagnosticContract.directImageDataLaunchArgument
    let synchronousSend =
      AppStoreRawImageV1PreparationDiagnosticContract.synchronousSendLaunchArgument
    XCTAssertTrue(
      AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(in: validArguments)
    )
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: ["GITimeline", diagnostic]
    ))
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: ["GITimeline", selector]
    ))
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: validArguments + ["--run-embedded-gemma-normal-flow"]
    ))
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.cacheMode(in: validArguments),
      .sharedModelCache
    )
    XCTAssertTrue(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: validArguments + [freshCache]
    ))
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.cacheMode(
        in: validArguments + [freshCache]
      ),
      .freshIsolatedDiagnosticCache
    )
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: ["GITimeline", freshCache]
    ))
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: validArguments + [freshCache, freshCache]
    ))
    XCTAssertTrue(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: validArguments + [cachesRoot]
    ))
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.cacheMode(
        in: validArguments + [cachesRoot]
      ),
      .freshCachesRootDiagnosticCache
    )
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: validArguments + [cachesRoot, cachesRoot]
    ))
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: validArguments + [freshCache, cachesRoot]
    ))
    XCTAssertTrue(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: validArguments + [directImage]
    ))
    XCTAssertTrue(
      AppStoreRawImageV1PreparationDiagnosticContract.requestsDirectImageData(
        in: validArguments + [directImage]
      )
    )
    let synchronousArguments = validArguments + [directImage, synchronousSend]
    XCTAssertTrue(
      AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
        in: synchronousArguments
      )
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.generationAPI(
        in: synchronousArguments
      ),
      .synchronousDiagnostic
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.requestedConfiguration(
        in: synchronousArguments
      ),
      .appStoreRawImageV1
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.cacheProfileSHA256(
        for: .appStoreRawImageV1
      ),
      AppStoreRawImageV1PreparationDiagnosticContract.cacheProfileSHA256(
        for: AppStoreRawImageV1PreparationDiagnosticContract.requestedConfiguration(
          in: synchronousArguments
        )!
      )
    )
    for invalidSynchronousArguments in [
      validArguments + [synchronousSend],
      synchronousArguments + [synchronousSend],
      ["GITimeline", synchronousSend],
      [
        "GITimeline",
        InferenceConfiguration.internalAppStoreRawImageV1GPUMainLaunchArgument,
        AppStoreRawImageV1PreparationDiagnosticContract.gpuMainLaunchArgument,
        directImage,
        synchronousSend,
      ],
      synchronousArguments + [freshCache],
      synchronousArguments + [synchronousSend + "-extra"],
    ] {
      XCTAssertFalse(
        AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
          in: invalidSynchronousArguments
        )
      )
    }
    XCTAssertTrue(AppEvaluationLaunchPolicy.isolatesJournal(
      ["GITimeline", synchronousSend + "-extra"]
    ))
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: ["GITimeline", selector, directImage]
    ))
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: validArguments + [directImage, directImage]
    ))
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: validArguments + [directImage, freshCache]
    ))
    let nearDirectImage = directImage + "-extra"
    XCTAssertTrue(
      AppStoreRawImageV1PreparationDiagnosticContract.hasDiagnosticLaunchArgument(
        in: ["GITimeline", nearDirectImage]
      )
    )
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: validArguments + [nearDirectImage]
    ))
    XCTAssertTrue(AppEvaluationLaunchPolicy.isolatesJournal(
      ["GITimeline", nearDirectImage]
    ))
    let nearMatch = freshCache + "-extra"
    XCTAssertTrue(
      AppStoreRawImageV1PreparationDiagnosticContract.hasDiagnosticLaunchArgument(
        in: ["GITimeline", nearMatch]
      )
    )
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: ["GITimeline", nearMatch]
    ))
    XCTAssertFalse(AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
      in: validArguments + [nearMatch]
    ))
    XCTAssertTrue(AppEvaluationLaunchPolicy.isolatesJournal(["GITimeline", nearMatch]))
    for preemptingArgument in [
      "--run-photo-evaluation-derived-map-iphone",
      "--run-photo-evaluation-raw-image-simulator",
      DerivedMapTuningV3Contract.launchArgumentPrefix,
      DerivedMapBlindValidationV1Contract.launchArgumentPrefix,
    ] {
      XCTAssertFalse(
        AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
          in: validArguments + [preemptingArgument]
        ),
        "A preempting diagnostic argument must invalidate the preparation probe: \(preemptingArgument)"
      )
    }
    XCTAssertEqual(
      ModelCatalog.normalFlowSelection,
      AppStoreRawImageV1PreparationDiagnosticContract.descriptor,
      "The preparation probe must remain bound to the ordinary app's exact embedded model."
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.sanitizedBrownFixtureSHA256,
      "637a7dd50e4adc9385c999a3ea1e269a4e25e3b78f4a783151f28b4c83540d73"
    )

    let configurationMarker =
      AppStoreRawImageV1PreparationDiagnosticContract.configurationMarker(
        .appStoreRawImageV1,
        selectorPresent: true,
        cacheMode: .sharedModelCache,
        idleTimerDisabled: true
      )
    XCTAssertTrue(configurationMarker.hasPrefix(
      "APP_STORE_RAW_IMAGE_V1_PREPARATION_CONFIG "
    ))
    XCTAssertTrue(configurationMarker.contains("config_match=true"))
    XCTAssertTrue(configurationMarker.contains(
      "config=app-store-raw-image-v1-cpu-candidate"
    ))
    XCTAssertTrue(configurationMarker.contains("backend=cpu"))
    XCTAssertTrue(configurationMarker.contains("vision=cpu"))
    XCTAssertTrue(configurationMarker.contains("context_tokens=1536"))
    XCTAssertTrue(configurationMarker.contains("visual_tokens=70"))
    XCTAssertTrue(configurationMarker.contains("output_cap_tokens=128"))
    XCTAssertTrue(configurationMarker.contains(
      "configured_transport=validated_sanitized_jpeg_image_data"
    ))
    XCTAssertTrue(configurationMarker.contains(
      "generation_api=conversation_send_message_stream_v1"
    ))
    XCTAssertTrue(configurationMarker.contains("expected_model_sha256="))
    XCTAssertFalse(configurationMarker.contains(" model_sha256="))
    XCTAssertTrue(configurationMarker.contains("cache_mode=shared_model_cache"))
    XCTAssertTrue(configurationMarker.contains("idle_timer_disabled=true"))
    XCTAssertFalse(configurationMarker.contains("/"))
    let fixtureMarker =
      AppStoreRawImageV1PreparationDiagnosticContract.directFixtureReadyMarker(
        fixtureID: "control",
        bundledSHA256: String(repeating: "a", count: 64),
        sanitizedSHA256: String(repeating: "b", count: 64)
      )
    XCTAssertTrue(fixtureMarker.hasPrefix(
      "APP_STORE_RAW_IMAGE_V1_PREPARATION_FIXTURE_READY "
    ))
    XCTAssertTrue(fixtureMarker.contains("journal_container=ephemeral"))
    XCTAssertFalse(fixtureMarker.contains("/"))
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.directImageRequestStartMarker(),
      "APP_STORE_RAW_IMAGE_V1_PREPARATION_IMAGE_REQUEST_START timeout_ms=32000 api=analyze_expected_sha256 transport=validated_sanitized_jpeg_image_data generation_api=conversation_send_message_stream_v1 output_cap_tokens=128"
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.directImageRequestStartMarker(
        generationAPI: .synchronousDiagnostic
      ),
      "APP_STORE_RAW_IMAGE_V1_PREPARATION_IMAGE_REQUEST_START timeout_ms=32000 api=analyze_expected_sha256 transport=validated_sanitized_jpeg_image_data generation_api=conversation_send_message_sync_v1 output_cap_tokens=128"
    )
    for stage in AppStoreRawImageV1PreparationDiagnosticContract.NativeStage.allCases {
      let marker = AppStoreRawImageV1PreparationDiagnosticContract.nativeStageMarker(stage)
      XCTAssertEqual(
        marker,
        "APP_STORE_RAW_IMAGE_V1_PREPARATION_NATIVE_STAGE stage=\(stage.rawValue)"
      )
      XCTAssertFalse(marker.contains("/"))
    }
    XCTAssertEqual(
      Array(
        AppStoreRawImageV1PreparationDiagnosticContract.NativeStage.allCases
          .prefix(7)
          .map(\.rawValue)
      ),
      [
        "engine_config_plan_start",
        "engine_config_plan_pass",
        "engine_construct_start",
        "engine_construct_pass",
        "engine_initialize_start",
        "engine_initialize_pass",
        "engine_initialize_fail",
      ]
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.nativeStageMarker(
        .engineInitializeStart,
        elapsedSeconds: 1.234
      ),
      "APP_STORE_RAW_IMAGE_V1_PREPARATION_NATIVE_STAGE stage=engine_initialize_start elapsed_ms=1234"
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.strictSchemaErrorClass(
        ObservationParserError.invalidJSON
      ),
      "strict_schema_invalid_json"
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.strictSchemaErrorClass(
        ObservationParserError.missingKeys(["bristol_type"])
      ),
      "strict_schema_missing_keys"
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.strictSchemaErrorClass(
        ObservationParserError.inconsistent("synthetic detail must not leak")
      ),
      "strict_schema_inconsistent"
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.cachePreparationErrorClass(
        GITimelineError.evidenceAlreadyExists
      ),
      "evidence_already_exists"
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.cachePreparationErrorClass(
        GITimelineError.insufficientModelStorage
      ),
      "insufficient_model_storage"
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.cachePreparationErrorClass(
        GITimelineError.invalidModelDescriptor
      ),
      "invalid_model_descriptor"
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.cachePreparationErrorClass(
        GITimelineError.invalidModelReceipt
      ),
      "invalid_model_receipt"
    )
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.cachePreparationErrorClass(
        CocoaError(.fileReadUnknown)
      ),
      "file_system_error"
    )
    let unknownCacheErrorClass = AppStoreRawImageV1PreparationDiagnosticContract
      .cachePreparationErrorClass(
        NSError(domain: "/private/sensitive/container/path", code: 999)
      )
    XCTAssertEqual(unknownCacheErrorClass, "unknown_error")
    XCTAssertFalse(unknownCacheErrorClass.contains("/"))
    XCTAssertEqual(
      AppStoreRawImageV1PreparationDiagnosticContract.cacheReadyMarker(
        preparation: ModelRuntimeEngineCachePreparation(
          mode: .freshCachesRootDiagnosticCache,
          disposition: .freshDiagnosticCache,
          backupExcluded: true,
          protectionClass: "complete_until_first_user_authentication"
        )
      ),
      "APP_STORE_RAW_IMAGE_V1_PREPARATION_CACHE_READY cache_mode=fresh_caches_root_diagnostic_cache cache_disposition=fresh_diagnostic_cache backup_excluded=true protection=complete_until_first_user_authentication"
    )
    let simulatorSharedCache = ModelRuntimeEngineCachePreparation(
      mode: .sharedModelCache,
      disposition: .coldVersionedCache,
      backupExcluded: true,
      protectionClass: "unavailable"
    )
    XCTAssertTrue(
      AppStoreRawImageV1PreparationDiagnosticContract.cachePreparationMatches(
        simulatorSharedCache,
        expectedMode: .sharedModelCache,
        simulatorFileProtectionUnavailable: true
      )
    )
    XCTAssertFalse(
      AppStoreRawImageV1PreparationDiagnosticContract.cachePreparationMatches(
        simulatorSharedCache,
        expectedMode: .sharedModelCache,
        simulatorFileProtectionUnavailable: false
      )
    )
    XCTAssertTrue(
      AppStoreRawImageV1PreparationDiagnosticContract.cachePreparationMatches(
        ModelRuntimeEngineCachePreparation(
          mode: .sharedModelCache,
          disposition: .validatedVersionedReuse,
          backupExcluded: true,
          protectionClass: "complete_until_first_user_authentication"
        ),
        expectedMode: .sharedModelCache,
        simulatorFileProtectionUnavailable: false
      )
    )
    XCTAssertFalse(
      AppStoreRawImageV1PreparationDiagnosticContract.cachePreparationMatches(
        ModelRuntimeEngineCachePreparation(
          mode: .sharedModelCache,
          disposition: .coldVersionedCache,
          backupExcluded: false,
          protectionClass: "unavailable"
        ),
        expectedMode: .sharedModelCache,
        simulatorFileProtectionUnavailable: true
      )
    )

    let terminalMarker = AppStoreRawImageV1PreparationDiagnosticContract.terminalMarker(
      passed: false,
      receiptSeconds: 0.25,
      engineInitializationSeconds: nil,
      totalSeconds: 90_000,
      engineState: .initializing,
      cacheMode: .freshIsolatedDiagnosticCache,
      errorClass: "runtime_not_ready"
    )
    XCTAssertTrue(terminalMarker.hasPrefix("APP_STORE_RAW_IMAGE_V1_PREPARATION_FAIL "))
    XCTAssertTrue(terminalMarker.contains("receipt_ms=250"))
    XCTAssertTrue(terminalMarker.contains("engine_init_ms=-1"))
    XCTAssertTrue(terminalMarker.contains("total_ms=86400000"))
    XCTAssertTrue(terminalMarker.contains("engine_state=initializing"))
    XCTAssertTrue(terminalMarker.contains("cache_mode=fresh_isolated_diagnostic_cache"))
    XCTAssertTrue(terminalMarker.contains("error_class=runtime_not_ready"))
    XCTAssertFalse(terminalMarker.contains("/"))

    let directSuggestion = PhotoSuggestionV1(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .stool,
      bristolType: 4,
      mixedForm: .no,
      apparentColor: "brown",
      redAppearingMaterial: .notSure,
      blackTarryAppearance: .notSure
    )
    let directTerminal = AppStoreRawImageV1PreparationDiagnosticContract.terminalMarker(
      passed: true,
      receiptSeconds: 0.1,
      engineInitializationSeconds: 1,
      totalSeconds: 2,
      engineState: .ready,
      cacheMode: .sharedModelCache,
      errorClass: "none",
      directImageRequested: true,
      imageRequestSeconds: 0.5,
      strictPhotoSuggestionParsed: true,
      canonicalOutputSHA256: String(repeating: "c", count: 64),
      suggestion: directSuggestion
    )
    XCTAssertTrue(directTerminal.contains("direct_image_requested=true"))
    XCTAssertTrue(directTerminal.contains("image_request_ms=500"))
    XCTAssertTrue(directTerminal.contains("expected_sha256_validated=true"))
    XCTAssertTrue(directTerminal.contains("strict_schema=true"))
    XCTAssertTrue(directTerminal.contains("repair_used=false"))
    XCTAssertTrue(directTerminal.contains("gemma_stool_presence=stool"))
    XCTAssertTrue(directTerminal.contains("gemma_bristol_type=4"))
    XCTAssertTrue(directTerminal.contains("gemma_apparent_color=brown"))
    XCTAssertTrue(directTerminal.contains("gemma_red_suggestion=not_sure"))
    XCTAssertTrue(directTerminal.contains("gemma_black_tarry_suggestion=not_sure"))
    XCTAssertTrue(directTerminal.contains("person_answers=unselected"))
    XCTAssertTrue(directTerminal.contains("journal_container=ephemeral"))
    XCTAssertFalse(directTerminal.contains("/"))
  }

  func testRawPhotoThreeFixtureRegressionSelectorsAndExpectationsFailClosed() {
    let contract = AppStoreRawImageV1PreparationDiagnosticContract.self
    let baseArguments = [
      "GITimeline",
      InferenceConfiguration.internalAppStoreRawImageV1LaunchArgument,
      contract.launchArgument,
    ]
    let directArguments = baseArguments + [contract.directImageDataLaunchArgument]

    XCTAssertEqual(contract.requestedRegressionFixture(in: directArguments), .brown)
    XCTAssertTrue(contract.isValidRequest(in: directArguments))
    for fixture in contract.RegressionFixture.allCases {
      let arguments = directArguments + [fixture.launchArgument]
      XCTAssertEqual(contract.requestedRegressionFixture(in: arguments), fixture)
      XCTAssertTrue(contract.isValidRequest(in: arguments))
      XCTAssertTrue(AppEvaluationLaunchPolicy.isolatesJournal(arguments))
    }

    let malformed = contract.fixtureLaunchArgumentPrefix + "green-extra"
    let gpuArguments = [
      "GITimeline",
      InferenceConfiguration.internalAppStoreRawImageV1GPUMainLaunchArgument,
      contract.gpuMainLaunchArgument,
      contract.directImageDataLaunchArgument,
      contract.RegressionFixture.green.launchArgument,
    ]
    for invalid in [
      baseArguments + [contract.RegressionFixture.green.launchArgument],
      directArguments + [
        contract.RegressionFixture.brown.launchArgument,
        contract.RegressionFixture.brown.launchArgument,
      ],
      directArguments + [
        contract.RegressionFixture.brown.launchArgument,
        contract.RegressionFixture.green.launchArgument,
      ],
      directArguments + [malformed],
      directArguments + [
        contract.RegressionFixture.green.launchArgument,
        contract.synchronousSendLaunchArgument,
      ],
      gpuArguments,
    ] {
      XCTAssertFalse(contract.isValidRequest(in: invalid))
      XCTAssertTrue(AppEvaluationLaunchPolicy.isolatesJournal(invalid))
    }
    XCTAssertNil(contract.requestedRegressionFixture(
      in: directArguments + [malformed]
    ))
    XCTAssertNil(contract.requestedRegressionFixture(
      in: directArguments + [
        contract.RegressionFixture.brown.launchArgument,
        contract.RegressionFixture.green.launchArgument,
      ]
    ))

    let brown = PhotoSuggestionV1(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .stool,
      bristolType: 4,
      mixedForm: .no,
      apparentColor: "light_brown",
      redAppearingMaterial: .no,
      blackTarryAppearance: .no
    )
    let green = PhotoSuggestionV1(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .stool,
      bristolType: nil,
      mixedForm: .notSure,
      apparentColor: "green",
      redAppearingMaterial: .notSure,
      blackTarryAppearance: .notSure
    )
    let control = PhotoSuggestionV1(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .nonStool,
      bristolType: nil,
      mixedForm: .notSure,
      apparentColor: nil,
      redAppearingMaterial: .notSure,
      blackTarryAppearance: .notSure
    )
    XCTAssertTrue(contract.regressionExpectationSatisfied(brown, for: .brown))
    XCTAssertTrue(contract.regressionExpectationSatisfied(green, for: .green))
    XCTAssertTrue(contract.regressionExpectationSatisfied(control, for: .control))
    XCTAssertFalse(contract.regressionExpectationSatisfied(green, for: .brown))
    XCTAssertFalse(contract.regressionExpectationSatisfied(brown, for: .green))
    XCTAssertFalse(contract.regressionExpectationSatisfied(brown, for: .control))

    let marker = contract.terminalMarker(
      passed: true,
      receiptSeconds: 0.1,
      engineInitializationSeconds: 1,
      totalSeconds: 2,
      engineState: .ready,
      cacheMode: .sharedModelCache,
      errorClass: "none",
      directImageRequested: true,
      imageRequestSeconds: 0.5,
      strictPhotoSuggestionParsed: true,
      canonicalOutputSHA256: String(repeating: "d", count: 64),
      suggestion: green,
      regressionFixture: .green,
      regressionExpectationPassed: true
    )
    XCTAssertTrue(marker.contains("regression_fixture=green"))
    XCTAssertTrue(marker.contains("regression_expectation=PASS"))
    XCTAssertFalse(marker.contains("/"))
  }

  func testSingleFullPrefillComparisonIsExactIsolatedAndFailClosed() throws {
    let contract = RawPhotoV12TuningContract.self
    let baseline = InferenceConfiguration.appStoreRawImageV1
    let candidate = InferenceConfiguration.appStoreRawImageV12SubjectGateTuning
    let comparison = InferenceConfiguration.appStoreRawImageFullPrefill280

    XCTAssertEqual(contract.inputDirectoryName, "FullPrefillNormalizationABV1")
    XCTAssertEqual(contract.manifestFilename, "manifest.json")

    XCTAssertFalse(baseline.permitsRawPhotoV12TuningOverride(candidate))
    XCTAssertTrue(candidate.permitsRawPhotoV12TuningOverride(candidate))
    XCTAssertFalse(candidate.permitsRawPhotoV12TuningOverride(baseline))
    XCTAssertTrue(comparison.permitsRawPhotoV12TuningOverride(comparison))
    XCTAssertFalse(candidate.permitsRawPhotoV12TuningOverride(comparison))
    XCTAssertNotEqual(candidate, .runtimeDefault)
    XCTAssertNotEqual(candidate.id, baseline.id)
    XCTAssertNotEqual(candidate.promptVersion, baseline.promptVersion)
    XCTAssertNotEqual(candidate.imageMessageForm, baseline.imageMessageForm)
    XCTAssertEqual(candidate.engineBackend, baseline.engineBackend)
    XCTAssertEqual(candidate.visionBackend, baseline.visionBackend)
    XCTAssertEqual(candidate.mainCPUThreadCount, baseline.mainCPUThreadCount)
    XCTAssertEqual(candidate.maxNumImages, baseline.maxNumImages)
    XCTAssertEqual(candidate.maxNumTokens, baseline.maxNumTokens)
    XCTAssertEqual(candidate.topK, baseline.topK)
    XCTAssertEqual(candidate.topP, baseline.topP)
    XCTAssertEqual(candidate.temperature, baseline.temperature)
    XCTAssertEqual(candidate.seed, baseline.seed)
    XCTAssertEqual(baseline.visualTokenBudget, 70)
    XCTAssertEqual(candidate.visualTokenBudget, 140)
    XCTAssertEqual(comparison.visualTokenBudget, 280)
    XCTAssertTrue(candidate.usesRawPhotoV1Schema)
    XCTAssertTrue(candidate.usesRawPhotoV12SubjectGateTuning)
    XCTAssertTrue(comparison.usesRawPhotoV12SubjectGateTuning)
    XCTAssertEqual(comparison.engineBackend, candidate.engineBackend)
    XCTAssertEqual(comparison.visionBackend, candidate.visionBackend)
    XCTAssertEqual(comparison.mainCPUThreadCount, candidate.mainCPUThreadCount)
    XCTAssertEqual(comparison.maxNumImages, candidate.maxNumImages)
    XCTAssertEqual(comparison.maxNumTokens, candidate.maxNumTokens)
    XCTAssertEqual(comparison.topK, candidate.topK)
    XCTAssertEqual(comparison.topP, candidate.topP)
    XCTAssertEqual(comparison.temperature, candidate.temperature)
    XCTAssertEqual(comparison.seed, candidate.seed)
    XCTAssertEqual(comparison.promptVersion, candidate.promptVersion)
    XCTAssertEqual(comparison.imageMessageForm, candidate.imageMessageForm)
    XCTAssertNotEqual(comparison.id, candidate.id)
    XCTAssertEqual(
      candidate.analysisPipelineVersion,
      AnalysisPipelineVersion.appStoreRawImageV12SubjectGateTuning
    )
    XCTAssertTrue(candidate.imageMessageForm.contains(
      "Content.imageData(validatedSanitizedJPEGBytes)"
    ))
    XCTAssertFalse(candidate.imageMessageForm.contains("imageFile"))

    let prompt = InferenceService.rawPhotoFullPrefillPrompt
    XCTAssertTrue(prompt.contains("Inspect only visible pixels"))
    XCTAssertTrue(prompt.contains("Decide in this order:"))
    XCTAssertTrue(prompt.contains("possible visible appearance only"))
    XCTAssertTrue(prompt.contains("form unable_to_assess"))
    XCTAssertTrue(prompt.contains("yes, no, or not_sure"))
    XCTAssertFalse(prompt.contains(
      "{\"schema_version\":\"gi-photo-v1\",\"image_usable\":true"
    ))
    XCTAssertFalse(prompt.contains("geometric"))
    XCTAssertFalse(prompt.contains("wood block"))
    XCTAssertFalse(prompt.contains("red capsule"))
    XCTAssertFalse(prompt.contains("patterned rug"))
    XCTAssertEqual(
      hexSHA256(Data(prompt.utf8)),
      contract.candidatePromptSHA256,
      "A new candidate prompt requires a new versioned tuning lane."
    )
    let budget = AppStoreRawPhotoGenerationBudgetContract.self
    XCTAssertEqual(prompt.utf8.count, 1_825)
    XCTAssertEqual(
      contract.candidatePromptSHA256,
      budget.subjectGateCandidatePromptSHA256
    )
    XCTAssertEqual(budget.subjectGateCandidateMeasuredPromptTokens, 411)
    XCTAssertEqual(
      budget.subjectGateCandidateRenderedPromptWithImagePlaceholderTokens,
      423
    )
    XCTAssertEqual(
      budget.subjectGateCandidateRenderedPromptSHA256,
      "09286b32731dbad9c9ef1682060155868cfb5d6ceebe3a38263987ff2bba12c0"
    )
    XCTAssertEqual(budget.subjectGateCandidateMaximumFirstRequestTokens, 692)
    XCTAssertEqual(budget.fullPrefillComparisonMaximumFirstRequestTokens, 832)
    XCTAssertEqual(
      candidate.maxNumTokens - budget.subjectGateCandidateMaximumFirstRequestTokens,
      844
    )
    XCTAssertEqual(
      comparison.maxNumTokens - budget.fullPrefillComparisonMaximumFirstRequestTokens,
      704
    )
    XCTAssertTrue(budget.acceptsSubjectGateCandidate(
      configuration: candidate,
      policy: .rawPhoto,
      prompt: prompt
    ))
    XCTAssertTrue(budget.acceptsSubjectGateCandidate(
      configuration: comparison,
      policy: .rawPhoto,
      prompt: prompt
    ))
    XCTAssertFalse(budget.acceptsSubjectGateCandidate(
      configuration: candidate,
      policy: .structured,
      prompt: prompt
    ))
    XCTAssertFalse(budget.acceptsSubjectGateCandidate(
      configuration: baseline,
      policy: .rawPhoto,
      prompt: prompt
    ))
    XCTAssertFalse(budget.acceptsSubjectGateCandidate(
      configuration: candidate,
      policy: .rawPhoto,
      prompt: prompt + " "
    ))
    XCTAssertEqual(
      hexSHA256(Data(InferenceService.rawPhotoFullPrefillSchema.utf8)),
      "c44b50a1bf7b62b4b04cf2047036af8559b7f87168da83b755bd557519660533"
    )
    let candidateConversation = try LiteRTConversationConfigPlan(
      configuration: candidate
    ).makeConversationConfig()
    let shippingConversation = try LiteRTConversationConfigPlan(
      configuration: baseline
    ).makeConversationConfig()
    XCTAssertTrue(candidateConversation.enableResponseFormat)
    XCTAssertFalse(shippingConversation.enableResponseFormat)
    XCTAssertEqual(candidateConversation.visualTokenBudget, 140)
    XCTAssertEqual(shippingConversation.visualTokenBudget, 70)
    XCTAssertEqual(
      try LiteRTConversationConfigPlan(configuration: comparison)
        .makeConversationConfig().visualTokenBudget,
      280
    )

    for mode in LiteRTPhotoSendMode.allCases {
      let candidateTransport = LiteRTPhotoResponseFormatPlan(
        configuration: candidate,
        mode: mode
      )
      let shippingTransport = LiteRTPhotoResponseFormatPlan(
        configuration: baseline,
        mode: mode
      )
      XCTAssertEqual(
        candidateTransport.schema,
        InferenceService.rawPhotoFullPrefillSchema
      )
      let responseFormat = try XCTUnwrap(candidateTransport.makeResponseFormat())
      XCTAssertEqual(responseFormat.type, .jsonObject)
      XCTAssertEqual(
        responseFormat.schemaOrPattern,
        InferenceService.rawPhotoFullPrefillSchema
      )
      XCTAssertNil(shippingTransport.schema)
      XCTAssertNil(try shippingTransport.makeResponseFormat())
    }

    let shippingCache = LiteRTEngineCacheProfileV1(
      descriptor: .liteRTGemma4E4B,
      configuration: baseline
    )
    let candidateCache = LiteRTEngineCacheProfileV1(
      descriptor: .liteRTGemma4E4B,
      configuration: candidate
    )
    XCTAssertEqual(shippingCache.visualTokenBudget, "70")
    XCTAssertEqual(candidateCache.visualTokenBudget, "140")
    XCTAssertEqual(
      try shippingCache.sha256,
      "dcd0407d6ea1c9225f1cd433b5a9ac9982c807ee0063906d99de0e439cf88359"
    )
    XCTAssertEqual(
      try candidateCache.sha256,
      "502914286d0c17ae6db02dbeae445fc46fa840298138f4f341b1273ea6afd8f8"
    )
    XCTAssertNotEqual(try shippingCache.sha256, try candidateCache.sha256)

    let productArguments = [
      InferenceConfiguration.internalAppStoreRawImageV1CandidateLaunchArgument
    ]
    XCTAssertTrue(
      V1CandidateProductQualificationLaunchPolicy.presentsProductUI(
        productArguments
      )
    )
    let fixtureArguments = productArguments + [
      RawPhotoV12TuningContract.Arm.arm280.launchArgument,
      RawPhotoV12TuningContract.orderedFixtures[0].launchArgument,
    ]
    XCTAssertFalse(
      V1CandidateProductQualificationLaunchPolicy.presentsProductUI(
        fixtureArguments
      )
    )

    XCTAssertEqual(contract.orderedFixtures.count, 12)
    XCTAssertEqual(Set(contract.orderedFixtures.map(\.id)).count, 12)
    XCTAssertEqual(contract.orderedFixtures.first?.id, "t12-type4-cold-start")
    XCTAssertTrue(contract.orderedFixtures.allSatisfy {
      $0.id.hasPrefix("t")
        && !$0.id.hasPrefix("h")
        && $0.asset.hasPrefix("assets/t")
        && $0.sanitizedSHA256.count == 64
    })

    let manifestObject: [String: Any] = [
      "manifest_version": contract.laneVersion,
      "source_manifest_sha256": contract.sourceManifestSHA256,
      "partition": "tuning",
      "route": PhotoEvaluationRoute.rawImageSimulator.rawValue,
      "contains_real_health_photos": false,
      "fixtures": contract.orderedFixtures.map { fixture in
        [
          "id": fixture.id,
          "asset": fixture.asset,
          "sanitized_image_sha256": fixture.sanitizedSHA256,
        ]
      },
    ]
    let manifestData = try! JSONSerialization.data(withJSONObject: manifestObject)
    let manifest = try! RawPhotoV12TuningManifest.decodeAndValidate(manifestData)
    XCTAssertTrue(contract.validateManifest(manifest))
    var holdoutManifest = manifestObject
    holdoutManifest["partition"] = "holdout"
    XCTAssertThrowsError(try RawPhotoV12TuningManifest.decodeAndValidate(
      JSONSerialization.data(withJSONObject: holdoutManifest)
    ))
    var labeledManifest = manifestObject
    var labeledFixtures = labeledManifest["fixtures"] as! [[String: Any]]
    labeledFixtures[0]["reference_target"] = "target_like"
    labeledManifest["fixtures"] = labeledFixtures
    XCTAssertThrowsError(try RawPhotoV12TuningManifest.decodeAndValidate(
      JSONSerialization.data(withJSONObject: labeledManifest)
    ))

    let executable = "GITimeline"
    for arm in RawPhotoV12TuningContract.Arm.allCases {
      for fixture in contract.orderedFixtures {
        let arguments = [
          executable,
          contract.diagnosticSelector(for: arm),
          arm.launchArgument,
          fixture.launchArgument,
        ]
        XCTAssertEqual(contract.requestedArm(in: arguments), arm)
        XCTAssertEqual(contract.requestedFixture(in: arguments), fixture)
        XCTAssertTrue(contract.isValidRequest(in: arguments))
        XCTAssertTrue(AppEvaluationLaunchPolicy.isolatesJournal(arguments))
      }
    }

    let valid = [
      executable,
      contract.diagnosticSelector(for: .arm280),
      RawPhotoV12TuningContract.Arm.arm280.launchArgument,
      contract.orderedFixtures[1].launchArgument,
    ]
    let invalidRequests = [
      [
        executable,
        RawPhotoV12TuningContract.Arm.arm280.launchArgument,
        contract.orderedFixtures[1].launchArgument,
      ],
      valid + [RawPhotoV12TuningContract.Arm.arm140.launchArgument],
      valid + [InferenceConfiguration.internalAppStoreRawImageV1GPUMainLaunchArgument],
      valid + [contract.orderedFixtures[2].launchArgument],
      valid + [contract.fixtureLaunchArgumentPrefix + "h01-type2-lumpy-formed"],
      valid + [AppStoreRawImageV1PreparationDiagnosticContract.launchArgument],
      valid + [PhotoSuggestionEvaluationHarness.rawImageSimulatorLaunchArgument],
    ]
    for invalid in invalidRequests {
      XCTAssertFalse(contract.isValidRequest(in: invalid))
      XCTAssertTrue(AppEvaluationLaunchPolicy.isolatesJournal(invalid))
    }

    let nonStool = FullPrefillPhotoSuggestionV1(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .nonStool,
      bristolType: nil,
      form: "unable_to_assess",
      mixedForm: .notSure,
      apparentColor: nil,
      redAppearingMaterial: .notSure,
      blackTarryAppearance: .notSure
    )
    let forcedStool = FullPrefillPhotoSuggestionV1(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .stool,
      bristolType: 4,
      form: "smooth_formed",
      mixedForm: .no,
      apparentColor: "brown",
      redAppearingMaterial: .no,
      blackTarryAppearance: .no
    )
    let tooDark = FullPrefillPhotoSuggestionV1(
      imageUsable: false,
      retakeReason: .tooDark,
      stoolPresence: .uncertain,
      bristolType: nil,
      form: "unable_to_assess",
      mixedForm: .notSure,
      apparentColor: nil,
      redAppearingMaterial: .notSure,
      blackTarryAppearance: .notSure
    )
    let glare = FullPrefillPhotoSuggestionV1(
      imageUsable: false,
      retakeReason: .glare,
      stoolPresence: .uncertain,
      bristolType: nil,
      form: "unable_to_assess",
      mixedForm: .notSure,
      apparentColor: nil,
      redAppearingMaterial: .notSure,
      blackTarryAppearance: .notSure
    )
    let mixed = FullPrefillPhotoSuggestionV1(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .stool,
      bristolType: nil,
      form: "mixed",
      mixedForm: .yes,
      apparentColor: "mixed",
      redAppearingMaterial: .notSure,
      blackTarryAppearance: .notSure
    )
    let nonTargetFixture = contract.orderedFixtures.first {
      $0.screen == .nonStool
    }!
    let darkFixture = contract.orderedFixtures.first {
      $0.screen == .technicalTooDark
    }!
    let glareFixture = contract.orderedFixtures.first {
      $0.screen == .technicalGlare
    }!
    let mixedFixture = contract.orderedFixtures.first {
      $0.screen == .noForcedSingleForm
    }!
    let recordOnlyFixture = contract.orderedFixtures.first {
      $0.screen == .recordOnly
    }!
    XCTAssertTrue(contract.expectationSatisfied(nonStool, fixture: nonTargetFixture))
    XCTAssertFalse(contract.expectationSatisfied(forcedStool, fixture: nonTargetFixture))
    XCTAssertTrue(contract.expectationSatisfied(tooDark, fixture: darkFixture))
    XCTAssertTrue(contract.expectationSatisfied(glare, fixture: glareFixture))
    XCTAssertTrue(contract.expectationSatisfied(mixed, fixture: mixedFixture))
    XCTAssertTrue(contract.expectationSatisfied(forcedStool, fixture: recordOnlyFixture))
    XCTAssertEqual(
      contract.semanticScore(nonStool, fixture: nonTargetFixture),
      .init(
        subjectTechnicalPass: true,
        bristolWithinOne: nil,
        bristolExact: nil,
        formExact: nil,
        mixedExact: nil,
        fullAbstention: true
      )
    )
    XCTAssertEqual(contract.semanticScore(nonStool, fixture: nonTargetFixture).points, 2)
    XCTAssertEqual(contract.semanticScore(forcedStool, fixture: recordOnlyFixture).points, 5)

    let contradictoryRaw = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":4,"form":"smooth_formed","mixed_form":"no","apparent_color":"brown","red_appearing_material":"yes","black_tarry_appearance":"no"}
    """
    let normalization = try FullPrefillDependentFieldAbstentionV1
      .parseAndNormalize(contradictoryRaw)
    XCTAssertEqual(normalization.rawResponse, contradictoryRaw)
    XCTAssertEqual(normalization.normalizedSuggestion, nonStool)
    XCTAssertNotEqual(
      normalization.rawResponseSHA256,
      normalization.normalizedCanonicalSHA256
    )
    let marker = contract.terminalMarker(
      disposition: .success,
      arm: .arm280,
      fixture: nonTargetFixture,
      errorClass: "none",
      journalIsolationAttested: true,
      inferenceLatencyMilliseconds: 7_000,
      endToEndLatencyMilliseconds: 9_000,
      peakMemoryBytes: 3_000_000_000,
      outputSHA256: normalization.rawResponseSHA256,
      suggestion: normalization.normalizedSuggestion,
      normalization: normalization,
      expectationPassed: true
    )
    XCTAssertTrue(marker.hasPrefix("GI_V1_FULL_PREFILL_NORMALIZATION_AB_PASS "))
    XCTAssertTrue(marker.contains(
      "comparison_family=gi-v1-photo-full-prefill-normalization-policy-ab-v1"
    ))
    XCTAssertTrue(marker.contains(
      "marker_contract=gi-v1-full-prefill-normalization-marker-v1"
    ))
    XCTAssertTrue(marker.contains("schema_key_count=10"))
    XCTAssertTrue(marker.contains(
      "normalization_policy=gi-photo-dependent-field-abstention-v1"
    ))
    XCTAssertTrue(marker.contains("partition=tuning"))
    XCTAssertTrue(marker.contains("holdout_manifest_access=false"))
    XCTAssertTrue(marker.contains("holdout_asset_access=false"))
    XCTAssertTrue(marker.contains("journal_container=ephemeral"))
    XCTAssertTrue(marker.contains("isolation_attested=true"))
    XCTAssertTrue(marker.contains("strict_schema=true"))
    XCTAssertTrue(marker.contains("output_kind=canonical_strict_json"))
    XCTAssertTrue(marker.contains("repair_used=false"))
    XCTAssertTrue(marker.contains("expectation_pass=true"))
    XCTAssertTrue(marker.contains(
      "output_sha256=\(normalization.rawResponseSHA256)"
    ))
    XCTAssertTrue(marker.contains(
      "raw_response_sha256=\(normalization.rawResponseSHA256)"
    ))
    XCTAssertTrue(marker.contains("normalization_occurred=true"))
    XCTAssertTrue(marker.contains("normalization_count=1"))
    XCTAssertTrue(marker.contains(
      "normalized_fields=bristol_type.form.mixed_form.apparent_color.red_appearing_material.black_tarry_appearance"
    ))
    XCTAssertTrue(marker.contains(
      "normalized_canonical_sha256=\(normalization.normalizedCanonicalSHA256)"
    ))
    XCTAssertTrue(marker.contains("form=unable_to_assess"))
    XCTAssertTrue(marker.contains("semantic_points=2"))
    XCTAssertTrue(marker.contains("semantic_max_points=2"))
    XCTAssertFalse(marker.contains("/"))

    let scoredMorphology = contract.terminalMarker(
      disposition: .success,
      arm: .arm280,
      fixture: recordOnlyFixture,
      errorClass: "none",
      journalIsolationAttested: true,
      inferenceLatencyMilliseconds: 7_000,
      endToEndLatencyMilliseconds: 9_000,
      peakMemoryBytes: 3_000_000_000,
      outputSHA256: String(repeating: "b", count: 64),
      suggestion: forcedStool,
      expectationPassed: true
    )
    XCTAssertTrue(scoredMorphology.hasPrefix(
      "GI_V1_FULL_PREFILL_NORMALIZATION_AB_PASS "
    ))
    XCTAssertTrue(scoredMorphology.contains("bristol_within_one=true"))
    XCTAssertTrue(scoredMorphology.contains("form_exact=true"))
    XCTAssertTrue(scoredMorphology.contains("mixed_exact=true"))

    let baselineRecorded = contract.terminalMarker(
      disposition: .success,
      arm: .arm140,
      fixture: nonTargetFixture,
      errorClass: "none",
      journalIsolationAttested: true,
      inferenceLatencyMilliseconds: 7_000,
      endToEndLatencyMilliseconds: 9_000,
      peakMemoryBytes: 3_000_000_000,
      outputSHA256: String(repeating: "c", count: 64),
      suggestion: nonStool,
      expectationPassed: true
    )
    XCTAssertTrue(baselineRecorded.hasPrefix(
      "GI_V1_FULL_PREFILL_NORMALIZATION_AB_PASS "
    ))
    XCTAssertTrue(baselineRecorded.contains("expectation_scored=true"))
    XCTAssertTrue(baselineRecorded.contains("expectation_pass=true"))

    let baselineSchemaFailure = contract.terminalMarker(
      disposition: .recordedBaselineSchemaFailure,
      arm: .arm140,
      fixture: nonTargetFixture,
      errorClass: contract.strictSchemaErrorClass(
        .invalidValue("apparent_color")
      ),
      journalIsolationAttested: true,
      inferenceLatencyMilliseconds: 7_100,
      endToEndLatencyMilliseconds: 9_100,
      peakMemoryBytes: 3_100_000_000,
      outputSHA256: String(repeating: "d", count: 64)
    )
    XCTAssertTrue(baselineSchemaFailure.hasPrefix(
      "GI_V1_FULL_PREFILL_NORMALIZATION_AB_FAIL "
    ))
    XCTAssertTrue(baselineSchemaFailure.contains("strict_schema=false"))
    XCTAssertTrue(baselineSchemaFailure.contains(
      "output_kind=raw_response_sha256_only"
    ))
    XCTAssertTrue(baselineSchemaFailure.contains(
      "error=strict_schema_invalid_value_apparent_color"
    ))
    for unavailableField in [
      "image_usable", "retake_reason", "stool_presence", "bristol_type", "form",
      "mixed_form", "apparent_color", "red_appearing_material",
      "black_tarry_appearance",
    ] {
      XCTAssertTrue(baselineSchemaFailure.contains(
        "\(unavailableField)=unavailable"
      ))
    }
    XCTAssertTrue(baselineSchemaFailure.contains("expectation_scored=false"))
    XCTAssertTrue(baselineSchemaFailure.contains("expectation_pass=not_scored"))

    let candidateSchemaFailure = contract.terminalMarker(
      disposition: .failure,
      arm: .arm280,
      fixture: nonTargetFixture,
      errorClass: contract.strictSchemaErrorClass(.invalidJSON),
      journalIsolationAttested: true,
      inferenceLatencyMilliseconds: 7_100,
      endToEndLatencyMilliseconds: 9_100,
      peakMemoryBytes: 3_100_000_000,
      outputSHA256: String(repeating: "e", count: 64)
    )
    XCTAssertTrue(candidateSchemaFailure.hasPrefix(
      "GI_V1_FULL_PREFILL_NORMALIZATION_AB_FAIL "
    ))
    XCTAssertTrue(candidateSchemaFailure.contains("strict_schema=false"))
    XCTAssertTrue(candidateSchemaFailure.contains(
      "error=strict_schema_invalid_json"
    ))

    let baselineRuntimeFailure = contract.terminalMarker(
      disposition: .failure,
      arm: .arm140,
      fixture: nonTargetFixture,
      errorClass: "GITimelineError.modelNotVerified",
      journalIsolationAttested: true
    )
    XCTAssertTrue(baselineRuntimeFailure.hasPrefix(
      "GI_V1_FULL_PREFILL_NORMALIZATION_AB_FAIL "
    ))
    XCTAssertTrue(baselineRuntimeFailure.contains("strict_schema=false"))
    XCTAssertTrue(baselineRuntimeFailure.contains("output_kind=unavailable"))
    XCTAssertTrue(baselineRuntimeFailure.contains("output_sha256=unavailable"))
    XCTAssertTrue(baselineRuntimeFailure.contains("inference_latency_ms=-1"))
    XCTAssertEqual(
      contract.sanitizedErrorClass(
        StagedInferenceError(
          stage: .timeout,
          underlying: GITimelineError.operationInProgress
        )
      ),
      "inference_deadline_exceeded"
    )
    XCTAssertEqual(
      marker.split(separator: " ").dropFirst().count,
      62,
      "The bounded comparison marker binds every ordered field."
    )
  }

  func testFreshRawPhotoPreparationCacheIsSeparateProtectedAndBackupExcluded() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-fresh-cache-test-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let runID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
    let policy = ModelRuntimeEngineCachePolicy.freshIsolatedDiagnosticCache(
      runID: runID,
      baseDirectory: base,
      availableCapacityOverride: .max
    )
    let selection = try policy.cacheSelection(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    )
    let cache = selection.url
    XCTAssertEqual(policy.mode, .freshIsolatedDiagnosticCache)
    XCTAssertEqual(selection.disposition, .freshDiagnosticCache)
    XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    XCTAssertEqual(cache.lastPathComponent, "Cache")
    XCTAssertTrue(cache.path.contains("InternalRawImageV1PreparationCache"))
    XCTAssertFalse(cache.path.contains("/Models/"))
    XCTAssertEqual(
      try cache.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
      true
    )
    XCTAssertThrowsError(try policy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    )) { error in
      XCTAssertEqual(error as? GITimelineError, .evidenceAlreadyExists)
    }
    let secondRunPolicy = ModelRuntimeEngineCachePolicy.freshIsolatedDiagnosticCache(
      runID: UUID(),
      baseDirectory: base,
      availableCapacityOverride: .max
    )
    XCTAssertThrowsError(try secondRunPolicy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    )) { error in
      XCTAssertEqual(error as? GITimelineError, .evidenceAlreadyExists)
    }
    let forbiddenBase = try AppFolders.applicationSupport()
      .appendingPathComponent("Images", isDirectory: true)
      .appendingPathComponent("Forbidden-\(UUID().uuidString)", isDirectory: true)
    let overlappingPolicy = ModelRuntimeEngineCachePolicy.freshIsolatedDiagnosticCache(
      runID: UUID(),
      baseDirectory: forbiddenBase
    )
    XCTAssertThrowsError(
      try overlappingPolicy.cacheURL(
        for: .liteRTGemma4E4B,
        configuration: .appStoreRawImageV1
      )
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: forbiddenBase.path))
    #if targetEnvironment(simulator)
    // Simulator filesystems do not expose NSFileProtectionKey. The production
    // helper still applies complete protection before returning the directory.
    XCTAssertNil(
      try FileManager.default.attributesOfItem(atPath: cache.path)[.protectionKey]
    )
    #else
    XCTAssertEqual(
      try FileManager.default.attributesOfItem(atPath: cache.path)[.protectionKey]
        as? FileProtectionType,
      .complete
    )
    #endif
  }

  func testFreshCachesRootPreparationCacheIsOutsideJournalProtectedAndBackupExcluded() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-fresh-caches-root-test-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let runID = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
    let policy = ModelRuntimeEngineCachePolicy.freshCachesRootDiagnosticCache(
      runID: runID,
      baseDirectory: base,
      availableCapacityOverride: .max
    )
    let selection = try policy.cacheSelection(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    )
    let cache = selection.url
    XCTAssertEqual(policy.mode, .freshCachesRootDiagnosticCache)
    XCTAssertEqual(selection.disposition, .freshDiagnosticCache)
    XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    XCTAssertEqual(cache.lastPathComponent, "Cache")
    XCTAssertTrue(cache.path.contains("InternalRawImageV1PreparationCaches"))
    XCTAssertFalse(cache.path.contains("/Models/"))
    XCTAssertFalse(cache.path.hasPrefix(try AppFolders.applicationSupport().path + "/"))
    XCTAssertEqual(
      try cache.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
      true
    )
    XCTAssertThrowsError(try policy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    ))
    let secondRunPolicy = ModelRuntimeEngineCachePolicy.freshCachesRootDiagnosticCache(
      runID: UUID(),
      baseDirectory: base
    )
    XCTAssertThrowsError(try secondRunPolicy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    ))
    let forbiddenBase = try AppFolders.applicationSupport()
      .appendingPathComponent("ForbiddenCachesRoot-\(UUID().uuidString)", isDirectory: true)
    let overlappingPolicy = ModelRuntimeEngineCachePolicy.freshCachesRootDiagnosticCache(
      runID: UUID(),
      baseDirectory: forbiddenBase
    )
    XCTAssertThrowsError(try overlappingPolicy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    ))
    XCTAssertFalse(FileManager.default.fileExists(atPath: forbiddenBase.path))
    #if targetEnvironment(simulator)
    XCTAssertNil(
      try FileManager.default.attributesOfItem(atPath: cache.path)[.protectionKey]
    )
    #else
    XCTAssertEqual(
      try FileManager.default.attributesOfItem(atPath: cache.path)[.protectionKey]
        as? FileProtectionType,
      .completeUntilFirstUserAuthentication
    )
    #endif
  }

  func testExplicitFreshCachesRootReplacementRotatesOnlyExactDerivedRoot() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-fresh-caches-root-replacement-test-\(UUID().uuidString)",
      isDirectory: true
    )
    let base = parent.appendingPathComponent("GITimeline", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let sibling = base.appendingPathComponent("SiblingMustRemain", isDirectory: true)
    try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)
    let siblingFile = sibling.appendingPathComponent("sentinel.txt", isDirectory: false)
    try Data("keep".utf8).write(to: siblingFile)

    let firstRunID = try XCTUnwrap(
      UUID(uuidString: "11111111-2222-3333-4444-555555555555")
    )
    let firstPolicy = ModelRuntimeEngineCachePolicy.freshCachesRootDiagnosticCache(
      runID: firstRunID,
      baseDirectory: base,
      availableCapacityOverride: .max
    )
    let firstCache = try firstPolicy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    )
    try Data("derived".utf8).write(
      to: firstCache.appendingPathComponent("compiled.bin", isDirectory: false)
    )

    let secondRunID = try XCTUnwrap(
      UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    )
    let replacementPolicy = ModelRuntimeEngineCachePolicy.freshCachesRootDiagnosticCache(
      runID: secondRunID,
      baseDirectory: base,
      availableCapacityOverride: .max,
      replaceExistingDiagnosticRoot: true
    )
    let replacementCache = try replacementPolicy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    )

    XCTAssertFalse(FileManager.default.fileExists(
      atPath: firstCache.deletingLastPathComponent().path
    ))
    XCTAssertTrue(FileManager.default.fileExists(atPath: replacementCache.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: siblingFile.path))
    XCTAssertEqual(try String(contentsOf: siblingFile, encoding: .utf8), "keep")
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(
        at: base.appendingPathComponent(
          "InternalRawImageV1PreparationCaches",
          isDirectory: true
        ),
        includingPropertiesForKeys: nil
      ).map(\.lastPathComponent),
      [secondRunID.uuidString.lowercased()]
    )
  }

  func testExplicitFreshCachesRootReplacementRefusesUnexpectedShapeWithoutDeletion() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-fresh-caches-root-shape-test-\(UUID().uuidString)",
      isDirectory: true
    )
    let base = parent.appendingPathComponent("GITimeline", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    let firstPolicy = ModelRuntimeEngineCachePolicy.freshCachesRootDiagnosticCache(
      runID: UUID(),
      baseDirectory: base,
      availableCapacityOverride: .max
    )
    let firstCache = try firstPolicy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    )
    let unexpected = firstCache.deletingLastPathComponent()
      .appendingPathComponent("unexpected.txt", isDirectory: false)
    try Data("do not delete".utf8).write(to: unexpected)
    let sibling = base.appendingPathComponent("SharedSibling", isDirectory: true)
    try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)

    let replacementPolicy = ModelRuntimeEngineCachePolicy.freshCachesRootDiagnosticCache(
      runID: UUID(),
      baseDirectory: base,
      availableCapacityOverride: .max,
      replaceExistingDiagnosticRoot: true
    )
    XCTAssertThrowsError(try replacementPolicy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    )) { error in
      XCTAssertEqual(error as? GITimelineError, .invalidModelDescriptor)
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: firstCache.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: unexpected.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
  }

  func testExplicitFreshCachesRootReplacementRefusesNestedSymlinkWithoutDeletion() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-fresh-caches-root-nested-symlink-test-\(UUID().uuidString)",
      isDirectory: true
    )
    let base = parent.appendingPathComponent("GITimeline", isDirectory: true)
    let outsideTarget = parent.appendingPathComponent("OutsideTarget", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    try FileManager.default.createDirectory(at: outsideTarget, withIntermediateDirectories: true)
    let outsideSentinel = outsideTarget.appendingPathComponent("sentinel.txt")
    try Data("outside".utf8).write(to: outsideSentinel)
    let firstPolicy = ModelRuntimeEngineCachePolicy.freshCachesRootDiagnosticCache(
      runID: UUID(),
      baseDirectory: base,
      availableCapacityOverride: .max
    )
    let firstCache = try firstPolicy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    )
    let nestedLink = firstCache.appendingPathComponent("linked-output")
    try FileManager.default.createSymbolicLink(
      at: nestedLink,
      withDestinationURL: outsideTarget
    )

    let replacementPolicy = ModelRuntimeEngineCachePolicy.freshCachesRootDiagnosticCache(
      runID: UUID(),
      baseDirectory: base,
      availableCapacityOverride: .max,
      replaceExistingDiagnosticRoot: true
    )
    XCTAssertThrowsError(try replacementPolicy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    )) { error in
      XCTAssertEqual(error as? GITimelineError, .invalidModelDescriptor)
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: firstCache.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: nestedLink.path))
    XCTAssertEqual(try String(contentsOf: outsideSentinel, encoding: .utf8), "outside")
  }

  func testFreshPreparationCachesRejectSymlinkedRootsWithoutCreatingTargetChildren() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-cache-symlink-test-\(UUID().uuidString)",
      isDirectory: true
    )
    let target = root.appendingPathComponent("Target", isDirectory: true)
    let linkedBase = root.appendingPathComponent("LinkedBase", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linkedBase, withDestinationURL: target)
    defer { try? FileManager.default.removeItem(at: root) }

    let cachesPolicy = ModelRuntimeEngineCachePolicy.freshCachesRootDiagnosticCache(
      runID: UUID(),
      baseDirectory: linkedBase
    )
    XCTAssertThrowsError(try cachesPolicy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    ))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])

    let supportPolicy = ModelRuntimeEngineCachePolicy.freshIsolatedDiagnosticCache(
      runID: UUID(),
      baseDirectory: linkedBase
    )
    XCTAssertThrowsError(try supportPolicy.cacheURL(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    ))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
  }

  func testCoordinatorPreparesOneFreshCachesRootAndReusesItInProcess() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-cache-preflight-test-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let runtime = ModelRuntimeCoordinator(
      engineCachePolicy: .freshCachesRootDiagnosticCache(
        runID: UUID(),
        baseDirectory: base,
        availableCapacityOverride: .max
      )
    )
    let first = try await runtime.prepareEngineCache(for: .liteRTGemma4E4B)
    let reused = try await runtime.prepareEngineCache(for: .liteRTGemma4E4B)
    XCTAssertEqual(first.mode, .freshCachesRootDiagnosticCache)
    XCTAssertEqual(reused.mode, .freshCachesRootDiagnosticCache)
    XCTAssertTrue(first.backupExcluded)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(
        at: base.appendingPathComponent(
          "InternalRawImageV1PreparationCaches",
          isDirectory: true
        ),
        includingPropertiesForKeys: nil
      ).count,
      1
    )
  }
  #endif

  func testShippingModelCacheIsVersionedRecreatableAndOutsideJournalStorage() throws {
    let cacheProfile = LiteRTEngineCacheProfileV1(
      descriptor: .liteRTGemma4E4B,
      configuration: .runtimeDefault
    )
    let cacheSchema = try AppFolders.liteRTCacheSchema(for: cacheProfile)
    XCTAssertEqual(cacheProfile.format, "gi-litert-engine-cache-profile-v2")
    XCTAssertEqual(cacheProfile.engineBackend, InferenceConfiguration.runtimeDefault.engineBackend)
    XCTAssertEqual(cacheProfile.visionBackend, InferenceConfiguration.runtimeDefault.visionBackend)
    XCTAssertEqual(cacheProfile.maxNumTokens, InferenceConfiguration.runtimeDefault.maxNumTokens)
    XCTAssertEqual(cacheProfile.visualTokenBudget, InferenceConfiguration.runtimeDefault.visualTokenBudget.map(String.init) ?? "runtime-default")
    XCTAssertEqual(
      cacheSchema,
      "litert-\(AppFolders.liteRTLMRevision)-v5-\(try cacheProfile.sha256)"
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-shipping-cache-test-\(UUID().uuidString)",
      isDirectory: true
    )
    let cachesRoot = root.appendingPathComponent("SystemCaches", isDirectory: true)
    let syntheticJournalRoot = root.appendingPathComponent("SyntheticJournal", isDirectory: true)
    let syntheticJournalSentinel = syntheticJournalRoot.appendingPathComponent(
      "must-remain.txt",
      isDirectory: false
    )
    try FileManager.default.createDirectory(
      at: syntheticJournalRoot,
      withIntermediateDirectories: true
    )
    try Data("unchanged synthetic journal sentinel".utf8).write(
      to: syntheticJournalSentinel,
      options: .atomic
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let cache = try AppFolders.modelCache(
      for: .liteRTGemma4E4B,
      cachesDirectory: cachesRoot,
      availableCapacityOverride: .max
    )
    let expected = cachesRoot
      .appendingPathComponent("GITimeline", isDirectory: true)
      .appendingPathComponent("LiteRT", isDirectory: true)
      .appendingPathComponent(cacheSchema, isDirectory: true)
      .appendingPathComponent(
        ModelDescriptor.liteRTGemma4E4B.cacheNamespace,
        isDirectory: true
      )
      .appendingPathComponent("Cache", isDirectory: true)
      .standardizedFileURL
    XCTAssertEqual(cache.standardizedFileURL, expected)
    XCTAssertFalse(cache.path.contains("Application Support"))
    XCTAssertFalse(cache.path.contains("/Models/"))
    XCTAssertEqual(
      try cache.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
      true
    )
    XCTAssertEqual(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        cachesDirectory: cachesRoot,
        availableCapacityOverride: .max
      ),
      cache
    )
    try FileManager.default.removeItem(at: cache)
    let recreated = try AppFolders.modelCache(
      for: .liteRTGemma4E4B,
      cachesDirectory: cachesRoot,
      availableCapacityOverride: .max
    )
    XCTAssertEqual(recreated, cache)
    XCTAssertTrue(FileManager.default.fileExists(atPath: recreated.path))
    XCTAssertEqual(
      try String(contentsOf: syntheticJournalSentinel, encoding: .utf8),
      "unchanged synthetic journal sentinel"
    )
    #if targetEnvironment(simulator)
    XCTAssertNil(
      try FileManager.default.attributesOfItem(
        atPath: recreated.path
      )[.protectionKey]
    )
    #endif
  }

  func testShippingModelCacheRejectsSymlinkedAppCacheRoot() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-shipping-cache-symlink-test-\(UUID().uuidString)",
      isDirectory: true
    )
    let cachesRoot = root.appendingPathComponent("SystemCaches", isDirectory: true)
    let target = root.appendingPathComponent("Target", isDirectory: true)
    let appCacheLink = cachesRoot.appendingPathComponent("GITimeline", isDirectory: true)
    try FileManager.default.createDirectory(at: cachesRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: appCacheLink, withDestinationURL: target)
    defer { try? FileManager.default.removeItem(at: root) }

    XCTAssertThrowsError(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        cachesDirectory: cachesRoot,
        availableCapacityOverride: .max
      )
    )
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
  }

  func testWarmShippingCacheBypassesColdCapacityGateButEmptyCacheDoesNot() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-shipping-cache-capacity-test-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = try AppFolders.modelCache(
      for: .liteRTGemma4E4B,
      cachesDirectory: root,
      availableCapacityOverride: .max
    )
    try Data("synthetic compiled cache".utf8).write(
      to: cache.appendingPathComponent("program_cache.bin"),
      options: .atomic
    )
    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    XCTAssertEqual(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        cachesDirectory: root,
        availableCapacityOverride: 0
      ),
      cache
    )
    try FileManager.default.removeItem(at: cache)
    XCTAssertThrowsError(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        cachesDirectory: root,
        availableCapacityOverride: 0
      )
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .insufficientModelStorage)
    }
  }

  func testCoordinatorRecreatesSharedCacheAfterPurgeInSameProcess() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-runtime-cache-purge-test-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = ModelRuntimeCoordinator(
      engineCachePolicy: .sharedModelCacheForTesting(
        cachesDirectory: root,
        availableCapacityOverride: .max
      )
    )
    let first = try await runtime.prepareEngineCache(for: .liteRTGemma4E4B)
    let appCaches = root.appendingPathComponent("GITimeline", isDirectory: true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: appCaches.path))
    try FileManager.default.removeItem(at: appCaches)
    let second = try await runtime.prepareEngineCache(for: .liteRTGemma4E4B)
    XCTAssertEqual(first.mode, .sharedModelCache)
    XCTAssertEqual(second.mode, .sharedModelCache)
    XCTAssertEqual(first.disposition, .coldVersionedCache)
    XCTAssertEqual(second.disposition, .coldVersionedCache)
    XCTAssertTrue(first.backupExcluded)
    XCTAssertTrue(second.backupExcluded)
    XCTAssertTrue(FileManager.default.fileExists(atPath: appCaches.path))
  }

  func testPhysicalRawImageDiagnosticMarkerIsCompleteAndDoesNotLeakErrorText() throws {
    let runID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let passCheckpoint = PhysicalRawImageDiagnosticCheckpoint(
      runID: runID,
      startedAt: startedAt,
      updatedAt: startedAt.addingTimeInterval(4),
      phase: .completed,
      stageHistory: [.started, .receiptVerified, .fixturePrepared, .engineReady, .imageRequestStarted, .completed],
      sanitizedImageSHA256: String(repeating: "a", count: 64),
      receiptVerified: true,
      preparationSeconds: 1.25,
      imageRequestSeconds: 2.5,
      totalSeconds: 4,
      peakResidentMemoryBytes: 123_456,
      dominantColor: .brown,
      configuredVisualTokenBudgetReadback: 70,
      outcome: "DIAGNOSTIC_PASS"
    )
    let passMarker = PhysicalRawImageDiagnosticContract.consoleMarker(
      for: passCheckpoint,
      checkpointWritten: true
    )
    XCTAssertTrue(passMarker.hasPrefix("PHYSICAL_RAW_IMAGE_DIAGNOSTIC_PASS "))
    XCTAssertTrue(passMarker.contains("config=physical-gpu-cpu-vision70-ctx1024-v1"))
    XCTAssertTrue(passMarker.contains("model=litert-gemma-4-e4b-28299f30"))
    XCTAssertTrue(passMarker.contains("revision=28299f30"))
    XCTAssertTrue(passMarker.contains(
      "model_sha256=\(PhysicalRawImageDiagnosticContract.descriptor.expectedSHA256)"
    ))
    XCTAssertTrue(passMarker.contains(
      "fixture_bundle_sha256=\(PhysicalRawImageDiagnosticContract.bundledBrownFixtureSHA256)"
    ))
    XCTAssertTrue(passMarker.contains("sanitized_sha256=\(String(repeating: "a", count: 64))"))
    XCTAssertTrue(passMarker.contains("receipt_verified=true"))
    XCTAssertTrue(passMarker.contains("prompt=gi-observation-v1"))
    XCTAssertTrue(passMarker.contains("visual_tokens_expected=70"))
    XCTAssertTrue(passMarker.contains("visual_tokens_configured_request=70"))
    XCTAssertTrue(passMarker.contains("vision_graph_telemetry=unavailable"))
    XCTAssertTrue(passMarker.contains("contract_fields=runtime_verified"))
    XCTAssertTrue(passMarker.contains("context_tokens=1024"))
    XCTAssertTrue(passMarker.contains("top_k=1"))
    XCTAssertTrue(passMarker.contains("top_p=1.0"))
    XCTAssertTrue(passMarker.contains("temperature=0.0"))
    XCTAssertTrue(passMarker.contains("seed=0"))
    XCTAssertTrue(passMarker.contains("prep_ms=1250"))
    XCTAssertTrue(passMarker.contains("request_ms=2500"))
    XCTAssertTrue(passMarker.contains("total_ms=4000"))
    XCTAssertTrue(passMarker.contains("peak_resident_bytes=123456"))
    XCTAssertTrue(passMarker.contains("error_class=none"))
    XCTAssertTrue(passMarker.contains("checkpoint=written"))
    XCTAssertFalse(passMarker.contains(runID.uuidString))
    XCTAssertFalse(passMarker.contains("/"))

    let controlObservation = VisualObservation(
      imageUsable: false,
      qualityIssue: "not_target_image",
      apparentBristolType: nil,
      apparentColor: "unable_to_assess",
      form: "unable_to_assess",
      redAppearingMaterial: "unable_to_assess",
      blackTarryAppearance: "unable_to_assess"
    )
    let structuredCheckpoint = PhysicalRawImageDiagnosticCheckpoint(
      runID: runID,
      startedAt: startedAt,
      updatedAt: startedAt.addingTimeInterval(8),
      phase: .completed,
      stageHistory: [
        .started, .receiptVerified, .fixturePrepared, .engineReady,
        .structuredRequestStarted, .structuredRequestCompleted,
        .structuredRepairStarted, .structuredRepairCompleted,
        .structuredValidationCompleted, .completed,
      ],
      diagnosticRequest: .controlStructuredObservation,
      fixtureID: SyntheticFixture.control.rawValue,
      bundledFixtureSHA256: PhysicalRawImageDiagnosticContract.bundledControlFixtureSHA256,
      sanitizedImageSHA256: PhysicalRawImageDiagnosticContract.sanitizedControlFixtureSHA256,
      receiptVerified: true,
      preparationSeconds: 1,
      totalSeconds: 8,
      peakResidentMemoryBytes: 654_321,
      configuredVisualTokenBudgetReadback: 70,
      structuredInitialSeconds: 2,
      structuredRepairSeconds: 3,
      structuredSeconds: 5,
      repairUsed: true,
      strictStructuredParsed: true,
      structuredExpectationPassed: true,
      structuredObservation: controlObservation,
      canonicalObservationSHA256: String(repeating: "c", count: 64),
      outcome: "DIAGNOSTIC_PASS_AFTER_REPAIR"
    )
    let structuredMarker = PhysicalRawImageDiagnosticContract.consoleMarker(
      for: structuredCheckpoint,
      checkpointWritten: true
    )
    XCTAssertTrue(structuredMarker.hasPrefix("PHYSICAL_RAW_IMAGE_DIAGNOSTIC_PASS "))
    XCTAssertTrue(structuredMarker.contains("request_kind=structured_observation"))
    XCTAssertTrue(structuredMarker.contains("fixture=control"))
    XCTAssertTrue(structuredMarker.contains("visual_tokens_expected=70"))
    XCTAssertTrue(structuredMarker.contains("visual_tokens_configured_request=70"))
    XCTAssertTrue(structuredMarker.contains("repair_used=true"))
    XCTAssertTrue(structuredMarker.contains("strict_structured=true"))
    XCTAssertTrue(structuredMarker.contains("structured_expectation=true"))
    XCTAssertTrue(structuredMarker.contains("observation_sha256=\(String(repeating: "c", count: 64))"))
    XCTAssertFalse(structuredMarker.contains(runID.uuidString))
    XCTAssertFalse(structuredMarker.contains("/"))

    let privateError = NSError(
      domain: "/Users/private/device-identifier",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "/Users/private/photo.jpg on DEVICE-SECRET"]
    )
    let errorClass = PhysicalRawImageDiagnosticContract.sanitizedErrorClass(privateError)
    let failCheckpoint = PhysicalRawImageDiagnosticCheckpoint(
      runID: runID,
      startedAt: startedAt,
      updatedAt: startedAt,
      phase: .failed,
      stageHistory: [.started, .failed],
      outcome: "FAIL",
      failureStage: InferenceErrorStage.persistence.rawValue,
      errorClass: errorClass
    )
    let failMarker = PhysicalRawImageDiagnosticContract.consoleMarker(
      for: failCheckpoint,
      checkpointWritten: false
    )
    XCTAssertTrue(failMarker.hasPrefix("PHYSICAL_RAW_IMAGE_DIAGNOSTIC_FAIL "))
    XCTAssertEqual(errorClass, "NSError")
    XCTAssertTrue(failMarker.contains("error_class=NSError"))
    XCTAssertFalse(failMarker.contains("Users"))
    XCTAssertFalse(failMarker.contains("DEVICE-SECRET"))
    XCTAssertFalse(failMarker.contains("photo.jpg"))
    XCTAssertFalse(failMarker.contains("/"))

    let structuredFallback = PhysicalRawImageDiagnosticContract.fallbackFailureMarker(
      for: PhysicalRawImageDiagnosticError.configurationDrift,
      request: .controlStructuredObservation
    )
    XCTAssertTrue(structuredFallback.hasPrefix("PHYSICAL_RAW_IMAGE_DIAGNOSTIC_FAIL "))
    XCTAssertTrue(structuredFallback.contains("request_kind=structured_observation"))
    XCTAssertTrue(structuredFallback.contains("fixture=control"))
    XCTAssertTrue(structuredFallback.contains(
      "fixture_bundle_sha256=\(PhysicalRawImageDiagnosticContract.bundledControlFixtureSHA256)"
    ))
    XCTAssertTrue(structuredFallback.contains("sanitized_sha256=unavailable"))
    XCTAssertTrue(structuredFallback.contains("contract_fields=expected_unverified"))

    let invalidFallback = PhysicalRawImageDiagnosticContract.fallbackFailureMarker(
      for: PhysicalRawImageDiagnosticError.configurationDrift
    )
    XCTAssertTrue(invalidFallback.hasPrefix("PHYSICAL_RAW_IMAGE_DIAGNOSTIC_FAIL "))
    XCTAssertTrue(invalidFallback.contains("request_kind=invalid_configuration"))
    XCTAssertTrue(invalidFallback.contains("fixture=unknown"))
    XCTAssertTrue(invalidFallback.contains("fixture_bundle_sha256=unavailable"))
    XCTAssertTrue(invalidFallback.contains("sanitized_sha256=unavailable"))
    XCTAssertTrue(invalidFallback.contains("contract_fields=expected_unverified"))
  }

  func testPhysicalRawImageSuiteLaunchArgumentIsExactAndMutuallyIsolated() {
    let argument = PhysicalRawImageSuiteContract.launchArgument
    XCTAssertEqual(argument, "--run-physical-raw-image-suite")
    XCTAssertTrue(PhysicalRawImageSuiteContract.isRequested(in: ["GITimeline", argument]))
    XCTAssertFalse(PhysicalRawImageSuiteContract.isRequested(in: ["GITimeline"]))
    XCTAssertFalse(PhysicalRawImageSuiteContract.isRequested(in: ["GITimeline", "\(argument)-extra"]))
    XCTAssertFalse(PhysicalRawImageDiagnosticContract.isRequested(in: ["GITimeline", argument]))
    XCTAssertFalse(PhysicalRawImageSuiteContract.isRequested(
      in: ["GITimeline", PhysicalRawImageDiagnosticContract.launchArgument]
    ))
    XCTAssertFalse(PhysicalRawImageSuiteContract.isRequested(
      in: [
        "GITimeline",
        argument,
        PhysicalRawImageDiagnosticContract.structuredControlLaunchArgument,
      ]
    ))
    XCTAssertFalse(PhysicalRawImageSuiteContract.isRequested(
      in: ["GITimeline", argument, "--run-embedded-gemma-normal-flow"]
    ))
    XCTAssertFalse(PhysicalRawImageSuiteContract.isRequested(
      in: ["GITimeline", argument, "\(argument)-extra"]
    ))
    XCTAssertEqual(PhysicalRawImageSuiteContract.fixtureIDs, ["brown", "green", "control"])
    XCTAssertEqual(PhysicalRawImageSuiteContract.configuration, .physicalGPUCPUVision70)
    XCTAssertFalse(PhysicalRawImageSuiteContract.configuration.usesLocalPixelBridge)
    XCTAssertTrue(PhysicalRawImageSuiteContract.configuration.imageMessageForm.contains("imageFile"))
  }

  func testPhysicalRawImageSuiteUsesPredeclaredFieldLevelStructuredExpectations() {
    let brown = VisualObservation(
      imageUsable: true,
      qualityIssue: "none",
      apparentBristolType: 4,
      apparentColor: "dark_brown",
      form: "smooth_formed",
      redAppearingMaterial: "not_observed",
      blackTarryAppearance: "not_observed"
    )
    let green = VisualObservation(
      imageUsable: true,
      qualityIssue: "none",
      apparentBristolType: 4,
      apparentColor: "green",
      form: "smooth_formed",
      redAppearingMaterial: "not_observed",
      blackTarryAppearance: "not_observed"
    )
    let control = VisualObservation(
      imageUsable: false,
      qualityIssue: "not_target_image",
      apparentBristolType: nil,
      apparentColor: "unable_to_assess",
      form: "unable_to_assess",
      redAppearingMaterial: "unable_to_assess",
      blackTarryAppearance: "unable_to_assess"
    )
    XCTAssertTrue(PhysicalRawImageSuiteContract.structuredExpectationSatisfied(
      fixtureID: "brown", observation: brown
    ))
    XCTAssertTrue(PhysicalRawImageSuiteContract.structuredExpectationSatisfied(
      fixtureID: "green", observation: green
    ))
    XCTAssertTrue(PhysicalRawImageSuiteContract.structuredExpectationSatisfied(
      fixtureID: "control", observation: control
    ))
    XCTAssertTrue(
      PhysicalRawImageDiagnosticContract.structuredControlExpectationSatisfied(control)
    )
    XCTAssertFalse(PhysicalRawImageSuiteContract.structuredExpectationSatisfied(
      fixtureID: "green", observation: brown
    ))
    XCTAssertFalse(PhysicalRawImageSuiteContract.structuredExpectationSatisfied(
      fixtureID: "control", observation: brown
    ))
    let incompleteAbstention = VisualObservation(
      imageUsable: false,
      qualityIssue: "not_target_image",
      apparentBristolType: nil,
      apparentColor: "brown",
      form: "unable_to_assess",
      redAppearingMaterial: "unable_to_assess",
      blackTarryAppearance: "unable_to_assess"
    )
    XCTAssertFalse(
      PhysicalRawImageDiagnosticContract.structuredControlExpectationSatisfied(
        incompleteAbstention
      )
    )
  }

  func testPhysicalRawImageSuiteMarkerIsCompleteAndPathFree() throws {
    let runID = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let fixtureResults: [PhysicalRawImageSuiteFixtureResult] = [
      ("brown", .brown, "a"),
      ("green", .green, "b"),
      ("control", .other, "c"),
    ].map { fixtureID, color, hashCharacter in
      PhysicalRawImageSuiteFixtureResult(
        fixtureID: fixtureID,
        bundledFixtureSHA256: try! XCTUnwrap(
          PhysicalRawImageSuiteContract.bundledFixtureSHA256[fixtureID]
        ),
        sanitizedImageSHA256: String(repeating: hashCharacter, count: 64),
        expectedDominantColor: color,
        dominantColor: color,
        dominantColorSeconds: 1,
        structuredInitialSeconds: 1,
        structuredRepairSeconds: nil,
        structuredSeconds: 2,
        repairUsed: false,
        strictStructuredParsed: true,
        structuredExpectationPassed: true,
        structuredObservation: nil,
        canonicalObservationSHA256: String(repeating: hashCharacter, count: 64),
        outcome: "PASS",
        failureStage: nil,
        errorClass: nil
      )
    }
    let checkpoint = PhysicalRawImageSuiteCheckpoint(
      runID: runID,
      startedAt: startedAt,
      updatedAt: startedAt.addingTimeInterval(20),
      phase: .completed,
      stageHistory: ["suite:started", "suite:completed"],
      receiptVerified: true,
      preparationSeconds: 10,
      totalSeconds: 20,
      peakResidentMemoryBytes: 3_000_000_000,
      fixtureResults: fixtureResults,
      colorPassCount: 3,
      structuredParseCount: 3,
      structuredExpectationPassCount: 3,
      uniqueCanonicalObservationCount: 3,
      outcome: "SUITE_PASS"
    )
    let marker = PhysicalRawImageSuiteContract.consoleMarker(
      for: checkpoint,
      checkpointWritten: true
    )
    XCTAssertTrue(marker.hasPrefix("PHYSICAL_RAW_IMAGE_SUITE_PASS "))
    XCTAssertTrue(marker.contains("colors=brown-BROWN_green-GREEN_control-OTHER"))
    XCTAssertTrue(marker.contains("color_pass=3_of_3"))
    XCTAssertTrue(marker.contains("structured_parse=3_of_3"))
    XCTAssertTrue(marker.contains("structured_expectations=3_of_3"))
    XCTAssertTrue(marker.contains("unique_structured=3_of_3"))
    XCTAssertTrue(marker.contains("checkpoint=written"))
    XCTAssertFalse(marker.contains(runID.uuidString))
    XCTAssertFalse(marker.contains("/"))
    XCTAssertFalse(marker.contains("Users"))
  }

  func testModelImportReceiptRoundTripRetainsSource() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let imports = root.appendingPathComponent("Import", isDirectory: true)
    let models = root.appendingPathComponent("Models", isDirectory: true)
    try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
    let payload = Data("tiny deterministic model fixture".utf8)
    let descriptor = try tinyDescriptor(data: payload)
    let source = imports.appendingPathComponent(descriptor.artifactFilename)
    try payload.write(to: source)
    let importer = ModelImporter(importDirectory: imports, modelsDirectory: models)

    let result = try importer.importModel(descriptor)
    let reread = try XCTUnwrap(importer.receipt(for: descriptor))

    XCTAssertEqual(reread.descriptorID, result.receipt.descriptorID)
    XCTAssertEqual(reread.importedSHA256, result.receipt.importedSHA256)
    XCTAssertEqual(reread.verifiedAt.timeIntervalSince1970, result.receipt.verifiedAt.timeIntervalSince1970, accuracy: 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "successful import must retain the staged source")
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.modelURL.path))
    XCTAssertNotNil(try importer.verifiedModel(for: descriptor))
  }

  func testBundledModelResolutionUsesReadOnlyLocationAndBuildKeyedReceipt() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let embedded = root.appendingPathComponent("EmbeddedModels", isDirectory: true)
    let models = root.appendingPathComponent("Models", isDirectory: true)
    try FileManager.default.createDirectory(at: embedded, withIntermediateDirectories: true)
    let payload = Data("tiny bundled deterministic model fixture".utf8)
    let descriptor = try tinyDescriptor(data: payload)
    try payload.write(to: embedded.appendingPathComponent(descriptor.artifactFilename))
    let build = ModelAppBuildIdentity(
      bundleIdentifier: "com.example.GITimeline.hackathon",
      shortVersion: "1.0",
      buildNumber: "42"
    )
    let importer = ModelImporter(
      modelsDirectory: models,
      embeddedModelsDirectory: embedded,
      appBuildIdentity: build
    )

    let first = try importer.verifiedBundledModel(for: descriptor)
    let second = try importer.verifiedBundledModel(for: descriptor)

    XCTAssertEqual(first.location.kind, .applicationBundle)
    XCTAssertEqual(first.modelURL, embedded.appendingPathComponent(descriptor.artifactFilename))
    XCTAssertEqual(first.receipt.appBuildIdentity, build)
    XCTAssertEqual(first.receipt.locationKind, .applicationBundle)
    XCTAssertEqual(
      first.receipt.verifiedAt.timeIntervalSince1970,
      second.receipt.verifiedAt.timeIntervalSince1970,
      accuracy: 1,
      "same-build launch should reuse verification"
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: try importer.modelURL(for: descriptor).path))
  }

  func testTrustedBundledBuildReceiptAvoidsRuntimeRehash() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let embedded = root.appendingPathComponent("EmbeddedModels", isDirectory: true)
    let models = root.appendingPathComponent("Models", isDirectory: true)
    try FileManager.default.createDirectory(at: embedded, withIntermediateDirectories: true)
    let expected = Data("expected same length".utf8)
    let tampered = Data("tampered same length".utf8)
    XCTAssertEqual(expected.count, tampered.count)
    let descriptor = try tinyDescriptor(data: expected)
    let artifact = embedded.appendingPathComponent(descriptor.artifactFilename)
    try tampered.write(to: artifact)
    let buildReceipt = [
      "status=verified",
      "model_id=\(descriptor.modelID)",
      "source_revision=\(descriptor.sourceRevision)",
      "bytes=\(descriptor.expectedBytes)",
      "sha256=\(descriptor.expectedSHA256)",
      "source_commit=\(String(repeating: "a", count: 40))",
      "source_tree=\(String(repeating: "b", count: 40))",
      "package_resolved_sha256=\(BundledBuildReceiptProvenance.expectedPackageResolvedSHA256)"
    ].joined(separator: "\n") + "\n"
    try Data(buildReceipt.utf8).write(
      to: artifact.deletingPathExtension().appendingPathExtension("receipt")
    )
    let build = ModelAppBuildIdentity(
      bundleIdentifier: "com.example.GITimeline.hackathon",
      shortVersion: "1.0",
      buildNumber: "43"
    )
    let importer = ModelImporter(
      modelsDirectory: models,
      embeddedModelsDirectory: embedded,
      appBuildIdentity: build,
      trustBundledBuildReceipt: true
    )

    let verified = try importer.verifiedBundledModel(for: descriptor)

    XCTAssertEqual(verified.modelURL, artifact)
    XCTAssertEqual(verified.receipt.importedSHA256, descriptor.expectedSHA256)
    XCTAssertEqual(verified.receipt.appBuildIdentity, build)
  }

  func testBundledBuildReceiptProvenancePinsPackageResolvedHash() {
    let validFields = [
      "source_commit": String(repeating: "a", count: 40),
      "source_tree": String(repeating: "b", count: 40),
      "package_resolved_sha256": "90798d0becbb33b4f42aa0e8ea7bd7a8cc2a8c752fc94417b6fd6b2f7b844a8f",
    ]
    XCTAssertTrue(BundledBuildReceiptProvenance.matches(
      fields: validFields,
      requiresRecordedSourceCommit: true
    ))
    XCTAssertTrue(BundledBuildReceiptProvenance.matches(
      fields: validFields,
      requiresRecordedSourceCommit: true,
      expectedSourceCommit: String(repeating: "a", count: 40),
      expectedSourceTree: String(repeating: "b", count: 40)
    ))
    XCTAssertFalse(BundledBuildReceiptProvenance.matches(
      fields: validFields,
      requiresRecordedSourceCommit: true,
      expectedSourceCommit: String(repeating: "c", count: 40),
      expectedSourceTree: String(repeating: "b", count: 40)
    ))
    XCTAssertFalse(BundledBuildReceiptProvenance.matches(
      fields: validFields,
      requiresRecordedSourceCommit: true,
      expectedSourceCommit: String(repeating: "a", count: 40),
      expectedSourceTree: nil
    ))

    var wrongPackage = validFields
    wrongPackage["package_resolved_sha256"] = String(repeating: "0", count: 64)
    XCTAssertFalse(BundledBuildReceiptProvenance.matches(
      fields: wrongPackage,
      requiresRecordedSourceCommit: true
    ))

    var missingPackage = validFields
    missingPackage.removeValue(forKey: "package_resolved_sha256")
    XCTAssertFalse(BundledBuildReceiptProvenance.matches(
      fields: missingPackage,
      requiresRecordedSourceCommit: true
    ))
  }

  func testBundledBuildReceiptProvenanceRequiresLowercaseRecordedCommitAndTreeForAppStore() {
    let packageField = [
      "source_tree": String(repeating: "b", count: 40),
      "package_resolved_sha256": BundledBuildReceiptProvenance.expectedPackageResolvedSHA256,
    ]
    for invalidSourceCommit in [
      "unrecorded",
      String(repeating: "A", count: 40),
      String(repeating: "a", count: 39),
      String(repeating: "g", count: 40),
      "",
    ] {
      var fields = packageField
      fields["source_commit"] = invalidSourceCommit
      XCTAssertFalse(BundledBuildReceiptProvenance.matches(
        fields: fields,
        requiresRecordedSourceCommit: true
      ), "unexpected App Store acceptance: \(invalidSourceCommit)")
    }

    for invalidSourceTree in [
      "unrecorded",
      String(repeating: "B", count: 40),
      String(repeating: "b", count: 39),
      String(repeating: "g", count: 40),
      "",
    ] {
      var fields = packageField
      fields["source_commit"] = String(repeating: "a", count: 40)
      fields["source_tree"] = invalidSourceTree
      XCTAssertFalse(BundledBuildReceiptProvenance.matches(
        fields: fields,
        requiresRecordedSourceCommit: true
      ), "unexpected App Store tree acceptance: \(invalidSourceTree)")
    }
  }

  func testBundledBuildReceiptProvenanceAllowsUnrecordedOnlyForDevelopment() {
    let fields = [
      "source_commit": "unrecorded",
      "source_tree": "unrecorded",
      "package_resolved_sha256": BundledBuildReceiptProvenance.expectedPackageResolvedSHA256,
    ]
    XCTAssertTrue(BundledBuildReceiptProvenance.matches(
      fields: fields,
      requiresRecordedSourceCommit: false
    ))
    XCTAssertFalse(BundledBuildReceiptProvenance.matches(
      fields: fields,
      requiresRecordedSourceCommit: true
    ))
  }

  func testBundledBuildReceiptProvenanceUsesCompilationCondition() {
    #if APPSTORE_RELEASE
    XCTAssertTrue(BundledBuildReceiptProvenance.requiresRecordedSourceCommit)
    #else
    XCTAssertFalse(BundledBuildReceiptProvenance.requiresRecordedSourceCommit)
    #endif
  }

  func testBundledReceiptInvalidatesForNewAppBuild() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let embedded = root.appendingPathComponent("EmbeddedModels", isDirectory: true)
    let models = root.appendingPathComponent("Models", isDirectory: true)
    try FileManager.default.createDirectory(at: embedded, withIntermediateDirectories: true)
    let expected = Data("expected same length".utf8)
    let descriptor = try tinyDescriptor(data: expected)
    let artifact = embedded.appendingPathComponent(descriptor.artifactFilename)
    try expected.write(to: artifact)
    let buildOne = ModelAppBuildIdentity(bundleIdentifier: "test.bundle", shortVersion: "1", buildNumber: "1")
    let importerOne = ModelImporter(
      modelsDirectory: models,
      embeddedModelsDirectory: embedded,
      appBuildIdentity: buildOne
    )
    _ = try importerOne.verifiedBundledModel(for: descriptor)

    try Data("tampered same length".utf8).write(to: artifact)
    let buildTwo = ModelAppBuildIdentity(bundleIdentifier: "test.bundle", shortVersion: "1", buildNumber: "2")
    let importerTwo = ModelImporter(
      modelsDirectory: models,
      embeddedModelsDirectory: embedded,
      appBuildIdentity: buildTwo
    )

    XCTAssertThrowsError(try importerTwo.verifiedBundledModel(for: descriptor))
  }

  func testWrongHashPreservesSourceAndPromotesNothing() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let imports = root.appendingPathComponent("Import", isDirectory: true)
    let models = root.appendingPathComponent("Models", isDirectory: true)
    try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
    let expected = Data("expected same length".utf8)
    let actual = Data("tampered same length".utf8)
    XCTAssertEqual(expected.count, actual.count)
    let descriptor = try tinyDescriptor(data: expected)
    let source = imports.appendingPathComponent(descriptor.artifactFilename)
    try actual.write(to: source)
    let importer = ModelImporter(importDirectory: imports, modelsDirectory: models)

    XCTAssertThrowsError(try importer.importModel(descriptor))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: try importer.modelURL(for: descriptor).path))
    XCTAssertNil(try importer.receipt(for: descriptor))
  }

  func testExplicitVerificationRejectsSameSizeTamperingAndReceiptSizeDrift() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let imports = root.appendingPathComponent("Import", isDirectory: true)
    let models = root.appendingPathComponent("Models", isDirectory: true)
    try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
    let expected = Data("expected same length".utf8)
    let descriptor = try tinyDescriptor(data: expected)
    try expected.write(to: imports.appendingPathComponent(descriptor.artifactFilename))
    let importer = ModelImporter(importDirectory: imports, modelsDirectory: models)
    let imported = try importer.importModel(descriptor)
    try Data("tampered same length".utf8).write(to: imported.modelURL)

    XCTAssertThrowsError(try importer.verifyInstalledModel(descriptor))
    try Data("short".utf8).write(to: imported.modelURL)
    XCTAssertThrowsError(try importer.receipt(for: descriptor))
  }

  func testLabStateMachineRevokesIntegrityCapability() throws {
    var state = DeviceInferenceLabStateMachine()
    XCTAssertThrowsError(try state.beginInitialization())
    state.receiptFound()
    XCTAssertNoThrow(try state.beginInitialization())
    state.integrityFailure()
    XCTAssertFalse(state.hasDurableReceipt)
    XCTAssertEqual(state.state, .failed)
    XCTAssertEqual(state.failureStage, .hash)
    XCTAssertThrowsError(try state.beginInitialization())
  }

  func testDominantColorParserAcceptsOnlyExactTokens() throws {
    XCTAssertEqual(try DominantColorResult.parse("BROWN\n"), .brown)
    XCTAssertEqual(try DominantColorResult.parse("GREEN"), .green)
    XCTAssertEqual(try DominantColorResult.parse("OTHER"), .other)
    for rejected in ["brown", "BROWN stool", "{\"color\":\"BROWN\"}", "```BROWN```", ""] {
      XCTAssertThrowsError(try DominantColorResult.parse(rejected), "unexpected acceptance: \(rejected)")
    }
  }

  func testBundledSyntheticFixturesMatchRecordedHashesAndDimensions() throws {
    for fixture in SyntheticFixture.allCases {
      let url = try XCTUnwrap(Bundle.main.url(forResource: fixture.resourceName, withExtension: "png"))
      let data = try Data(contentsOf: url)
      XCTAssertEqual(hexSHA256(data), fixture.bundledSHA256)
      let image = try XCTUnwrap(UIImage(data: data))
      XCTAssertEqual(image.size, CGSize(width: 1024, height: 1024))
    }
  }

  func testRawImageRegressionFixtureSanitizationHashesArePinned() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    for fixture in AppStoreRawImageV1PreparationDiagnosticContract
      .RegressionFixture.allCases
    {
      let prepared = try imageStore.prepare(fixture.verifiedBundledData())
      XCTAssertEqual(prepared.reference.sha256, fixture.sanitizedSHA256)
      XCTAssertEqual(fixture.trackedSourceSHA256.count, 64)
      XCTAssertEqual(fixture.bundledSHA256.count, 64)
      XCTAssertEqual(fixture.sanitizedSHA256.count, 64)
    }
  }

  func testEvidenceSummaryDoesNotExposeFailureTextOrPaths() throws {
    let record = InferenceExperimentEvidence(
      experimentID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      timestamp: Date(timeIntervalSince1970: 0),
      hypothesis: "test",
      intendedVariable: "none",
      buildState: "test",
      deviceModel: "iPhone-test",
      iOSVersion: "test",
      xcodeVersion: "test",
      liteRTLMRevision: String(repeating: "a", count: 40),
      descriptor: .galleryGemma3nE2B,
      configuration: .deterministicBaseline,
      fixture: .brown,
      fixtureFilename: "synthetic-brown-clay.svg.png",
      fixtureDimensions: "1024x1024",
      bundledFixtureSHA256: SyntheticFixture.brown.bundledSHA256,
      sanitizedImageSHA256: String(repeating: "c", count: 64),
      syntheticProvenance: SyntheticFixture.brown.provenance,
      requestKind: .structuredObservation,
      requestForm: InferenceConfiguration.deterministicBaseline.imageMessageForm,
      engineInitializationSeconds: nil,
      engineWasReady: false,
      inferenceSeconds: nil,
      rawResponseFilename: nil,
      parserResult: "FAIL_STRICT",
      repairResult: "FAIL",
      structuredOutput: nil,
      dominantColor: nil,
      highestObservedMemoryBytes: nil,
      memoryMethod: "NOT_MEASURED",
      staleResultRejected: false,
      outcome: "FAIL",
      failureStage: .repair,
      failureMessage: "/Users/private/account/model/path",
      nextExperiment: "none"
    )
    XCTAssertFalse(record.sanitizedSummary.contains("/Users/"))
    XCTAssertFalse(record.sanitizedSummary.contains("private"))
    XCTAssertTrue(record.sanitizedSummary.contains("failure_stage=repair"))
  }

  func testManualSaveRemainsAvailableDuringColdModelPreparation() async throws {
    let harness = try makeHarness(modelReady: false, modelVerified: true, prepareDelayNanoseconds: 80_000_000)
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)
    harness.viewModel.note = "preserve during initialization"

    let preparation = Task { await harness.viewModel.prepareModel() }
    try await Task.sleep(for: .milliseconds(10))
    XCTAssertTrue(harness.viewModel.isPreparingModel)
    XCTAssertTrue(harness.viewModel.canSave)
    XCTAssertTrue(harness.viewModel.canReplaceOrClear)
    harness.viewModel.save()
    XCTAssertEqual(harness.store.records.first?.note, "preserve during initialization")
    await preparation.value
  }

  func testLateAutomaticPreparationFailurePreservesManualEdits() async throws {
    let harness = try makeHarness(
      modelReady: false,
      modelVerified: true,
      failPrepare: true,
      prepareDelayNanoseconds: 80_000_000,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())

    let preparation = Task { await harness.viewModel.prepareModel() }
    for _ in 0..<100 where !harness.viewModel.isPreparingModel {
      try await Task.sleep(for: .milliseconds(2))
    }
    XCTAssertTrue(harness.viewModel.isPreparingModel)

    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)
    harness.viewModel.note = "preserve edits after late preparation failure"
    let capturedAt = harness.viewModel.capturedAt

    await preparation.value

    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A late preparation failure must leave the active manual form intact.")
    }
    XCTAssertEqual(harness.viewModel.note, "preserve edits after late preparation failure")
    XCTAssertEqual(harness.viewModel.capturedAt, capturedAt)
    XCTAssertTrue(harness.viewModel.canSave)
  }

  func testAttachingPhotoPrefillsEditableRedAndBlackSuggestionsForOneFinalSave() async throws {
    let harness = try makeHarness(scripts: [.response(valid)], autoAnalysisEnabled: true)
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    let draft = try XCTUnwrap(harness.viewModel.currentDraftURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draft.path))
    XCTAssertNotNil(harness.viewModel.reviewedObservation)
    XCTAssertEqual(harness.viewModel.confirmedBristolType, 4)
    XCTAssertEqual(harness.viewModel.confirmedPhotoUsable, true)
    XCTAssertEqual(harness.viewModel.mixedForm, .no)
    XCTAssertEqual(harness.viewModel.apparentColor, "brown")
    XCTAssertEqual(harness.viewModel.suggestedRedMaterial, .no)
    XCTAssertEqual(harness.viewModel.suggestedBlackTarry, .no)
    XCTAssertEqual(harness.viewModel.redBlood, .no)
    XCTAssertEqual(harness.viewModel.blackTarry, .no)
    XCTAssertEqual(
      harness.viewModel.redSuggestionHint,
      "AI suggestion: No blood-like red material detected in this photo."
    )
    XCTAssertEqual(
      harness.viewModel.blackSuggestionHint,
      "AI suggestion: No black or tar-like appearance detected in this photo."
    )
    XCTAssertEqual(harness.viewModel.outstandingReviewCount, 0)
    XCTAssertTrue(harness.viewModel.canSave)
    guard case .reviewing(_, let review) = harness.viewModel.flowState else {
      return XCTFail("Automatic attach should advance into the review state.")
    }
    XCTAssertEqual(review.outstandingCount, 0)
    XCTAssertTrue(ReviewField.allCases.allSatisfy { review.state(for: $0) == .confirmed })
    harness.viewModel.redBlood = .yes
    XCTAssertTrue(harness.viewModel.canSave, "An edit remains part of the one whole-entry confirmation.")
  }

  func testShippingV1SuggestionPrefillsEditableAppearanceAnswersAndPreservesProvenance() async throws {
    let shippingResponse = """
    {"schema_version":"gi-photo-v1","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":5,"mixed_form":"no","apparent_color":"dark_brown","red_appearing_material":"yes","black_tarry_appearance":"not_sure"}
    """
    let harness = try makeHarness(
      scripts: [.response(shippingResponse)],
      descriptor: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.confirmedBristolType, 5)
    XCTAssertEqual(harness.viewModel.mixedForm, .no)
    XCTAssertEqual(harness.viewModel.apparentColor, "dark_brown")
    XCTAssertEqual(harness.viewModel.suggestedRedMaterial, .yes)
    XCTAssertEqual(harness.viewModel.suggestedBlackTarry, .unsure)
    XCTAssertEqual(harness.viewModel.redBlood, .yes)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)
    XCTAssertEqual(
      harness.viewModel.redSuggestionHint,
      "AI suggestion: Possible blood-like red material is visible."
    )
    XCTAssertEqual(
      harness.viewModel.blackSuggestionHint,
      "AI suggestion: Unable to determine whether a black or tar-like appearance is visible."
    )
    XCTAssertTrue(harness.viewModel.canSave)
    harness.viewModel.redBlood = .no
    XCTAssertTrue(harness.viewModel.canSave)
    harness.viewModel.save()

    let entry = try XCTUnwrap(harness.store.records.first)
    let original = try PhotoSuggestionV1Parser.parse(XCTUnwrap(entry.originalAIJSON))
    XCTAssertEqual(original.bristolType, 5)
    XCTAssertEqual(original.redAppearingMaterial, .yes)
    XCTAssertEqual(entry.redBlood, SymptomFlag.no.rawValue)
    XCTAssertEqual(entry.savedAnalysisSource, .gemmaRawImage)
    XCTAssertEqual(entry.analysisPipelineVersion, AnalysisPipelineVersion.appStoreRawImageV1)

    guard case .confirmedV1(let confirmation) = try StoredReviewedEntry.parse(
      XCTUnwrap(entry.reviewedJSON)
    ) else { return XCTFail("Expected one whole-entry confirmation envelope.") }
    XCTAssertEqual(confirmation.personConfirmedRed, .no)
    XCTAssertEqual(confirmation.personConfirmedBlackTarry, .unsure)
    XCTAssertEqual(confirmation.typedFieldProvenance[.redMaterial], .editedBeforeConfirmation)
    XCTAssertEqual(confirmation.typedFieldProvenance[.blackTarry], .acceptedUnchanged)

    let provenanceData = try XCTUnwrap(entry.modelProvenanceJSON?.data(using: .utf8))
    let provenance = try JSONDecoder().decode(InferenceProvenanceSnapshot.self, from: provenanceData)
    XCTAssertEqual(provenance.configuration, .appStoreRawImageV1)
    XCTAssertEqual(provenance.suggestionSchemaVersion, PhotoSuggestionV1.schemaVersion)
    XCTAssertEqual(provenance.parsePath, .direct)
    XCTAssertEqual(provenance.sanitizedImageSHA256, entry.imageSHA256)
  }

  func testShippingV1UnusableSuggestionDisplaysEditableNotSureAppearanceAnswers()
    async throws
  {
    let unusableResponse = """
    {"schema_version":"gi-photo-v1","image_usable":false,"retake_reason":"blurred","stool_presence":"uncertain","bristol_type":null,"mixed_form":"not_sure","apparent_color":null,"red_appearing_material":"not_sure","black_tarry_appearance":"not_sure"}
    """
    let harness = try makeHarness(
      scripts: [.response(unusableResponse)],
      descriptor: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.confirmedPhotoUsable, false)
    XCTAssertEqual(harness.viewModel.redBlood, .unsure)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)
    XCTAssertEqual(
      harness.viewModel.redSuggestionHint,
      "AI suggestion: Unable to determine whether blood-like red material is visible."
    )
    XCTAssertEqual(
      harness.viewModel.blackSuggestionHint,
      "AI suggestion: Unable to determine whether a black or tar-like appearance is visible."
    )
    XCTAssertTrue(harness.viewModel.canSave)
  }

  func testFullPrefillCandidateHasNoSeparateSubjectGate() async throws {
    let response = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":null,"red_appearing_material":"not_sure","black_tarry_appearance":"not_sure"}
    """
    let inference = MockInferenceService(scripts: [.response(response)])
    let harness = try makeHarness(
      inference: inference,
      descriptor: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV12SubjectGateTuning,
      autoAnalysisEnabled: false
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    if case .confirmingSubject = harness.viewModel.flowState {
      XCTFail("The candidate must not stop at a separate subject question.")
    }
    XCTAssertNil(harness.viewModel.subjectConfirmation)
    XCTAssertNotNil(harness.viewModel.currentDraftURL)
    let countsBeforeAnalysis = await inference.invocationCounts()
    XCTAssertEqual(countsBeforeAnalysis.analyze, 0)

    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    let countsAfterAnalysis = await inference.invocationCounts()
    XCTAssertEqual(countsAfterAnalysis.analyze, 1)
    XCTAssertEqual(harness.viewModel.confirmedStoolPresence, .nonStool)
    XCTAssertEqual(harness.viewModel.confirmedForm, "unable_to_assess")
    XCTAssertEqual(harness.viewModel.redBlood, .unsure)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)
    XCTAssertTrue(
      harness.viewModel.canSave,
      "The single save action must be able to adopt a complete conservative abstention."
    )
  }

  func testFullPrefillCandidateMakesOneCallPrefillsEveryFieldAndSavesEditedProvenance() async throws {
    let response = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":5,"form":"soft_blobs","mixed_form":"no","apparent_color":"dark_brown","red_appearing_material":"yes","black_tarry_appearance":"not_sure"}
    """
    let inference = MockInferenceService(scripts: [.response(response)])
    let harness = try makeHarness(
      inference: inference,
      descriptor: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV12SubjectGateTuning,
      autoAnalysisEnabled: false
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)

    let counts = await inference.invocationCounts()
    XCTAssertEqual(counts.analyze, 1)
    XCTAssertEqual(counts.repair, 0)
    XCTAssertNil(harness.viewModel.subjectConfirmation)
    XCTAssertEqual(harness.viewModel.confirmedPhotoUsable, true)
    XCTAssertEqual(harness.viewModel.confirmedStoolPresence, .stool)
    XCTAssertEqual(harness.viewModel.confirmedBristolType, 5)
    XCTAssertEqual(harness.viewModel.confirmedForm, "soft_blobs")
    XCTAssertEqual(harness.viewModel.mixedForm, .no)
    XCTAssertEqual(harness.viewModel.apparentColor, "dark_brown")
    XCTAssertEqual(harness.viewModel.suggestedRedMaterial, .yes)
    XCTAssertEqual(harness.viewModel.suggestedBlackTarry, .unsure)
    XCTAssertEqual(harness.viewModel.redBlood, .yes)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)
    XCTAssertEqual(
      harness.viewModel.redSuggestionHint,
      "AI suggestion: Possible blood-like red material is visible."
    )
    XCTAssertEqual(
      harness.viewModel.blackSuggestionHint,
      "AI suggestion: Unable to determine whether a black or tar-like appearance is visible."
    )
    XCTAssertTrue(harness.viewModel.canSave)

    harness.viewModel.updateConfirmedBristolType(6)
    harness.viewModel.leakageOrAccident = .no
    harness.viewModel.redBlood = .no
    XCTAssertTrue(harness.viewModel.canSave)
    harness.viewModel.save()
    let entry = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(
      entry.analysisPipelineVersion,
      AnalysisPipelineVersion.appStoreRawImageV12SubjectGateTuning
    )
    let confirmation = try XCTUnwrap(entry.confirmedEntrySnapshot)
    XCTAssertNil(confirmation.personConfirmedSubject)
    XCTAssertEqual(confirmation.personConfirmedStoolPresence, .stool)
    XCTAssertEqual(confirmation.personConfirmedBristolType, 6)
    XCTAssertEqual(confirmation.personConfirmedForm, "mushy")
    XCTAssertEqual(
      confirmation.typedFieldProvenance[.redMaterial],
      .editedBeforeConfirmation
    )
    XCTAssertEqual(
      confirmation.typedFieldProvenance[.blackTarry],
      .acceptedUnchanged
    )
    XCTAssertEqual(
      confirmation.typedFieldProvenance[.bristolType],
      .editedBeforeConfirmation
    )
    XCTAssertEqual(confirmation.typedFieldProvenance[.form], .editedBeforeConfirmation)
    let original = try FullPrefillPhotoSuggestionV1Parser.parse(
      XCTUnwrap(entry.originalAIJSON)
    )
    XCTAssertEqual(original.bristolType, 5)
    XCTAssertEqual(original.form, "soft_blobs")
    XCTAssertEqual(original.redAppearingMaterial, .yes)
    XCTAssertEqual(entry.originalObservation?.redAppearingMaterial, "apparent")
    XCTAssertEqual(entry.observation?.redAppearingMaterial, "not_observed")
    XCTAssertEqual(entry.observation?.blackTarryAppearance, "unable_to_assess")
  }

  func testFullPrefillCandidateUsesExactNegativeAndPositiveAppearanceCopy()
    async throws
  {
    let response = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":4,"form":"smooth_formed","mixed_form":"no","apparent_color":"brown","red_appearing_material":"no","black_tarry_appearance":"yes"}
    """
    let harness = try makeHarness(
      scripts: [.response(response)],
      descriptor: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV12SubjectGateTuning,
      autoAnalysisEnabled: false
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.redBlood, .no)
    XCTAssertEqual(harness.viewModel.blackTarry, .yes)
    XCTAssertEqual(
      harness.viewModel.redSuggestionHint,
      "AI suggestion: No blood-like red material detected in this photo."
    )
    XCTAssertEqual(
      harness.viewModel.blackSuggestionHint,
      "AI suggestion: Possible black or tar-like appearance is visible."
    )
  }

  func testFullPrefillDraftRelaunchPreservesCompleteEditableSuggestion() async throws {
    let response = """
    {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"stool","bristol_type":5,"form":"soft_blobs","mixed_form":"no","apparent_color":"dark_brown","red_appearing_material":"yes","black_tarry_appearance":"not_sure"}
    """
    let harness = try makeHarness(
      scripts: [.response(response)],
      descriptor: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV12SubjectGateTuning,
      autoAnalysisEnabled: false
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let initialSnapshot = try decoder.decode(
      DraftSnapshot.self,
      from: Data(contentsOf: snapshotURL)
    )
    XCTAssertEqual(initialSnapshot.version, DraftSnapshot.currentVersion)
    XCTAssertNil(initialSnapshot.subjectConfirmation)
    XCTAssertNil(initialSnapshot.confirmedStoolPresence)
    XCTAssertNil(initialSnapshot.confirmedForm)

    let beforeAnalysis = try restoredViewModel(
      from: harness,
      descriptor: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV12SubjectGateTuning
    )
    beforeAnalysis.restoreUnfinishedDraftIfAvailable()
    guard case .reading = beforeAnalysis.flowState else {
      return XCTFail("An unfinished candidate draft must reopen ready for its one analysis call.")
    }
    XCTAssertNil(beforeAnalysis.subjectConfirmation)

    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    XCTAssertEqual(harness.viewModel.redBlood, .yes)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)

    let afterAnalysis = try restoredViewModel(
      from: harness,
      descriptor: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV12SubjectGateTuning
    )
    afterAnalysis.restoreUnfinishedDraftIfAvailable()
    guard case .reviewing = afterAnalysis.flowState else {
      return XCTFail("A reviewed candidate draft must reopen in whole-entry review.")
    }
    XCTAssertNil(afterAnalysis.subjectConfirmation)
    XCTAssertEqual(afterAnalysis.confirmedStoolPresence, .stool)
    XCTAssertEqual(afterAnalysis.confirmedBristolType, 5)
    XCTAssertEqual(afterAnalysis.confirmedForm, "soft_blobs")
    XCTAssertEqual(afterAnalysis.apparentColor, "dark_brown")
    XCTAssertEqual(afterAnalysis.redBlood, .yes)
    XCTAssertEqual(afterAnalysis.blackTarry, .unsure)
    XCTAssertEqual(
      afterAnalysis.redSuggestionHint,
      "AI suggestion: Possible blood-like red material is visible."
    )
    XCTAssertEqual(
      afterAnalysis.blackSuggestionHint,
      "AI suggestion: Unable to determine whether a black or tar-like appearance is visible."
    )
    XCTAssertTrue(afterAnalysis.canSave)

    afterAnalysis.redBlood = .no
    XCTAssertTrue(afterAnalysis.canSave)
    afterAnalysis.save()
    let saved = try XCTUnwrap(harness.store.records.first)
    XCTAssertNil(saved.confirmedEntrySnapshot?.personConfirmedSubject)
    XCTAssertEqual(
      saved.confirmedEntrySnapshot?.personConfirmedStoolPresence,
      .stool
    )
    XCTAssertEqual(saved.confirmedEntrySnapshot?.personConfirmedForm, "soft_blobs")
    XCTAssertEqual(saved.redBlood, SymptomFlag.no.rawValue)
    XCTAssertEqual(saved.blackTarry, SymptomFlag.unsure.rawValue)
  }

  func testFullPrefillInvalidOutputNeverRepairsAndRetainsPhotoForManualEntry() async throws {
    let inference = MockInferenceService(scripts: [
      .malformed("not json"),
      .response(valid),
    ])
    let harness = try makeHarness(
      inference: inference,
      descriptor: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV12SubjectGateTuning,
      autoAnalysisEnabled: false
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    let draft = try XCTUnwrap(harness.viewModel.currentDraftURL)
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)

    let counts = await inference.invocationCounts()
    XCTAssertEqual(counts.analyze, 1)
    XCTAssertEqual(counts.repair, 0)
    XCTAssertEqual(harness.viewModel.currentDraftURL, draft)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draft.path))
    XCTAssertNil(harness.viewModel.reviewedObservation)
    guard case .manual(let draftID) = harness.viewModel.flowState else {
      return XCTFail("Candidate parse failure must retain the photo in manual entry.")
    }
    XCTAssertNotNil(draftID)
  }

  func testFrozenExtremeQualityChecksRejectOnlyOrderedExtremeControls() async throws {
    typealias Contract = PhotoTechnicalQualityAssessment
    XCTAssertEqual(Contract.contractVersion, "gi-v1-extreme-photo-quality-v1")
    XCTAssertEqual(Contract.minimumPixelDimension, 256)
    XCTAssertEqual(Contract.maximumAspectRatio, 3.5)
    XCTAssertEqual(Contract.maximumDarkMeanLuminance, 0.08)
    XCTAssertEqual(Contract.maximumDarkP90Luminance, 0.12)
    XCTAssertEqual(Contract.minimumGlareMeanLuminance, 0.84)
    XCTAssertEqual(Contract.minimumGlareP10Luminance, 0.82)
    XCTAssertEqual(Contract.minimumGlareP90Luminance, 0.96)
    XCTAssertEqual(Contract.minimumSharpLaplacianVariance, 0.0004)
    XCTAssertEqual(Contract.minimumBlurContrastRange, 0.15)

    func metrics(
      width: Int = 256,
      height: Int = 256,
      aspect: Double = 1,
      mean: Double = 0.5,
      p05: Double = 0.1,
      p10: Double = 0.2,
      p90: Double = 0.8,
      p95: Double = 0.9,
      laplacian: Double = 0.01
    ) -> PhotoTechnicalQualityMetrics {
      PhotoTechnicalQualityMetrics(
        pixelWidth: width,
        pixelHeight: height,
        aspectRatio: aspect,
        meanLuminance: mean,
        p05Luminance: p05,
        p10Luminance: p10,
        p90Luminance: p90,
        p95Luminance: p95,
        laplacianVariance: laplacian
      )
    }

    // Exact inclusive/exclusive edges.
    XCTAssertNil(Contract.retakeReason(for: metrics()))
    XCTAssertEqual(Contract.retakeReason(for: metrics(width: 255)), .other)
    XCTAssertEqual(Contract.retakeReason(for: metrics(height: 255)), .other)
    XCTAssertNil(Contract.retakeReason(for: metrics(aspect: 3.5)))
    XCTAssertEqual(
      Contract.retakeReason(for: metrics(aspect: 3.5.nextUp)), .other
    )
    XCTAssertEqual(
      Contract.retakeReason(for: metrics(mean: 0.08, p90: 0.12)), .tooDark
    )
    XCTAssertNil(Contract.retakeReason(for: metrics(mean: 0.08.nextUp, p90: 0.12)))
    XCTAssertNil(Contract.retakeReason(for: metrics(mean: 0.08, p90: 0.12.nextUp)))
    XCTAssertEqual(
      Contract.retakeReason(for: metrics(mean: 0.84, p10: 0.82, p90: 0.96)),
      .glare
    )
    XCTAssertEqual(
      Contract.retakeReason(for: metrics(
        mean: 0.84.nextDown, p10: 0.82, p90: 0.96
      )),
      .glare
    )
    XCTAssertEqual(
      Contract.retakeReason(for: metrics(
        mean: 0.84, p10: 0.82.nextDown, p90: 0.96
      )),
      .glare
    )
    XCTAssertNil(Contract.retakeReason(for: metrics(mean: 0.84, p10: 0.82, p90: 0.96.nextDown)))
    XCTAssertEqual(
      Contract.retakeReason(for: metrics(
        mean: 0.4, p05: 0.3, p10: 0.35, p90: 0.42,
        p95: 0.45, laplacian: 0.0004.nextDown
      )),
      .blurred
    )
    XCTAssertNil(Contract.retakeReason(for: metrics(
      mean: 0.4, p05: 0.3, p10: 0.35, p90: 0.42,
      p95: 0.45, laplacian: 0.0004
    )))
    XCTAssertNil(Contract.retakeReason(for: metrics(
      mean: 0.4, p05: 0.3, p10: 0.35, p90: 0.42,
      p95: 0.45.nextDown, laplacian: 0.0004.nextDown
    )))

    // Ordered first failure: size, framing, darkness, glare, then blur.
    let lowDarkBlur = metrics(
      width: 255, aspect: 4, mean: 0.08, p05: 0,
      p10: 0.05, p90: 0.12, p95: 0.2, laplacian: 0
    )
    XCTAssertEqual(Contract.retakeReason(for: lowDarkBlur), .other)
    var ordered = metrics(
      aspect: 4, mean: 0.08, p05: 0, p10: 0.05,
      p90: 0.12, p95: 0.2, laplacian: 0
    )
    XCTAssertEqual(Contract.retakeReason(for: ordered), .other)
    ordered = metrics(
      mean: 0.08, p05: 0, p10: 0.05,
      p90: 0.12, p95: 0.2, laplacian: 0
    )
    XCTAssertEqual(Contract.retakeReason(for: ordered), .tooDark)
    ordered = metrics(
      mean: 0.84, p05: 0.1, p10: 0.82,
      p90: 0.96, p95: 0.98, laplacian: 0
    )
    XCTAssertEqual(Contract.retakeReason(for: ordered), .glare)

    let rejectedMetrics: [(PhotoTechnicalQualityMetrics, PhotoRetakeReason)] = [
      (metrics(width: 255), .other),
      (metrics(aspect: 3.5.nextUp), .other),
      (metrics(mean: 0.08, p90: 0.12), .tooDark),
      (metrics(mean: 0.84, p10: 0.82, p90: 0.96), .glare),
      (metrics(
        mean: 0.4, p05: 0.3, p10: 0.35, p90: 0.42,
        p95: 0.45, laplacian: 0.0004.nextDown
      ), .blurred),
    ]
    let inference = MockInferenceService(
      scripts: Array(repeating: .response(valid), count: rejectedMetrics.count + 1)
    )
    for (qualityMetrics, expectedReason) in rejectedMetrics {
      let output = try await CandidatePhotoQualityGate.resolve(
        assessment: PhotoTechnicalQualityAssessment(
          metrics: qualityMetrics,
          retakeReason: Contract.retakeReason(for: qualityMetrics)
        )
      ) {
        try await inference.analyze(
          draftURL: URL(fileURLWithPath: "/candidate-quality-gate.jpg"),
          expectedSHA256: String(repeating: "a", count: 64)
        )
      }
      XCTAssertEqual(
        try FullPrefillPhotoSuggestionV1Parser.parse(output),
        FullPrefillPhotoSuggestionV1.technicalAbstention(
          reason: expectedReason
        )
      )
      let counts = await inference.invocationCounts()
      XCTAssertEqual(counts.analyze, 0, "A rejected quality branch must not call Gemma.")
      XCTAssertEqual(counts.repair, 0)
    }

    let passMetrics = metrics()
    let passOutput = try await CandidatePhotoQualityGate.resolve(
      assessment: PhotoTechnicalQualityAssessment(
        metrics: passMetrics,
        retakeReason: Contract.retakeReason(for: passMetrics)
      )
    ) {
      try await inference.analyze(
        draftURL: URL(fileURLWithPath: "/candidate-quality-gate.jpg"),
        expectedSHA256: String(repeating: "a", count: 64)
      )
    }
    XCTAssertEqual(passOutput, valid)
    let passCounts = await inference.invocationCounts()
    XCTAssertEqual(passCounts.analyze, 1)
    XCTAssertEqual(passCounts.repair, 0)

    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    let dark = try imageStore.prepare(imageData(color: .black))
    let glare = try imageStore.prepare(imageData(color: .white))
    let ordinary = try imageStore.prepare(imageData(color: .brown))
    let darkData = try Data(contentsOf: dark.url)
    let glareData = try Data(contentsOf: glare.url)
    let ordinaryData = try Data(contentsOf: ordinary.url)
    XCTAssertEqual(
      try PhotoTechnicalQualityAssessment.evaluate(darkData).retakeReason,
      .tooDark
    )
    XCTAssertEqual(
      try PhotoTechnicalQualityAssessment.evaluate(glareData).retakeReason,
      .glare
    )
    XCTAssertTrue(
      try PhotoTechnicalQualityAssessment.evaluate(ordinaryData).shouldCallGemma
    )
  }

  func testHybridPhotoQualityPreflightUsesUnpaddedLandscapeAndPortraitContent()
    async throws
  {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    XCTAssertEqual(
      PhotoQualityRecommendation.contractVersion,
      "gi-hybrid-photo-quality-preflight-v1"
    )

    let hardCases: [(QualitySyntheticKind, PhotoQualityIssue, PhotoRetakeReason)] = [
      (.severeBlur, .severeBlur, .blurred),
      (.tooDark, .tooDark, .tooDark),
      (.overexposedGlare, .overexposedGlare, .glare),
      (.nearBlank, .nearBlank, .other),
      (.veryLowContrast, .veryLowContrast, .obstructed),
    ]
    let orientations: [(name: String, size: CGSize)] = [
      ("landscape", CGSize(width: 640, height: 480)),
      ("portrait", CGSize(width: 480, height: 640)),
    ]
    for orientation in orientations {
      for (kind, expectedIssue, expectedReason) in hardCases {
        let raw = qualitySyntheticJPEG(kind, size: orientation.size)
        let prepared = try imageStore.prepare(raw)
        let recommendation = try XCTUnwrap(
          imageStore.photoQualityRecommendation(for: prepared),
          "missing deterministic recommendation for \(orientation.name) \(kind)"
        )
        XCTAssertEqual(
          recommendation.severity, .hard,
          "\(orientation.name) \(kind)"
        )
        XCTAssertEqual(
          recommendation.issue, expectedIssue,
          "\(orientation.name) \(kind)"
        )
        XCTAssertEqual(
          recommendation.retakeReason, expectedReason,
          "\(orientation.name) \(kind)"
        )
        XCTAssertFalse(
          recommendation.shouldRunQwen,
          "\(orientation.name) \(kind)"
        )

        let engine = MockPhotoSuggestionEngine(mode: .success("unused"))
        let harness = try makeHarness(
          photoSuggestionEngine: engine,
          modelReady: false,
          descriptor: nil,
          autoAnalysisEnabled: true
        )
        try harness.viewModel.prepareImageData(raw)
        let counts = await engine.counts()
        XCTAssertEqual(
          counts,
          .init(prepare: 0, suggest: 0, cancel: 0),
          "hard \(orientation.name) \(kind) must stop before engine work"
        )
        harness.cleanup()
      }

      let good = try imageStore.prepare(
        qualitySyntheticJPEG(.good, size: orientation.size)
      )
      XCTAssertNil(
        try imageStore.photoQualityRecommendation(for: good),
        "usable \(orientation.name) 4:3 content must remain eligible"
      )
    }
  }

  func testHardHybridQualityStopSkipsEngineAndManualContinuationKeepsDraftPhotoAndPDF()
    async throws
  {
    let raw = """
      {"apparent_color":"brown","black_appearance":"no","black_tarry_appearance":"no","bristol_type":4,"form":"smooth_formed","image_usable":true,"mixed_form":"no","red_appearing_material":"no","retake_reason":null,"schema_version":"gi-photo-full-prefill-v2","stool_presence":"stool"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }
    harness.viewModel.note = "Keep this unfinished draft note."

    try harness.viewModel.prepareImageData(qualitySyntheticJPEG(.tooDark))

    let retainedDraft = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let retainedBytes = try Data(contentsOf: retainedDraft)
    XCTAssertTrue(FileManager.default.fileExists(atPath: retainedDraft.path))
    XCTAssertEqual(harness.viewModel.note, "Keep this unfinished draft note.")
    XCTAssertEqual(harness.viewModel.confirmedPhotoUsable, false)
    XCTAssertEqual(harness.viewModel.confirmedRetakeReason, .tooDark)
    XCTAssertEqual(harness.viewModel.photoQualityRecommendation?.issue, .tooDark)
    XCTAssertEqual(
      harness.viewModel.photoQualityRecommendation?.message,
      "This photo may be too dark to provide useful suggestions. Taking another photo in more even light may improve the results."
    )
    guard case .failed(let draftID, _) = harness.viewModel.flowState else {
      return XCTFail("A hard quality result must use the retained-photo retake surface.")
    }
    XCTAssertNotNil(draftID)
    let hardStopCounts = await engine.counts()
    XCTAssertEqual(
      hardStopCounts,
      .init(prepare: 0, suggest: 0, cancel: 0),
      "Hard deterministic quality must stop before engine allocation or generation."
    )

    await harness.viewModel.loadPhotoDataForTesting { Data("not an image".utf8) }
    XCTAssertEqual(harness.viewModel.currentDraftURL, retainedDraft)
    XCTAssertEqual(try Data(contentsOf: retainedDraft), retainedBytes)
    XCTAssertEqual(harness.viewModel.note, "Keep this unfinished draft note.")

    harness.viewModel.keepLowQualityPhotoAndContinueManually()
    guard case .manual(let manualDraftID) = harness.viewModel.flowState else {
      return XCTFail("The secondary action must enter the existing manual form.")
    }
    XCTAssertNotNil(manualDraftID)
    XCTAssertEqual(harness.viewModel.currentDraftURL, retainedDraft)
    XCTAssertTrue(FileManager.default.fileExists(atPath: retainedDraft.path))
    XCTAssertNil(harness.viewModel.photoQualityRecommendation)
    XCTAssertTrue(harness.viewModel.usesProviderNeutralManualPhotoReview)
    XCTAssertTrue(
      harness.viewModel.statusMessage?.contains("photo will remain with the saved entry and PDF") == true
    )
    XCTAssertEqual(harness.viewModel.confirmedStoolPresence, .uncertain)
    XCTAssertNil(harness.viewModel.confirmedBristolType)
    XCTAssertEqual(harness.viewModel.confirmedForm, "unable_to_assess")
    XCTAssertEqual(harness.viewModel.confirmedApparentColor, "unable_to_assess")
    XCTAssertEqual(harness.viewModel.confirmedPhotoUsable, false)
    XCTAssertEqual(harness.viewModel.confirmedRetakeReason, .tooDark)
    XCTAssertEqual(harness.viewModel.mixedForm, .unsure)
    XCTAssertEqual(harness.viewModel.redBlood, .unsure)
    XCTAssertEqual(harness.viewModel.blackAppearance, .unsure)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)

    // The complete retained-photo presentation is a user choice, not an
    // inference-engine capability. It must reconstruct even when the next
    // process has no provider-neutral engine instance.
    let restored = NewEntryViewModel(
      imageStore: harness.imageStore,
      store: harness.store,
      inference: MockInferenceService(scripts: []),
      descriptor: nil,
      modelVerified: false,
      engineReady: false,
      configuration: .deterministicBaseline,
      autoAnalysisEnabled: false
    )
    restored.restoreUnfinishedDraftIfAvailable()
    guard case .manual = restored.flowState else {
      return XCTFail("The kept low-quality photo must relaunch in manual review.")
    }
    XCTAssertNil(restored.photoQualityRecommendation)
    XCTAssertTrue(restored.usesProviderNeutralManualPhotoReview)
    XCTAssertEqual(restored.confirmedPhotoUsable, false)
    XCTAssertEqual(restored.confirmedRetakeReason, .tooDark)

    // The retained-photo manual tuple is complete and person-editable. These
    // are the values that must be saved; the deterministic prefill is not an
    // immutable model answer.
    harness.viewModel.updateConfirmedPhotoUsable(true)
    harness.viewModel.updateStoolPresence(.stool)
    harness.viewModel.updateConfirmedBristolType(5)
    harness.viewModel.updateMixedForm(.no)
    harness.viewModel.updateApparentColor("yellow")
    harness.viewModel.redBlood = .yes
    harness.viewModel.blackAppearance = .no
    harness.viewModel.blackTarry = .yes

    harness.viewModel.painScore = 0
    harness.viewModel.urgency = UrgencyLevel.none
    XCTAssertTrue(harness.viewModel.canSave)
    harness.viewModel.save()

    let record = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(record.savedAnalysisSource, .manual)
    XCTAssertEqual(record.confirmedPhotoUsable, true)
    let savedConfirmation = try XCTUnwrap(record.confirmedEntrySnapshot)
    XCTAssertNil(savedConfirmation.personConfirmedRetakeReason)
    XCTAssertEqual(savedConfirmation.personConfirmedStoolPresence, .stool)
    XCTAssertEqual(record.confirmedBristolType, 5)
    XCTAssertEqual(savedConfirmation.personConfirmedForm, "soft_blobs")
    XCTAssertEqual(savedConfirmation.personConfirmedApparentColor, "yellow")
    XCTAssertEqual(record.mixedFormAnswer, .no)
    XCTAssertEqual(record.redBlood.flatMap(SymptomFlag.init(rawValue:)), .yes)
    XCTAssertEqual(record.blackAppearanceAnswer, .no)
    XCTAssertEqual(record.blackTarry.flatMap(SymptomFlag.init(rawValue:)), .yes)
    XCTAssertEqual(record.note, "Keep this unfinished draft note.")
    let imageFilename = try XCTUnwrap(record.imageFilename)
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: harness.root.appendingPathComponent("Images/\(imageFilename)").path
    ))

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let day = calendar.startOfDay(for: record.capturedAt)
    let export = try JournalExportSnapshotFactory.make(
      entries: [record],
      completions: [],
      treatmentEvents: [],
      range: .init(from: day, through: day),
      scope: .allEntries,
      generatedAt: day.addingTimeInterval(12 * 3_600),
      calendar: calendar,
      timeZone: calendar.timeZone
    )
    let pdf = try JournalPDFRenderer().render(
      snapshot: export,
      photoDirectory: harness.root.appendingPathComponent("Images")
    )
    let document = try XCTUnwrap(PDFDocument(data: pdf))
    let text = (0..<document.pageCount)
      .compactMap { document.page(at: $0)?.string }
      .joined(separator: "\n")
    XCTAssertTrue(text.contains("Photo included"))
    XCTAssertTrue(text.contains("Manual value — retake recommendation: No retake recommended"))
    XCTAssertTrue(text.contains("Manual value — entry subject: Bowel movement"))
    XCTAssertTrue(text.contains("Manual value — Bristol type: Type 5"))
    XCTAssertTrue(text.contains("Manual value — form: Soft Blobs"))
    XCTAssertTrue(text.contains("Manual value — apparent color: Yellow"))
    XCTAssertTrue(text.contains("Manual value — possible red/blood-like appearance: Yes"))
    XCTAssertTrue(text.contains("Manual value — possible unusually black appearance: No"))
    XCTAssertTrue(text.contains("Manual value — possible tar-like appearance: Yes"))
  }

  func testBorderlineQualityRecommendsRetakeButContinuesAutomaticAnalysis()
    async throws
  {
    let raw = """
      {"apparent_color":"brown","black_appearance":"no","black_tarry_appearance":"no","bristol_type":4,"form":"smooth_formed","image_usable":true,"mixed_form":"no","red_appearing_material":"no","retake_reason":null,"schema_version":"gi-photo-full-prefill-v2","stool_presence":"stool"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(
      qualitySyntheticJPEG(.borderlineDark)
    )
    await waitForAutomaticAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.photoQualityRecommendation?.severity, .borderline)
    XCTAssertEqual(harness.viewModel.photoQualityRecommendation?.issue, .tooDark)
    let borderlineCounts = await engine.counts()
    XCTAssertEqual(borderlineCounts, .init(prepare: 1, suggest: 1, cancel: 0))
    guard case .reviewing = harness.viewModel.flowState else {
      return XCTFail("Borderline quality must remain eligible for automatic analysis.")
    }
    harness.viewModel.keepBorderlinePhoto()
    XCTAssertNil(harness.viewModel.photoQualityRecommendation)
    XCTAssertNotNil(harness.viewModel.currentDraftURL)
  }

  func testCameraAndPhotosPickerFailureRestoreExactHardQualityPresentation()
    async throws
  {
    for seam in ["camera", "photos_picker"] {
      let engine = MockPhotoSuggestionEngine(mode: .success("unused"))
      let harness = try makeHarness(
        photoSuggestionEngine: engine,
        modelReady: false,
        descriptor: nil,
        autoAnalysisEnabled: true
      )
      defer { harness.cleanup() }
      harness.viewModel.note = "hard rollback note \(seam)"
      harness.viewModel.painScore = 3
      harness.viewModel.urgency = .severe
      try harness.viewModel.prepareImageData(
        qualitySyntheticJPEG(.tooDark, size: CGSize(width: 640, height: 480))
      )

      let oldURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
      let oldBytes = try Data(contentsOf: oldURL)
      let oldRecommendation = try XCTUnwrap(
        harness.viewModel.photoQualityRecommendation
      )
      let oldFlow = harness.viewModel.flowState
      let oldBusy = harness.viewModel.isBusy
      guard case .failed(let oldDraftID, let oldMessage) = harness.viewModel.flowState else {
        return XCTFail("hard precondition must expose the retake card")
      }

      if seam == "camera" {
        XCTAssertThrowsError(
          try harness.viewModel.prepareImageData(Data("invalid camera image".utf8))
        )
      } else {
        await harness.viewModel.loadPhotoDataForTesting {
          Data("invalid picker image".utf8)
        }
      }

      XCTAssertEqual(harness.viewModel.currentDraftURL, oldURL, seam)
      XCTAssertEqual(try Data(contentsOf: oldURL), oldBytes, seam)
      XCTAssertEqual(
        harness.viewModel.note, "hard rollback note \(seam)", seam
      )
      XCTAssertEqual(harness.viewModel.painScore, 3, seam)
      XCTAssertEqual(harness.viewModel.urgency, .severe, seam)
      XCTAssertEqual(
        harness.viewModel.photoQualityRecommendation,
        oldRecommendation,
        seam
      )
      XCTAssertEqual(harness.viewModel.flowState, oldFlow, seam)
      XCTAssertEqual(harness.viewModel.isBusy, oldBusy, seam)
      XCTAssertEqual(harness.viewModel.confirmedPhotoUsable, false, seam)
      XCTAssertEqual(harness.viewModel.confirmedRetakeReason, .tooDark, seam)
      guard case .failed(let restoredDraftID, let restoredMessage) =
        harness.viewModel.flowState
      else { return XCTFail("\(seam) did not restore the hard retake flow") }
      XCTAssertEqual(restoredDraftID, oldDraftID, seam)
      XCTAssertEqual(restoredMessage, oldMessage, seam)
      let counts = await engine.counts()
      XCTAssertEqual(
        counts,
        .init(prepare: 0, suggest: 0, cancel: 0),
        seam
      )
    }
  }

  func testCameraAndPhotosPickerFailureRestoreExactBorderlineReviewPresentation()
    async throws
  {
    let raw = """
      {"apparent_color":"brown","black_appearance":"no","black_tarry_appearance":"no","bristol_type":4,"form":"smooth_formed","image_usable":true,"mixed_form":"no","red_appearing_material":"no","retake_reason":null,"schema_version":"gi-photo-full-prefill-v2","stool_presence":"stool"}
      """
    for seam in ["camera", "photos_picker"] {
      let engine = MockPhotoSuggestionEngine(mode: .success(raw))
      let harness = try makeHarness(
        photoSuggestionEngine: engine,
        modelReady: false,
        descriptor: nil,
        autoAnalysisEnabled: true
      )
      defer { harness.cleanup() }
      try harness.viewModel.prepareImageData(
        qualitySyntheticJPEG(
          .borderlineDark,
          size: CGSize(width: 480, height: 640)
        )
      )
      await waitForAutomaticAnalysis(harness.viewModel)
      harness.viewModel.note = "borderline rollback note \(seam)"
      harness.viewModel.updateApparentColor("yellow")
      harness.viewModel.redBlood = .yes

      let oldURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
      let oldBytes = try Data(contentsOf: oldURL)
      let oldRecommendation = try XCTUnwrap(
        harness.viewModel.photoQualityRecommendation
      )
      let oldReview = try XCTUnwrap(harness.viewModel.reviewSession)
      let oldFlow = harness.viewModel.flowState
      let oldBusy = harness.viewModel.isBusy
      guard case .reviewing(let oldDraftID, let oldFlowReview) = oldFlow
      else { return XCTFail("borderline precondition must be reviewing") }
      XCTAssertEqual(oldFlowReview, oldReview)

      if seam == "camera" {
        XCTAssertThrowsError(
          try harness.viewModel.prepareImageData(Data("invalid camera image".utf8))
        )
      } else {
        await harness.viewModel.loadPhotoDataForTesting {
          Data("invalid picker image".utf8)
        }
      }

      XCTAssertEqual(harness.viewModel.currentDraftURL, oldURL, seam)
      XCTAssertEqual(try Data(contentsOf: oldURL), oldBytes, seam)
      XCTAssertEqual(
        harness.viewModel.note, "borderline rollback note \(seam)", seam
      )
      XCTAssertEqual(harness.viewModel.apparentColor, "yellow", seam)
      XCTAssertEqual(harness.viewModel.redBlood, .yes, seam)
      XCTAssertEqual(
        harness.viewModel.photoQualityRecommendation,
        oldRecommendation,
        seam
      )
      XCTAssertEqual(harness.viewModel.reviewSession, oldReview, seam)
      XCTAssertEqual(harness.viewModel.flowState, oldFlow, seam)
      XCTAssertEqual(harness.viewModel.isBusy, oldBusy, seam)
      guard case .reviewing(let restoredDraftID, let restoredFlowReview) =
        harness.viewModel.flowState
      else { return XCTFail("\(seam) did not restore the borderline review flow") }
      XCTAssertEqual(restoredDraftID, oldDraftID, seam)
      XCTAssertEqual(restoredFlowReview, oldFlowReview, seam)
      let counts = await engine.counts()
      XCTAssertEqual(
        counts,
        .init(prepare: 1, suggest: 1, cancel: 0),
        seam
      )
    }
  }

  func testHardAndBorderlineReplacementSnapshotFailureRestoreExactPresentationOnce()
    async throws
  {
    let raw = """
      {"apparent_color":"brown","black_appearance":"no","black_tarry_appearance":"no","bristol_type":4,"form":"smooth_formed","image_usable":true,"mixed_form":"no","red_appearing_material":"no","retake_reason":null,"schema_version":"gi-photo-full-prefill-v2","stool_presence":"stool"}
      """
    for kind in [QualitySyntheticKind.tooDark, .borderlineDark] {
      let fault = SnapshotSaveFault()
      let engine = MockPhotoSuggestionEngine(mode: .success(raw))
      let harness = try makeHarness(
        photoSuggestionEngine: engine,
        modelReady: false,
        descriptor: nil,
        autoAnalysisEnabled: true,
        snapshotSaveFailureInjector: { try fault.run() }
      )
      defer { harness.cleanup() }

      try harness.viewModel.prepareImageData(qualitySyntheticJPEG(kind))
      if kind == .borderlineDark {
        await waitForAutomaticAnalysis(harness.viewModel)
      }
      let oldURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
      let oldBytes = try Data(contentsOf: oldURL)
      let oldFlow = harness.viewModel.flowState
      let oldReview = harness.viewModel.reviewSession
      let oldRecommendation = try XCTUnwrap(
        harness.viewModel.photoQualityRecommendation
      )
      let oldStatus = harness.viewModel.statusMessage
      let snapshotURL = harness.root.appendingPathComponent(
        "Drafts/active-draft.v1.json"
      )
      let snapshotBytes = try Data(contentsOf: snapshotURL)
      let engineCounts = await engine.counts()
      let callsBeforeReplacement = fault.invocationCount

      fault.shouldFail = true
      XCTAssertThrowsError(
        try harness.viewModel.prepareImageData(qualitySyntheticJPEG(.good)),
        kind.description
      )

      XCTAssertEqual(
        fault.invocationCount,
        callsBeforeReplacement + 1,
        kind.description
      )
      XCTAssertEqual(harness.viewModel.flowState, oldFlow, kind.description)
      XCTAssertEqual(
        harness.viewModel.reviewSession,
        oldReview,
        kind.description
      )
      XCTAssertEqual(
        harness.viewModel.photoQualityRecommendation,
        oldRecommendation,
        kind.description
      )
      XCTAssertEqual(
        harness.viewModel.statusMessage,
        oldStatus,
        kind.description
      )
      XCTAssertEqual(harness.viewModel.currentDraftURL, oldURL, kind.description)
      XCTAssertEqual(try Data(contentsOf: oldURL), oldBytes, kind.description)
      XCTAssertEqual(
        try Data(contentsOf: snapshotURL),
        snapshotBytes,
        kind.description
      )
      let finalEngineCounts = await engine.counts()
      XCTAssertEqual(finalEngineCounts, engineCounts, kind.description)
    }
  }

  func testHardAndBorderlineQualityRecommendationsPersistAndReconstructAcrossRelaunch()
    async throws
  {
    let raw = """
      {"apparent_color":"brown","black_appearance":"no","black_tarry_appearance":"no","bristol_type":4,"form":"smooth_formed","image_usable":true,"mixed_form":"no","red_appearing_material":"no","retake_reason":null,"schema_version":"gi-photo-full-prefill-v2","stool_presence":"stool"}
      """
    for kind in [QualitySyntheticKind.tooDark, .borderlineDark] {
      let engine = MockPhotoSuggestionEngine(mode: .success(raw))
      let harness = try makeHarness(
        photoSuggestionEngine: engine,
        modelReady: false,
        descriptor: nil,
        autoAnalysisEnabled: true
      )
      defer { harness.cleanup() }

      try harness.viewModel.prepareImageData(qualitySyntheticJPEG(kind))
      if kind == .borderlineDark {
        await waitForAutomaticAnalysis(harness.viewModel)
      }
      let expected = try XCTUnwrap(
        harness.viewModel.photoQualityRecommendation
      )
      let snapshotURL = harness.root.appendingPathComponent(
        "Drafts/active-draft.v1.json"
      )
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let snapshot = try decoder.decode(
        DraftSnapshot.self,
        from: Data(contentsOf: snapshotURL)
      )
      XCTAssertEqual(
        snapshot.photoQualityRecommendation,
        expected,
        kind.description
      )
      let countsBeforeRestore = await engine.counts()

      let restored = NewEntryViewModel(
        imageStore: harness.imageStore,
        store: harness.store,
        inference: MockInferenceService(scripts: []),
        photoSuggestionEngine: engine,
        descriptor: nil,
        modelVerified: false,
        engineReady: false,
        configuration: .deterministicBaseline,
        autoAnalysisEnabled: true
      )
      restored.restoreUnfinishedDraftIfAvailable()

      XCTAssertEqual(
        restored.photoQualityRecommendation,
        expected,
        kind.description
      )
      XCTAssertEqual(
        restored.currentDraftURL,
        harness.viewModel.currentDraftURL,
        kind.description
      )
      if expected.severity == .hard {
        guard case .failed(_, let message) = restored.flowState else {
          return XCTFail("hard recommendation must reconstruct its retake card")
        }
        XCTAssertEqual(message, expected.message)
        XCTAssertEqual(restored.statusMessage, expected.message)
      } else {
        guard case .reviewing = restored.flowState else {
          return XCTFail("borderline recommendation must remain on review")
        }
      }
      let countsAfterRestore = await engine.counts()
      XCTAssertEqual(countsAfterRestore, countsBeforeRestore, kind.description)
    }
  }

  /// Test-only resources are injected into the built XCTest bundle from the
  /// external evidence directory. No synthetic image is a public app resource.
  func testFrozenExternalSyntheticJPEGsPassNativeValidationAndTechnicalRejectsAreZeroCall() async throws {
    let resourceRoot = try XCTUnwrap(Bundle(for: GITimelineTests.self).resourceURL)
      .appendingPathComponent("SyntheticVisionV1Fixtures", isDirectory: true)
    guard FileManager.default.fileExists(atPath: resourceRoot.path) else {
      throw XCTSkip("External frozen synthetic fixtures were not injected into this test bundle.")
    }
    let manifestData = try Data(
      contentsOf: resourceRoot.appendingPathComponent("manifest.json")
    )
    let manifest = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
    )
    let fixtures = try XCTUnwrap(manifest["fixtures"] as? [[String: Any]])
    XCTAssertEqual(fixtures.count, 26)

    let expectedTechnicalReasons: [String: PhotoRetakeReason] = [
      "pxp-022": .tooDark,
      "pxp-023": .glare,
      "pxp-024": .blurred,
      "pxp-025": .other,
    ]
    var validatedJPEGCount = 0
    for fixture in fixtures {
      let opaqueID = try XCTUnwrap(fixture["opaque_id"] as? String)
      guard let relativePath = fixture["sanitized_relative_path"] as? String else {
        XCTAssertEqual(opaqueID, "pxp-026")
        continue
      }
      let expectedSHA256 = try XCTUnwrap(
        fixture["sanitized_file_sha256"] as? String
      )
      let data = try Data(contentsOf: resourceRoot.appendingPathComponent(relativePath))
      let actualSHA256 = SHA256.hash(data: data).map {
        String(format: "%02x", $0)
      }.joined()
      XCTAssertEqual(actualSHA256, expectedSHA256, opaqueID)
      XCTAssertNoThrow(
        try ImageStore.validateSanitizedJournalJPEG(
          data,
          expectedSHA256: expectedSHA256
        ),
        opaqueID
      )
      validatedJPEGCount += 1

      guard let expectedReason = expectedTechnicalReasons[opaqueID] else {
        continue
      }
      let assessment = try PhotoTechnicalQualityAssessment.evaluate(data)
      XCTAssertEqual(assessment.retakeReason, expectedReason, opaqueID)
      var modelCallCount = 0
      let output = try await CandidatePhotoQualityGate.resolve(data: data) {
        modelCallCount += 1
        return "UNEXPECTED_MODEL_CALL"
      }
      XCTAssertEqual(modelCallCount, 0, opaqueID)
      XCTAssertEqual(
        try FullPrefillPhotoSuggestionV1Parser.parse(output),
        .technicalAbstention(reason: expectedReason),
        opaqueID
      )
    }
    XCTAssertEqual(validatedJPEGCount, 25)

    let corrupt = try XCTUnwrap(
      fixtures.first { ($0["opaque_id"] as? String) == "pxp-026" }
    )
    let corruptRelativePath = try XCTUnwrap(
      corrupt["source_relative_path"] as? String
    )
    let corruptData = try Data(
      contentsOf: resourceRoot.appendingPathComponent(corruptRelativePath)
    )
    var corruptModelCallCount = 0
    do {
      _ = try await CandidatePhotoQualityGate.resolve(data: corruptData) {
        corruptModelCallCount += 1
        return "UNEXPECTED_MODEL_CALL"
      }
      XCTFail("Corrupt bytes must fail before the model closure.")
    } catch {
      XCTAssertEqual(error as? GITimelineError, .invalidImage)
    }
    XCTAssertEqual(corruptModelCallCount, 0)
  }

  func testSyntheticVisionExactDataContractBindsPlanPromptsSchemasBudgetsAndBounds() throws {
    let resourceRoot = try XCTUnwrap(Bundle(for: GITimelineTests.self).resourceURL)
      .appendingPathComponent("SyntheticVisionV1Fixtures", isDirectory: true)
    guard FileManager.default.fileExists(atPath: resourceRoot.path) else {
      throw XCTSkip("External frozen synthetic fixtures were not injected into this test bundle.")
    }
    func data(_ relativePath: String) throws -> Data {
      try Data(contentsOf: resourceRoot.appendingPathComponent(relativePath))
    }
    let planData = try data("runtime-plan.json")
    let plan = try SyntheticVisionV1RuntimePlan.decodeAndValidate(planData)
    XCTAssertEqual(plan.assetIndex.count, 25)
    XCTAssertEqual(plan.transport.initialProbeFixtureID, "pxp-002")
    XCTAssertEqual(plan.transport.sequence, ["pxp-002", "pxp-003", "pxp-002"])
    XCTAssertEqual(plan.primitive.sequence.count, 32)
    XCTAssertEqual(plan.primitive.coldRestartBoundariesAfterPositions, [12])
    XCTAssertEqual(plan.fullPrefill.sequence, ["pxp-011", "pxp-012", "pxp-013", "pxp-014"])
    XCTAssertEqual(plan.technicalQuality.sequence, ["pxp-022", "pxp-023", "pxp-024", "pxp-025", "pxp-026"])

    let transport = try data(plan.transport.promptRelativePath)
    let engineeringPrompt = try data(plan.primitive.promptRelativePath)
    let engineeringSchema = try data(try XCTUnwrap(plan.primitive.schemaRelativePath))
    let fullPrefillPrompt = try data(plan.fullPrefill.promptRelativePath)
    let fullPrefillSchema = try data(try XCTUnwrap(plan.fullPrefill.schemaRelativePath))
    let configurations: [(InferenceConfiguration, String)] = [
      (.appStoreRawImageFullPrefill280,
        InferenceConfiguration.internalAppStoreRawImageV1Candidate280LaunchArgument),
      (.appStoreRawImageV12SubjectGateTuning,
        InferenceConfiguration.internalAppStoreRawImageV1CandidateLaunchArgument),
      (.appStoreRawImageFullPrefill70,
        InferenceConfiguration.internalAppStoreRawImageV1Candidate70LaunchArgument),
    ]
    for (configuration, selector) in configurations {
      XCTAssertTrue(SyntheticVisionExactDataProbeContract.accepts(
        configuration: configuration,
        promptData: transport,
        schemaData: nil
      ))
      XCTAssertTrue(SyntheticVisionExactDataProbeContract.accepts(
        configuration: configuration,
        promptData: engineeringPrompt,
        schemaData: engineeringSchema
      ))
      XCTAssertTrue(SyntheticVisionExactDataProbeContract.accepts(
        configuration: configuration,
        promptData: fullPrefillPrompt,
        schemaData: fullPrefillSchema
      ))
      let launch = [
        SyntheticVisionV1Contract.Mode.transportInitial.launchArgument,
        selector,
      ]
      XCTAssertEqual(
        SyntheticVisionV1Contract.requested(in: launch)?.configuration,
        configuration
      )
      XCTAssertTrue(AppEvaluationLaunchPolicy.isolatesJournal(launch))
    }
    XCTAssertEqual(
      SyntheticVisionExactDataProbeContract.requestKind(
        promptData: transport,
        schemaData: nil
      ),
      .transport
    )
    XCTAssertEqual(
      SyntheticVisionExactDataProbeContract.requestKind(
        promptData: engineeringPrompt,
        schemaData: engineeringSchema
      ),
      .engineeringPrimitive
    )
    XCTAssertEqual(
      SyntheticVisionExactDataProbeContract.requestKind(
        promptData: fullPrefillPrompt,
        schemaData: fullPrefillSchema
      ),
      .fullPrefill
    )
    XCTAssertEqual(
      SyntheticVisionExactDataProbeContract.generationPolicy(
        promptData: transport,
        schemaData: nil
      ),
      .probe
    )
    XCTAssertEqual(
      SyntheticVisionExactDataProbeContract.generationPolicy(
        promptData: engineeringPrompt,
        schemaData: engineeringSchema
      ),
      .syntheticPrimitive
    )
    XCTAssertEqual(
      SyntheticVisionExactDataProbeContract.generationPolicy(
        promptData: fullPrefillPrompt,
        schemaData: fullPrefillSchema
      ),
      .rawPhoto
    )
    XCTAssertNil(try SyntheticVisionExactDataProbeContract.makeResponseFormat(
      schemaData: nil
    ))
    XCTAssertNotNil(try SyntheticVisionExactDataProbeContract.makeResponseFormat(
      schemaData: engineeringSchema
    ))
    XCTAssertNotNil(try SyntheticVisionExactDataProbeContract.makeResponseFormat(
      schemaData: fullPrefillSchema
    ))
    XCTAssertFalse(SyntheticVisionExactDataProbeContract.accepts(
      configuration: .appStoreRawImageV1,
      promptData: transport,
      schemaData: nil
    ))
    XCTAssertFalse(SyntheticVisionExactDataProbeContract.accepts(
      configuration: .appStoreRawImageFullPrefill280,
      promptData: Data("wrong".utf8),
      schemaData: engineeringSchema
    ))
    XCTAssertNil(SyntheticVisionV1Contract.requested(in: [
      SyntheticVisionV1Contract.Mode.transportInitial.launchArgument,
      SyntheticVisionV1Contract.Mode.transportSequence.launchArgument,
      InferenceConfiguration.internalAppStoreRawImageV1Candidate280LaunchArgument,
    ]))
    XCTAssertNil(SyntheticVisionV1Contract.requested(in: [
      SyntheticVisionV1Contract.Mode.cancellation.launchArgument,
      InferenceConfiguration.internalAppStoreRawImageV1CandidateLaunchArgument,
    ]))
  }

  func testSyntheticVisionProcessEpochAndReceiptIntegrityAreStableAndLossless() throws {
    let processID = SyntheticVisionExactDataProbeContract.processID
    let processStart = SyntheticVisionExactDataProbeContract
      .processStartUnixNanoseconds
    let processEpoch = SyntheticVisionExactDataProbeContract.processEpochID
    XCTAssertGreaterThan(processID, 0)
    XCTAssertGreaterThan(processStart, 0)
    XCTAssertTrue(ImageStore.isValidSHA256(processEpoch))
    XCTAssertEqual(processID, SyntheticVisionExactDataProbeContract.processID)
    XCTAssertEqual(
      processStart,
      SyntheticVisionExactDataProbeContract.processStartUnixNanoseconds
    )
    XCTAssertEqual(processEpoch, SyntheticVisionExactDataProbeContract.processEpochID)

    let raw = Data("{\"image_present\":\"yes\"}".utf8)
    func makeReceipt(
      rawSHA256: String,
      terminal: SyntheticVisionExactDataProbeTerminal = .success,
      terminalErrorCode: String? = nil,
      modelCallStarted: Bool = true,
      nativeCompletionObserved: Bool = true
    ) -> SyntheticVisionExactDataProbeReceipt {
      SyntheticVisionExactDataProbeReceipt(
        contractVersion: SyntheticVisionExactDataProbeContract.version,
        requestID: UUID().uuidString.lowercased(),
        conversationID: UUID().uuidString.lowercased(),
        processID: processID,
        processEpochID: processEpoch,
        processStartUnixNanoseconds: processStart,
        engineSessionEpochID: UUID().uuidString.lowercased(),
        modelArtifactSHA256:
          SyntheticVisionExactDataProbeContract.modelArtifactSHA256,
        cacheMode: "fresh_isolated_diagnostic_cache",
        cacheDisposition: "created",
        cacheProfileSHA256: String(repeating: "b", count: 64),
        cachePathSHA256: String(repeating: "c", count: 64),
        configurationID: InferenceConfiguration
          .appStoreRawImageFullPrefill280.id,
        visualTokenBudget: 280,
        requestKind: .engineeringPrimitive,
        promptSHA256:
          SyntheticVisionExactDataProbeContract.engineeringPromptSHA256,
        responseSchemaSHA256:
          SyntheticVisionExactDataProbeContract.engineeringSchemaSHA256,
        promptUTF8RoundTripVerified: true,
        schemaUTF8RoundTripVerified: true,
        expectedImageSHA256: String(repeating: "a", count: 64),
        loadedImageSHA256: String(repeating: "a", count: 64),
        inferenceBoundImageSHA256: String(repeating: "a", count: 64),
        inferenceBoundImageByteCount: 4_096,
        imageMessageForm:
          "Message(contents:[Content.imageData(exactSanitizedData),Content.text(frozenPrompt)])",
        generationDeadlineMilliseconds: 30_000,
        generationMaximumOutputTokens: 128,
        generationMaximumUTF8Bytes: 2_048,
        responseFormatEnabled: true,
        automaticToolCalling: false,
        conversationCreated: true,
        modelCallStarted: modelCallStarted,
        modelCallCount: modelCallStarted ? 1 : 0,
        repairCallCount: 0,
        nativeCallCompletionObserved: nativeCompletionObserved,
        nativeCompletionKind: nativeCompletionObserved
          ? "synchronous_send_return" : "model_call_not_started",
        terminal: terminal,
        terminalErrorCode: terminalErrorCode,
        rawCaptureNote: nil,
        nativeErrorType: nil,
        nativeErrorDomain: nil,
        nativeErrorCode: nil,
        rawResponseUTF8Base64: raw.base64EncodedString(),
        rawResponseUTF8SHA256: rawSHA256,
        rawResponseUTF8ByteCount: raw.count
      )
    }
    let valid = makeReceipt(
      rawSHA256: SyntheticVisionExactDataProbeContract.sha256Hex(raw)
    )
    XCTAssertTrue(valid.hasValidInternalIntegrity)
    XCTAssertEqual(valid.rawResponseUTF8, raw)
    let encoded = try JSONEncoder().encode(valid)
    let decoded = try JSONDecoder().decode(
      SyntheticVisionExactDataProbeReceipt.self,
      from: encoded
    )
    XCTAssertEqual(decoded, valid)
    XCTAssertTrue(decoded.hasValidInternalIntegrity)
    XCTAssertFalse(makeReceipt(
      rawSHA256: String(repeating: "0", count: 64)
    ).hasValidInternalIntegrity)
  }

  func testWholeEntryPrefillAllowsEditsAndKeepsPersonEnteredContext() async throws {
    let harness = try makeHarness(scripts: [.response(valid)], autoAnalysisEnabled: true)
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.suggestedRedMaterial, .no)
    XCTAssertEqual(harness.viewModel.suggestedBlackTarry, .no)
    XCTAssertEqual(harness.viewModel.redBlood, .no)
    XCTAssertEqual(harness.viewModel.blackTarry, .no)
    XCTAssertTrue(harness.viewModel.canSave)

    harness.viewModel.updateMixedForm(.yes)
    XCTAssertEqual(harness.viewModel.reviewState(for: .mixedForm), .edited)
    harness.viewModel.redBlood = .yes
    harness.viewModel.blackTarry = .no
    harness.viewModel.dizziness = .unsure
    harness.viewModel.note = "User-entered context"
    harness.viewModel.urgency = .moderate
    harness.viewModel.painScore = 2
    harness.viewModel.strainingOrIncomplete = .no

    XCTAssertEqual(harness.viewModel.outstandingReviewCount, 0)
    XCTAssertTrue(harness.viewModel.canSave)
    XCTAssertEqual(harness.viewModel.redBlood, .yes)
    XCTAssertEqual(harness.viewModel.blackTarry, .no)
    XCTAssertEqual(harness.viewModel.dizziness, .unsure)
    XCTAssertNil(harness.viewModel.severePain)
    XCTAssertEqual(harness.viewModel.note, "User-entered context")

    harness.viewModel.save()
    let saved = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(saved.provenance, EntryProvenance.ai_edited.rawValue)
    XCTAssertEqual(saved.redBlood, SymptomFlag.yes.rawValue)
    XCTAssertEqual(saved.dizziness, SymptomFlag.unsure.rawValue)
  }

  func testAutomaticFailureAndCancelKeepDraftUsableWithoutAllowingStaleResult() async throws {
    let failure = try makeHarness(
      scripts: [.malformed("not json"), .malformed("still not json")],
      autoAnalysisEnabled: true
    )
    defer { failure.cleanup() }
    try failure.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(failure.viewModel)
    let retainedDraft = try XCTUnwrap(failure.viewModel.currentDraftURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: retainedDraft.path))
    XCTAssertNil(failure.viewModel.reviewedObservation)
    guard case .manual(let manualDraftID) = failure.viewModel.flowState else {
      return XCTFail("A failed automatic read must enter real manual review with the draft retained.")
    }
    XCTAssertNotNil(manualDraftID)
    XCTAssertEqual(failure.viewModel.analysisSource, .manual)
    XCTAssertFalse(failure.viewModel.canSave)
    completeRequiredReview(failure.viewModel)
    XCTAssertTrue(failure.viewModel.canSave)
    failure.viewModel.save()
    let manualRecord = try XCTUnwrap(failure.store.records.first)
    XCTAssertNil(manualRecord.originalAIJSON)
    let manualConfirmation = try XCTUnwrap(manualRecord.confirmedEntrySnapshot)
    XCTAssertTrue(manualConfirmation.typedFieldProvenance.values.allSatisfy {
      $0 == .manualNoSuggestion
    })
    XCTAssertEqual(manualRecord.savedAnalysisSource, .manual)
    XCTAssertNil(failure.viewModel.currentDraftURL)
    XCTAssertFalse(FileManager.default.fileExists(atPath: retainedDraft.path))

    let cancellation = try makeHarness(scripts: [.slow(valid, nanoseconds: 300_000_000)], autoAnalysisEnabled: true)
    defer { cancellation.cleanup() }
    // This test exercises cancellation after reading starts, so use the
    // shared deterministic quality-eligible fixture rather than a uniform
    // rectangle that the production preflight correctly stops early.
    try cancellation.viewModel.prepareImageData(imageData())
    let cancelledDraft = try XCTUnwrap(cancellation.viewModel.currentDraftURL)
    await waitForReading(cancellation.viewModel)
    cancellation.viewModel.cancelReading()
    try await Task.sleep(for: .milliseconds(400))
    XCTAssertFalse(cancellation.viewModel.isBusy)
    XCTAssertNil(cancellation.viewModel.reviewedObservation, "A cancelled response must never replace the retained draft.")
    XCTAssertEqual(cancellation.viewModel.currentDraftURL, cancelledDraft)
    XCTAssertTrue(FileManager.default.fileExists(atPath: cancelledDraft.path))
    guard case .manual(let failedDraftID) = cancellation.viewModel.flowState else {
      return XCTFail("Cancellation should retain the photo and enter manual review.")
    }
    XCTAssertNotNil(failedDraftID)
  }

  func testExclusiveInferenceGateRejectsOverlapAndStaleRelease() throws {
    var gate = ExclusiveInferenceGate()
    let structured = try gate.beginStructured(draftPath: "/synthetic/draft-a.jpg")

    XCTAssertThrowsError(try gate.beginProbe())
    gate.finish(UUID())
    XCTAssertThrowsError(try gate.beginStructured(draftPath: "/synthetic/draft-b.jpg"))
    XCTAssertTrue(gate.ownsStructured(token: structured, draftPath: "/synthetic/draft-a.jpg"))

    gate.finish(structured)
    let probe = try gate.beginProbe()
    XCTAssertFalse(gate.ownsStructured(token: probe, draftPath: "/synthetic/draft-a.jpg"))
    gate.finish(probe)
    XCTAssertNoThrow(try gate.beginStructured(draftPath: "/synthetic/draft-b.jpg"))
  }

  func testBoundedStreamingGenerationCollectsChunksWithoutCancellingNativeWork() async throws {
    let probe = StreamingCancellationProbe()
    let stream = AsyncThrowingStream<String, Error> { continuation in
      continuation.yield("{")
      continuation.yield("}")
      continuation.finish()
    }

    let output = try await BoundedStreamingGeneration.collect(
      stream,
      policy: BoundedGenerationPolicy(deadline: .seconds(1), maximumUTF8Bytes: 2),
      cancelNativeGeneration: { probe.cancel() },
      onFirstElement: { probe.recordFirstElement() },
      text: { $0 }
    )

    XCTAssertEqual(output, "{}")
    XCTAssertEqual(probe.cancellationCount, 0)
    XCTAssertEqual(probe.firstElementCount, 1)
  }

  func testBoundedStreamingGenerationCancelsNativeWorkAtUTF8ByteLimit() async {
    let probe = StreamingCancellationProbe()
    let stream = AsyncThrowingStream<String, Error> { continuation in
      continuation.yield("ééé")
    }

    do {
      _ = try await BoundedStreamingGeneration.collect(
        stream,
        policy: BoundedGenerationPolicy(deadline: .seconds(1), maximumUTF8Bytes: 5),
        cancelNativeGeneration: { probe.cancel() },
        text: { $0 }
      )
      XCTFail("A six-byte response must not fit in a five-byte policy.")
    } catch {
      XCTAssertEqual(
        error as? BoundedGenerationError,
        .outputTooLarge(maximumUTF8Bytes: 5)
      )
    }
    XCTAssertEqual(probe.cancellationCount, 1)
  }

  func testBoundedStreamingGenerationDeadlineCancelsNativeWork() async {
    let probe = StreamingCancellationProbe()

    do {
      _ = try await BoundedStreamingGeneration.collect(
        probe.stream(),
        policy: BoundedGenerationPolicy(deadline: .milliseconds(20), maximumUTF8Bytes: 128),
        cancelNativeGeneration: { probe.cancel() },
        text: { $0 }
      )
      XCTFail("An unfinished stream must hit its deadline.")
    } catch {
      XCTAssertEqual(error as? BoundedGenerationError, .timedOut)
    }
    XCTAssertEqual(probe.cancellationCount, 1)
  }

  func testBoundedStreamingGenerationDeadlineCannotReturnSuccessWhenNativeStreamFinishesCleanly() async {
    let probe = StreamingCancellationProbe()

    do {
      _ = try await BoundedStreamingGeneration.collect(
        probe.stream(),
        policy: BoundedGenerationPolicy(deadline: .milliseconds(20), maximumUTF8Bytes: 128),
        cancelNativeGeneration: { probe.finishNormallyAfterCancellation() },
        text: { $0 }
      )
      XCTFail("A deadline that wins the terminal race must not return partial output as success.")
    } catch {
      XCTAssertEqual(error as? BoundedGenerationError, .timedOut)
    }
    XCTAssertEqual(probe.cancellationCount, 1)
  }

  func testBoundedStreamingGenerationTaskCancellationCancelsNativeWork() async {
    let probe = StreamingCancellationProbe()
    let task = Task {
      try await BoundedStreamingGeneration.collect(
        probe.stream(),
        policy: BoundedGenerationPolicy(deadline: .seconds(5), maximumUTF8Bytes: 128),
        cancelNativeGeneration: { probe.cancel() },
        text: { $0 }
      )
    }
    await Task.yield()
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("A cancelled task must not return model output.")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertEqual(probe.cancellationCount, 1)
  }

  func testBoundedStreamingGenerationTaskCancellationCannotReturnSuccessWhenNativeStreamFinishesCleanly() async {
    let probe = StreamingCancellationProbe()
    let task = Task {
      try await BoundedStreamingGeneration.collect(
        probe.stream(),
        policy: BoundedGenerationPolicy(deadline: .seconds(5), maximumUTF8Bytes: 128),
        cancelNativeGeneration: { probe.finishNormallyAfterCancellation() },
        text: { $0 }
      )
    }
    await Task.yield()
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Task cancellation that wins the terminal race must not return partial output as success.")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertEqual(probe.cancellationCount, 1)
  }

  #if !APPSTORE_RELEASE_TESTING
  func testSynchronousDiagnosticWaitsForNativeCancelAndPreservesFirstCause() async {
    let probe = SynchronousDiagnosticCancellationProbe()
    let cancellation = SynchronousDiagnosticCancellation(
      cancelNativeGeneration: { probe.cancelNativeGeneration() },
      onCancelRequested: { probe.recordTelemetry() }
    )

    let cancelTask = Task.detached {
      cancellation.cancel(.deadline)
    }
    let didStartCancellation = await probe.waitUntilCancelStarted()
    XCTAssertTrue(didStartCancellation)

    let finishTask = Task.detached {
      let cause = cancellation.finishAndReadCause()
      probe.recordFinished(cause)
      return cause
    }
    try? await Task.sleep(for: .milliseconds(40))
    XCTAssertFalse(
      probe.didFinish,
      "The inference gate must not reopen while Conversation.cancel() is still in flight."
    )

    cancellation.cancel(.taskCancellation)
    XCTAssertEqual(probe.cancelInvocationCount, 1, "The first cancellation cause must win.")
    probe.releaseNativeCancellation()
    _ = await cancelTask.value
    let finishedCause = await finishTask.value
    XCTAssertEqual(finishedCause, .deadline)
    XCTAssertTrue(probe.didFinish)
    XCTAssertTrue(probe.cancelReturnedBeforeFinish)
    XCTAssertTrue(probe.cancelReturnedBeforeTelemetry)

    let completedProbe = SynchronousDiagnosticCancellationProbe()
    let alreadyCompleted = SynchronousDiagnosticCancellation(
      cancelNativeGeneration: { completedProbe.recordImmediateCancel() }
    )
    XCTAssertNil(alreadyCompleted.finishAndReadCause())
    alreadyCompleted.cancel(.deadline)
    XCTAssertEqual(completedProbe.cancelInvocationCount, 0)
  }
  #endif

  func testTerminalRepairOutputIsCanonicalAndRejectsTrailingText() throws {
    let fenced = "```json\n\(valid)\n```"
    let canonical = try StructuredInferenceOutput.canonicalFinalJSON(fenced)

    XCTAssertEqual(
      try ObservationParser.parse(canonical),
      try ObservationParser.parse(valid)
    )
    XCTAssertFalse(canonical.contains("```"))
    XCTAssertThrowsError(
      try StructuredInferenceOutput.canonicalFinalJSON(valid + "\nAdditional explanation")
    )
  }

  func testRuntimeCoordinatorGateMakesLeaseAndTransitionMutuallyExclusive() throws {
    var gate = RuntimeCoordinatorGate()
    let transient = try gate.acquire(descriptorID: "e2b", purpose: .transient)

    XCTAssertTrue(gate.hasLease)
    XCTAssertThrowsError(try gate.beginTransition())
    gate.release(UUID())
    XCTAssertTrue(gate.hasLease, "a stale token must not release the active operation")
    gate.release(transient)

    try gate.beginTransition()
    XCTAssertTrue(gate.transitionInProgress)
    XCTAssertThrowsError(try gate.acquire(descriptorID: "e4b", purpose: .transient))
    gate.endTransition()

    let structured = try gate.acquire(
      descriptorID: "e2b",
      purpose: .structured(draftPath: "/synthetic/draft.jpg")
    )
    XCTAssertEqual(
      gate.structuredToken(descriptorID: "e2b", draftPath: "/synthetic/draft.jpg"),
      structured
    )
    XCTAssertNil(gate.structuredToken(descriptorID: "e2b", draftPath: "/synthetic/other.jpg"))
    gate.release(structured)
    XCTAssertFalse(gate.hasLease)
  }

  func testLabRunSignatureAllowsAtMostOneExperimentalVariable() {
    let baseline = LabRunSignature(
      descriptorID: "e2b",
      configurationID: "baseline-v1",
      fixtureID: "brown",
      probeKind: .dominantColor
    )
    XCTAssertNotNil(baseline.intendedVariable(comparedTo: nil))
    XCTAssertTrue(baseline.intendedVariable(comparedTo: baseline)?.contains("Repeatability") == true)

    let oneChange = LabRunSignature(
      descriptorID: "e4b",
      configurationID: "baseline-v1",
      fixtureID: "brown",
      probeKind: .dominantColor
    )
    XCTAssertTrue(oneChange.intendedVariable(comparedTo: baseline)?.contains("candidate descriptor") == true)

    let twoChanges = LabRunSignature(
      descriptorID: "e4b",
      configurationID: "baseline-v1",
      fixtureID: "green",
      probeKind: .dominantColor
    )
    XCTAssertNil(twoChanges.intendedVariable(comparedTo: baseline))
  }

  func testMocksCompile() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    let prepared = try imageStore.prepare(imageData())
    let inference = MockInferenceService(scripts: [.response("{}")])
    _ = try await inference.analyze(
      draftURL: prepared.url,
      expectedSHA256: prepared.reference.sha256
    )
    let store = try FailingEntryStore(); store.failNextSave = true
    XCTAssertTrue(store.failNextSave)
  }

  func testPhysicalLocalPixelBridgeKeepsExactModelTextPathExplicit() {
    let bridge = InferenceConfiguration.physicalCPUVisualBridge
    XCTAssertTrue(bridge.usesLocalPixelBridge)
    XCTAssertEqual(bridge.engineBackend, "cpu")
    XCTAssertEqual(bridge.visionBackend, "disabled")
    XCTAssertEqual(bridge.maxNumTokens, 2_048)
    XCTAssertTrue(bridge.imageMessageForm.contains("raw image is not sent"))
  }

  func testLocalPixelBridgeFindsBrownElongatedShapeAndBristolSuggestion() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let data = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480), format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
      UIColor(red: 0.48, green: 0.25, blue: 0.10, alpha: 1).setFill()
      context.cgContext.fillEllipse(in: CGRect(x: 100, y: 180, width: 440, height: 120))
    }.jpegData(compressionQuality: 0.9)!
    let prepared = try imageStore.prepare(data)

    let facts = try LocalPixelFeatureExtractor.extract(from: prepared.url)

    XCTAssertEqual(facts.dominantColorHint, "brown")
    XCTAssertEqual(facts.apparentColorHint, "brown")
    XCTAssertEqual(facts.bristolTypeHint, 4)
    XCTAssertEqual(facts.formHint, "smooth_formed")
    XCTAssertEqual(facts.shapeSuggestionConfidence, "low_hackathon_approximation")
    XCTAssertEqual(facts.coarseShapeGrid.count, 12)
    XCTAssertTrue(facts.coarseShapeGrid.contains { $0.contains("B") })
  }

  func testUnfinishedDraftSnapshotRestoresManualFieldsAndUsesOnlyRelativePhotoMetadata() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    harness.viewModel.enterManualMode()
    harness.viewModel.updateConfirmedBristolType(4)
    harness.viewModel.updateMixedForm(.no)
    harness.viewModel.updateConfirmedPhotoUsable(true)
    harness.viewModel.painScore = 3
    harness.viewModel.urgency = .moderate
    harness.viewModel.strainingOrIncomplete = .no
    harness.viewModel.redBlood = .no
    harness.viewModel.blackTarry = .no
    harness.viewModel.dizziness = .unsure
    harness.viewModel.severePain = .no
    harness.viewModel.note = "resume this locally"

    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    let rawSnapshot = try Data(contentsOf: snapshotURL)
    let snapshotText = try XCTUnwrap(String(data: rawSnapshot, encoding: .utf8))
    XCTAssertFalse(snapshotText.contains(draftURL.path), "Snapshot must never retain an absolute photo path.")
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(DraftSnapshot.self, from: rawSnapshot)
    XCTAssertEqual(snapshot.version, DraftSnapshot.currentVersion)
    let snapshotDraft = try XCTUnwrap(snapshot.draft)
    XCTAssertEqual(snapshotDraft.filename, draftURL.lastPathComponent)
    XCTAssertEqual(snapshot.note, "resume this locally")

    let restored = try restoredViewModel(from: harness)
    restored.restoreUnfinishedDraftIfAvailable()
    XCTAssertEqual(restored.currentDraftURL, draftURL)
    XCTAssertEqual(restored.confirmedBristolType, 4)
    XCTAssertEqual(restored.mixedForm, .no)
    XCTAssertEqual(restored.confirmedPhotoUsable, true)
    XCTAssertEqual(restored.painScore, 3)
    XCTAssertEqual(restored.urgency, .moderate)
    XCTAssertEqual(restored.dizziness, .unsure)
    XCTAssertEqual(restored.note, "resume this locally")
    guard case .manual(let restoredID) = restored.flowState else { return XCTFail("An interrupted draft must reopen in manual review.") }
    XCTAssertEqual(restoredID, snapshotDraft.id)
  }

  func testUnfinishedNoPhotoManualDraftRestoresAfterColdRelaunchAndClearRemovesIt() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")

    harness.viewModel.enterManualMode()
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path), "A pristine manual form must not become a durable draft.")
    harness.viewModel.updateConfirmedBristolType(6)
    harness.viewModel.updateMixedForm(.yes)
    harness.viewModel.painScore = 4
    harness.viewModel.urgency = .severe
    harness.viewModel.leakageOrAccident = .no
    harness.viewModel.redBlood = .no
    harness.viewModel.blackTarry = .unsure
    harness.viewModel.dizziness = .no
    harness.viewModel.severePain = .no
    harness.viewModel.note = "no-photo manual entry survives relaunch"

    let snapshotData = try Data(contentsOf: snapshotURL)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(DraftSnapshot.self, from: snapshotData)
    XCTAssertNil(snapshot.draft)
    let snapshotText = try XCTUnwrap(String(data: snapshotData, encoding: .utf8))
    XCTAssertFalse(snapshotText.contains("filename"), "No-photo snapshots must not contain a photo reference or bytes.")

    let restored = try restoredViewModel(from: harness)
    restored.restoreUnfinishedDraftIfAvailable()
    XCTAssertNil(restored.currentDraftURL)
    XCTAssertEqual(restored.confirmedBristolType, 6)
    XCTAssertEqual(restored.mixedForm, .yes)
    XCTAssertEqual(restored.painScore, 4)
    XCTAssertEqual(restored.urgency, .severe)
    XCTAssertEqual(restored.leakageOrAccident, .no)
    XCTAssertEqual(restored.blackTarry, .unsure)
    XCTAssertEqual(restored.note, "no-photo manual entry survives relaunch")
    guard case .manual(let restoredDraftID) = restored.flowState else {
      return XCTFail("No-photo draft must restore to manual entry.")
    }
    XCTAssertNil(restoredDraftID)

    restored.clear()
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
  }

  func testSuccessfulNoPhotoManualSaveRemovesRecoveryRecord() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")

    harness.viewModel.enterManualMode()
    harness.viewModel.updateConfirmedBristolType(4)
    harness.viewModel.updateMixedForm(.no)
    completeRequiredContext(harness.viewModel)
    harness.viewModel.note = "save this no-photo manual entry"
    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))

    harness.viewModel.save()
    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertNil(harness.store.records.first?.imageFilename)
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
  }

  func testUnfinishedReviewedDraftRestoresReviewSessionAndClearRemovesRecoveryFiles() async throws {
    let harness = try makeHarness(scripts: [.response(valid)])
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    harness.viewModel.updateConfirmedBristolType(5)
    harness.viewModel.updateMixedForm(.yes)
    harness.viewModel.updateConfirmedPhotoUsable(true)
    harness.viewModel.note = "reviewed before interruption"

    let restored = try restoredViewModel(from: harness)
    restored.restoreUnfinishedDraftIfAvailable()
    XCTAssertEqual(restored.currentDraftURL, draftURL)
    XCTAssertEqual(restored.reviewedObservation?.apparentBristolType, 5)
    XCTAssertEqual(restored.note, "reviewed before interruption")
    XCTAssertEqual(restored.reviewState(for: .bristolType), .edited)
    XCTAssertEqual(restored.reviewState(for: .mixedForm), .edited)
    XCTAssertEqual(restored.reviewState(for: .photoUsable), .confirmed)

    restored.clear()
    XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path))
    let afterClear = try restoredViewModel(from: harness)
    afterClear.restoreUnfinishedDraftIfAvailable()
    XCTAssertNil(afterClear.currentDraftURL)
    XCTAssertNil(afterClear.draftRestorationNotice)
  }

  func testCurrentReviewedDraftBindsSuggestionToExactSanitizedPhotoHash() async throws {
    let harness = try makeHarness(scripts: [.response(valid)])
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)

    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    let data = try Data(contentsOf: snapshotURL)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(DraftSnapshot.self, from: data)
    XCTAssertEqual(snapshot.version, DraftSnapshot.currentVersion)
    XCTAssertEqual(snapshot.modelSuggestedImageSHA256, snapshot.draft?.sha256)

    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["modelSuggestedImageSHA256"] = String(repeating: "f", count: 64)
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
      .write(to: snapshotURL, options: .atomic)

    let restarted = try restoredViewModel(from: harness)
    restarted.restoreUnfinishedDraftIfAvailable()
    XCTAssertNil(restarted.currentDraftURL)
    let notice = try XCTUnwrap(restarted.draftRestorationNotice)
    XCTAssertTrue(notice.contains("local files were kept unchanged"))
    XCTAssertFalse(notice.lowercased().contains("recovery"))
    XCTAssertFalse(notice.lowercased().contains("restore"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
  }

  func testSuccessfulSaveRemovesUnfinishedDraftRecoveryRecord() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)
    harness.viewModel.save()
    XCTAssertEqual(harness.store.records.count, 1)

    let restarted = try restoredViewModel(from: harness)
    restarted.restoreUnfinishedDraftIfAvailable()
    XCTAssertNil(restarted.currentDraftURL)
    XCTAssertNil(restarted.draftRestorationNotice)
  }

  func testCorruptDraftSnapshotLeavesPhotoUntouchedAndReportsRecoveryNotice() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    try Data("not valid JSON".utf8).write(to: snapshotURL, options: .atomic)

    let restarted = try restoredViewModel(from: harness)
    restarted.restoreUnfinishedDraftIfAvailable()
    XCTAssertNil(restarted.currentDraftURL)
    let notice = try XCTUnwrap(restarted.draftRestorationNotice)
    XCTAssertTrue(notice.contains("local files were kept unchanged"))
    XCTAssertFalse(notice.lowercased().contains("recovery"))
    XCTAssertFalse(notice.lowercased().contains("restore"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
  }

  func testDraftHashMismatchLeavesFilesUntouchedAndReportsRecoveryNotice() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    try Data("tampered local photo".utf8).write(to: draftURL, options: .atomic)

    let restarted = try restoredViewModel(from: harness)
    restarted.restoreUnfinishedDraftIfAvailable()
    XCTAssertNil(restarted.currentDraftURL)
    let notice = try XCTUnwrap(restarted.draftRestorationNotice)
    XCTAssertTrue(notice.contains("local files were kept unchanged"))
    XCTAssertFalse(notice.lowercased().contains("recovery"))
    XCTAssertFalse(notice.lowercased().contains("restore"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: harness.root.appendingPathComponent("Drafts/active-draft.v1.json").path))
  }

  func testProtectedDataUnavailableKeepsDraftAndDisablesDestructiveDiscard() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.enterManualMode()
    harness.viewModel.note = "keep this protected draft"
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))

    let protectedStore = DraftSnapshotStore(
      imageStore: harness.imageStore,
      protectedDataIsAvailable: { false }
    )
    let restored = NewEntryViewModel(
      imageStore: harness.imageStore,
      draftSnapshotStore: protectedStore,
      store: harness.store,
      inference: MockInferenceService(scripts: []),
      descriptor: .galleryGemma3nE2B,
      modelVerified: true,
      engineReady: true,
      configuration: .deterministicBaseline
    )
    restored.restoreUnfinishedDraftIfAvailable()

    let notice = try XCTUnwrap(restored.draftRestorationNotice)
    XCTAssertTrue(notice.localizedCaseInsensitiveContains("still protected on this device"))
    XCTAssertTrue(notice.localizedCaseInsensitiveContains("try reopening it"))
    XCTAssertFalse(notice.lowercased().contains("recovery"))
    XCTAssertFalse(notice.lowercased().contains("restore"))
    XCTAssertFalse(restored.canDiscardUnavailableDraft)
    restored.discardUnrestorableDraft()
    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))
  }

  func testFirstPhotoSnapshotWriteFailureLeavesNoUnreferencedDraftFile() throws {
    let fault = SnapshotSaveFault()
    fault.shouldFail = true
    let harness = try makeHarness(snapshotSaveFailureInjector: { try fault.run() })
    defer { harness.cleanup() }
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")

    XCTAssertThrowsError(try harness.viewModel.prepareImageData(imageData()))

    XCTAssertNil(harness.viewModel.currentDraftURL)
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    let JPEGs = try FileManager.default.contentsOfDirectory(
      at: harness.root.appendingPathComponent("Drafts"),
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension.lowercased() == "jpg" }
    XCTAssertTrue(JPEGs.isEmpty, "A failed first snapshot must not strand a prepared JPEG.")
  }

  func testPreparedImageWriterFailureAfterCreatingFileCleansOrphan() throws {
    struct SimulatedPostWriteFailure: Error {}
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts")
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: root.appendingPathComponent("Images"),
      preparedImageWriter: { data, url in
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        throw SimulatedPostWriteFailure()
      }
    )

    XCTAssertThrowsError(try imageStore.prepare(imageData()))
    let files = try FileManager.default.contentsOfDirectory(at: drafts, includingPropertiesForKeys: nil)
    XCTAssertFalse(files.contains(where: { $0.pathExtension.lowercased() == "jpg" }))
  }

  func testPreEraseImageStoreCannotCommitLatePickerPhotoAfterMarkerClears() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts")
    let epoch = JournalWriteEpoch()
    var markerExists = false
    let preEraseStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: root.appendingPathComponent("Images"),
      writeGate: JournalWriteGate(
        pendingEraseProbe: { markerExists },
        epoch: epoch
      )
    )

    epoch.invalidateCurrentWriters()
    markerExists = true
    markerExists = false
    XCTAssertThrowsError(try preEraseStore.prepare(imageData())) { error in
      XCTAssertEqual(error as? JournalWriteGateError, .staleWriter)
    }
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: drafts.path),
      "A stale picker result must be rejected before it can recreate the Drafts directory."
    )
    let files = (try? FileManager.default.contentsOfDirectory(at: drafts, includingPropertiesForKeys: nil)) ?? []
    XCTAssertFalse(
      files.contains(where: { $0.pathExtension.lowercased() == "jpg" }),
      "A picker result owned by the pre-erase UI must not leave a draft JPEG after erase."
    )
  }

  func testReplacementSnapshotWriteFailureRetainsPriorSnapshotAndPhoto() throws {
    let fault = SnapshotSaveFault()
    let harness = try makeHarness(snapshotSaveFailureInjector: { try fault.run() })
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData(color: .brown))
    let oldDraftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    let oldSnapshotBytes = try Data(contentsOf: snapshotURL)

    fault.shouldFail = true
    XCTAssertThrowsError(try harness.viewModel.prepareImageData(imageData(color: .green)))

    XCTAssertEqual(harness.viewModel.currentDraftURL, oldDraftURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: oldDraftURL.path))
    XCTAssertEqual(try Data(contentsOf: snapshotURL), oldSnapshotBytes)
    let JPEGs = try FileManager.default.contentsOfDirectory(
      at: harness.root.appendingPathComponent("Drafts"),
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension.lowercased() == "jpg" }
    XCTAssertEqual(JPEGs.map(\.lastPathComponent), [oldDraftURL.lastPathComponent])
  }

  func testBlockedProtectedDraftCannotBeOverwrittenAndRetriesAfterUnlock() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    let snapshotBytes = try Data(contentsOf: snapshotURL)
    let availability = ProtectedDataAvailability(isAvailable: false)
    let protectedStore = DraftSnapshotStore(
      imageStore: harness.imageStore,
      protectedDataIsAvailable: { availability.isAvailable }
    )
    let restored = NewEntryViewModel(
      imageStore: harness.imageStore,
      draftSnapshotStore: protectedStore,
      store: harness.store,
      inference: MockInferenceService(scripts: []),
      descriptor: .galleryGemma3nE2B,
      modelVerified: true,
      engineReady: true,
      configuration: .deterministicBaseline
    )

    restored.restoreUnfinishedDraftIfAvailable()
    XCTAssertTrue(restored.isDraftRecoveryBlocked)
    XCTAssertFalse(restored.canReplaceOrClear)
    XCTAssertFalse(restored.canSave)
    restored.enterManualMode()
    try restored.prepareImageData(imageData(color: .green))
    restored.clear()

    XCTAssertEqual(try Data(contentsOf: snapshotURL), snapshotBytes)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))
    let JPEGs = try FileManager.default.contentsOfDirectory(
      at: harness.root.appendingPathComponent("Drafts"),
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension.lowercased() == "jpg" }
    XCTAssertEqual(JPEGs.map(\.lastPathComponent), [draftURL.lastPathComponent])

    availability.isAvailable = true
    restored.retryDraftRestoration()
    XCTAssertFalse(restored.isDraftRecoveryBlocked)
    XCTAssertNil(restored.draftRestorationNotice)
    XCTAssertEqual(restored.currentDraftURL, draftURL)
  }

  func testProtectedDataRaceDuringSnapshotReadRemainsTemporarilyUnavailable() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let availability = ProtectedDataAvailability(isAvailable: true)
    let protectedStore = DraftSnapshotStore(
      imageStore: harness.imageStore,
      protectedDataIsAvailable: { availability.isAvailable },
      dataReader: { url in
        if url.lastPathComponent == "active-draft.v1.json" {
          availability.isAvailable = false
          throw CocoaError(.fileReadNoPermission)
        }
        return try Data(contentsOf: url)
      }
    )

    guard case .temporarilyUnavailable = protectedStore.restore() else {
      return XCTFail("A lock race must remain non-discardable and retryable.")
    }
  }

  func testDirectPOSIXProtectedDataReadFailureRemainsTemporarilyUnavailable() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let protectedStore = DraftSnapshotStore(
      imageStore: harness.imageStore,
      protectedDataIsAvailable: { true },
      dataReader: { _ in
        throw NSError(domain: NSPOSIXErrorDomain, code: 13)
      }
    )

    guard case .temporarilyUnavailable = protectedStore.restore() else {
      return XCTFail("A direct access-denied error can be a protected-data race and must remain retryable.")
    }
  }

  func testDraftDirectoryEnumerationFailureCannotMasqueradeAsNoDraft() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    _ = try imageStore.draftsDirectory()
    let store = DraftSnapshotStore(
      imageStore: imageStore,
      directoryContents: { _ in throw CocoaError(.fileReadUnknown) }
    )

    guard case .unavailable = store.restore() else {
      return XCTFail("Failed enumeration is uncertain recovery state, never an empty-draft result.")
    }
  }

  func testKeptUnavailableDraftRemainsBlockedUntilExplicitDiscard() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    try Data("invalid recovery record".utf8).write(to: snapshotURL, options: .atomic)
    let snapshotBytes = try Data(contentsOf: snapshotURL)
    let restored = try restoredViewModel(from: harness)

    restored.restoreUnfinishedDraftIfAvailable()
    XCTAssertTrue(restored.isDraftRecoveryBlocked)
    XCTAssertTrue(restored.canDiscardUnavailableDraft)
    restored.dismissDraftRestorationNotice() // the user's "Keep local files" path
    try restored.prepareImageData(imageData(color: .green))
    XCTAssertEqual(try Data(contentsOf: snapshotURL), snapshotBytes)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))

    restored.discardUnrestorableDraft()
    XCTAssertFalse(restored.isDraftRecoveryBlocked)
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path))
  }

  func testClearAndExplicitDiscardStayBlockedUntilEveryRecoveryFileIsRemoved() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    let fault = DraftRemovalFault()
    fault.shouldFail = true
    let faultingSnapshotStore = DraftSnapshotStore(
      imageStore: harness.imageStore,
      itemRemover: { url in
        try fault.remove(url)
      }
    )
    let restored = NewEntryViewModel(
      imageStore: harness.imageStore,
      draftSnapshotStore: faultingSnapshotStore,
      store: harness.store,
      inference: MockInferenceService(scripts: []),
      descriptor: .galleryGemma3nE2B,
      modelVerified: true,
      engineReady: true,
      configuration: .deterministicBaseline
    )
    restored.restoreUnfinishedDraftIfAvailable()

    restored.clear()
    XCTAssertTrue(restored.isDraftRecoveryBlocked)
    XCTAssertTrue(restored.canDiscardUnavailableDraft)
    XCTAssertEqual(restored.currentDraftURL, draftURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))

    restored.discardUnrestorableDraft()
    XCTAssertTrue(restored.isDraftRecoveryBlocked)
    XCTAssertNotNil(restored.draftRestorationNotice)

    fault.shouldFail = false
    restored.discardUnrestorableDraft()
    XCTAssertFalse(restored.isDraftRecoveryBlocked)
    XCTAssertNil(restored.currentDraftURL)
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path))
  }

  func testStalePreEraseDraftStoreCannotRecreateSnapshotAfterMarkerClears() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(DraftSnapshot.self, from: Data(contentsOf: snapshotURL))

    let epoch = JournalWriteEpoch()
    var markerExists = false
    let preEraseStore = DraftSnapshotStore(
      imageStore: harness.imageStore,
      protectedDataIsAvailable: { true },
      writeGate: JournalWriteGate(
        pendingEraseProbe: { markerExists },
        epoch: epoch
      )
    )
    epoch.invalidateCurrentWriters()

    // If erase fails before the marker is written, the reconstructed UI uses
    // a current gate and can restore the untouched snapshot and JPEG.
    let reconstructedStore = DraftSnapshotStore(
      imageStore: harness.imageStore,
      protectedDataIsAvailable: { true },
      writeGate: JournalWriteGate(
        pendingEraseProbe: { markerExists },
        epoch: epoch
      )
    )
    guard case .restored = reconstructedStore.restore() else {
      return XCTFail("A marker-absent erase failure must leave the existing draft restorable.")
    }

    // Successful erase removes the files and later clears its marker. An old
    // inference completion must remain stale and cannot recreate the snapshot.
    markerExists = true
    try FileManager.default.removeItem(at: draftURL)
    try FileManager.default.removeItem(at: snapshotURL)
    markerExists = false
    XCTAssertThrowsError(try preEraseStore.save(snapshot)) { error in
      XCTAssertEqual(error as? JournalWriteGateError, .staleWriter)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
  }

  func testStaleDraftRestoreSkipsOrphanPruningAndKeepsAuthoritativeDraftReadable() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let authoritativeDraft = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let orphan = harness.root
      .appendingPathComponent("Drafts", isDirectory: true)
      .appendingPathComponent("\(UUID().uuidString).jpg")
    try imageData(color: .green).write(to: orphan, options: .atomic)

    let epoch = JournalWriteEpoch()
    var markerExists = false
    let staleStore = DraftSnapshotStore(
      imageStore: harness.imageStore,
      protectedDataIsAvailable: { true },
      writeGate: JournalWriteGate(
        pendingEraseProbe: { markerExists },
        epoch: epoch
      )
    )
    epoch.invalidateCurrentWriters()
    markerExists = true
    markerExists = false

    guard case .restored = staleStore.restore() else {
      return XCTFail("A stale gate must not prevent read-only restoration of the authoritative draft.")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: authoritativeDraft.path))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: orphan.path),
      "A stale restore may read its snapshot but must never prune another JPEG."
    )
  }

  func testPostCommitDraftSnapshotUsesStableEntryIDAndCleansOnRelaunch() throws {
    let interruption = PostCommitCleanupInterruption()
    interruption.shouldInterrupt = true
    let harness = try makeHarness(postCommitCleanupInterruption: { interruption.shouldInterrupt })
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")

    harness.viewModel.save()

    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let interruptedSnapshot = try decoder.decode(DraftSnapshot.self, from: Data(contentsOf: snapshotURL))
    let savedRecord = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(interruptedSnapshot.pendingEntryID, savedRecord.id)
    XCTAssertEqual(
      interruptedSnapshot.pendingEntryFingerprint,
      try EntryTransactionFingerprint.make(for: savedRecord)
    )

    let relaunched = try restoredViewModel(from: harness)
    relaunched.restoreUnfinishedDraftIfAvailable()

    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertNil(relaunched.currentDraftURL)
    XCTAssertFalse(relaunched.isDraftRecoveryBlocked)
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path))
  }

  func testPendingCommittedSnapshotWithAlreadyDeletedDraftSelfHeals() throws {
    let interruption = PostCommitCleanupInterruption()
    interruption.shouldInterrupt = true
    let harness = try makeHarness(postCommitCleanupInterruption: { interruption.shouldInterrupt })
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)
    harness.viewModel.save()
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    try FileManager.default.removeItem(at: draftURL)

    let relaunched = try restoredViewModel(from: harness)
    relaunched.restoreUnfinishedDraftIfAvailable()

    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertFalse(relaunched.isDraftRecoveryBlocked)
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
  }

  func testCommittedPendingSnapshotCleansAfterDiscussionMarkWithoutLosingMark() throws {
    let interruption = PostCommitCleanupInterruption()
    interruption.shouldInterrupt = true
    let harness = try makeHarness(postCommitCleanupInterruption: { interruption.shouldInterrupt })
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)
    harness.viewModel.save()
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    let saved = try XCTUnwrap(harness.store.records.first)
    let markDate = Date(timeIntervalSince1970: 1_720_000_000)
    try harness.store.setDiscussionMark(true, for: saved, at: markDate)

    let relaunched = try restoredViewModel(from: harness)
    relaunched.restoreUnfinishedDraftIfAvailable()

    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertEqual(harness.store.records.first?.markedForDiscussionAt, markDate)
    XCTAssertFalse(relaunched.isDraftRecoveryBlocked)
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path))
  }

  func testMissingSnapshotNeverDeletesUnverifiableOrphanDraft() throws {
    let interruption = PostCommitCleanupInterruption()
    interruption.shouldInterrupt = true
    let harness = try makeHarness(postCommitCleanupInterruption: { interruption.shouldInterrupt })
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    harness.viewModel.enterManualMode()
    completeRequiredReview(harness.viewModel)
    harness.viewModel.save()
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    try FileManager.default.removeItem(at: snapshotURL)

    let relaunched = try restoredViewModel(from: harness)
    relaunched.restoreUnfinishedDraftIfAvailable()

    XCTAssertTrue(relaunched.isDraftRecoveryBlocked)
    XCTAssertTrue(relaunched.canDiscardUnavailableDraft)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path), "Without transaction metadata, an orphan must never be guessed safe to delete.")
    XCTAssertEqual(harness.store.records.count, 1)
  }

  func testPendingFingerprintMismatchBlocksCleanupAndPreservesBothSources() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    let container = try PersistenceSchema.makeInMemoryContainer()
    let firstContext = ModelContext(container)
    let firstStore = EntryStore(context: firstContext)
    let viewModel = NewEntryViewModel(
      imageStore: imageStore,
      store: firstStore,
      inference: MockInferenceService(scripts: []),
      descriptor: .galleryGemma3nE2B,
      modelVerified: true,
      engineReady: true,
      configuration: .deterministicBaseline,
      postCommitCleanupInterruption: { true }
    )
    try viewModel.prepareImageData(imageData())
    let draftURL = try XCTUnwrap(viewModel.currentDraftURL)
    viewModel.enterManualMode()
    completeRequiredReview(viewModel)
    viewModel.note = "original payload"
    viewModel.save()
    let snapshotURL = root.appendingPathComponent("Drafts/active-draft.v1.json")
    let saved = try XCTUnwrap(try firstContext.fetch(FetchDescriptor<EntryRecord>()).first)
    saved.note = "different durable payload"
    try firstContext.save()

    // A genuinely new context must observe the persisted mismatch; recovery
    // cannot rely on an unsaved in-memory mutation from the original context.
    let reopenedContext = ModelContext(container)
    XCTAssertEqual(
      try XCTUnwrap(try reopenedContext.fetch(FetchDescriptor<EntryRecord>()).first).note,
      "different durable payload"
    )
    let relaunched = NewEntryViewModel(
      imageStore: imageStore,
      store: EntryStore(context: reopenedContext),
      inference: MockInferenceService(scripts: []),
      descriptor: .galleryGemma3nE2B,
      modelVerified: true,
      engineReady: true,
      configuration: .deterministicBaseline
    )
    relaunched.restoreUnfinishedDraftIfAvailable()

    XCTAssertTrue(relaunched.isDraftRecoveryBlocked)
    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))
    XCTAssertEqual(try reopenedContext.fetchCount(FetchDescriptor<EntryRecord>()), 1)
  }

  func testPendingReviewedAtAndFingerprintMatchExactAIRecord() async throws {
    let interruption = PostCommitCleanupInterruption()
    interruption.shouldInterrupt = true
    let harness = try makeHarness(
      scripts: [.response(valid)],
      postCommitCleanupInterruption: { interruption.shouldInterrupt }
    )
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    completeRequiredReview(harness.viewModel)
    harness.viewModel.save()

    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(
      DraftSnapshot.self,
      from: Data(contentsOf: harness.root.appendingPathComponent("Drafts/active-draft.v1.json"))
    )
    let record = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(snapshot.pendingReviewedAt, record.reviewedAt)
    XCTAssertEqual(snapshot.pendingEntryFingerprint, try EntryTransactionFingerprint.make(for: record))
  }

  func testDiskBackedColdReopenPreservesAITransactionBitsAndFinishesCleanup() async throws {
    let root = temporaryRoot()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    let drafts = root.appendingPathComponent("Drafts")
    let images = root.appendingPathComponent("Images")

    struct ExpectedTransaction {
      let id: UUID
      let reviewedAt: Date
      let fingerprint: String
      let draftURL: URL
    }

    @MainActor func writeInterruptedAITransaction() async throws -> ExpectedTransaction {
      let container = try PersistenceSchema.openPublicStore(at: storeURL)
      let context = ModelContext(container)
      let imageStore = ImageStore(draftsDirectory: drafts, imagesDirectory: images)
      let store = EntryStore(context: context)
      let viewModel = NewEntryViewModel(
        imageStore: imageStore,
        store: store,
        inference: MockInferenceService(scripts: [.response(valid)]),
        descriptor: .galleryGemma3nE2B,
        modelVerified: true,
        engineReady: true,
        configuration: .deterministicBaseline,
        postCommitCleanupInterruption: { true }
      )
      try viewModel.prepareImageData(imageData())
      let draftURL = try XCTUnwrap(viewModel.currentDraftURL)
      viewModel.analyze()
      await waitForAnalysis(viewModel)
      completeRequiredReview(viewModel)
      viewModel.save()

      let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
      let snapshot = try decoder.decode(
        DraftSnapshot.self,
        from: Data(contentsOf: drafts.appendingPathComponent("active-draft.v1.json"))
      )
      let record = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
      return ExpectedTransaction(
        id: record.id,
        reviewedAt: try XCTUnwrap(record.reviewedAt),
        fingerprint: try XCTUnwrap(snapshot.pendingEntryFingerprint),
        draftURL: draftURL
      )
    }

    let expected = try await writeInterruptedAITransaction()
    await Task.yield()

    // Reopen the SQLite-backed store with a new ModelContainer and context.
    // This catches Date/encoding drift that an in-memory reused context cannot.
    let reopenedContainer = try PersistenceSchema.openPublicStore(at: storeURL)
    let reopenedContext = ModelContext(reopenedContainer)
    let expectedID = expected.id
    let reopenedRecord = try XCTUnwrap(
      try reopenedContext.fetch(
        FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == expectedID })
      ).first
    )
    XCTAssertEqual(reopenedRecord.reviewedAt, expected.reviewedAt)
    XCTAssertEqual(try EntryTransactionFingerprint.make(for: reopenedRecord), expected.fingerprint)

    let reopenedImageStore = ImageStore(draftsDirectory: drafts, imagesDirectory: images)
    let relaunched = NewEntryViewModel(
      imageStore: reopenedImageStore,
      store: EntryStore(context: reopenedContext),
      inference: MockInferenceService(scripts: []),
      descriptor: .galleryGemma3nE2B,
      modelVerified: true,
      engineReady: true,
      configuration: .deterministicBaseline
    )
    relaunched.restoreUnfinishedDraftIfAvailable()

    XCTAssertFalse(relaunched.isDraftRecoveryBlocked)
    XCTAssertEqual(try reopenedContext.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: expected.draftURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: drafts.appendingPathComponent("active-draft.v1.json").path))
  }

  func testVersionOneSnapshotDecodesAndIsMigratedOnNextDraftWrite() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    var legacyObject = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL)) as? [String: Any]
    )
    legacyObject["version"] = DraftSnapshot.legacyVersion
    legacyObject.removeValue(forKey: "pendingEntryID")
    legacyObject.removeValue(forKey: "pendingEntryFingerprint")
    legacyObject.removeValue(forKey: "pendingReviewedAt")
    try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys]).write(to: snapshotURL, options: .atomic)

    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let legacy = try decoder.decode(DraftSnapshot.self, from: Data(contentsOf: snapshotURL))
    XCTAssertEqual(legacy.version, DraftSnapshot.legacyVersion)
    XCTAssertNil(legacy.pendingEntryID)
    XCTAssertNoThrow(try legacy.validateStructure())

    let restored = try restoredViewModel(from: harness)
    restored.restoreUnfinishedDraftIfAvailable()
    restored.note = "rewrite this legacy snapshot"
    let migrated = try decoder.decode(DraftSnapshot.self, from: Data(contentsOf: snapshotURL))
    XCTAssertEqual(migrated.version, DraftSnapshot.currentVersion)
    XCTAssertNil(migrated.pendingEntryID)
    XCTAssertNil(migrated.pendingEntryFingerprint)
  }

  func testVersionOneSnapshotRejectsPendingTransactionFields() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL)) as? [String: Any]
    )
    object["version"] = DraftSnapshot.legacyVersion
    object["pendingEntryID"] = UUID().uuidString
    object["pendingEntryFingerprint"] = String(repeating: "a", count: 64)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let invalid = try decoder.decode(
      DraftSnapshot.self,
      from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )

    XCTAssertThrowsError(try invalid.validateStructure()) { error in
      XCTAssertEqual(error as? DraftSnapshotError, .invalidContents)
    }
  }

  func testVersionSevenSnapshotWithoutV8FieldsRestoresAndRewritesVersionEight()
    throws
  {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let snapshotURL = harness.root.appendingPathComponent(
      "Drafts/active-draft.v1.json"
    )
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL))
        as? [String: Any]
    )
    object["version"] = DraftSnapshot.normalizationReceiptVersion
    object.removeValue(forKey: "blackAppearance")
    object.removeValue(forKey: "photoSuggestionEngineReceiptJSON")
    let predecessorBytes = try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys]
    )
    try predecessorBytes.write(to: snapshotURL, options: .atomic)
    let predecessorText = try XCTUnwrap(
      String(data: predecessorBytes, encoding: .utf8)
    )
    XCTAssertFalse(predecessorText.contains("blackAppearance"))
    XCTAssertFalse(predecessorText.contains("photoSuggestionEngineReceiptJSON"))

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let predecessor = try decoder.decode(DraftSnapshot.self, from: predecessorBytes)
    XCTAssertEqual(predecessor.version, DraftSnapshot.normalizationReceiptVersion)
    XCTAssertNil(predecessor.blackAppearance)
    XCTAssertNil(predecessor.photoSuggestionEngineReceiptJSON)
    XCTAssertNoThrow(try predecessor.validateStructure())

    let restored = try restoredViewModel(from: harness)
    restored.restoreUnfinishedDraftIfAvailable()
    XCTAssertNil(restored.blackAppearance)
    restored.note = "rewrite the valid version-seven draft"
    let rewritten = try decoder.decode(
      DraftSnapshot.self,
      from: Data(contentsOf: snapshotURL)
    )
    XCTAssertEqual(rewritten.version, DraftSnapshot.currentVersion)
    XCTAssertNil(rewritten.blackAppearance)
    XCTAssertNil(rewritten.photoSuggestionEngineReceiptJSON)
  }

  func testV8AndV9SnapshotsUseVersionAwareAppearancePrefillMigration()
    async throws
  {
    // Older model-backed snapshots are re-derived from the authenticated raw
    // suggestion rather than trusting stale displayed fields. Under the
    // current complete tri-state contract, an authenticated model "no"
    // displays as an editable, unconfirmed No.
    let raw = """
      {"black_tarry_appearance":"no","schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":"dark_brown","red_appearing_material":"no","black_appearance":"no"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.redBlood, .no)
    XCTAssertEqual(harness.viewModel.blackAppearance, .no)
    XCTAssertEqual(harness.viewModel.blackTarry, .no)

    let snapshotURL = harness.root.appendingPathComponent(
      "Drafts/active-draft.v1.json"
    )
    let object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL))
        as? [String: Any]
    )
    XCTAssertEqual(object["version"] as? Int, DraftSnapshot.currentVersion)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let predecessors: [(version: Int, stored: SymptomFlag)] = [
      (DraftSnapshot.providerNeutralVersion, .no),
      (DraftSnapshot.safetyPrefillVersion, .unsure),
    ]
    for predecessorCase in predecessors {
      var predecessorObject = object
      predecessorObject["version"] = predecessorCase.version
      predecessorObject["redBlood"] = predecessorCase.stored.rawValue
      predecessorObject["blackAppearance"] = predecessorCase.stored.rawValue
      predecessorObject["blackTarry"] = predecessorCase.stored.rawValue
      let predecessorBytes = try JSONSerialization.data(
        withJSONObject: predecessorObject,
        options: [.sortedKeys]
      )
      try predecessorBytes.write(to: snapshotURL, options: .atomic)

      let predecessor = try decoder.decode(
        DraftSnapshot.self,
        from: predecessorBytes
      )
      XCTAssertEqual(predecessor.version, predecessorCase.version)
      XCTAssertEqual(predecessor.redBlood, predecessorCase.stored)
      XCTAssertEqual(predecessor.blackAppearance, predecessorCase.stored)
      XCTAssertEqual(predecessor.blackTarry, predecessorCase.stored)
      XCTAssertEqual(predecessor.originalValidatedJSON, raw)
      XCTAssertEqual(predecessor.analysisSource, .onDevicePhotoSuggestion)
      XCTAssertNoThrow(try predecessor.validateStructure())

      let restored = try restoredViewModel(from: harness)
      restored.restoreUnfinishedDraftIfAvailable()

      XCTAssertEqual(restored.redBlood, .no)
      XCTAssertEqual(restored.blackAppearance, .no)
      XCTAssertEqual(restored.blackTarry, .no)
      XCTAssertEqual(
        restored.aiReadHints["redMaterial"],
        "AI suggestion: No blood-like red material detected in this photo."
      )
      XCTAssertEqual(
        restored.aiReadHints["blackAppearance"],
        "AI suggestion: No black or tar-like appearance detected in this photo."
      )
      XCTAssertEqual(
        restored.aiReadHints["blackTarry"],
        "AI suggestion: No black or tar-like appearance detected in this photo."
      )
      XCTAssertTrue(restored.canSave)
    }
  }

  func testAppearancePrefillMigrationPreservesPersonEditsInV8AndV9Drafts()
    async throws
  {
    let raw = """
      {"black_tarry_appearance":"no","schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":"dark_brown","red_appearing_material":"no","black_appearance":"no"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    let snapshotURL = harness.root.appendingPathComponent(
      "Drafts/active-draft.v1.json"
    )
    let currentObject = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL))
        as? [String: Any]
    )
    let cases: [
      (version: Int, stored: [SymptomFlag], expected: [SymptomFlag])
    ] = [
      // V8 already used complete tri-state prefill. Both divergent values
      // are person edits and must survive unchanged.
      (
        DraftSnapshot.providerNeutralVersion,
        [.yes, .unsure, .no],
        [.yes, .unsure, .no]
      ),
      // In V9, Not sure was the automatic value for model No. Only the field
      // still equal to that automatic value migrates; Yes and No are edits.
      (
        DraftSnapshot.safetyPrefillVersion,
        [.yes, .no, .unsure],
        [.yes, .no, .no]
      ),
    ]

    for migrationCase in cases {
      var object = currentObject
      object["version"] = migrationCase.version
      object["redBlood"] = migrationCase.stored[0].rawValue
      object["blackAppearance"] = migrationCase.stored[1].rawValue
      object["blackTarry"] = migrationCase.stored[2].rawValue
      try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys]
      ).write(to: snapshotURL, options: .atomic)

      let restored = try restoredViewModel(from: harness)
      restored.restoreUnfinishedDraftIfAvailable()
      XCTAssertEqual(restored.redBlood, migrationCase.expected[0])
      XCTAssertEqual(restored.blackAppearance, migrationCase.expected[1])
      XCTAssertEqual(restored.blackTarry, migrationCase.expected[2])
      XCTAssertTrue(restored.canSave)
    }
  }

  func testV9DraftWithRealLegacyV1ReceiptRestoresAndShowsExactHints()
    async throws
  {
    let suggestion = PhotoSuggestionPayloadV2(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .uncertain,
      bristolType: nil,
      form: "unable_to_assess",
      mixedForm: .notSure,
      apparentColor: "dark_brown",
      redAppearingMaterial: .no,
      blackAppearance: .no,
      blackTarryAppearance: .no
    )
    let raw = try PhotoSuggestionPayloadV2Parser.canonicalJSON(suggestion)
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    let snapshotURL = harness.root.appendingPathComponent(
      "Drafts/active-draft.v1.json"
    )
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL))
        as? [String: Any]
    )
    let draftObject = try XCTUnwrap(object["draft"] as? [String: Any])
    let imageSHA256 = try XCTUnwrap(draftObject["sha256"] as? String)
    let instant = Date(timeIntervalSinceReferenceDate: 2_500)
    let legacy = try decomposedPhotoSuggestionReceiptFixture(
      fusionVersion: Qwen3DecomposedFusion.legacyCompleteTriStateVersion,
      parserVersion: Qwen3DecomposedContract.legacyParserVersion,
      negativeAppearance: true,
      imageSHA256: imageSHA256,
      analysisPipelineVersion:
        MockPhotoSuggestionEngine.identity.analysisPipelineVersion,
      instant: instant
    )
    XCTAssertEqual(String(data: legacy.rawOutput, encoding: .utf8), raw)
    let receiptJSON = try XCTUnwrap(legacy.receipt.canonicalJSON)
    let dateEncoder = JSONEncoder()
    dateEncoder.dateEncodingStrategy = .iso8601
    let instantString = try JSONDecoder().decode(
      String.self,
      from: dateEncoder.encode(instant)
    )

    object["version"] = DraftSnapshot.safetyPrefillVersion
    object["redBlood"] = SymptomFlag.unsure.rawValue
    object["blackAppearance"] = SymptomFlag.unsure.rawValue
    object["blackTarry"] = SymptomFlag.unsure.rawValue
    object["originalValidatedJSON"] = raw
    object["photoSuggestionEngineReceiptJSON"] = receiptJSON
    object["modelSuggestedImageSHA256"] = imageSHA256
    object["modelSuggestedAt"] = instantString
    object["generationStartedAt"] = instantString
    object["generationEndedAt"] = instantString
    try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys]
    ).write(to: snapshotURL, options: .atomic)

    let restored = try restoredViewModel(from: harness)
    restored.restoreUnfinishedDraftIfAvailable()
    XCTAssertFalse(restored.isDraftRecoveryBlocked)
    XCTAssertEqual(restored.redBlood, .no)
    XCTAssertEqual(restored.blackAppearance, .no)
    XCTAssertEqual(restored.blackTarry, .no)
    XCTAssertEqual(
      restored.aiReadHints["redMaterial"],
      "AI suggestion: No blood-like red material detected in this photo."
    )
    XCTAssertEqual(
      restored.aiReadHints["blackAppearance"],
      "AI suggestion: No black or tar-like appearance detected in this photo."
    )
    XCTAssertEqual(
      restored.aiReadHints["blackTarry"],
      "AI suggestion: No black or tar-like appearance detected in this photo."
    )
    XCTAssertTrue(restored.canSave)
  }

  func testVersionThreeEditDraftWithoutBlackAppearanceValidatesAndRewritesV4()
    throws
  {
    let input = EntryInput(
      id: UUID(),
      capturedAt: Date(timeIntervalSince1970: 1_730_000_000),
      draftURL: nil,
      imageSHA256: nil,
      redBlood: .no,
      blackTarry: .unsure,
      dizziness: .no,
      severePain: .no,
      note: "legacy edit",
      provenance: .manual,
      reviewedAt: nil,
      originalAIJSON: nil,
      reviewedJSON: nil,
      modelID: nil,
      modelProvenanceJSON: nil,
      demoKind: nil,
      imageFilename: nil
    )
    let entry = EntryRecord(input: input)
    var edit = EntryEditInput(entry: entry)
    edit.blackAppearance = nil
    let baseline = try EntryRecordFingerprint.make(for: entry)
    let current = try EntryEditDraftSnapshot(
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      input: edit,
      pendingSave: false
    )
    var object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(current))
        as? [String: Any]
    )
    object["version"] = EntryEditDraftSnapshot.retakeReasonVersion
    object["inputHash"] = try edit
      .legacyCanonicalSHA256WithoutBlackAppearance()
    var predecessorInput = try XCTUnwrap(object["input"] as? [String: Any])
    predecessorInput.removeValue(forKey: "blackAppearance")
    object["input"] = predecessorInput
    let predecessorBytes = try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys]
    )
    let predecessorText = try XCTUnwrap(
      String(data: predecessorBytes, encoding: .utf8)
    )
    XCTAssertFalse(predecessorText.contains("blackAppearance"))

    let predecessor = try JSONDecoder().decode(
      EntryEditDraftSnapshot.self,
      from: predecessorBytes
    )
    XCTAssertNil(predecessor.input.blackAppearance)
    XCTAssertNoThrow(try predecessor.validate(expectedEntryID: entry.id))
    let rewritten = try EntryEditDraftSnapshot(
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      input: predecessor.input,
      pendingSave: false
    )
    XCTAssertEqual(rewritten.version, EntryEditDraftSnapshot.currentVersion)
    XCTAssertEqual(rewritten.inputHash, try predecessor.input.canonicalSHA256())
  }

  func testProviderNeutralV2OneCallPersistsExactRawDraftReceiptAndBlackFields()
    async throws
  {
    let raw = """
      {"black_tarry_appearance":"no","schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":"dark_brown","red_appearing_material":"yes","black_appearance":"yes"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    let callCounts = await engine.counts()
    XCTAssertEqual(callCounts, .init(prepare: 1, suggest: 1, cancel: 0))
    XCTAssertEqual(harness.viewModel.analysisSource, .onDevicePhotoSuggestion)
    XCTAssertEqual(harness.viewModel.confirmedStoolPresence, .nonStool)
    XCTAssertNil(harness.viewModel.confirmedBristolType)
    XCTAssertEqual(harness.viewModel.confirmedForm, "unable_to_assess")
    XCTAssertEqual(harness.viewModel.mixedForm, .unsure)
    XCTAssertEqual(harness.viewModel.apparentColor, "dark_brown")
    XCTAssertEqual(harness.viewModel.redBlood, .yes)
    XCTAssertEqual(harness.viewModel.blackAppearance, .yes)
    XCTAssertEqual(harness.viewModel.blackTarry, .no)
    XCTAssertTrue(harness.viewModel.canSave)

    let snapshotURL = harness.root.appendingPathComponent(
      "Drafts/active-draft.v1.json"
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(
      DraftSnapshot.self,
      from: Data(contentsOf: snapshotURL)
    )
    XCTAssertEqual(snapshot.version, DraftSnapshot.currentVersion)
    XCTAssertEqual(snapshot.originalValidatedJSON, raw)
    XCTAssertEqual(snapshot.analysisSource, .onDevicePhotoSuggestion)
    XCTAssertEqual(snapshot.blackAppearance, .yes)
    let draftReceiptJSON = try XCTUnwrap(
      snapshot.photoSuggestionEngineReceiptJSON
    )
    let draftReceipt = try PhotoSuggestionEngineReceipt.decode(
      draftReceiptJSON
    )
    XCTAssertEqual(draftReceipt.identity, MockPhotoSuggestionEngine.identity)
    XCTAssertEqual(
      try draftReceipt.validate(rawOutputUTF8: Data(raw.utf8)),
      try PhotoSuggestionPayloadV2Parser.parse(raw)
    )
    XCTAssertThrowsError(
      try draftReceipt.validate(rawOutputUTF8: Data((raw + " ").utf8))
    )

    // A cold view-model restore must recover the exact validated review and
    // must not schedule a second model call before the one-tap save.
    let relaunched = NewEntryViewModel(
      imageStore: harness.imageStore,
      store: harness.store,
      inference: MockInferenceService(scripts: []),
      photoSuggestionEngine: engine,
      descriptor: nil,
      modelVerified: true,
      engineReady: true,
      configuration: .deterministicBaseline,
      autoAnalysisEnabled: true
    )
    relaunched.restoreUnfinishedDraftIfAvailable()
    XCTAssertFalse(relaunched.canAnalyze)
    XCTAssertTrue(relaunched.canSave)
    XCTAssertEqual(relaunched.analysisSource, .onDevicePhotoSuggestion)
    XCTAssertEqual(relaunched.blackAppearance, .yes)
    XCTAssertEqual(relaunched.blackTarry, .no)
    XCTAssertEqual(
      relaunched.aiReadHints["redMaterial"],
      "AI suggestion: Possible blood-like red material is visible."
    )
    XCTAssertEqual(
      relaunched.aiReadHints["blackAppearance"],
      "AI suggestion: Possible black or tar-like appearance is visible."
    )
    XCTAssertEqual(
      relaunched.aiReadHints["blackTarry"],
      "AI suggestion: No black or tar-like appearance detected in this photo."
    )
    let relaunchedCallCounts = await engine.counts()
    XCTAssertEqual(
      relaunchedCallCounts,
      .init(prepare: 1, suggest: 1, cancel: 0)
    )

    // The public one-tap adoption path accepts the complete displayed tuple.
    relaunched.save()
    let record = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertEqual(record.savedAnalysisSource, .onDevicePhotoSuggestion)
    XCTAssertEqual(record.originalAIJSON, raw)
    XCTAssertEqual(record.modelID, MockPhotoSuggestionEngine.identity.modelID)
    XCTAssertEqual(record.modelProvenanceJSON, draftReceiptJSON)
    XCTAssertEqual(record.blackAppearanceAnswer, .yes)
    XCTAssertEqual(record.blackTarry, SymptomFlag.no.rawValue)
    let accepted = try XCTUnwrap(record.confirmedEntrySnapshot)
    XCTAssertEqual(accepted.initiallyAcceptedBlackAppearance, .yes)
    XCTAssertEqual(accepted.personConfirmedBlackAppearance, .yes)
    XCTAssertEqual(accepted.initiallyAcceptedBlackTarry, .no)
    XCTAssertEqual(
      accepted.typedFieldProvenance[.blackAppearance],
      .acceptedUnchanged
    )
    XCTAssertTrue(
      accepted.typedFieldProvenance.values.allSatisfy {
        $0 == .acceptedUnchanged
      }
    )

    // A later edit changes only the final value and edit provenance. The
    // initially accepted V2 tuple and immutable engine receipt remain intact.
    var edit = EntryEditInput(entry: record)
    edit.blackAppearance = .no
    try harness.store.update(
      record,
      with: edit,
      baselineFingerprint: try EntryRecordFingerprint.make(for: record),
      at: Date(timeIntervalSince1970: 1_730_000_010)
    )
    let edited = try XCTUnwrap(record.confirmedEntrySnapshot)
    XCTAssertEqual(edited.initiallyAcceptedBlackAppearance, .yes)
    XCTAssertEqual(edited.personConfirmedBlackAppearance, .no)
    XCTAssertEqual(
      edited.typedFieldProvenance[.blackAppearance],
      .editedAfterConfirmation
    )
    XCTAssertEqual(record.originalAIJSON, raw)
    XCTAssertEqual(record.modelProvenanceJSON, draftReceiptJSON)

    let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let day = calendar.startOfDay(for: record.capturedAt)
    let export = try JournalExportSnapshotFactory.make(
      entries: [record],
      completions: [],
      treatmentEvents: [],
      range: .init(from: day, through: day),
      scope: .allEntries,
      generatedAt: day.addingTimeInterval(12 * 3_600),
      calendar: calendar,
      timeZone: zone
    )
    let pdf = try JournalPDFRenderer().render(
      snapshot: export,
      photoDirectory: harness.root.appendingPathComponent("Images")
    )
    let document = try XCTUnwrap(PDFDocument(data: pdf))
    let text = (0..<document.pageCount)
      .compactMap { document.page(at: $0)?.string }
      .joined(separator: "\n")
    XCTAssertTrue(
      text.contains(
        "On-device suggestion — possible unusually black appearance: Yes"
      )
    )
    XCTAssertTrue(
      text.contains("On-device suggestion — possible tar-like appearance: No")
    )
    XCTAssertTrue(
      text.contains("Accepted value — possible unusually black appearance: Yes")
    )
    XCTAssertTrue(
      text.contains("Accepted value — possible tar-like appearance: No")
    )
    XCTAssertTrue(
      text.contains("Final value — possible unusually black appearance: No")
    )
    XCTAssertTrue(
      text.contains("Final value — possible tar-like appearance: No")
    )
    XCTAssertEqual(text.components(separatedBy: "Photo included").count - 1, 1)
  }

  func testProviderNeutralV2AllThreeAppearanceFieldsDisplayNoAndAcceptUnchanged()
    async throws
  {
    // A fused model "no" for all three appearance fields displays as an
    // editable, visibly unconfirmed No and is preserved in provenance.
    let raw = """
      {"black_tarry_appearance":"no","schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":"dark_brown","red_appearing_material":"no","black_appearance":"no"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.redBlood, .no)
    XCTAssertEqual(harness.viewModel.blackAppearance, .no)
    XCTAssertEqual(harness.viewModel.blackTarry, .no)
    XCTAssertTrue(harness.viewModel.canSave)

    // Saving the untouched displayed values must record accepted-unchanged,
    // never a false "edited before confirmation" for the untouched fields.
    harness.viewModel.save()
    let record = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertEqual(record.originalAIJSON, raw)
    XCTAssertEqual(record.redBlood, SymptomFlag.no.rawValue)
    XCTAssertEqual(record.blackAppearanceAnswer, .no)
    XCTAssertEqual(record.blackTarry, SymptomFlag.no.rawValue)

    XCTAssertEqual(harness.viewModel.savedSafetyGuidance, .none)

    let accepted = try XCTUnwrap(record.confirmedEntrySnapshot)
    XCTAssertEqual(accepted.initiallyAcceptedRed, .no)
    XCTAssertEqual(accepted.initiallyAcceptedBlackAppearance, .no)
    XCTAssertEqual(accepted.initiallyAcceptedBlackTarry, .no)
    XCTAssertEqual(
      accepted.typedFieldProvenance[.redMaterial],
      .acceptedUnchanged
    )
    XCTAssertEqual(
      accepted.typedFieldProvenance[.blackAppearance],
      .acceptedUnchanged
    )
    XCTAssertEqual(
      accepted.typedFieldProvenance[.blackTarry],
      .acceptedUnchanged
    )

    // The raw fused canonical "no" for every field remains preserved,
    // untouched, in the receipts/originalValidatedJSON.
    XCTAssertTrue(record.originalAIJSON?.contains(
      "\"red_appearing_material\":\"no\""
    ) == true)
    XCTAssertTrue(record.originalAIJSON?.contains(
      "\"black_appearance\":\"no\""
    ) == true)
    XCTAssertTrue(record.originalAIJSON?.contains(
      "\"black_tarry_appearance\":\"no\""
    ) == true)
  }

  func testProviderNeutralV2PersonChangingSuggestedYesToNoRecordsEditedBeforeConfirmation()
    async throws
  {
    // Every AI suggestion remains editable before the one whole-entry save.
    let raw = """
      {"black_tarry_appearance":"no","schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":"dark_brown","red_appearing_material":"yes","black_appearance":"no"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)
    XCTAssertEqual(harness.viewModel.redBlood, .yes)

    harness.viewModel.redBlood = .no
    XCTAssertTrue(harness.viewModel.canSave)

    harness.viewModel.save()
    let record = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(record.redBlood, SymptomFlag.no.rawValue)
    XCTAssertEqual(record.originalAIJSON, raw)

    // `initiallyAcceptedRed` records the value confirmed at save in the V2
    // envelope; originalAIJSON and field provenance preserve that the person
    // changed the model's displayed Yes to No before confirmation.
    let accepted = try XCTUnwrap(record.confirmedEntrySnapshot)
    XCTAssertEqual(accepted.initiallyAcceptedRed, .no)
    XCTAssertEqual(accepted.personConfirmedRed, .no)
    XCTAssertEqual(
      accepted.typedFieldProvenance[.redMaterial],
      .editedBeforeConfirmation
    )
  }

  func testProviderNeutralV2PersonEditingRedToYesThenSavePersists()
    async throws
  {
    // Diagnostic regression for a physical-device report: the full journey
    // (real Qwen3 engine) reached review, the person edited the displayed
    // "possible red material" answer from Not sure to Yes, save became
    // enabled, was tapped, and `save()` threw -- surfacing only the generic
    // "Couldn't save this entry" message (the underlying
    // `error.localizedDescription` went to `statusMessage`, never shown).
    // This reproduces that exact device-captured validated V2 canonical
    // fixture through the provider-neutral mock, then performs the same
    // edit-then-save the person did, to see whether `save()` throws here too
    // and, if so, to capture the real underlying error text.
    let raw = """
      {"apparent_color":"brown","black_appearance":"not_sure","black_tarry_appearance":"not_sure","bristol_type":null,"form":"unable_to_assess","image_usable":true,"mixed_form":"not_sure","red_appearing_material":"no","retake_reason":null,"schema_version":"gi-photo-full-prefill-v2","stool_presence":"uncertain"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    // The model's negative red appearance suggestion displays as editable No;
    // the two uncertain black/tarry answers remain Not sure.
    XCTAssertEqual(harness.viewModel.redBlood, .no)
    XCTAssertEqual(harness.viewModel.blackAppearance, .unsure)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)

    // The person's deliberate edit: No -> Yes.
    harness.viewModel.redBlood = .yes
    XCTAssertTrue(harness.viewModel.canSave)

    // This is the exact entry point `save.tap()` invokes in the running app.
    harness.viewModel.save()

    if case .failed(_, let flowMessage) = harness.viewModel.flowState {
      XCTFail(
        """
        save() threw after editing red material to Yes on the device-captured \
        V2 fixture. flowState message: \(flowMessage). \
        statusMessage (underlying error.localizedDescription): \
        \(harness.viewModel.statusMessage ?? "<nil>")
        """
      )
      return
    }
    guard case .saved(let entryID) = harness.viewModel.flowState else {
      return XCTFail(
        "Expected .saved after editing red to Yes and saving, got \(harness.viewModel.flowState)."
      )
    }

    let record = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertEqual(record.id, entryID)
    XCTAssertEqual(record.originalAIJSON, raw)
    XCTAssertEqual(record.redBlood, SymptomFlag.yes.rawValue)

    let accepted = try XCTUnwrap(record.confirmedEntrySnapshot)
    XCTAssertEqual(accepted.personConfirmedRed, .yes)
    XCTAssertEqual(
      accepted.typedFieldProvenance[.redMaterial],
      .editedBeforeConfirmation
    )
  }

  func testProviderNeutralV2PersonSavingUneditedFusedUncertainFixturePersists()
    async throws
  {
    // Second diagnostic variant: the same device-captured V2 fixture, saved
    // with no edits (red No; black and tar-like Not sure).
    let raw = """
      {"apparent_color":"brown","black_appearance":"not_sure","black_tarry_appearance":"not_sure","bristol_type":null,"form":"unable_to_assess","image_usable":true,"mixed_form":"not_sure","red_appearing_material":"no","retake_reason":null,"schema_version":"gi-photo-full-prefill-v2","stool_presence":"uncertain"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.redBlood, .no)
    XCTAssertEqual(harness.viewModel.blackAppearance, .unsure)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)
    XCTAssertTrue(harness.viewModel.canSave)

    harness.viewModel.save()

    if case .failed(_, let flowMessage) = harness.viewModel.flowState {
      XCTFail(
        """
        save() threw on the device-captured V2 fixture with NO edits at all. \
        flowState message: \(flowMessage). \
        statusMessage (underlying error.localizedDescription): \
        \(harness.viewModel.statusMessage ?? "<nil>")
        """
      )
      return
    }
    guard case .saved = harness.viewModel.flowState else {
      return XCTFail(
        "Expected .saved for an unedited save of the device fixture, got \(harness.viewModel.flowState)."
      )
    }
    XCTAssertEqual(harness.store.records.count, 1)
  }

  /// Negative appearance output is displayed as an editable No with the
  /// exact appearance-only AI-suggestion copy.
  func testProviderNeutralV2NegativeAppearanceSuggestionsDisplayNoWithExactCopy()
    async throws
  {
    let raw = """
      {"apparent_color":null,"black_appearance":"no","black_tarry_appearance":"no","bristol_type":null,"form":"unable_to_assess","image_usable":true,"mixed_form":"not_sure","red_appearing_material":"no","retake_reason":null,"schema_version":"gi-photo-full-prefill-v2","stool_presence":"uncertain"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.redBlood, .no)
    XCTAssertEqual(harness.viewModel.blackAppearance, .no)
    XCTAssertEqual(harness.viewModel.blackTarry, .no)
    XCTAssertEqual(
      harness.viewModel.aiReadHints["redMaterial"],
      "AI suggestion: No blood-like red material detected in this photo."
    )
    XCTAssertEqual(
      harness.viewModel.aiReadHints["blackAppearance"],
      "AI suggestion: No black or tar-like appearance detected in this photo."
    )
    XCTAssertEqual(
      harness.viewModel.aiReadHints["blackTarry"],
      "AI suggestion: No black or tar-like appearance detected in this photo."
    )

    // Subject, Bristol, and mixed form are unqualified model heads by policy
    // (Qwen3DecomposedContract.forcedNotSureFields): only the static,
    // non-diagnostic reminder is ever shown for them, never a synthesized
    // value.
    let staticHint = "Photo AI cannot assess this yet — answer from what you saw."
    XCTAssertEqual(harness.viewModel.aiReadHints["bristol"], staticHint)
    XCTAssertEqual(harness.viewModel.aiReadHints["subject"], staticHint)
    XCTAssertEqual(harness.viewModel.aiReadHints["mixedForm"], staticHint)

    // apparent_color fused to nil, but this mock receipt never attaches
    // decomposedFieldProvenance, so the qualified-raw-color-read rule has no
    // evidence to surface and must not invent one.
    XCTAssertNil(harness.viewModel.aiReadHints["apparentColor"])

    XCTAssertTrue(harness.viewModel.canSave)
    harness.viewModel.save()

    guard case .saved = harness.viewModel.flowState else {
      return XCTFail(
        "Expected .saved after saving the unedited device fixture, got \(harness.viewModel.flowState)."
      )
    }
    // save() resets model-suggestion state as part of its committed-cleanup
    // path; every AI read hint must be cleared along with it.
    XCTAssertTrue(harness.viewModel.aiReadHints.isEmpty)
  }

  func testProviderNeutralV2PositiveAppearanceSuggestionsDisplayYesWithExactCopy() async throws {
    let raw = """
      {"apparent_color":null,"black_appearance":"yes","black_tarry_appearance":"yes","bristol_type":null,"form":"unable_to_assess","image_usable":true,"mixed_form":"not_sure","red_appearing_material":"yes","retake_reason":null,"schema_version":"gi-photo-full-prefill-v2","stool_presence":"uncertain"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.redBlood, .yes)
    XCTAssertEqual(harness.viewModel.blackAppearance, .yes)
    XCTAssertEqual(harness.viewModel.blackTarry, .yes)
    XCTAssertEqual(
      harness.viewModel.aiReadHints["redMaterial"],
      "AI suggestion: Possible blood-like red material is visible."
    )
    XCTAssertEqual(
      harness.viewModel.aiReadHints["blackAppearance"],
      "AI suggestion: Possible black or tar-like appearance is visible."
    )
    XCTAssertEqual(
      harness.viewModel.aiReadHints["blackTarry"],
      "AI suggestion: Possible black or tar-like appearance is visible."
    )
  }

  func testProviderNeutralV2MixedAppearanceSuggestionsEditOnceSaveAndPDFUsePersonValues()
    async throws
  {
    // One response deliberately exercises the complete visible tri-state:
    // red Yes, unusually black No, and tar-like Not sure.
    let raw = """
      {"apparent_color":null,"black_appearance":"no","black_tarry_appearance":"not_sure","bristol_type":null,"form":"unable_to_assess","image_usable":true,"mixed_form":"not_sure","red_appearing_material":"yes","retake_reason":null,"schema_version":"gi-photo-full-prefill-v2","stool_presence":"uncertain"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.redBlood, .yes)
    XCTAssertEqual(harness.viewModel.blackAppearance, .no)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)
    XCTAssertEqual(
      harness.viewModel.aiReadHints["redMaterial"],
      "AI suggestion: Possible blood-like red material is visible."
    )
    XCTAssertEqual(
      harness.viewModel.aiReadHints["blackAppearance"],
      "AI suggestion: No black or tar-like appearance detected in this photo."
    )
    XCTAssertEqual(
      harness.viewModel.aiReadHints["blackTarry"],
      "AI suggestion: Unable to determine whether a black or tar-like appearance is visible."
    )

    // Every suggestion stays editable. These three edits are adopted together
    // by the same single whole-entry save action.
    harness.viewModel.redBlood = .no
    harness.viewModel.blackAppearance = .yes
    harness.viewModel.blackTarry = .no
    XCTAssertTrue(harness.viewModel.canSave)
    XCTAssertTrue(harness.store.records.isEmpty)

    harness.viewModel.save()

    XCTAssertEqual(harness.store.records.count, 1)
    guard case .saved = harness.viewModel.flowState else {
      return XCTFail("The single final confirmation must save the complete displayed entry.")
    }
    let record = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(record.redBlood, SymptomFlag.no.rawValue)
    XCTAssertEqual(record.blackAppearanceAnswer, .yes)
    XCTAssertEqual(record.blackTarry, SymptomFlag.no.rawValue)
    let confirmation = try XCTUnwrap(record.confirmedEntrySnapshot)
    XCTAssertEqual(confirmation.personConfirmedRed, .no)
    XCTAssertEqual(confirmation.personConfirmedBlackAppearance, .yes)
    XCTAssertEqual(confirmation.personConfirmedBlackTarry, .no)
    XCTAssertEqual(
      confirmation.typedFieldProvenance[.redMaterial],
      .editedBeforeConfirmation
    )
    XCTAssertEqual(
      confirmation.typedFieldProvenance[.blackAppearance],
      .editedBeforeConfirmation
    )
    XCTAssertEqual(
      confirmation.typedFieldProvenance[.blackTarry],
      .editedBeforeConfirmation
    )

    let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let day = calendar.startOfDay(for: record.capturedAt)
    let export = try JournalExportSnapshotFactory.make(
      entries: [record],
      completions: [],
      treatmentEvents: [],
      range: .init(from: day, through: day),
      scope: .allEntries,
      generatedAt: day.addingTimeInterval(12 * 3_600),
      calendar: calendar,
      timeZone: zone
    )
    let pdf = try JournalPDFRenderer().render(
      snapshot: export,
      photoDirectory: harness.root.appendingPathComponent("Images")
    )
    let document = try XCTUnwrap(PDFDocument(data: pdf))
    let text = (0..<document.pageCount)
      .compactMap { document.page(at: $0)?.string }
      .joined(separator: "\n")
    XCTAssertTrue(text.contains("On-device suggestion — possible red appearance: Yes"))
    XCTAssertTrue(text.contains("On-device suggestion — possible unusually black appearance: No"))
    XCTAssertTrue(text.contains("On-device suggestion — possible tar-like appearance: Not sure"))
    XCTAssertTrue(text.contains("Accepted value — possible red/blood-like appearance: No"))
    XCTAssertTrue(text.contains("Accepted value — possible unusually black appearance: Yes"))
    XCTAssertTrue(text.contains("Accepted value — possible tar-like appearance: No"))
    XCTAssertTrue(text.contains("Final value — possible red/blood-like appearance: No"))
    XCTAssertTrue(text.contains("Final value — possible unusually black appearance: Yes"))
    XCTAssertTrue(text.contains("Final value — possible tar-like appearance: No"))
    XCTAssertEqual(text.components(separatedBy: "Photo included").count - 1, 1)
  }

  /// Diagnostic regression for the physical-device E2E save failure
  /// (invalidEntryProvenance, E2E run 13): receipt validation recomputes
  /// latencyMilliseconds from startedAt/endedAt and requires exact equality,
  /// and save-time validation runs on a receipt decoded from canonicalJSON.
  /// The former whole-second ISO-8601 date encoding truncated fractional
  /// seconds, so any receipt with realistic sub-second timings passed
  /// validation in memory at analysis time and then failed it after the
  /// canonical round trip at save time. Every earlier fixture dodged this by
  /// using startedAt == endedAt on a whole second with latency 0, as real
  /// timed runs never do.
  func testEngineReceiptWithFractionalSecondTimingsSurvivesCanonicalRoundTrip()
    throws
  {
    let raw =
      "{\"apparent_color\":\"brown\",\"black_appearance\":\"not_sure\",\"black_tarry_appearance\":\"not_sure\",\"bristol_type\":null,\"form\":\"unable_to_assess\",\"image_usable\":true,\"mixed_form\":\"not_sure\",\"red_appearing_material\":\"no\",\"retake_reason\":null,\"schema_version\":\"gi-photo-full-prefill-v2\",\"stool_presence\":\"uncertain\"}"
    let rawOutputUTF8 = Data(raw.utf8)
    let canonical = try PhotoSuggestionPayloadV2Parser.canonicalJSON(
      PhotoSuggestionPayloadV2Parser.parse(raw)
    )
    let startedAt = Date(timeIntervalSinceReferenceDate: 777_000_123.417)
    let endedAt = startedAt.addingTimeInterval(23.719)
    let receipt = PhotoSuggestionEngineReceipt(
      requestID: UUID(),
      identity: MockPhotoSuggestionEngine.identity,
      analyzedImageSHA256: String(repeating: "d", count: 64),
      analyzedPixelWidth: 512,
      analyzedPixelHeight: 512,
      startedAt: startedAt,
      endedAt: endedAt,
      latencyMilliseconds: Int(
        (endedAt.timeIntervalSince(startedAt) * 1_000).rounded()
      ),
      rawOutputUTF8Base64: rawOutputUTF8.base64EncodedString(),
      rawOutputUTF8SHA256: SHA256.hash(data: rawOutputUTF8)
        .map { String(format: "%02x", $0) }.joined(),
      rawOutputUTF8ByteCount: rawOutputUTF8.count,
      canonicalParsedJSON: canonical,
      modelCallCount: 1,
      repairCallCount: 0
    )
    XCTAssertNoThrow(try receipt.validate(rawOutputUTF8: rawOutputUTF8))

    let canonicalJSON = try XCTUnwrap(receipt.canonicalJSON)
    let decoded = try PhotoSuggestionEngineReceipt.decode(canonicalJSON)
    XCTAssertNoThrow(
      try decoded.validate(rawOutputUTF8: rawOutputUTF8),
      "A decoded receipt must satisfy the same validation as the in-memory receipt it was encoded from."
    )
    XCTAssertEqual(
      decoded.canonicalJSON, canonicalJSON,
      "canonicalJSON must be stable across a decode round trip; the store compares it byte-for-byte."
    )
    XCTAssertEqual(decoded.startedAt, startedAt)
    XCTAssertEqual(decoded.endedAt, endedAt)
  }

  /// Decomposed twin of `testEngineReceiptWithFractionalSecondTimingsSurvivesCanonicalRoundTrip`.
  /// `validate(rawOutputUTF8:)` has two branches: the `decomposedFieldProvenance == nil`
  /// branch exercised above, and `validateDecomposed` (~20 invariants) -- the branch every
  /// real on-device save takes, since a completed run always populates
  /// `decomposedFieldProvenance` (only historical/legacy fixtures leave it nil). Two other
  /// tests already build a decomposed receipt via `decomposedPhotoSuggestionReceiptFixture()`
  /// (`testDecomposedPhotoSuggestionReceiptRoundTripsWithSeparateFieldEvidence` and
  /// `testDecomposedPhotoSuggestionReceiptRejectsContractViolations`), but both use
  /// `startedAt == endedAt` on a whole second with latency 0 -- exactly the fixture shape
  /// that let the whole-second ISO-8601 date-truncation bug ship undetected in the nil
  /// branch before `canonicalJSON` switched to `.deferredToDate` (see the comment on that
  /// property). Neither existing decomposed test would have caught a regression back to
  /// whole-second date encoding, because zero fractional seconds survives truncation
  /// trivially. This test builds a fully valid decomposed receipt -- mirroring
  /// `Qwen3HybridPhotoSuggestionEngine.buildRun`/`makeRunEvidence`'s real construction of
  /// the seven per-field records, run evidence, fusion, and provenance -- with realistic
  /// fractional-second `startedAt`/`endedAt`, so a regression in either encoding strategy is
  /// caught on the branch every real device save actually takes.
  func testDecomposedEngineReceiptValidatesAndSurvivesCanonicalRoundTrip()
    throws
  {
    let requestID = UUID()
    let imageSHA256 = String(repeating: "1", count: 64)
    let tensorSHA256 = String(repeating: "2", count: 64)

    // One rawText label per Qwen3DecomposedField.allCases, each of which
    // Qwen3DecomposedLabelParser.parse(_:for:) reproduces as the stored
    // parsed label (mirrors the engine's per-field prompt/response loop).
    let rawTextByField: [Qwen3DecomposedField: String] = [
      .subject: "stool", .bristol: "4", .mixed: "no", .color: "brown",
      .red: "yes", .black: "yes", .glossy: "yes",
    ]
    XCTAssertEqual(Set(rawTextByField.keys), Set(Qwen3DecomposedField.allCases))

    let fields: [Qwen3DecomposedRawFieldRecord] = Qwen3DecomposedField.allCases
      .enumerated().map { index, field in
        let text = rawTextByField[field]!
        let bytes = Data(text.utf8)
        return Qwen3DecomposedRawFieldRecord(
          field: field,
          prompt: field.prompt,
          promptSHA256: Qwen3DecomposedContract.promptSHA256(for: field),
          analyzedImageSHA256: imageSHA256,
          preparedTensorSHA256: tensorSHA256,
          rawTokenIDs: [index + 1],
          rawText: text,
          rawUTF8Base64: bytes.base64EncodedString(),
          rawUTF8SHA256: hexSHA256(bytes),
          parsed: Qwen3DecomposedLabelParser.parse(text, for: field),
          qualified: Qwen3DecomposedContract.qualifiedFields.contains(field),
          generationCacheID: "\(requestID.uuidString)-nil-cache-\(index + 1)",
          usedFreshGenerationCache: true,
          stopReason: "eos",
          latencyMilliseconds: index,
          mlxActiveMemoryBytes: 1_000 + index,
          mlxCacheMemoryBytes: 2_000 + index,
          mlxPeakMemoryBytes: 3_000 + index,
          hostPeakRSSBytes: 4_000 + index,
          modelCallOrdinal: index + 1
        )
      }
    XCTAssertEqual(Set(fields.map(\.generationCacheID)).count, fields.count)

    let pixelEvidence = try decomposedPixelEvidenceFixture()
    XCTAssertEqual(pixelEvidence.schemaVersion, HybridPixelEvidence.schemaVersion)
    XCTAssertEqual(pixelEvidence.thresholdVersion, HybridPixelEvidence.thresholdVersion)

    let runEvidence = Qwen3DecomposedRunEvidence(
      analyzedImageSHA256: imageSHA256,
      preparedTensorSHA256: tensorSHA256,
      pixelEvidence: pixelEvidence,
      fields: fields
    )
    XCTAssertNoThrow(try runEvidence.validate())

    let fused = try Qwen3DecomposedFusion.fuse(runEvidence)
    let rawOutputUTF8 = Data(fused.canonicalV2JSON.utf8)

    let provenance = PhotoSuggestionDecomposedProvenance(
      runEvidence: runEvidence,
      qualificationVersion: Qwen3DecomposedContract.qualificationPolicyVersion,
      fusionVersion: Qwen3DecomposedFusion.fusionVersion,
      fusedCanonicalJSON: fused.canonicalV2JSON
    )

    // Realistic fractional-second timings, as every real timed run has --
    // never startedAt == endedAt on a whole second.
    let startedAt = Date(timeIntervalSinceReferenceDate: 888_000_456.183)
    let endedAt = startedAt.addingTimeInterval(31.457)

    let receipt = PhotoSuggestionEngineReceipt(
      requestID: requestID,
      identity: PhotoSuggestionEngineIdentity(
        providerID: "qwen3-test-provider",
        modelID: "qwen3-test-model",
        modelRevision: "test-revision",
        modelArtifactSHA256: String(repeating: "3", count: 64),
        runtimeID: "mlx-test-runtime",
        runtimeVersion: "1",
        promptVersion: Qwen3DecomposedContract.promptSetVersion,
        promptSHA256: Qwen3DecomposedContract.promptSetSHA256,
        parserVersion: Qwen3DecomposedContract.parserVersion,
        schemaVersion: PhotoSuggestionPayloadV2.schemaVersion,
        preprocessingVersion: "qwen3-preprocess-v1",
        analysisPipelineVersion: "qwen3-decomposed-pipeline-v1"
      ),
      analyzedImageSHA256: imageSHA256,
      analyzedPixelWidth: 512,
      analyzedPixelHeight: 512,
      startedAt: startedAt,
      endedAt: endedAt,
      latencyMilliseconds: Int(
        (endedAt.timeIntervalSince(startedAt) * 1_000).rounded()
      ),
      rawOutputUTF8Base64: rawOutputUTF8.base64EncodedString(),
      rawOutputUTF8SHA256: hexSHA256(rawOutputUTF8),
      rawOutputUTF8ByteCount: rawOutputUTF8.count,
      canonicalParsedJSON: fused.canonicalV2JSON,
      modelCallCount: Qwen3DecomposedField.allCases.count,
      repairCallCount: 0,
      decomposedFieldProvenance: provenance
    )
    XCTAssertNoThrow(try receipt.validate(rawOutputUTF8: rawOutputUTF8))

    let canonicalJSON = try XCTUnwrap(receipt.canonicalJSON)
    let decoded = try PhotoSuggestionEngineReceipt.decode(canonicalJSON)
    XCTAssertNoThrow(
      try decoded.validate(rawOutputUTF8: rawOutputUTF8),
      "A decoded decomposed receipt must satisfy the same validateDecomposed invariants as the in-memory receipt it was encoded from."
    )
    XCTAssertEqual(
      decoded.canonicalJSON, canonicalJSON,
      "canonicalJSON must be stable across a decode round trip; the store compares it byte-for-byte."
    )
  }

  func testProviderNeutralV2InvalidOutputFallsBackOnceWithoutModelProvenance()
    async throws
  {
    let engine = MockPhotoSuggestionEngine(mode: .failure(.invalidOutput))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    let callCounts = await engine.counts()
    XCTAssertEqual(callCounts, .init(prepare: 1, suggest: 1, cancel: 0))
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("An invalid one-shot output must enter manual review.")
    }
    XCTAssertNotNil(harness.viewModel.currentDraftURL)
    XCTAssertEqual(harness.viewModel.analysisSource, .manual)
    XCTAssertEqual(harness.viewModel.confirmedStoolPresence, .uncertain)
    XCTAssertNil(harness.viewModel.confirmedBristolType)
    XCTAssertEqual(harness.viewModel.confirmedForm, "unable_to_assess")
    XCTAssertEqual(harness.viewModel.mixedForm, .unsure)
    XCTAssertEqual(harness.viewModel.apparentColor, "unable_to_assess")
    XCTAssertEqual(harness.viewModel.redBlood, .unsure)
    XCTAssertEqual(harness.viewModel.blackAppearance, .unsure)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)
    XCTAssertNil(harness.viewModel.confirmedPhotoUsable)
    XCTAssertFalse(harness.viewModel.canSave)

    harness.viewModel.updateConfirmedPhotoUsable(true)
    XCTAssertTrue(harness.viewModel.canSave)
    harness.viewModel.save()
    let record = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(record.savedAnalysisSource, .manual)
    XCTAssertEqual(record.provenance, EntryProvenance.manual.rawValue)
    XCTAssertNil(record.originalAIJSON)
    XCTAssertNil(record.modelID)
    XCTAssertNil(record.modelProvenanceJSON)
    let confirmation = try XCTUnwrap(record.confirmedEntrySnapshot)
    XCTAssertNil(confirmation.initiallyAcceptedBlackAppearance)
    XCTAssertEqual(confirmation.personConfirmedBlackAppearance, .unsure)
    XCTAssertTrue(
      confirmation.typedFieldProvenance.values.allSatisfy {
        $0 == .manualNoSuggestion
      }
    )
  }

  func testProviderNeutralV2TimeoutFallsBackWithoutModelProvenance()
    async throws
  {
    let engine = MockPhotoSuggestionEngine(mode: .failure(.timedOut))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForAutomaticAnalysis(harness.viewModel)

    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 1, suggest: 1, cancel: 0))
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A timed-out one-shot provider must enter manual review.")
    }
    XCTAssertEqual(harness.viewModel.analysisSource, .manual)
    XCTAssertEqual(harness.viewModel.confirmedStoolPresence, .uncertain)
    XCTAssertEqual(harness.viewModel.blackAppearance, .unsure)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)
  }

  func testProviderNeutralV2ReceiptRequestPhotoAndDimensionMutationsFailClosed()
    async throws
  {
    let raw = """
      {"black_tarry_appearance":"no","schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":"dark_brown","red_appearing_material":"yes","black_appearance":"yes"}
      """
    let mutations: [MockPhotoSuggestionEngine.ReceiptMutation] = [
      .requestID,
      .imageSHA256,
      .pixelWidth,
      .pixelHeight,
    ]
    for mutation in mutations {
      let engine = MockPhotoSuggestionEngine(
        mode: .successWithReceiptMutation(raw, mutation)
      )
      let harness = try makeHarness(
        photoSuggestionEngine: engine,
        modelReady: false,
        descriptor: nil,
        autoAnalysisEnabled: true
      )
      defer { harness.cleanup() }

      await harness.viewModel.startAutomaticPreparation()
      try harness.viewModel.prepareImageData(imageData())
      await waitForAutomaticAnalysis(harness.viewModel)

      let counts = await engine.counts()
      XCTAssertEqual(counts, .init(prepare: 1, suggest: 1, cancel: 0))
      guard case .manual = harness.viewModel.flowState else {
        return XCTFail("A receipt/input association mutation must fail closed.")
      }
      XCTAssertEqual(harness.viewModel.analysisSource, .manual)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let snapshot = try decoder.decode(
        DraftSnapshot.self,
        from: Data(contentsOf: harness.root.appendingPathComponent(
          "Drafts/active-draft.v1.json"
        ))
      )
      XCTAssertNil(snapshot.originalValidatedJSON)
      XCTAssertNil(snapshot.photoSuggestionEngineReceiptJSON)
    }
  }

  func testProviderNeutralV2BackgroundCancelIgnoresLateResultAndRetriesFresh()
    async throws
  {
    let raw = """
      {"black_tarry_appearance":"no","schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":"dark_brown","red_appearing_material":"yes","black_appearance":"yes"}
      """
    let engine = DelayedPhotoSuggestionEngine()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      analysisTimeout: .seconds(5),
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForReading(harness.viewModel)
    for _ in 0..<100 {
      if (await engine.counts()).suggest >= 1 { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let firstStartedCounts = await engine.counts()
    XCTAssertEqual(firstStartedCounts.suggest, 1)

    harness.viewModel.handleAppBecameInactive()
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Backgrounding during reading must enter manual review.")
    }
    for _ in 0..<100 {
      if (await engine.counts()).cancel >= 1 { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let cancelledCounts = await engine.counts()
    XCTAssertEqual(cancelledCounts.cancel, 1)

    await engine.complete(callIndex: 0, raw: raw)
    await waitForAnalysis(harness.viewModel)
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("The cancelled late result must not reopen model review.")
    }
    XCTAssertEqual(harness.viewModel.analysisSource, .manual)
    XCTAssertEqual(harness.viewModel.blackAppearance, .unsure)

    harness.viewModel.retryAnalysis()
    await waitForReading(harness.viewModel)
    for _ in 0..<100 {
      if (await engine.counts()).suggest >= 2 { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let retryStartedCounts = await engine.counts()
    XCTAssertEqual(retryStartedCounts.suggest, 2)
    await engine.complete(callIndex: 1, raw: raw)
    await waitForAutomaticAnalysis(harness.viewModel)

    XCTAssertEqual(harness.viewModel.analysisSource, .onDevicePhotoSuggestion)
    XCTAssertEqual(harness.viewModel.blackAppearance, .yes)
    XCTAssertEqual(harness.viewModel.blackTarry, .no)
    XCTAssertEqual(
      harness.viewModel.aiReadHints["blackTarry"],
      "AI suggestion: No black or tar-like appearance detected in this photo."
    )
    let finalCounts = await engine.counts()
    XCTAssertEqual(finalCounts, .init(prepare: 1, suggest: 2, cancel: 1))
    let requestIDs = await engine.requestIDs()
    guard requestIDs.count == 2 else {
      return XCTFail("Retry must issue exactly one fresh provider request.")
    }
    XCTAssertNotEqual(requestIDs[0], requestIDs[1])
  }

  func testProviderNeutralPreparationBackgroundRejectsLateSuccessWithoutSuggestion()
    async throws
  {
    let engine = DelayedPreparationPhotoSuggestionEngine()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    await waitForPreparationStart(engine)
    guard case .reading = harness.viewModel.flowState else {
      return XCTFail("Preparation must retain the photo at the automatic boundary.")
    }

    harness.viewModel.handleAppBecameInactive()
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Backgrounding during preparation must open manual entry immediately.")
    }
    harness.viewModel.note = "Keep this person-entered note."
    let manualStatus = harness.viewModel.statusMessage

    await engine.completePreparation()
    try? await Task.sleep(for: .milliseconds(30))

    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Late preparation success must not reopen model review.")
    }
    XCTAssertEqual(harness.viewModel.analysisSource, .manual)
    XCTAssertEqual(harness.viewModel.note, "Keep this person-entered note.")
    XCTAssertEqual(harness.viewModel.statusMessage, manualStatus)
    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 1, suggest: 0, cancel: 0))
  }

  func testProviderNeutralPreparationBackgroundRejectsLateFailure()
    async throws
  {
    let engine = DelayedPreparationPhotoSuggestionEngine()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    await waitForPreparationStart(engine)
    harness.viewModel.handleAppBecameInactive()
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Backgrounding during preparation must open manual entry immediately.")
    }
    harness.viewModel.note = "Manual work survives the late failure."
    let manualStatus = harness.viewModel.statusMessage

    await engine.failPreparation()
    try? await Task.sleep(for: .milliseconds(30))

    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Late preparation failure must not replace manual entry.")
    }
    XCTAssertEqual(harness.viewModel.analysisSource, .manual)
    XCTAssertEqual(harness.viewModel.note, "Manual work survives the late failure.")
    XCTAssertEqual(harness.viewModel.statusMessage, manualStatus)
    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 1, suggest: 0, cancel: 0))
  }

  func testProviderNeutralPreparationDeadlineKeepsPhotoManualAndRejectsLateCompletion()
    async throws
  {
    let engine = DelayedPreparationPhotoSuggestionEngine()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      preparationTimeout: .milliseconds(25),
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    await waitForPreparationStart(engine)
    for _ in 0..<100 {
      if case .manual = harness.viewModel.flowState { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let retainedPhoto = try XCTUnwrap(harness.viewModel.currentDraftURL)
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Preparation deadline must open retained-photo manual entry.")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: retainedPhoto.path))
    let deadlineStatus = harness.viewModel.statusMessage

    await engine.completePreparation()
    try? await Task.sleep(for: .milliseconds(30))

    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Late completion after the deadline must stay quarantined.")
    }
    XCTAssertEqual(harness.viewModel.currentDraftURL, retainedPhoto)
    XCTAssertEqual(harness.viewModel.statusMessage, deadlineStatus)
    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 1, suggest: 0, cancel: 0))
  }

  func testProviderNeutralPreparationHandoffCannotReopenManualFallback()
    async throws
  {
    let engine = DelayedPreparationPhotoSuggestionEngine()
    let handoff = DelayedPreparationHandoff()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      preparationHandoff: { await handoff.wait() },
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    await waitForPreparationStart(engine)
    await engine.completePreparation()
    for _ in 0..<100 {
      if await handoff.hasStarted() { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let handoffStarted = await handoff.hasStarted()
    XCTAssertTrue(handoffStarted)

    harness.viewModel.handleAppBecameInactive()
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Backgrounding must win before a delayed automatic handoff.")
    }
    harness.viewModel.note = "Manual fallback wins."
    let manualStatus = harness.viewModel.statusMessage

    await handoff.release()
    try? await Task.sleep(for: .milliseconds(30))

    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A stale handoff must not resurrect Reading after manual fallback.")
    }
    XCTAssertFalse(harness.viewModel.isBusy)
    XCTAssertEqual(harness.viewModel.note, "Manual fallback wins.")
    XCTAssertEqual(harness.viewModel.statusMessage, manualStatus)
    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 1, suggest: 0, cancel: 0))
  }

  func testQueuedDirectAndRetryAutomaticStartsCannotReopenManualFallback()
    async throws
  {
    let engine = MockPhotoSuggestionEngine(mode: .failure(.invalidOutput))
    let handoff = DelayedPreparationHandoff()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: true,
      automaticAnalysisHandoff: { await handoff.wait() },
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    for _ in 0..<100 {
      if await handoff.hasStarted() { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let directHandoffStarted = await handoff.hasStarted()
    XCTAssertTrue(directHandoffStarted)

    harness.viewModel.handleAppBecameInactive()
    harness.viewModel.note = "Manual fallback wins every queued start."
    await handoff.release()
    try? await Task.sleep(for: .milliseconds(30))

    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A direct queued start must not restore Reading after backgrounding.")
    }

    harness.viewModel.retryAnalysis()
    for _ in 0..<100 {
      if await handoff.hasStarted(count: 2) { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let retryHandoffStarted = await handoff.hasStarted(count: 2)
    XCTAssertTrue(retryHandoffStarted)

    harness.viewModel.handleAppBecameInactive()
    await handoff.release()
    try? await Task.sleep(for: .milliseconds(30))

    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A retry queued start must not restore Reading after backgrounding.")
    }
    XCTAssertFalse(harness.viewModel.isBusy)
    XCTAssertEqual(harness.viewModel.note, "Manual fallback wins every queued start.")
    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 0, suggest: 0, cancel: 0))
  }

  func testBackgroundDuringDelayedPhotoTransferInstallsManualPhotoWithoutAnalysis()
    async throws
  {
    let raw = """
      {"black_tarry_appearance":"no","schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":"dark_brown","red_appearing_material":"yes","black_appearance":"yes"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let transfer = DelayedPhotoTransfer()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    let loadTask = Task {
      await harness.viewModel.loadPhotoDataForTesting { try await transfer.load() }
    }
    for _ in 0..<100 {
      if await transfer.hasStarted() { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let transferStarted = await transfer.hasStarted()
    XCTAssertTrue(transferStarted)

    harness.viewModel.handleAppBecameInactive()
    guard case .manual(let draftID) = harness.viewModel.flowState, draftID == nil else {
      return XCTFail("An interrupted transfer must first open a no-photo manual draft.")
    }
    let manualCapturedAt = Date(timeIntervalSince1970: 1_734_000_000)
    harness.viewModel.capturedAt = manualCapturedAt
    harness.viewModel.note = "Do not overwrite this manual draft."
    await transfer.complete(imageData())
    await loadTask.value

    guard case .manual(let draftID) = harness.viewModel.flowState,
      draftID != nil
    else {
      return XCTFail("The eventual selected photo must remain in manual entry.")
    }
    XCTAssertNotNil(harness.viewModel.currentDraftURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(harness.viewModel.currentDraftURL).path))
    XCTAssertEqual(harness.viewModel.analysisSource, .manual)
    XCTAssertEqual(harness.viewModel.capturedAt, manualCapturedAt)
    XCTAssertEqual(harness.viewModel.note, "Do not overwrite this manual draft.")
    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 0, suggest: 0, cancel: 0))
  }

  func testSaveRevokesDelayedTransferBeforeCleanupFailureAndRetry()
    async throws
  {
    let removalFault = DraftRemovalFault()
    removalFault.shouldFail = true
    let engine = MockPhotoSuggestionEngine(mode: .failure(.invalidOutput))
    let transfer = DelayedPhotoTransfer()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: false,
      snapshotItemRemover: { url in try removalFault.remove(url) }
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData(color: .brown))
    harness.viewModel.enterManualMode()
    harness.viewModel.note = "Freeze this exact retry draft."
    let originalDraftURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let originalHash = hexSHA256(try Data(contentsOf: originalDraftURL))

    let delayedLoad = Task {
      await harness.viewModel.loadPhotoDataForTesting { try await transfer.load() }
    }
    for _ in 0..<100 {
      if await transfer.hasStarted() { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let transferStarted = await transfer.hasStarted()
    XCTAssertTrue(transferStarted)

    harness.viewModel.handleAppBecameInactive()
    harness.viewModel.updateStoolPresence(.stool)
    harness.viewModel.updateConfirmedBristolType(4)
    harness.viewModel.updateConfirmedPhotoUsable(true)
    harness.viewModel.updateApparentColor("brown")
    harness.viewModel.blackAppearance = .no
    completeRequiredContext(harness.viewModel)
    XCTAssertTrue(harness.viewModel.canSave)

    harness.viewModel.save()

    XCTAssertEqual(harness.store.records.count, 1)
    guard case .failed = harness.viewModel.flowState else {
      return XCTFail("A cleanup failure must leave the committed draft retryable.")
    }
    let snapshotURL = harness.root.appendingPathComponent("Drafts/active-draft.v1.json")
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let pendingSnapshot = try decoder.decode(DraftSnapshot.self, from: Data(contentsOf: snapshotURL))
    let pendingID = try XCTUnwrap(pendingSnapshot.pendingEntryID)
    let pendingFingerprint = try XCTUnwrap(pendingSnapshot.pendingEntryFingerprint)
    XCTAssertEqual(harness.store.records.first?.id, pendingID)

    await transfer.complete(imageData(color: .green))
    await delayedLoad.value

    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertEqual(harness.viewModel.currentDraftURL, originalDraftURL)
    XCTAssertEqual(hexSHA256(try Data(contentsOf: originalDraftURL)), originalHash)
    XCTAssertEqual(harness.viewModel.note, "Freeze this exact retry draft.")
    let preservedSnapshot = try decoder.decode(DraftSnapshot.self, from: Data(contentsOf: snapshotURL))
    XCTAssertEqual(preservedSnapshot.pendingEntryID, pendingID)
    XCTAssertEqual(preservedSnapshot.pendingEntryFingerprint, pendingFingerprint)
    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 0, suggest: 0, cancel: 0))

    removalFault.shouldFail = false
    harness.viewModel.retrySave()

    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertEqual(harness.store.records.first?.id, pendingID)
    XCTAssertNil(harness.viewModel.currentDraftURL)
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
  }

  func testDirectReplacementRevokesBackgroundedTransferBeforeItsLateCompletion()
    async throws
  {
    let raw = """
      {"black_tarry_appearance":"no","schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":"dark_brown","red_appearing_material":"yes","black_appearance":"yes"}
      """
    let engine = MockPhotoSuggestionEngine(mode: .success(raw))
    let transfer = DelayedPhotoTransfer()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: false
    )
    defer { harness.cleanup() }

    let delayedLoad = Task {
      await harness.viewModel.loadPhotoDataForTesting { try await transfer.load() }
    }
    for _ in 0..<100 {
      if await transfer.hasStarted() { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let transferStarted = await transfer.hasStarted()
    XCTAssertTrue(transferStarted)
    harness.viewModel.handleAppBecameInactive()

    try harness.viewModel.prepareImageData(imageData(color: .orange))
    harness.viewModel.enterManualMode()
    harness.viewModel.note = "Replacement manual note"
    harness.viewModel.updateConfirmedBristolType(4)
    harness.viewModel.updateMixedForm(.no)
    harness.viewModel.updateConfirmedPhotoUsable(true)
    let replacementURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let replacementHash = SHA256.hash(data: try Data(contentsOf: replacementURL))
      .map { String(format: "%02x", $0) }
      .joined()

    await transfer.complete(imageData(color: .brown))
    await delayedLoad.value

    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A stale transfer must not replace the newer manual draft.")
    }
    XCTAssertEqual(harness.viewModel.currentDraftURL, replacementURL)
    let finalHash = SHA256.hash(data: try Data(contentsOf: replacementURL))
      .map { String(format: "%02x", $0) }
      .joined()
    XCTAssertEqual(finalHash, replacementHash)
    XCTAssertEqual(harness.viewModel.note, "Replacement manual note")
    XCTAssertEqual(harness.viewModel.confirmedBristolType, 4)
    XCTAssertEqual(harness.viewModel.mixedForm, .no)
    XCTAssertEqual(harness.viewModel.confirmedPhotoUsable, true)
    XCTAssertEqual(harness.viewModel.analysisSource, .manual)
    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 0, suggest: 0, cancel: 0))
  }

  func testBackgroundedReplacementFailureRestoresOldPhotoReviewAnswers()
    async throws
  {
    let engine = MockPhotoSuggestionEngine(mode: .failure(.invalidOutput))
    let transfer = DelayedPhotoTransfer()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: false
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData(color: .brown))
    harness.viewModel.enterManualMode()
    harness.viewModel.capturedAt = Date(timeIntervalSince1970: 1_735_000_000)
    harness.viewModel.note = "Keep non-photo context."
    harness.viewModel.updateConfirmedBristolType(4)
    harness.viewModel.updateMixedForm(.no)
    harness.viewModel.updateConfirmedPhotoUsable(true)
    harness.viewModel.redBlood = .yes
    harness.viewModel.blackAppearance = .no
    harness.viewModel.blackTarry = .yes
    let oldURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let oldHash = hexSHA256(try Data(contentsOf: oldURL))

    let delayedLoad = Task {
      await harness.viewModel.loadPhotoDataForTesting { try await transfer.load() }
    }
    for _ in 0..<100 {
      if await transfer.hasStarted() { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let transferStarted = await transfer.hasStarted()
    XCTAssertTrue(transferStarted)

    harness.viewModel.handleAppBecameInactive()
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Backgrounding must establish retained-photo manual review.")
    }
    // These edits happen after the privacy-boundary transition. A late
    // invalid transfer must roll back to them, not to the pre-transfer form.
    harness.viewModel.note = "Post-background retained-photo edits."
    harness.viewModel.updateConfirmedPhotoUsable(true)
    harness.viewModel.updateConfirmedBristolType(5)
    harness.viewModel.updateMixedForm(.no)
    harness.viewModel.redBlood = .no
    harness.viewModel.blackAppearance = .yes
    harness.viewModel.blackTarry = .unsure
    let manualStatus = harness.viewModel.statusMessage
    await transfer.complete(Data([0x00]))
    await delayedLoad.value

    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A failed replacement must leave the old photo in manual review.")
    }
    XCTAssertFalse(harness.viewModel.isBusy)
    XCTAssertEqual(harness.viewModel.currentDraftURL, oldURL)
    XCTAssertEqual(hexSHA256(try Data(contentsOf: oldURL)), oldHash)
    XCTAssertEqual(harness.viewModel.note, "Post-background retained-photo edits.")
    XCTAssertEqual(harness.viewModel.confirmedBristolType, 5)
    XCTAssertEqual(harness.viewModel.mixedForm, .no)
    XCTAssertEqual(harness.viewModel.confirmedPhotoUsable, true)
    XCTAssertNil(harness.viewModel.confirmedRetakeReason)
    XCTAssertEqual(harness.viewModel.redBlood, .no)
    XCTAssertEqual(harness.viewModel.blackAppearance, .yes)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)
    XCTAssertEqual(harness.viewModel.statusMessage, manualStatus)
    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 0, suggest: 0, cancel: 0))
  }

  func testBackgroundedReplacementSnapshotFailureRestoresPostBackgroundEditsOnce()
    async throws
  {
    let fault = SnapshotSaveFault()
    let transfer = DelayedPhotoTransfer()
    let harness = try makeHarness(
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: false,
      snapshotSaveFailureInjector: { try fault.run() }
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.enterManualMode()
    let oldURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let oldBytes = try Data(contentsOf: oldURL)

    let delayedLoad = Task {
      await harness.viewModel.loadPhotoDataForTesting {
        try await transfer.load()
      }
    }
    for _ in 0..<100 {
      if await transfer.hasStarted() { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let transferStarted = await transfer.hasStarted()
    XCTAssertTrue(transferStarted)
    harness.viewModel.handleAppBecameInactive()
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Backgrounding must establish retained-photo manual review.")
    }

    harness.viewModel.note = "Edits made while the picker was backgrounded."
    harness.viewModel.updateConfirmedPhotoUsable(true)
    harness.viewModel.updateStoolPresence(.stool)
    harness.viewModel.updateConfirmedBristolType(6)
    harness.viewModel.updateMixedForm(.no)
    harness.viewModel.updateApparentColor("orange")
    harness.viewModel.redBlood = .yes
    harness.viewModel.blackAppearance = .no
    harness.viewModel.blackTarry = .unsure
    let manualFlow = harness.viewModel.flowState
    let manualStatus = harness.viewModel.statusMessage
    let snapshotURL = harness.root.appendingPathComponent(
      "Drafts/active-draft.v1.json"
    )
    let snapshotBytes = try Data(contentsOf: snapshotURL)
    let callsBeforeReplacement = fault.invocationCount

    fault.shouldFail = true
    await transfer.complete(imageData(color: .green))
    await delayedLoad.value

    XCTAssertEqual(fault.invocationCount, callsBeforeReplacement + 1)
    XCTAssertEqual(harness.viewModel.flowState, manualFlow)
    XCTAssertEqual(harness.viewModel.statusMessage, manualStatus)
    XCTAssertEqual(harness.viewModel.currentDraftURL, oldURL)
    XCTAssertEqual(try Data(contentsOf: oldURL), oldBytes)
    XCTAssertEqual(try Data(contentsOf: snapshotURL), snapshotBytes)
    XCTAssertEqual(
      harness.viewModel.note,
      "Edits made while the picker was backgrounded."
    )
    XCTAssertEqual(harness.viewModel.confirmedStoolPresence, .stool)
    XCTAssertEqual(harness.viewModel.confirmedBristolType, 6)
    XCTAssertEqual(harness.viewModel.mixedForm, .no)
    XCTAssertEqual(harness.viewModel.confirmedPhotoUsable, true)
    XCTAssertNil(harness.viewModel.confirmedRetakeReason)
    XCTAssertEqual(harness.viewModel.apparentColor, "orange")
    XCTAssertEqual(harness.viewModel.redBlood, .yes)
    XCTAssertEqual(harness.viewModel.blackAppearance, .no)
    XCTAssertEqual(harness.viewModel.blackTarry, .unsure)
  }

  func testBackgroundedReplacementSuccessClearsOldPhotoReviewAnswers()
    async throws
  {
    let engine = MockPhotoSuggestionEngine(mode: .failure(.invalidOutput))
    let transfer = DelayedPhotoTransfer()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: false
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData(color: .brown))
    harness.viewModel.enterManualMode()
    let manualCapturedAt = Date(timeIntervalSince1970: 1_735_000_000)
    harness.viewModel.capturedAt = manualCapturedAt
    harness.viewModel.note = "Keep this person-entered note."
    harness.viewModel.painScore = 4
    harness.viewModel.urgency = .moderate
    harness.viewModel.updateConfirmedBristolType(4)
    harness.viewModel.updateMixedForm(.no)
    harness.viewModel.updateConfirmedPhotoUsable(true)
    harness.viewModel.redBlood = .yes
    harness.viewModel.blackAppearance = .no
    harness.viewModel.blackTarry = .yes
    let oldURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    let oldHash = hexSHA256(try Data(contentsOf: oldURL))
    let replacementData = imageData(color: .green)

    let delayedLoad = Task {
      await harness.viewModel.loadPhotoDataForTesting { try await transfer.load() }
    }
    for _ in 0..<100 {
      if await transfer.hasStarted() { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let transferStarted = await transfer.hasStarted()
    XCTAssertTrue(transferStarted)

    harness.viewModel.handleAppBecameInactive()
    await transfer.complete(replacementData)
    await delayedLoad.value

    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A successful backgrounded replacement must remain manual.")
    }
    let replacementURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    XCTAssertNotEqual(replacementURL, oldURL)
    let installedReplacementData = try Data(contentsOf: replacementURL)
    XCTAssertFalse(installedReplacementData.isEmpty)
    XCTAssertNotEqual(hexSHA256(installedReplacementData), oldHash)
    XCTAssertEqual(harness.viewModel.capturedAt, manualCapturedAt)
    XCTAssertEqual(harness.viewModel.note, "Keep this person-entered note.")
    XCTAssertEqual(harness.viewModel.painScore, 4)
    XCTAssertEqual(harness.viewModel.urgency, .moderate)
    XCTAssertNil(harness.viewModel.confirmedStoolPresence)
    XCTAssertNil(harness.viewModel.confirmedBristolType)
    XCTAssertNil(harness.viewModel.confirmedForm)
    XCTAssertNil(harness.viewModel.confirmedApparentColor)
    XCTAssertNil(harness.viewModel.confirmedPhotoUsable)
    XCTAssertNil(harness.viewModel.confirmedRetakeReason)
    XCTAssertNil(harness.viewModel.mixedForm)
    XCTAssertNil(harness.viewModel.redBlood)
    XCTAssertNil(harness.viewModel.blackAppearance)
    XCTAssertNil(harness.viewModel.blackTarry)
    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 0, suggest: 0, cancel: 0))
  }

  func testNormalPhotoTransferStagingFailureUnlocksAndPreservesPriorManualDraft()
    async throws
  {
    let engine = MockPhotoSuggestionEngine(mode: .failure(.invalidOutput))
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: false
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData(color: .brown))
    harness.viewModel.enterManualMode()
    harness.viewModel.note = "Prior manual note"
    harness.viewModel.updateConfirmedBristolType(4)
    harness.viewModel.updateMixedForm(.no)
    harness.viewModel.updateConfirmedPhotoUsable(true)
    let priorURL = try XCTUnwrap(harness.viewModel.currentDraftURL)

    await harness.viewModel.loadPhotoDataForTesting { Data([0x00]) }

    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A normal replacement failure must restore the prior manual state.")
    }
    XCTAssertFalse(harness.viewModel.isBusy)
    XCTAssertTrue(harness.viewModel.canReplaceOrClear)
    XCTAssertEqual(harness.viewModel.currentDraftURL, priorURL)
    XCTAssertEqual(harness.viewModel.note, "Prior manual note")
    XCTAssertEqual(harness.viewModel.confirmedBristolType, 4)
    XCTAssertEqual(harness.viewModel.mixedForm, .no)
    XCTAssertEqual(harness.viewModel.confirmedPhotoUsable, true)
    let failedCounts = await engine.counts()
    XCTAssertEqual(failedCounts, .init(prepare: 0, suggest: 0, cancel: 0))

    let freshData = imageData(color: .green)
    await harness.viewModel.loadPhotoDataForTesting { freshData }
    let freshURL = try XCTUnwrap(harness.viewModel.currentDraftURL)
    XCTAssertNotEqual(freshURL, priorURL)
    XCTAssertFalse(harness.viewModel.isBusy)
    let finalCounts = await engine.counts()
    XCTAssertEqual(finalCounts, .init(prepare: 0, suggest: 0, cancel: 0))
  }

  func testBackgroundRetainedPhotoTransferStagingFailureKeepsManualDraftAndStatus()
    async throws
  {
    let engine = MockPhotoSuggestionEngine(mode: .failure(.invalidOutput))
    let transfer = DelayedPhotoTransfer()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: false
    )
    defer { harness.cleanup() }

    let delayedLoad = Task {
      await harness.viewModel.loadPhotoDataForTesting { try await transfer.load() }
    }
    for _ in 0..<100 {
      if await transfer.hasStarted() { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let transferStarted = await transfer.hasStarted()
    XCTAssertTrue(transferStarted)

    harness.viewModel.handleAppBecameInactive()
    guard case .manual(let draftID) = harness.viewModel.flowState, draftID == nil else {
      return XCTFail("Backgrounding must establish the manual fallback before staging fails.")
    }
    let editedCapturedAt = Date(timeIntervalSince1970: 1_736_000_000)
    harness.viewModel.capturedAt = editedCapturedAt
    harness.viewModel.note = "Retained manual note"
    harness.viewModel.updateStoolPresence(.stool)
    harness.viewModel.updateConfirmedBristolType(5)
    harness.viewModel.updateMixedForm(.no)
    harness.viewModel.updateApparentColor("yellow")
    harness.viewModel.redBlood = .yes
    harness.viewModel.blackAppearance = .no
    harness.viewModel.blackTarry = .yes
    let manualStatus = harness.viewModel.statusMessage

    await transfer.complete(Data([0x00]))
    await delayedLoad.value

    guard case .manual(let draftID) = harness.viewModel.flowState, draftID == nil else {
      return XCTFail("Manual fallback must survive a late staging failure.")
    }
    XCTAssertFalse(harness.viewModel.isBusy)
    XCTAssertTrue(harness.viewModel.canReplaceOrClear)
    XCTAssertNil(harness.viewModel.currentDraftURL)
    XCTAssertEqual(harness.viewModel.capturedAt, editedCapturedAt)
    XCTAssertEqual(harness.viewModel.note, "Retained manual note")
    XCTAssertEqual(harness.viewModel.confirmedStoolPresence, .stool)
    XCTAssertEqual(harness.viewModel.confirmedBristolType, 5)
    XCTAssertEqual(harness.viewModel.mixedForm, .no)
    XCTAssertEqual(harness.viewModel.apparentColor, "yellow")
    XCTAssertEqual(harness.viewModel.redBlood, .yes)
    XCTAssertEqual(harness.viewModel.blackAppearance, .no)
    XCTAssertEqual(harness.viewModel.blackTarry, .yes)
    XCTAssertEqual(harness.viewModel.statusMessage, manualStatus)
    let failedCounts = await engine.counts()
    XCTAssertEqual(failedCounts, .init(prepare: 0, suggest: 0, cancel: 0))

    let freshData = imageData(color: .green)
    await harness.viewModel.loadPhotoDataForTesting { freshData }
    XCTAssertNotNil(harness.viewModel.currentDraftURL)
    XCTAssertFalse(harness.viewModel.isBusy)
    let finalCounts = await engine.counts()
    XCTAssertEqual(finalCounts, .init(prepare: 0, suggest: 0, cancel: 0))
  }

  func testColdRestoreOfInterruptedProviderNeutralDraftStaysManualWithoutSecondModelCall()
    async throws
  {
    let interruptedEngine = DelayedPreparationPhotoSuggestionEngine()
    let harness = try makeHarness(
      photoSuggestionEngine: interruptedEngine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    await waitForPreparationStart(interruptedEngine)
    let restoredEngine = DelayedPreparationPhotoSuggestionEngine()
    let restored = NewEntryViewModel(
      imageStore: harness.imageStore,
      store: harness.store,
      inference: MockInferenceService(scripts: []),
      photoSuggestionEngine: restoredEngine,
      descriptor: nil,
      modelVerified: false,
      engineReady: false,
      configuration: .deterministicBaseline,
      autoAnalysisEnabled: true
    )

    restored.restoreUnfinishedDraftIfAvailable()
    guard case .manual = restored.flowState else {
      return XCTFail("An interrupted provider-neutral draft must cold-restore as manual.")
    }
    XCTAssertNotNil(restored.currentDraftURL)
    XCTAssertEqual(restored.analysisSource, .manual)
    let restoredCounts = await restoredEngine.counts()
    XCTAssertEqual(restoredCounts, .init(prepare: 0, suggest: 0, cancel: 0))
    await interruptedEngine.failPreparation()
  }

  func testProviderNeutralPreparationReplacementAndClearRejectLateCompletion()
    async throws
  {
    let engine = DelayedPreparationPhotoSuggestionEngine()
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    try harness.viewModel.prepareImageData(imageData())
    await waitForPreparationStart(engine)
    // A different size changes the retained-photo identity while preserving
    // an analysis-eligible texture for this stale-preparation lifecycle test.
    try harness.viewModel.prepareImageData(
      imageData(size: CGSize(width: 800, height: 600))
    )
    for _ in 0..<100 {
      if (await engine.counts()).prepare == 2 { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let replacementCounts = await engine.counts()
    XCTAssertEqual(replacementCounts.prepare, 2)

    await engine.completePreparation(callIndex: 0)
    try? await Task.sleep(for: .milliseconds(30))
    guard case .reading = harness.viewModel.flowState else {
      return XCTFail("A replaced photo must not inherit stale preparation readiness.")
    }
    let staleReplacementCounts = await engine.counts()
    XCTAssertEqual(staleReplacementCounts.suggest, 0)

    harness.viewModel.clear()
    guard case .empty = harness.viewModel.flowState else {
      return XCTFail("Clear must remove the active retained draft before late preparation returns.")
    }
    await engine.completePreparation(callIndex: 1)
    try? await Task.sleep(for: .milliseconds(30))

    guard case .empty = harness.viewModel.flowState else {
      return XCTFail("Late preparation after clear must not recreate a draft or analysis.")
    }
    let counts = await engine.counts()
    XCTAssertEqual(counts, .init(prepare: 2, suggest: 0, cancel: 0))
  }

  func testProviderNeutralV2BackgroundCancelQuarantinesUntilFullRestart()
    async throws
  {
    let raw = """
      {"black_tarry_appearance":"no","schema_version":"gi-photo-full-prefill-v2","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":null,"form":"unable_to_assess","mixed_form":"not_sure","apparent_color":"dark_brown","red_appearing_material":"yes","black_appearance":"yes"}
      """
    let engine = DelayedPhotoSuggestionEngine(cancellationDisposition: .fullAppRestartRequired)
    let harness = try makeHarness(
      photoSuggestionEngine: engine,
      modelReady: false,
      analysisTimeout: .seconds(5),
      descriptor: nil,
      autoAnalysisEnabled: true
    )
    defer { harness.cleanup() }

    await harness.viewModel.startAutomaticPreparation()
    try harness.viewModel.prepareImageData(imageData())
    await waitForReading(harness.viewModel)
    for _ in 0..<100 {
      if (await engine.counts()).suggest >= 1 { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let retainedPhoto = try XCTUnwrap(harness.viewModel.currentDraftURL)

    harness.viewModel.handleAppBecameInactive()
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("Background cancellation must immediately preserve a manual draft.")
    }
    for _ in 0..<100 {
      if (await engine.counts()).cancel >= 1 { break }
      try? await Task.sleep(for: .milliseconds(5))
    }
    let counts = await engine.counts()
    XCTAssertEqual(counts.cancel, 1)

    await engine.complete(callIndex: 0, raw: raw)
    await waitForAnalysis(harness.viewModel)
    for _ in 0..<100 where !harness.viewModel.requiresFullAppRestart {
      try? await Task.sleep(for: .milliseconds(5))
    }

    XCTAssertTrue(harness.viewModel.requiresFullAppRestart)
    XCTAssertEqual(harness.viewModel.currentDraftURL, retainedPhoto)
    XCTAssertEqual(harness.viewModel.analysisSource, .manual)
    guard case .manual = harness.viewModel.flowState else {
      return XCTFail("A late result must not replace the quarantined manual draft.")
    }

    harness.viewModel.retryAnalysis()
    try? await Task.sleep(for: .milliseconds(30))
    let retryCounts = await engine.counts()
    XCTAssertEqual(retryCounts.suggest, 1)
  }

  func testLegacyPhotoSuggestionReceiptRemainsBackwardReadableWhenDecomposedEvidenceIsAbsent()
    throws
  {
    let (receipt, rawOutput) = try legacyPhotoSuggestionReceiptFixture()
    let encoded = try XCTUnwrap(receipt.canonicalJSON)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
    )
    XCTAssertNil(object["decomposedFieldProvenance"])

    let decoded = try PhotoSuggestionEngineReceipt.decode(encoded)
    XCTAssertNil(decoded.decomposedFieldProvenance)
    XCTAssertNoThrow(try decoded.validate(rawOutputUTF8: rawOutput))
  }

  func testDecomposedPhotoSuggestionReceiptRoundTripsWithSeparateFieldEvidence()
    throws
  {
    let fixture = try decomposedPhotoSuggestionReceiptFixture()
    let encoded = try XCTUnwrap(fixture.receipt.canonicalJSON)
    let decoded = try PhotoSuggestionEngineReceipt.decode(encoded)
    let validated = try decoded.validate(rawOutputUTF8: fixture.rawOutput)
    let fusedRaw = try XCTUnwrap(String(data: fixture.rawOutput, encoding: .utf8))
    let provenance = try XCTUnwrap(decoded.decomposedFieldProvenance)

    XCTAssertEqual(decoded, fixture.receipt)
    XCTAssertEqual(fusedRaw, decoded.canonicalParsedJSON)
    XCTAssertEqual(validated.stoolPresence, .uncertain)
    XCTAssertEqual(provenance.runEvidence.fields.count, Qwen3DecomposedField.allCases.count)
    XCTAssertEqual(
      Set(provenance.runEvidence.fields.map(\.rawTokenIDs)).count,
      Qwen3DecomposedField.allCases.count
    )
    XCTAssertTrue(provenance.runEvidence.fields.allSatisfy {
      $0.rawText != fusedRaw && !$0.rawTokenIDs.isEmpty
    })
  }

  func testQwen1024PreprocessingEvidenceRoundTripsWithTruthfulEffectiveDimensions()
    throws
  {
    let tensorSHA256 = String(repeating: "e", count: 64)
    let evidence = PhotoSuggestionPreprocessingEvidence(
      requestedProfile: "1024",
      effectiveProfile: "1024",
      preprocessingVersion: PhotoSuggestionPreprocessingEvidence.qwen1024Version,
      sourcePixelWidth: 800,
      sourcePixelHeight: 600,
      effectiveSourcePixelWidth: 800,
      effectiveSourcePixelHeight: 600,
      derivativePixelWidth: 1024,
      derivativePixelHeight: 1024,
      derivativeContentPixelWidth: 1024,
      derivativeContentPixelHeight: 768,
      deterministicDerivativePixelWidth: 512,
      deterministicDerivativePixelHeight: 512,
      deterministicDerivativeRGBASHA256: String(repeating: "8", count: 64),
      sourceWasUpscaled: true,
      pixelBudget: 1_048_576,
      expectedFrameT: 1,
      expectedFrameH: 64,
      expectedFrameW: 64,
      actualFrameT: 1,
      actualFrameH: 64,
      actualFrameW: 64,
      postMergeVisualTokenCount: 1_024,
      derivativeRGBASHA256: String(repeating: "9", count: 64),
      preparedTensorSHA256: tensorSHA256,
      preprocessLatencyMilliseconds: 87,
      availableMemoryBytes: 2_700_000_000,
      mlxActiveMemoryBytes: 1_800_000_000,
      mlxPeakMemoryBytes: 2_360_000_000,
      mlxCacheMemoryBytes: 1_700_000_000,
      hostPeakRSSBytes: 1_980_000_000,
      thermalState: "nominal"
    )
    let fixture = try decomposedPhotoSuggestionReceiptFixture(
      fusionVersion: Qwen3DecomposedFusion.fusionVersion,
      negativeAppearance: false,
      providerID: "internal-qwen3-qualification",
      preprocessingVersion: PhotoSuggestionPreprocessingEvidence.qwen1024Version,
      analyzedPixelWidth: 800,
      analyzedPixelHeight: 600,
      preprocessingEvidence: evidence
    )
    let encoded = try XCTUnwrap(fixture.receipt.canonicalJSON)
    let decoded = try PhotoSuggestionEngineReceipt.decode(encoded)
    XCTAssertEqual(decoded.preprocessingEvidence, evidence)
    XCTAssertEqual(decoded.canonicalJSON, encoded)
    XCTAssertNoThrow(try decoded.validate(rawOutputUTF8: fixture.rawOutput))
  }

  func testQwenPreprocessingReceiptRejectsUnsupportedDimensionsHiddenFallbackAndTensorMismatch()
    throws
  {
    let evidence = PhotoSuggestionPreprocessingEvidence(
      requestedProfile: "1024",
      effectiveProfile: "1024",
      preprocessingVersion: PhotoSuggestionPreprocessingEvidence.qwen1024Version,
      sourcePixelWidth: 1024,
      sourcePixelHeight: 768,
      effectiveSourcePixelWidth: 1024,
      effectiveSourcePixelHeight: 768,
      derivativePixelWidth: 1024,
      derivativePixelHeight: 1024,
      derivativeContentPixelWidth: 1024,
      derivativeContentPixelHeight: 768,
      deterministicDerivativePixelWidth: 512,
      deterministicDerivativePixelHeight: 512,
      deterministicDerivativeRGBASHA256: String(repeating: "8", count: 64),
      sourceWasUpscaled: false,
      pixelBudget: 1_048_576,
      expectedFrameT: 1,
      expectedFrameH: 64,
      expectedFrameW: 64,
      actualFrameT: 1,
      actualFrameH: 64,
      actualFrameW: 64,
      postMergeVisualTokenCount: 1_024,
      derivativeRGBASHA256: String(repeating: "9", count: 64),
      preparedTensorSHA256: String(repeating: "e", count: 64),
      preprocessLatencyMilliseconds: 1,
      availableMemoryBytes: 1,
      mlxActiveMemoryBytes: 1,
      mlxPeakMemoryBytes: 1,
      mlxCacheMemoryBytes: 1,
      hostPeakRSSBytes: 1,
      thermalState: "fair"
    )
    let fixture = try decomposedPhotoSuggestionReceiptFixture(
      fusionVersion: Qwen3DecomposedFusion.fusionVersion,
      negativeAppearance: false,
      providerID: "internal-qwen3-qualification",
      preprocessingVersion: PhotoSuggestionPreprocessingEvidence.qwen1024Version,
      analyzedPixelWidth: 1024,
      analyzedPixelHeight: 768,
      preprocessingEvidence: evidence
    )

    func rejects(_ mutate: (inout [String: Any]) -> Void, line: UInt = #line) throws {
      let mutated = try mutatedPhotoSuggestionReceipt(fixture.receipt, mutate: mutate)
      XCTAssertThrowsError(try mutated.validate(rawOutputUTF8: fixture.rawOutput), line: line)
    }
    try rejects { object in
      var preprocessing = object["preprocessingEvidence"] as! [String: Any]
      preprocessing["derivativePixelWidth"] = 768
      object["preprocessingEvidence"] = preprocessing
    }
    try rejects { object in
      var preprocessing = object["preprocessingEvidence"] as! [String: Any]
      preprocessing["deterministicDerivativePixelWidth"] = 1024
      object["preprocessingEvidence"] = preprocessing
    }
    try rejects { object in
      var preprocessing = object["preprocessingEvidence"] as! [String: Any]
      preprocessing["effectiveProfile"] = "512"
      object["preprocessingEvidence"] = preprocessing
    }
    try rejects { object in
      var preprocessing = object["preprocessingEvidence"] as! [String: Any]
      preprocessing["preparedTensorSHA256"] = String(repeating: "0", count: 64)
      object["preprocessingEvidence"] = preprocessing
    }
  }

  func testHistoricalQwen256And512ReceiptsRemainReadableWithoutPreprocessingEvidence()
    throws
  {
    for version in [
      "qwen3vl-hybrid-512-v1",
      "qwen3vl-hybrid-256-qa-resource-fallback-v1",
    ] {
      let fixture = try decomposedPhotoSuggestionReceiptFixture(
        fusionVersion: Qwen3DecomposedFusion.fusionVersion,
        negativeAppearance: false,
        providerID: "internal-qwen3-qualification",
        preprocessingVersion: version
      )
      XCTAssertNil(fixture.receipt.preprocessingEvidence)
      XCTAssertNoThrow(try fixture.receipt.validate(rawOutputUTF8: fixture.rawOutput))
    }
  }

  func testCurrentQwenProfileCannotOmitRequiredPreprocessingEvidence() throws {
    let fixture = try decomposedPhotoSuggestionReceiptFixture(
      fusionVersion: Qwen3DecomposedFusion.fusionVersion,
      negativeAppearance: false,
      providerID: "internal-qwen3-qualification",
      preprocessingVersion: PhotoSuggestionPreprocessingEvidence.qwen512Version
    )
    XCTAssertNil(fixture.receipt.preprocessingEvidence)
    XCTAssertThrowsError(try fixture.receipt.validate(rawOutputUTF8: fixture.rawOutput))
  }

  func testHistoricalDecomposedReceiptVersionsReplayWithoutRewritingBytes()
    throws
  {
    let v1 = try decomposedPhotoSuggestionReceiptFixture(
      fusionVersion: Qwen3DecomposedFusion.legacyCompleteTriStateVersion,
      parserVersion: Qwen3DecomposedContract.legacyParserVersion,
      negativeAppearance: true
    )
    let v1JSON = try XCTUnwrap(v1.receipt.canonicalJSON)
    let v1Decoded = try PhotoSuggestionEngineReceipt.decode(v1JSON)
    let v1Suggestion = try v1Decoded.validate(rawOutputUTF8: v1.rawOutput)
    XCTAssertEqual(v1Decoded.canonicalJSON, v1JSON)
    XCTAssertEqual(v1Suggestion.redAppearingMaterial, .no)
    XCTAssertEqual(v1Suggestion.blackAppearance, .no)
    XCTAssertEqual(v1Suggestion.blackTarryAppearance, .no)

    let v2 = try decomposedPhotoSuggestionReceiptFixture(
      fusionVersion: Qwen3DecomposedFusion.legacyPositiveOnlyVersion,
      negativeAppearance: true
    )
    let v2JSON = try XCTUnwrap(v2.receipt.canonicalJSON)
    let v2Decoded = try PhotoSuggestionEngineReceipt.decode(v2JSON)
    let v2Suggestion = try v2Decoded.validate(rawOutputUTF8: v2.rawOutput)
    XCTAssertEqual(v2Decoded.canonicalJSON, v2JSON)
    XCTAssertEqual(v2Suggestion.redAppearingMaterial, .notSure)
    XCTAssertEqual(v2Suggestion.blackAppearance, .notSure)
    XCTAssertEqual(v2Suggestion.blackTarryAppearance, .notSure)

    // Merely relabeling V2 bytes as V1 must fail because replayed semantics
    // no longer match the canonical fused output carried by the receipt.
    let mislabeled = try mutatedPhotoSuggestionReceipt(v2.receipt) { object in
      self.mutateReceiptProvenance(&object) {
        $0["fusionVersion"] =
          Qwen3DecomposedFusion.legacyCompleteTriStateVersion
      }
    }
    XCTAssertThrowsError(
      try mislabeled.validate(rawOutputUTF8: v2.rawOutput)
    )
  }

  func testHistoricalV9AcceptedNotSureRecordCanLoadEditAndExportPDF()
    throws
  {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    let prepared = try harness.imageStore.prepare(imageData())
    let confirmedAt = Date(timeIntervalSinceReferenceDate: 3_000)
    let legacy = try decomposedPhotoSuggestionReceiptFixture(
      fusionVersion: Qwen3DecomposedFusion.legacyCompleteTriStateVersion,
      parserVersion: Qwen3DecomposedContract.legacyParserVersion,
      negativeAppearance: true,
      imageSHA256: prepared.reference.sha256,
      analysisPipelineVersion: "qwen3-decomposed-pipeline-v1",
      instant: confirmedAt
    )
    let raw = try XCTUnwrap(String(data: legacy.rawOutput, encoding: .utf8))
    let receiptJSON = try XCTUnwrap(legacy.receipt.canonicalJSON)
    let fields = Dictionary(
      uniqueKeysWithValues: ConfirmationField.allCases.map {
        ($0, FieldConfirmationProvenance.acceptedUnchanged)
      }
    )
    let confirmation = ConfirmedEntrySnapshotV1(
      confirmedAt: confirmedAt,
      personConfirmedPhotoUsable: true,
      initiallyAcceptedPhotoUsable: true,
      initiallyAcceptedRetakeReason: nil,
      initiallyAcceptedStoolPresence: .uncertain,
      initiallyAcceptedBristolType: nil,
      initiallyAcceptedForm: "unable_to_assess",
      initiallyAcceptedMixedForm: .unsure,
      initiallyAcceptedApparentColor: "dark_brown",
      initiallyAcceptedRed: .unsure,
      initiallyAcceptedBlackAppearance: .unsure,
      initiallyAcceptedBlackTarry: .unsure,
      personConfirmedRetakeReason: nil,
      personConfirmedStoolPresence: .uncertain,
      personConfirmedBristolType: nil,
      personConfirmedForm: "unable_to_assess",
      personConfirmedMixedForm: .unsure,
      personConfirmedApparentColor: "dark_brown",
      personConfirmedRed: .unsure,
      personConfirmedBlackAppearance: .unsure,
      personConfirmedBlackTarry: .unsure,
      fieldProvenance: fields
    )
    let reviewedJSON = try XCTUnwrap(confirmation.canonicalJSON)
    let id = UUID()
    let input = EntryInput(
      id: id,
      capturedAt: confirmedAt,
      draftURL: prepared.url,
      imageSHA256: prepared.reference.sha256,
      redBlood: .unsure,
      blackAppearance: .unsure,
      blackTarry: .unsure,
      dizziness: .no,
      severePain: .no,
      note: "Historical V9 confirmation",
      painScore: 0,
      urgency: UrgencyLevel.none,
      confirmedBristolType: nil,
      confirmedPhotoUsable: true,
      mixedForm: .unsure,
      strainingOrIncomplete: nil,
      leakageOrAccident: nil,
      analysisSource: .onDevicePhotoSuggestion,
      analysisPipelineVersion:
        legacy.receipt.identity.analysisPipelineVersion,
      provenance: .ai_unedited,
      reviewedAt: confirmedAt,
      originalAIJSON: raw,
      reviewedJSON: reviewedJSON,
      modelID: legacy.receipt.identity.modelID,
      modelProvenanceJSON: receiptJSON,
      demoKind: nil,
      imageFilename: "\(id.uuidString).jpg"
    )

    XCTAssertNoThrow(
      try harness.store.save(input, imageStore: harness.imageStore)
    )
    let record = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(record.redBlood, SymptomFlag.unsure.rawValue)
    XCTAssertEqual(record.blackAppearanceAnswer, .unsure)
    XCTAssertEqual(record.blackTarry, SymptomFlag.unsure.rawValue)
    XCTAssertEqual(record.provenance, EntryProvenance.ai_unedited.rawValue)

    var edit = EntryEditInput(entry: record)
    edit.note = "Historical V9 confirmation remains editable"
    XCTAssertNoThrow(
      try harness.store.update(
        record,
        with: edit,
        baselineFingerprint: try EntryRecordFingerprint.make(for: record),
        at: confirmedAt.addingTimeInterval(1)
      )
    )
    XCTAssertEqual(record.note, edit.note)
    XCTAssertEqual(record.provenance, EntryProvenance.ai_unedited.rawValue)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let day = calendar.startOfDay(for: confirmedAt)
    let export = try JournalExportSnapshotFactory.make(
      entries: [record],
      completions: [],
      treatmentEvents: [],
      range: .init(from: day, through: day),
      scope: .allEntries,
      generatedAt: day.addingTimeInterval(12 * 3_600),
      calendar: calendar,
      timeZone: calendar.timeZone
    )
    let pdf = try JournalPDFRenderer().render(
      snapshot: export,
      photoDirectory: harness.root.appendingPathComponent("Images")
    )
    let document = try XCTUnwrap(PDFDocument(data: pdf))
    let text = (0..<document.pageCount)
      .compactMap { document.page(at: $0)?.string }
      .joined(separator: "\n")
    XCTAssertTrue(
      text.contains("On-device suggestion — possible red appearance: No")
    )
    XCTAssertTrue(
      text.contains(
        "Accepted value — possible red/blood-like appearance: Not sure"
      )
    )
    XCTAssertTrue(
      text.contains(
        "Final value — possible red/blood-like appearance: Not sure"
      )
    )
    XCTAssertTrue(text.contains("Photo included"))
  }

  func testDecomposedPhotoSuggestionReceiptRejectsContractViolations()
    throws
  {
    let fixture = try decomposedPhotoSuggestionReceiptFixture()

    func rejects(_ mutate: (inout [String: Any]) -> Void, line: UInt = #line) throws {
      let mutated = try mutatedPhotoSuggestionReceipt(fixture.receipt, mutate: mutate)
      XCTAssertThrowsError(try mutated.validate(rawOutputUTF8: fixture.rawOutput), line: line)
    }

    try rejects({ $0["modelCallCount"] = 6 })
    try rejects({ object in
      self.mutateReceiptIdentity(&object) { $0["promptSHA256"] = String(repeating: "0", count: 64) }
    })
    try rejects({ object in
      self.mutateReceiptField(&object, at: 0) { $0["prompt"] = "wrong prompt" }
    })
    try rejects({ object in
      self.mutateReceiptField(&object, at: 0) { $0["promptSHA256"] = String(repeating: "0", count: 64) }
    })
    try rejects({ object in
      self.mutateReceiptFields(&object) { fields in fields.swapAt(0, 1) }
    })
    try rejects({ object in
      self.mutateReceiptField(&object, at: 0) { $0["modelCallOrdinal"] = 7 }
    })
    try rejects({ object in
      let sourceCacheID = self.receiptField(&object, at: 0)["generationCacheID"]
      self.mutateReceiptField(&object, at: 1) { field in
        field["generationCacheID"] = sourceCacheID
      }
    })
    try rejects({ object in
      self.mutateReceiptField(&object, at: 0) { $0["usedFreshGenerationCache"] = false }
    })
    try rejects({ object in
      self.mutateReceiptField(&object, at: 3) { $0["qualified"] = false }
    })
    try rejects({ object in
      self.mutateReceiptProvenance(&object) { $0["qualificationVersion"] = "wrong" }
    })
    try rejects({ object in
      self.mutateReceiptRunEvidence(&object) { $0["analyzedImageSHA256"] = String(repeating: "0", count: 64) }
    })
    try rejects({ object in
      self.mutateReceiptField(&object, at: 0) { $0["preparedTensorSHA256"] = String(repeating: "0", count: 64) }
    })
    try rejects({ object in
      self.mutateReceiptRunEvidence(&object) { $0["preparedTensorSHA256"] = "not-a-sha" }
      self.mutateReceiptFields(&object) { fields in
        for index in fields.indices { fields[index]["preparedTensorSHA256"] = "not-a-sha" }
      }
    })
    try rejects({ object in
      self.mutateReceiptField(&object, at: 0) { $0.removeValue(forKey: "mlxActiveMemoryBytes") }
    })
    try rejects({ object in
      self.mutateReceiptField(&object, at: 0) { $0["hostPeakRSSBytes"] = -1 }
    })
    try rejects({ object in
      self.mutateReceiptField(&object, at: 0) { $0["rawUTF8Base64"] = "bm9uZGU=" }
    })
    try rejects({ object in
      self.mutateReceiptField(&object, at: 0) { $0["rawUTF8SHA256"] = String(repeating: "0", count: 64) }
    })
    try rejects({ object in
      self.mutateReceiptField(&object, at: 0) { field in
        field["parsed"] = ["field": "subject", "label": "unsure", "disposition": "accepted"]
      }
    })
    try rejects({ object in
      self.mutateReceiptProvenance(&object) { $0["fusionVersion"] = "wrong" }
    })
    try rejects({ object in
      self.mutateReceiptProvenance(&object) { $0["fusedCanonicalJSON"] = "{}" }
    })
  }

  private func legacyPhotoSuggestionReceiptFixture()
    throws -> (receipt: PhotoSuggestionEngineReceipt, rawOutput: Data)
  {
    let suggestion = PhotoSuggestionPayloadV2(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .uncertain,
      bristolType: nil,
      form: "unable_to_assess",
      mixedForm: .notSure,
      apparentColor: nil,
      redAppearingMaterial: .notSure,
      blackAppearance: .notSure,
      blackTarryAppearance: .notSure
    )
    let canonical = try PhotoSuggestionPayloadV2Parser.canonicalJSON(suggestion)
    let rawOutput = Data(canonical.utf8)
    let instant = Date(timeIntervalSinceReferenceDate: 1_000)
    let receipt = PhotoSuggestionEngineReceipt(
      requestID: UUID(),
      identity: PhotoSuggestionEngineIdentity(
        providerID: "test-provider",
        modelID: "test-provider/photo-v2",
        modelRevision: "test-revision",
        modelArtifactSHA256: String(repeating: "a", count: 64),
        runtimeID: "test-runtime",
        runtimeVersion: "1",
        promptVersion: "test-prompt-v1",
        promptSHA256: String(repeating: "b", count: 64),
        parserVersion: PhotoSuggestionPayloadV2Parser.parserVersion,
        schemaVersion: PhotoSuggestionPayloadV2.schemaVersion,
        preprocessingVersion: "test-preprocess-v1",
        analysisPipelineVersion: "test-pipeline-v1"
      ),
      analyzedImageSHA256: String(repeating: "c", count: 64),
      analyzedPixelWidth: 512,
      analyzedPixelHeight: 512,
      startedAt: instant,
      endedAt: instant,
      latencyMilliseconds: 0,
      rawOutputUTF8Base64: rawOutput.base64EncodedString(),
      rawOutputUTF8SHA256: hexSHA256(rawOutput),
      rawOutputUTF8ByteCount: rawOutput.count,
      canonicalParsedJSON: canonical,
      modelCallCount: 1,
      repairCallCount: 0
    )
    return (receipt, rawOutput)
  }

  private func decomposedPhotoSuggestionReceiptFixture()
    throws -> (receipt: PhotoSuggestionEngineReceipt, rawOutput: Data)
  {
    try decomposedPhotoSuggestionReceiptFixture(
      fusionVersion: Qwen3DecomposedFusion.fusionVersion,
      parserVersion: Qwen3DecomposedContract.parserVersion,
      negativeAppearance: false
    )
  }

  private func decomposedPhotoSuggestionReceiptFixture(
    fusionVersion: String,
    parserVersion: String = Qwen3DecomposedContract.parserVersion,
    negativeAppearance: Bool,
    imageSHA256: String = String(repeating: "d", count: 64),
    analysisPipelineVersion: String = "qwen3-decomposed-pipeline-v1",
    instant: Date = Date(timeIntervalSinceReferenceDate: 2_000),
    providerID: String = "qwen3-test-provider",
    preprocessingVersion: String = "qwen3-preprocess-v1",
    analyzedPixelWidth: Int = 512,
    analyzedPixelHeight: Int = 512,
    preprocessingEvidence: PhotoSuggestionPreprocessingEvidence? = nil
  )
    throws -> (receipt: PhotoSuggestionEngineReceipt, rawOutput: Data)
  {
    let tensorSHA256 = String(repeating: "e", count: 64)
    let appearanceLabel = negativeAppearance ? "no" : "yes"
    let rawText: [Qwen3DecomposedField: String] = [
      .subject: "stool", .bristol: "4", .mixed: "no", .color: "brown",
      .red: appearanceLabel, .black: appearanceLabel,
      .glossy: appearanceLabel,
    ]
    let fields = Qwen3DecomposedField.allCases.enumerated().map { index, field in
      let text = rawText[field]!
      let bytes = Data(text.utf8)
      return Qwen3DecomposedRawFieldRecord(
        field: field,
        prompt: field.prompt,
        promptSHA256: Qwen3DecomposedContract.promptSHA256(for: field),
        analyzedImageSHA256: imageSHA256,
        preparedTensorSHA256: tensorSHA256,
        rawTokenIDs: [index + 1],
        rawText: text,
        rawUTF8Base64: bytes.base64EncodedString(),
        rawUTF8SHA256: hexSHA256(bytes),
        parsed: Qwen3DecomposedLabelParser.parse(
          text,
          for: field,
          replaying: parserVersion
        ),
        qualified: Qwen3DecomposedContract.qualifiedFields.contains(field),
        generationCacheID: "fresh-nil-cache-\(index + 1)",
        usedFreshGenerationCache: true,
        stopReason: "eos",
        latencyMilliseconds: index,
        mlxActiveMemoryBytes: 0,
        mlxCacheMemoryBytes: 0,
        mlxPeakMemoryBytes: 0,
        hostPeakRSSBytes: 0,
        modelCallOrdinal: index + 1
      )
    }
    let pixelEvidence = try decomposedPixelEvidenceFixture(
      appearance: negativeAppearance ? .highNegative : .highPositive
    )
    let runEvidence = Qwen3DecomposedRunEvidence(
      analyzedImageSHA256: imageSHA256,
      preparedTensorSHA256: tensorSHA256,
      pixelEvidence: pixelEvidence,
      fields: fields
    )
    let fused = try Qwen3DecomposedFusion.fuse(
      runEvidence,
      replaying: fusionVersion
    )
    let rawOutput = Data(fused.canonicalV2JSON.utf8)
    let provenance = PhotoSuggestionDecomposedProvenance(
      runEvidence: runEvidence,
      qualificationVersion: Qwen3DecomposedContract.qualificationPolicyVersion,
      fusionVersion: fusionVersion,
      fusedCanonicalJSON: fused.canonicalV2JSON
    )
    let receipt = PhotoSuggestionEngineReceipt(
      requestID: UUID(),
      identity: PhotoSuggestionEngineIdentity(
        providerID: providerID,
        modelID: "qwen3-test-model",
        modelRevision: "test-revision",
        modelArtifactSHA256: String(repeating: "f", count: 64),
        runtimeID: "mlx-test-runtime",
        runtimeVersion: "1",
        promptVersion: Qwen3DecomposedContract.promptSetVersion,
        promptSHA256: Qwen3DecomposedContract.promptSetSHA256,
        parserVersion: parserVersion,
        schemaVersion: PhotoSuggestionPayloadV2.schemaVersion,
        preprocessingVersion: preprocessingVersion,
        analysisPipelineVersion: analysisPipelineVersion
      ),
      analyzedImageSHA256: imageSHA256,
      analyzedPixelWidth: analyzedPixelWidth,
      analyzedPixelHeight: analyzedPixelHeight,
      startedAt: instant,
      endedAt: instant,
      latencyMilliseconds: 0,
      rawOutputUTF8Base64: rawOutput.base64EncodedString(),
      rawOutputUTF8SHA256: hexSHA256(rawOutput),
      rawOutputUTF8ByteCount: rawOutput.count,
      canonicalParsedJSON: fused.canonicalV2JSON,
      modelCallCount: Qwen3DecomposedField.allCases.count,
      repairCallCount: 0,
      decomposedFieldProvenance: provenance,
      preprocessingEvidence: preprocessingEvidence
    )
    return (receipt, rawOutput)
  }

  private func decomposedPixelEvidenceFixture(
    appearance: HybridEvidenceStrength = .highPositive
  ) throws -> HybridPixelEvidence {
    let json = """
      {"schemaVersion":"gi-hybrid-pixel-evidence-v2","thresholdVersion":"gi-hybrid-thresholds-v2","quality":"usable","baseColorCandidate":"dark_brown","baseColorConfidencePPM":800000,"localizedRed":"\(appearance.rawValue)","localizedBlack":"\(appearance.rawValue)","tarryGlossSmear":"\(appearance.rawValue)","darkPixelFractionPPM":1,"overexposedPixelFractionPPM":1,"foregroundFractionPPM":1,"foregroundComponentCount":1,"largestForegroundRegionFractionPPM":1,"largestForegroundSolidityPPM":1,"redPixelFractionPPM":1,"blackLowChromaPixelFractionPPM":1,"largestRedRegionFractionPPM":1,"largestBlackRegionFractionPPM":1,"largestBlackRegionElongationNumerator":1,"largestBlackRegionElongationDenominator":1,"componentLocalGlossFractionPPM":1,"strongEdgeFractionPPM":1,"lumaRange":1,"edgeMean":1}
      """
    return try JSONDecoder().decode(HybridPixelEvidence.self, from: Data(json.utf8))
  }

  private func mutatedPhotoSuggestionReceipt(
    _ receipt: PhotoSuggestionEngineReceipt,
    mutate: (inout [String: Any]) -> Void
  ) throws -> PhotoSuggestionEngineReceipt {
    let json = try XCTUnwrap(receipt.canonicalJSON)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    )
    mutate(&object)
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try PhotoSuggestionEngineReceipt.decode(try XCTUnwrap(String(data: data, encoding: .utf8)))
  }

  private func mutateReceiptIdentity(
    _ object: inout [String: Any],
    mutate: (inout [String: Any]) -> Void
  ) {
    guard var identity = object["identity"] as? [String: Any] else { fatalError("missing test identity") }
    mutate(&identity)
    object["identity"] = identity
  }

  private func mutateReceiptProvenance(
    _ object: inout [String: Any],
    mutate: (inout [String: Any]) -> Void
  ) {
    guard var provenance = object["decomposedFieldProvenance"] as? [String: Any] else {
      fatalError("missing test provenance")
    }
    mutate(&provenance)
    object["decomposedFieldProvenance"] = provenance
  }

  private func mutateReceiptRunEvidence(
    _ object: inout [String: Any],
    mutate: (inout [String: Any]) -> Void
  ) {
    mutateReceiptProvenance(&object) { provenance in
      guard var evidence = provenance["runEvidence"] as? [String: Any] else {
        fatalError("missing test run evidence")
      }
      mutate(&evidence)
      provenance["runEvidence"] = evidence
    }
  }

  private func mutateReceiptFields(
    _ object: inout [String: Any],
    mutate: (inout [[String: Any]]) -> Void
  ) {
    mutateReceiptRunEvidence(&object) { evidence in
      guard var fields = evidence["fields"] as? [[String: Any]] else {
        fatalError("missing test field records")
      }
      mutate(&fields)
      evidence["fields"] = fields
    }
  }

  private func mutateReceiptField(
    _ object: inout [String: Any],
    at index: Int,
    mutate: (inout [String: Any]) -> Void
  ) {
    mutateReceiptFields(&object) { fields in mutate(&fields[index]) }
  }

  private func receiptField(_ object: inout [String: Any], at index: Int) -> [String: Any] {
    guard let provenance = object["decomposedFieldProvenance"] as? [String: Any],
      let evidence = provenance["runEvidence"] as? [String: Any],
      let fields = evidence["fields"] as? [[String: Any]]
    else { fatalError("missing test field records") }
    return fields[index]
  }

  private func restoredViewModel(
    from harness: Harness,
    descriptor: ModelDescriptor = .galleryGemma3nE2B,
    configuration: InferenceConfiguration = .deterministicBaseline
  ) throws -> NewEntryViewModel {
    NewEntryViewModel(
      imageStore: harness.imageStore,
      store: harness.store,
      inference: MockInferenceService(scripts: []),
      descriptor: descriptor,
      modelVerified: true,
      engineReady: true,
      configuration: configuration
    )
  }

  private func completeRequiredReview(
    _ viewModel: NewEntryViewModel,
    bristolType: Int? = 4,
    mixedForm: ClinicalTriState = .no,
    photoUsable: Bool = true
  ) {
    viewModel.updateConfirmedBristolType(bristolType)
    viewModel.updateMixedForm(mixedForm)
    if viewModel.currentDraftURL != nil {
      viewModel.updateConfirmedPhotoUsable(photoUsable)
    }
    completeRequiredContext(viewModel)
  }

  private func completeRequiredContext(_ viewModel: NewEntryViewModel) {
    viewModel.urgency = UrgencyLevel.none
    viewModel.painScore = 0
    viewModel.redBlood = .no
    viewModel.blackTarry = .no
    switch ClinicalValidation.conditionalQuestion(for: viewModel.confirmedBristolType) {
    case .strainingOrIncomplete:
      viewModel.strainingOrIncomplete = .no
      viewModel.leakageOrAccident = nil
    case .leakageOrAccident:
      viewModel.leakageOrAccident = .no
      viewModel.strainingOrIncomplete = nil
    case nil:
      viewModel.strainingOrIncomplete = nil
      viewModel.leakageOrAccident = nil
    }
  }

  private func waitForAnalysis(_ viewModel: NewEntryViewModel) async {
    for _ in 0..<200 where viewModel.isBusy { try? await Task.sleep(for: .milliseconds(10)) }
    XCTAssertFalse(viewModel.isBusy, "analysis did not complete within the test window")
  }

  private func waitForAutomaticAnalysis(_ viewModel: NewEntryViewModel) async {
    for _ in 0..<240 {
      switch viewModel.flowState {
      case .reviewing, .manual, .failed:
        XCTAssertFalse(viewModel.isBusy, "automatic analysis reached a terminal state while still locked")
        return
      default:
        try? await Task.sleep(for: .milliseconds(10))
      }
    }
    XCTFail("automatic analysis did not reach suggestion review or manual review within the test window")
  }

  private func waitForReading(_ viewModel: NewEntryViewModel) async {
    for _ in 0..<80 {
      if case .reading = viewModel.flowState, viewModel.isBusy { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
    XCTFail("automatic analysis did not begin reading within the test window")
  }

  private func waitForPreparationStart(
    _ engine: DelayedPreparationPhotoSuggestionEngine
  ) async {
    for _ in 0..<100 {
      if (await engine.counts()).prepare == 1 { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
    XCTFail("provider-neutral preparation did not begin within the test window")
  }

  private enum QualitySyntheticKind: Equatable, CustomStringConvertible {
    case good
    case severeBlur
    case tooDark
    case overexposedGlare
    case nearBlank
    case veryLowContrast
    case borderlineDark

    var description: String {
      switch self {
      case .good: "good"
      case .severeBlur: "severe blur"
      case .tooDark: "too dark"
      case .overexposedGlare: "overexposed/glare"
      case .nearBlank: "near blank"
      case .veryLowContrast: "very low contrast"
      case .borderlineDark: "borderline dark"
      }
    }
  }

  private func qualitySyntheticJPEG(
    _ kind: QualitySyntheticKind,
    size: CGSize = CGSize(width: 512, height: 512)
  ) -> Data {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      switch kind {
      case .good:
        // A scoped, orientation-independent eligible-photo control. Its broad
        // luminance range and dense material texture keep the assertion about
        // source geometry separate from the shared lifecycle fixture helper.
        UIColor(white: 0.50, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
        let insetX = size.width * 0.12
        let insetY = size.height * 0.12
        let cell = max(6, min(size.width, size.height) / 48)
        let subject = CGRect(
          x: insetX,
          y: insetY,
          width: size.width - (2 * insetX),
          height: size.height - (2 * insetY)
        )
        for y in stride(from: subject.minY, to: subject.maxY, by: cell) {
          for x in stride(from: subject.minX, to: subject.maxX, by: cell) {
            let column = Int((x - subject.minX) / cell)
            let row = Int((y - subject.minY) / cell)
            let color = (column + row).isMultiple(of: 2)
              ? UIColor(red: 0.22, green: 0.08, blue: 0.02, alpha: 1)
              : UIColor(red: 0.84, green: 0.57, blue: 0.25, alpha: 1)
            color.setFill()
            context.fill(CGRect(x: x, y: y, width: cell, height: cell))
          }
        }
      case .tooDark:
        UIColor.black.setFill()
        context.fill(CGRect(origin: .zero, size: size))
      case .overexposedGlare:
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: size))
      case .nearBlank:
        UIColor(white: 0.5, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
      case .veryLowContrast:
        UIColor(red: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: 1)
          .setFill()
        context.fill(CGRect(origin: .zero, size: size))
        UIColor(red: 147 / 255, green: 145 / 255, blue: 128 / 255, alpha: 1)
          .setFill()
        context.fill(CGRect(x: 64, y: 64, width: 384, height: 384))
      case .severeBlur:
        for x in 0..<Int(size.width) {
          let value = CGFloat(64 + x * 128 / max(1, Int(size.width))) / 255
          UIColor(white: value, alpha: 1).setFill()
          context.fill(CGRect(x: CGFloat(x), y: 0, width: 1, height: size.height))
        }
      case .borderlineDark:
        UIColor.black.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        let brightStart = Int(size.width * 0.70)
        for y in stride(from: 0, to: Int(size.height), by: 12) {
          for x in stride(from: brightStart, to: Int(size.width), by: 12) {
            let value: CGFloat = ((x / 12) + (y / 12)).isMultiple(of: 2)
              ? 0.45 : 0.72
            UIColor(white: value, alpha: 1).setFill()
            context.fill(CGRect(x: x, y: y, width: 12, height: 12))
          }
        }
      }
    }.jpegData(compressionQuality: 0.95)!
  }

  private func imageData(color: UIColor = .brown, size: CGSize = CGSize(width: 640, height: 480)) -> Data {
    let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      // The shared default stands in for an analysis-eligible photo across
      // lifecycle tests. A uniform brown rectangle is now correctly rejected
      // as near-blank, so only that default uses deterministic texture;
      // explicit color fixtures remain uniform for their original assertions.
      guard color.isEqual(UIColor.brown) else {
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        return
      }
      UIColor(white: 0.52, alpha: 1).setFill()
      context.fill(CGRect(origin: .zero, size: size))
      let insetX = size.width * 0.16
      let insetY = size.height * 0.22
      let cell = max(6, min(size.width, size.height) / 64)
      var row = 0
      for y in stride(from: insetY, to: size.height - insetY, by: cell) {
        var column = 0
        for x in stride(from: insetX, to: size.width - insetX, by: cell) {
          let tone: UIColor = (row + column).isMultiple(of: 2)
            ? UIColor(red: 0.46, green: 0.25, blue: 0.10, alpha: 1)
            : UIColor(red: 0.67, green: 0.42, blue: 0.20, alpha: 1)
          tone.setFill()
          context.fill(CGRect(x: x, y: y, width: cell, height: cell))
          column += 1
        }
        row += 1
      }
    }.jpegData(compressionQuality: 0.9)!
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("GITimelineTests-\(UUID().uuidString)", isDirectory: true)
  }

  private func tinyDescriptor(data: Data) throws -> ModelDescriptor {
    try ModelDescriptor(
      id: "test-model-v1",
      family: "Synthetic test model",
      modelID: "official/test-model",
      artifactFilename: "test-model.litertlm",
      sourceRevision: String(repeating: "a", count: 40),
      sourceURL: "https://example.invalid/official/test-model",
      expectedSHA256: hexSHA256(data),
      expectedBytes: Int64(data.count),
      cacheNamespace: "test-model-v1",
      minimumMemoryGB: 1
    )
  }

  private func hexSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func makeHarness(
    scripts: [MockInferenceService.Script] = [],
    inference: (any TimelineInferenceServing)? = nil,
    photoSuggestionEngine: (any PhotoSuggestionEngine)? = nil,
    modelReady: Bool = true,
    modelVerified: Bool? = nil,
    failPrepare: Bool = false,
    prepareDelayNanoseconds: UInt64 = 0,
    analysisTimeout: Duration = .seconds(30),
    preparationTimeout: Duration = .seconds(15),
    preparationHandoff: @escaping @Sendable () async -> Void = {},
    automaticAnalysisHandoff: @escaping @Sendable () async -> Void = {},
    descriptor: ModelDescriptor? = .galleryGemma3nE2B,
    configuration: InferenceConfiguration = .deterministicBaseline,
    executionLocation: InferenceExecutionLocation = .currentAppLocal,
    autoAnalysisEnabled: Bool = false,
    requiresFullAppRestartAfterCancellation: Bool = false,
    snapshotSaveFailureInjector: DraftSnapshotStore.SaveFailureInjector? = nil,
    snapshotItemRemover: DraftSnapshotStore.ItemRemover? = nil,
    postCommitCleanupInterruption: @escaping @MainActor () -> Bool = { false }
  ) throws -> Harness {
    let root = temporaryRoot()
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let draftSnapshotStore = DraftSnapshotStore(
      imageStore: imageStore,
      saveFailureInjector: snapshotSaveFailureInjector,
      itemRemover: snapshotItemRemover
    )
    let store = try FailingEntryStore()
    let inferenceService: any TimelineInferenceServing
    if let inference {
      inferenceService = inference
    } else {
      inferenceService = MockInferenceService(
        scripts: scripts,
        failPrepare: failPrepare,
        initiallyReady: modelReady && !failPrepare,
        prepareDelayNanoseconds: prepareDelayNanoseconds,
        requiresFullAppRestartAfterCancellation: requiresFullAppRestartAfterCancellation
      )
    }
    let viewModel = NewEntryViewModel(
      imageStore: imageStore,
      draftSnapshotStore: draftSnapshotStore,
      store: store,
      inference: inferenceService,
      photoSuggestionEngine: photoSuggestionEngine,
      descriptor: descriptor,
      modelVerified: modelVerified ?? modelReady,
      engineReady: modelReady && !failPrepare,
      configuration: configuration,
      executionLocation: executionLocation,
      analysisTimeout: analysisTimeout,
      preparationTimeout: preparationTimeout,
      preparationHandoff: preparationHandoff,
      automaticAnalysisHandoff: automaticAnalysisHandoff,
      autoAnalysisEnabled: autoAnalysisEnabled,
      postCommitCleanupInterruption: postCommitCleanupInterruption
    )
    return Harness(root: root, imageStore: imageStore, store: store, viewModel: viewModel)
  }
}

@MainActor private struct Harness {
  let root: URL
  let imageStore: ImageStore
  let store: FailingEntryStore
  let viewModel: NewEntryViewModel
  func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private actor MockPhotoSuggestionEngine: PhotoSuggestionEngine {
  enum ReceiptMutation: Equatable, Sendable {
    case requestID
    case imageSHA256
    case pixelWidth
    case pixelHeight
  }

  enum Mode: Sendable {
    case success(String)
    case successWithReceiptMutation(String, ReceiptMutation)
    case failure(PhotoSuggestionFailureReason)
  }

  struct Counts: Equatable, Sendable {
    let prepare: Int
    let suggest: Int
    let cancel: Int
  }

  static let identity = PhotoSuggestionEngineIdentity(
    providerID: "test-provider",
    modelID: "test-provider/photo-v2",
    modelRevision: "test-revision",
    modelArtifactSHA256: String(repeating: "a", count: 64),
    runtimeID: "test-runtime",
    runtimeVersion: "1.0",
    promptVersion: "test-prompt-v1",
    promptSHA256: String(repeating: "b", count: 64),
    parserVersion: PhotoSuggestionPayloadV2Parser.parserVersion,
    schemaVersion: PhotoSuggestionPayloadV2.schemaVersion,
    preprocessingVersion: "image-store-sanitized-jpeg-v1",
    analysisPipelineVersion: "test-provider-neutral-v2"
  )

  private let mode: Mode
  private var prepareCount = 0
  private var suggestCount = 0
  private var cancelCount = 0

  init(mode: Mode) { self.mode = mode }

  func prepare() async throws -> PhotoSuggestionEngineIdentity {
    prepareCount += 1
    return Self.identity
  }

  func suggest(
    _ input: PreparedPhotoSuggestionInput
  ) async throws -> PhotoSuggestionRun {
    suggestCount += 1
    let imageData = try Data(contentsOf: input.url)
    guard Self.sha256(imageData) == input.sha256 else {
      throw Self.failure(
        input: input,
        reason: .invalidInput,
        rawOutputUTF8: nil
      )
    }
    let raw: String
    let mutation: ReceiptMutation?
    switch mode {
    case .failure(let reason):
      throw Self.failure(
        input: input,
        reason: reason,
        rawOutputUTF8: nil
      )
    case .success(let value):
      raw = value
      mutation = nil
    case .successWithReceiptMutation(let value, let receiptMutation):
      raw = value
      mutation = receiptMutation
    }
    return try Self.run(input: input, raw: raw, mutation: mutation)
  }

  func cancel(
    requestID: UUID
  ) async -> PhotoSuggestionCancellationDisposition {
    cancelCount += 1
    return .settled
  }

  func counts() -> Counts {
    Counts(
      prepare: prepareCount,
      suggest: suggestCount,
      cancel: cancelCount
    )
  }

  private static func failure(
    input: PreparedPhotoSuggestionInput,
    reason: PhotoSuggestionFailureReason,
    rawOutputUTF8: Data?
  ) -> PhotoSuggestionEngineError {
    let at = Date(timeIntervalSince1970: 1_730_000_000)
    return PhotoSuggestionEngineError(
      requestID: input.requestID,
      reason: reason,
      identity: identity,
      analyzedImageSHA256: input.sha256,
      startedAt: at,
      endedAt: at,
      modelCallCount: 1,
      repairCallCount: 0,
      rawOutputUTF8: rawOutputUTF8,
      rawOutputUTF8SHA256: rawOutputUTF8.map(sha256),
      requiresFullAppRestart: false
    )
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func run(
    input: PreparedPhotoSuggestionInput,
    raw: String,
    mutation: ReceiptMutation?
  ) throws -> PhotoSuggestionRun {
    let rawOutputUTF8 = Data(raw.utf8)
    let suggestion = try PhotoSuggestionPayloadV2Parser.parse(raw)
    let canonical = try PhotoSuggestionPayloadV2Parser.canonicalJSON(
      suggestion
    )
    let startedAt = Date(timeIntervalSince1970: 1_730_000_000)
    let endedAt = startedAt
    let receipt = PhotoSuggestionEngineReceipt(
      requestID: mutation == .requestID ? UUID() : input.requestID,
      identity: Self.identity,
      analyzedImageSHA256: mutation == .imageSHA256
        ? String(repeating: "c", count: 64) : input.sha256,
      analyzedPixelWidth: input.pixelWidth + (mutation == .pixelWidth ? 1 : 0),
      analyzedPixelHeight: input.pixelHeight + (mutation == .pixelHeight ? 1 : 0),
      startedAt: startedAt,
      endedAt: endedAt,
      latencyMilliseconds: 0,
      rawOutputUTF8Base64: rawOutputUTF8.base64EncodedString(),
      rawOutputUTF8SHA256: sha256(rawOutputUTF8),
      rawOutputUTF8ByteCount: rawOutputUTF8.count,
      canonicalParsedJSON: canonical,
      modelCallCount: 1,
      repairCallCount: 0
    )
    return PhotoSuggestionRun(
      suggestion: suggestion,
      rawOutputUTF8: rawOutputUTF8,
      canonicalParsedJSON: canonical,
      receipt: receipt
    )
  }
}

/// Holds each provider call past Swift-task cancellation so lifecycle tests can
/// prove that a late native result never overwrites the manual fallback.
private actor DelayedPhotoSuggestionEngine: PhotoSuggestionEngine {
  private struct PendingCall {
    let input: PreparedPhotoSuggestionInput
    let continuation: CheckedContinuation<PhotoSuggestionRun, Error>
  }

  private var pending: [Int: PendingCall] = [:]
  private var inputs: [PreparedPhotoSuggestionInput] = []
  private var prepareCount = 0
  private var suggestCount = 0
  private var cancelCount = 0
  private let cancellationDisposition: PhotoSuggestionCancellationDisposition

  init(cancellationDisposition: PhotoSuggestionCancellationDisposition = .settled) {
    self.cancellationDisposition = cancellationDisposition
  }

  func prepare() async throws -> PhotoSuggestionEngineIdentity {
    prepareCount += 1
    return MockPhotoSuggestionEngine.identity
  }

  func suggest(
    _ input: PreparedPhotoSuggestionInput
  ) async throws -> PhotoSuggestionRun {
    let callIndex = suggestCount
    suggestCount += 1
    inputs.append(input)
    return try await withCheckedThrowingContinuation { continuation in
      pending[callIndex] = PendingCall(
        input: input,
        continuation: continuation
      )
    }
  }

  func cancel(
    requestID: UUID
  ) async -> PhotoSuggestionCancellationDisposition {
    cancelCount += 1
    return cancellationDisposition
  }

  func complete(callIndex: Int, raw: String) {
    guard let call = pending.removeValue(forKey: callIndex) else { return }
    do {
      call.continuation.resume(returning: try MockPhotoSuggestionEngine.run(
        input: call.input,
        raw: raw,
        mutation: nil
      ))
    } catch {
      call.continuation.resume(throwing: error)
    }
  }

  func counts() -> MockPhotoSuggestionEngine.Counts {
    .init(prepare: prepareCount, suggest: suggestCount, cancel: cancelCount)
  }

  func requestIDs() -> [UUID] { inputs.map(\.requestID) }
}

/// Holds only engine initialization past Swift cancellation. This isolates the
/// lifecycle boundary under test from provider inference/receipt behavior.
private actor DelayedPreparationPhotoSuggestionEngine: PhotoSuggestionEngine {
  private var preparationContinuations: [Int: CheckedContinuation<PhotoSuggestionEngineIdentity, Error>] = [:]
  private var prepareCount = 0
  private var suggestCount = 0
  private var cancelCount = 0

  func prepare() async throws -> PhotoSuggestionEngineIdentity {
    let callIndex = prepareCount
    prepareCount += 1
    return try await withCheckedThrowingContinuation { continuation in
      preparationContinuations[callIndex] = continuation
    }
  }

  func suggest(
    _ input: PreparedPhotoSuggestionInput
  ) async throws -> PhotoSuggestionRun {
    suggestCount += 1
    throw CocoaError(.fileReadUnknown)
  }

  func cancel(
    requestID: UUID
  ) async -> PhotoSuggestionCancellationDisposition {
    cancelCount += 1
    return .settled
  }

  func completePreparation(callIndex: Int = 0) {
    preparationContinuations.removeValue(forKey: callIndex)?
      .resume(returning: MockPhotoSuggestionEngine.identity)
  }

  func failPreparation(callIndex: Int = 0) {
    preparationContinuations.removeValue(forKey: callIndex)?
      .resume(throwing: CocoaError(.fileReadCorruptFile))
  }

  func counts() -> MockPhotoSuggestionEngine.Counts {
    .init(prepare: prepareCount, suggest: suggestCount, cancel: cancelCount)
  }
}

/// Pauses only the success-to-analysis handoff so a lifecycle transition can
/// deterministically occur after preparation succeeded but before it queues a
/// provider suggestion.
private actor DelayedPreparationHandoff {
  private var continuation: CheckedContinuation<Void, Never>?
  private var startCount = 0

  func wait() async {
    startCount += 1
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func hasStarted(count: Int = 1) -> Bool { startCount >= count }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

/// Mirrors a PhotosPicker transfer that finishes only after the app crossed a
/// privacy boundary. The view model must retain its eventual bytes manually.
private actor DelayedPhotoTransfer {
  private var continuation: CheckedContinuation<Data?, Error>?
  private var started = false

  func load() async throws -> Data? {
    started = true
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
    }
  }

  func hasStarted() -> Bool { started }

  func complete(_ data: Data) {
    continuation?.resume(returning: data)
    continuation = nil
  }
}

/// Models the coordinator's brief interval between a cancellation request and
/// its final safe-release versus quarantine disposition. During that interval
/// an eager status query deliberately returns a conservative transient `true`,
/// making a premature UI query observable in regression tests.
private actor SettlementAwareInferenceService: TimelineInferenceServing {
  private let finalRequiresRestart: Bool
  private var started = false
  private var settled = false
  private var statusQueryCount = 0
  private var queriedBeforeSettlement = false

  init(finalRequiresRestart: Bool) {
    self.finalRequiresRestart = finalRequiresRestart
  }

  func prepare() -> EnginePreparationResult {
    EnginePreparationResult(seconds: 0, reusedCurrentProcessEngine: true)
  }

  func engineState() -> EngineProcessState { .ready }

  func analyze(draftURL: URL, expectedSHA256: String) async throws -> String {
    started = true
    do {
      try await Task.sleep(for: .seconds(5))
      settled = true
      return "{}"
    } catch {
      // Ignore the parent task's cancellation only long enough to make the
      // settlement interleaving deterministic for the view-model regression.
      await Task.detached {
        try? await Task.sleep(for: .milliseconds(50))
      }.value
      settled = true
      throw error
    }
  }

  func repair(draftURL: URL, errors: String) throws -> String { throw CancellationError() }
  func discardRepairContext(draftURL: URL) {}

  func requiresFullAppRestartAfterCancellation() -> Bool {
    statusQueryCount += 1
    if !settled {
      queriedBeforeSettlement = true
      return true
    }
    return finalRequiresRestart
  }

  func hasStarted() -> Bool { started }
  func hasSettled() -> Bool { settled }
  func queryCount() -> Int { statusQueryCount }
  func wasQueriedBeforeSettlement() -> Bool { queriedBeforeSettlement }
}

@MainActor private final class SnapshotSaveFault {
  var shouldFail = false
  private(set) var invocationCount = 0

  func run() throws {
    invocationCount += 1
    guard shouldFail else { return }
    throw CocoaError(.fileWriteUnknown)
  }
}

@MainActor private final class ProtectedDataAvailability {
  var isAvailable: Bool

  init(isAvailable: Bool) {
    self.isAvailable = isAvailable
  }
}

@MainActor private final class PostCommitCleanupInterruption {
  var shouldInterrupt = false
}

@MainActor private final class DraftRemovalFault {
  var shouldFail = false

  func remove(_ url: URL) throws {
    if shouldFail, url.pathExtension.lowercased() == "jpg" {
      throw CocoaError(.fileWriteUnknown)
    }
    try FileManager.default.removeItem(at: url)
  }
}

#if !APPSTORE_RELEASE_TESTING
private final class SynchronousDiagnosticCancellationProbe: @unchecked Sendable {
  private let started = DispatchSemaphore(value: 0)
  private let release = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var events: [String] = []
  private var storedCancelInvocationCount = 0
  private var storedDidFinish = false

  var cancelInvocationCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedCancelInvocationCount
  }

  var didFinish: Bool {
    lock.lock()
    defer { lock.unlock() }
    return storedDidFinish
  }

  var cancelReturnedBeforeFinish: Bool {
    event("cancel-return") < event("finish")
  }

  var cancelReturnedBeforeTelemetry: Bool {
    event("cancel-return") < event("telemetry")
  }

  func cancelNativeGeneration() {
    lock.lock()
    storedCancelInvocationCount += 1
    events.append("cancel-start")
    lock.unlock()
    started.signal()
    release.wait()
    record("cancel-return")
  }

  func recordTelemetry() { record("telemetry") }

  func recordImmediateCancel() {
    lock.lock()
    storedCancelInvocationCount += 1
    lock.unlock()
  }

  func recordFinished(_ cause: SynchronousDiagnosticCancellation.Cause?) {
    lock.lock()
    events.append("finish")
    storedDidFinish = true
    lock.unlock()
  }

  func waitUntilCancelStarted() async -> Bool {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        continuation.resume(
          returning: self.started.wait(timeout: .now() + 1) == .success
        )
      }
    }
  }

  func releaseNativeCancellation() { release.signal() }

  private func record(_ value: String) {
    lock.lock()
    events.append(value)
    lock.unlock()
  }

  private func event(_ value: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    return events.firstIndex(of: value) ?? .max
  }
}
#endif

private final class StreamingCancellationProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: AsyncThrowingStream<String, Error>.Continuation?
  private var storedCancellationCount = 0
  private var storedFirstElementCount = 0

  var cancellationCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedCancellationCount
  }

  var firstElementCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedFirstElementCount
  }

  func stream() -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      lock.lock()
      self.continuation = continuation
      lock.unlock()
    }
  }

  func cancel() {
    lock.lock()
    storedCancellationCount += 1
    let continuation = continuation
    lock.unlock()
    continuation?.finish(throwing: CancellationError())
  }

  func recordFirstElement() {
    lock.lock()
    storedFirstElementCount += 1
    lock.unlock()
  }

  func finishNormallyAfterCancellation() {
    lock.lock()
    storedCancellationCount += 1
    let continuation = continuation
    lock.unlock()
    continuation?.finish()
  }
}
