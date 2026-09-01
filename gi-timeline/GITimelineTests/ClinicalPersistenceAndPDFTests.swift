import XCTest
import SwiftData
import PDFKit
import UIKit
import CryptoKit
import GITimelineCore
@testable import GITimeline

@MainActor final class ClinicalPersistenceAndPDFTests: XCTestCase {
  private func temporaryRoot() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("GIJournalDataPDFTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func container() throws -> ModelContainer {
    let schema = Schema([EntryRecord.self, DailyCompletionRecord.self, TreatmentEventRecord.self])
    return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
  }

  func testPersistenceIsolationAttestationIsExclusiveToExplicitEphemeralBootstrap() throws {
    let ephemeral = PersistenceBootstrap.makeEphemeral()
    XCTAssertTrue(ephemeral.permitsJournalPresentation)
    XCTAssertTrue(ephemeral.isEphemeral)

    let publicResult = PersistenceBootstrap.open(
      publicStoreURL: URL(fileURLWithPath: "/synthetic/GITimeline.store"),
      openPublicStore: { _ in try self.container() }
    )
    XCTAssertTrue(publicResult.permitsJournalPresentation)
    XCTAssertFalse(publicResult.isEphemeral)

    let blockedResult = PersistenceBootstrap.open(
      publicStoreURL: URL(fileURLWithPath: "/synthetic/GITimeline.store"),
      openPublicStore: { _ in throw CocoaError(.fileReadUnknown) },
      makeRecoveryContainer: { try self.container() }
    )
    XCTAssertFalse(blockedResult.permitsJournalPresentation)
    XCTAssertFalse(blockedResult.isEphemeral)
  }

  private func assertNoRetiredTransferVocabulary(
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let lowercased = message.lowercased()
    XCTAssertFalse(lowercased.contains("recovery"), file: file, line: line)
    XCTAssertFalse(lowercased.contains("restore"), file: file, line: line)
  }

  private func input(
    id: UUID = UUID(),
    draftURL: URL? = nil,
    hash: String? = nil,
    filename: String? = nil,
    note: String? = nil,
    markedAt: Date? = nil,
    confirmedBristolType: Int? = 4,
    originalAIJSON: String? = nil,
    reviewedJSON: String? = nil
  ) -> EntryInput {
    EntryInput(
      id: id,
      capturedAt: Date(timeIntervalSince1970: 1_710_000_000),
      draftURL: draftURL,
      imageSHA256: hash,
      redBlood: .unsure,
      blackTarry: .no,
      dizziness: .no,
      severePain: .no,
      note: note,
      painScore: 3,
      urgency: .moderate,
      confirmedBristolType: confirmedBristolType,
      confirmedPhotoUsable: draftURL == nil ? nil : true,
      mixedForm: .no,
      strainingOrIncomplete: .no,
      leakageOrAccident: nil,
      analysisSource: .manual,
      analysisPipelineVersion: nil,
      markedForDiscussionAt: markedAt,
      provenance: .manual,
      reviewedAt: nil,
      originalAIJSON: originalAIJSON,
      reviewedJSON: reviewedJSON,
      modelID: nil,
      modelProvenanceJSON: nil,
      demoKind: nil,
      imageFilename: filename
    )
  }

  private func validImageData(
    color: UIColor = .brown,
    size: CGSize = CGSize(width: 64, height: 48)
  ) -> Data {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { context in
      color.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }
    return image.jpegData(compressionQuality: 0.9)!
  }

  private func writeSanitizedJournalPhoto(
    to photoDirectory: URL,
    id: UUID,
    color: UIColor = .brown,
    size: CGSize = CGSize(width: 64, height: 48)
  ) throws -> (filename: String, hash: String, bytes: Data) {
    let imageStore = ImageStore(
      draftsDirectory: photoDirectory.appendingPathComponent("Drafts", isDirectory: true),
      imagesDirectory: photoDirectory,
      writeGate: .unrestricted
    )
    let prepared = try imageStore.prepare(validImageData(color: color, size: size))
    let destination = try imageStore.promotedURL(for: id)
    try imageStore.promoteVerifiedDraft(
      prepared.url,
      to: destination,
      expectedSHA256: prepared.reference.sha256
    )
    return (
      destination.lastPathComponent,
      prepared.reference.sha256,
      try Data(contentsOf: destination)
    )
  }

  private func preparedPhotoInput(
    _ imageStore: ImageStore,
    id: UUID = UUID(),
    color: UIColor = .brown
  ) throws -> (input: EntryInput, prepared: PreparedDraft) {
    let prepared = try imageStore.prepare(validImageData(color: color))
    return (
      input: input(
        id: id,
        draftURL: prepared.url,
        hash: prepared.reference.sha256,
        filename: "\(id.uuidString).jpg"
      ),
      prepared: prepared
    )
  }

  private struct PDFImageObject: Hashable {
    let width: Int
    let height: Int
    let isImageMask: Bool

    var pixelSize: CGSize {
      CGSize(width: width, height: height)
    }
  }

  private final class PDFImageCollector {
    var seen = Set<CGPDFStreamRef>()
    var images: [PDFImageObject] = []

    func scan(resources: CGPDFDictionaryRef) {
      var xObjects: CGPDFDictionaryRef?
      guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects),
        let xObjects
      else { return }

      CGPDFDictionaryApplyBlock(xObjects, { _, object, _ in
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream),
          let stream,
          self.seen.insert(stream).inserted,
          let dictionary = CGPDFStreamGetDictionary(stream)
        else { return true }

        var subtypeName: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtypeName),
          let subtypeName
        else { return true }

        switch String(cString: subtypeName) {
        case "Image":
          var width: CGPDFInteger = 0
          var height: CGPDFInteger = 0
          var isImageMask = false
          guard CGPDFDictionaryGetInteger(dictionary, "Width", &width),
            CGPDFDictionaryGetInteger(dictionary, "Height", &height)
          else { return true }

          _ = CGPDFDictionaryGetBoolean(dictionary, "ImageMask", &isImageMask)
          self.images.append(
            PDFImageObject(
              width: width,
              height: height,
              isImageMask: isImageMask
            )
          )
        case "Form":
          var nestedResources: CGPDFDictionaryRef?
          if CGPDFDictionaryGetDictionary(
            dictionary,
            "Resources",
            &nestedResources
          ), let nestedResources {
            self.scan(resources: nestedResources)
          }
        default:
          break
        }
        return true
      }, nil)
    }
  }

  private func embeddedPDFImages(
    in data: Data,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> [PDFImageObject] {
    let provider = try XCTUnwrap(
      CGDataProvider(data: data as CFData),
      file: file,
      line: line
    )
    let document = try XCTUnwrap(
      CGPDFDocument(provider),
      file: file,
      line: line
    )
    let collector = PDFImageCollector()
    guard document.numberOfPages > 0 else {
      XCTFail("PDF has no pages.", file: file, line: line)
      return []
    }

    for pageNumber in 1...document.numberOfPages {
      guard let pageDictionary = document.page(at: pageNumber)?.dictionary else {
        XCTFail("Missing PDF page \(pageNumber)", file: file, line: line)
        continue
      }
      var resources: CGPDFDictionaryRef?
      if CGPDFDictionaryGetDictionary(
        pageDictionary,
        "Resources",
        &resources
      ), let resources {
        collector.scan(resources: resources)
      }
    }
    return collector.images
  }

  private struct LegacyV0Fixture: Decodable {
    let fixtureVersion: Int
    let purpose: String
    let id: UUID
    let capturedAt: Date
    let imageFilename: String?
    let imageSHA256: String?
    let redBlood: String?
    let blackTarry: String?
    let dizziness: String?
    let severePain: String?
    let note: String?
    let painScore: Int?
    let urgency: String?
    let bm24h: Int?
    let confirmedBristolType: Int?
    let confirmedPhotoUsable: Bool?
    let mixedForm: String?
    let strainingOrIncomplete: String?
    let leakageOrAccident: String?
    let analysisSource: String?
    let analysisPipelineVersion: String?
    let markedForDiscussionAt: Date?
    let provenance: String
    let reviewedAt: Date?
    let originalAIJSON: String?
    let reviewedJSON: String?
    let modelID: String?
    let modelProvenanceJSON: String?
    let demoKind: String?
    let imageUnavailable: Bool
    let createdAt: Date
    let updatedAt: Date

    func entryInput() -> EntryInput {
      EntryInput(
        id: id,
        capturedAt: capturedAt,
        draftURL: nil,
        imageSHA256: imageSHA256,
        redBlood: redBlood.flatMap(SymptomFlag.init(rawValue:)),
        blackTarry: blackTarry.flatMap(SymptomFlag.init(rawValue:)),
        dizziness: dizziness.flatMap(SymptomFlag.init(rawValue:)),
        severePain: severePain.flatMap(SymptomFlag.init(rawValue:)),
        note: note,
        painScore: painScore,
        urgency: urgency.flatMap(UrgencyLevel.init(rawValue:)),
        confirmedBristolType: confirmedBristolType,
        confirmedPhotoUsable: confirmedPhotoUsable,
        mixedForm: mixedForm.flatMap(ClinicalTriState.init(rawValue:)),
        strainingOrIncomplete: strainingOrIncomplete.flatMap(ClinicalTriState.init(rawValue:)),
        leakageOrAccident: leakageOrAccident.flatMap(ClinicalTriState.init(rawValue:)),
        analysisSource: analysisSource.flatMap(AnalysisSource.init(rawValue:)),
        analysisPipelineVersion: analysisPipelineVersion,
        markedForDiscussionAt: markedForDiscussionAt,
        provenance: EntryProvenance(rawValue: provenance) ?? .manual,
        reviewedAt: reviewedAt,
        originalAIJSON: originalAIJSON,
        reviewedJSON: reviewedJSON,
        modelID: modelID,
        modelProvenanceJSON: modelProvenanceJSON,
        demoKind: demoKind,
        imageFilename: imageFilename
      )
    }
  }

  private func legacyV0Fixture() throws -> LegacyV0Fixture {
    let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "legacy-v0-synthetic-entry", withExtension: "json"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(LegacyV0Fixture.self, from: Data(contentsOf: fixtureURL))
  }

  func testClinicalSummaryIncludesEveryRequiredMetricAndDenominator() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_720_000_000)
    let interval = LocalDayInterval(
      start: start,
      end: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start)),
      totalDays: 1,
      isPartial: false
    )
    let types = [1, 3, 5, 6, 7]
    let pains = [0, 2, 4, 6, 8]
    let entries = types.enumerated().map { index, type in
      ClinicalEntrySnapshot(
        id: UUID(),
        capturedAt: start.addingTimeInterval(Double(index + 1) * 60),
        confirmedBristolType: type,
        suggestedBristolType: index == 0 || index == 3 ? type + 1 : type,
        hasOriginalAIObservation: true,
        confirmedPhotoUsable: index == 0 ? false : true,
        mixedForm: index == 0 || index == 4 ? .yes : .no,
        painScore: pains[index],
        urgency: index == 0 || index == 4 ? .severe : .moderate,
        strainingOrIncomplete: type <= 5 ? (index == 0 || index == 2 ? .yes : .no) : nil,
        leakageOrAccident: type >= 6 ? (index == 4 ? .yes : .no) : nil,
        redBlood: index == 0 ? .yes : (index == 1 ? .unsure : .no),
        blackTarry: index == 2 ? .yes : (index == 3 ? .unsure : .no)
      )
    }
    let summary = TreatmentResponseCalculator(calendar: calendar, timeZone: calendar.timeZone)
      .summarize(interval: interval, entries: entries, completions: [])

    XCTAssertEqual(summary.bristolGroups.type1To2, 1)
    XCTAssertEqual(summary.bristolGroups.type3To5, 2)
    XCTAssertEqual(summary.bristolGroups.type6To7, 2)
    XCTAssertEqual(summary.bristolGroups.denominator, 5)
    XCTAssertEqual(summary.consistencies.hard, 1)
    XCTAssertEqual(summary.consistencies.formed, 1)
    XCTAssertEqual(summary.consistencies.soft, 1)
    XCTAssertEqual(summary.consistencies.loose, 1)
    XCTAssertEqual(summary.consistencies.watery, 1)
    XCTAssertEqual(summary.consistencies.mixedConfirmed, 2)
    XCTAssertEqual(summary.medianPain, 4)
    XCTAssertEqual(summary.painDenominator, 5)
    XCTAssertEqual(summary.severeUrgency, .init(count: 2, denominator: 5))
    XCTAssertEqual(summary.strainingYes, .init(count: 2, denominator: 3))
    XCTAssertEqual(summary.leakageYes, .init(count: 1, denominator: 2))
    XCTAssertEqual(summary.unusablePhotoCount, 1)
    XCTAssertEqual(summary.bristolCorrectionCount, 2)
    XCTAssertEqual(summary.redBloodYes, .init(count: 1, denominator: 5))
    XCTAssertEqual(summary.redBloodUnsure, .init(count: 1, denominator: 5))
    XCTAssertEqual(summary.blackTarryYes, .init(count: 1, denominator: 5))
    XCTAssertEqual(summary.blackTarryUnsure, .init(count: 1, denominator: 5))

    let original = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
    let reviewed = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":6,\"apparent_color\":\"brown\",\"form\":\"mushy\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
    let persisted = EntryRecord(input: input(confirmedBristolType: 6, originalAIJSON: original, reviewedJSON: reviewed))
    XCTAssertEqual(persisted.originalObservation?.apparentBristolType, 4)
    XCTAssertEqual(persisted.observation?.apparentBristolType, 6)
    let persistedSummary = TreatmentResponseCalculator(calendar: calendar, timeZone: calendar.timeZone).summarize(
      interval: interval,
      entries: [ClinicalEntrySnapshot(
        id: persisted.id,
        capturedAt: start.addingTimeInterval(300),
        confirmedBristolType: persisted.effectiveConfirmedBristolType,
        suggestedBristolType: persisted.originalObservation?.apparentBristolType,
        hasOriginalAIObservation: persisted.originalObservation != nil
      )],
      completions: []
    )
    XCTAssertEqual(persistedSummary.bristolCorrectionCount, 1)
  }

  func testNoPhotoSaveAndReconcileRemainIntentionalWhileMissingExpectedPhotoIsUnavailable() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let images = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    try store.save(input(), imageStore: images)
    let noPhoto = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
    try await store.reconcile(imageStore: images)
    XCTAssertNil(noPhoto.imageFilename)
    XCTAssertFalse(noPhoto.imageUnavailable)
    XCTAssertEqual(noPhoto.savedAnalysisSource, .manual)
    XCTAssertNil(noPhoto.originalAIJSON)
    XCTAssertNil(noPhoto.reviewedJSON)

    let missingID = UUID()
    context.insert(EntryRecord(input: input(id: missingID, draftURL: root.appendingPathComponent("missing-draft"), hash: "hash", filename: "\(missingID.uuidString).jpg")))
    try context.save()
    try await store.reconcile(imageStore: images)
    let records = try context.fetch(FetchDescriptor<EntryRecord>())
    XCTAssertTrue(try XCTUnwrap(records.first { $0.id == missingID }).imageUnavailable)
  }

  func testConfirmedConsistencyDependsOnConfirmedBristolNotPhotoUsability() throws {
    let record = EntryRecord(input: input())
    record.confirmedBristolType = 4
    record.confirmedPhotoUsable = false
    XCTAssertEqual(record.confirmedConsistency, .formed)
  }

  func testExistingEntryOnlyStoreReopensWithExpandedSchemaWithoutRewritingEntry() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    let entryID = UUID()

    do {
      let entryOnlySchema = Schema([EntryRecord.self])
      let configuration = ModelConfiguration("GITimeline", schema: entryOnlySchema, url: storeURL, cloudKitDatabase: .none)
      let oldContainer = try ModelContainer(for: entryOnlySchema, configurations: [configuration])
      let oldContext = ModelContext(oldContainer)
      oldContext.autosaveEnabled = false
      oldContext.insert(EntryRecord(input: input(id: entryID, note: "Preserve this entry")))
      try oldContext.save()
    }

    do {
      let expandedSchema = Schema([EntryRecord.self, DailyCompletionRecord.self, TreatmentEventRecord.self])
      let configuration = ModelConfiguration("GITimeline", schema: expandedSchema, url: storeURL, cloudKitDatabase: .none)
      let reopened = try ModelContainer(for: expandedSchema, configurations: [configuration])
      let context = ModelContext(reopened)
      let entries = try context.fetch(FetchDescriptor<EntryRecord>())
      XCTAssertEqual(entries.count, 1)
      XCTAssertEqual(entries.first?.id, entryID)
      XCTAssertEqual(entries.first?.note, "Preserve this entry")
      XCTAssertNil(entries.first?.analysisPipelineVersion)

      context.insert(DailyCompletionRecord(dayKey: "2026-08-01", dayStart: Date(), answer: .yes))
      context.insert(TreatmentEventRecord(effectiveDate: Date(), kind: .other, name: "Synthetic marker"))
      try context.save()
      XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
      XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyCompletionRecord>()), 1)
      XCTAssertEqual(try context.fetchCount(FetchDescriptor<TreatmentEventRecord>()), 1)
    }
  }

  func testGeneratedUnversionedStoreReopensThroughSchemaV1FieldForField() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    let fixture = try legacyV0Fixture()

    do {
      // This uses the generated, pre-VersionedSchema form of the store, not a
      // hand-authored SQLite file or a migration mock.
      let legacySchema = Schema([EntryRecord.self])
      let configuration = ModelConfiguration(PersistenceSchema.storeName, schema: legacySchema, url: storeURL, cloudKitDatabase: .none)
      let legacyContainer = try ModelContainer(for: legacySchema, configurations: [configuration])
      let legacyContext = ModelContext(legacyContainer)
      legacyContext.autosaveEnabled = false
      let record = EntryRecord(input: fixture.entryInput())
      record.bm24h = fixture.bm24h
      record.imageUnavailable = fixture.imageUnavailable
      record.createdAt = fixture.createdAt
      record.updatedAt = fixture.updatedAt
      legacyContext.insert(record)
      try legacyContext.save()
    }

    let bootstrapped = PersistenceBootstrap.open(publicStoreURL: storeURL)
    XCTAssertTrue(bootstrapped.permitsJournalPresentation)
    let context = ModelContext(try XCTUnwrap(bootstrapped.modelContainer))
    let record = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)

    XCTAssertEqual(record.id, fixture.id)
    XCTAssertEqual(record.capturedAt, fixture.capturedAt)
    XCTAssertEqual(record.imageFilename, fixture.imageFilename)
    XCTAssertEqual(record.imageSHA256, fixture.imageSHA256)
    XCTAssertEqual(record.redBlood, fixture.redBlood)
    XCTAssertEqual(record.blackTarry, fixture.blackTarry)
    XCTAssertEqual(record.dizziness, fixture.dizziness)
    XCTAssertEqual(record.severePain, fixture.severePain)
    XCTAssertEqual(record.note, fixture.note)
    XCTAssertEqual(record.painScore, fixture.painScore)
    XCTAssertEqual(record.urgency, fixture.urgency)
    XCTAssertEqual(record.bm24h, fixture.bm24h)
    XCTAssertEqual(record.confirmedBristolType, fixture.confirmedBristolType)
    XCTAssertEqual(record.confirmedPhotoUsable, fixture.confirmedPhotoUsable)
    XCTAssertEqual(record.mixedForm, fixture.mixedForm)
    XCTAssertEqual(record.strainingOrIncomplete, fixture.strainingOrIncomplete)
    XCTAssertEqual(record.leakageOrAccident, fixture.leakageOrAccident)
    XCTAssertEqual(record.analysisSource, fixture.analysisSource)
    XCTAssertEqual(record.analysisPipelineVersion, fixture.analysisPipelineVersion)
    XCTAssertEqual(record.markedForDiscussionAt, fixture.markedForDiscussionAt)
    XCTAssertEqual(record.provenance, fixture.provenance)
    XCTAssertEqual(record.reviewedAt, fixture.reviewedAt)
    XCTAssertEqual(record.originalAIJSON, fixture.originalAIJSON)
    XCTAssertEqual(record.reviewedJSON, fixture.reviewedJSON)
    XCTAssertEqual(record.modelID, fixture.modelID)
    XCTAssertEqual(record.modelProvenanceJSON, fixture.modelProvenanceJSON)
    XCTAssertEqual(record.demoKind, fixture.demoKind)
    XCTAssertEqual(record.imageUnavailable, fixture.imageUnavailable)
    XCTAssertEqual(record.createdAt, fixture.createdAt)
    XCTAssertEqual(record.updatedAt, fixture.updatedAt)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyCompletionRecord>()), 0)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TreatmentEventRecord>()), 0)
  }

  func testGeneratedCompleteUnversionedStoreReopensThroughSchemaV1() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    let entryID = UUID()
    let treatmentID = UUID()
    let day = Date(timeIntervalSince1970: 1_735_000_000)

    do {
      let unversionedSchema = Schema([EntryRecord.self, DailyCompletionRecord.self, TreatmentEventRecord.self])
      let configuration = ModelConfiguration(PersistenceSchema.storeName, schema: unversionedSchema, url: storeURL, cloudKitDatabase: .none)
      let oldContainer = try ModelContainer(for: unversionedSchema, configurations: [configuration])
      let oldContext = ModelContext(oldContainer)
      oldContext.autosaveEnabled = false
      oldContext.insert(EntryRecord(input: input(id: entryID, note: "Synthetic complete legacy store")))
      oldContext.insert(DailyCompletionRecord(dayKey: "2025-01-01", dayStart: day, answer: .yes, now: day))
      oldContext.insert(TreatmentEventRecord(id: treatmentID, effectiveDate: day, kind: .startedTreatment, name: "Synthetic treatment", doseOrNote: "Synthetic", now: day))
      try oldContext.save()
    }

    let reopened = PersistenceBootstrap.open(publicStoreURL: storeURL)
    XCTAssertTrue(reopened.permitsJournalPresentation)
    let context = ModelContext(try XCTUnwrap(reopened.modelContainer))
    XCTAssertEqual(try context.fetch(FetchDescriptor<EntryRecord>()).first?.id, entryID)
    let completion = try XCTUnwrap(try context.fetch(FetchDescriptor<DailyCompletionRecord>()).first)
    XCTAssertEqual(completion.dayKey, "2025-01-01")
    XCTAssertEqual(completion.answer, .yes)
    let treatment = try XCTUnwrap(try context.fetch(FetchDescriptor<TreatmentEventRecord>()).first)
    XCTAssertEqual(treatment.id, treatmentID)
    XCTAssertEqual(treatment.kind, .startedTreatment)
    XCTAssertEqual(treatment.name, "Synthetic treatment")
  }

  func testSavedJournalSurvivesDiskBackedColdReopenAcrossEveryEntityAndPhoto() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let entryID = UUID()
    let treatmentID = UUID()
    let capturedAt = Date(timeIntervalSince1970: 1_725_000_000)
    let markedAt = capturedAt.addingTimeInterval(90)
    let dayStart = Date(timeIntervalSince1970: 1_724_947_200)
    let treatmentDate = dayStart.addingTimeInterval(86_400)
    let imageStore = ImageStore(draftsDirectory: drafts, imagesDirectory: images)
    let prepared = try imageStore.prepare(validImageData(color: .green))
    let expectedFilename = "\(entryID.uuidString).jpg"
    let expectedHash = prepared.reference.sha256

    do {
      let container = try PersistenceSchema.openPublicStore(at: storeURL)
      let context = ModelContext(container)
      try EntryStore(context: context).save(
        input(
          id: entryID,
          draftURL: prepared.url,
          hash: expectedHash,
          filename: expectedFilename,
          note: "Synthetic restart durability fixture",
          markedAt: markedAt,
          confirmedBristolType: 4
        ),
        imageStore: imageStore
      )
      context.insert(
        DailyCompletionRecord(
          dayKey: "2024-08-30",
          dayStart: dayStart,
          answer: .yes,
          now: capturedAt
        )
      )
      context.insert(
        TreatmentEventRecord(
          id: treatmentID,
          effectiveDate: treatmentDate,
          kind: .beganFiber,
          name: "Synthetic restart marker",
          doseOrNote: "Local-only fixture",
          now: capturedAt
        )
      )
      try context.save()
    }

    // Simulate termination after a delete moved the referenced photo into the
    // protected queue but before the database delete committed. The exact app
    // bootstrap must run reconciliation and restore this photo before exposing
    // writable journal UI.
    let canonicalPhoto = try XCTUnwrap(imageStore.imageURL(filename: expectedFilename))
    let stagedPhoto = try XCTUnwrap(imageStore.stageForDeletion(canonicalPhoto))
    XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalPhoto.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: stagedPhoto.queuedURL.path))

    do {
      let reopened = await PersistenceBootstrap.openAppJournal(
        publicStoreURL: storeURL,
        resumePendingErase: { _ in nil },
        reconcileJournal: { context in
          try await EntryStore(context: context).reconcile(imageStore: imageStore)
        }
      )
      XCTAssertTrue(reopened.permitsJournalPresentation)
      let context = ModelContext(try XCTUnwrap(reopened.modelContainer))
      let entry = try XCTUnwrap(
        try context.fetch(
          FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == entryID })
        ).first
      )
      XCTAssertEqual(entry.note, "Synthetic restart durability fixture")
      XCTAssertEqual(entry.markedForDiscussionAt, markedAt)
      XCTAssertEqual(entry.imageFilename, expectedFilename)
      XCTAssertEqual(entry.imageSHA256, expectedHash)
      XCTAssertFalse(entry.imageUnavailable)
      XCTAssertTrue(
        try imageStore.storedImageIsVerified(
          filename: expectedFilename,
          expectedSHA256: expectedHash
        )
      )

      let completion = try XCTUnwrap(
        try context.fetch(
          FetchDescriptor<DailyCompletionRecord>(
            predicate: #Predicate { $0.dayKey == "2024-08-30" }
          )
        ).first
      )
      XCTAssertEqual(completion.answer, .yes)
      XCTAssertEqual(completion.dayStart, dayStart)

      let treatment = try XCTUnwrap(
        try context.fetch(
          FetchDescriptor<TreatmentEventRecord>(
            predicate: #Predicate { $0.id == treatmentID }
          )
        ).first
      )
      XCTAssertEqual(treatment.kind, .beganFiber)
      XCTAssertEqual(treatment.name, "Synthetic restart marker")
      XCTAssertEqual(treatment.doseOrNote, "Local-only fixture")
      XCTAssertEqual(treatment.effectiveDate, treatmentDate)

    }

    // A second independent open proves that reconciliation did not only leave
    // the values visible in a reused context; the same on-disk journal remains
    // authoritative for another cold launch.
    let secondReopen = await PersistenceBootstrap.openAppJournal(
      publicStoreURL: storeURL,
      resumePendingErase: { _ in nil },
      reconcileJournal: { context in
        try await EntryStore(context: context).reconcile(imageStore: imageStore)
      }
    )
    XCTAssertTrue(secondReopen.permitsJournalPresentation)
    let secondContext = ModelContext(try XCTUnwrap(secondReopen.modelContainer))
    XCTAssertEqual(try secondContext.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertEqual(try secondContext.fetchCount(FetchDescriptor<DailyCompletionRecord>()), 1)
    XCTAssertEqual(try secondContext.fetchCount(FetchDescriptor<TreatmentEventRecord>()), 1)
    XCTAssertTrue(
      try imageStore.storedImageIsVerified(
        filename: expectedFilename,
        expectedSHA256: expectedHash
      )
    )
  }

  /// The normal product claim covers more than the first save: an edited and
  /// discussion-marked photo entry, an explicit no-BM day, and a completed
  /// row deletion whose protected file cleanup was interrupted must all stay
  /// correct after the process loses its original SwiftData context.
  func testDiskBackedColdReopenPreservesEditedMarkedEntryAndNoBMWhileFinalizingPendingDelete() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let retainedID = UUID()
    let deletedID = UUID()
    let editDate = Date(timeIntervalSince1970: 1_711_086_400)
    let discussionDate = editDate.addingTimeInterval(120)
    let noBowelMovementDate = Date(timeIntervalSince1970: 1_720_000_000)
    let healthyImages = ImageStore(draftsDirectory: drafts, imagesDirectory: images)
    var expectedRetainedFilename = ""
    var expectedRetainedHash = ""
    var expectedDeletedFilename = ""

    do {
      let context = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
      let store = EntryStore(context: context)
      let (retainedInput, retainedPrepared) = try preparedPhotoInput(
        healthyImages,
        id: retainedID,
        color: .green
      )
      let (deletedInput, _) = try preparedPhotoInput(
        healthyImages,
        id: deletedID,
        color: .brown
      )
      expectedRetainedFilename = retainedInput.imageFilename!
      expectedRetainedHash = retainedPrepared.reference.sha256
      expectedDeletedFilename = deletedInput.imageFilename!
      try store.save(retainedInput, imageStore: healthyImages)
      try store.save(deletedInput, imageStore: healthyImages)

      let retained = try XCTUnwrap(
        try context.fetch(
          FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == retainedID })
        ).first
      )
      var edit = EntryEditInput(entry: retained)
      edit.capturedAt = editDate
      edit.redBlood = .yes
      edit.blackTarry = .unsure
      edit.dizziness = .yes
      edit.severePain = .no
      edit.note = "  Edited before synthetic cold relaunch  "
      edit.painScore = 6
      edit.urgency = .severe
      edit.confirmedBristolType = 5
      edit.confirmedPhotoUsable = true
      edit.mixedForm = .yes
      edit.strainingOrIncomplete = .yes
      edit.leakageOrAccident = nil
      try store.update(retained, with: edit, at: discussionDate)
      try store.setDiscussionMark(true, for: retained, at: discussionDate)
      try ClinicalTimelineStore(context: context).setNoBowelMovement(
        true,
        for: noBowelMovementDate,
        now: discussionDate
      )

      let deleted = try XCTUnwrap(
        try context.fetch(
          FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == deletedID })
        ).first
      )
      let faultingDeleteImages = ImageStore(
        draftsDirectory: drafts,
        imagesDirectory: images,
        queuedImageRemover: { _ in throw CocoaError(.fileWriteUnknown) }
      )
      XCTAssertEqual(
        try store.delete(deleted, imageStore: faultingDeleteImages),
        .recordDeletedPhotoCleanupPending
      )
      XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: try healthyImages.deletionQueueDirectory()
            .appendingPathComponent(expectedDeletedFilename).path
        )
      )
    }

    // Use a new SQLite container and the exact bootstrap reconciliation path,
    // rather than reusing the writing context. This models process termination
    // between the durable row deletion and queued photo cleanup.
    let reopened = await PersistenceBootstrap.openAppJournal(
      publicStoreURL: storeURL,
      resumePendingErase: { _ in nil },
      reconcileJournal: { context in
        try await EntryStore(context: context).reconcile(imageStore: healthyImages)
      }
    )
    XCTAssertTrue(reopened.permitsJournalPresentation)
    let reopenedContext = ModelContext(try XCTUnwrap(reopened.modelContainer))
    let entries = try reopenedContext.fetch(FetchDescriptor<EntryRecord>())
    XCTAssertEqual(entries.count, 1)
    let retained = try XCTUnwrap(entries.first)
    XCTAssertEqual(retained.id, retainedID)
    XCTAssertEqual(retained.capturedAt, editDate)
    XCTAssertEqual(retained.note, "Edited before synthetic cold relaunch")
    XCTAssertEqual(retained.redBlood, SymptomFlag.yes.rawValue)
    XCTAssertEqual(retained.blackTarry, SymptomFlag.unsure.rawValue)
    XCTAssertEqual(retained.dizziness, SymptomFlag.yes.rawValue)
    XCTAssertEqual(retained.severePain, SymptomFlag.no.rawValue)
    XCTAssertEqual(retained.painScore, 6)
    XCTAssertEqual(retained.urgency, UrgencyLevel.severe.rawValue)
    XCTAssertEqual(retained.confirmedBristolType, 5)
    XCTAssertEqual(retained.confirmedPhotoUsable, true)
    XCTAssertEqual(retained.mixedForm, ClinicalTriState.yes.rawValue)
    XCTAssertEqual(retained.strainingOrIncomplete, ClinicalTriState.yes.rawValue)
    XCTAssertNil(retained.leakageOrAccident)
    XCTAssertEqual(retained.markedForDiscussionAt, discussionDate)
    XCTAssertEqual(retained.imageFilename, expectedRetainedFilename)
    XCTAssertEqual(retained.imageSHA256, expectedRetainedHash)
    XCTAssertFalse(retained.imageUnavailable)
    XCTAssertTrue(
      try healthyImages.storedImageIsVerified(
        filename: expectedRetainedFilename,
        expectedSHA256: expectedRetainedHash
      )
    )
    XCTAssertEqual(
      try reopenedContext.fetch(FetchDescriptor<DailyCompletionRecord>()).map(\.answer),
      [.noBowelMovement]
    )
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: try healthyImages.deletionQueueDirectory()
          .appendingPathComponent(expectedDeletedFilename).path
      )
    )
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: try XCTUnwrap(healthyImages.imageURL(filename: expectedDeletedFilename)).path
      )
    )
  }

  func testDiskBackedColdReopenPreservesAmbiguousPhotoCopiesAndBlocksPDFExport() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let entryID = UUID()
    let imageStore = ImageStore(draftsDirectory: drafts, imagesDirectory: images)
    var expectedFilename = ""
    var expectedHash = ""
    var expectedBytes = Data()
    let capturedAt = Date(timeIntervalSince1970: 1_710_000_000)

    do {
      let context = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
      let store = EntryStore(context: context)
      let (entryInput, prepared) = try preparedPhotoInput(
        imageStore,
        id: entryID,
        color: .green
      )
      expectedFilename = try XCTUnwrap(entryInput.imageFilename)
      expectedHash = prepared.reference.sha256
      try store.save(entryInput, imageStore: imageStore)

      let canonical = try XCTUnwrap(imageStore.imageURL(filename: expectedFilename))
      expectedBytes = try Data(contentsOf: canonical)
      let queued = try imageStore.deletionQueueDirectory()
        .appendingPathComponent(expectedFilename, isDirectory: false)
      // Synthetic interrupted-deletion fixture: two byte-identical protected
      // candidates exist. Reconciliation must not choose one to delete.
      try FileManager.default.copyItem(at: canonical, to: queued)
      XCTAssertEqual(try Data(contentsOf: queued), expectedBytes)
    }

    let reopened = await PersistenceBootstrap.openAppJournal(
      publicStoreURL: storeURL,
      resumePendingErase: { _ in nil },
      reconcileJournal: { context in
        try await EntryStore(context: context).reconcile(imageStore: imageStore)
      }
    )
    XCTAssertTrue(reopened.permitsJournalPresentation)
    let reopenedContext = ModelContext(try XCTUnwrap(reopened.modelContainer))
    XCTAssertEqual(try reopenedContext.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    let record = try XCTUnwrap(
      try reopenedContext.fetch(
        FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == entryID })
      ).first
    )
    XCTAssertEqual(record.imageFilename, expectedFilename)
    XCTAssertEqual(record.imageSHA256, expectedHash)
    XCTAssertTrue(record.imageUnavailable, "Ambiguous retained copies must fail closed, not be deleted or silently selected.")
    let canonical = try XCTUnwrap(imageStore.imageURL(filename: expectedFilename))
    let queued = try imageStore.deletionQueueDirectory()
      .appendingPathComponent(expectedFilename, isDirectory: false)
    XCTAssertEqual(try Data(contentsOf: canonical), expectedBytes)
    XCTAssertEqual(try Data(contentsOf: queued), expectedBytes)

    XCTAssertThrowsError(
      try JournalExportSnapshotFactory.make(
        entries: [record],
        completions: [],
        treatmentEvents: [],
        range: .init(from: capturedAt, through: capturedAt),
        scope: .allEntries,
        generatedAt: capturedAt
      )
    ) { error in
      XCTAssertEqual(error as? JournalExportValidationError, .photoIntegrity)
    }
  }

  func testAppBootstrapReconciliationFailureBlocksInsteadOfShowingAnEmptyJournal() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    do {
      let context = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
      context.insert(EntryRecord(input: input(note: "Preserve through blocked bootstrap")))
      try context.save()
    }

    let result = await PersistenceBootstrap.openAppJournal(
      publicStoreURL: storeURL,
      resumePendingErase: { _ in nil },
      reconcileJournal: { _ in throw CocoaError(.fileWriteOutOfSpace) }
    )
    XCTAssertFalse(result.permitsJournalPresentation)
    let message = try XCTUnwrap(result.recoveryMessage)
    XCTAssertTrue(message.contains("could not safely check"))
    XCTAssertTrue(message.contains("No replacement or empty journal was substituted"))
    XCTAssertTrue(message.localizedCaseInsensitiveContains("keep the app installed"))
    assertNoRetiredTransferVocabulary(message)

    let preserved = PersistenceBootstrap.open(publicStoreURL: storeURL)
    XCTAssertTrue(preserved.permitsJournalPresentation)
    let context = ModelContext(try XCTUnwrap(preserved.modelContainer))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<EntryRecord>()).first?.note,
      "Preserve through blocked bootstrap"
    )
  }

  func testPendingEraseBootstrapBlocksEntryWithoutRetiredTransferLanguage() async throws {
    struct SyntheticPendingErase: Error {}
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    do {
      let context = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
      context.insert(EntryRecord(input: input(note: "Preserve while erase cleanup is blocked")))
      try context.save()
    }

    let result = await PersistenceBootstrap.openAppJournal(
      publicStoreURL: storeURL,
      resumePendingErase: { _ in throw SyntheticPendingErase() },
      reconcileJournal: { _ in
        XCTFail("Reconciliation must not run while confirmed erase cleanup is pending.")
      }
    )

    XCTAssertFalse(result.permitsJournalPresentation)
    XCTAssertEqual(result.recoveryReason, .pendingErase)
    let message = try XCTUnwrap(result.recoveryMessage)
    XCTAssertTrue(message.localizedCaseInsensitiveContains("journal entry is blocked"))
    XCTAssertTrue(message.localizedCaseInsensitiveContains("keep the app installed"))
    XCTAssertTrue(message.localizedCaseInsensitiveContains("local cleanup is pending"))
    assertNoRetiredTransferVocabulary(message)

    let preserved = PersistenceBootstrap.open(publicStoreURL: storeURL)
    XCTAssertTrue(preserved.permitsJournalPresentation)
    let context = ModelContext(try XCTUnwrap(preserved.modelContainer))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<EntryRecord>()).first?.note,
      "Preserve while erase cleanup is blocked"
    )
  }

  func testProtectedPhotoReadBlocksBootstrapAndHealthyUnlockRetryPreservesPhoto() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let healthyImages = ImageStore(draftsDirectory: drafts, imagesDirectory: images)
    let prepared = try healthyImages.prepare(validImageData(color: .brown))
    let id = UUID()

    do {
      let context = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
      try EntryStore(context: context).save(
        input(
          id: id,
          draftURL: prepared.url,
          hash: prepared.reference.sha256,
          filename: "\(id.uuidString).jpg",
          note: "Protected photo must not become missing"
        ),
        imageStore: healthyImages
      )
    }

    let protectedImages = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images,
      imageDataReader: { _ in throw CocoaError(.fileReadNoPermission) },
      protectedDataIsAvailable: { false }
    )
    let blocked = await PersistenceBootstrap.openAppJournal(
      publicStoreURL: storeURL,
      resumePendingErase: { _ in nil },
      reconcileJournal: { context in
        try await EntryStore(context: context).reconcile(imageStore: protectedImages)
      },
      // The denial is injected after the store opens, matching a lock race
      // during per-photo verification rather than a pre-open locked device.
      protectedDataIsAvailable: { true }
    )
    XCTAssertFalse(blocked.permitsJournalPresentation)
    XCTAssertEqual(blocked.recoveryReason, .protectedDataUnavailable)
    let blockedMessage = try XCTUnwrap(blocked.recoveryMessage)
    XCTAssertTrue(blockedMessage.localizedCaseInsensitiveContains("unlock this iPhone"))
    XCTAssertTrue(blockedMessage.localizedCaseInsensitiveContains("new or empty journal"))
    assertNoRetiredTransferVocabulary(blockedMessage)

    let afterBlockedAttempt = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
    let stillAvailable = try XCTUnwrap(
      try afterBlockedAttempt.fetch(
        FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == id })
      ).first
    )
    XCTAssertFalse(stillAvailable.imageUnavailable)

    let retried = await PersistenceBootstrap.openAppJournal(
      publicStoreURL: storeURL,
      resumePendingErase: { _ in nil },
      reconcileJournal: { context in
        try await EntryStore(context: context).reconcile(imageStore: healthyImages)
      },
      protectedDataIsAvailable: { true }
    )
    XCTAssertTrue(retried.permitsJournalPresentation)
    let retryContext = ModelContext(try XCTUnwrap(retried.modelContainer))
    let preserved = try XCTUnwrap(
      try retryContext.fetch(
        FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == id })
      ).first
    )
    XCTAssertFalse(preserved.imageUnavailable)
    XCTAssertTrue(
      try healthyImages.storedImageIsVerified(
        filename: "\(id.uuidString).jpg",
        expectedSHA256: prepared.reference.sha256
      )
    )
  }

  func testProtectedStoreOpenFailureUsesAutomaticUnlockRecoveryReason() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let result = await PersistenceBootstrap.openAppJournal(
      publicStoreURL: root.appendingPathComponent("GITimeline.store"),
      openPublicStore: { _ in throw CocoaError(.fileReadNoPermission) },
      protectedDataIsAvailable: { true }
    )

    XCTAssertFalse(result.permitsJournalPresentation)
    XCTAssertEqual(result.recoveryReason, .protectedDataUnavailable)
    let message = try XCTUnwrap(result.recoveryMessage)
    XCTAssertTrue(message.contains("Unlock this iPhone"))
    XCTAssertTrue(message.localizedCaseInsensitiveContains("new or empty journal"))
    assertNoRetiredTransferVocabulary(message)
  }

  func testPublicStoreOpenFailurePreservesCanonicalBytesAndBlocksJournal() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    let canonicalBytes = Data("synthetic canonical bytes: do not overwrite".utf8)
    try canonicalBytes.write(to: storeURL, options: .atomic)

    let result = PersistenceBootstrap.open(
      publicStoreURL: storeURL,
      openPublicStore: { _ in throw CocoaError(.fileReadCorruptFile) }
    )

    XCTAssertFalse(result.permitsJournalPresentation)
    XCTAssertNotNil(result.modelContainer, "Blocked presentation must use an in-memory container when available.")
    let message = try XCTUnwrap(result.recoveryMessage)
    XCTAssertTrue(message.localizedCaseInsensitiveContains("existing journal was not changed"))
    assertNoRetiredTransferVocabulary(message)
    XCTAssertEqual(try Data(contentsOf: storeURL), canonicalBytes)
  }

  func testEraseAllJournalDataDeletesRecordsAndJournalFilesButKeepsModelAssets() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let exports = root.appendingPathComponent("Exports", isDirectory: true)
    let models = root.appendingPathComponent("Models", isDirectory: true)
    for directory in [images, drafts, exports, models] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data("photo".utf8).write(to: images.appendingPathComponent("entry.jpg"))
    try Data("draft".utf8).write(to: drafts.appendingPathComponent("draft.jpg"))
    try Data("partial export".utf8).write(to: exports.appendingPathComponent(".partial.pdf"))
    let modelURL = models.appendingPathComponent("gemma-4-E4B-it.litertlm")
    let markerURL = root.appendingPathComponent("erase-pending.v1.json")
    try Data("model stays".utf8).write(to: modelURL)

    let context = ModelContext(try container())
    context.insert(EntryRecord(input: input()))
    context.insert(DailyCompletionRecord(dayKey: "2026-08-02", dayStart: Date(), answer: .yes))
    context.insert(TreatmentEventRecord(effectiveDate: Date(), kind: .other, name: "Test treatment"))
    try context.save()

    let summary = try JournalDataEraser(
      context: context,
      journalDirectories: { [images, drafts, exports] },
      pendingMarkerURL: { markerURL }
    ).eraseAllJournalData()

    XCTAssertEqual(summary.recordsDeleted, 3)
    XCTAssertEqual(summary.filesDeleted, 3)
    XCTAssertTrue(summary.completedWithoutWarnings)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyCompletionRecord>()), 0)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TreatmentEventRecord>()), 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
  }

  func testEraseAllJournalDataRollsBackRecordsAndKeepsFilesWhenStoreSaveFails() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let markerURL = root.appendingPathComponent("erase-pending.v1.json")
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    let imageURL = images.appendingPathComponent("entry.jpg")
    try Data("photo".utf8).write(to: imageURL)

    let context = ModelContext(try container())
    context.insert(EntryRecord(input: input()))
    try context.save()

    let eraser = JournalDataEraser(
      context: context,
      journalDirectories: { [images] },
      failureInjector: { throw CocoaError(.fileWriteUnknown) },
      pendingMarkerURL: { markerURL }
    )
    XCTAssertThrowsError(try eraser.eraseAllJournalData()) { error in
      XCTAssertEqual((error as? JournalDataErasePendingFailure)?.stage, .database)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path), "A pre-commit failure keeps the confirmed erase intent for a safe retry on launch.")

    let gate = JournalWriteGate {
      FileManager.default.fileExists(atPath: markerURL.path)
    }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: images
    )
    let blockedEntryStore = EntryStore(context: context, writeGate: gate)
    XCTAssertThrowsError(try blockedEntryStore.save(input(note: "must not survive retry"), imageStore: imageStore)) { error in
      XCTAssertEqual(error as? JournalWriteGateError, .erasePending)
    }
    XCTAssertThrowsError(
      try ClinicalTimelineStore(context: context, writeGate: gate).setDailyCompletion(.yes, for: Date())
    ) { error in
      XCTAssertEqual(error as? JournalWriteGateError, .erasePending)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)

    let resumed = try XCTUnwrap(
      JournalDataEraser(
        context: context,
        journalDirectories: { [images] },
        pendingMarkerURL: { markerURL }
      ).resumePendingEraseIfNeeded()
    )
    XCTAssertTrue(resumed.completedWithoutWarnings)
    XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)
    try blockedEntryStore.save(input(note: "allowed after completed retry"), imageStore: imageStore)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
  }

  func testConfirmedEraseEpochPermanentlyRejectsStaleWritersAfterMarkerClears() throws {
    let epoch = JournalWriteEpoch()
    var markerExists = false
    let preEraseGate = JournalWriteGate(
      pendingEraseProbe: { markerExists },
      epoch: epoch
    )

    XCTAssertNoThrow(try preEraseGate.requireWritable())
    epoch.invalidateCurrentWriters()
    markerExists = true
    XCTAssertThrowsError(try preEraseGate.requireWritable()) { error in
      XCTAssertEqual(error as? JournalWriteGateError, .staleWriter)
    }

    // Clearing the durable marker after successful cleanup must never revive
    // an inference task or view model retained from before confirmation.
    markerExists = false
    XCTAssertThrowsError(try preEraseGate.requireWritable()) { error in
      XCTAssertEqual(error as? JournalWriteGateError, .staleWriter)
    }

    // A marker-absent failure before erase begins reconstructs the journal UI.
    // Its stores capture the current epoch and may restore the untouched draft.
    let reconstructedGate = JournalWriteGate(
      pendingEraseProbe: { markerExists },
      epoch: epoch
    )
    XCTAssertNoThrow(try reconstructedGate.requireWritable())
  }

  func testConfirmedRetryWithoutMarkerRestartsRealEraseAfterPreMarkerFailure() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let markerURL = root.appendingPathComponent("erase-pending.v1.json")
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    let imageURL = images.appendingPathComponent("retained.jpg")
    try Data("retained journal photo".utf8).write(to: imageURL)
    let context = ModelContext(try container())
    context.insert(EntryRecord(input: input(note: "retained after pre-marker failure")))
    try context.save()

    // Directory resolution is deliberately before marker commit. The first
    // confirmed attempt therefore changes nothing and leaves no marker.
    let firstAttempt = JournalDataEraser(
      context: context,
      journalDirectories: { throw CocoaError(.fileReadUnknown) },
      pendingMarkerURL: { markerURL }
    )
    XCTAssertThrowsError(try firstAttempt.eraseAllJournalData())
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))

    // This models Try Again after the earlier marker probe was unknown. Marker
    // absence cannot be reported as success; it must execute the real erase.
    let retry = JournalDataEraser(
      context: context,
      journalDirectories: { [images] },
      pendingMarkerURL: { markerURL }
    )
    let summary = try retry.resumeOrRestartConfirmedErase()
    XCTAssertTrue(summary.completedWithoutWarnings)
    XCTAssertEqual(summary.recordsDeleted, 1)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
  }

  func testInterruptedEraseResumesCleanupBeforeJournalCanRestoreFiles() throws {
    struct SimulatedTermination: Error {}
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let exports = root.appendingPathComponent("Exports", isDirectory: true)
    let markerURL = root.appendingPathComponent("erase-pending.v1.json")
    for directory in [images, drafts, exports] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let imageURL = images.appendingPathComponent("entry.jpg")
    let draftSnapshotURL = drafts.appendingPathComponent("active-draft.v1.json")
    let draftPhotoURL = drafts.appendingPathComponent("draft.jpg")
    let exportURL = exports.appendingPathComponent("temporary.pdf")
    for url in [imageURL, draftSnapshotURL, draftPhotoURL, exportURL] {
      try Data("journal data".utf8).write(to: url, options: .atomic)
    }
    let context = ModelContext(try container())
    context.insert(EntryRecord(input: input()))
    context.insert(DailyCompletionRecord(dayKey: "2026-08-02", dayStart: Date(), answer: .yes))
    try context.save()

    let interrupted = JournalDataEraser(
      context: context,
      journalDirectories: { [images, drafts, exports] },
      afterDatabaseCommitInjector: { throw SimulatedTermination() },
      pendingMarkerURL: { markerURL }
    )
    XCTAssertThrowsError(try interrupted.eraseAllJournalData()) { error in
      XCTAssertEqual((error as? JournalDataErasePendingFailure)?.stage, .postCommit)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: draftSnapshotURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))

    let resumed = JournalDataEraser(
      context: context,
      journalDirectories: { [images, drafts, exports] },
      pendingMarkerURL: { markerURL }
    )
    let summary = try XCTUnwrap(resumed.resumePendingEraseIfNeeded())

    XCTAssertEqual(summary.recordsDeleted, 0)
    XCTAssertEqual(summary.filesDeleted, 4)
    XCTAssertTrue(summary.completedWithoutWarnings)
    XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: draftSnapshotURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: draftPhotoURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
  }

  func testPartialEraseCleanupBlocksWritesUntilRelaunchRetryFinishes() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let markerURL = root.appendingPathComponent("erase-pending.v1.json")
    for directory in [images, drafts] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data("retained".utf8).write(to: directory.appendingPathComponent("retained.dat"))
    }
    let context = ModelContext(try container())
    context.insert(EntryRecord(input: input(note: "erase me")))
    try context.save()

    let interrupted = JournalDataEraser(
      context: context,
      journalDirectories: { [images, drafts] },
      cleanupFailureInjector: { directory in
        if directory.standardizedFileURL == images.standardizedFileURL {
          throw CocoaError(.fileWriteUnknown)
        }
      },
      pendingMarkerURL: { markerURL }
    )
    XCTAssertThrowsError(try interrupted.eraseAllJournalData()) { error in
      let pending = error as? JournalDataErasePendingFailure
      XCTAssertEqual(pending?.stage, .fileCleanup)
      XCTAssertEqual(pending?.cleanupFailureCount, 1)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: images.appendingPathComponent("retained.dat").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: drafts.appendingPathComponent("retained.dat").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))

    let gate = JournalWriteGate { FileManager.default.fileExists(atPath: markerURL.path) }
    let blockedStore = EntryStore(context: context, writeGate: gate)
    XCTAssertThrowsError(try blockedStore.save(input(note: "blocked"), imageStore: ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images
    ))) { error in
      XCTAssertEqual(error as? JournalWriteGateError, .erasePending)
    }

    let resumed = try XCTUnwrap(JournalDataEraser(
      context: context,
      journalDirectories: { [images, drafts] },
      pendingMarkerURL: { markerURL }
    ).resumePendingEraseIfNeeded())
    XCTAssertTrue(resumed.completedWithoutWarnings)
    XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: images.appendingPathComponent("retained.dat").path))
  }

  func testMarkerClearFailureKeepsWritesBlockedUntilIdempotentRetry() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let markerURL = root.appendingPathComponent("erase-pending.v1.json")
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    let context = ModelContext(try container())
    context.insert(EntryRecord(input: input(note: "erase me")))
    try context.save()

    let interrupted = JournalDataEraser(
      context: context,
      journalDirectories: { [images] },
      markerClearFailureInjector: { throw CocoaError(.fileWriteUnknown) },
      pendingMarkerURL: { markerURL }
    )
    XCTAssertThrowsError(try interrupted.eraseAllJournalData()) { error in
      XCTAssertEqual((error as? JournalDataErasePendingFailure)?.stage, .markerClear)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))

    let gate = JournalWriteGate { FileManager.default.fileExists(atPath: markerURL.path) }
    let blockedStore = EntryStore(context: context, writeGate: gate)
    XCTAssertThrowsError(try blockedStore.save(input(note: "blocked"), imageStore: ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: images
    ))) { error in
      XCTAssertEqual(error as? JournalWriteGateError, .erasePending)
    }

    let resumed = try XCTUnwrap(JournalDataEraser(
      context: context,
      journalDirectories: { [images] },
      pendingMarkerURL: { markerURL }
    ).resumePendingEraseIfNeeded())
    XCTAssertTrue(resumed.completedWithoutWarnings)
    XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
  }

  func testPartialPhotoTupleFailsBeforeInsertAndRetryMakesOneRecord() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    XCTAssertThrowsError(try store.save(input(draftURL: root.appendingPathComponent("draft")), imageStore: imageStore))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)

    let (complete, _) = try preparedPhotoInput(imageStore)
    let failing = try FailingEntryStore()
    failing.failNextSave = true
    XCTAssertThrowsError(try failing.save(complete, imageStore: imageStore))
    XCTAssertEqual(failing.records.count, 0)
    try failing.save(complete, imageStore: imageStore)
    XCTAssertEqual(failing.records.count, 1)
  }

  func testEntrySaveIdempotencyRequiresExactCanonicalFingerprint() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let id = UUID()
    let exact = input(id: id, note: "exact payload")

    try store.save(exact, imageStore: imageStore)
    try store.save(exact, imageStore: imageStore)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    let record = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
    XCTAssertEqual(
      try EntryTransactionFingerprint.make(for: exact),
      try EntryTransactionFingerprint.make(for: record)
    )

    let conflicting = input(id: id, note: "different payload")
    XCTAssertThrowsError(try store.save(conflicting, imageStore: imageStore)) { error in
      XCTAssertEqual(error as? GITimelineError, .entryTransactionConflict)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertEqual(record.note, "exact payload")
  }

  func testPhotoPromotionExcludesNewAndCrashRecoveryCanonicalFilesFromBackup() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    var hardenedPaths: [String] = []
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images,
      backupExcluder: { url in hardenedPaths.append(url.standardizedFileURL.path) }
    )
    let context = ModelContext(try container())
    let store = EntryStore(context: context)

    let fresh = try preparedPhotoInput(imageStore)
    let freshCanonical = try imageStore.promotedURL(for: fresh.input.id)
    try store.save(fresh.input, imageStore: imageStore)
    XCTAssertEqual(
      hardenedPaths,
      [
        fresh.prepared.url.standardizedFileURL.path,
        freshCanonical.standardizedFileURL.path,
      ]
    )

    let recovered = try preparedPhotoInput(imageStore)
    let recoveredCanonical = try imageStore.promotedURL(for: recovered.input.id)
    try imageStore.promoteVerifiedDraft(
      recovered.prepared.url,
      to: recoveredCanonical,
      expectedSHA256: recovered.prepared.reference.sha256
    )
    hardenedPaths.removeAll()

    try store.save(recovered.input, imageStore: imageStore)
    XCTAssertEqual(hardenedPaths, [recoveredCanonical.standardizedFileURL.path])
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 2)
    XCTAssertTrue(FileManager.default.fileExists(atPath: recovered.prepared.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: recoveredCanonical.path))
  }

  func testBackupExclusionFailurePreventsInsertAndPreservesDraftForRetry() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let normalizedImagesPath = images.standardizedFileURL.path
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images,
      backupExcluder: { url in
        guard url.deletingLastPathComponent().standardizedFileURL.path == normalizedImagesPath else {
          return
        }
        throw CocoaError(.fileWriteNoPermission)
      }
    )
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let (entryInput, prepared) = try preparedPhotoInput(imageStore)
    let canonical = try imageStore.promotedURL(for: entryInput.id)
    let preparedBytes = try Data(contentsOf: prepared.url)

    XCTAssertThrowsError(try store.save(entryInput, imageStore: imageStore))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.url.path))
    XCTAssertEqual(try Data(contentsOf: prepared.url), preparedBytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.path))

    // A retry after a crash may find the verified canonical JPEG already in
    // place. Failed re-hardening must not erase that candidate or its draft.
    let healthyImageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images
    )
    let (recoveredInput, recoveredDraft) = try preparedPhotoInput(healthyImageStore)
    let recoveredCanonical = try healthyImageStore.promotedURL(for: recoveredInput.id)
    try healthyImageStore.promoteVerifiedDraft(
      recoveredDraft.url,
      to: recoveredCanonical,
      expectedSHA256: recoveredDraft.reference.sha256
    )
    let recoveredBytes = try Data(contentsOf: recoveredCanonical)

    XCTAssertThrowsError(try store.save(recoveredInput, imageStore: imageStore))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: recoveredDraft.url.path))
    XCTAssertEqual(try Data(contentsOf: recoveredCanonical), recoveredBytes)

    // The original failed input remains retryable with the same staged bytes.
    try store.save(entryInput, imageStore: healthyImageStore)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertEqual(try Data(contentsOf: prepared.url), preparedBytes)
    XCTAssertEqual(try Data(contentsOf: canonical), preparedBytes)
  }

  func testReconcileRestoreReappliesBackupExclusionWithoutChangingRetainedBytes() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    var hardenedPaths: [String] = []
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images,
      backupExcluder: { url in hardenedPaths.append(url.standardizedFileURL.path) }
    )
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let (entryInput, prepared) = try preparedPhotoInput(imageStore)
    let canonical = try imageStore.promotedURL(for: entryInput.id)
    let draftBytes = try Data(contentsOf: prepared.url)
    try store.save(entryInput, imageStore: imageStore)
    let canonicalBytes = try Data(contentsOf: canonical)
    hardenedPaths.removeAll()

    let staged = try XCTUnwrap(imageStore.stageForDeletion(canonical))
    XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.path))
    XCTAssertEqual(try Data(contentsOf: staged.queuedURL), canonicalBytes)
    hardenedPaths.removeAll()

    try await store.reconcile(imageStore: imageStore)

    XCTAssertEqual(hardenedPaths, [canonical.standardizedFileURL.path])
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertEqual(try Data(contentsOf: prepared.url), draftBytes)
    XCTAssertEqual(try Data(contentsOf: canonical), canonicalBytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: staged.queuedURL.path))
    XCTAssertFalse(try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first).imageUnavailable)
  }

  func testStageForDeletionReappliesBackupExclusionAfterMoveAndQueuedRetry() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    var hardenedPaths: [String] = []
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images,
      backupExcluder: { url in hardenedPaths.append(url.standardizedFileURL.path) }
    )
    let (entryInput, prepared) = try preparedPhotoInput(imageStore)
    let canonical = try imageStore.promotedURL(for: entryInput.id)
    try EntryStore(context: ModelContext(try container())).save(entryInput, imageStore: imageStore)
    let canonicalBytes = try Data(contentsOf: canonical)
    hardenedPaths.removeAll()

    let staged = try XCTUnwrap(imageStore.stageForDeletion(canonical))
    XCTAssertEqual(hardenedPaths, [staged.queuedURL.standardizedFileURL.path])
    XCTAssertEqual(try Data(contentsOf: staged.queuedURL), canonicalBytes)
    XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.url.path))

    hardenedPaths.removeAll()
    let retried = try XCTUnwrap(imageStore.stageForDeletion(canonical))
    XCTAssertEqual(retried, staged)
    XCTAssertEqual(hardenedPaths, [staged.queuedURL.standardizedFileURL.path])
    XCTAssertEqual(try Data(contentsOf: staged.queuedURL), canonicalBytes)
  }

  func testRestoreExistingCanonicalReappliesBackupExclusionWithoutMovingBytes() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    var hardenedPaths: [String] = []
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images,
      backupExcluder: { url in hardenedPaths.append(url.standardizedFileURL.path) }
    )
    let (entryInput, _) = try preparedPhotoInput(imageStore)
    let canonical = try imageStore.promotedURL(for: entryInput.id)
    try EntryStore(context: ModelContext(try container())).save(entryInput, imageStore: imageStore)
    let canonicalBytes = try Data(contentsOf: canonical)
    let queued = try imageStore.deletionQueueDirectory()
      .appendingPathComponent(canonical.lastPathComponent, isDirectory: false)
    hardenedPaths.removeAll()

    try imageStore.restore(.init(originalURL: canonical, queuedURL: queued))

    XCTAssertEqual(hardenedPaths, [canonical.standardizedFileURL.path])
    XCTAssertEqual(try Data(contentsOf: canonical), canonicalBytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: queued.path))
  }

  func testStageForDeletionBackupExclusionFailureRetainsQueuedBytesForReconcile() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let healthyImageStore = ImageStore(draftsDirectory: drafts, imagesDirectory: images)
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let (entryInput, prepared) = try preparedPhotoInput(healthyImageStore)
    let canonical = try healthyImageStore.promotedURL(for: entryInput.id)
    try store.save(entryInput, imageStore: healthyImageStore)
    let canonicalBytes = try Data(contentsOf: canonical)
    let faultingImageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images,
      backupExcluder: { _ in throw CocoaError(.fileWriteNoPermission) }
    )
    let queued = try faultingImageStore.deletionQueueDirectory()
      .appendingPathComponent(canonical.lastPathComponent, isDirectory: false)

    XCTAssertThrowsError(try faultingImageStore.stageForDeletion(canonical))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.url.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.path))
    XCTAssertEqual(try Data(contentsOf: queued), canonicalBytes)

    try await store.reconcile(imageStore: healthyImageStore)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertEqual(try Data(contentsOf: canonical), canonicalBytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: queued.path))
  }

  func testReconcileRestoreBackupExclusionFailureRetainsRowDraftAndQueuedBytesForRetry() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let healthyImageStore = ImageStore(draftsDirectory: drafts, imagesDirectory: images)
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let (entryInput, prepared) = try preparedPhotoInput(healthyImageStore)
    let canonical = try healthyImageStore.promotedURL(for: entryInput.id)
    let draftBytes = try Data(contentsOf: prepared.url)
    try store.save(entryInput, imageStore: healthyImageStore)
    let canonicalBytes = try Data(contentsOf: canonical)
    var attemptedPaths: [String] = []
    let faultingImageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images,
      backupExcluder: { url in
        attemptedPaths.append(url.standardizedFileURL.path)
        throw CocoaError(.fileWriteNoPermission)
      }
    )

    let staged = try XCTUnwrap(healthyImageStore.stageForDeletion(canonical))
    try await store.reconcile(imageStore: faultingImageStore)

    XCTAssertEqual(attemptedPaths, [canonical.standardizedFileURL.path])
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.url.path))
    XCTAssertEqual(try Data(contentsOf: prepared.url), draftBytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.path))
    XCTAssertEqual(try Data(contentsOf: staged.queuedURL), canonicalBytes)
    XCTAssertTrue(try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first).imageUnavailable)

    try await store.reconcile(imageStore: healthyImageStore)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertEqual(try Data(contentsOf: canonical), canonicalBytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: staged.queuedURL.path))
    XCTAssertFalse(try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first).imageUnavailable)
  }

  func testMatchingRecoveredCanonicalPromotionCreatesOneRowButMismatchPreservesBothSources() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    let context = ModelContext(try container())
    let store = EntryStore(context: context)

    let matching = try preparedPhotoInput(imageStore)
    let matchingCanonical = try imageStore.promotedURL(for: matching.input.id)
    try imageStore.promoteVerifiedDraft(
      matching.prepared.url,
      to: matchingCanonical,
      expectedSHA256: matching.prepared.reference.sha256
    )
    try store.save(matching.input, imageStore: imageStore)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: matching.prepared.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: matchingCanonical.path))

    let conflictingID = UUID()
    let brown = try preparedPhotoInput(imageStore, id: conflictingID, color: .brown)
    let green = try imageStore.prepare(validImageData(color: .green))
    let conflictingCanonical = try imageStore.promotedURL(for: conflictingID)
    try imageStore.promoteVerifiedDraft(
      green.url,
      to: conflictingCanonical,
      expectedSHA256: green.reference.sha256
    )
    XCTAssertThrowsError(try store.save(brown.input, imageStore: imageStore)) { error in
      XCTAssertEqual(error as? GITimelineError, .ambiguousPhotoState)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: brown.prepared.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: conflictingCanonical.path))
  }

  func testNoPhotoDeleteDirectoryFailureHappensBeforeDurableMutation() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts")
    let images = root.appendingPathComponent("Images")
    let healthyImages = ImageStore(draftsDirectory: drafts, imagesDirectory: images)
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    try store.save(input(note: "must remain"), imageStore: healthyImages)
    let record = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
    let faultingImages = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images,
      directoryAccessFailureInjector: { kind in
        if kind == .deletionQueue { throw CocoaError(.fileReadUnknown) }
      }
    )

    XCTAssertThrowsError(try store.delete(record, imageStore: faultingImages))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertEqual(try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first).note, "must remain")
  }

  func testCommittedDeleteReportsPhotoCleanupPendingWithoutThrowingOrRestoringRow() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts")
    let images = root.appendingPathComponent("Images")
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images,
      queuedImageRemover: { _ in throw CocoaError(.fileWriteUnknown) }
    )
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let (entryInput, _) = try preparedPhotoInput(imageStore)
    try store.save(entryInput, imageStore: imageStore)
    let record = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
    let canonical = try XCTUnwrap(imageStore.imageURL(filename: record.imageFilename))
    let queued = try imageStore.deletionQueueDirectory()
      .appendingPathComponent(try XCTUnwrap(record.imageFilename))

    let deletion = HistoryDeletionCoordinator(store: store, imageStore: imageStore)
    deletion.request(record)
    deletion.confirm()

    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: queued.path))
    XCTAssertNil(deletion.errorMessage, "A durable row deletion must never be surfaced as rolled back.")
    XCTAssertNotNil(deletion.noticeMessage)
    XCTAssertNil(deletion.pendingDelete)

    // Launch reconciliation can finish the protected queue cleanup later.
    let healthyImages = ImageStore(draftsDirectory: drafts, imagesDirectory: images)
    try await store.reconcile(imageStore: healthyImages)
    XCTAssertFalse(FileManager.default.fileExists(atPath: queued.path))
  }

  func testSaveRehashesDraftBeforePromotionAndKeepsTamperedDraftForRecovery() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let (entryInput, prepared) = try preparedPhotoInput(imageStore)

    // Simulate a local alteration between photo preparation and Save.
    try Data("tampered bytes".utf8).write(to: prepared.url, options: .atomic)
    XCTAssertThrowsError(try store.save(entryInput, imageStore: imageStore))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.url.path), "The staged draft remains available for recovery.")
    let canonical = try imageStore.promotedURL(for: entryInput.id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.path))
  }

  func testDeleteRollbackRestoresPhotoAndClearsDeletionQueue() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let store = try FailingEntryStore()
    let (entryInput, _) = try preparedPhotoInput(imageStore)
    try store.save(entryInput, imageStore: imageStore)
    let entry = try XCTUnwrap(store.records.first)
    let image = try XCTUnwrap(imageStore.imageURL(filename: entry.imageFilename))

    store.failNextDelete = true
    XCTAssertThrowsError(try store.delete(entry, imageStore: imageStore))
    XCTAssertEqual(store.records.count, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
    let queued = try imageStore.deletionQueueDirectory().appendingPathComponent(try XCTUnwrap(entry.imageFilename))
    XCTAssertFalse(FileManager.default.fileExists(atPath: queued.path))
  }

  func testReconcileRestoresReferencedQueuedPhotoAndRetriesUnreferencedQueueDeletion() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let (entryInput, _) = try preparedPhotoInput(imageStore)
    try store.save(entryInput, imageStore: imageStore)
    let image = try XCTUnwrap(imageStore.imageURL(filename: entryInput.imageFilename))
    let staged = try XCTUnwrap(imageStore.stageForDeletion(image))
    XCTAssertFalse(FileManager.default.fileExists(atPath: image.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: staged.queuedURL.path))

    try await store.reconcile(imageStore: imageStore)
    XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: staged.queuedURL.path))
    imageStore.deleteBestEffort(image)
    XCTAssertTrue(FileManager.default.fileExists(atPath: image.path), "Draft cleanup must never remove a canonical journal photo.")

    let orphanDraft = try imageStore.prepare(validImageData(color: .green))
    let orphan = try imageStore.promotedURL(for: UUID())
    try imageStore.promoteVerifiedDraft(orphanDraft.url, to: orphan, expectedSHA256: orphanDraft.reference.sha256)
    let queuedOrphan = try XCTUnwrap(imageStore.stageForDeletion(orphan))
    XCTAssertTrue(FileManager.default.fileExists(atPath: queuedOrphan.queuedURL.path))

    try await store.reconcile(imageStore: imageStore)
    XCTAssertFalse(FileManager.default.fileExists(atPath: queuedOrphan.queuedURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
  }

  func testReconcileMarksHashMismatchUnavailableWithoutDeletingRecordOrPhoto() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let (entryInput, _) = try preparedPhotoInput(imageStore, color: .brown)
    try store.save(entryInput, imageStore: imageStore)
    let image = try XCTUnwrap(imageStore.imageURL(filename: entryInput.imageFilename))
    let replacement = try imageStore.prepare(validImageData(color: .green))
    try Data(contentsOf: replacement.url).write(to: image, options: .atomic)

    try await store.reconcile(imageStore: imageStore)
    let record = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
    XCTAssertTrue(record.imageUnavailable)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
  }

  func testJournalPhotoPresentationNeverShowsAnUnavailableRetainedFile() {
    let entry = EntryRecord(input: input(filename: "retained-but-invalid.jpg"))

    entry.imageUnavailable = true
    XCTAssertFalse(JournalPhotoPresentation.canDisplay(entry))
    XCTAssertEqual(JournalPhotoPresentation.unavailableTitle(for: entry), "Photo unavailable")

    entry.imageUnavailable = false
    XCTAssertTrue(JournalPhotoPresentation.canDisplay(entry))

    entry.imageFilename = nil
    XCTAssertFalse(JournalPhotoPresentation.canDisplay(entry))
    XCTAssertEqual(JournalPhotoPresentation.unavailableTitle(for: entry), "No photo attached")
  }

  func testReconcileOutOfSpaceRollsBackVisibleMutationAndRetryPersistsIt() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("GITimeline.store")
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    let id = UUID()
    let filename = "\(id.uuidString).jpg"
    do {
      let context = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
      let record = EntryRecord(
        input: input(
          id: id,
          draftURL: root.appendingPathComponent("missing-draft.jpg"),
          hash: String(repeating: "a", count: 64),
          filename: filename
        )
      )
      context.insert(record)
      try context.save()

      let faulting = EntryStore(context: context) { point in
        if case .afterReconcileBeforeSave = point {
          throw CocoaError(.fileWriteOutOfSpace)
        }
      }
      do {
        try await faulting.reconcile(imageStore: imageStore)
        XCTFail("Expected the injected out-of-space error.")
      } catch {
        XCTAssertEqual((error as? CocoaError)?.code, .fileWriteOutOfSpace)
      }
      let rolledBack = try XCTUnwrap(
        try context.fetch(
          FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == id })
        ).first
      )
      XCTAssertFalse(
        rolledBack.imageUnavailable,
        "A failed reconciliation save must not leak an uncommitted unavailable state into the UI context."
      )

      try await EntryStore(context: context).reconcile(imageStore: imageStore)
    }

    let reopenedContext = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
    let persistedRetry = try XCTUnwrap(
      try reopenedContext.fetch(
        FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == id })
      ).first
    )
    XCTAssertTrue(persistedRetry.imageUnavailable)
  }

  func testReconcilePreservesPotentialPhotoWhenLegacyReferenceIsMalformed() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let prepared = try imageStore.prepare(validImageData())
    let recoverable = try imageStore.imagesDirectory().appendingPathComponent("recoverable.jpg")
    try Data(contentsOf: prepared.url).write(to: recoverable, options: .atomic)
    let legacy = EntryRecord(input: input(
      draftURL: prepared.url,
      hash: prepared.reference.sha256,
      filename: "../recoverable.jpg"
    ))
    context.insert(legacy)
    try context.save()

    try await store.reconcile(imageStore: imageStore)
    XCTAssertTrue(FileManager.default.fileExists(atPath: recoverable.path))
    XCTAssertTrue(legacy.imageUnavailable)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
  }

  func testRepositoryRejectsManualEntriesWithAISuggestionProvenanceFields() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let observation = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"

    XCTAssertThrowsError(try store.save(
      input(originalAIJSON: observation, reviewedJSON: observation),
      imageStore: imageStore
    ))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)
  }

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  func testFullPrefillRepositoryRequiresCompleteEditableValuesAndDirectProvenance() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    let storeURL = root.appendingPathComponent("FullPrefillMultiEdit.store")
    let context = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
    let store = EntryStore(context: context, writeGate: .unrestricted)
    let descriptor = ModelDescriptor.liteRTGemma4E4B
    let configuration = InferenceConfiguration.appStoreRawImageV12SubjectGateTuning
    let suggestedAt = Date(timeIntervalSince1970: 1_710_000_010)
    let suggestion = FullPrefillPhotoSuggestionV1(
      imageUsable: true,
      retakeReason: nil,
      stoolPresence: .stool,
      bristolType: nil,
      form: "mixed",
      mixedForm: .yes,
      apparentColor: nil,
      redAppearingMaterial: .yes,
      blackTarryAppearance: .notSure
    )
    let originalJSON = try FullPrefillPhotoSuggestionV1Parser.canonicalJSON(
      suggestion
    )
    let normalization = try FullPrefillDependentFieldAbstentionV1
      .parseAndNormalize(originalJSON)
    let normalizationReceipt = FullPrefillNormalizationReceiptV1(
      result: normalization
    )

    func candidateInput(
      stoolPresence: StoolPresence? = .stool,
      bristolType: Int? = nil,
      form: String? = "mixed",
      mixedForm: ClinicalTriState? = .yes,
      apparentColor: String? = nil,
      confirmedPhotoUsable: Bool? = true,
      red: SymptomFlag? = .yes,
      black: SymptomFlag? = .unsure,
      redProvenance: FieldConfirmationProvenance = .acceptedUnchanged,
      blackProvenance: FieldConfirmationProvenance = .acceptedUnchanged,
      parsePath: InferenceParsePath = .direct
    ) throws -> (EntryInput, PreparedDraft) {
      let id = UUID()
      let draft = try imageStore.prepare(validImageData())
      let fieldProvenance: [ConfirmationField: FieldConfirmationProvenance] = [
        .photoUsable: .acceptedUnchanged,
        .retakeReason: .acceptedUnchanged,
        .stoolPresence: .acceptedUnchanged,
        .bristolType: .acceptedUnchanged,
        .form: .acceptedUnchanged,
        .mixedForm: .acceptedUnchanged,
        .apparentColor: .acceptedUnchanged,
        .redMaterial: redProvenance,
        .blackTarry: blackProvenance,
      ]
      let confirmation = ConfirmedEntrySnapshotV1(
        confirmedAt: suggestedAt,
        personConfirmedPhotoUsable: confirmedPhotoUsable,
        initiallyAcceptedPhotoUsable: true,
        initiallyAcceptedRetakeReason: nil,
        initiallyAcceptedStoolPresence: .stool,
        initiallyAcceptedBristolType: nil,
        initiallyAcceptedForm: "mixed",
        initiallyAcceptedMixedForm: .yes,
        initiallyAcceptedApparentColor: nil,
        initiallyAcceptedRed: .yes,
        initiallyAcceptedBlackTarry: .unsure,
        personConfirmedStoolPresence: stoolPresence,
        personConfirmedBristolType: bristolType,
        personConfirmedForm: form,
        personConfirmedMixedForm: mixedForm,
        personConfirmedApparentColor: apparentColor,
        personConfirmedRed: red,
        personConfirmedBlackTarry: black,
        fieldProvenance: fieldProvenance,
        personConfirmedSubject: nil
      )
      let modelProvenance = InferenceProvenanceSnapshot(
        descriptor: descriptor,
        configuration: configuration,
        executionLocation: .simulatorLocal,
        sanitizedImageSHA256: draft.reference.sha256,
        suggestedAt: suggestedAt,
        generationStartedAt: suggestedAt.addingTimeInterval(-1),
        generationEndedAt: suggestedAt,
        parsePath: parsePath,
        suggestionSchemaVersion: FullPrefillPhotoSuggestionV1.schemaVersion,
        fullPrefillNormalization: normalizationReceipt
      )
      return (
        EntryInput(
          id: id,
          capturedAt: Date(timeIntervalSince1970: 1_710_000_000),
          draftURL: draft.url,
          imageSHA256: draft.reference.sha256,
          redBlood: red,
          blackTarry: black,
          dizziness: nil,
          severePain: nil,
          note: nil,
          confirmedBristolType: bristolType,
          confirmedPhotoUsable: confirmedPhotoUsable,
          mixedForm: mixedForm,
          analysisSource: .gemmaRawImage,
          analysisPipelineVersion: configuration.analysisPipelineVersion,
          provenance: .ai_unedited,
          reviewedAt: suggestedAt,
          originalAIJSON: originalJSON,
          reviewedJSON: try XCTUnwrap(confirmation.canonicalJSON),
          modelID: descriptor.modelID,
          modelProvenanceJSON: try XCTUnwrap(modelProvenance.canonicalJSON),
          demoKind: nil,
          imageFilename: "\(id.uuidString).jpg"
        ),
        draft
      )
    }

    let rejectedInputs = try [
      (candidateInput(stoolPresence: nil), GITimelineError.invalidEntryProvenance),
      (candidateInput(form: nil), GITimelineError.invalidEntryProvenance),
      (candidateInput(confirmedPhotoUsable: nil), GITimelineError.invalidPhotoAttachment),
      (candidateInput(confirmedPhotoUsable: false), GITimelineError.invalidEntryProvenance),
      (candidateInput(red: nil), GITimelineError.invalidEntryProvenance),
      (candidateInput(black: nil), GITimelineError.invalidEntryProvenance),
      (candidateInput(redProvenance: .independentPersonAnswer), GITimelineError.invalidEntryProvenance),
      (candidateInput(blackProvenance: .independentPersonAnswer), GITimelineError.invalidEntryProvenance),
      (candidateInput(parsePath: .serializationRepair), GITimelineError.invalidEntryProvenance),
    ]
    for ((candidate, draft), expectedError) in rejectedInputs {
      XCTAssertThrowsError(try store.save(candidate, imageStore: imageStore)) { error in
        XCTAssertEqual(error as? GITimelineError, expectedError)
      }
      XCTAssertTrue(FileManager.default.fileExists(atPath: draft.url.path))
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 0)

    let (accepted, acceptedDraft) = try candidateInput()
    XCTAssertNoThrow(try store.save(accepted, imageStore: imageStore))
    XCTAssertTrue(FileManager.default.fileExists(atPath: acceptedDraft.url.path))
    XCTAssertTrue(try imageStore.storedImageIsVerified(
      filename: try XCTUnwrap(accepted.imageFilename),
      expectedSHA256: try XCTUnwrap(accepted.imageSHA256)
    ))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)

    let acceptedID = accepted.id
    let saved = try XCTUnwrap(
      context.fetch(
        FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == acceptedID })
      ).first
    )
    let baseline = try EntryRecordFingerprint.make(for: saved)
    var edit = EntryEditInput(entry: saved)
    let initiallyAccepted = try XCTUnwrap(saved.confirmedEntrySnapshot)
    XCTAssertEqual(initiallyAccepted.initiallyAcceptedPhotoUsable, true)
    XCTAssertNil(initiallyAccepted.initiallyAcceptedRetakeReason)
    XCTAssertEqual(initiallyAccepted.initiallyAcceptedStoolPresence, .stool)
    XCTAssertNil(initiallyAccepted.initiallyAcceptedBristolType)
    XCTAssertEqual(initiallyAccepted.initiallyAcceptedForm, "mixed")
    XCTAssertEqual(initiallyAccepted.initiallyAcceptedMixedForm, .yes)
    XCTAssertNil(initiallyAccepted.initiallyAcceptedApparentColor)
    XCTAssertEqual(initiallyAccepted.initiallyAcceptedRed, .yes)
    XCTAssertEqual(initiallyAccepted.initiallyAcceptedBlackTarry, .unsure)
    XCTAssertEqual(edit.redBlood, .yes)
    XCTAssertEqual(edit.blackTarry, .unsure)

    edit.redBlood = .no
    edit.blackTarry = .no
    try store.update(
      saved,
      with: edit,
      baselineFingerprint: baseline,
      at: suggestedAt.addingTimeInterval(2)
    )
    let updatedConfirmation = try XCTUnwrap(saved.confirmedEntrySnapshot)
    XCTAssertNil(updatedConfirmation.personConfirmedSubject)
    XCTAssertEqual(updatedConfirmation.personConfirmedStoolPresence, .stool)
    XCTAssertEqual(updatedConfirmation.personConfirmedForm, "mixed")
    XCTAssertEqual(
      updatedConfirmation.typedFieldProvenance[.redMaterial],
      .editedAfterConfirmation
    )
    XCTAssertEqual(
      updatedConfirmation.typedFieldProvenance[.blackTarry],
      .editedAfterConfirmation
    )
    XCTAssertEqual(updatedConfirmation.initiallyAcceptedRed, .yes)
    XCTAssertEqual(updatedConfirmation.initiallyAcceptedBlackTarry, .unsure)

    var unusableEdit = EntryEditInput(entry: saved)
    unusableEdit.confirmedPhotoUsable = false
    unusableEdit.retakeReason = .glare
    unusableEdit.stoolPresence = .uncertain
    // Exercise the persistence boundary with every dependent field still
    // populated, including now-irrelevant person-context questions. The
    // full-prefill closure must abstain deterministically before validation.
    unusableEdit.confirmedBristolType = 4
    unusableEdit.form = "smooth_formed"
    unusableEdit.mixedForm = .no
    unusableEdit.apparentColor = "brown"
    unusableEdit.redBlood = .yes
    unusableEdit.blackTarry = .no
    unusableEdit.strainingOrIncomplete = .yes
    unusableEdit.leakageOrAccident = .yes
    try store.update(
      saved,
      with: unusableEdit,
      baselineFingerprint: try EntryRecordFingerprint.make(for: saved),
      at: suggestedAt.addingTimeInterval(3)
    )
    let unusableConfirmation = try XCTUnwrap(saved.confirmedEntrySnapshot)
    XCTAssertFalse(try XCTUnwrap(unusableConfirmation.personConfirmedPhotoUsable))
    XCTAssertEqual(unusableConfirmation.personConfirmedRetakeReason, .glare)
    XCTAssertEqual(unusableConfirmation.personConfirmedStoolPresence, .uncertain)
    XCTAssertNil(unusableConfirmation.personConfirmedBristolType)
    XCTAssertEqual(unusableConfirmation.personConfirmedForm, "unable_to_assess")
    XCTAssertEqual(unusableConfirmation.personConfirmedMixedForm, .unsure)
    XCTAssertEqual(unusableConfirmation.personConfirmedRed, .unsure)
    XCTAssertEqual(unusableConfirmation.personConfirmedBlackTarry, .unsure)
    XCTAssertNil(saved.strainingOrIncompleteAnswer)
    XCTAssertNil(saved.leakageOrAccidentAnswer)
    XCTAssertEqual(unusableConfirmation.initiallyAcceptedPhotoUsable, true)
    XCTAssertNil(unusableConfirmation.initiallyAcceptedRetakeReason)
    XCTAssertEqual(unusableConfirmation.initiallyAcceptedStoolPresence, .stool)
    XCTAssertNil(unusableConfirmation.initiallyAcceptedBristolType)
    XCTAssertEqual(unusableConfirmation.initiallyAcceptedForm, "mixed")
    XCTAssertEqual(unusableConfirmation.initiallyAcceptedMixedForm, .yes)
    XCTAssertNil(unusableConfirmation.initiallyAcceptedApparentColor)
    XCTAssertEqual(
      unusableConfirmation.typedFieldProvenance[.retakeReason],
      .editedAfterConfirmation
    )

    let reopenedContext = ModelContext(
      try PersistenceSchema.openPublicStore(at: storeURL)
    )
    let reopenedStore = EntryStore(
      context: reopenedContext,
      writeGate: .unrestricted
    )
    let reopened = try XCTUnwrap(
      reopenedContext.fetch(
        FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == acceptedID })
      ).first
    )
    let relaunchedConfirmation = try XCTUnwrap(reopened.confirmedEntrySnapshot)
    XCTAssertNil(relaunchedConfirmation.initiallyAcceptedRetakeReason)
    XCTAssertNil(relaunchedConfirmation.initiallyAcceptedBristolType)
    XCTAssertNil(relaunchedConfirmation.initiallyAcceptedApparentColor)

    var usableAgain = EntryEditInput(entry: reopened)
    usableAgain.confirmedPhotoUsable = true
    usableAgain.retakeReason = nil
    usableAgain.stoolPresence = .stool
    usableAgain.confirmedBristolType = 3
    usableAgain.form = "cracked_formed"
    usableAgain.mixedForm = .no
    usableAgain.apparentColor = "yellow"
    usableAgain.redBlood = .no
    usableAgain.blackTarry = .no
    try reopenedStore.update(
      reopened,
      with: usableAgain,
      baselineFingerprint: try EntryRecordFingerprint.make(for: reopened),
      at: suggestedAt.addingTimeInterval(4)
    )
    let usableAgainConfirmation = try XCTUnwrap(reopened.confirmedEntrySnapshot)
    XCTAssertTrue(try XCTUnwrap(usableAgainConfirmation.personConfirmedPhotoUsable))
    XCTAssertNil(usableAgainConfirmation.personConfirmedRetakeReason)
    XCTAssertEqual(usableAgainConfirmation.personConfirmedStoolPresence, .stool)
    XCTAssertEqual(usableAgainConfirmation.personConfirmedBristolType, 3)
    XCTAssertEqual(usableAgainConfirmation.personConfirmedForm, "cracked_formed")
    XCTAssertEqual(usableAgainConfirmation.initiallyAcceptedPhotoUsable, true)
    XCTAssertEqual(usableAgainConfirmation.initiallyAcceptedStoolPresence, .stool)
    XCTAssertNil(usableAgainConfirmation.initiallyAcceptedRetakeReason)
    XCTAssertNil(usableAgainConfirmation.initiallyAcceptedBristolType)
    XCTAssertEqual(usableAgainConfirmation.initiallyAcceptedForm, "mixed")
    XCTAssertEqual(usableAgainConfirmation.initiallyAcceptedMixedForm, .yes)
    XCTAssertNil(usableAgainConfirmation.initiallyAcceptedApparentColor)
  }

  func testContradictoryRawFullPrefillNormalizesThroughDraftSaveReopenEditAndPDF() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("NormalizedFullPrefill.store")
    let drafts = root.appendingPathComponent("Drafts")
    let images = root.appendingPathComponent("Images")
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images
    )
    let context = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
    let entryStore = EntryStore(context: context, writeGate: .unrestricted)
    let raw = """
      {"schema_version":"gi-photo-full-prefill-v1","image_usable":true,"retake_reason":null,"stool_presence":"non_stool","bristol_type":4,"form":"smooth_formed","mixed_form":"no","apparent_color":"brown","red_appearing_material":"yes","black_tarry_appearance":"no"}

      """
    let expected = try FullPrefillDependentFieldAbstentionV1
      .parseAndNormalize(raw)
    XCTAssertTrue(expected.normalizationOccurred)
    let inference = MockInferenceService(scripts: [.response(raw)])
    let viewModel = NewEntryViewModel(
      imageStore: imageStore,
      store: entryStore,
      inference: inference,
      descriptor: .liteRTGemma4E4B,
      modelVerified: true,
      engineReady: true,
      configuration: .appStoreRawImageV12SubjectGateTuning,
      executionLocation: .simulatorLocal
    )

    try viewModel.prepareImageData(validImageData())
    let stagedDraft = try XCTUnwrap(viewModel.currentDraftURL)
    viewModel.analyze()
    for _ in 0..<220 where viewModel.isBusy {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertFalse(viewModel.isBusy)
    let firstCounts = await inference.invocationCounts()
    XCTAssertEqual(firstCounts.analyze, 1)
    XCTAssertEqual(firstCounts.repair, 0)
    XCTAssertEqual(viewModel.confirmedStoolPresence, .nonStool)
    XCTAssertNil(viewModel.confirmedBristolType)
    XCTAssertEqual(viewModel.confirmedForm, "unable_to_assess")
    XCTAssertEqual(viewModel.mixedForm, .unsure)
    XCTAssertEqual(viewModel.apparentColor, "unable_to_assess")
    XCTAssertEqual(viewModel.redBlood, .unsure)
    XCTAssertEqual(viewModel.blackTarry, .unsure)
    XCTAssertTrue(viewModel.canSave)
    XCTAssertFalse(viewModel.canAnalyze)

    let draftDecoder = JSONDecoder()
    draftDecoder.dateDecodingStrategy = .iso8601
    let draftSnapshot = try draftDecoder.decode(
      DraftSnapshot.self,
      from: Data(contentsOf: drafts.appendingPathComponent("active-draft.v1.json"))
    )
    XCTAssertEqual(draftSnapshot.originalValidatedJSON, raw)
    let draftReceipt = try XCTUnwrap(draftSnapshot.fullPrefillNormalization)
    XCTAssertNoThrow(try draftReceipt.validate(rawResponse: raw))
    XCTAssertEqual(draftReceipt.rawResponseSHA256, expected.rawResponseSHA256)
    XCTAssertEqual(
      draftReceipt.normalizedCanonicalSHA256,
      expected.normalizedCanonicalSHA256
    )
    XCTAssertEqual(
      draftReceipt.normalizationPolicyVersion,
      FullPrefillDependentFieldAbstentionV1.policyVersion
    )
    XCTAssertEqual(draftReceipt.normalizedFields, expected.normalizedFields)
    XCTAssertNotEqual(draftReceipt.normalizedSuggestionJSON, raw)

    let relaunchInference = MockInferenceService(scripts: [])
    let relaunched = NewEntryViewModel(
      imageStore: imageStore,
      store: entryStore,
      inference: relaunchInference,
      descriptor: .liteRTGemma4E4B,
      modelVerified: true,
      engineReady: true,
      configuration: .appStoreRawImageV12SubjectGateTuning,
      executionLocation: .simulatorLocal
    )
    relaunched.restoreUnfinishedDraftIfAvailable()
    XCTAssertEqual(relaunched.currentDraftURL, stagedDraft)
    XCTAssertEqual(relaunched.confirmedStoolPresence, .nonStool)
    XCTAssertNil(relaunched.confirmedBristolType)
    XCTAssertEqual(relaunched.confirmedForm, "unable_to_assess")
    XCTAssertEqual(relaunched.mixedForm, .unsure)
    XCTAssertEqual(relaunched.apparentColor, "unable_to_assess")
    XCTAssertEqual(relaunched.redBlood, .unsure)
    XCTAssertEqual(relaunched.blackTarry, .unsure)
    XCTAssertTrue(relaunched.canSave)
    XCTAssertFalse(relaunched.canAnalyze)
    relaunched.analyze()
    let relaunchCounts = await relaunchInference.invocationCounts()
    XCTAssertEqual(relaunchCounts.analyze, 0)
    XCTAssertEqual(relaunchCounts.repair, 0)
    XCTAssertEqual(relaunched.confirmedStoolPresence, .nonStool)

    relaunched.save()
    XCTAssertNotNil(relaunched.savedEntryID)
    XCTAssertFalse(FileManager.default.fileExists(atPath: stagedDraft.path))

    let reopenedContext = ModelContext(
      try PersistenceSchema.openPublicStore(at: storeURL)
    )
    let saved = try XCTUnwrap(
      reopenedContext.fetch(FetchDescriptor<EntryRecord>()).first
    )
    XCTAssertEqual(saved.originalAIJSON, raw)
    XCTAssertTrue(
      try imageStore.storedImageIsVerified(
        filename: try XCTUnwrap(saved.imageFilename),
        expectedSHA256: try XCTUnwrap(saved.imageSHA256)
      )
    )
    let provenanceData = try XCTUnwrap(
      saved.modelProvenanceJSON?.data(using: .utf8)
    )
    let provenance = try JSONDecoder().decode(
      InferenceProvenanceSnapshot.self,
      from: provenanceData
    )
    let savedReceipt = try XCTUnwrap(provenance.fullPrefillNormalization)
    XCTAssertNoThrow(try savedReceipt.validate(rawResponse: raw))
    let independentRawHash = SHA256.hash(data: Data(raw.utf8))
      .map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(savedReceipt.rawResponseSHA256, independentRawHash)
    XCTAssertEqual(savedReceipt.normalizedSuggestionJSON, expected.normalizedCanonicalJSON)
    XCTAssertTrue(savedReceipt.normalizedSuggestionJSON.contains("\"apparent_color\":null"))
    XCTAssertEqual(savedReceipt.normalizedFields, [
      "bristol_type", "form", "mixed_form", "apparent_color",
      "red_appearing_material", "black_tarry_appearance",
    ])
    let accepted = try XCTUnwrap(saved.confirmedEntrySnapshot)
    XCTAssertEqual(accepted.initiallyAcceptedStoolPresence, .nonStool)
    XCTAssertNil(accepted.initiallyAcceptedBristolType)
    XCTAssertEqual(accepted.initiallyAcceptedForm, "unable_to_assess")
    XCTAssertEqual(accepted.initiallyAcceptedMixedForm, .unsure)
    XCTAssertEqual(accepted.initiallyAcceptedApparentColor, "unable_to_assess")
    XCTAssertEqual(accepted.initiallyAcceptedRed, .unsure)
    XCTAssertEqual(accepted.initiallyAcceptedBlackTarry, .unsure)
    XCTAssertEqual(accepted.personConfirmedStoolPresence, .nonStool)
    XCTAssertEqual(accepted.personConfirmedApparentColor, "unable_to_assess")

    var edit = EntryEditInput(entry: saved)
    edit.confirmedPhotoUsable = true
    edit.retakeReason = nil
    edit.stoolPresence = .stool
    edit.confirmedBristolType = 3
    edit.form = "cracked_formed"
    edit.mixedForm = .no
    edit.apparentColor = "yellow"
    edit.redBlood = .no
    edit.blackTarry = .no
    edit.strainingOrIncomplete = .no
    edit.leakageOrAccident = nil
    try EntryStore(context: reopenedContext, writeGate: .unrestricted).update(
      saved,
      with: edit,
      baselineFingerprint: try EntryRecordFingerprint.make(for: saved),
      at: Date(timeIntervalSince1970: 1_720_000_000)
    )

    let finalContext = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
    let finalEntry = try XCTUnwrap(
      finalContext.fetch(FetchDescriptor<EntryRecord>()).first
    )
    XCTAssertEqual(finalEntry.originalAIJSON, raw)
    let finalConfirmation = try XCTUnwrap(finalEntry.confirmedEntrySnapshot)
    XCTAssertEqual(finalConfirmation.initiallyAcceptedStoolPresence, .nonStool)
    XCTAssertNil(finalConfirmation.initiallyAcceptedBristolType)
    XCTAssertEqual(
      finalConfirmation.initiallyAcceptedApparentColor,
      "unable_to_assess"
    )
    XCTAssertEqual(finalConfirmation.personConfirmedStoolPresence, .stool)
    XCTAssertEqual(finalConfirmation.personConfirmedBristolType, 3)
    XCTAssertEqual(finalConfirmation.personConfirmedForm, "cracked_formed")
    XCTAssertEqual(finalConfirmation.personConfirmedApparentColor, "yellow")
    XCTAssertEqual(
      finalConfirmation.typedFieldProvenance[.stoolPresence],
      .editedAfterConfirmation
    )

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.startOfDay(for: finalEntry.capturedAt)
    let export = try JournalExportSnapshotFactory.make(
      entries: [finalEntry],
      completions: [],
      treatmentEvents: [],
      range: .init(from: day, through: day),
      scope: .allEntries,
      calendar: calendar,
      timeZone: calendar.timeZone
    )
    let pdfData = try JournalPDFRenderer().render(
      snapshot: export,
      photoDirectory: images
    )
    let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
    let pdfText = (0..<pdf.pageCount)
      .compactMap { pdf.page(at: $0)?.string }
      .joined(separator: "\n")
    XCTAssertTrue(pdfText.contains("Photo included"))
    XCTAssertTrue(pdfText.contains("On-device suggestion — photo subject: Different subject"))
    XCTAssertTrue(pdfText.contains("On-device suggestion — apparent color: Not recorded"))
    XCTAssertTrue(pdfText.contains("Accepted value — photo subject: Different subject"))
    XCTAssertTrue(pdfText.contains("Accepted value — apparent color: Unable to assess"))
    XCTAssertTrue(pdfText.contains("Final value — photo subject: Bowel movement"))
    XCTAssertTrue(pdfText.contains("Final value — apparent color: Yellow"))
    XCTAssertTrue(pdfText.contains("photo subject: Edited after confirmation"))
  }
  #endif

  func testUnusablePhotoAllowsPersonSelectedBristolOnlyWhenPhotoObservationFullyAbstains() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images")
    )
    let context = ModelContext(try container())
    let store = EntryStore(context: context)
    let descriptor = ModelDescriptor.liteRTGemma4E4B
    let configuration = InferenceConfiguration.deterministicBaseline
    let modelProvenance = try XCTUnwrap(
      InferenceProvenanceSnapshot(
        descriptor: descriptor,
        configuration: configuration,
        executionLocation: .simulatorLocal
      ).canonicalJSON
    )
    let original = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
    let fullAbstention = "{\"image_usable\":false,\"quality_issue\":\"other\",\"apparent_bristol_type\":null,\"apparent_color\":\"unable_to_assess\",\"form\":\"unable_to_assess\",\"red_appearing_material\":\"unable_to_assess\",\"black_tarry_appearance\":\"unable_to_assess\"}"
    let retainedPhotoClaim = "{\"image_usable\":false,\"quality_issue\":\"other\",\"apparent_bristol_type\":null,\"apparent_color\":\"brown\",\"form\":\"unable_to_assess\",\"red_appearing_material\":\"unable_to_assess\",\"black_tarry_appearance\":\"unable_to_assess\"}"

    func aiInput(id: UUID, draft: PreparedDraft, reviewedJSON: String) -> EntryInput {
      EntryInput(
        id: id,
        capturedAt: Date(timeIntervalSince1970: 1_710_000_000),
        draftURL: draft.url,
        imageSHA256: draft.reference.sha256,
        redBlood: .unsure,
        blackTarry: .unsure,
        dizziness: nil,
        severePain: nil,
        note: nil,
        confirmedBristolType: 4,
        confirmedPhotoUsable: false,
        mixedForm: .no,
        analysisSource: .gemmaRawImage,
        analysisPipelineVersion: configuration.analysisPipelineVersion,
        provenance: .ai_edited,
        reviewedAt: Date(timeIntervalSince1970: 1_710_000_001),
        originalAIJSON: original,
        reviewedJSON: reviewedJSON,
        modelID: descriptor.modelID,
        modelProvenanceJSON: modelProvenance,
        demoKind: nil,
        imageFilename: "\(id.uuidString).jpg"
      )
    }

    let acceptedID = UUID()
    let acceptedDraft = try imageStore.prepare(validImageData())
    try store.save(
      aiInput(id: acceptedID, draft: acceptedDraft, reviewedJSON: fullAbstention),
      imageStore: imageStore
    )
    let accepted = try XCTUnwrap(
      context.fetch(FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == acceptedID })).first
    )
    XCTAssertEqual(accepted.confirmedBristolType, 4)
    XCTAssertFalse(try XCTUnwrap(accepted.confirmedPhotoUsable))
    XCTAssertNil(accepted.observation?.apparentBristolType)

    let rejectedID = UUID()
    let rejectedDraft = try imageStore.prepare(validImageData(color: .red))
    XCTAssertThrowsError(try store.save(
      aiInput(id: rejectedID, draft: rejectedDraft, reviewedJSON: retainedPhotoClaim),
      imageStore: imageStore
    )) { error in
      XCTAssertEqual(error as? GITimelineError, .invalidEntryProvenance)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: rejectedDraft.url.path))
  }

  func testDiscussionMarkIsTransactionalAndDoesNotAlterClinicalData() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(draftsDirectory: root.appendingPathComponent("Drafts"), imagesDirectory: root.appendingPathComponent("Images"))
    let store = try FailingEntryStore()
    try store.save(input(note: "Keep me"), imageStore: imageStore)
    let entry = try XCTUnwrap(store.records.first)
    let originalSymptoms = (entry.redBlood, entry.blackTarry, entry.note, entry.analysisSource)
    let markDate = Date(timeIntervalSince1970: 1_720_000_000)
    try store.setDiscussionMark(true, for: entry, at: markDate)
    XCTAssertEqual(entry.markedForDiscussionAt, markDate)
    XCTAssertEqual(entry.redBlood, originalSymptoms.0)
    XCTAssertEqual(entry.blackTarry, originalSymptoms.1)
    XCTAssertEqual(entry.note, originalSymptoms.2)
    XCTAssertEqual(entry.analysisSource, originalSymptoms.3)

    store.failNextMark = true
    XCTAssertThrowsError(try store.setDiscussionMark(false, for: entry, at: markDate.addingTimeInterval(1)))
    XCTAssertTrue(try XCTUnwrap(store.records.first).isMarkedForDiscussion)
  }

  func testDailyCompletionUpsertsOneLocalDayAndNilClearsWhileTreatmentPersists() throws {
    let container = try container()
    let context = ModelContext(container)
    var calendar = Calendar(identifier: .gregorian)
    let zone = TimeZone(identifier: "America/New_York")!
    calendar.timeZone = zone
    let store = ClinicalTimelineStore(context: context, calendar: calendar, timeZone: zone)
    let morning = ISO8601DateFormatter().date(from: "2024-03-10T06:30:00Z")!
    let evening = ISO8601DateFormatter().date(from: "2024-03-11T03:30:00Z")!
    try store.setDailyCompletion(.yes, for: morning)
    try store.setDailyCompletion(.no, for: evening)
    var completions = try context.fetch(FetchDescriptor<DailyCompletionRecord>())
    XCTAssertEqual(completions.count, 1)
    XCTAssertEqual(completions.first?.answer, .no)
    try store.setDailyCompletion(nil, for: morning)
    completions = try context.fetch(FetchDescriptor<DailyCompletionRecord>())
    XCTAssertTrue(completions.isEmpty)

    let treatment = try store.addTreatmentEvent(kind: .beganFiber, name: "Synthetic fiber", doseOrNote: "One note", effectiveDate: evening)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TreatmentEventRecord>()), 1)
    XCTAssertEqual(treatment.kind, .beganFiber)
    XCTAssertEqual(treatment.effectiveDate, calendar.startOfDay(for: evening))
  }

  func testTreatmentUpdatePersistsNormalizedFieldsAndPreservesCreationIdentity() throws {
    let container = try container()
    let context = ModelContext(container)
    var calendar = Calendar(identifier: .gregorian)
    let zone = TimeZone(identifier: "America/New_York")!
    calendar.timeZone = zone
    let store = ClinicalTimelineStore(context: context, calendar: calendar, timeZone: zone)
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
    let updatedAt = Date(timeIntervalSince1970: 1_720_000_000)
    let newEffectiveDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-07-15T22:15:00Z"))
    let treatment = try store.addTreatmentEvent(
      kind: .startedTreatment,
      name: "Original marker",
      doseOrNote: "Original note",
      effectiveDate: createdAt,
      now: createdAt
    )
    let originalID = treatment.id

    try store.updateTreatmentEvent(
      treatment,
      kind: .changedDose,
      name: "  Updated marker\n",
      doseOrNote: "  Documentation only  ",
      effectiveDate: newEffectiveDate,
      now: updatedAt
    )

    let persisted = try XCTUnwrap(try context.fetch(FetchDescriptor<TreatmentEventRecord>()).first)
    XCTAssertEqual(persisted.id, originalID)
    XCTAssertEqual(persisted.kind, .changedDose)
    XCTAssertEqual(persisted.name, "Updated marker")
    XCTAssertEqual(persisted.doseOrNote, "Documentation only")
    XCTAssertEqual(persisted.effectiveDate, calendar.startOfDay(for: newEffectiveDate))
    XCTAssertEqual(persisted.createdAt, createdAt)
    XCTAssertEqual(persisted.updatedAt, updatedAt)
  }

  func testTreatmentUpdateRejectsEmptyNameWithoutChangingPersistedRecord() throws {
    let context = ModelContext(try container())
    let store = ClinicalTimelineStore(context: context)
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
    let treatment = try store.addTreatmentEvent(
      kind: .beganFiber,
      name: "Original marker",
      doseOrNote: "Original note",
      effectiveDate: createdAt,
      now: createdAt
    )

    XCTAssertThrowsError(
      try store.updateTreatmentEvent(
        treatment,
        kind: .stoppedTreatment,
        name: " \n\t ",
        doseOrNote: nil,
        effectiveDate: createdAt.addingTimeInterval(86_400),
        now: createdAt.addingTimeInterval(10)
      )
    ) { error in
      XCTAssertEqual(error as? ClinicalTimelineStoreError, .emptyTreatmentName)
    }

    let persisted = try XCTUnwrap(try context.fetch(FetchDescriptor<TreatmentEventRecord>()).first)
    XCTAssertEqual(persisted.kind, .beganFiber)
    XCTAssertEqual(persisted.name, "Original marker")
    XCTAssertEqual(persisted.doseOrNote, "Original note")
    XCTAssertEqual(persisted.createdAt, createdAt)
    XCTAssertEqual(persisted.updatedAt, createdAt)
  }

  func testTreatmentUpdateRollsBackEveryFieldWhenPreSaveTransactionFails() throws {
    let context = ModelContext(try container())
    let originalStore = ClinicalTimelineStore(context: context)
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
    let treatment = try originalStore.addTreatmentEvent(
      kind: .startedTreatment,
      name: "Original marker",
      doseOrNote: "Original note",
      effectiveDate: createdAt,
      now: createdAt
    )
    let failingStore = ClinicalTimelineStore(
      context: context,
      failureInjector: { point in
        if case .afterTreatmentUpdateBeforeSave = point {
          throw CocoaError(.fileWriteUnknown)
        }
      }
    )

    XCTAssertThrowsError(
      try failingStore.updateTreatmentEvent(
        treatment,
        kind: .changedDiet,
        name: "Changed marker",
        doseOrNote: nil,
        effectiveDate: createdAt.addingTimeInterval(86_400),
        now: createdAt.addingTimeInterval(20)
      )
    )

    let persisted = try XCTUnwrap(try context.fetch(FetchDescriptor<TreatmentEventRecord>()).first)
    XCTAssertEqual(persisted.kind, .startedTreatment)
    XCTAssertEqual(persisted.name, "Original marker")
    XCTAssertEqual(persisted.doseOrNote, "Original note")
    XCTAssertEqual(persisted.effectiveDate, Calendar.current.startOfDay(for: createdAt))
    XCTAssertEqual(persisted.createdAt, createdAt)
    XCTAssertEqual(persisted.updatedAt, createdAt)
  }

  func testTreatmentDeletePersistsAndFailedDeleteRollsBack() throws {
    let context = ModelContext(try container())
    let store = ClinicalTimelineStore(context: context)
    let retained = try store.addTreatmentEvent(
      kind: .other,
      name: "Retained after rollback",
      doseOrNote: nil,
      effectiveDate: Date()
    )
    let deleted = try store.addTreatmentEvent(
      kind: .changedDiet,
      name: "Delete me",
      doseOrNote: nil,
      effectiveDate: Date()
    )
    let failingStore = ClinicalTimelineStore(
      context: context,
      failureInjector: { point in
        if case .afterTreatmentDeleteBeforeSave = point {
          throw CocoaError(.fileWriteUnknown)
        }
      }
    )

    XCTAssertThrowsError(try failingStore.deleteTreatmentEvent(retained))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TreatmentEventRecord>()), 2)
    try store.deleteTreatmentEvent(deleted)
    let remaining = try context.fetch(FetchDescriptor<TreatmentEventRecord>())
    XCTAssertEqual(remaining.map(\.id), [retained.id])
  }

  func testTreatmentUpdateAndDeleteRespectJournalWriteGate() throws {
    let context = ModelContext(try container())
    let treatment = try ClinicalTimelineStore(context: context).addTreatmentEvent(
      kind: .other,
      name: "Protected marker",
      doseOrNote: nil,
      effectiveDate: Date()
    )
    let blockedStore = ClinicalTimelineStore(
      context: context,
      writeGate: JournalWriteGate { true }
    )

    XCTAssertThrowsError(
      try blockedStore.updateTreatmentEvent(
        treatment,
        kind: .changedDiet,
        name: "Must not change",
        doseOrNote: nil,
        effectiveDate: Date()
      )
    ) { error in
      XCTAssertEqual(error as? JournalWriteGateError, .erasePending)
    }
    XCTAssertThrowsError(try blockedStore.deleteTreatmentEvent(treatment)) { error in
      XCTAssertEqual(error as? JournalWriteGateError, .erasePending)
    }

    let persisted = try XCTUnwrap(try context.fetch(FetchDescriptor<TreatmentEventRecord>()).first)
    XCTAssertEqual(persisted.name, "Protected marker")
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<TreatmentEventRecord>()), 1)
  }

  func testDuplicateDailyCompletionFailsClosedWithoutDeletingEitherRecord() throws {
    let container = try container()
    let context = ModelContext(container)
    var calendar = Calendar(identifier: .gregorian)
    let zone = TimeZone(identifier: "America/New_York")!
    calendar.timeZone = zone
    let date = ISO8601DateFormatter().date(from: "2024-03-10T17:00:00Z")!
    let calculator = TreatmentResponseCalculator(calendar: calendar, timeZone: zone)
    let dayKey = calculator.dayKey(for: date)
    let first = DailyCompletionRecord(dayKey: dayKey, dayStart: calculator.localDayStart(for: date), answer: .yes)
    let second = DailyCompletionRecord(dayKey: dayKey, dayStart: calculator.localDayStart(for: date), answer: .no)
    // Keep the corrupt fixture in the current context without saving it: the
    // unique constraint blocks creation of this state in a healthy store, but
    // migration/corruption handling must still refuse to choose one.
    context.insert(first)
    context.insert(second)
    let store = ClinicalTimelineStore(context: context, calendar: calendar, timeZone: zone)

    XCTAssertThrowsError(try store.setDailyCompletion(.yes, for: date)) { error in
      XCTAssertEqual(error as? ClinicalTimelineStoreError, .duplicateDailyCompletion)
    }
    let duplicates = try context.fetch(
      FetchDescriptor<DailyCompletionRecord>(predicate: #Predicate { $0.dayKey == dayKey })
    )
    XCTAssertEqual(duplicates.count, 2)
    XCTAssertEqual(Set(duplicates.compactMap(\.answer)), Set([.yes, .no]))
  }

  func testEntryEditPreservesImmutablePhotoAndProvenanceAndRollsBackAllMutableFields() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images"),
      writeGate: .unrestricted
    )
    let context = ModelContext(try container())
    let store = EntryStore(context: context, writeGate: .unrestricted)
    let (entryInput, _) = try preparedPhotoInput(imageStore)
    try store.save(entryInput, imageStore: imageStore)
    let original = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
    let originalID = original.id
    let originalFilename = original.imageFilename
    let originalHash = original.imageSHA256
    let originalAnalysisSource = original.analysisSource
    let originalProvenance = original.provenance
    let originalCreatedAt = original.createdAt
    let successfulUpdateDate = Date(timeIntervalSince1970: 1_720_000_000)
    var successfulEdit = EntryEditInput(entry: original)
    successfulEdit.capturedAt = original.capturedAt.addingTimeInterval(86_400)
    successfulEdit.redBlood = .yes
    successfulEdit.blackTarry = .unsure
    successfulEdit.dizziness = .yes
    successfulEdit.severePain = .yes
    successfulEdit.note = "  Persisted edit  "
    successfulEdit.painScore = 5
    successfulEdit.urgency = .severe
    successfulEdit.confirmedBristolType = 5
    successfulEdit.confirmedPhotoUsable = false
    successfulEdit.mixedForm = .yes
    successfulEdit.strainingOrIncomplete = .yes
    successfulEdit.leakageOrAccident = nil
    try store.update(original, with: successfulEdit, at: successfulUpdateDate)

    let persisted = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
    XCTAssertEqual(persisted.note, "Persisted edit")
    XCTAssertEqual(persisted.updatedAt, successfulUpdateDate)
    XCTAssertEqual(persisted.id, originalID)
    XCTAssertEqual(persisted.imageFilename, originalFilename)
    XCTAssertEqual(persisted.imageSHA256, originalHash)
    XCTAssertEqual(persisted.analysisSource, originalAnalysisSource)
    XCTAssertEqual(persisted.provenance, originalProvenance)
    XCTAssertEqual(persisted.createdAt, originalCreatedAt)

    var rejectedEdit = EntryEditInput(entry: persisted)
    rejectedEdit.capturedAt = persisted.capturedAt.addingTimeInterval(86_400)
    rejectedEdit.redBlood = .no
    rejectedEdit.blackTarry = .yes
    rejectedEdit.dizziness = .no
    rejectedEdit.severePain = .no
    rejectedEdit.note = "Must roll back"
    rejectedEdit.painScore = 9
    rejectedEdit.urgency = .moderate
    rejectedEdit.confirmedBristolType = 6
    rejectedEdit.confirmedPhotoUsable = true
    rejectedEdit.mixedForm = .no
    rejectedEdit.strainingOrIncomplete = nil
    rejectedEdit.leakageOrAccident = .yes
    let failingStore = EntryStore(
      context: context,
      failureInjector: { point in
        if case .afterUpdateBeforeSave = point { throw CocoaError(.fileWriteUnknown) }
      },
      writeGate: .unrestricted
    )
    XCTAssertThrowsError(
      try failingStore.update(persisted, with: rejectedEdit, at: successfulUpdateDate.addingTimeInterval(100))
    )

    let afterRollback = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
    XCTAssertEqual(afterRollback.capturedAt, successfulEdit.capturedAt)
    XCTAssertEqual(afterRollback.redBlood, SymptomFlag.yes.rawValue)
    XCTAssertEqual(afterRollback.blackTarry, SymptomFlag.unsure.rawValue)
    XCTAssertEqual(afterRollback.dizziness, SymptomFlag.yes.rawValue)
    XCTAssertEqual(afterRollback.severePain, SymptomFlag.yes.rawValue)
    XCTAssertEqual(afterRollback.note, "Persisted edit")
    XCTAssertEqual(afterRollback.painScore, 5)
    XCTAssertEqual(afterRollback.urgency, UrgencyLevel.severe.rawValue)
    XCTAssertEqual(afterRollback.confirmedBristolType, 5)
    XCTAssertEqual(afterRollback.confirmedPhotoUsable, false)
    XCTAssertEqual(afterRollback.mixedForm, ClinicalTriState.yes.rawValue)
    XCTAssertEqual(afterRollback.strainingOrIncomplete, ClinicalTriState.yes.rawValue)
    XCTAssertNil(afterRollback.leakageOrAccident)
    XCTAssertEqual(afterRollback.updatedAt, successfulUpdateDate)
    XCTAssertEqual(afterRollback.id, originalID)
    XCTAssertEqual(afterRollback.imageFilename, originalFilename)
    XCTAssertEqual(afterRollback.imageSHA256, originalHash)
    XCTAssertEqual(afterRollback.analysisSource, originalAnalysisSource)
    XCTAssertEqual(afterRollback.provenance, originalProvenance)
    XCTAssertEqual(afterRollback.createdAt, originalCreatedAt)
  }

  func testNoBowelMovementExplicitlyReplacesLegacyAnswerButRemovalPreservesLegacyAnswerAndEntryConflictFailsClosed() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let context = ModelContext(try container())
    var calendar = Calendar(identifier: .gregorian)
    let zone = TimeZone(identifier: "America/New_York")!
    calendar.timeZone = zone
    let store = ClinicalTimelineStore(
      context: context,
      calendar: calendar,
      timeZone: zone,
      writeGate: .unrestricted
    )
    let eventDate = Date(timeIntervalSince1970: 1_710_000_000)

    try store.setDailyCompletion(.yes, for: eventDate)
    try store.setNoBowelMovement(true, for: eventDate)
    var completions = try context.fetch(FetchDescriptor<DailyCompletionRecord>())
    XCTAssertEqual(completions.count, 1)
    XCTAssertEqual(completions.first?.answer, .noBowelMovement)

    try store.setNoBowelMovement(false, for: eventDate)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyCompletionRecord>()), 0)
    try store.setDailyCompletion(.yes, for: eventDate)
    try store.setNoBowelMovement(false, for: eventDate)
    completions = try context.fetch(FetchDescriptor<DailyCompletionRecord>())
    XCTAssertEqual(completions.count, 1)
    XCTAssertEqual(completions.first?.answer, .yes)

    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts"),
      imagesDirectory: root.appendingPathComponent("Images"),
      writeGate: .unrestricted
    )
    try EntryStore(context: context, writeGate: .unrestricted).save(input(), imageStore: imageStore)
    XCTAssertThrowsError(try store.setNoBowelMovement(true, for: eventDate)) { error in
      XCTAssertEqual(error as? ClinicalTimelineStoreError, .bowelMovementAlreadyRecorded)
    }
    completions = try context.fetch(FetchDescriptor<DailyCompletionRecord>())
    XCTAssertEqual(completions.count, 1)
    XCTAssertEqual(completions.first?.answer, .yes)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EntryRecord>()), 1)
  }

  func testMarkerOnlyPDFIncludesNoBowelMovementDayWithoutInventingEntry() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    var calendar = Calendar(identifier: .gregorian)
    let zone = TimeZone(identifier: "America/New_York")!
    calendar.timeZone = zone
    let day = Date(timeIntervalSince1970: 1_710_000_000)
    let snapshot = try JournalExportBuilder(calendar: calendar, timeZone: zone).build(
      range: .init(from: day, through: day),
      scope: .allEntries,
      entries: [],
      completions: [.init(day: day, answer: .noBowelMovement)],
      treatmentMarkers: [],
      generatedAt: day
    )
    XCTAssertTrue(snapshot.entries.isEmpty)
    XCTAssertEqual(snapshot.noBowelMovementDays, [calendar.startOfDay(for: day)])

    let data = try JournalPDFRenderer().render(snapshot: snapshot, photoDirectory: root)
    let document = try XCTUnwrap(PDFDocument(data: data))
    let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    let normalizedText = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = zone
    formatter.dateFormat = "MMM d, yyyy"
    XCTAssertTrue(normalizedText.contains("0 entries | All entries"))
    XCTAssertTrue(normalizedText.contains("Days with no bowel movement"))
    XCTAssertTrue(normalizedText.contains(formatter.string(from: calendar.startOfDay(for: day))))
    XCTAssertFalse(normalizedText.contains("Entry 1 -"))
  }

  func testPDFIsValidSearchableAndPaginatesCompleteLongNoteWithoutPhoto() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let longNote = (0..<450).map { "word\($0)" }.joined(separator: " ") + " FINAL LONG NOTE TOKEN"
    let range = JournalExportRange(from: Date(timeIntervalSince1970: 1_710_000_000), through: Date(timeIntervalSince1970: 1_710_000_000))
    let entry = JournalExportEntry(
      id: UUID(), capturedAt: Date(timeIntervalSince1970: 1_710_000_000), confirmedBristolType: 4,
      mixedForm: .no, painScore: 3, urgency: .moderate, strainingOrIncomplete: .no,
      redBlood: .unsure, blackTarry: .no, dizziness: .no, severeOrWorseningPain: .no,
      note: longNote, markedForDiscussionAt: Date(timeIntervalSince1970: 1_710_000_001), photoState: .noPhoto
    )
    var calendar = Calendar(identifier: .gregorian); let zone = TimeZone(identifier: "America/New_York")!; calendar.timeZone = zone
    let snapshot = try JournalExportBuilder(calendar: calendar, timeZone: zone).build(
      range: range, scope: .allEntries, entries: [entry], completions: [], treatmentMarkers: [], generatedAt: Date(timeIntervalSince1970: 1_710_000_100)
    )
    let data = try JournalPDFRenderer().render(snapshot: snapshot, photoDirectory: root)
    let document = try XCTUnwrap(PDFDocument(data: data))
    XCTAssertGreaterThan(document.pageCount, 1)
    let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    let normalizedText = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    XCTAssertTrue(text.contains("GI Journal"))
    XCTAssertTrue(text.contains("No photo attached"))
    XCTAssertTrue(normalizedText.contains("FINAL LONG NOTE TOKEN"))
    XCTAssertEqual(text.components(separatedBy: "Entry 1 -").count - 1, 1)
    XCTAssertTrue(normalizedText.contains("An unmarked entry is not a safety signal or reassurance."))
    XCTAssertFalse(text.localizedCaseInsensitiveContains("analysisPipelineVersion"))
    XCTAssertEqual(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "GI Journal")
  }

  func testMissingSelectedPhotoFailsClosedBeforePDFDataIsReturned() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let id = UUID()
    let day = Date(timeIntervalSince1970: 1_710_000_000)
    let entry = JournalExportEntry(
      id: id,
      capturedAt: day,
      confirmedBristolType: 4,
      photoState: .available(filename: "\(id.uuidString).jpg"),
      photoSHA256: String(repeating: "0", count: 64)
    )
    let snapshot = try JournalExportBuilder().build(
      range: .init(from: day, through: day),
      scope: .allEntries,
      entries: [entry],
      completions: [],
      treatmentMarkers: [],
      generatedAt: day
    )

    XCTAssertThrowsError(try JournalPDFRenderer().render(snapshot: snapshot, photoDirectory: root)) { error in
      guard case JournalPDFExportError.photoIntegrity = error else {
        return XCTFail("Expected photo-integrity failure, got \(error)")
      }
    }
  }

  func testRendererBoundsPhotoAndDoesNotEmbedOriginalJPEGBytes() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let day = Date(timeIntervalSince1970: 1_710_000_000)
    let id = UUID()
    let photo = try writeSanitizedJournalPhoto(to: root, id: id, color: .systemGreen)
    let entry = JournalExportEntry(
      id: id,
      capturedAt: day,
      confirmedBristolType: 4,
      photoState: .available(filename: photo.filename),
      photoSHA256: photo.hash
    )
    let snapshot = try JournalExportBuilder().build(range: .init(from: day, through: day), scope: .allEntries, entries: [entry], completions: [], treatmentMarkers: [], generatedAt: day)
    let pdf = try JournalPDFRenderer().render(snapshot: snapshot, photoDirectory: root)
    XCTAssertNotNil(PDFDocument(data: pdf))
    XCTAssertNil(pdf.range(of: photo.bytes), "The renderer must redraw a bounded thumbnail, never embed the original JPEG bytes.")
  }

  func testExportCleanupCannotRemoveFilesOutsideExportsDirectory() throws {
    let external = temporaryRoot().appendingPathComponent("journal-image.jpg")
    try Data("journal".utf8).write(to: external)
    let export = try AppFolders.writeExport(Data("pdf".utf8), filename: "GI-Journal_2000-01-01_to_2000-01-01.pdf")
    XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
    try AppFolders.removeExport(external)
    XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
    try AppFolders.removeExport(export)
    XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
  }

  func testPreEraseBlockedPDFRenderCannotWriteAfterMarkerClears() async throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let day = Date(timeIntervalSince1970: 1_710_000_000)
    let snapshot = try JournalExportBuilder().build(
      range: .init(from: day, through: day),
      scope: .allEntries,
      entries: [JournalExportEntry(id: UUID(), capturedAt: day, confirmedBristolType: 4, photoState: .noPhoto)],
      completions: [],
      treatmentMarkers: [],
      generatedAt: day
    )
    let output = root.appendingPathComponent(snapshot.filename)
    let epoch = JournalWriteEpoch()
    var markerExists = false
    var writerWasCalled = false
    let gate = JournalWriteGate(
      pendingEraseProbe: { markerExists },
      epoch: epoch
    )
    let renderProbe = BlockingPDFRenderProbe()
    defer { renderProbe.finish() }
    let task = Task { @MainActor in
      try await JournalPDFExporter.createPDF(
        snapshot: snapshot,
        photoDirectory: root,
        writeGate: gate,
        renderer: { _, _ in try renderProbe.render() },
        exportWriter: { data, _, _ in
          writerWasCalled = true
          try data.write(to: output, options: .atomic)
          return output
        }
      )
    }

    await Task.yield()
    XCTAssertTrue(renderProbe.waitUntilStarted(), "Detached PDF rendering did not reach the deterministic barrier.")
    epoch.invalidateCurrentWriters()
    markerExists = true
    markerExists = false
    renderProbe.finish()
    do {
      _ = try await task.value
      XCTFail("A PDF render retained from before confirmed erase must not commit.")
    } catch {
      XCTAssertEqual(error as? JournalWriteGateError, .staleWriter)
    }
    XCTAssertFalse(writerWasCalled)
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
  }

  func testStalePDFLifecycleCannotRemoveNewExportAtSameDeterministicPath() throws {
    let epoch = JournalWriteEpoch()
    var markerExists = false
    let oldGate = JournalWriteGate(
      pendingEraseProbe: { markerExists },
      epoch: epoch
    )
    let filename = "GI-Journal_epoch-collision-\(UUID().uuidString).pdf"
    let oldURL = try AppFolders.writeExport(Data("old export".utf8), filename: filename, writeGate: oldGate)

    epoch.invalidateCurrentWriters()
    markerExists = true
    // Simulate erase authority removing the old preview before marker clear.
    try FileManager.default.removeItem(at: oldURL)
    markerExists = false
    let newGate = JournalWriteGate(
      pendingEraseProbe: { markerExists },
      epoch: epoch
    )
    let newURL = try AppFolders.writeExport(Data("new export".utf8), filename: filename, writeGate: newGate)
    defer { try? AppFolders.removeExport(newURL, writeGate: newGate) }

    XCTAssertThrowsError(try AppFolders.removeExport(newURL, writeGate: oldGate)) { error in
      XCTAssertEqual(error as? JournalWriteGateError, .staleWriter)
    }
    XCTAssertEqual(try Data(contentsOf: newURL), Data("new export".utf8))
  }

  func testInferenceCallerDeadlineReturnsWhenOperationIgnoresCancellation() async {
    let probe = NonCooperativeInferenceProbe()
    let startedAt = ContinuousClock.now
    let task = Task {
      try await InferenceCallerDeadlineRace.run(deadline: .milliseconds(20)) {
        await probe.value()
      }
    }
    await probe.waitUntilStarted()
    defer { probe.finish() }

    do {
      _ = try await task.value
      XCTFail("A non-cooperative inference operation must not hold its caller indefinitely.")
    } catch {
      XCTAssertEqual(error as? InferenceCallerContainmentError, .timedOut)
    }
    XCTAssertLessThan(startedAt.duration(to: .now), .milliseconds(500))
    XCTAssertEqual(probe.cancellationCount, 1, "Containment should still request best-effort native cancellation.")
  }

  func testPreparationDeadlineReturnsWithoutCancellingNonCooperativeInitializer() async {
    let probe = NonCooperativeInferenceProbe()
    let startedAt = ContinuousClock.now
    let task = Task {
      try await InferenceCallerDeadlineRace.run(
        deadline: .milliseconds(20),
        cancelOperationOnContainment: false
      ) {
        await probe.value()
      }
    }
    await probe.waitUntilStarted()
    defer { probe.finish() }

    do {
      _ = try await task.value
      XCTFail("Preparation containment must release its caller when the initializer does not return.")
    } catch {
      XCTAssertEqual(error as? InferenceCallerContainmentError, .timedOut)
    }
    XCTAssertLessThan(startedAt.duration(to: .now), .milliseconds(500))
    XCTAssertEqual(
      probe.cancellationCount,
      0,
      "Preparation containment must not cancel or replace LiteRT's sole initializer."
    )
  }

  func testPreparationDeadlinePublishesOneTerminalAndLateCompletionStaysQuarantined() async throws {
    let nativeProbe = SynchronousBlockingInferenceProbe()
    let disposition = InferenceCallerContainmentDisposition { containment in
      guard containment == .timedOut else { return }
      nativeProbe.recordDeadlineFired()
    }
    var gate = RuntimeCoordinatorGate()
    let token = try gate.acquire(descriptorID: "e4b", purpose: .transient)
    XCTAssertTrue(gate.beginContainedCall(token))
    let startedAt = ContinuousClock.now
    let task = Task {
      try await InferenceCallerDeadlineRace.run(
        deadline: .milliseconds(40),
        cancelOperationOnContainment: false,
        containmentDisposition: disposition
      ) {
        nativeProbe.value()
      }
    }
    await nativeProbe.waitUntilStarted()
    defer { nativeProbe.finish() }

    let terminalPublished = await nativeProbe.waitUntilDeadlineFired()
    XCTAssertTrue(terminalPublished)
    XCTAssertLessThan(
      startedAt.duration(to: .now),
      .seconds(1),
      "Terminal preparation containment must not await the blocked native initializer."
    )
    XCTAssertEqual(disposition.state, .contained(.timedOut))

    do {
      _ = try await task.value
      XCTFail("The caller must receive the committed preparation deadline failure.")
    } catch {
      XCTAssertEqual(error as? InferenceCallerContainmentError, .timedOut)
      gate.quarantine(token)
    }
    XCTAssertTrue(gate.hasQuarantinedOperation)

    // The native-shaped operation is deliberately released only after the
    // caller has failed. Its stale success must not replace the terminal
    // disposition or allow the same lease to reopen in this process.
    nativeProbe.finish()
    try? await Task.sleep(for: .milliseconds(100))
    gate.finishContainedCall(token)
    gate.release(token)
    XCTAssertEqual(disposition.state, .contained(.timedOut))
    XCTAssertEqual(nativeProbe.deadlineFiredCount, 1)
    XCTAssertTrue(gate.hasQuarantinedOperation)
    XCTAssertTrue(gate.hasLease)
  }

  func testPreparationCallerCancellationDoesNotCancelNonCooperativeInitializer() async {
    let probe = NonCooperativeInferenceProbe()
    let task = Task {
      try await InferenceCallerDeadlineRace.run(
        deadline: .seconds(5),
        cancelOperationOnContainment: false
      ) {
        await probe.value()
      }
    }
    await probe.waitUntilStarted()
    defer { probe.finish() }
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Caller cancellation must release the preparation caller.")
    } catch {
      XCTAssertEqual(error as? InferenceCallerContainmentError, .callerCancelled)
    }
    XCTAssertEqual(
      probe.cancellationCount,
      0,
      "Caller cancellation must leave the sole native initializer alive behind its quarantined lease."
    )
  }

  func testPreparationCancellationBeforeStartDoesNotRunOrRequireQuarantine() async {
    let probe = NonCooperativeInferenceProbe()
    let reachedPreCommit = DispatchSemaphore(value: 0)
    let releasePreCommit = DispatchSemaphore(value: 0)
    let task = Task {
      try await InferenceCallerDeadlineRace.run(
        deadline: .seconds(5),
        cancelOperationOnContainment: false,
        beforeOperationCommitForTesting: {
          reachedPreCommit.signal()
          _ = releasePreCommit.wait(timeout: .now() + 1)
        }
      ) {
        await probe.value()
      }
    }

    let didReachPreCommit = await waitForTestSignal(reachedPreCommit)
    XCTAssertTrue(didReachPreCommit)
    task.cancel()
    releasePreCommit.signal()

    do {
      _ = try await task.value
      XCTFail("Cancellation before the operation-start commit must release the caller.")
    } catch {
      let containment = error as? InferenceCallerContainmentError
      XCTAssertEqual(containment, .callerCancelledBeforeOperationStarted)
      XCTAssertFalse(containment?.requiresQuarantine ?? true)
    }
    XCTAssertFalse(probe.hasStarted)
    XCTAssertEqual(probe.cancellationCount, 0)
  }

  func testQuarantinedPreparationLeaseRejectsRetryTransitionAndStaleRelease() throws {
    var gate = RuntimeCoordinatorGate()
    let token = try gate.acquire(descriptorID: "e4b", purpose: .transient)
    XCTAssertTrue(gate.beginContainedCall(token))

    gate.quarantine(token)
    XCTAssertTrue(gate.hasLease)
    XCTAssertTrue(gate.hasQuarantinedOperation)
    XCTAssertThrowsError(try gate.acquire(descriptorID: "e4b", purpose: .transient))
    XCTAssertThrowsError(try gate.beginTransition())

    gate.finishContainedCall(token)
    gate.release(token)
    XCTAssertTrue(
      gate.hasQuarantinedOperation,
      "A late initializer completion or same-token release must not reopen the engine gate."
    )
    XCTAssertTrue(gate.hasLease)
  }

  func testCancellationStatusRequiresFinalQuarantineRatherThanUnsettledReservation() throws {
    var gate = RuntimeCoordinatorGate()
    let token = try gate.acquire(descriptorID: "e4b", purpose: .transient)
    XCTAssertFalse(gate.requiresRestartAfterCancellation)
    XCTAssertTrue(gate.beginContainedCall(token))
    XCTAssertFalse(
      gate.requiresRestartAfterCancellation,
      "A reservation is not proof that native invocation committed."
    )
    gate.quarantine(token)
    XCTAssertTrue(
      gate.requiresRestartAfterCancellation,
      "Only a finalized quarantine requires a new app process."
    )
  }

  func testInferenceCallerOSDeadlineReturnsWhenOperationBlocksSynchronously() async {
    let probe = SynchronousBlockingInferenceProbe()
    let startedAt = ContinuousClock.now
    let task = Task {
      try await InferenceCallerDeadlineRace.run(
        deadline: .milliseconds(40),
        onDeadlineThreadStarted: { probe.recordDeadlineThreadStarted() },
        onDeadline: { probe.recordDeadlineFired() }
      ) {
        probe.value()
      }
    }
    await probe.waitUntilStarted()
    defer { probe.finish() }

    do {
      _ = try await task.value
      XCTFail("An OS-backed deadline must release a caller blocked in synchronous native-shaped work.")
    } catch {
      XCTAssertEqual(error as? InferenceCallerContainmentError, .timedOut)
    }
    XCTAssertLessThan(startedAt.duration(to: .now), .seconds(1))
    let deadlineThreadStarted = await probe.waitUntilDeadlineThreadStarted()
    let deadlineFired = await probe.waitUntilDeadlineFired()
    XCTAssertTrue(deadlineThreadStarted)
    XCTAssertTrue(deadlineFired)
    XCTAssertEqual(probe.deadlineThreadStartedCount, 1)
    XCTAssertEqual(probe.deadlineFiredCount, 1)
  }

  func testPreparationDeadlineThreadStagesAreOrderedAroundCallerContainment() async {
    let operationProbe = SynchronousBlockingInferenceProbe()
    let stageProbe = DeadlineThreadStageProbe()
    let startedAt = ContinuousClock.now
    let task = Task {
      try await InferenceCallerDeadlineRace.run(
        deadline: .milliseconds(40),
        cancelOperationOnContainment: false,
        deadlineThreadObserver: { stageProbe.record($0) }
      ) {
        operationProbe.value()
      }
    }
    await operationProbe.waitUntilStarted()
    defer { operationProbe.finish() }

    do {
      _ = try await task.value
      XCTFail("Preparation containment must release the caller before native-shaped work returns.")
    } catch {
      XCTAssertEqual(error as? InferenceCallerContainmentError, .timedOut)
    }
    XCTAssertLessThan(startedAt.duration(to: .now), .seconds(1))
    let didPublishResumeStage = await stageProbe.waitUntilContinuationResumeReturned()
    XCTAssertTrue(didPublishResumeStage)
    XCTAssertEqual(
      stageProbe.stages,
      [
        .threadStarted,
        .waitElapsedBeforeLocks,
        .containmentCommitted,
        .continuationResumeReturned,
      ]
    )
  }

  func testInferenceCallerFastResultDisarmsDedicatedDeadlineThread() async throws {
    let probe = SynchronousBlockingInferenceProbe()
    let stageProbe = DeadlineThreadStageProbe()
    let value = try await InferenceCallerDeadlineRace.run(
      deadline: .milliseconds(40),
      onDeadline: { probe.recordDeadlineFired() },
      deadlineThreadObserver: { stageProbe.record($0) }
    ) {
      "fast"
    }

    XCTAssertEqual(value, "fast")
    try? await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(
      probe.deadlineFiredCount,
      0,
      "A completed operation must disarm its dedicated deadline thread."
    )
    XCTAssertEqual(
      stageProbe.stages,
      [.threadStarted],
      "A disarmed deadline must not publish elapsed or containment stages."
    )
  }

  func testBlockingDeadlineThreadObserverCannotDelayCallerContainment() async {
    let operationProbe = SynchronousBlockingInferenceProbe()
    let observerEntered = DispatchSemaphore(value: 0)
    let releaseObserver = DispatchSemaphore(value: 0)
    let disposition = InferenceCallerContainmentDisposition()
    let startedAt = ContinuousClock.now
    let task = Task {
      try await InferenceCallerDeadlineRace.run(
        deadline: .milliseconds(40),
        cancelOperationOnContainment: false,
        containmentDisposition: disposition,
        deadlineThreadObserver: { stage in
          guard stage == .threadStarted else { return }
          observerEntered.signal()
          _ = releaseObserver.wait(timeout: .now() + 1)
        }
      ) {
        operationProbe.value()
      }
    }
    defer {
      releaseObserver.signal()
      operationProbe.finish()
    }

    let didEnterObserver = await waitForTestSignal(observerEntered)
    XCTAssertTrue(didEnterObserver)
    do {
      _ = try await task.value
      XCTFail("A blocked diagnostic observer must not prevent caller containment.")
    } catch {
      XCTAssertEqual(error as? InferenceCallerContainmentError, .timedOut)
    }
    XCTAssertLessThan(
      startedAt.duration(to: .now),
      .milliseconds(300),
      "Observer delivery must remain off the containment thread."
    )
    XCTAssertEqual(disposition.state, .contained(.timedOut))
  }

  func testInferenceCallerResolvesBeforePotentiallyBlockingDeadlineTelemetry() async {
    let operationProbe = SynchronousBlockingInferenceProbe()
    let telemetryEntered = DispatchSemaphore(value: 0)
    let releaseTelemetry = DispatchSemaphore(value: 0)
    let startedAt = ContinuousClock.now
    let task = Task {
      try await InferenceCallerDeadlineRace.run(
        deadline: .milliseconds(40),
        onDeadline: {
          telemetryEntered.signal()
          _ = releaseTelemetry.wait(timeout: .now() + 1)
        }
      ) {
        operationProbe.value()
      }
    }
    await operationProbe.waitUntilStarted()
    defer {
      releaseTelemetry.signal()
      operationProbe.finish()
    }

    do {
      _ = try await task.value
      XCTFail("The deadline must still fail the caller while telemetry is blocked.")
    } catch {
      XCTAssertEqual(error as? InferenceCallerContainmentError, .timedOut)
    }
    XCTAssertLessThan(
      startedAt.duration(to: .now),
      .milliseconds(300),
      "Best-effort telemetry must run only after caller containment wins."
    )
    let didEnterTelemetry = await waitForTestSignal(telemetryEntered)
    XCTAssertTrue(didEnterTelemetry)
  }

  func testInferenceCallerCancellationReturnsWhenOperationIgnoresCancellation() async {
    let probe = NonCooperativeInferenceProbe()
    let task = Task {
      try await InferenceCallerDeadlineRace.run(deadline: .seconds(5)) {
        await probe.value()
      }
    }
    await probe.waitUntilStarted()
    defer { probe.finish() }
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Caller cancellation must release the caller even when inference ignores it.")
    } catch {
      XCTAssertEqual(error as? InferenceCallerContainmentError, .callerCancelled)
    }
    XCTAssertEqual(probe.cancellationCount, 1)
  }

  func testInferenceCallerDeadlinePassesThroughFastResult() async throws {
    let value = try await InferenceCallerDeadlineRace.run(deadline: .seconds(1)) { "complete" }
    XCTAssertEqual(value, "complete")
  }

  func testContainedCallCannotBeDiscardedOrReopenedBeforeQuarantine() throws {
    var gate = RuntimeCoordinatorGate()
    let token = try gate.acquire(
      descriptorID: "e4b",
      purpose: .structured(draftPath: "/synthetic/draft.jpg")
    )
    XCTAssertTrue(gate.beginContainedCall(token))

    // This is the cancellation interleaving: discard arrives after the caller
    // cancels but before the coordinator handles the contained-call result.
    XCTAssertFalse(gate.permitsRepairContextDiscard(token))
    XCTAssertThrowsError(try gate.acquire(descriptorID: "e4b", purpose: .transient))

    gate.quarantine(token)
    XCTAssertTrue(gate.hasLease)
    XCTAssertTrue(gate.hasQuarantinedOperation)
    XCTAssertTrue(gate.isQuarantined(token))
    XCTAssertFalse(gate.permitsRepairContextDiscard(token))
    gate.release(UUID())
    XCTAssertTrue(gate.hasQuarantinedOperation, "A stale completion must not reopen the quarantined engine.")
  }

  func testStructuredContainmentQuarantinesBeforePotentiallyBlockingTelemetry() async throws {
    var gate = RuntimeCoordinatorGate()
    let token = try gate.acquire(
      descriptorID: "e4b",
      purpose: .structured(draftPath: "/synthetic/draft.jpg")
    )
    XCTAssertTrue(gate.beginContainedCall(token))
    let telemetryEntered = DispatchSemaphore(value: 0)
    let releaseTelemetry = DispatchSemaphore(value: 0)
    let startedAt = ContinuousClock.now
    defer { releaseTelemetry.signal() }

    StructuredInferenceContainment.quarantine(
      gate: &gate,
      token: token,
      telemetry: {
        telemetryEntered.signal()
        _ = releaseTelemetry.wait(timeout: .now() + 1)
      }
    )

    XCTAssertLessThan(
      startedAt.duration(to: .now),
      .milliseconds(300),
      "Coordinator quarantine must complete without waiting for diagnostic output."
    )
    XCTAssertTrue(gate.isQuarantined(token))
    XCTAssertTrue(gate.hasQuarantinedOperation)
    let didEnterTelemetry = await waitForTestSignal(telemetryEntered)
    XCTAssertTrue(didEnterTelemetry)
  }

  func testEntryEditDraftRoundTripsCanonicalEditableValuesWithoutEvidencePayloads() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("EntryEdits", isDirectory: true)
    let entry = EntryRecord(input: input(note: "baseline"))
    let baseline = try EntryRecordFingerprint.make(for: entry)
    var edited = EntryEditInput(entry: entry)
    edited.note = "  unfinished person note  "
    edited.redBlood = .yes
    edited.blackTarry = .unsure
    edited.confirmedBristolType = 5
    edited.mixedForm = .yes
    let store = EntryEditDraftStore(
      directoryProvider: { directory },
      protectedDataIsAvailable: { true },
      writeGate: .unrestricted
    )

    try store.save(
      input: edited,
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      pendingSave: false
    )

    guard case .resumed(let snapshot) = store.resume(for: entry) else {
      return XCTFail("Expected exact unfinished-edit restoration")
    }
    XCTAssertEqual(snapshot.input, edited)
    XCTAssertEqual(snapshot.inputHash, try edited.canonicalSHA256())
    XCTAssertFalse(snapshot.pendingSave)
    let bytes = try Data(contentsOf: entryEditSnapshotURL(directory: directory, id: entry.id))
    let json = try XCTUnwrap(String(data: bytes, encoding: .utf8))
    for forbidden in [
      "imageFilename", "imageSHA256", "draftURL", "originalAIJSON",
      "reviewedJSON", "modelID", "modelProvenanceJSON",
    ] {
      XCTAssertFalse(json.contains(forbidden), "Edit snapshot must exclude \(forbidden)")
    }
  }

  func testEntryEditDraftMalformedAndWrongIDFailClosedWithoutDeletingFiles() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("EntryEdits", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let entry = EntryRecord(input: input(note: "saved"))
    let url = entryEditSnapshotURL(directory: directory, id: entry.id)
    let store = EntryEditDraftStore(
      directoryProvider: { directory },
      protectedDataIsAvailable: { true },
      writeGate: .unrestricted
    )

    try Data("not json".utf8).write(to: url, options: [.atomic, .completeFileProtection])
    guard case .unavailable = store.resume(for: entry) else {
      return XCTFail("Malformed edit draft must be unavailable")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

    let wrongID = UUID()
    let wrong = try EntryEditDraftSnapshot(
      entryID: wrongID,
      baselineRecordFingerprint: String(repeating: "a", count: 64),
      input: EntryEditInput(entry: entry),
      pendingSave: false
    )
    try JSONEncoder().encode(wrong).write(to: url, options: [.atomic, .completeFileProtection])
    guard case .unavailable = store.resume(for: entry) else {
      return XCTFail("A snapshot for another entry must never restore")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
  }

  func testEntryEditDraftPreSaveInterruptionRestoresAndClearsPendingMarker() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("EntryEdits", isDirectory: true)
    let context = ModelContext(try container())
    let entry = EntryRecord(input: input(note: "saved"))
    context.insert(entry)
    try context.save()
    let baseline = try EntryRecordFingerprint.make(for: entry)
    var edited = EntryEditInput(entry: entry)
    edited.note = "interrupted before database commit"
    let store = EntryEditDraftStore(
      directoryProvider: { directory },
      protectedDataIsAvailable: { true },
      writeGate: .unrestricted
    )
    let updateDate = Date(timeIntervalSince1970: 1_729_999_900)
    let repository = EntryStore(context: context, writeGate: .unrestricted)
    let expected = try repository.expectedUpdateFingerprint(
      for: entry,
      input: edited,
      baselineFingerprint: baseline,
      at: updateDate
    )
    try store.save(
      input: edited,
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      pendingSave: true,
      expectedPostSaveRecordFingerprint: expected
    )

    guard case .resumed(let restored) = store.resume(for: entry) else {
      return XCTFail("A baseline row proves the pending save did not commit")
    }
    XCTAssertEqual(restored.input, edited)
    XCTAssertFalse(restored.pendingSave)
    XCTAssertNil(restored.expectedPostSaveRecordFingerprint)
    let persisted = try JSONDecoder().decode(
      EntryEditDraftSnapshot.self,
      from: Data(contentsOf: entryEditSnapshotURL(directory: directory, id: entry.id))
    )
    XCTAssertFalse(persisted.pendingSave)
  }

  func testEntryEditDraftPostSaveInterruptionFinishesCleanupWithoutReapplying() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("EntryEdits", isDirectory: true)
    let context = ModelContext(try container())
    let entry = EntryRecord(input: input(note: "saved"))
    context.insert(entry)
    try context.save()
    let baseline = try EntryRecordFingerprint.make(for: entry)
    var edited = EntryEditInput(entry: entry)
    edited.note = "  committed edit  "
    edited.redBlood = .yes
    let editDrafts = EntryEditDraftStore(
      directoryProvider: { directory },
      protectedDataIsAvailable: { true },
      writeGate: .unrestricted
    )
    let repository = EntryStore(context: context, writeGate: .unrestricted)
    let updateDate = Date(timeIntervalSince1970: 1_730_000_000)
    let expected = try repository.expectedUpdateFingerprint(
      for: entry,
      input: edited,
      baselineFingerprint: baseline,
      at: updateDate
    )
    try editDrafts.save(
      input: edited,
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      pendingSave: true,
      expectedPostSaveRecordFingerprint: expected
    )
    try repository.update(
      entry,
      with: edited,
      baselineFingerprint: baseline,
      at: updateDate
    )

    XCTAssertEqual(try EntryRecordFingerprint.make(for: entry), expected)
    XCTAssertEqual(editDrafts.resume(for: entry), .committedCleanupFinished)
    XCTAssertEqual(entry.note, "committed edit")
    XCTAssertFalse(editDrafts.snapshotExists(entryID: entry.id))
  }

  func testEntryEditDraftPendingSaveConflictsWhenUnrelatedFullRowStateChanges() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("EntryEdits", isDirectory: true)
    let context = ModelContext(try container())
    let entry = EntryRecord(input: input(note: "saved"))
    context.insert(entry)
    try context.save()
    let baseline = try EntryRecordFingerprint.make(for: entry)
    var edited = EntryEditInput(entry: entry)
    edited.note = "same editable values after commit"
    let repository = EntryStore(context: context, writeGate: .unrestricted)
    let updateDate = Date(timeIntervalSince1970: 1_730_000_050)
    let expected = try repository.expectedUpdateFingerprint(
      for: entry,
      input: edited,
      baselineFingerprint: baseline,
      at: updateDate
    )
    let drafts = EntryEditDraftStore(
      directoryProvider: { directory },
      protectedDataIsAvailable: { true },
      writeGate: .unrestricted
    )
    try drafts.save(
      input: edited,
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      pendingSave: true,
      expectedPostSaveRecordFingerprint: expected
    )
    try repository.update(
      entry,
      with: edited,
      baselineFingerprint: baseline,
      at: updateDate
    )
    XCTAssertEqual(
      try EntryEditInput(entry: entry).canonicalSHA256(),
      try edited.canonicalSHA256(),
      "The editable fields intentionally still match the pending input"
    )
    entry.markedForDiscussionAt = Date(timeIntervalSince1970: 1_730_000_060)
    try context.save()

    guard case .conflict = drafts.resume(for: entry) else {
      return XCTFail("An unrelated full-row change must not be mistaken for the pending commit")
    }
    XCTAssertTrue(drafts.snapshotExists(entryID: entry.id))
    XCTAssertNotEqual(try EntryRecordFingerprint.make(for: entry), expected)
  }

  func testEntryEditorDismissPolicyBlocksLoadingConflictsAndCleanupFailures() {
    XCTAssertTrue(EntryEditorDismissPolicy.disablesInteractiveDismiss(
      persistenceReady: false,
      hasUnsavedEdit: false,
      persistenceBlocked: false,
      isSaving: false,
      saveCommittedCleanupPending: false
    ))
    XCTAssertTrue(EntryEditorDismissPolicy.disablesInteractiveDismiss(
      persistenceReady: true,
      hasUnsavedEdit: false,
      persistenceBlocked: true,
      isSaving: false,
      saveCommittedCleanupPending: false
    ))
    XCTAssertTrue(EntryEditorDismissPolicy.disablesInteractiveDismiss(
      persistenceReady: true,
      hasUnsavedEdit: false,
      persistenceBlocked: false,
      isSaving: false,
      saveCommittedCleanupPending: true
    ))
    XCTAssertFalse(EntryEditorDismissPolicy.disablesInteractiveDismiss(
      persistenceReady: true,
      hasUnsavedEdit: false,
      persistenceBlocked: false,
      isSaving: false,
      saveCommittedCleanupPending: false
    ))
  }

  func testConfirmedEntryPhotoUnusableEditAbstainsColorAndPreservesPersonRedBlack() throws {
    let original = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
    let fieldProvenance = Dictionary(
      uniqueKeysWithValues: ConfirmationField.allCases.map {
        ($0, FieldConfirmationProvenance.acceptedUnchanged)
      }
    )
    let confirmation = ConfirmedEntrySnapshotV1(
      confirmedAt: Date(timeIntervalSince1970: 1_720_000_000),
      personConfirmedPhotoUsable: true,
      personConfirmedBristolType: 4,
      personConfirmedMixedForm: .no,
      personConfirmedApparentColor: "brown",
      personConfirmedRed: .no,
      personConfirmedBlackTarry: .no,
      fieldProvenance: fieldProvenance
    )
    let entryID = UUID()
    let record = EntryRecord(input: EntryInput(
      id: entryID,
      capturedAt: Date(timeIntervalSince1970: 1_720_000_100),
      draftURL: URL(fileURLWithPath: "/synthetic/not-read.jpg"),
      imageSHA256: String(repeating: "a", count: 64),
      redBlood: .no,
      blackTarry: .no,
      dizziness: .no,
      severePain: .no,
      note: nil,
      painScore: 2,
      urgency: .moderate,
      confirmedBristolType: 4,
      confirmedPhotoUsable: true,
      mixedForm: .no,
      strainingOrIncomplete: .no,
      leakageOrAccident: nil,
      analysisSource: .gemmaRawImage,
      analysisPipelineVersion: "synthetic-edit-test",
      markedForDiscussionAt: nil,
      provenance: .ai_unedited,
      reviewedAt: Date(timeIntervalSince1970: 1_720_000_000),
      originalAIJSON: original,
      reviewedJSON: try XCTUnwrap(confirmation.canonicalJSON),
      modelID: "synthetic-model",
      modelProvenanceJSON: nil,
      demoKind: nil,
      imageFilename: "\(entryID.uuidString).jpg"
    ))
    let context = ModelContext(try container())
    context.insert(record)
    try context.save()
    let baseline = try EntryRecordFingerprint.make(for: record)
    var edited = EntryEditInput(entry: record)
    edited.confirmedPhotoUsable = false
    edited.apparentColor = "brown"
    edited.redBlood = .yes
    edited.blackTarry = .unsure
    let repository = EntryStore(context: context, writeGate: .unrestricted)
    try repository.update(
      record,
      with: edited,
      baselineFingerprint: baseline,
      at: Date(timeIntervalSince1970: 1_720_000_200)
    )

    let savedConfirmation = try XCTUnwrap(record.confirmedEntrySnapshot)
    XCTAssertFalse(try XCTUnwrap(savedConfirmation.personConfirmedPhotoUsable))
    XCTAssertEqual(savedConfirmation.personConfirmedApparentColor, "unable_to_assess")
    XCTAssertEqual(savedConfirmation.personConfirmedBristolType, 4)
    XCTAssertEqual(savedConfirmation.personConfirmedMixedForm, .no)
    XCTAssertEqual(savedConfirmation.personConfirmedRed, .yes)
    XCTAssertEqual(savedConfirmation.personConfirmedBlackTarry, .unsure)
    XCTAssertEqual(record.redBlood, SymptomFlag.yes.rawValue)
    XCTAssertEqual(record.blackTarry, SymptomFlag.unsure.rawValue)
    XCTAssertEqual(record.observation?.imageUsable, false)
    XCTAssertEqual(record.observation?.apparentColor, "unable_to_assess")
    XCTAssertEqual(record.observation?.form, "unable_to_assess")
    XCTAssertEqual(record.observation?.redAppearingMaterial, "unable_to_assess")
    XCTAssertEqual(record.observation?.blackTarryAppearance, "unable_to_assess")
  }

  func testLegacyAIEditRejectsMalformedAndFutureReviewedPayloadWithoutMutation() throws {
    let original = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
    let unsupportedPayloads = [
      "{",
      "{\"schemaVersion\":\"gi-confirmed-entry-v99\",\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}",
    ]
    for reviewed in unsupportedPayloads {
      let context = ModelContext(try container())
      let id = UUID()
      let record = EntryRecord(input: input(
        id: id,
        draftURL: URL(fileURLWithPath: "/synthetic/not-read.jpg"),
        hash: String(repeating: "b", count: 64),
        filename: "\(id.uuidString).jpg",
        note: "unchanged",
        originalAIJSON: original,
        reviewedJSON: reviewed
      ))
      record.provenance = EntryProvenance.ai_unedited.rawValue
      context.insert(record)
      try context.save()
      let baseline = try EntryRecordFingerprint.make(for: record)
      var edited = EntryEditInput(entry: record)
      edited.note = "must not persist"
      let repository = EntryStore(context: context, writeGate: .unrestricted)
      let updateDate = Date(timeIntervalSince1970: 1_750_000_000)

      XCTAssertThrowsError(try repository.expectedUpdateFingerprint(
        for: record,
        input: edited,
        baselineFingerprint: baseline,
        at: updateDate
      )) { error in
        XCTAssertEqual(error as? GITimelineError, .invalidEntryProvenance)
      }
      XCTAssertThrowsError(try repository.update(
        record,
        with: edited,
        baselineFingerprint: baseline,
        at: updateDate
      )) { error in
        XCTAssertEqual(error as? GITimelineError, .invalidEntryProvenance)
      }
      XCTAssertEqual(record.note, "unchanged")
      XCTAssertEqual(record.reviewedJSON, reviewed)
      XCTAssertEqual(try EntryRecordFingerprint.make(for: record), baseline)
    }
  }

  func testDiskBackedEditPendingProofReopensExactlyAcrossAllSupportedBranches() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("journal.store")
    let editDirectory = root.appendingPathComponent("EntryEdits", isDirectory: true)
    let editDrafts = EntryEditDraftStore(
      directoryProvider: { editDirectory },
      protectedDataIsAvailable: { true },
      writeGate: .unrestricted
    )
    let legacyObservation = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
    var expectedByID: [UUID: String] = [:]

    do {
      let context = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
      let manual = EntryRecord(input: input(note: "manual baseline"))

      let confirmed = EntryRecord(input: input(note: "confirmed baseline"))
      let confirmedAt = Date(timeIntervalSince1970: 1_751_000_000)
      let manualProvenance = Dictionary(
        uniqueKeysWithValues: ConfirmationField.allCases.map {
          ($0, FieldConfirmationProvenance.manualNoSuggestion)
        }
      )
      let envelope = ConfirmedEntrySnapshotV1(
        confirmedAt: confirmedAt,
        personConfirmedPhotoUsable: nil,
        personConfirmedBristolType: 4,
        personConfirmedMixedForm: .no,
        personConfirmedApparentColor: nil,
        personConfirmedRed: .unsure,
        personConfirmedBlackTarry: .no,
        fieldProvenance: manualProvenance
      )
      confirmed.reviewedAt = confirmedAt
      confirmed.reviewedJSON = try XCTUnwrap(envelope.canonicalJSON)

      let legacyID = UUID()
      let legacy = EntryRecord(input: input(
        id: legacyID,
        draftURL: URL(fileURLWithPath: "/synthetic/not-read.jpg"),
        hash: String(repeating: "c", count: 64),
        filename: "\(legacyID.uuidString).jpg",
        note: "legacy baseline",
        originalAIJSON: legacyObservation,
        reviewedJSON: legacyObservation
      ))
      legacy.analysisSource = AnalysisSource.gemmaRawImage.rawValue
      legacy.analysisPipelineVersion = "legacy-observation-v1"
      legacy.provenance = EntryProvenance.ai_unedited.rawValue
      legacy.reviewedAt = Date(timeIntervalSince1970: 1_751_000_010)

      let records = [manual, confirmed, legacy]
      records.forEach(context.insert)
      try context.save()
      let repository = EntryStore(context: context, writeGate: .unrestricted)
      for (index, record) in records.enumerated() {
        let baseline = try EntryRecordFingerprint.make(for: record)
        var edited = EntryEditInput(entry: record)
        edited.note = "committed branch \(index)"
        let updateDate = Date(timeIntervalSince1970: 1_751_000_100 + Double(index))
        let expected = try repository.expectedUpdateFingerprint(
          for: record,
          input: edited,
          baselineFingerprint: baseline,
          at: updateDate
        )
        try editDrafts.save(
          input: edited,
          entryID: record.id,
          baselineRecordFingerprint: baseline,
          pendingSave: true,
          expectedPostSaveRecordFingerprint: expected
        )
        try repository.update(
          record,
          with: edited,
          baselineFingerprint: baseline,
          at: updateDate
        )
        XCTAssertEqual(try EntryRecordFingerprint.make(for: record), expected)
        if index == 1 {
          let preservedLegacyEnvelope = try XCTUnwrap(record.confirmedEntrySnapshot)
          XCTAssertNil(preservedLegacyEnvelope.personConfirmedStoolPresence)
          XCTAssertNil(preservedLegacyEnvelope.personConfirmedForm)
        }
        expectedByID[record.id] = expected
      }
    }

    do {
      let reopenedContext = ModelContext(try PersistenceSchema.openPublicStore(at: storeURL))
      let reopened = try reopenedContext.fetch(FetchDescriptor<EntryRecord>())
      XCTAssertEqual(reopened.count, 3)
      for record in reopened {
        XCTAssertEqual(
          try EntryRecordFingerprint.make(for: record),
          try XCTUnwrap(expectedByID[record.id])
        )
        XCTAssertEqual(editDrafts.resume(for: record), .committedCleanupFinished)
        XCTAssertFalse(editDrafts.snapshotExists(entryID: record.id))
      }
    }
  }

  func testEntryEditDraftSnapshotRejectsUnsupportedVersionAndProofPairMismatch() throws {
    let entry = EntryRecord(input: input(note: "baseline"))
    let baseline = try EntryRecordFingerprint.make(for: entry)
    let edit = EntryEditInput(entry: entry)
    let proof = String(repeating: "d", count: 64)

    XCTAssertThrowsError(try EntryEditDraftSnapshot(
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      input: edit,
      pendingSave: true
    )) { error in
      XCTAssertEqual(error as? EntryEditDraftError, .invalidContents)
    }
    XCTAssertThrowsError(try EntryEditDraftSnapshot(
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      input: edit,
      pendingSave: false,
      expectedPostSaveRecordFingerprint: proof
    )) { error in
      XCTAssertEqual(error as? EntryEditDraftError, .invalidContents)
    }

    let valid = try EntryEditDraftSnapshot(
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      input: edit,
      pendingSave: true,
      expectedPostSaveRecordFingerprint: proof
    )
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
    )
    object["version"] = 99
    let unsupported = try JSONDecoder().decode(
      EntryEditDraftSnapshot.self,
      from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
    XCTAssertThrowsError(try unsupported.validate(expectedEntryID: entry.id)) { error in
      XCTAssertEqual(error as? EntryEditDraftError, .invalidContents)
    }

    object["version"] = 1
    let legacyPending = try JSONDecoder().decode(
      EntryEditDraftSnapshot.self,
      from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
    XCTAssertThrowsError(try legacyPending.validate(expectedEntryID: entry.id)) { error in
      XCTAssertEqual(error as? EntryEditDraftError, .invalidContents)
    }

    let nonpending = try EntryEditDraftSnapshot(
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      input: edit,
      pendingSave: false
    )
    var legacyObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(nonpending)) as? [String: Any]
    )
    legacyObject["version"] = 1
    legacyObject["inputHash"] = try edit.legacyCanonicalSHA256WithoutRetakeReason()
    var legacyInput = try XCTUnwrap(legacyObject["input"] as? [String: Any])
    legacyInput.removeValue(forKey: "blackAppearance")
    legacyInput.removeValue(forKey: "retakeReason")
    legacyInput.removeValue(forKey: "stoolPresence")
    legacyInput.removeValue(forKey: "form")
    legacyObject["input"] = legacyInput
    let legacyNonpending = try JSONDecoder().decode(
      EntryEditDraftSnapshot.self,
      from: JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])
    )
    XCTAssertNoThrow(try legacyNonpending.validate(expectedEntryID: entry.id))
  }

  func testEntryEditDraftConflictNeverOverwritesOrDeletesOlderDraft() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("EntryEdits", isDirectory: true)
    let context = ModelContext(try container())
    let entry = EntryRecord(input: input(note: "saved"))
    context.insert(entry)
    try context.save()
    let baseline = try EntryRecordFingerprint.make(for: entry)
    var edited = EntryEditInput(entry: entry)
    edited.note = "older unfinished edit"
    let store = EntryEditDraftStore(
      directoryProvider: { directory },
      protectedDataIsAvailable: { true },
      writeGate: .unrestricted
    )
    try store.save(
      input: edited,
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      pendingSave: false
    )
    entry.markedForDiscussionAt = Date(timeIntervalSince1970: 1_740_000_000)
    try context.save()

    guard case .conflict = store.resume(for: entry) else {
      return XCTFail("A full-record mismatch must fail closed")
    }
    XCTAssertThrowsError(
      try EntryStore(context: context, writeGate: .unrestricted).update(
        entry,
        with: edited,
        baselineFingerprint: baseline,
        at: Date(timeIntervalSince1970: 1_740_000_100)
      )
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .entryTransactionConflict)
    }
    XCTAssertEqual(entry.note, "saved")
    XCTAssertTrue(store.snapshotExists(entryID: entry.id))
  }

  func testEntryEditDraftProtectedDataUnavailableKeepsSnapshotUntouched() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("EntryEdits", isDirectory: true)
    let entry = EntryRecord(input: input(note: "saved"))
    let available = EntryEditDraftStore(
      directoryProvider: { directory },
      protectedDataIsAvailable: { true },
      writeGate: .unrestricted
    )
    try available.save(
      input: EntryEditInput(entry: entry),
      entryID: entry.id,
      baselineRecordFingerprint: try EntryRecordFingerprint.make(for: entry),
      pendingSave: false
    )
    let protected = EntryEditDraftStore(
      directoryProvider: { directory },
      protectedDataIsAvailable: { false },
      writeGate: .unrestricted
    )

    guard case .temporarilyUnavailable = protected.resume(for: entry) else {
      return XCTFail("Locked protected data must be retryable")
    }
    XCTAssertFalse(protected.remove(entryID: entry.id))
    XCTAssertTrue(available.snapshotExists(entryID: entry.id))
  }

  func testEntryEditDraftCommittedCleanupFailureKeepsIdempotentMarker() throws {
    let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("EntryEdits", isDirectory: true)
    let context = ModelContext(try container())
    let entry = EntryRecord(input: input(note: "saved"))
    context.insert(entry)
    try context.save()
    let baseline = try EntryRecordFingerprint.make(for: entry)
    var edited = EntryEditInput(entry: entry)
    edited.note = "saved despite cleanup interruption"
    let writer = EntryEditDraftStore(
      directoryProvider: { directory },
      protectedDataIsAvailable: { true },
      writeGate: .unrestricted
    )
    let repository = EntryStore(context: context, writeGate: .unrestricted)
    let updateDate = Date(timeIntervalSince1970: 1_730_000_100)
    let expected = try repository.expectedUpdateFingerprint(
      for: entry,
      input: edited,
      baselineFingerprint: baseline,
      at: updateDate
    )
    try writer.save(
      input: edited,
      entryID: entry.id,
      baselineRecordFingerprint: baseline,
      pendingSave: true,
      expectedPostSaveRecordFingerprint: expected
    )
    try repository.update(
      entry,
      with: edited,
      baselineFingerprint: baseline,
      at: updateDate
    )
    let cleanupFails = EntryEditDraftStore(
      directoryProvider: { directory },
      protectedDataIsAvailable: { true },
      itemRemover: { _ in throw CocoaError(.fileWriteUnknown) },
      writeGate: .unrestricted
    )

    guard case .committedCleanupPending = cleanupFails.resume(for: entry) else {
      return XCTFail("A committed row must not be restored when cleanup fails")
    }
    XCTAssertEqual(entry.note, edited.note)
    XCTAssertTrue(writer.snapshotExists(entryID: entry.id))
    var didDismiss = false
    XCTAssertFalse(
      cleanupFails.removeBeforeDismiss(entryID: entry.id) { didDismiss = true }
    )
    XCTAssertFalse(didDismiss, "Cancel/Close must keep the editor presented when cleanup fails")
  }

  private func entryEditSnapshotURL(directory: URL, id: UUID) -> URL {
    directory.appendingPathComponent("\(id.uuidString.lowercased()).v1.json")
  }

  func testZRendersRepresentativeSyntheticPDFWithEverySelectedPhoto() throws {
    var calendar = Calendar(identifier: .gregorian)
    let zone = TimeZone(identifier: "America/New_York")!
    calendar.timeZone = zone
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
    let through = calendar.date(byAdding: .day, value: 2, to: start)!
    let photoRoot = temporaryRoot(); defer { try? FileManager.default.removeItem(at: photoRoot) }
    let firstID = UUID()
    let firstFixtureSize = CGSize(width: 61, height: 43)
    let firstPhoto = try writeSanitizedJournalPhoto(
      to: photoRoot,
      id: firstID,
      color: .systemGreen,
      size: firstFixtureSize
    )
    let thirdID = UUID()
    let thirdFixtureSize = CGSize(width: 73, height: 47)
    let thirdPhoto = try writeSanitizedJournalPhoto(
      to: photoRoot,
      id: thirdID,
      color: .brown,
      size: thirdFixtureSize
    )
    let longNote = "Synthetic pagination note. " + (0..<360).map { "detail\($0)" }.joined(separator: " ") + " END OF SYNTHETIC NOTE"
    let entries = [
      JournalExportEntry(
        id: firstID, capturedAt: start.addingTimeInterval(9 * 3_600), confirmedBristolType: 2,
        mixedForm: .yes, painScore: 5, urgency: .severe, strainingOrIncomplete: .yes,
        redBlood: .unsure, blackTarry: .no, dizziness: .no, severeOrWorseningPain: .no,
        note: "Synthetic marked entry with an available non-health fixture image.", markedForDiscussionAt: start,
        photoState: .available(filename: firstPhoto.filename),
        photoSHA256: firstPhoto.hash,
        suggestedVisual: JournalSuggestedVisual(
          stoolPresence: .stool,
          retakeReason: .tooDark,
          bristolType: 2,
          form: "hard_lumps",
          mixedForm: .yes,
          apparentColor: "brown",
          redAppearance: .yes,
          blackTarryAppearance: .unsure
        ),
        confirmedPhotoUsable: false,
        initiallyAcceptedPhotoUsable: false,
        initiallyAcceptedRetakeReason: .glare,
        initiallyAcceptedStoolPresence: .uncertain,
        initiallyAcceptedBristolType: nil,
        initiallyAcceptedForm: "unable_to_assess",
        initiallyAcceptedMixedForm: .unsure,
        initiallyAcceptedApparentColor: "unable_to_assess",
        initiallyAcceptedRed: .unsure,
        initiallyAcceptedBlackTarry: .no,
        confirmedRetakeReason: .blurred,
        personConfirmedSubject: true,
        confirmedStoolPresence: .uncertain,
        confirmedForm: "unable_to_assess",
        confirmedApparentColor: "unable_to_assess",
        fieldProvenance: [
          .photoUsable: .editedAfterConfirmation,
          .retakeReason: .editedAfterConfirmation,
          .stoolPresence: .acceptedUnchanged,
          .bristolType: .acceptedUnchanged,
          .form: .acceptedUnchanged,
          .mixedForm: .acceptedUnchanged,
          .apparentColor: .acceptedUnchanged,
          .redMaterial: .acceptedUnchanged,
          .blackTarry: .acceptedUnchanged,
        ]
      ),
      JournalExportEntry(
        id: UUID(), capturedAt: calendar.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(12 * 3_600),
        confirmedBristolType: 6, mixedForm: .no, painScore: 1, urgency: .moderate,
        leakageOrAccident: .no, redBlood: .no, blackTarry: .no, dizziness: nil,
        severeOrWorseningPain: .no, note: nil, photoState: .noPhoto
      ),
      JournalExportEntry(
        id: thirdID, capturedAt: through.addingTimeInterval(14 * 3_600), confirmedBristolType: nil,
        mixedForm: .unsure, painScore: 7, urgency: .severe, redBlood: nil, blackTarry: nil,
        dizziness: .yes, severeOrWorseningPain: .yes, note: longNote, markedForDiscussionAt: through,
        photoState: .available(filename: thirdPhoto.filename),
        photoSHA256: thirdPhoto.hash
      )
    ]
    let snapshot = try JournalExportBuilder(calendar: calendar, timeZone: zone).build(
      range: .init(from: start, through: through),
      scope: .allEntries,
      entries: entries,
      completions: [.init(day: start, answer: .yes), .init(day: through, answer: .no)],
      treatmentMarkers: [],
      generatedAt: through.addingTimeInterval(17 * 3_600)
    )
    let data = try JournalPDFRenderer().render(snapshot: snapshot, photoDirectory: photoRoot)
    let document = try XCTUnwrap(PDFDocument(data: data))
    XCTAssertGreaterThan(document.pageCount, 2)
    for pageIndex in 0..<document.pageCount {
      XCTAssertTrue(
        try XCTUnwrap(document.page(at: pageIndex)?.string).contains("Page \(pageIndex + 1)"),
        "Page \(pageIndex + 1) must include its searchable page number."
      )
    }
    let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    let normalizedText = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    XCTAssertTrue(normalizedText.contains("END OF SYNTHETIC NOTE"))
    XCTAssertTrue(text.contains("No photo attached"))
    XCTAssertTrue(text.contains("On-device suggestion — possible red appearance"))
    XCTAssertTrue(text.contains("On-device suggestion — retake recommendation: Too dark"))
    XCTAssertTrue(text.contains("Your answer — photo clearly showed the bowel movement: Yes"))
    XCTAssertTrue(text.contains("Accepted value — possible red/blood-like appearance: Not sure"))
    XCTAssertTrue(text.contains("Accepted value — possible black/tar-like appearance: No"))
    XCTAssertTrue(text.contains("Accepted value — retake recommendation: Glare"))
    XCTAssertTrue(text.contains("Final value — retake recommendation: Blurred"))
    XCTAssertTrue(
      normalizedText.contains("retake recommendation: Edited after confirmation")
    )
    // The third, legacy/manual photo entry intentionally has no accepted model
    // values; the first full-prefill entry above must still render its concrete
    // accepted red and black values rather than inheriting that legacy absence.
    XCTAssertEqual(text.components(separatedBy: "Photo included").count - 1, 2)
    XCTAssertFalse(text.contains("Photo unavailable"))
    XCTAssertNil(data.range(of: firstPhoto.bytes))
    XCTAssertNil(data.range(of: thirdPhoto.bytes))
    let fixtureSizes: Set<CGSize> = [firstFixtureSize, thirdFixtureSize]
    let embeddedFixtureSizes = try embeddedPDFImages(in: data)
      .filter { !$0.isImageMask }
      .map(\.pixelSize)
      .filter(fixtureSizes.contains)
      .sorted { ($0.width, $0.height) < ($1.width, $1.height) }
    XCTAssertEqual(
      embeddedFixtureSizes,
      [firstFixtureSize, thirdFixtureSize],
      "Every selected journal photo must be embedded exactly once as a PDF image object."
    )
  }

  func testMarkedOnlyPDFRendersEverySelectedPhotoAndExcludesUnselectedPhoto() throws {
    let day = Date(timeIntervalSince1970: 1_710_000_000)
    let photoRoot = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: photoRoot) }
    let firstID = UUID()
    let firstPhoto = try writeSanitizedJournalPhoto(
      to: photoRoot,
      id: firstID,
      color: .systemGreen,
      size: CGSize(width: 61, height: 43)
    )
    let secondID = UUID()
    let secondPhoto = try writeSanitizedJournalPhoto(
      to: photoRoot,
      id: secondID,
      color: .brown,
      size: CGSize(width: 73, height: 47)
    )
    let unselectedID = UUID()
    let unselectedPhoto = try writeSanitizedJournalPhoto(
      to: photoRoot,
      id: unselectedID,
      color: .systemBlue,
      size: CGSize(width: 89, height: 53)
    )
    let entries = [
      JournalExportEntry(
        id: firstID,
        capturedAt: day,
        confirmedBristolType: 4,
        note: "Selected marked photo one",
        markedForDiscussionAt: day,
        photoState: .available(filename: firstPhoto.filename),
        photoSHA256: firstPhoto.hash
      ),
      JournalExportEntry(
        id: secondID,
        capturedAt: day.addingTimeInterval(60),
        confirmedBristolType: 5,
        note: "Selected marked photo two",
        markedForDiscussionAt: day,
        photoState: .available(filename: secondPhoto.filename),
        photoSHA256: secondPhoto.hash
      ),
      JournalExportEntry(
        id: unselectedID,
        capturedAt: day.addingTimeInterval(120),
        confirmedBristolType: 6,
        note: "Unselected photo must not appear",
        photoState: .available(filename: unselectedPhoto.filename),
        photoSHA256: unselectedPhoto.hash
      ),
    ]
    let snapshot = try JournalExportBuilder().build(
      range: .init(from: day, through: day),
      scope: .markedForDiscussion,
      entries: entries,
      completions: [],
      treatmentMarkers: [],
      generatedAt: day.addingTimeInterval(180)
    )
    XCTAssertEqual(snapshot.entries.map(\.id), [firstID, secondID])

    let data = try JournalPDFRenderer().render(
      snapshot: snapshot,
      photoDirectory: photoRoot
    )
    let document = try XCTUnwrap(PDFDocument(data: data))
    let text = (0..<document.pageCount)
      .compactMap { document.page(at: $0)?.string }
      .joined(separator: "\n")
    XCTAssertEqual(text.components(separatedBy: "Photo included").count - 1, 2)
    XCTAssertTrue(text.contains("Selected marked photo one"))
    XCTAssertTrue(text.contains("Selected marked photo two"))
    XCTAssertFalse(text.contains("Unselected photo must not appear"))
    XCTAssertNil(data.range(of: firstPhoto.bytes))
    XCTAssertNil(data.range(of: secondPhoto.bytes))
    XCTAssertNil(data.range(of: unselectedPhoto.bytes))
    let selectedFixtureSizes = [
      CGSize(width: 61, height: 43),
      CGSize(width: 73, height: 47),
    ]
    let allFixtureSizes = Set(selectedFixtureSizes + [CGSize(width: 89, height: 53)])
    let embeddedFixtureSizes = try embeddedPDFImages(in: data)
      .filter { !$0.isImageMask }
      .map(\.pixelSize)
      .filter(allFixtureSizes.contains)
      .sorted { ($0.width, $0.height) < ($1.width, $1.height) }
    XCTAssertEqual(
      embeddedFixtureSizes,
      selectedFixtureSizes,
      "Both selected photos must be embedded exactly once and the uniquely sized unselected photo must be absent."
    )
    XCTAssertFalse(embeddedFixtureSizes.contains(CGSize(width: 89, height: 53)))
  }
}

/// Deliberately records cancellation without resuming its operation. This
/// models a native worker that accepts Task.cancel() but never unwinds until an
/// external event releases it.
private final class NonCooperativeInferenceProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var valueContinuation: CheckedContinuation<String, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var storedHasStarted = false
  private var storedCancellationCount = 0

  var cancellationCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedCancellationCount
  }

  var hasStarted: Bool {
    lock.lock()
    defer { lock.unlock() }
    return storedHasStarted
  }

  func value() async -> String {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        lock.lock()
        valueContinuation = continuation
        storedHasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume() }
      }
    } onCancel: {
      lock.lock()
      storedCancellationCount += 1
      lock.unlock()
    }
  }

  func waitUntilStarted() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if storedHasStarted {
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

/// Models LiteRT's synchronous conversation creation: the operation occupies a
/// cooperative-executor thread and ignores Task cancellation until an external
/// event releases the underlying native-shaped wait.
private final class SynchronousBlockingInferenceProbe: @unchecked Sendable {
  private let started = DispatchSemaphore(value: 0)
  private let release = DispatchSemaphore(value: 0)
  private let deadlineThreadStarted = DispatchSemaphore(value: 0)
  private let deadlineFired = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var storedDeadlineThreadStartedCount = 0
  private var storedDeadlineFiredCount = 0

  var deadlineThreadStartedCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedDeadlineThreadStartedCount
  }

  var deadlineFiredCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return storedDeadlineFiredCount
  }

  func value() -> String {
    started.signal()
    release.wait()
    return "late"
  }

  func waitUntilStarted() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        self.started.wait()
        continuation.resume()
      }
    }
  }

  func recordDeadlineFired() {
    lock.lock()
    storedDeadlineFiredCount += 1
    lock.unlock()
    deadlineFired.signal()
  }

  func recordDeadlineThreadStarted() {
    lock.lock()
    storedDeadlineThreadStartedCount += 1
    lock.unlock()
    deadlineThreadStarted.signal()
  }

  func waitUntilDeadlineThreadStarted() async -> Bool {
    await waitForTestSignal(deadlineThreadStarted)
  }

  func waitUntilDeadlineFired() async -> Bool {
    await waitForTestSignal(deadlineFired)
  }

  func finish() { release.signal() }
}

private final class DeadlineThreadStageProbe: @unchecked Sendable {
  private let lock = NSLock()
  private let continuationResumeReturned = DispatchSemaphore(value: 0)
  private var storedStages: [InferenceDeadlineThreadStage] = []

  var stages: [InferenceDeadlineThreadStage] {
    lock.lock()
    defer { lock.unlock() }
    return storedStages
  }

  func record(_ stage: InferenceDeadlineThreadStage) {
    lock.lock()
    storedStages.append(stage)
    lock.unlock()
    if stage == .continuationResumeReturned {
      continuationResumeReturned.signal()
    }
  }

  func waitUntilContinuationResumeReturned() async -> Bool {
    await waitForTestSignal(continuationResumeReturned)
  }
}

/// Test-only bridge: the test actor must not synchronously block while a
/// utility-priority worker publishes containment telemetry. The production
/// containment path remains deliberately asynchronous and unchanged.
private func waitForTestSignal(_ semaphore: DispatchSemaphore) async -> Bool {
  await withCheckedContinuation { continuation in
    DispatchQueue.global(qos: .utility).async {
      continuation.resume(returning: semaphore.wait(timeout: .now() + 1) == .success)
    }
  }
}

private final class BlockingPDFRenderProbe: @unchecked Sendable {
  private let started = DispatchSemaphore(value: 0)
  private let release = DispatchSemaphore(value: 0)

  func render() throws -> Data {
    started.signal()
    release.wait()
    return Data("%PDF-1.7 deterministic test".utf8)
  }

  func waitUntilStarted() -> Bool {
    started.wait(timeout: .now() + 3) == .success
  }

  func finish() {
    release.signal()
  }
}
