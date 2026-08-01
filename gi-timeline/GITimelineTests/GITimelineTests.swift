import CryptoKit
import ImageIO
import GITimelineCore
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
    XCTAssertTrue(harness.viewModel.canSave)
    XCTAssertEqual(harness.viewModel.statusMessage, "AI analysis unavailable — you can still save this entry manually")

    harness.viewModel.save()
    XCTAssertEqual(harness.store.records.count, 1)
    XCTAssertEqual(harness.store.records.first?.provenance, EntryProvenance.manual.rawValue)
    XCTAssertNil(harness.store.records.first?.originalAIJSON)
    XCTAssertNil(harness.store.records.first?.reviewedJSON)
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
    XCTAssertTrue(harness.viewModel.canSave)
    XCTAssertNil(harness.viewModel.statusMessage)
  }

  func testInferenceFailurePreservesDraftAndRetrySucceedsOnSameDraft() async throws {
    let harness = try makeHarness(scripts: [
      .malformed("not json"),
      .malformed("still not json"),
      .response(valid),
    ])
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draft = try XCTUnwrap(harness.viewModel.currentDraftURL)

    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    XCTAssertNil(harness.viewModel.reviewedObservation)
    XCTAssertEqual(harness.viewModel.currentDraftURL, draft)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draft.path))
    XCTAssertTrue(harness.viewModel.canAnalyze)

    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    XCTAssertNotNil(harness.viewModel.reviewedObservation)
    XCTAssertEqual(harness.viewModel.currentDraftURL, draft)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draft.path))
    XCTAssertTrue(harness.viewModel.canSave)
  }

  func testSaveFailureRollsBackCopyKeepsDraftAndRetryCreatesExactlyOne() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    let draft = try XCTUnwrap(harness.viewModel.currentDraftURL)
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

  func testSuccessfulSaveUsesSharedResetAndFreshSecondEntry() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData(color: .brown))
    harness.viewModel.redBlood = .yes
    harness.viewModel.save()
    XCTAssertNil(harness.viewModel.redBlood)
    XCTAssertEqual(harness.store.records.count, 1)

    try harness.viewModel.prepareImageData(imageData(color: .green))
    XCTAssertNil(harness.viewModel.redBlood)
    harness.viewModel.save()
    XCTAssertEqual(harness.store.records.count, 2)
    XCTAssertNotEqual(harness.store.records[0].id, harness.store.records[1].id)
    XCTAssertEqual(HistoryPresentation.manualAnalysisText, "No AI analysis was saved.")
  }

  func testReviewedProvenanceTimestampAndNilSymptomsPersist() async throws {
    let harness = try makeHarness(scripts: [.response(valid)])
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    XCTAssertNotNil(harness.viewModel.reviewedObservation)
    harness.viewModel.updateReview {
      VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: "green", form: $0.form, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: $0.blackTarryAppearance)
    }
    harness.viewModel.save()

    let entry = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(entry.provenance, EntryProvenance.ai_edited.rawValue)
    XCTAssertNotNil(entry.reviewedAt)
    XCTAssertNotEqual(entry.originalAIJSON, entry.reviewedJSON)
    let provenanceData = try XCTUnwrap(entry.modelProvenanceJSON?.data(using: .utf8))
    let modelProvenance = try JSONDecoder().decode(InferenceProvenanceSnapshot.self, from: provenanceData)
    XCTAssertEqual(modelProvenance.descriptorID, ModelDescriptor.galleryGemma3nE2B.id)
    XCTAssertEqual(modelProvenance.configuration, .deterministicBaseline)
    XCTAssertNil(entry.redBlood); XCTAssertNil(entry.blackTarry); XCTAssertNil(entry.dizziness); XCTAssertNil(entry.severePain)
    XCTAssertTrue(entry.flagSummary.isEmpty)
    XCTAssertEqual(HistoryPresentation.reportedValue(entry.redBlood), "Not recorded")
    XCTAssertEqual(HistoryPresentation.reportedValue(entry.note), "Not recorded")
  }

  func testUneditedAnalysisGetsUneditedProvenance() async throws {
    let harness = try makeHarness(scripts: [.response(valid)])
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    harness.viewModel.analyze()
    await waitForAnalysis(harness.viewModel)
    harness.viewModel.save()
    XCTAssertEqual(harness.store.records.first?.provenance, EntryProvenance.ai_unedited.rawValue)
    XCTAssertEqual(harness.store.records.first?.originalAIJSON, harness.store.records.first?.reviewedJSON)
  }

  func testEditedUnusableReviewPersistsExplicitNullAndReopens() async throws {
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
    harness.viewModel.save()

    let entry = try XCTUnwrap(harness.store.records.first)
    XCTAssertEqual(entry.provenance, EntryProvenance.ai_edited.rawValue)
    XCTAssertTrue(try XCTUnwrap(entry.reviewedJSON).contains("\"apparent_bristol_type\":null"))
    let reopened = try XCTUnwrap(entry.observation)
    XCTAssertFalse(reopened.imageUsable)
    XCTAssertNil(reopened.apparentBristolType)
    XCTAssertEqual(reopened.qualityIssue, "other")
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
    XCTAssertEqual(disconnected.viewModel.analyzeUnavailableReason, "No Gemma model is selected for this build.")

    let unverified = try makeHarness(
      modelReady: false,
      modelVerified: false,
      descriptor: .liteRTGemma4E4B,
      configuration: .simulatorCPUFallback,
      executionLocation: .simulatorLocal
    )
    defer { unverified.cleanup() }
    XCTAssertEqual(unverified.viewModel.runtimeBadgeLabel, "Gemma 4 E4B · iPhone Simulator")
    XCTAssertEqual(unverified.viewModel.analyzeUnavailableReason, "Import and verify the exact Gemma model first.")

    let unprepared = try makeHarness(
      modelReady: false,
      modelVerified: true,
      descriptor: .liteRTGemma4E4B,
      configuration: .simulatorCPUFallback,
      executionLocation: .simulatorLocal
    )
    defer { unprepared.cleanup() }
    XCTAssertEqual(unprepared.viewModel.analyzeUnavailableReason, "Prepare Gemma before analyzing.")

    let ready = try makeHarness(
      descriptor: .liteRTGemma4E4B,
      configuration: .simulatorCPUFallback,
      executionLocation: .simulatorLocal
    )
    defer { ready.cleanup() }
    XCTAssertEqual(ready.viewModel.analyzeUnavailableReason, "Choose a photo or demo image to analyze.")
    try ready.viewModel.prepareImageData(imageData())
    XCTAssertNil(ready.viewModel.analyzeUnavailableReason)
  }

  func testUIDemoAttributionAndResetMarkerDoNotTrustEditableNote() async throws {
    let demo = try makeHarness(scripts: [.response(valid)], descriptor: nil)
    defer { demo.cleanup() }
    demo.viewModel.prepareDemoFixture(.brown)
    demo.viewModel.analyze()
    await waitForAnalysis(demo.viewModel)
    demo.viewModel.save()

    let demoEntry = try XCTUnwrap(demo.store.records.first)
    XCTAssertEqual(demoEntry.demoKind, SyntheticFixture.brown.rawValue)
    XCTAssertTrue(DemoDataPolicy.isSyntheticDemo(demoEntry))
    XCTAssertTrue(demoEntry.isUIDemoProvider)
    XCTAssertEqual(demoEntry.savedRuntimeLabel, "UI demo · Gemma not connected")

    let manual = try makeHarness()
    defer { manual.cleanup() }
    try manual.viewModel.prepareImageData(imageData())
    manual.viewModel.note = "\(DemoDataPolicy.notePrefix) typed by a person"
    manual.viewModel.save()
    let manualEntry = try XCTUnwrap(manual.store.records.first)
    XCTAssertNil(manualEntry.demoKind)
    XCTAssertFalse(DemoDataPolicy.isSyntheticDemo(manualEntry))
  }

  func testTimeoutKeepsLocksUntilCompletionDiscardsLateResultAndLocksModelImport() async throws {
    let harness = try makeHarness(scripts: [.slow(valid, nanoseconds: 80_000_000)], analysisTimeout: .milliseconds(10))
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    XCTAssertFalse(harness.viewModel.canImportModel)

    harness.viewModel.analyze()
    XCTAssertFalse(harness.viewModel.canAnalyze)
    XCTAssertFalse(harness.viewModel.canSave)
    XCTAssertFalse(harness.viewModel.canImportModel)
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertTrue(harness.viewModel.isBusy)
    XCTAssertEqual(harness.viewModel.statusMessage, "AI analysis timed out — waiting for the local engine to finish")

    await waitForAnalysis(harness.viewModel)
    XCTAssertNil(harness.viewModel.reviewedObservation)
    XCTAssertTrue(harness.viewModel.canSave)
    XCTAssertFalse(harness.viewModel.canImportModel)
    XCTAssertEqual(harness.viewModel.statusMessage, "AI analysis timed out — you can still save this entry manually")
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
    XCTAssertTrue(corrupt.viewModel.canSave)
    XCTAssertEqual(corrupt.viewModel.statusMessage, "Local model preparation failed — you can still save manually")
  }

  func testDeleteFailureKeepsEntryAndImageThenSuccessRemovesBoth() throws {
    let harness = try makeHarness()
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
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

  func testReconciliationDeletesOrphanAndMarksMissingImage() throws {
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

    try EntryStore(context: context).reconcile(imageStore: imageStore)

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
    let inference = MockInferenceService(scripts: [.response("{}")])
    _ = try await inference.analyze(draftURL: URL(fileURLWithPath: "/tmp/fixture.jpg"))
    let store = try FailingEntryStore(); store.failNextSave = true
    XCTAssertTrue(store.failNextSave)
  }

  private func waitForAnalysis(_ viewModel: NewEntryViewModel) async {
    for _ in 0..<200 where viewModel.isBusy { try? await Task.sleep(for: .milliseconds(10)) }
    XCTAssertFalse(viewModel.isBusy, "analysis did not complete within the test window")
  }

  private func imageData(color: UIColor = .brown, size: CGSize = CGSize(width: 640, height: 480)) -> Data {
    let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { context in color.setFill(); context.fill(CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.9)!
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
    modelReady: Bool = true,
    modelVerified: Bool? = nil,
    failPrepare: Bool = false,
    prepareDelayNanoseconds: UInt64 = 0,
    analysisTimeout: Duration = .seconds(30),
    descriptor: ModelDescriptor? = .galleryGemma3nE2B,
    configuration: InferenceConfiguration = .deterministicBaseline,
    executionLocation: InferenceExecutionLocation = .currentAppLocal
  ) throws -> Harness {
    let root = temporaryRoot()
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let store = try FailingEntryStore()
    let viewModel = NewEntryViewModel(
      imageStore: imageStore,
      store: store,
      inference: MockInferenceService(scripts: scripts, failPrepare: failPrepare, initiallyReady: modelReady && !failPrepare, prepareDelayNanoseconds: prepareDelayNanoseconds),
      descriptor: descriptor,
      modelVerified: modelVerified ?? modelReady,
      engineReady: modelReady && !failPrepare,
      configuration: configuration,
      executionLocation: executionLocation,
      analysisTimeout: analysisTimeout
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
