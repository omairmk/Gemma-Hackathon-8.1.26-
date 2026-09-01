import CryptoKit
import SwiftData
import XCTest
@testable import GITimeline

final class LegacyPredecessorStoreTests: XCTestCase {
  private static let provenanceCommit = "8eb4722f4055f8e2912cb20192c695deb067d8a3"
  private static let manifestSHA256 = "aa33f7ef6afc7cdac0963c83c660dab91320d39b16a4daf970cceeaa9c659507"
  private static let generatorSourceSHA256 = "6cccea8aebc5afa6faa3e6ef0c486b4911aa10e131b6bdc8566c1c94d06dc7e7"
  private static let artifactKind = "synthetic_predecessor_schema_shaped"
  private static let artifactNotice = "Synthetic predecessor-schema-shaped SwiftData fixture generated now with the recorded current toolchain; it is not a store or binary produced by the predecessor commit or toolchain."
  private static let scopeNotice = "Schema and persisted-row compatibility only; this fixture contains no photo bytes and makes no photo-durability claim. Separate tests cover photo storage and relaunch."

  private struct GenerationEnvironment: Decodable, Equatable {
    let xcodeVersion: String
    let xcodeBuildVersion: String
    let swiftCompilerVersion: String
    let swiftTarget: String
    let macOSProductVersion: String
    let macOSBuildVersion: String
    let systemSQLiteVersion: String
  }

  private struct Manifest: Decodable {
    struct FileHash: Decodable {
      let name: String
      let sha256: String
      let bytes: Int
    }

    let fixtureVersion: Int
    let artifactKind: String
    let artifactNotice: String
    let scopeNotice: String
    let provenanceCommit: String
    let sourceBlobs: [String: String]
    let generatorModuleName: String
    let generatorSourceSHA256: String
    let generationEnvironment: GenerationEnvironment
    let files: [FileHash]
    let expectedValues: [String: String]
  }

  private func sha256(_ url: URL) throws -> String {
    let digest = SHA256.hash(data: try Data(contentsOf: url))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private func fixtureURL(named name: String) throws -> URL {
    try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: name, withExtension: nil),
      "Missing test-only predecessor fixture resource: \(name)"
    )
  }

  private func manifest() throws -> Manifest {
    let url = try fixtureURL(named: "legacy-predecessor-store-manifest.json")
    XCTAssertEqual(
      try sha256(url),
      Self.manifestSHA256,
      "The committed predecessor fixture identity changed without an explicit test review."
    )
    return try JSONDecoder().decode(
      Manifest.self,
      from: Data(contentsOf: url)
    )
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("LegacyPredecessorStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func expectedDate(_ key: String, in expected: [String: String]) throws -> Date {
    Date(timeIntervalSince1970: try XCTUnwrap(Double(try XCTUnwrap(expected[key]))))
  }

  private func verifyFixtureHashes(_ manifest: Manifest, at directory: URL? = nil) throws {
    for file in manifest.files {
      let url: URL
      if let directory {
        url = directory.appendingPathComponent(file.name)
      } else {
        url = try fixtureURL(named: file.name)
      }
      XCTAssertEqual(try sha256(url), file.sha256, "Hash mismatch for \(file.name)")
      XCTAssertEqual(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, file.bytes, "Size mismatch for \(file.name)")
    }
  }

  private func assertSyntheticValues(
    _ expected: [String: String],
    in context: ModelContext,
    reconciledMissingPhoto: Bool = false
  ) throws {
    let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).only)
    XCTAssertEqual(entry.id.uuidString, expected["entryID"])
    XCTAssertEqual(entry.capturedAt, try expectedDate("entryCapturedAt", in: expected))
    XCTAssertEqual(entry.imageFilename, expected["entryImageFilename"])
    XCTAssertEqual(entry.imageSHA256, expected["entryImageSHA256"])
    XCTAssertEqual(entry.redBlood, expected["entryRedBlood"])
    XCTAssertEqual(entry.blackTarry, expected["entryBlackTarry"])
    XCTAssertEqual(entry.dizziness, expected["entryDizziness"])
    XCTAssertEqual(entry.severePain, expected["entrySeverePain"])
    XCTAssertEqual(entry.note, expected["entryNote"])
    XCTAssertEqual(entry.painScore, Int(expected["entryPainScore"]!))
    XCTAssertEqual(entry.urgency, expected["entryUrgency"])
    XCTAssertEqual(entry.bm24h, Int(expected["entryBM24H"]!))
    XCTAssertEqual(entry.confirmedBristolType, Int(expected["entryConfirmedBristolType"]!))
    XCTAssertEqual(entry.confirmedPhotoUsable, Bool(expected["entryConfirmedPhotoUsable"]!))
    XCTAssertEqual(entry.mixedForm, expected["entryMixedForm"])
    XCTAssertEqual(entry.strainingOrIncomplete, expected["entryStrainingOrIncomplete"])
    XCTAssertEqual(entry.leakageOrAccident, expected["entryLeakageOrAccident"])
    XCTAssertEqual(entry.analysisSource, expected["entryAnalysisSource"])
    XCTAssertEqual(entry.analysisPipelineVersion, expected["entryAnalysisPipelineVersion"])
    XCTAssertEqual(entry.markedForDiscussionAt, try expectedDate("entryMarkedForDiscussionAt", in: expected))
    XCTAssertEqual(entry.provenance, expected["entryProvenance"])
    XCTAssertEqual(entry.reviewedAt, try expectedDate("entryReviewedAt", in: expected))
    XCTAssertEqual(entry.originalAIJSON, expected["entryOriginalAIJSON"])
    XCTAssertEqual(entry.reviewedJSON, expected["entryReviewedJSON"])
    XCTAssertEqual(entry.modelID, expected["entryModelID"])
    XCTAssertEqual(entry.modelProvenanceJSON, expected["entryModelProvenanceJSON"])
    XCTAssertEqual(entry.demoKind, expected["entryDemoKind"])
    if reconciledMissingPhoto {
      XCTAssertTrue(
        entry.imageUnavailable,
        "The full app bootstrap must retain a predecessor row while explicitly marking its intentionally absent photo unavailable."
      )
    } else {
      XCTAssertEqual(entry.imageUnavailable, Bool(expected["entryImageUnavailable"]!))
    }
    XCTAssertEqual(entry.createdAt, try expectedDate("entryCreatedAt", in: expected))
    if reconciledMissingPhoto {
      XCTAssertGreaterThanOrEqual(
        entry.updatedAt,
        try expectedDate("entryUpdatedAt", in: expected),
        "Missing-photo reconciliation may advance updatedAt but must never move it backward."
      )
    } else {
      XCTAssertEqual(entry.updatedAt, try expectedDate("entryUpdatedAt", in: expected))
    }

    let completion = try XCTUnwrap(try context.fetch(FetchDescriptor<DailyCompletionRecord>()).only)
    XCTAssertEqual(completion.dayKey, expected["dailyCompletionDayKey"])
    XCTAssertEqual(completion.dayStart, try expectedDate("dailyCompletionDayStart", in: expected))
    XCTAssertEqual(completion.answerRawValue, expected["dailyCompletionAnswer"])
    XCTAssertEqual(completion.createdAt, try expectedDate("dailyCompletionCreatedAt", in: expected))
    XCTAssertEqual(completion.updatedAt, try expectedDate("dailyCompletionUpdatedAt", in: expected))

    let treatment = try XCTUnwrap(try context.fetch(FetchDescriptor<TreatmentEventRecord>()).only)
    XCTAssertEqual(treatment.id.uuidString, expected["treatmentID"])
    XCTAssertEqual(treatment.effectiveDate, try expectedDate("treatmentEffectiveDate", in: expected))
    XCTAssertEqual(treatment.kindRawValue, expected["treatmentKind"])
    XCTAssertEqual(treatment.name, expected["treatmentName"])
    XCTAssertEqual(treatment.doseOrNote, expected["treatmentDoseOrNote"])
    XCTAssertEqual(treatment.createdAt, try expectedDate("treatmentCreatedAt", in: expected))
    XCTAssertEqual(treatment.updatedAt, try expectedDate("treatmentUpdatedAt", in: expected))
  }

  private func openAndAssertCopy(_ storeURL: URL, manifest: Manifest) throws {
    let result = PersistenceBootstrap.open(publicStoreURL: storeURL)
    XCTAssertTrue(result.permitsJournalPresentation)
    let context = ModelContext(try XCTUnwrap(result.modelContainer))
    try assertSyntheticValues(manifest.expectedValues, in: context)
  }

  func testImmutablePredecessorStoreOpensAndColdReopensThroughCurrentBootstrap() throws {
    let manifest = try manifest()
    XCTAssertEqual(manifest.fixtureVersion, 2)
    XCTAssertEqual(manifest.artifactKind, Self.artifactKind)
    XCTAssertEqual(manifest.artifactNotice, Self.artifactNotice)
    XCTAssertEqual(manifest.scopeNotice, Self.scopeNotice)
    XCTAssertEqual(manifest.provenanceCommit, Self.provenanceCommit)
    XCTAssertEqual(
      manifest.sourceBlobs,
      [
        "gi-timeline/GITimeline/EntryRecord.swift": "2cb0db60f3fa64d7403b14bc3ef76bfb7f60de03",
        "gi-timeline/GITimeline/ClinicalTimelineRecords.swift": "2fc1691723eb6fdcd8e46ae9caf79ed3cfd7ca00",
        "gi-timeline/GITimeline/GITimelineApp.swift": "67ad9ae22172d26f813612125154544bfee64ff4"
      ]
    )
    XCTAssertEqual(manifest.generatorModuleName, "GITimeline")
    XCTAssertEqual(manifest.generatorSourceSHA256, Self.generatorSourceSHA256)
    XCTAssertEqual(
      manifest.generationEnvironment,
      GenerationEnvironment(
        xcodeVersion: "26.6",
        xcodeBuildVersion: "17F113",
        swiftCompilerVersion: "Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)",
        swiftTarget: "arm64-apple-macosx26.0",
        macOSProductVersion: "26.6",
        macOSBuildVersion: "25G72",
        systemSQLiteVersion: "3.51.0"
      )
    )
    XCTAssertEqual(Set(manifest.files.map(\.name)), ["legacy-predecessor.store", "legacy-predecessor.store-shm", "legacy-predecessor.store-wal"])
    XCTAssertEqual(manifest.expectedValues.count, 42)

    // This is intentionally a schema/row fixture, not a photo fixture. Separate
    // persistence tests own real photo-byte, reconciliation, and relaunch proof.
    XCTAssertFalse(manifest.files.contains { $0.name.hasSuffix(".jpg") })

    // Fixture resources belong only to the unit-test bundle, never the app.
    for file in manifest.files {
      XCTAssertNil(Bundle.main.url(forResource: file.name, withExtension: nil))
    }
    XCTAssertNil(Bundle.main.url(forResource: "legacy-predecessor-store-manifest.json", withExtension: nil))

    try verifyFixtureHashes(manifest)
    let originalHashes = try Dictionary(uniqueKeysWithValues: manifest.files.map { file in
      (file.name, try sha256(try fixtureURL(named: file.name)))
    })

    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let copiedFixture = root.appendingPathComponent("CopiedFixture", isDirectory: true)
    try FileManager.default.createDirectory(at: copiedFixture, withIntermediateDirectories: true)
    for file in manifest.files {
      try FileManager.default.copyItem(at: fixtureURL(named: file.name), to: copiedFixture.appendingPathComponent(file.name))
    }
    try verifyFixtureHashes(manifest, at: copiedFixture)

    let copyStoreURL = copiedFixture.appendingPathComponent("legacy-predecessor.store")
    try openAndAssertCopy(copyStoreURL, manifest: manifest)
    // A separate bootstrap after the first container goes out of scope is the
    // cold-reopen proof; only the copied test file is ever opened.
    try openAndAssertCopy(copyStoreURL, manifest: manifest)

    // Opening the copy must not alter the committed test resource.
    for file in manifest.files {
      XCTAssertEqual(try sha256(try fixtureURL(named: file.name)), originalHashes[file.name])
    }
    try verifyFixtureHashes(manifest)
  }

  @MainActor
  func testImmutablePredecessorStoreReachesReadyThroughFullAppBootstrapAndReconciliation() async throws {
    let manifest = try manifest()
    let originalHashes = try Dictionary(uniqueKeysWithValues: manifest.files.map { file in
      (file.name, try sha256(try fixtureURL(named: file.name)))
    })
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let copiedFixture = root.appendingPathComponent("CopiedFixture", isDirectory: true)
    try FileManager.default.createDirectory(
      at: copiedFixture,
      withIntermediateDirectories: true
    )
    for file in manifest.files {
      try FileManager.default.copyItem(
        at: fixtureURL(named: file.name),
        to: copiedFixture.appendingPathComponent(file.name)
      )
    }
    try verifyFixtureHashes(manifest, at: copiedFixture)

    let storeURL = copiedFixture.appendingPathComponent("legacy-predecessor.store")
    let imageStore = ImageStore(
      draftsDirectory: root.appendingPathComponent("Drafts", isDirectory: true),
      imagesDirectory: root.appendingPathComponent("Images", isDirectory: true),
      protectedDataIsAvailable: { true },
      writeGate: .unrestricted
    )

    do {
      let opened = await PersistenceBootstrap.openAppJournal(
        publicStoreURL: storeURL,
        resumePendingErase: { _ in nil },
        reconcileJournal: { context in
          try await EntryStore(context: context).reconcile(imageStore: imageStore)
        },
        protectedDataIsAvailable: { true }
      )
      XCTAssertTrue(opened.permitsJournalPresentation)
      let context = ModelContext(try XCTUnwrap(opened.modelContainer))
      try assertSyntheticValues(
        manifest.expectedValues,
        in: context,
        reconciledMissingPhoto: true
      )
    }

    // A second complete bootstrap proves that the app-level launch path did
    // not merely expose values from the first migration/reconciliation context.
    let reopened = await PersistenceBootstrap.openAppJournal(
      publicStoreURL: storeURL,
      resumePendingErase: { _ in nil },
      reconcileJournal: { context in
        try await EntryStore(context: context).reconcile(imageStore: imageStore)
      },
      protectedDataIsAvailable: { true }
    )
    XCTAssertTrue(reopened.permitsJournalPresentation)
    let reopenedContext = ModelContext(try XCTUnwrap(reopened.modelContainer))
    try assertSyntheticValues(
      manifest.expectedValues,
      in: reopenedContext,
      reconciledMissingPhoto: true
    )

    let expectedPhoto = root.appendingPathComponent("Images", isDirectory: true)
      .appendingPathComponent(
        try XCTUnwrap(manifest.expectedValues["entryImageFilename"]),
        isDirectory: false
      )
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: expectedPhoto.path),
      "The bootstrap must not fabricate a photo that the predecessor fixture intentionally does not contain."
    )

    // The immutable bundled predecessor evidence is never opened or rewritten.
    for file in manifest.files {
      XCTAssertEqual(try sha256(try fixtureURL(named: file.name)), originalHashes[file.name])
    }
    try verifyFixtureHashes(manifest)
  }
}

private extension Array {
  var only: Element? { count == 1 ? first : nil }
}
