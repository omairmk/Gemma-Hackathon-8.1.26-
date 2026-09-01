import XCTest
import CryptoKit
import GITimelineCore
#if canImport(LiteRTLM)
import LiteRTLM
#endif
import PDFKit
import SwiftData
import UIKit
@testable import GITimeline

/// Intentionally not excluded from the AppStoreTesting test configuration.
/// Its host app defines both `APPSTORE_RELEASE` and `APPSTORE_RELEASE_TESTING`
/// so it can trust its build-validated sentinel without weakening App Store.
@MainActor final class AppStoreReceiptProvenanceTests: XCTestCase {
  private let recordedCommit = String(repeating: "a", count: 40)
  private let recordedTree = String(repeating: "b", count: 40)

  func testReceiptPolicyKeepsRealAppStoreRecordedOnly() {
    XCTAssertTrue(BundledBuildReceiptProvenance.requiresRecordedSourceCommit(
      isAppStoreRelease: true,
      isAppStoreReleaseTesting: false
    ))
    XCTAssertFalse(BundledBuildReceiptProvenance.requiresRecordedSourceCommit(
      isAppStoreRelease: true,
      isAppStoreReleaseTesting: true
    ))
    XCTAssertFalse(BundledBuildReceiptProvenance.requiresRecordedSourceCommit(
      isAppStoreRelease: false,
      isAppStoreReleaseTesting: false
    ))

    let recordedFields = [
      "source_commit": recordedCommit,
      "source_tree": recordedTree,
      "package_resolved_sha256": BundledBuildReceiptProvenance.expectedPackageResolvedSHA256,
    ]
    XCTAssertTrue(BundledBuildReceiptProvenance.matches(
      fields: recordedFields,
      requiresRecordedSourceCommit: true,
      expectedSourceCommit: recordedCommit,
      expectedSourceTree: recordedTree
    ))

    let unrecordedFields = [
      "source_commit": "unrecorded",
      "source_tree": "unrecorded",
      "package_resolved_sha256": BundledBuildReceiptProvenance.expectedPackageResolvedSHA256,
    ]
    XCTAssertFalse(BundledBuildReceiptProvenance.matches(
      fields: unrecordedFields,
      requiresRecordedSourceCommit: true
    ))
  }

  func testAppStoreTestingCompilationTrustsOnlyBuildValidatedSentinel() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("The sentinel receipt policy is exercised by the AppStoreTesting configuration.")
    #else
    XCTAssertFalse(
      BundledBuildReceiptProvenance.requiresRecordedSourceCommit,
      "AppStoreTesting trusts only its build-validated source sentinel at runtime."
    )

    let unrecordedFields = [
      "source_commit": "unrecorded",
      "source_tree": "unrecorded",
      "package_resolved_sha256": BundledBuildReceiptProvenance.expectedPackageResolvedSHA256,
    ]
    XCTAssertTrue(BundledBuildReceiptProvenance.matches(
      fields: unrecordedFields,
      requiresRecordedSourceCommit: BundledBuildReceiptProvenance.requiresRecordedSourceCommit,
      expectedSourceCommit: "unrecorded",
      expectedSourceTree: "unrecorded"
    ))

    var wrongPackageFields = unrecordedFields
    wrongPackageFields["package_resolved_sha256"] = String(repeating: "c", count: 64)
    XCTAssertFalse(BundledBuildReceiptProvenance.matches(
      fields: wrongPackageFields,
      requiresRecordedSourceCommit: BundledBuildReceiptProvenance.requiresRecordedSourceCommit,
      expectedSourceCommit: "unrecorded",
      expectedSourceTree: "unrecorded"
    ))
    #endif
  }

  func testAppStoreTestingHostContainsNoEmbeddedModelPayload() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("The public package payload is exercised by the AppStoreTesting configuration.")
    #else
    let appURL = Bundle.main.bundleURL
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: appURL.appendingPathComponent("EmbeddedModels", isDirectory: true).path
      )
    )
    let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
    let enumerator = FileManager.default.enumerator(
      at: appURL,
      includingPropertiesForKeys: resourceKeys,
      options: [.skipsHiddenFiles]
    )
    let modelURLs = (enumerator?.allObjects as? [URL] ?? []).filter {
      $0.pathExtension == "litertlm"
    }
    XCTAssertTrue(modelURLs.isEmpty, "Manual fallback must package no model payload.")
    #endif
  }

  func testProductionRuntimeDefaultsToDirectRawPhotoConfiguration() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("The production runtime default is exercised by the AppStoreTesting configuration.")
    #else
    XCTAssertEqual(InferenceConfiguration.runtimeDefault, .appStoreRawImageV1)
    XCTAssertEqual(
      InferenceConfiguration.runtimeDefault.id,
      "app-store-raw-image-v1-cpu-candidate"
    )
    XCTAssertEqual(InferenceConfiguration.runtimeDefault.engineBackend, "cpu")
    XCTAssertEqual(InferenceConfiguration.runtimeDefault.visionBackend, "cpu")
    XCTAssertNil(InferenceConfiguration.runtimeDefault.mainCPUThreadCount)
    XCTAssertEqual(InferenceConfiguration.runtimeDefault.maxNumImages, 1)
    XCTAssertEqual(InferenceConfiguration.runtimeDefault.maxNumTokens, 1_536)
    XCTAssertEqual(InferenceConfiguration.runtimeDefault.visualTokenBudget, 70)
    XCTAssertEqual(InferenceConfiguration.runtimeDefault.promptVersion, "gi-photo-v1.2")
    XCTAssertEqual(
      InferenceConfiguration.runtimeDefault.imageMessageForm,
      "Message(contents:[Content.imageData(validatedSanitizedJPEGBytes),Content.text(gi-photo-v1.2)])"
    )
    XCTAssertTrue(InferenceConfiguration.runtimeDefault.usesRawPhotoV1Schema)
    XCTAssertFalse(InferenceConfiguration.runtimeDefault.usesLocalPixelBridge)
    XCTAssertNil(ModelCatalog.releaseSelection)
    XCTAssertNil(ModelCatalog.normalFlowSelection)
    #endif
  }

  func testAppStoreManualFallbackNeverInvokesInferenceAndPersistsCompletePhotoEntry() async throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("The public manual fallback is exercised by the AppStoreTesting configuration.")
    #else
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-appstore-manual-fallback-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images
    )
    let draftStore = DraftSnapshotStore(imageStore: imageStore)
    let container = try PersistenceSchema.openPublicStore(
      at: root.appendingPathComponent("GITimeline.store")
    )
    let context = ModelContext(container)
    let inference = AppStoreCountingInference()
    let viewModel = NewEntryViewModel(
      imageStore: imageStore,
      draftSnapshotStore: draftStore,
      store: EntryStore(context: context),
      inference: inference,
      descriptor: .liteRTGemma4E4B,
      modelVerified: true,
      engineReady: true,
      configuration: .appStoreRawImageV1,
      autoAnalysisEnabled: true
    )

    try viewModel.prepareImageData(Self.shippingPhotoData())
    XCTAssertTrue(viewModel.usesPublicManualFallback)
    XCTAssertFalse(viewModel.canAnalyze)
    XCTAssertFalse(viewModel.canPrepareModel)
    XCTAssertFalse(viewModel.canImportModel)
    XCTAssertFalse(viewModel.hasAnalysis)
    guard case .manual = viewModel.flowState else {
      return XCTFail("Attaching a public photo must enter the manual sheet directly.")
    }
    await viewModel.startAutomaticPreparation()
    await viewModel.prepareModel()
    viewModel.analyze()
    viewModel.retryAnalysis()
    try? await Task.sleep(for: .milliseconds(30))
    let liveCounts = await inference.snapshot()
    XCTAssertEqual(liveCounts, .init(prepare: 0, analyze: 0, repair: 0))

    viewModel.capturedAt = Date(timeIntervalSince1970: 1_770_000_000)
    viewModel.updateConfirmedPhotoUsable(true)
    viewModel.updateStoolPresence(.stool)
    viewModel.updateConfirmedBristolType(4)
    viewModel.updateApparentColor("brown")
    viewModel.redBlood = .no
    viewModel.blackAppearance = .no
    viewModel.blackTarry = .unsure
    XCTAssertTrue(viewModel.canSave)
    viewModel.retryAnalysis()
    try? await Task.sleep(for: .milliseconds(30))
    XCTAssertTrue(viewModel.canSave)
    guard case .manual = viewModel.flowState else {
      return XCTFail("Retry must preserve the completed public manual sheet.")
    }
    let postReviewRetryCounts = await inference.snapshot()
    XCTAssertEqual(postReviewRetryCounts, .init(prepare: 0, analyze: 0, repair: 0))

    let relaunched = NewEntryViewModel(
      imageStore: imageStore,
      draftSnapshotStore: draftStore,
      store: EntryStore(context: context),
      inference: inference,
      descriptor: .liteRTGemma4E4B,
      modelVerified: true,
      engineReady: true,
      configuration: .appStoreRawImageV1,
      autoAnalysisEnabled: true
    )
    relaunched.restoreUnfinishedDraftIfAvailable()
    XCTAssertNotNil(relaunched.currentDraftURL)
    XCTAssertEqual(relaunched.confirmedPhotoUsable, true)
    XCTAssertEqual(relaunched.confirmedStoolPresence, .stool)
    XCTAssertEqual(relaunched.confirmedBristolType, 4)
    XCTAssertEqual(relaunched.confirmedForm, "smooth_formed")
    XCTAssertEqual(relaunched.mixedForm, .no)
    XCTAssertEqual(relaunched.apparentColor, "brown")
    XCTAssertEqual(relaunched.redBlood, .no)
    XCTAssertEqual(relaunched.blackAppearance, .no)
    XCTAssertEqual(relaunched.blackTarry, .unsure)
    XCTAssertFalse(relaunched.canAnalyze)
    XCTAssertTrue(relaunched.canSave)
    relaunched.analyze()
    try? await Task.sleep(for: .milliseconds(30))
    let relaunchedCounts = await inference.snapshot()
    XCTAssertEqual(relaunchedCounts, .init(prepare: 0, analyze: 0, repair: 0))
    relaunched.save()

    let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
    XCTAssertEqual(entry.savedAnalysisSource, .manual)
    XCTAssertEqual(entry.provenance, EntryProvenance.manual.rawValue)
    XCTAssertNil(entry.analysisPipelineVersion)
    XCTAssertNil(entry.originalAIJSON)
    XCTAssertNil(entry.modelID)
    XCTAssertNil(entry.modelProvenanceJSON)
    XCTAssertNotNil(entry.imageFilename)
    XCTAssertNotNil(entry.imageSHA256)

    guard case .confirmedV1(let confirmation) = try StoredReviewedEntry.parse(
      XCTUnwrap(entry.reviewedJSON)
    ) else { return XCTFail("Expected a whole-entry confirmation envelope.") }
    XCTAssertEqual(confirmation.personConfirmedPhotoUsable, true)
    XCTAssertNil(confirmation.personConfirmedRetakeReason)
    XCTAssertEqual(confirmation.personConfirmedStoolPresence, .stool)
    XCTAssertEqual(confirmation.personConfirmedBristolType, 4)
    XCTAssertEqual(confirmation.personConfirmedForm, "smooth_formed")
    XCTAssertEqual(confirmation.personConfirmedMixedForm, .no)
    XCTAssertEqual(confirmation.personConfirmedApparentColor, "brown")
    XCTAssertEqual(confirmation.personConfirmedRed, .no)
    XCTAssertEqual(confirmation.personConfirmedBlackAppearance, .no)
    XCTAssertEqual(confirmation.personConfirmedBlackTarry, .unsure)
    XCTAssertNil(confirmation.initiallyAcceptedPhotoUsable)
    XCTAssertNil(confirmation.initiallyAcceptedRetakeReason)
    XCTAssertNil(confirmation.initiallyAcceptedStoolPresence)
    XCTAssertNil(confirmation.initiallyAcceptedBristolType)
    XCTAssertNil(confirmation.initiallyAcceptedForm)
    XCTAssertNil(confirmation.initiallyAcceptedMixedForm)
    XCTAssertNil(confirmation.initiallyAcceptedApparentColor)
    XCTAssertNil(confirmation.initiallyAcceptedRed)
    XCTAssertNil(confirmation.initiallyAcceptedBlackAppearance)
    XCTAssertNil(confirmation.initiallyAcceptedBlackTarry)
    XCTAssertEqual(
      confirmation.typedFieldProvenance,
      Dictionary(uniqueKeysWithValues: ConfirmationField.allCases.map {
        ($0, FieldConfirmationProvenance.manualNoSuggestion)
      })
    )

    var edited = EntryEditInput(entry: entry)
    edited.apparentColor = "yellow"
    edited.note = "edited after save"
    try EntryStore(context: context, writeGate: .unrestricted).update(
      entry,
      with: edited,
      baselineFingerprint: try EntryRecordFingerprint.make(for: entry),
      at: Date(timeIntervalSince1970: 1_770_000_100)
    )
    let entryID = entry.id
    let reopened = try XCTUnwrap(
      try context.fetch(
        FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.id == entryID })
      ).first
    )
    XCTAssertEqual(reopened.note, "edited after save")
    XCTAssertEqual(reopened.confirmedEntrySnapshot?.personConfirmedApparentColor, "yellow")
    XCTAssertNil(reopened.originalAIJSON)
    XCTAssertNil(reopened.modelProvenanceJSON)
    XCTAssertNil(reopened.confirmedEntrySnapshot?.initiallyAcceptedApparentColor)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.startOfDay(for: reopened.capturedAt)
    let export = try JournalExportSnapshotFactory.make(
      entries: [reopened],
      completions: [],
      treatmentEvents: [],
      range: .init(from: day, through: day),
      scope: .allEntries,
      generatedAt: Date(timeIntervalSince1970: 1_770_000_200),
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
    XCTAssertTrue(pdfText.contains("Manual entry; attached photo was not analyzed or used to prefill fields"))
    XCTAssertTrue(pdfText.contains("Manual value — apparent color: Yellow"))
    XCTAssertFalse(pdfText.contains("Gemma observation"))
    XCTAssertFalse(pdfText.contains("Accepted value —"))
    XCTAssertFalse(pdfText.contains("Photo suggestions are appearance-only"))
    #endif
  }

  func testAppStoreUpdateClearsUnfinishedModelVisualPrefillBeforeManualSave() async throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("The public in-place-update migration is exercised by the AppStoreTesting configuration.")
    #else
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-appstore-model-draft-migration-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: images
    )
    let draftStore = DraftSnapshotStore(imageStore: imageStore)
    let prepared = try imageStore.prepare(Self.shippingPhotoData())
    let capturedAt = Date(timeIntervalSince1970: 1_769_999_000)
    let modelFinishedAt = Date(timeIntervalSince1970: 1_769_999_010)
    let original = VisualObservation(
      imageUsable: true,
      qualityIssue: "none",
      apparentBristolType: 4,
      apparentColor: "brown",
      form: "smooth_formed",
      redAppearingMaterial: "possible",
      blackTarryAppearance: "not_observed"
    )
    let rawModelJSON = try ObservationParser.canonicalJSON(original)
    try draftStore.save(DraftSnapshot(
      version: DraftSnapshot.currentVersion,
      pendingEntryID: nil,
      pendingEntryFingerprint: nil,
      pendingReviewedAt: nil,
      draft: .init(
        id: prepared.reference.id,
        filename: prepared.url.lastPathComponent,
        sha256: prepared.reference.sha256
      ),
      capturedAt: capturedAt,
      confirmedStoolPresence: .stool,
      confirmedBristolType: 4,
      confirmedForm: "smooth_formed",
      confirmedApparentColor: "brown",
      confirmedPhotoUsable: true,
      confirmedRetakeReason: nil,
      subjectConfirmation: nil,
      mixedForm: .no,
      painScore: 3,
      urgency: .moderate,
      strainingOrIncomplete: .yes,
      leakageOrAccident: nil,
      redBlood: .yes,
      blackTarry: .no,
      dizziness: .no,
      severePain: .no,
      note: "Person-entered context survives the update.",
      reviewedObservation: original,
      review: .init(
        original: original,
        reviewed: original,
        originalMixedForm: .no,
        reviewedMixedForm: .no,
        states: Dictionary(uniqueKeysWithValues: ReviewField.allCases.map {
          ($0.rawValue, ReviewState.confirmed.rawValue)
        })
      ),
      originalValidatedJSON: rawModelJSON,
      fullPrefillNormalization: nil,
      modelSuggestedImageSHA256: prepared.reference.sha256,
      modelSuggestedAt: modelFinishedAt,
      generationStartedAt: modelFinishedAt.addingTimeInterval(-1),
      generationEndedAt: modelFinishedAt,
      inferenceParsePath: InferenceParsePath.direct.rawValue,
      analysisSource: .gemmaRawImage,
      analysisPipelineVersion: nil,
      didChooseBristolType: true,
      didChooseMixedForm: true,
      didReviewPhotoUsability: true
    ))

    let container = try PersistenceSchema.openPublicStore(
      at: root.appendingPathComponent("GITimeline.store")
    )
    let context = ModelContext(container)
    let inference = AppStoreCountingInference()
    let viewModel = NewEntryViewModel(
      imageStore: imageStore,
      draftSnapshotStore: draftStore,
      store: EntryStore(context: context),
      inference: inference,
      descriptor: .liteRTGemma4E4B,
      modelVerified: true,
      engineReady: true,
      configuration: .appStoreRawImageV1,
      autoAnalysisEnabled: true
    )
    viewModel.restoreUnfinishedDraftIfAvailable()

    let retainedPhotoURL = try XCTUnwrap(viewModel.currentDraftURL)
    XCTAssertEqual(
      Self.hexSHA256(try Data(contentsOf: retainedPhotoURL)),
      prepared.reference.sha256
    )
    XCTAssertEqual(viewModel.capturedAt, capturedAt)
    XCTAssertEqual(viewModel.note, "Person-entered context survives the update.")
    XCTAssertEqual(viewModel.painScore, 3)
    XCTAssertEqual(viewModel.urgency, .moderate)
    XCTAssertEqual(viewModel.strainingOrIncomplete, .yes)
    XCTAssertEqual(viewModel.dizziness, .no)
    XCTAssertEqual(viewModel.severePain, .no)
    XCTAssertEqual(viewModel.analysisSource, .manual)
    XCTAssertNil(viewModel.confirmedPhotoUsable)
    XCTAssertNil(viewModel.confirmedRetakeReason)
    XCTAssertNil(viewModel.confirmedStoolPresence)
    XCTAssertNil(viewModel.confirmedBristolType)
    XCTAssertNil(viewModel.confirmedForm)
    XCTAssertNil(viewModel.apparentColor)
    XCTAssertNil(viewModel.subjectConfirmation)
    XCTAssertNil(viewModel.mixedForm)
    XCTAssertNil(viewModel.redBlood)
    XCTAssertNil(viewModel.blackTarry)
    XCTAssertFalse(viewModel.hasAnalysis)
    XCTAssertFalse(viewModel.canAnalyze)
    XCTAssertFalse(viewModel.canSave)

    await viewModel.startAutomaticPreparation()
    await viewModel.prepareModel()
    viewModel.analyze()
    viewModel.retryAnalysis()
    try? await Task.sleep(for: .milliseconds(30))
    let inferenceCounts = await inference.snapshot()
    XCTAssertEqual(
      inferenceCounts,
      .init(prepare: 0, analyze: 0, repair: 0)
    )

    viewModel.updateConfirmedPhotoUsable(true)
    viewModel.updateStoolPresence(.stool)
    viewModel.updateConfirmedBristolType(4)
    viewModel.updateApparentColor("brown")
    viewModel.redBlood = .no
    viewModel.blackAppearance = .no
    viewModel.blackTarry = .no
    XCTAssertTrue(viewModel.canSave)
    viewModel.save()

    let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
    XCTAssertEqual(entry.savedAnalysisSource, .manual)
    XCTAssertEqual(entry.provenance, EntryProvenance.manual.rawValue)
    XCTAssertEqual(entry.imageSHA256, prepared.reference.sha256)
    XCTAssertNil(entry.originalAIJSON)
    XCTAssertNil(entry.modelProvenanceJSON)
    XCTAssertNil(entry.analysisPipelineVersion)
    guard case .confirmedV1(let confirmation) = try StoredReviewedEntry.parse(
      XCTUnwrap(entry.reviewedJSON)
    ) else { return XCTFail("Expected a manual whole-entry confirmation envelope.") }
    XCTAssertNil(confirmation.initiallyAcceptedPhotoUsable)
    XCTAssertNil(confirmation.initiallyAcceptedStoolPresence)
    XCTAssertNil(confirmation.initiallyAcceptedBristolType)
    XCTAssertNil(confirmation.initiallyAcceptedForm)
    XCTAssertNil(confirmation.initiallyAcceptedMixedForm)
    XCTAssertNil(confirmation.initiallyAcceptedApparentColor)
    XCTAssertNil(confirmation.initiallyAcceptedRed)
    XCTAssertNil(confirmation.initiallyAcceptedBlackAppearance)
    XCTAssertNil(confirmation.initiallyAcceptedBlackTarry)
    XCTAssertEqual(confirmation.personConfirmedBlackAppearance, .no)
    XCTAssertEqual(
      confirmation.typedFieldProvenance,
      Dictionary(uniqueKeysWithValues: ConfirmationField.allCases.map {
        ($0, FieldConfirmationProvenance.manualNoSuggestion)
      })
    )
    #endif
  }

  func testPublicHelpAndSettingsDisclosureOmitPortableRecoveryFeatureClaims() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("The public help surface is exercised by the AppStoreTesting configuration.")
    #else
    let publicHelp = GIJournalHelpRoute.helpAbout.body.lowercased()
    let photoSuggestionHelp = GIJournalHelpRoute.photoSuggestions.body.lowercased()
    let settingsDisclosure = AppFolders.dataLossLine.lowercased()
    for prohibitedPhrase in [
      "encrypted recovery",
      "recovery archive",
      "recovery key",
      "recovery file",
      "separate key",
      "private backup",
      "portable or encrypted",
      "journal-backup archive",
      "cross-install/device",
      "export recovery",
      "import recovery",
      "restore journal",
    ] {
      for (surface, copy) in [("Public Help", publicHelp), ("Settings disclosure", settingsDisclosure)] {
        XCTAssertFalse(
          copy.contains(prohibitedPhrase),
          "\(surface) must not advertise a removed portable-recovery feature: \(prohibitedPhrase)"
        )
      }
    }
    XCTAssertTrue(publicHelp.contains("saved logs are designed to remain"))
    XCTAssertTrue(publicHelp.contains("every attached photo for those entries are placed in a new pdf"))
    XCTAssertTrue(publicHelp.contains("a pdf cannot restore the journal"))
    XCTAssertTrue(photoSuggestionHelp.contains("attached photo is stored locally with the manual entry"))
    XCTAssertTrue(photoSuggestionHelp.contains("does not analyze the photo or use it to prefill fields"))
    XCTAssertTrue(publicHelp.contains("this public version does not analyze the photo"))
    XCTAssertFalse(photoSuggestionHelp.contains("gemma"))
    XCTAssertFalse(publicHelp.contains("gemma"))
    XCTAssertFalse(photoSuggestionHelp.contains("internal 140/280"))
    XCTAssertFalse(photoSuggestionHelp.contains("prefill red"))
    XCTAssertFalse(photoSuggestionHelp.contains("prefill black"))
    XCTAssertTrue(settingsDisclosure.contains("does not upload it to the developer"))
    XCTAssertTrue(settingsDisclosure.contains("may permanently lose entries and photos"))
    XCTAssertTrue(settingsDisclosure.contains("photo-inclusive pdf"))
    XCTAssertTrue(settingsDisclosure.contains("cannot restore the journal or create journal entries"))
    #endif
  }

  func testPublicThirdPartyAcknowledgmentsDescribeModelFreeManualLane() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("The public acknowledgments are exercised by the AppStoreTesting configuration.")
    #else
    let acknowledgments = GIJournalThirdPartyAcknowledgments.summary.lowercased()
    XCTAssertTrue(acknowledgments.contains("does not include or run a third-party ai model or runtime"))
    XCTAssertFalse(acknowledgments.contains("litert"))
    XCTAssertFalse(acknowledgments.contains("gemma"))
    XCTAssertFalse(acknowledgments.contains("qwen"))
    XCTAssertFalse(acknowledgments.contains("embedded gemma"))
    XCTAssertFalse(acknowledgments.contains("the public release model is"))
    XCTAssertFalse(GIJournalThirdPartyAcknowledgments.includesGemmaModelLink)

    let publicManualCopy = [
      acknowledgments,
      GIJournalPublicManualLaneCopy.photoAttachmentDisclosure.lowercased(),
      GIJournalPublicManualLaneCopy.privacyPhotoDisclosure.lowercased(),
    ].joined(separator: "\n")
    XCTAssertFalse(publicManualCopy.contains("bundled model"))
    XCTAssertFalse(publicManualCopy.contains("embedded model"))
    XCTAssertTrue(publicManualCopy.contains("contains no model"))
    XCTAssertTrue(publicManualCopy.contains("does not analyze the photo"))
    XCTAssertTrue(publicManualCopy.contains("prefill"))
    #endif
  }

  func testModelFreeManualSaveStillShowsWholeEntrySuccessState() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("The model-free App Store fallback is exercised by the AppStoreTesting configuration.")
    #else
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-appstore-model-free-save-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let container = try PersistenceSchema.makeInMemoryContainer()
    let context = ModelContext(container)
    let viewModel = NewEntryViewModel(
      imageStore: ImageStore(
        draftsDirectory: root.appendingPathComponent("Drafts", isDirectory: true),
        imagesDirectory: root.appendingPathComponent("Images", isDirectory: true)
      ),
      store: EntryStore(context: context),
      inference: UnavailableInferenceService(),
      descriptor: nil,
      modelVerified: false,
      configuration: .appStoreRawImageV1,
      autoAnalysisEnabled: false
    )

    viewModel.enterManualMode()
    viewModel.updateStoolPresence(.stool)
    viewModel.updateConfirmedBristolType(4)
    viewModel.updateMixedForm(.no)
    viewModel.updateApparentColor("brown")
    viewModel.redBlood = .no
    viewModel.blackAppearance = .no
    viewModel.blackTarry = .no
    XCTAssertTrue(viewModel.canSave)

    viewModel.save()

    let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<EntryRecord>()).first)
    XCTAssertEqual(entry.confirmedEntrySnapshot?.personConfirmedBlackAppearance, .no)
    XCTAssertNil(entry.confirmedEntrySnapshot?.initiallyAcceptedBlackAppearance)
    guard case .saved(let visibleID) = viewModel.flowState else {
      return XCTFail("A model-free manual save must show the whole-entry success state.")
    }
    XCTAssertEqual(visibleID, entry.id)
    XCTAssertFalse(viewModel.canSave)

    viewModel.startAnotherEntry()
    guard case .empty = viewModel.flowState else {
      return XCTFail("Add another must start a fresh entry after the success state.")
    }
    #endif
  }

  func testLiveJournalDirectoriesAndSyntheticPDFRequestBackupExclusion() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("The shipping local-storage policy is exercised by the AppStoreTesting configuration.")
    #else
    let directories = [
      try AppFolders.applicationSupport(),
      try AppFolders.drafts(),
      try AppFolders.entryEditDrafts(),
      try AppFolders.images(),
      try AppFolders.exports(),
    ]
    for directory in directories {
      let values = try directory.resourceValues(
        forKeys: [.isDirectoryKey, .isExcludedFromBackupKey]
      )
      XCTAssertEqual(values.isDirectory, true, "Expected a live journal directory: \(directory.lastPathComponent)")
      XCTAssertEqual(
        values.isExcludedFromBackup,
        true,
        "The live journal directory must retain the requested backup exclusion: \(directory.lastPathComponent)"
      )
    }

    let export = try AppFolders.writeExport(
      Data("%PDF-1.7\n%%EOF\n".utf8),
      filename: "GI-Journal_backup-exclusion-test-\(UUID().uuidString).pdf",
      writeGate: .unrestricted
    )
    defer { try? AppFolders.removeExport(export, writeGate: .unrestricted) }
    XCTAssertEqual(
      try export.resourceValues(
        forKeys: [.isRegularFileKey, .isExcludedFromBackupKey]
      ).isExcludedFromBackup,
      true,
      "A synthetic clinician PDF in the app-owned staging directory must retain the requested backup exclusion."
    )

    AppFolders.enforceStoreProtection()
    for storeFile in try AppFolders.storeFiles()
      where FileManager.default.fileExists(atPath: storeFile.path)
    {
      XCTAssertEqual(
        try storeFile.resourceValues(
          forKeys: [.isRegularFileKey, .isExcludedFromBackupKey]
        ).isExcludedFromBackup,
        true,
        "An existing SwiftData store or sidecar must retain the requested backup exclusion."
      )
    }
    #endif
  }

  func testUnsavedDraftSnapshotAndPreparedPhotoRequestBackupExclusion() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Concrete unsaved-draft backup handling is exercised by the AppStoreTesting configuration.")
    #else
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-appstore-unsaved-draft-backup-exclusion-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    try FileManager.default.createDirectory(at: drafts, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    try AppFolders.excludeFromBackup(drafts)
    try AppFolders.excludeFromBackup(images)

    let imageStore = ImageStore(draftsDirectory: drafts, imagesDirectory: images)
    let container = try PersistenceSchema.makeInMemoryContainer()
    let viewModel = NewEntryViewModel(
      imageStore: imageStore,
      store: EntryStore(context: ModelContext(container)),
      inference: UnavailableInferenceService(),
      descriptor: nil,
      modelVerified: false,
      configuration: .appStoreRawImageV1,
      autoAnalysisEnabled: false
    )

    try viewModel.prepareImageData(Self.shippingPhotoData())
    let photo = try XCTUnwrap(viewModel.currentDraftURL)
    let snapshot = drafts.appendingPathComponent("active-draft.v1.json")
    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.path))

    for file in [photo, snapshot] {
      let values = try file.resourceValues(
        forKeys: [.isRegularFileKey, .isExcludedFromBackupKey]
      )
      XCTAssertEqual(values.isRegularFile, true)
      XCTAssertEqual(
        values.isExcludedFromBackup,
        true,
        "Every concrete unsaved-draft artifact must retain the requested backup exclusion: \(file.lastPathComponent)"
      )
    }
    #endif
  }

  func testPreparedJPEGBackupExclusionFailureDeletesNewJPEG() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Concrete unsaved-draft failure handling is exercised by AppStoreTesting.")
    #else
    struct SimulatedBackupExclusionFailure: Error {}
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-appstore-jpeg-exclusion-failure-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: root.appendingPathComponent("Images", isDirectory: true),
      backupExcluder: { _ in throw SimulatedBackupExclusionFailure() }
    )

    XCTAssertThrowsError(try imageStore.prepare(Self.shippingPhotoData())) { error in
      XCTAssertTrue(error is SimulatedBackupExclusionFailure)
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: drafts,
      includingPropertiesForKeys: nil
    )
    XCTAssertFalse(
      files.contains(where: { $0.pathExtension.lowercased() == "jpg" }),
      "A prepared JPEG must not survive when its concrete backup exclusion fails."
    )
    #endif
  }

  func testSnapshotBackupExclusionFailurePreservesPriorSnapshotAndPhoto() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Concrete unfinished-draft failure handling is exercised by AppStoreTesting.")
    #else
    struct SimulatedBackupExclusionFailure: Error {}
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-appstore-snapshot-exclusion-failure-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let imageStore = ImageStore(
      draftsDirectory: drafts,
      imagesDirectory: root.appendingPathComponent("Images", isDirectory: true)
    )
    let healthySnapshotStore = DraftSnapshotStore(imageStore: imageStore)
    let container = try PersistenceSchema.makeInMemoryContainer()
    let viewModel = NewEntryViewModel(
      imageStore: imageStore,
      draftSnapshotStore: healthySnapshotStore,
      store: EntryStore(context: ModelContext(container)),
      inference: UnavailableInferenceService(),
      descriptor: nil,
      modelVerified: false,
      configuration: .appStoreRawImageV1,
      autoAnalysisEnabled: false
    )
    try viewModel.prepareImageData(Self.shippingPhotoData())
    let oldDraftURL = try XCTUnwrap(viewModel.currentDraftURL)
    let snapshotURL = drafts.appendingPathComponent("active-draft.v1.json")
    let oldSnapshotBytes = try Data(contentsOf: snapshotURL)

    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: oldSnapshotBytes) as? [String: Any]
    )
    object["note"] = "this replacement must not become visible"
    let replacementBytes = try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys]
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let replacement = try decoder.decode(DraftSnapshot.self, from: replacementBytes)
    var attemptedStagedURL: URL?
    let faultingStore = DraftSnapshotStore(
      imageStore: imageStore,
      backupExcluder: { url in
        attemptedStagedURL = url
        throw SimulatedBackupExclusionFailure()
      }
    )

    XCTAssertThrowsError(try faultingStore.save(replacement)) { error in
      XCTAssertTrue(error is SimulatedBackupExclusionFailure)
    }
    XCTAssertEqual(try Data(contentsOf: snapshotURL), oldSnapshotBytes)
    XCTAssertTrue(FileManager.default.fileExists(atPath: oldDraftURL.path))
    let attempted = try XCTUnwrap(attemptedStagedURL)
    XCTAssertTrue(attempted.lastPathComponent.hasPrefix(".active-draft.v1."))
    XCTAssertEqual(attempted.pathExtension, "tmp")
    XCTAssertFalse(FileManager.default.fileExists(atPath: attempted.path))
    let files = try FileManager.default.contentsOfDirectory(
      at: drafts,
      includingPropertiesForKeys: nil
    )
    XCTAssertFalse(files.contains(where: { $0.pathExtension.lowercased() == "tmp" }))
    XCTAssertEqual(
      files.filter { $0.pathExtension.lowercased() == "jpg" }.map(\.lastPathComponent),
      [oldDraftURL.lastPathComponent]
    )
    #endif
  }

  #if canImport(LiteRTLM)
  func testAppStoreModelCacheRejectsJunkAndPartialReceiptAsCold() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping cache resource handling is exercised by the AppStoreTesting configuration.")
    #else
    let root = temporaryCacheTestRoot("junk-partial")
    defer { try? FileManager.default.removeItem(at: root) }
    var cache = try populatedModelCache(in: root)
    assertColdCacheRejected(in: root)
    cache = try populatedModelCache(in: root)

    try Data("{".utf8).write(
      to: AppFolders.modelCacheCompletionReceiptURL(for: cache),
      options: .atomic
    )
    assertColdCacheRejected(in: root)
    #endif
  }

  func testAppStoreModelCacheReceiptRejectsStaleRuntimeAndWrongModel() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping cache resource handling is exercised by the AppStoreTesting configuration.")
    #else
    let root = temporaryCacheTestRoot("receipt-fields")
    defer { try? FileManager.default.removeItem(at: root) }
    var cache = try populatedModelCache(in: root)

    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    try mutateCompletionReceipt(for: cache, key: "cache_schema", value: "stale-schema")
    assertColdCacheRejected(in: root)
    cache = try populatedModelCache(in: root)

    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    try mutateCompletionReceipt(
      for: cache,
      key: "model_sha256",
      value: String(repeating: "f", count: 64)
    )
    assertColdCacheRejected(in: root)
    cache = try populatedModelCache(in: root)

    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    try mutateCompletionReceipt(
      for: cache,
      key: "engine_profile_sha256",
      value: String(repeating: "a", count: 64)
    )
    assertColdCacheRejected(in: root)
    cache = try populatedModelCache(in: root)

    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    try mutateCompletionReceipt(
      for: cache,
      key: "litert_lm_revision",
      value: String(repeating: "e", count: 40)
    )
    assertColdCacheRejected(in: root)
    #endif
  }

  func testAppStoreEngineCacheProfileConservativelyBindsReviewedRouteInputs() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping engine-cache identity is exercised by AppStoreTesting.")
    #else
    let shipping = InferenceConfiguration.appStoreRawImageV1
    let profile = LiteRTEngineCacheProfileV1(
      descriptor: .liteRTGemma4E4B,
      configuration: shipping
    )
    XCTAssertEqual(profile.format, "gi-litert-engine-cache-profile-v2")
    XCTAssertEqual(profile.engineBackend, "cpu")
    XCTAssertEqual(profile.visionBackend, "cpu")
    XCTAssertEqual(profile.audioBackend, "disabled")
    XCTAssertEqual(profile.mainCPUThreadCount, "runtime-default")
    XCTAssertEqual(profile.maxNumImages, "1")
    XCTAssertEqual(profile.maxNumTokens, 1_536)
    XCTAssertEqual(
      profile.swiftWrapperCompileInputSHA256,
      "22c81184a1bad821ea7c890c167fa0a75089ba774beaf8176a0d3b99290d842d"
    )
    XCTAssertEqual(profile.visualTokenBudget, "70")
    XCTAssertEqual(profile.benchmarkMode, "disabled")
    XCTAssertEqual(profile.speculativeDecodingMode, "runtime-default-nil")
    XCTAssertEqual(
      try profile.sha256,
      "dcd0407d6ea1c9225f1cd433b5a9ac9982c807ee0063906d99de0e439cf88359"
    )
    XCTAssertEqual(
      try profile.sha256,
      try LiteRTEngineCacheProfileV1(
        descriptor: .liteRTGemma4E4B,
        configuration: shipping
      ).sha256
    )

    func configuration(
      engine: String = "cpu",
      vision: String = "cpu",
      mainThreads: Int? = nil,
      images: Int? = 1,
      context: Int = 1_536,
      visual: Int? = 70,
      topK: Int = 1,
      topP: Float = 1,
      temperature: Float = 0,
      seed: Int = 0,
      prompt: String = "gi-photo-v1.2",
      message: String = "Message(contents:[Content.imageData(validatedSanitizedJPEGBytes),Content.text(gi-photo-v1.2)])"
    ) -> InferenceConfiguration {
      InferenceConfiguration(
        id: "test-profile",
        engineBackend: engine,
        visionBackend: vision,
        mainCPUThreadCount: mainThreads,
        maxNumImages: images,
        maxNumTokens: context,
        topK: topK,
        topP: topP,
        temperature: temperature,
        seed: seed,
        promptVersion: prompt,
        imageMessageForm: message,
        visualTokenBudget: visual
      )
    }

    // maxNumImages is legacy-only in the packaged v0.15 native header and the
    // visual budget is conversation-scoped. They remain in V5 as conservative
    // route-isolation inputs; this test does not claim they alter the advanced
    // engine's compiled artifact.
    let routeIdentityVariants = [
      configuration(engine: "gpu"),
      configuration(vision: "disabled"),
      configuration(mainThreads: 2),
      configuration(images: 2),
      configuration(images: nil),
      configuration(context: 1_024),
      configuration(visual: 140),
      configuration(visual: nil),
    ]
    for variant in routeIdentityVariants {
      let changed = LiteRTEngineCacheProfileV1(
        descriptor: .liteRTGemma4E4B,
        configuration: variant
      )
      XCTAssertNotEqual(changed, profile)
      XCTAssertNotEqual(try changed.sha256, try profile.sha256)
      XCTAssertNotEqual(
        try AppFolders.liteRTCacheSchema(for: changed),
        try AppFolders.liteRTCacheSchema(for: profile)
      )
    }

    let nonEngineChange = configuration(
      topK: 8,
      topP: 0.75,
      temperature: 0.5,
      seed: 99,
      prompt: "different-prompt",
      message: "different-message-form"
    )
    XCTAssertEqual(
      LiteRTEngineCacheProfileV1(
        descriptor: .liteRTGemma4E4B,
        configuration: nonEngineChange
      ),
      profile
    )
    #endif
  }

  func testAppStoreEngineCacheProfileMismatchUsesEmptyIsolatedV5Directory() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping engine-cache isolation is exercised by AppStoreTesting.")
    #else
    let root = temporaryCacheTestRoot("profile-isolation")
    let cachesRoot = root.appendingPathComponent("SyntheticCaches", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let shipping = InferenceConfiguration.appStoreRawImageV1
    let changed = InferenceConfiguration(
      id: "changed-context-test",
      engineBackend: shipping.engineBackend,
      visionBackend: shipping.visionBackend,
      mainCPUThreadCount: shipping.mainCPUThreadCount,
      maxNumImages: shipping.maxNumImages,
      maxNumTokens: 2_048,
      topK: shipping.topK,
      topP: shipping.topP,
      temperature: shipping.temperature,
      seed: shipping.seed,
      promptVersion: shipping.promptVersion,
      imageMessageForm: shipping.imageMessageForm,
      visualTokenBudget: shipping.visualTokenBudget
    )
    let coldShippingResolution = try AppFolders.modelCacheResolution(
      for: .liteRTGemma4E4B,
      configuration: shipping,
      cachesDirectory: cachesRoot,
      availableCapacityOverride: .max,
      allowLegacyApplicationSupportReuse: false
    )
    XCTAssertEqual(coldShippingResolution.disposition, .coldVersionedCache)
    let shippingCache = coldShippingResolution.url
    let shippingCacheFile = shippingCache.appendingPathComponent("program_cache.bin")
    try Data("shipping profile cache".utf8).write(to: shippingCacheFile, options: .atomic)
    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      configuration: shipping,
      cacheURL: shippingCache
    )
    let warmShippingResolution = try AppFolders.modelCacheResolution(
      for: .liteRTGemma4E4B,
      configuration: shipping,
      cachesDirectory: cachesRoot,
      availableCapacityOverride: 0,
      allowLegacyApplicationSupportReuse: false
    )
    XCTAssertEqual(warmShippingResolution.url, shippingCache)
    XCTAssertEqual(warmShippingResolution.disposition, .validatedVersionedReuse)

    XCTAssertThrowsError(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        configuration: changed,
        cachesDirectory: cachesRoot,
        availableCapacityOverride: 0,
        allowLegacyApplicationSupportReuse: false
      )
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .insufficientModelStorage)
    }
    let changedCache = try AppFolders.modelCache(
      for: .liteRTGemma4E4B,
      configuration: changed,
      cachesDirectory: cachesRoot,
      availableCapacityOverride: .max,
      allowLegacyApplicationSupportReuse: false
    )
    XCTAssertNotEqual(changedCache, shippingCache)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: changedCache.path).isEmpty)
    XCTAssertEqual(try Data(contentsOf: shippingCacheFile), Data("shipping profile cache".utf8))

    let changedFile = changedCache.appendingPathComponent("stale.bin")
    try Data("stale changed profile".utf8).write(to: changedFile, options: .atomic)
    let copiedReceipt = AppFolders.modelCacheCompletionReceiptURL(for: changedCache)
    try FileManager.default.copyItem(
      at: AppFolders.modelCacheCompletionReceiptURL(for: shippingCache),
      to: copiedReceipt
    )
    XCTAssertThrowsError(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        configuration: changed,
        cachesDirectory: cachesRoot,
        availableCapacityOverride: 0,
        allowLegacyApplicationSupportReuse: false
      )
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .insufficientModelStorage)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: changedCache.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: changedFile.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: copiedReceipt.path))
    XCTAssertEqual(try Data(contentsOf: shippingCacheFile), Data("shipping profile cache".utf8))
    let reset = try AppFolders.modelCache(
      for: .liteRTGemma4E4B,
      configuration: changed,
      cachesDirectory: cachesRoot,
      availableCapacityOverride: .max,
      allowLegacyApplicationSupportReuse: false
    )
    XCTAssertEqual(reset, changedCache)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: reset.path).isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: copiedReceipt.path))
    XCTAssertEqual(try Data(contentsOf: shippingCacheFile), Data("shipping profile cache".utf8))
    #endif
  }

  func testAppStoreCacheSelectionAndEngineConfigPlanUseSameProfile() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping cache selection and EngineConfig mapping are exercised by AppStoreTesting.")
    #else
    let root = temporaryCacheTestRoot("engine-config-plan")
    defer { try? FileManager.default.removeItem(at: root) }
    let configuration = InferenceConfiguration.appStoreRawImageV1
    let policy = ModelRuntimeEngineCachePolicy.sharedModelCacheForTesting(
      cachesDirectory: root.appendingPathComponent("SyntheticCaches", isDirectory: true),
      availableCapacityOverride: .max
    )
    let selection = try policy.cacheSelection(
      for: .liteRTGemma4E4B,
      configuration: configuration
    )
    let modelURL = root.appendingPathComponent(
      ModelDescriptor.liteRTGemma4E4B.artifactFilename,
      isDirectory: false
    )
    let plan = try LiteRTEngineConfigPlan(
      profile: selection.profile,
      modelURL: modelURL,
      cacheURL: selection.url
    )

    XCTAssertEqual(
      selection.profile,
      LiteRTEngineCacheProfileV1(
        descriptor: .liteRTGemma4E4B,
        configuration: configuration
      )
    )
    XCTAssertEqual(plan.modelPath, modelURL.path)
    XCTAssertEqual(plan.cachePath, selection.url.path)
    XCTAssertEqual(plan.engineBackend, "cpu")
    XCTAssertEqual(plan.visionBackend, "cpu")
    XCTAssertEqual(plan.audioBackend, "disabled")
    XCTAssertNil(plan.mainCPUThreadCount)
    XCTAssertEqual(plan.maxNumImages, 1)
    XCTAssertEqual(plan.maxNumTokens, 1_536)
    XCTAssertNil(plan.textLoraRank)
    XCTAssertNil(plan.audioLoraRank)
    XCTAssertEqual(selection.profile.visualTokenBudget, "70")
    let engineConfig = try plan.makeEngineConfig()
    XCTAssertEqual(engineConfig.backend, .cpu())
    XCTAssertEqual(engineConfig.maxNumImages, 1)
    XCTAssertEqual(engineConfig.maxNumTokens, 1_536)
    #endif
  }

  func testVendoredLiteRTWrapperValidatesAndForwardsReviewedEngineLimits() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("The vendored App Store wrapper is exercised by AppStoreTesting.")
    #else
    let defaultConfig = try EngineConfig(modelPath: "/synthetic/model.litertlm")
    XCTAssertEqual(defaultConfig.backend, .cpu())
    XCTAssertNil(defaultConfig.maxNumImages)

    for invalidImageCount in [-1, Int(Int32.max) + 1] {
      XCTAssertThrowsError(try EngineConfig(
        modelPath: "/synthetic/model.litertlm",
        maxNumImages: invalidImageCount
      )) { error in
        XCTAssertEqual(
          error as? LiteRTLMError,
          .config(.invalidMaxNumImages(count: invalidImageCount))
        )
      }
    }
    for invalidThreadCount in [0, -1, Int(Int32.max) + 1] {
      XCTAssertThrowsError(try EngineConfig(
        modelPath: "/synthetic/model.litertlm",
        backend: .cpu(threadCount: invalidThreadCount),
        maxNumImages: 1
      )) { error in
        XCTAssertEqual(
          error as? LiteRTLMError,
          .config(.invalidCPUThreadCount(count: invalidThreadCount))
        )
      }
    }

    let shipping = InferenceConfiguration.appStoreRawImageV1
    let explicitCPU = InferenceConfiguration(
      id: "explicit-main-cpu-test",
      engineBackend: shipping.engineBackend,
      visionBackend: shipping.visionBackend,
      mainCPUThreadCount: 3,
      maxNumImages: 1,
      maxNumTokens: shipping.maxNumTokens,
      topK: shipping.topK,
      topP: shipping.topP,
      temperature: shipping.temperature,
      seed: shipping.seed,
      promptVersion: shipping.promptVersion,
      imageMessageForm: shipping.imageMessageForm,
      visualTokenBudget: shipping.visualTokenBudget
    )
    let plan = try LiteRTEngineConfigPlan(
      profile: LiteRTEngineCacheProfileV1(
        descriptor: .liteRTGemma4E4B,
        configuration: explicitCPU
      ),
      modelURL: URL(fileURLWithPath: "/synthetic/model.litertlm"),
      cacheURL: URL(fileURLWithPath: "/synthetic/cache", isDirectory: true)
    )
    XCTAssertEqual(plan.mainCPUThreadCount, 3)
    XCTAssertEqual(plan.maxNumImages, 1)
    let engineConfig = try plan.makeEngineConfig()
    XCTAssertEqual(engineConfig.backend, .cpu(threadCount: 3))
    XCTAssertEqual(engineConfig.maxNumImages, 1)
    #endif
  }

  func testAppStoreConversationConfigUsesScopedVisualBudgetAndExactSampler() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping ConversationConfig mapping is exercised by AppStoreTesting.")
    #else
    let shipping = InferenceConfiguration.appStoreRawImageV1
    let plan = try LiteRTConversationConfigPlan(configuration: shipping)
    XCTAssertEqual(plan.topK, shipping.topK)
    XCTAssertEqual(plan.topP, shipping.topP)
    XCTAssertEqual(plan.temperature, shipping.temperature)
    XCTAssertEqual(plan.seed, shipping.seed)
    XCTAssertEqual(plan.visualTokenBudget, 70)

    let conversation = try plan.makeConversationConfig()
    XCTAssertEqual(conversation.visualTokenBudget, 70)
    XCTAssertEqual(conversation.samplerConfig?.topK, shipping.topK)
    XCTAssertEqual(conversation.samplerConfig?.topP, shipping.topP)
    XCTAssertEqual(conversation.samplerConfig?.temperature, shipping.temperature)
    XCTAssertEqual(conversation.samplerConfig?.seed, shipping.seed)

    let baselinePlan = try LiteRTConversationConfigPlan(
      configuration: .deterministicBaseline
    )
    XCTAssertNil(baselinePlan.visualTokenBudget)
    XCTAssertNil(try baselinePlan.makeConversationConfig().visualTokenBudget)

    let invalidBudget = InferenceConfiguration(
      id: "invalid-conversation-visual-budget-test",
      engineBackend: shipping.engineBackend,
      visionBackend: shipping.visionBackend,
      mainCPUThreadCount: shipping.mainCPUThreadCount,
      maxNumImages: shipping.maxNumImages,
      maxNumTokens: shipping.maxNumTokens,
      topK: shipping.topK,
      topP: shipping.topP,
      temperature: shipping.temperature,
      seed: shipping.seed,
      promptVersion: shipping.promptVersion,
      imageMessageForm: shipping.imageMessageForm,
      visualTokenBudget: 71
    )
    XCTAssertThrowsError(
      try LiteRTConversationConfigPlan(configuration: invalidBudget)
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .invalidModelDescriptor)
    }
    #endif
  }

  func testAppStoreModelCacheReceiptRejectsPathIdentityAndSymlinkMismatch() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping cache resource handling is exercised by the AppStoreTesting configuration.")
    #else
    let root = temporaryCacheTestRoot("receipt-identity")
    defer { try? FileManager.default.removeItem(at: root) }
    var cache = try populatedModelCache(in: root)
    var receiptURL = AppFolders.modelCacheCompletionReceiptURL(for: cache)

    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    try mutateCompletionReceipt(
      for: cache,
      key: "cache_path",
      value: cache.appendingPathComponent("moved", isDirectory: true).path
    )
    assertColdCacheRejected(in: root)
    cache = try populatedModelCache(in: root)
    receiptURL = AppFolders.modelCacheCompletionReceiptURL(for: cache)

    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    try FileManager.default.removeItem(at: cache)
    try FileManager.default.createDirectory(
      at: cache,
      withIntermediateDirectories: true
    )
    try Data("replacement cache".utf8).write(
      to: cache.appendingPathComponent("program_cache.bin"),
      options: .atomic
    )
    assertColdCacheRejected(in: root)
    cache = try populatedModelCache(in: root)
    receiptURL = AppFolders.modelCacheCompletionReceiptURL(for: cache)

    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    let externalReceipt = root.appendingPathComponent(
      "outside-receipt.json",
      isDirectory: false
    )
    try FileManager.default.moveItem(at: receiptURL, to: externalReceipt)
    try FileManager.default.createSymbolicLink(
      at: receiptURL,
      withDestinationURL: externalReceipt
    )
    assertColdCacheRejected(in: root)
    XCTAssertTrue(FileManager.default.fileExists(atPath: externalReceipt.path))
    #endif
  }

  func testAppStoreModelCacheValidCompletionReceiptQualifiesWarmAndPurgeStaysCold() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping cache resource handling is exercised by the AppStoreTesting configuration.")
    #else
    let root = temporaryCacheTestRoot("valid-receipt")
    let cachesRoot = root.appendingPathComponent("SyntheticCaches", isDirectory: true)
    let journalRoot = root.appendingPathComponent("SyntheticJournal", isDirectory: true)
    let journalSentinel = journalRoot.appendingPathComponent(
      "must-remain-unchanged.bin",
      isDirectory: false
    )
    let journalSentinelBytes = Data("synthetic journal sentinel".utf8)
    try FileManager.default.createDirectory(
      at: journalRoot,
      withIntermediateDirectories: true
    )
    try journalSentinelBytes.write(to: journalSentinel, options: .atomic)
    defer { try? FileManager.default.removeItem(at: root) }

    var cache = try populatedModelCache(in: root)
    assertColdCacheRejected(in: root)
    cache = try populatedModelCache(in: root)
    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    let receiptURL = AppFolders.modelCacheCompletionReceiptURL(for: cache)
    let receiptValues = try receiptURL.resourceValues(
      forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
    )
    XCTAssertEqual(receiptValues.isRegularFile, true)
    XCTAssertEqual(receiptValues.isSymbolicLink, false)
    XCTAssertEqual(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        cachesDirectory: cachesRoot,
        availableCapacityOverride: 0
      ),
      cache,
      "Only a valid post-initialization receipt may bypass the cold-capacity gate."
    )
    XCTAssertEqual(try Data(contentsOf: journalSentinel), journalSentinelBytes)

    let appCacheRoot = cachesRoot.appendingPathComponent(
      "GITimeline",
      isDirectory: true
    )
    try FileManager.default.removeItem(at: appCacheRoot)
    XCTAssertThrowsError(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        cachesDirectory: cachesRoot,
        availableCapacityOverride: 0
      )
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .insufficientModelStorage)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: appCacheRoot.path))
    XCTAssertEqual(try Data(contentsOf: journalSentinel), journalSentinelBytes)

    let recreated = try AppFolders.modelCache(
      for: .liteRTGemma4E4B,
      cachesDirectory: cachesRoot,
      availableCapacityOverride: .max
    )
    XCTAssertEqual(recreated, cache)
    XCTAssertTrue(FileManager.default.fileExists(atPath: recreated.path))
    XCTAssertEqual(
      try recreated.resourceValues(
        forKeys: [.isExcludedFromBackupKey]
      ).isExcludedFromBackup,
      true
    )
    XCTAssertEqual(try Data(contentsOf: journalSentinel), journalSentinelBytes)
    #endif
  }

  func testAppStoreConversationRefreshCapturesLazyVisionCacheFilesForWarmReuse() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping lazy-modality cache handling is exercised by AppStoreTesting.")
    #else
    let root = temporaryCacheTestRoot("lazy-vision-refresh")
    let cachesRoot = root.appendingPathComponent("SyntheticCaches", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = try populatedModelCache(in: root)

    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    let receiptURL = AppFolders.modelCacheCompletionReceiptURL(for: cache)
    let engineOnlyReceipt = try Data(contentsOf: receiptURL)

    let lazyVisionFiles = [
      cache.appendingPathComponent("vision_encoder_cache.bin"),
      cache.appendingPathComponent("vision_adapter_cache.bin"),
    ]
    try Data("synthetic lazy vision encoder".utf8).write(
      to: lazyVisionFiles[0],
      options: .atomic
    )
    try Data("synthetic lazy vision adapter".utf8).write(
      to: lazyVisionFiles[1],
      options: .atomic
    )

    // Production invokes this same strict writer after createConversation()
    // returns. The refreshed manifest must bind the lazily added modality
    // files rather than force a cold rebuild on the next launch.
    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    XCTAssertNotEqual(try Data(contentsOf: receiptURL), engineOnlyReceipt)

    let warm = try AppFolders.modelCacheResolution(
      for: .liteRTGemma4E4B,
      cachesDirectory: cachesRoot,
      availableCapacityOverride: 0
    )
    XCTAssertEqual(warm.url, cache)
    XCTAssertEqual(warm.disposition, .validatedVersionedReuse)
    for file in lazyVisionFiles {
      XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    #endif
  }

  func testAppStoreUnrefreshedLazyVisionCacheFailsClosedWithoutTouchingJournal() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping lazy-modality cache handling is exercised by AppStoreTesting.")
    #else
    let root = temporaryCacheTestRoot("lazy-vision-stale-receipt")
    let cachesRoot = root.appendingPathComponent("SyntheticCaches", isDirectory: true)
    let journalSentinel = root
      .appendingPathComponent("SyntheticJournal", isDirectory: true)
      .appendingPathComponent("must-remain-unchanged.bin", isDirectory: false)
    let journalBytes = Data("synthetic private journal sentinel".utf8)
    try FileManager.default.createDirectory(
      at: journalSentinel.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try journalBytes.write(to: journalSentinel, options: .atomic)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = try populatedModelCache(in: root)

    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    let receiptURL = AppFolders.modelCacheCompletionReceiptURL(for: cache)
    try Data("synthetic unreceipted vision cache".utf8).write(
      to: cache.appendingPathComponent("vision_encoder_cache.bin"),
      options: .atomic
    )

    XCTAssertThrowsError(
      try AppFolders.modelCacheResolution(
        for: .liteRTGemma4E4B,
        cachesDirectory: cachesRoot,
        availableCapacityOverride: 0
      )
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .insufficientModelStorage)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: receiptURL.path))
    XCTAssertEqual(try Data(contentsOf: journalSentinel), journalBytes)
    #endif
  }

  func testAppStoreGenerationRefreshCapturesFirstVisionCacheMutationForWarmReuse() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping post-generation cache handling is exercised by AppStoreTesting.")
    #else
    let root = temporaryCacheTestRoot("post-generation-refresh")
    let cachesRoot = root.appendingPathComponent("SyntheticCaches", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = try populatedModelCache(in: root)

    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    let conversationFile = cache.appendingPathComponent(
      "vision_conversation_cache.bin"
    )
    try Data("synthetic conversation cache".utf8).write(
      to: conversationFile,
      options: .atomic
    )
    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    let postConversationReceipt = try Data(
      contentsOf: AppFolders.modelCacheCompletionReceiptURL(for: cache)
    )

    let firstGenerationFile = cache.appendingPathComponent(
      "vision_first_generation_cache.bin"
    )
    try Data("synthetic first image generation cache".utf8).write(
      to: firstGenerationFile,
      options: .atomic
    )

    // Production invokes the same strict writer only after bounded streaming
    // finishes successfully. The refreshed manifest must bind generation-time
    // files so a valid warm cache does not require another model-sized build.
    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    XCTAssertNotEqual(
      try Data(contentsOf: AppFolders.modelCacheCompletionReceiptURL(for: cache)),
      postConversationReceipt
    )

    let warm = try AppFolders.modelCacheResolution(
      for: .liteRTGemma4E4B,
      cachesDirectory: cachesRoot,
      availableCapacityOverride: 0
    )
    XCTAssertEqual(warm.url, cache)
    XCTAssertEqual(warm.disposition, .validatedVersionedReuse)
    XCTAssertTrue(FileManager.default.fileExists(atPath: conversationFile.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: firstGenerationFile.path))
    #endif
  }

  func testAppStoreUnrefreshedGenerationMutationFailsClosedWithoutTouchingJournal() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping post-generation cache handling is exercised by AppStoreTesting.")
    #else
    let root = temporaryCacheTestRoot("post-generation-stale-receipt")
    let cachesRoot = root.appendingPathComponent("SyntheticCaches", isDirectory: true)
    let journalSentinel = root
      .appendingPathComponent("SyntheticJournal", isDirectory: true)
      .appendingPathComponent("must-remain-unchanged.bin", isDirectory: false)
    let journalBytes = Data("synthetic private journal sentinel".utf8)
    try FileManager.default.createDirectory(
      at: journalSentinel.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try journalBytes.write(to: journalSentinel, options: .atomic)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = try populatedModelCache(in: root)

    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    let conversationFile = cache.appendingPathComponent(
      "vision_conversation_cache.bin"
    )
    try Data("synthetic conversation cache".utf8).write(
      to: conversationFile,
      options: .atomic
    )
    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    let receiptURL = AppFolders.modelCacheCompletionReceiptURL(for: cache)

    try Data("synthetic unreceipted generation cache".utf8).write(
      to: cache.appendingPathComponent(
        "vision_first_generation_cache.bin"
      ),
      options: .atomic
    )

    XCTAssertThrowsError(
      try AppFolders.modelCacheResolution(
        for: .liteRTGemma4E4B,
        cachesDirectory: cachesRoot,
        availableCapacityOverride: 0
      )
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .insufficientModelStorage)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: receiptURL.path))
    XCTAssertEqual(try Data(contentsOf: journalSentinel), journalBytes)
    #endif
  }

  func testAppStoreModelCacheReceiptRejectsPartialFilePurge() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping cache resource handling is exercised by the AppStoreTesting configuration.")
    #else
    let root = temporaryCacheTestRoot("partial-purge")
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = try populatedModelCache(in: root)
    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )
    XCTAssertEqual(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        cachesDirectory: root.appendingPathComponent(
          "SyntheticCaches",
          isDirectory: true
        ),
        availableCapacityOverride: 0
      ),
      cache
    )

    try FileManager.default.removeItem(
      at: cache.appendingPathComponent("tokenizer_cache.bin")
    )
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: cache.appendingPathComponent("program_cache.bin").path
    ))
    assertColdCacheRejected(in: root)
    #endif
  }

  func testAppStoreLegacyApplicationSupportCacheReusesWithoutColdAllocationAndUpgradesReceipt() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping cache upgrade handling is exercised by the AppStoreTesting configuration.")
    #else
    let root = temporaryCacheTestRoot("legacy-upgrade")
    let cachesRoot = root.appendingPathComponent("SyntheticCaches", isDirectory: true)
    let applicationSupportRoot = root
      .appendingPathComponent("SyntheticApplicationSupport", isDirectory: true)
      .appendingPathComponent("GITimeline", isDirectory: true)
    let legacyCache = applicationSupportRoot
      .appendingPathComponent("Models", isDirectory: true)
      .appendingPathComponent(
        ModelDescriptor.liteRTGemma4E4B.cacheNamespace,
        isDirectory: true
      )
      .appendingPathComponent("Cache", isDirectory: true)
    let syntheticJournalSentinel = applicationSupportRoot
      .appendingPathComponent("Images", isDirectory: true)
      .appendingPathComponent("must-remain-unchanged.bin", isDirectory: false)
    let sentinelBytes = Data("synthetic journal sentinel".utf8)
    try FileManager.default.createDirectory(
      at: legacyCache,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: syntheticJournalSentinel.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("legacy synthetic compiled cache".utf8).write(
      to: legacyCache.appendingPathComponent("program_cache.bin"),
      options: .atomic
    )
    try sentinelBytes.write(to: syntheticJournalSentinel, options: .atomic)
    defer { try? FileManager.default.removeItem(at: root) }

    let legacyResolution = try AppFolders.modelCacheResolution(
      for: .liteRTGemma4E4B,
      cachesDirectory: cachesRoot,
      legacyApplicationSupportRoot: applicationSupportRoot,
      availableCapacityOverride: 0,
      allowLegacyApplicationSupportReuse: true
    )
    XCTAssertEqual(legacyResolution.disposition, .compatibleLegacyReuse)
    let selected = legacyResolution.url
    XCTAssertEqual(selected, legacyCache.standardizedFileURL)
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: cachesRoot.appendingPathComponent("GITimeline", isDirectory: true).path
    ))
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: AppFolders.modelCacheCompletionReceiptURL(for: legacyCache).path
    ))
    XCTAssertEqual(try Data(contentsOf: syntheticJournalSentinel), sentinelBytes)

    // This is the same hook used only after Engine.initialize() succeeds. It
    // upgrades the reused cache to the normal strict receipt contract.
    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: selected
    )
    XCTAssertEqual(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        cachesDirectory: cachesRoot,
        legacyApplicationSupportRoot: applicationSupportRoot,
        availableCapacityOverride: 0,
        allowLegacyApplicationSupportReuse: true
      ),
      legacyCache.standardizedFileURL
    )

    try mutateCompletionReceipt(
      for: legacyCache,
      key: "model_sha256",
      value: String(repeating: "f", count: 64)
    )
    XCTAssertThrowsError(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        cachesDirectory: cachesRoot,
        legacyApplicationSupportRoot: applicationSupportRoot,
        availableCapacityOverride: 0,
        allowLegacyApplicationSupportReuse: true
      )
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .invalidModelReceipt)
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: legacyCache.path))
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: cachesRoot.appendingPathComponent("GITimeline", isDirectory: true).path
    ))
    XCTAssertEqual(try Data(contentsOf: syntheticJournalSentinel), sentinelBytes)
    #endif
  }

  func testAppStoreRawPhotoRouteDoesNotReuseConfigurationUnboundLegacyCache() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping raw-photo cache isolation is exercised by the AppStoreTesting configuration.")
    #else
    XCTAssertFalse(
      InferenceConfiguration.appStoreRawImageV1
        .allowsLegacyApplicationSupportCacheReuse
    )
    XCTAssertTrue(
      InferenceConfiguration.deterministicBaseline
        .allowsLegacyApplicationSupportCacheReuse
    )

    let root = temporaryCacheTestRoot("raw-photo-legacy-isolation")
    let cachesRoot = root.appendingPathComponent("SyntheticCaches", isDirectory: true)
    let applicationSupportRoot = root
      .appendingPathComponent("SyntheticApplicationSupport", isDirectory: true)
      .appendingPathComponent("GITimeline", isDirectory: true)
    let legacyCache = applicationSupportRoot
      .appendingPathComponent("Models", isDirectory: true)
      .appendingPathComponent(
        ModelDescriptor.liteRTGemma4E4B.cacheNamespace,
        isDirectory: true
      )
      .appendingPathComponent("Cache", isDirectory: true)
    let legacyCacheFile = legacyCache.appendingPathComponent(
      "program_cache.bin",
      isDirectory: false
    )
    let syntheticJournalSentinel = applicationSupportRoot
      .appendingPathComponent("Images", isDirectory: true)
      .appendingPathComponent("must-remain-unchanged.bin", isDirectory: false)
    let legacyBytes = Data("configuration-unbound legacy cache".utf8)
    let sentinelBytes = Data("synthetic journal sentinel".utf8)
    try FileManager.default.createDirectory(
      at: legacyCache,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: syntheticJournalSentinel.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try legacyBytes.write(to: legacyCacheFile, options: .atomic)
    try sentinelBytes.write(to: syntheticJournalSentinel, options: .atomic)
    defer { try? FileManager.default.removeItem(at: root) }

    let policy = ModelRuntimeEngineCachePolicy.sharedModelCacheForTesting(
      cachesDirectory: cachesRoot,
      availableCapacityOverride: 0,
      legacyApplicationSupportRoot: applicationSupportRoot
    )
    XCTAssertThrowsError(
      try policy.cacheURL(
        for: .liteRTGemma4E4B,
        configuration: .appStoreRawImageV1
      )
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .insufficientModelStorage)
    }
    let compatibleLegacySelection = try policy.cacheSelection(
      for: .liteRTGemma4E4B,
      configuration: .deterministicBaseline
    )
    XCTAssertEqual(compatibleLegacySelection.url, legacyCache.standardizedFileURL)
    XCTAssertEqual(
      compatibleLegacySelection.disposition,
      .compatibleLegacyReuse
    )

    XCTAssertThrowsError(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        cachesDirectory: cachesRoot,
        legacyApplicationSupportRoot: applicationSupportRoot,
        availableCapacityOverride: 0,
        allowLegacyApplicationSupportReuse: false
      )
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .insufficientModelStorage)
    }
    XCTAssertEqual(try Data(contentsOf: legacyCacheFile), legacyBytes)
    XCTAssertEqual(try Data(contentsOf: syntheticJournalSentinel), sentinelBytes)

    let rawPhotoResolution = try AppFolders.modelCacheResolution(
      for: .liteRTGemma4E4B,
      cachesDirectory: cachesRoot,
      legacyApplicationSupportRoot: applicationSupportRoot,
      availableCapacityOverride: .max,
      allowLegacyApplicationSupportReuse: false
    )
    XCTAssertEqual(rawPhotoResolution.disposition, .coldVersionedCache)
    XCTAssertNotEqual(rawPhotoResolution.disposition, .compatibleLegacyReuse)
    let selected = rawPhotoResolution.url
    XCTAssertNotEqual(selected.standardizedFileURL, legacyCache.standardizedFileURL)
    XCTAssertTrue(selected.path.hasPrefix(cachesRoot.path + "/"))
    XCTAssertEqual(selected.lastPathComponent, "Cache")
    XCTAssertEqual(try Data(contentsOf: legacyCacheFile), legacyBytes)
    XCTAssertEqual(try Data(contentsOf: syntheticJournalSentinel), sentinelBytes)
    #endif
  }

  func testCPUShippingCandidateLeavesPriorV3CacheUntouchedAndSelectsProfileBoundV5() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping cache generation isolation is exercised by AppStoreTesting.")
    #else
    let profile = LiteRTEngineCacheProfileV1(
      descriptor: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1
    )
    let cacheSchema = try AppFolders.liteRTCacheSchema(for: profile)
    XCTAssertEqual(
      cacheSchema,
      "litert-\(AppFolders.liteRTLMRevision)-v5-\(try profile.sha256)"
    )
    let root = temporaryCacheTestRoot("cpu-v5-isolation")
    let cachesRoot = root.appendingPathComponent("SyntheticCaches", isDirectory: true)
    let priorSchema = "litert-\(AppFolders.liteRTLMRevision)-v3"
    let priorDescriptorRoot = cachesRoot
      .appendingPathComponent("GITimeline", isDirectory: true)
      .appendingPathComponent("LiteRT", isDirectory: true)
      .appendingPathComponent(priorSchema, isDirectory: true)
      .appendingPathComponent(
        ModelDescriptor.liteRTGemma4E4B.cacheNamespace,
        isDirectory: true
      )
    let priorCache = priorDescriptorRoot.appendingPathComponent(
      "Cache",
      isDirectory: true
    )
    let priorCacheFile = priorCache.appendingPathComponent(
      "program_cache.bin",
      isDirectory: false
    )
    let priorReceipt = priorDescriptorRoot.appendingPathComponent(
      AppFolders.modelCacheCompletionReceiptFilename,
      isDirectory: false
    )
    let priorCacheBytes = Data("synthetic superseded unbound v3 cache".utf8)
    let priorReceiptBytes = Data("synthetic superseded unbound v3 receipt".utf8)
    try FileManager.default.createDirectory(
      at: priorCache,
      withIntermediateDirectories: true
    )
    try priorCacheBytes.write(to: priorCacheFile, options: .atomic)
    try priorReceiptBytes.write(to: priorReceipt, options: .atomic)
    defer { try? FileManager.default.removeItem(at: root) }

    XCTAssertThrowsError(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        configuration: .appStoreRawImageV1,
        cachesDirectory: cachesRoot,
        availableCapacityOverride: 0,
        allowLegacyApplicationSupportReuse: false
      )
    ) { error in
      XCTAssertEqual(error as? GITimelineError, .insufficientModelStorage)
    }
    XCTAssertEqual(try Data(contentsOf: priorCacheFile), priorCacheBytes)
    XCTAssertEqual(try Data(contentsOf: priorReceipt), priorReceiptBytes)

    let selected = try AppFolders.modelCache(
      for: .liteRTGemma4E4B,
      configuration: .appStoreRawImageV1,
      cachesDirectory: cachesRoot,
      availableCapacityOverride: .max,
      allowLegacyApplicationSupportReuse: false
    )
    XCTAssertTrue(selected.path.contains("/\(cacheSchema)/"))
    XCTAssertFalse(selected.path.contains("/\(priorSchema)/"))
    XCTAssertEqual(try Data(contentsOf: priorCacheFile), priorCacheBytes)
    XCTAssertEqual(try Data(contentsOf: priorReceipt), priorReceiptBytes)
    #endif
  }

  func testAppStoreModelCacheReceiptRejectsSameInodeSameSizeMutation() throws {
    #if !APPSTORE_RELEASE_TESTING
    throw XCTSkip("Shipping cache receipt integrity is exercised by the AppStoreTesting configuration.")
    #else
    let root = temporaryCacheTestRoot("same-inode-mutation")
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = try populatedModelCache(in: root)
    let cacheFile = cache.appendingPathComponent("program_cache.bin")
    try AppFolders.recordSuccessfulEngineInitialization(
      for: .liteRTGemma4E4B,
      cacheURL: cache
    )

    let before = try FileManager.default.attributesOfItem(atPath: cacheFile.path)
    let original = try Data(contentsOf: cacheFile)
    let replacement = Data(original.map { $0 ^ 0xff })
    let handle = try FileHandle(forWritingTo: cacheFile)
    try handle.seek(toOffset: 0)
    try handle.write(contentsOf: replacement)
    try handle.synchronize()
    try handle.close()
    let after = try FileManager.default.attributesOfItem(atPath: cacheFile.path)

    XCTAssertEqual(before[.systemFileNumber] as? NSNumber, after[.systemFileNumber] as? NSNumber)
    XCTAssertEqual(before[.size] as? NSNumber, after[.size] as? NSNumber)
    XCTAssertEqual(try Data(contentsOf: cacheFile), replacement)
    assertColdCacheRejected(in: root)
    #endif
  }

  private func temporaryCacheTestRoot(_ suffix: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "GI-appstore-cache-\(suffix)-\(UUID().uuidString)",
      isDirectory: true
    )
  }

  private func populatedModelCache(in root: URL) throws -> URL {
    let cache = try AppFolders.modelCache(
      for: .liteRTGemma4E4B,
      cachesDirectory: root.appendingPathComponent(
        "SyntheticCaches",
        isDirectory: true
      ),
      availableCapacityOverride: .max
    )
    try Data("synthetic compiled cache".utf8).write(
      to: cache.appendingPathComponent("program_cache.bin"),
      options: .atomic
    )
    try Data("synthetic tokenizer cache".utf8).write(
      to: cache.appendingPathComponent("tokenizer_cache.bin"),
      options: .atomic
    )
    return cache
  }

  private func assertColdCacheRejected(
    in root: URL,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try AppFolders.modelCache(
        for: .liteRTGemma4E4B,
        cachesDirectory: root.appendingPathComponent(
          "SyntheticCaches",
          isDirectory: true
        ),
        availableCapacityOverride: 0
      ),
      file: file,
      line: line
    ) { error in
      XCTAssertEqual(
        error as? GITimelineError,
        .insufficientModelStorage,
        file: file,
        line: line
      )
    }
  }

  private func mutateCompletionReceipt(
    for cache: URL,
    key: String,
    value: String
  ) throws {
    let receiptURL = AppFolders.modelCacheCompletionReceiptURL(for: cache)
    let data = try Data(contentsOf: receiptURL)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    object[key] = value
    try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys]
    ).write(to: receiptURL, options: .atomic)
  }
  #endif

  private static func shippingPhotoData() -> Data {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let size = CGSize(width: 64, height: 48)
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.brown.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }.jpegData(compressionQuality: 0.9)!
  }

  private static func hexSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private struct AppStoreInferenceCounts: Equatable, Sendable {
  let prepare: Int
  let analyze: Int
  let repair: Int
}

/// A fail-closed spy: the public manual route is given a seemingly ready
/// provider and automatic-analysis flag so the test proves compile-time/public
/// guards, rather than merely testing an unavailable dependency.
private actor AppStoreCountingInference: TimelineInferenceServing {
  private var prepareCount = 0
  private var analyzeCount = 0
  private var repairCount = 0

  func prepare() async throws -> EnginePreparationResult {
    prepareCount += 1
    return EnginePreparationResult(seconds: 0, reusedCurrentProcessEngine: true)
  }

  func engineState() async -> EngineProcessState { .ready }

  func analyze(draftURL: URL, expectedSHA256: String) async throws -> String {
    analyzeCount += 1
    throw GITimelineError.operationInProgress
  }

  func repair(draftURL: URL, errors: String) async throws -> String {
    repairCount += 1
    throw GITimelineError.operationInProgress
  }

  func discardRepairContext(draftURL: URL) async {}

  func snapshot() -> AppStoreInferenceCounts {
    AppStoreInferenceCounts(
      prepare: prepareCount,
      analyze: analyzeCount,
      repair: repairCount
    )
  }
}
