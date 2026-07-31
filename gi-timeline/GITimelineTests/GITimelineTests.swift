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

  func testTimeoutKeepsLocksUntilCompletionDiscardsLateResultAndLocksModelImport() async throws {
    let harness = try makeHarness(scripts: [.slow(valid, nanoseconds: 80_000_000)], analysisTimeout: .milliseconds(10))
    defer { harness.cleanup() }
    try harness.viewModel.prepareImageData(imageData())
    XCTAssertTrue(harness.viewModel.canImportModel)

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
    corrupt.viewModel.analyze()
    await waitForAnalysis(corrupt.viewModel)
    XCTAssertNil(corrupt.viewModel.reviewedObservation)
    XCTAssertTrue(corrupt.viewModel.canImportModel)
    XCTAssertEqual(corrupt.viewModel.statusMessage, "AI analysis unavailable — you can still save this entry manually")
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
    let input = EntryInput(id: UUID(), capturedAt: Date(), draftURL: root.appendingPathComponent("unused"), imageSHA256: "hash", redBlood: nil, blackTarry: nil, dizziness: nil, severePain: nil, note: nil, provenance: .manual, reviewedAt: nil, originalAIJSON: nil, reviewedJSON: nil, modelID: nil, imageFilename: "missing.jpg")
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

  private func makeHarness(scripts: [MockInferenceService.Script] = [], modelReady: Bool = true, failPrepare: Bool = false, analysisTimeout: Duration = .seconds(30)) throws -> Harness {
    let root = temporaryRoot()
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let store = try FailingEntryStore()
    let viewModel = NewEntryViewModel(imageStore: imageStore, store: store, inference: MockInferenceService(scripts: scripts, failPrepare: failPrepare), modelReady: modelReady, analysisTimeout: analysisTimeout)
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
