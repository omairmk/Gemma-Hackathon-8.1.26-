#if DEBUG
import CryptoKit
import Foundation
import GITimelineCore
import SwiftData
import SwiftUI
import UIKit

enum LabDeviceFacts {
  static var hardwareModel: String {
    if let simulatedModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
      !simulatedModel.isEmpty
    {
      return simulatedModel
    }

    var systemInfo = utsname()
    guard uname(&systemInfo) == 0 else { return "UNKNOWN" }
    return Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { identifier, element in
      guard let byte = element.value as? Int8, byte != 0 else { return }
      identifier.append(Character(UnicodeScalar(UInt8(bitPattern: byte))))
    }
  }
}

enum LabBuildFacts {
  // Physical next-step experiments are intentionally kept dirty until their
  // gates pass. This identifies the exact committed base and milestone without
  // exposing signing or device identifiers.
  static let sourceState = "base_commit=b399ef59eea71ea47f44cec7cca12de6dfc0f2c5; dirty=true; milestone=physical-next-steps"
}

enum LabModelState: String, Codable, CaseIterable, Sendable {
  case missing
  case importing
  case verifying
  case verified
  case initializing
  case ready
  case failed
}

struct DeviceInferenceLabStateMachine: Equatable, Sendable {
  private(set) var state: LabModelState = .missing
  private(set) var hasDurableReceipt = false
  private(set) var failureStage: InferenceErrorStage?

  mutating func receiptFound() { hasDurableReceipt = true; state = .verified; failureStage = nil }
  mutating func receiptMissing() { hasDurableReceipt = false; state = .missing; failureStage = nil }
  mutating func beginImport() { state = .importing; failureStage = nil }
  mutating func beginVerification() { state = .verifying; failureStage = nil }
  mutating func beginInitialization() throws {
    guard hasDurableReceipt else { throw GITimelineError.modelNotVerified }
    state = .initializing
    failureStage = nil
  }
  mutating func engineReady() { state = .ready; failureStage = nil }
  mutating func fail(_ stage: InferenceErrorStage) { state = .failed; failureStage = stage }
  mutating func integrityFailure() { hasDurableReceipt = false; state = .failed; failureStage = .hash }
}

enum SyntheticFixture: String, CaseIterable, Identifiable, Codable, Sendable {
  case brown
  case green
  case control

  var id: String { rawValue }
  var title: String {
    switch self {
    case .brown: return "Brown fixture"
    case .green: return "Green fixture"
    case .control: return "Non-target control"
    }
  }
  var resourceName: String {
    switch self {
    case .brown: return "synthetic-brown-clay.svg"
    case .green: return "synthetic-green-clay.svg"
    case .control: return "synthetic-control-geometric.svg"
    }
  }
  var bundledSHA256: String {
    switch self {
    // Xcode's CopyPNGFile strips PNG text chunks. These are the exact bytes
    // loaded from the Debug app bundle, distinct from the tracked source hash.
    case .brown: return "fd8a75195b33e5faaf1e13aae801c97485be5a3a65b40c28c34920b2b8a0ee18"
    case .green: return "d9e82709870c9c18b8e48c5c1477ca4db525447828799d3b0b612f74140a6911"
    case .control: return "9cb76c4d0bc72096e3dc08db468000d1db6a792542d6f1f5a2ec3ad940897fc7"
    }
  }
  var trackedSourceSHA256: String {
    switch self {
    case .brown: return "de793203c6665ecddf280092d2c09154d3e91abd254e078f04ff1c118f3490ca"
    case .green: return "040b71e3de49ae23dfcfed1387a56f32321acf61380a11cf5c6c5bb8a4ba2a73"
    case .control: return "1c51c348c0eab49d94959039de5816dbed8f4725c744271b0b34eb36cf75a9d0"
    }
  }
  var provenance: String {
    switch self {
    case .brown, .green: return "Project synthetic watermarked clay prop; no health data."
    case .control: return "Project-authored watermarked geometric non-target control; no health data."
    }
  }

  func verifiedBundledData(bundle: Bundle = .main) throws -> Data {
    guard let url = bundle.url(forResource: resourceName, withExtension: "png") else {
      throw GITimelineError.syntheticFixtureIntegrity
    }
    let data = try Data(contentsOf: url)
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard hash == bundledSHA256 else { throw GITimelineError.syntheticFixtureIntegrity }
    return data
  }
}

enum LabProbeKind: String, Codable, Sendable {
  case dominantColor = "dominant_color"
  case structuredObservation = "structured_observation"
}

struct LabRunSignature: Equatable, Sendable {
  let descriptorID: String
  let configurationID: String
  let fixtureID: String
  let probeKind: LabProbeKind

  func intendedVariable(comparedTo previous: LabRunSignature?) -> String? {
    guard let previous else {
      return "Baseline establishment; no prior physical run exists in this process."
    }
    var changes: [String] = []
    if descriptorID != previous.descriptorID { changes.append("candidate descriptor") }
    if configurationID != previous.configurationID { changes.append("inference configuration") }
    if fixtureID != previous.fixtureID { changes.append("synthetic fixture") }
    if probeKind != previous.probeKind { changes.append("probe/request kind") }
    switch changes.count {
    case 0:
      return "Repeatability index only; candidate, configuration, fixture, and request kind are unchanged."
    case 1:
      return "Changed exactly one variable from the prior run: \(changes[0])."
    default:
      return nil
    }
  }
}

struct InferenceExperimentEvidence: Codable, Sendable {
  let experimentID: UUID
  let timestamp: Date
  let hypothesis: String
  let intendedVariable: String
  let buildState: String
  let deviceModel: String
  let iOSVersion: String
  let xcodeVersion: String
  let liteRTLMRevision: String
  let descriptor: ModelDescriptor
  let configuration: InferenceConfiguration
  let fixture: SyntheticFixture
  let fixtureFilename: String
  let fixtureDimensions: String
  let bundledFixtureSHA256: String
  let sanitizedImageSHA256: String
  let syntheticProvenance: String
  let requestKind: LabProbeKind
  let requestForm: String
  let engineInitializationSeconds: Double?
  let engineWasReady: Bool
  let inferenceSeconds: Double?
  let rawResponseFilename: String?
  let parserResult: String
  let repairResult: String
  let structuredOutput: VisualObservation?
  let dominantColor: DominantColorResult?
  let highestObservedMemoryBytes: UInt64?
  let memoryMethod: String
  let staleResultRejected: Bool
  let outcome: String
  let failureStage: InferenceErrorStage?
  let failureMessage: String?
  let nextExperiment: String

  var sanitizedSummary: String {
    [
      "run=\(experimentID.uuidString)",
      "candidate=\(descriptor.modelID)@\(descriptor.sourceRevision)",
      "artifact_sha256=\(descriptor.expectedSHA256)",
      "config=\(configuration.label)",
      "fixture=\(fixture.rawValue)",
      "sanitized_sha256=\(sanitizedImageSHA256)",
      "probe=\(requestKind.rawValue)",
      "parser=\(parserResult)",
      "repair=\(repairResult)",
      "outcome=\(outcome)",
      "failure_stage=\(failureStage?.rawValue ?? "none")"
    ].joined(separator: "\n")
  }
}

struct InferenceEvidenceStore {
  func save(_ record: InferenceExperimentEvidence, rawResponse: String?) throws -> URL {
    let root = try AppFolders.inferenceEvidence()
    let stem = record.experimentID.uuidString.lowercased()
    let directory = root.appendingPathComponent(stem, isDirectory: true)
    guard !FileManager.default.fileExists(atPath: directory.path) else { throw GITimelineError.evidenceAlreadyExists }
    let temporary = root.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    do {
      if let rawResponse {
        let rawURL = temporary.appendingPathComponent("response.raw.txt")
        try Data(rawResponse.utf8).write(to: rawURL, options: .atomic)
        try AppFolders.protect(rawURL)
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let jsonURL = temporary.appendingPathComponent("evidence.json")
      try encoder.encode(record).write(to: jsonURL, options: .atomic)
      try AppFolders.protect(jsonURL)
      try AppFolders.protect(temporary)
      try FileManager.default.moveItem(at: temporary, to: directory)
      return directory.appendingPathComponent("evidence.json")
    } catch {
      try? FileManager.default.removeItem(at: temporary)
      throw error
    }
  }
}

struct OvernightSmokeRun: Codable, Sendable {
  let fixture: SyntheticFixture
  let requestKind: LabProbeKind
  let inferenceSeconds: Double?
  let parserResult: String
  let repairResult: String
  let dominantColor: DominantColorResult?
  let structuredOutput: VisualObservation?
  let failureStage: InferenceErrorStage?
  let outcome: String
}

struct OvernightSmokeSummary: Codable, Sendable {
  let startedAt: Date
  let finishedAt: Date
  let descriptor: ModelDescriptor
  let configuration: InferenceConfiguration
  let executionLocation: InferenceExecutionLocation
  let engineInitializationSeconds: Double?
  let runs: [OvernightSmokeRun]
  let brownGreenContrastPassed: Bool
  let nonTargetDistinctPassed: Bool
  let structuredPassCount: Int
  let threeConsecutiveStructuredRunsPassed: Bool
}

enum OvernightPOCError: LocalizedError {
  case failed(String)
  var errorDescription: String? {
    switch self { case .failed(let message): return message }
  }
}

struct OvernightNormalFlowSummary: Codable, Sendable {
  let runID: UUID
  let startedAt: Date
  let finishedAt: Date
  let descriptor: ModelDescriptor
  let configuration: InferenceConfiguration
  let executionLocation: InferenceExecutionLocation
  let selectedFixture: SyntheticFixture
  let modelReceiptVerified: Bool
  let engineReady: Bool
  let imagePrepared: Bool
  let realAnalysisPassed: Bool
  let originalObservation: VisualObservation
  let editedObservation: VisualObservation
  let editPersisted: Bool
  let savePassed: Bool
  let historyEntryFoundImmediately: Bool
  let imageCopyExists: Bool
  let savedProvenance: String
  let savedModelID: String?
  let savedConfiguration: InferenceConfiguration?
  let savedExecutionLocation: InferenceExecutionLocation?
}

struct OvernightNormalFlowRelaunchSummary: Codable, Sendable {
  let verifiedAt: Date
  let runID: UUID
  let entryFoundAfterRelaunch: Bool
  let reviewedObservationReopened: Bool
  let editedObservationPersisted: Bool
  let modelProvenancePersisted: Bool
  let imageReopened: Bool
  let historySummary: String
  let outcome: String
}

@MainActor
final class OvernightNormalFlowRunner {
  static let launchRunArgument = "--run-overnight-normal-flow"
  static let launchVerifyArgument = "--verify-overnight-normal-flow"
  static let defaultsRunIDKey = "OvernightNormalFlowRunID"

  private let runtime: ModelRuntimeCoordinator
  private let context: ModelContext

  init(runtime: ModelRuntimeCoordinator, context: ModelContext) {
    self.runtime = runtime
    self.context = context
  }

  func run() async throws -> URL {
    let startedAt = Date()
    let runID = UUID()
    let priorRunID = UserDefaults.standard.string(forKey: Self.defaultsRunIDKey)
      .flatMap(UUID.init(uuidString:))
    guard let descriptor = ModelCatalog.debugPOCSelection else {
      throw OvernightPOCError.failed("The DEBUG POC descriptor is unavailable.")
    }
    let configuration = await runtime.configurationSnapshot()
    let receiptVerified = (try await runtime.receipt(for: descriptor)) != nil
    guard receiptVerified else { throw GITimelineError.modelNotVerified }
    let service = CoordinatedInferenceService(runtime: runtime, descriptor: descriptor)
    let initiallyReady = await runtime.engineState(descriptor) == .ready
    let imageStore = ImageStore()
    let viewModel = NewEntryViewModel(
      imageStore: imageStore,
      store: EntryStore(context: context),
      inference: service,
      descriptor: descriptor,
      modelVerified: true,
      engineReady: initiallyReady,
      configuration: configuration,
      executionLocation: .currentAppLocal,
      modelImportOperation: { selected in try await self.runtime.importModel(selected) },
      analysisTimeout: .seconds(60),
      autoAnalysisEnabled: true
    )
    if !initiallyReady { await viewModel.prepareModel() }
    guard viewModel.isEngineReady else {
      throw OvernightPOCError.failed("The real Gemma engine did not become ready in the normal flow.")
    }

    let fixture = SyntheticFixture.brown
    viewModel.prepareDemoFixture(fixture)
    guard viewModel.currentDraftURL != nil else {
      throw OvernightPOCError.failed("The verified model and synthetic image did not create a draft.")
    }
    for _ in 0..<900 {
      switch viewModel.flowState {
      case .reviewing, .failed: break
      default:
        try await Task.sleep(for: .milliseconds(100))
        continue
      }
      break
    }
    guard case .reviewing = viewModel.flowState,
      !viewModel.isBusy,
      let original = viewModel.reviewedObservation
    else {
      throw OvernightPOCError.failed("The normal-flow real Gemma analysis did not finish with a review result.")
    }

    let editedForm = original.form == "mushy" ? "smooth_formed" : "mushy"
    viewModel.updateReview {
      VisualObservation(
        imageUsable: $0.imageUsable,
        qualityIssue: $0.qualityIssue,
        apparentBristolType: $0.apparentBristolType,
        apparentColor: $0.apparentColor,
        form: editedForm,
        redAppearingMaterial: $0.redAppearingMaterial,
        blackTarryAppearance: $0.blackTarryAppearance
      )
    }
    guard let edited = viewModel.reviewedObservation else {
      throw OvernightPOCError.failed("The editable review state was lost.")
    }
    let note = "\(DemoDataPolicy.notePrefix) \(runID.uuidString)"
    viewModel.note = note
    guard viewModel.canSave else { throw OvernightPOCError.failed("The reviewed entry could not be saved.") }
    viewModel.save()

    let entries = try context.fetch(FetchDescriptor<EntryRecord>())
    guard let entry = entries.first(where: { $0.note == note }) else {
      throw OvernightPOCError.failed("The saved entry did not appear in the History data source.")
    }
    let provenance = try entry.modelProvenanceJSON
      .flatMap { $0.data(using: .utf8) }
      .map { try JSONDecoder().decode(InferenceProvenanceSnapshot.self, from: $0) }
    let imageExists = entry.imageFilename.flatMap { imageStore.imageURL(filename: $0) }
      .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    let savedObservation = entry.observation
    let summary = OvernightNormalFlowSummary(
      runID: runID,
      startedAt: startedAt,
      finishedAt: Date(),
      descriptor: descriptor,
      configuration: configuration,
      executionLocation: .currentAppLocal,
      selectedFixture: fixture,
      modelReceiptVerified: receiptVerified,
      engineReady: viewModel.isEngineReady,
      imagePrepared: true,
      realAnalysisPassed: true,
      originalObservation: original,
      editedObservation: edited,
      editPersisted: savedObservation == edited,
      savePassed: true,
      historyEntryFoundImmediately: true,
      imageCopyExists: imageExists,
      savedProvenance: entry.provenance,
      savedModelID: entry.modelID,
      savedConfiguration: provenance?.configuration,
      savedExecutionLocation: provenance?.executionLocation
    )
    let url = try save(summary, stem: "normal-flow")
    let allPassed = summary.editPersisted
      && summary.imageCopyExists
      && summary.savedProvenance == EntryProvenance.ai_edited.rawValue
      && summary.savedModelID == descriptor.modelID
      && summary.savedConfiguration == configuration
      && summary.savedExecutionLocation == .currentAppLocal
    guard allPassed else {
      throw OvernightPOCError.failed("One or more real-provider normal-flow acceptance checks failed.")
    }
    if let priorRunID, priorRunID != runID {
      let priorNote = "\(DemoDataPolicy.notePrefix) \(priorRunID.uuidString)"
      if let priorEntry = entries.first(where: { $0.note == priorNote }) {
        try EntryStore(context: context).delete(priorEntry, imageStore: imageStore)
      }
    }
    UserDefaults.standard.set(runID.uuidString, forKey: Self.defaultsRunIDKey)
    return url
  }

  func verifyAfterRelaunch() throws -> URL {
    guard let stored = UserDefaults.standard.string(forKey: Self.defaultsRunIDKey),
      let runID = UUID(uuidString: stored)
    else { throw OvernightPOCError.failed("No prior normal-flow run marker was found.") }
    let note = "\(DemoDataPolicy.notePrefix) \(runID.uuidString)"
    let entries = try context.fetch(FetchDescriptor<EntryRecord>())
    guard let entry = entries.first(where: { $0.note == note }) else {
      throw OvernightPOCError.failed("The synthetic entry was not found after relaunch.")
    }
    let observation = entry.observation
    let provenance = try entry.modelProvenanceJSON
      .flatMap { $0.data(using: .utf8) }
      .map { try JSONDecoder().decode(InferenceProvenanceSnapshot.self, from: $0) }
    let imageExists = entry.imageFilename.flatMap { ImageStore().imageURL(filename: $0) }
      .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    let reviewReopened = observation != nil
    let editPersisted = observation?.form == "mushy"
    let provenancePersisted = provenance?.configuration == .runtimeDefault
      && provenance?.executionLocation == .currentAppLocal
      && entry.modelID == ModelDescriptor.liteRTGemma4E4B.modelID
    let allPassed = reviewReopened && editPersisted && provenancePersisted && imageExists
    let summary = OvernightNormalFlowRelaunchSummary(
      verifiedAt: Date(),
      runID: runID,
      entryFoundAfterRelaunch: true,
      reviewedObservationReopened: reviewReopened,
      editedObservationPersisted: editPersisted,
      modelProvenancePersisted: provenancePersisted,
      imageReopened: imageExists,
      historySummary: observation.map { "Bristol \($0.apparentBristolType.map(String.init) ?? "none") · \($0.apparentColor)" } ?? "No reviewed observation",
      outcome: allPassed ? "PASS" : "FAIL"
    )
    let url = try save(summary, stem: "normal-flow-relaunch")
    guard allPassed else {
      throw OvernightPOCError.failed("One or more relaunch acceptance checks failed.")
    }
    return url
  }

  private func save<T: Encodable>(_ value: T, stem: String) throws -> URL {
    let root = try AppFolders.inferenceEvidence()
    let url = root.appendingPathComponent("\(stem)-\(UUID().uuidString.lowercased()).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(value).write(to: url, options: .atomic)
    try AppFolders.protect(url)
    return url
  }
}

@MainActor
final class DeviceInferenceLabViewModel: ObservableObject {
  @Published private(set) var selectedDescriptor: ModelDescriptor
  @Published private(set) var modelState: LabModelState = .missing
  @Published private(set) var hasDurableReceipt = false
  @Published private(set) var receipt: ModelVerificationReceipt?
  @Published private(set) var selectedFixture: SyntheticFixture?
  @Published private(set) var selectedImage: Image?
  @Published private(set) var sanitizedImageSHA256: String?
  @Published private(set) var fixtureIntegrityLabel = "Not loaded"
  @Published private(set) var fixtureDimensions = "NOT_LOADED"
  @Published private(set) var initializationSeconds: Double?
  @Published private(set) var inferenceSeconds: Double?
  @Published private(set) var parserResult = "NOT_RUN"
  @Published private(set) var repairResult = "NOT_RUN"
  @Published private(set) var validatedObservation: VisualObservation?
  @Published private(set) var dominantColor: DominantColorResult?
  @Published private(set) var rawResponse: String?
  @Published private(set) var attemptID: UUID?
  @Published private(set) var staleResultStatus = "NOT_RUN"
  @Published private(set) var failureStage: InferenceErrorStage?
  @Published private(set) var failureMessage: String?
  @Published private(set) var lastEvidenceURL: URL?
  @Published private(set) var statusMessage: String?

  let configuration = InferenceConfiguration.runtimeDefault
  let candidates = ModelCatalog.debugCandidates

  private var stateMachine = DeviceInferenceLabStateMachine()
  private let runtime: ModelRuntimeCoordinator
  private let imageStore = ImageStore()
  private let evidenceStore = InferenceEvidenceStore()
  private var preparedDraft: PreparedDraft?
  private var activeAttemptID: UUID?
  private var receiptRefreshID: UUID?
  private var lastProbeKind: LabProbeKind?
  private var lastEvidence: InferenceExperimentEvidence?
  private var previousRunSignature: LabRunSignature?

  private var modelFileExists = false

  init(runtime: ModelRuntimeCoordinator) {
    // The owner explicitly chose Gemma 4 E4B as the current DEBUG target.
    // Release selection remains nil until this exact artifact passes phone gates.
    let descriptor = ModelDescriptor.liteRTGemma4E4B
    selectedDescriptor = descriptor
    self.runtime = runtime
  }

  var canImport: Bool { !isBusy && modelState != .ready }
  var canVerify: Bool { !isBusy && modelFileExists }
  var canInitialize: Bool { !isBusy && hasDurableReceipt && modelState != .ready }
  var canRun: Bool { !isBusy && modelState == .ready && preparedDraft != nil }
  var canRepeat: Bool { canRun && lastProbeKind != nil }
  var isBusy: Bool { [.importing, .verifying, .initializing].contains(modelState) || activeAttemptID != nil }
  var canChangeInput: Bool { !isBusy }
  var canCopyEvidence: Bool { lastEvidence != nil }
  var canSaveEvidence: Bool { lastEvidence != nil && lastEvidenceURL == nil }

  func selectCandidate(id: String) {
    guard canChangeInput, let descriptor = candidates.first(where: { $0.id == id }), descriptor != selectedDescriptor else { return }
    let previous = selectedDescriptor
    discardPreparedDraft()
    selectedDescriptor = descriptor
    resetRunDisplay()
    receipt = nil
    modelFileExists = false
    stateMachine.beginVerification()
    publishState()
    Task {
      await runtime.invalidate(previous)
      await refreshReceipt()
    }
  }

  func refreshReceipt() async {
    let descriptor = selectedDescriptor
    let refreshID = UUID()
    receiptRefreshID = refreshID
    stateMachine.beginVerification()
    publishState()
    let fileExists = await runtime.modelExists(for: descriptor)
    do {
      let refreshedReceipt = try await runtime.receipt(for: descriptor)
      guard receiptRefreshID == refreshID, selectedDescriptor.id == descriptor.id else { return }
      modelFileExists = fileExists
      if let refreshedReceipt {
        receipt = refreshedReceipt
        stateMachine.receiptFound()
      } else {
        receipt = nil
        stateMachine.receiptMissing()
      }
    } catch {
      guard receiptRefreshID == refreshID, selectedDescriptor.id == descriptor.id else { return }
      modelFileExists = fileExists
      receipt = nil
      stateMachine.integrityFailure()
      failureStage = .hash
      failureMessage = error.localizedDescription
    }
    publishState()
  }

  func importSelectedModel() async {
    guard canImport else { return }
    receiptRefreshID = nil
    stateMachine.beginImport(); publishState(); statusMessage = "Copying and verifying the exact candidate"
    do {
      let descriptor = selectedDescriptor
      let result = try await runtime.importModel(descriptor)
      receipt = result.receipt
      modelFileExists = true
      stateMachine.receiptFound()
      statusMessage = "Imported copy verified; staged source retained through engine initialization."
    } catch {
      let stage: InferenceErrorStage
      switch error as? GITimelineError {
      case .modelHashMismatch, .modelSizeMismatch, .invalidModelReceipt: stage = .hash
      default: stage = .import
      }
      stateMachine.fail(stage)
      failureMessage = error.localizedDescription
      statusMessage = nil
    }
    publishState()
  }

  func verifyInstalledModel() async {
    guard canVerify else { return }
    receiptRefreshID = nil
    stateMachine.beginVerification(); publishState(); statusMessage = "Rehashing the installed model"
    do {
      let descriptor = selectedDescriptor
      let verified = try await runtime.verifyInstalledModel(descriptor)
      receipt = verified.receipt
      modelFileExists = true
      stateMachine.receiptFound()
      statusMessage = "Installed model hash verified."
    } catch {
      receipt = nil
      stateMachine.integrityFailure()
      await runtime.invalidate(selectedDescriptor)
      failureMessage = error.localizedDescription
      statusMessage = nil
    }
    publishState()
  }

  func initializeEngine() async {
    guard canInitialize else { return }
    do { try stateMachine.beginInitialization() }
    catch { failureMessage = error.localizedDescription; return }
    publishState(); statusMessage = "Initializing the local image-capable engine"
    do {
      let result = try await runtime.prepare(selectedDescriptor)
      initializationSeconds = result.seconds
      stateMachine.engineReady()
      statusMessage = "Engine ready in this process."
    } catch {
      stateMachine.fail((error as? StagedInferenceError)?.stage ?? .engineInitialization)
      failureMessage = error.localizedDescription
      statusMessage = nil
    }
    publishState()
  }

  /// Launch-argument-driven synthetic smoke path for unattended evidence. It
  /// calls the same view-model/runtime methods as the visible lab; no mock or
  /// alternate engine is introduced.
  func runOvernightSmoke() async throws -> URL {
    let startedAt = Date()
    await refreshReceipt()
    guard hasDurableReceipt else { throw GITimelineError.modelNotVerified }
    if modelState != .ready { await initializeEngine() }
    guard modelState == .ready else {
      throw StagedInferenceError(
        stage: failureStage ?? .engineInitialization,
        underlying: GITimelineError.modelNotVerified
      )
    }
    let coldInitializationSeconds = initializationSeconds
    var results: [OvernightSmokeRun] = []

    for fixture in [SyntheticFixture.brown, .green, .control] {
      loadFixture(fixture)
      await runDominantColorProbe()
      results.append(currentAutomationResult(fixture: fixture, kind: .dominantColor))
    }
    for fixture in [SyntheticFixture.control, .brown, .green] {
      loadFixture(fixture)
      await runStructuredObservation()
      results.append(currentAutomationResult(fixture: fixture, kind: .structuredObservation))
    }

    let colors = Dictionary(uniqueKeysWithValues: results.compactMap { run in
      run.requestKind == .dominantColor ? run.dominantColor.map { (run.fixture, $0) } : nil
    })
    let structured = results.filter { $0.requestKind == .structuredObservation }
    let summary = OvernightSmokeSummary(
      startedAt: startedAt,
      finishedAt: Date(),
      descriptor: selectedDescriptor,
      configuration: configuration,
      executionLocation: .currentAppLocal,
      engineInitializationSeconds: coldInitializationSeconds,
      runs: results,
      brownGreenContrastPassed: colors[.brown] == .brown && colors[.green] == .green,
      nonTargetDistinctPassed: colors[.control] == .other,
      structuredPassCount: structured.filter { $0.outcome == "PASS" }.count,
      threeConsecutiveStructuredRunsPassed: structured.count == 3 && structured.allSatisfy { $0.outcome == "PASS" }
    )
    let root = try AppFolders.inferenceEvidence()
    let url = root.appendingPathComponent("overnight-smoke-\(UUID().uuidString.lowercased()).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(summary).write(to: url, options: .atomic)
    try AppFolders.protect(url)
    let allPassed = summary.brownGreenContrastPassed
      && summary.nonTargetDistinctPassed
      && summary.structuredPassCount == 3
      && summary.threeConsecutiveStructuredRunsPassed
      && summary.runs.allSatisfy { $0.outcome == "PASS" }
    guard allPassed else {
      statusMessage = "Overnight smoke failed; evidence saved for review."
      throw OvernightPOCError.failed("One or more real-Gemma smoke acceptance checks failed.")
    }
    statusMessage = "Overnight smoke evidence saved."
    return url
  }

  func loadFixture(_ fixture: SyntheticFixture) {
    guard canChangeInput else { return }
    discardPreparedDraft()
    resetRunDisplay()
    do {
      let data = try fixture.verifiedBundledData()
      let prepared = try imageStore.prepare(data)
      guard let preview = UIImage(contentsOfFile: prepared.url.path) else { throw GITimelineError.invalidImage }
      preparedDraft = prepared
      selectedFixture = fixture
      selectedImage = Image(uiImage: preview)
      sanitizedImageSHA256 = prepared.reference.sha256
      fixtureDimensions = "\(Int(preview.size.width))x\(Int(preview.size.height))"
      fixtureIntegrityLabel = "Bundled SHA-256 verified · \(fixtureDimensions)"
      failureStage = nil
      failureMessage = nil
    } catch {
      failureStage = .imageEncoding
      failureMessage = error.localizedDescription
      fixtureIntegrityLabel = "FAIL"
    }
  }

  func runDominantColorProbe() async { await run(.dominantColor) }
  func runStructuredObservation() async { await run(.structuredObservation) }
  func repeatLast() async { if let lastProbeKind { await run(lastProbeKind) } }

  func copySanitizedSummary() {
    guard let lastEvidence else { return }
    UIPasteboard.general.string = lastEvidence.sanitizedSummary
    statusMessage = "Sanitized summary copied."
  }

  func saveLastEvidence() {
    guard let lastEvidence else { return }
    if lastEvidenceURL != nil {
      statusMessage = "Synthetic-only evidence is already saved for this immutable run."
      return
    }
    do {
      lastEvidenceURL = try evidenceStore.save(lastEvidence, rawResponse: rawResponse)
      statusMessage = "Synthetic-only evidence saved."
    } catch {
      failureStage = .persistence
      failureMessage = error.localizedDescription
    }
  }

  private func run(_ kind: LabProbeKind) async {
    guard canRun, let draft = preparedDraft, let fixture = selectedFixture else { return }
    let signature = LabRunSignature(
      descriptorID: selectedDescriptor.id,
      configurationID: configuration.id,
      fixtureID: fixture.id,
      probeKind: kind
    )
    guard let intendedVariable = signature.intendedVariable(comparedTo: previousRunSignature) else {
      statusMessage = "Run refused: change only one of candidate, configuration, fixture, or request kind at a time."
      return
    }
    let runID = UUID()
    activeAttemptID = runID
    attemptID = runID
    staleResultStatus = "CURRENT"
    lastProbeKind = kind
    parserResult = "NOT_RUN"
    repairResult = "NOT_RUN"
    validatedObservation = nil
    dominantColor = nil
    rawResponse = nil
    failureStage = nil
    failureMessage = nil
    statusMessage = "Running \(kind.rawValue) with a bundled synthetic fixture"
    let clock = ContinuousClock()
    let start = clock.now
    var rawForEvidence: String?
    var stagedFailure: InferenceErrorStage?
    var stagedMessage: String?

    do {
      switch kind {
      case .dominantColor:
        let raw = try await runtime.dominantColorProbe(selectedDescriptor, draftURL: draft.url)
        rawForEvidence = raw
        let parsed = try DominantColorResult.parse(raw)
        guard activeAttemptID == runID else {
          staleResultStatus = "REJECTED"
          throw StagedInferenceError(stage: .generation, underlying: GITimelineError.operationInProgress)
        }
        dominantColor = parsed
        parserResult = "PASS_EXACT_TOKEN"
        repairResult = "NOT_APPLICABLE"
      case .structuredObservation:
        let initial = try await runtime.analyze(selectedDescriptor, draftURL: draft.url)
        rawForEvidence = "INITIAL\n\(initial)"
        let observation: VisualObservation
        do {
          observation = try ObservationParser.parse(initial)
          parserResult = "PASS_STRICT"
          repairResult = "NOT_NEEDED"
        } catch {
          parserResult = "FAIL_STRICT"
          let repaired: String
          do {
            repaired = try await runtime.repair(selectedDescriptor, draftURL: draft.url, errors: error.localizedDescription)
          } catch {
            throw StagedInferenceError(stage: .repair, underlying: error)
          }
          rawForEvidence = "\(rawForEvidence ?? "")\n\nREPAIR\n\(repaired)"
          do { observation = try ObservationParser.parse(repaired) }
          catch { throw StagedInferenceError(stage: .repair, underlying: error) }
          repairResult = "PASS_ONE_REPAIR"
        }
        await runtime.discardRepairContext(selectedDescriptor, draftURL: draft.url)
        guard activeAttemptID == runID else {
          staleResultStatus = "REJECTED"
          throw StagedInferenceError(stage: .generation, underlying: GITimelineError.operationInProgress)
        }
        validatedObservation = observation
      }
      inferenceSeconds = start.duration(to: clock.now).secondsDouble
      rawResponse = rawForEvidence
      statusMessage = "Synthetic probe completed."
    } catch {
      await runtime.discardRepairContext(selectedDescriptor, draftURL: draft.url)
      inferenceSeconds = start.duration(to: clock.now).secondsDouble
      rawResponse = rawForEvidence
      let staged = error as? StagedInferenceError
      stagedFailure = staged?.stage ?? (kind == .structuredObservation ? .parsing : .generation)
      stagedMessage = error.localizedDescription
      failureStage = stagedFailure
      failureMessage = stagedMessage
      statusMessage = nil
    }

    let isCurrent = activeAttemptID == runID
    if activeAttemptID == runID { activeAttemptID = nil }
    if !isCurrent { staleResultStatus = "REJECTED" }
    let rawFilename = rawForEvidence == nil ? nil : "response.raw.txt"
    let record = InferenceExperimentEvidence(
      experimentID: runID,
      timestamp: Date(),
      hypothesis: kind == .dominantColor ? "The configured runtime consumes image pixels and returns the fixture's dominant class." : "The configured runtime returns validator-accepted structured observations from an image-plus-text request.",
      intendedVariable: intendedVariable,
      buildState: LabBuildFacts.sourceState,
      deviceModel: LabDeviceFacts.hardwareModel,
      iOSVersion: UIDevice.current.systemVersion,
      xcodeVersion: "26.6 (17F113)",
      liteRTLMRevision: "2117fc4314670e00047bc8469783f02a68c33f0c",
      descriptor: selectedDescriptor,
      configuration: configuration,
      fixture: fixture,
      fixtureFilename: "\(fixture.resourceName).png",
      fixtureDimensions: fixtureDimensions,
      bundledFixtureSHA256: fixture.bundledSHA256,
      sanitizedImageSHA256: draft.reference.sha256,
      syntheticProvenance: fixture.provenance,
      requestKind: kind,
      requestForm: configuration.imageMessageForm,
      engineInitializationSeconds: initializationSeconds,
      engineWasReady: modelState == .ready,
      inferenceSeconds: inferenceSeconds,
      rawResponseFilename: rawFilename,
      parserResult: parserResult,
      repairResult: repairResult,
      structuredOutput: validatedObservation,
      dominantColor: dominantColor,
      highestObservedMemoryBytes: nil,
      memoryMethod: "NOT_MEASURED; use Instruments or label Debug Navigator values as highest observed sample.",
      staleResultRejected: staleResultStatus == "REJECTED",
      outcome: stagedFailure == nil && isCurrent ? "PASS_PROBE_ONLY" : "FAIL",
      failureStage: stagedFailure,
      failureMessage: stagedFailure.map { "\($0.rawValue): details redacted; see local DEBUG display." },
      nextExperiment: stagedFailure == nil ? "Review this probe against the physical-device gate before changing one variable." : "Classify the recorded failure stage and change exactly one supported variable."
    )
    previousRunSignature = signature
    lastEvidence = record
    do { lastEvidenceURL = try evidenceStore.save(record, rawResponse: rawForEvidence) }
    catch { failureStage = .persistence; failureMessage = error.localizedDescription }
  }

  private func discardPreparedDraft() {
    if let preparedDraft { imageStore.deleteBestEffort(preparedDraft.url) }
    preparedDraft = nil
    selectedFixture = nil
    selectedImage = nil
    sanitizedImageSHA256 = nil
    fixtureIntegrityLabel = "Not loaded"
    fixtureDimensions = "NOT_LOADED"
  }

  private func currentAutomationResult(
    fixture: SyntheticFixture,
    kind: LabProbeKind
  ) -> OvernightSmokeRun {
    OvernightSmokeRun(
      fixture: fixture,
      requestKind: kind,
      inferenceSeconds: inferenceSeconds,
      parserResult: parserResult,
      repairResult: repairResult,
      dominantColor: dominantColor,
      structuredOutput: validatedObservation,
      failureStage: failureStage,
      outcome: failureStage == nil && staleResultStatus == "CURRENT" ? "PASS" : "FAIL"
    )
  }

  private func resetRunDisplay() {
    inferenceSeconds = nil
    parserResult = "NOT_RUN"
    repairResult = "NOT_RUN"
    validatedObservation = nil
    dominantColor = nil
    rawResponse = nil
    attemptID = nil
    staleResultStatus = "NOT_RUN"
    failureStage = nil
    failureMessage = nil
    lastEvidenceURL = nil
    lastEvidence = nil
    statusMessage = nil
    lastProbeKind = nil
  }

  private func publishState() {
    modelState = stateMachine.state
    hasDurableReceipt = stateMachine.hasDurableReceipt
    failureStage = stateMachine.failureStage
  }

}

struct DeviceInferenceLabTab: View {
  let runtime: ModelRuntimeCoordinator
  @State private var viewModel: DeviceInferenceLabViewModel?
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if let viewModel { DeviceInferenceLabView(viewModel: viewModel) }
      else if let errorMessage { ContentUnavailableView("Lab unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage)) }
      else { ProgressView().task {
        let created = DeviceInferenceLabViewModel(runtime: runtime)
        viewModel = created
        await created.refreshReceipt()
      } }
    }
  }
}

struct DeviceInferenceLabView: View {
  @ObservedObject var viewModel: DeviceInferenceLabViewModel

  var body: some View {
    NavigationStack {
      Form {
        Section("Synthetic-only DEBUG lab") {
          Text("Real health photos are disabled here. Every run uses the production importer, sanitizer, inference service, and strict parser.")
            .font(.footnote)
        }
        Section("Candidate") {
          Picker("Exact candidate", selection: Binding(
            get: { viewModel.selectedDescriptor.id },
            set: { viewModel.selectCandidate(id: $0) }
          )) {
            ForEach(viewModel.candidates) { descriptor in Text(descriptor.family).tag(descriptor.id) }
          }
          .disabled(!viewModel.canChangeInput)
          Text(viewModel.selectedDescriptor.modelID).font(.caption).textSelection(.enabled)
          Text("Revision \(viewModel.selectedDescriptor.sourceRevision)").font(.caption2).textSelection(.enabled)
          Text("Expected SHA-256 \(viewModel.selectedDescriptor.shortSHA256)…").font(.caption2).textSelection(.enabled)
          Text(viewModel.configuration.label).font(.caption2)
        }
        Section("Model state") {
          LabeledContent("State", value: viewModel.modelState.rawValue)
          LabeledContent("Durable receipt", value: viewModel.hasDurableReceipt ? "verified" : "absent")
          LabeledContent("Process engine", value: viewModel.modelState == .ready ? "ready" : "not ready")
          Button("Import staged exact artifact") { Task { await viewModel.importSelectedModel() } }.disabled(!viewModel.canImport)
          Button("Explicitly rehash installed copy") { Task { await viewModel.verifyInstalledModel() } }.disabled(!viewModel.canVerify)
          Button("Initialize engine") { Task { await viewModel.initializeEngine() } }.disabled(!viewModel.canInitialize)
          if let seconds = viewModel.initializationSeconds { LabeledContent("Initialization", value: "\(seconds.formatted(.number.precision(.fractionLength(2)))) s") }
        }
        Section("Bundled fixtures") {
          HStack {
            ForEach(SyntheticFixture.allCases) { fixture in
              Button(fixture.title) { viewModel.loadFixture(fixture) }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canChangeInput)
            }
          }
          if let image = viewModel.selectedImage { image.resizable().scaledToFit().frame(maxHeight: 220) }
          LabeledContent("Fixture integrity", value: viewModel.fixtureIntegrityLabel)
          if let hash = viewModel.sanitizedImageSHA256 { Text("Sanitized SHA-256 \(hash)").font(.caption2).textSelection(.enabled) }
        }
        Section("Shared-runtime probes") {
          Button("Run dominant-color probe") { Task { await viewModel.runDominantColorProbe() } }.disabled(!viewModel.canRun)
          Button("Run structured observation") { Task { await viewModel.runStructuredObservation() } }.disabled(!viewModel.canRun)
          Button("Repeat last") { Task { await viewModel.repeatLast() } }.disabled(!viewModel.canRepeat)
          if let attemptID = viewModel.attemptID { LabeledContent("Attempt", value: attemptID.uuidString) }
          LabeledContent("Stale-result status", value: viewModel.staleResultStatus)
          if let seconds = viewModel.inferenceSeconds { LabeledContent("Inference", value: "\(seconds.formatted(.number.precision(.fractionLength(2)))) s") }
          LabeledContent("Strict parser", value: viewModel.parserResult)
          LabeledContent("One repair", value: viewModel.repairResult)
          if let color = viewModel.dominantColor { LabeledContent("Color token", value: color.rawValue) }
          if let observation = viewModel.validatedObservation {
            Text((try? ObservationParser.canonicalJSON(observation)) ?? "Validated output unavailable").font(.caption).textSelection(.enabled)
          }
        }
        if let raw = viewModel.rawResponse {
          Section("Synthetic-only raw response") { Text(raw).font(.caption.monospaced()).textSelection(.enabled) }
        }
        if let stage = viewModel.failureStage {
          Section("Failure") {
            LabeledContent("Stage", value: stage.rawValue)
            Text(viewModel.failureMessage ?? "Unknown failure").font(.caption)
          }
        }
        Section("Sanitized evidence") {
          Button("Copy sanitized summary") { viewModel.copySanitizedSummary() }.disabled(!viewModel.canCopyEvidence)
          Button("Retry saving evidence") { viewModel.saveLastEvidence() }.disabled(!viewModel.canSaveEvidence)
          if let url = viewModel.lastEvidenceURL { ShareLink(item: url) { Label("Export synthetic evidence", systemImage: "square.and.arrow.up") } }
        }
        if let status = viewModel.statusMessage { Section { Text(status).font(.footnote).foregroundStyle(.secondary) } }
      }
      .navigationTitle("Device Inference Lab")
    }
  }
}
#endif

#if DEBUG || HACKATHON_EMBEDDED_GEMMA
import CryptoKit
import Darwin
import Foundation
import GITimelineCore
import ImageIO
import UIKit

/// Fixed, path-free console contract for a Hackathon-only preparation probe.
/// The executable harness is compiled only under `HACKATHON_EMBEDDED_GEMMA`;
/// keeping this argument/marker policy in the shared diagnostic partition lets
/// unit tests prove that the probe cannot run without the existing raw selector.
enum AppStoreRawImageV1PreparationDiagnosticContract {
  enum RegressionFixture: String, CaseIterable, Sendable {
    case brown
    case green
    case control

    var launchArgument: String {
      AppStoreRawImageV1PreparationDiagnosticContract.fixtureLaunchArgumentPrefix
        + rawValue
    }

    var resourceName: String {
      switch self {
      case .brown: return "synthetic-brown-clay.svg"
      case .green: return "synthetic-green-clay.svg"
      case .control: return "synthetic-control-geometric.svg"
      }
    }

    var trackedSourceSHA256: String {
      switch self {
      case .brown:
        return "de793203c6665ecddf280092d2c09154d3e91abd254e078f04ff1c118f3490ca"
      case .green:
        return "040b71e3de49ae23dfcfed1387a56f32321acf61380a11cf5c6c5bb8a4ba2a73"
      case .control:
        return "1c51c348c0eab49d94959039de5816dbed8f4725c744271b0b34eb36cf75a9d0"
      }
    }

    var bundledSHA256: String {
      switch self {
      case .brown:
        return "fd8a75195b33e5faaf1e13aae801c97485be5a3a65b40c28c34920b2b8a0ee18"
      case .green:
        return "d9e82709870c9c18b8e48c5c1477ca4db525447828799d3b0b612f74140a6911"
      case .control:
        return "9cb76c4d0bc72096e3dc08db468000d1db6a792542d6f1f5a2ec3ad940897fc7"
      }
    }

    var sanitizedSHA256: String {
      switch self {
      case .brown:
        return "637a7dd50e4adc9385c999a3ea1e269a4e25e3b78f4a783151f28b4c83540d73"
      case .green:
        return "5bc2acdfb2ada84f03a904f1eba8da37b500557ecbdce6ea88018dba59f3da90"
      case .control:
        return "6d6ab9a6dd5d692bbc53c4a76c71faaa4b32c767c23101a207cf508dfccd1d1d"
      }
    }

    func verifiedBundledData(bundle: Bundle = .main) throws -> Data {
      guard let url = bundle.url(forResource: resourceName, withExtension: "png") else {
        throw GITimelineError.syntheticFixtureIntegrity
      }
      let data = try Data(contentsOf: url)
      let hash = SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }.joined()
      guard hash == bundledSHA256 else {
        throw GITimelineError.syntheticFixtureIntegrity
      }
      return data
    }
  }

  enum GenerationAPI: String, Sendable {
    case streaming = "conversation_send_message_stream_v1"
    case synchronousDiagnostic = "conversation_send_message_sync_v1"
  }

  enum NativeStage: String, CaseIterable, Sendable {
    case engineConfigPlanStart = "engine_config_plan_start"
    case engineConfigPlanPass = "engine_config_plan_pass"
    case engineConstructStart = "engine_construct_start"
    case engineConstructPass = "engine_construct_pass"
    case engineInitializeStart = "engine_initialize_start"
    case engineInitializePass = "engine_initialize_pass"
    case engineInitializeFail = "engine_initialize_fail"
    case conversationCreateStart = "conversation_create_start"
    case conversationCreatePass = "conversation_create_pass"
    case conversationCreateFail = "conversation_create_fail"
    case streamCreateStart = "stream_create_start"
    case streamCreatePass = "stream_create_pass"
    case firstChunk = "first_chunk"
    case synchronousSendStart = "sync_send_start"
    case synchronousSendReturn = "sync_send_return"
    case synchronousCancelRequested = "sync_cancel_requested"
    case synchronousQuarantined = "sync_quarantined"
    case generationFail = "generation_fail"
    case outerDeadlineThreadStarted = "outer_deadline_thread_started"
    case outerDeadlineFired = "outer_deadline_fired"
    case outerDeadlineCaught = "outer_deadline_caught"
  }

  static let launchArgument = "--diagnose-app-store-raw-image-v1-preparation"
  static let gpuMainLaunchArgument =
    "--diagnose-app-store-raw-image-v1-gpu-main-cpu-vision70-ab"
  static let freshCacheLaunchArgument =
    "--diagnose-app-store-raw-image-v1-preparation-fresh-cache"
  static let cachesRootLaunchArgument =
    "--diagnose-app-store-raw-image-v1-preparation-caches-root"
  static let directImageDataLaunchArgument =
    "--diagnose-app-store-raw-image-v1-direct-image-data"
  static let fixtureLaunchArgumentPrefix =
    "--diagnose-app-store-raw-image-v1-preparation-fixture-"
  static let synchronousSendLaunchArgument =
    "--diagnose-app-store-raw-image-v1-sync-send-ab"
  static let markerPrefix = "APP_STORE_RAW_IMAGE_V1_PREPARATION"
  static let sanitizedBrownFixtureSHA256 = RegressionFixture.brown.sanitizedSHA256
  static let descriptor = ModelDescriptor.liteRTGemma4E4B
  static let configuration = InferenceConfiguration.appStoreRawImageV1
  static let gpuMainConfiguration =
    InferenceConfiguration.appStoreRawImageV1GPUMainDiagnostic

  static func cacheProfile(
    for configuration: InferenceConfiguration
  ) -> LiteRTEngineCacheProfileV1 {
    LiteRTEngineCacheProfileV1(
      descriptor: descriptor,
      configuration: configuration
    )
  }

  static func cacheProfileSHA256(
    for configuration: InferenceConfiguration
  ) -> String {
    (try? cacheProfile(for: configuration).sha256) ?? "unavailable"
  }

  static func cacheSchema(
    for configuration: InferenceConfiguration
  ) -> String {
    let profile = cacheProfile(for: configuration)
    return (try? AppFolders.liteRTCacheSchema(for: profile)) ?? "unavailable"
  }
  private static let conflictingLaunchArguments = [
    "--run-embedded-gemma-smoke",
    "--run-embedded-gemma-normal-flow",
    "--verify-embedded-gemma-normal-flow",
    "--run-overnight-normal-flow",
    "--verify-overnight-normal-flow",
    "--run-overnight-gemma-smoke",
    "--run-photo-evaluation-derived-map-iphone",
    "--run-photo-evaluation-raw-image-simulator",
  ]

  static func hasDiagnosticLaunchArgument(in arguments: [String]) -> Bool {
    arguments.contains {
      $0.hasPrefix(launchArgument)
        || $0.hasPrefix(gpuMainLaunchArgument)
        || $0.hasPrefix(directImageDataLaunchArgument)
        || $0.hasPrefix(synchronousSendLaunchArgument)
    }
  }

  static func requestedConfiguration(
    in arguments: [String]
  ) -> InferenceConfiguration? {
    let cpuLaunchCount = arguments.filter { $0 == launchArgument }.count
    let gpuMainLaunchCount = arguments.filter { $0 == gpuMainLaunchArgument }.count
    guard cpuLaunchCount <= 1, gpuMainLaunchCount <= 1,
      cpuLaunchCount + gpuMainLaunchCount == 1
    else { return nil }

    let resolved = InferenceConfiguration.internalDiagnosticConfiguration(
      arguments: arguments
    )
    if cpuLaunchCount == 1, resolved == configuration { return configuration }
    if gpuMainLaunchCount == 1, resolved == gpuMainConfiguration {
      return gpuMainConfiguration
    }
    return nil
  }

  static func requestsDirectImageData(in arguments: [String]) -> Bool {
    arguments.filter { $0 == directImageDataLaunchArgument }.count == 1
  }

  /// Explicit fixture selectors exist only for the bounded Simulator regression.
  /// Preserve the earlier selector-free direct-image command as brown so old
  /// receipts stay reproducible, while rejecting malformed or duplicate flags.
  static func requestedRegressionFixture(
    in arguments: [String]
  ) -> RegressionFixture? {
    let fixtureArguments = arguments.filter {
      $0.hasPrefix(fixtureLaunchArgumentPrefix)
    }
    guard fixtureArguments.count <= 1 else { return nil }
    guard let fixtureArgument = fixtureArguments.first else { return .brown }
    return RegressionFixture.allCases.first {
      $0.launchArgument == fixtureArgument
    }
  }

  static func generationAPI(in arguments: [String]) -> GenerationAPI? {
    let synchronousCount = arguments.filter { $0 == synchronousSendLaunchArgument }.count
    guard synchronousCount <= 1 else { return nil }
    return synchronousCount == 1 ? .synchronousDiagnostic : .streaming
  }

  static func cacheMode(in arguments: [String]) -> ModelRuntimeEngineCacheMode? {
    let freshCount = arguments.filter { $0 == freshCacheLaunchArgument }.count
    let cachesRootCount = arguments.filter { $0 == cachesRootLaunchArgument }.count
    guard freshCount <= 1, cachesRootCount <= 1,
      freshCount + cachesRootCount <= 1
    else { return nil }
    if freshCount == 1 { return .freshIsolatedDiagnosticCache }
    if cachesRootCount == 1 { return .freshCachesRootDiagnosticCache }
    return .sharedModelCache
  }

  static func isValidRequest(in arguments: [String]) -> Bool {
    let directImageCount = arguments.filter {
      $0 == directImageDataLaunchArgument
    }.count
    let fixtureArguments = arguments.filter {
      $0.hasPrefix(fixtureLaunchArgumentPrefix)
    }
    guard directImageCount <= 1, fixtureArguments.count <= 1,
      requestedRegressionFixture(in: arguments) != nil,
      let requestedCacheMode = cacheMode(in: arguments),
      let generationAPI = generationAPI(in: arguments)
    else { return false }
    guard let requestedConfiguration = requestedConfiguration(in: arguments)
    else { return false }
    return !arguments.contains {
        ($0.hasPrefix(launchArgument) && $0 != launchArgument
          && $0 != freshCacheLaunchArgument
          && $0 != cachesRootLaunchArgument
          && !RegressionFixture.allCases.map(\.launchArgument).contains($0))
          || ($0.hasPrefix(gpuMainLaunchArgument) && $0 != gpuMainLaunchArgument)
      }
      && !arguments.contains {
        $0.hasPrefix(directImageDataLaunchArgument)
          && $0 != directImageDataLaunchArgument
      }
      && !arguments.contains {
        $0.hasPrefix(synchronousSendLaunchArgument)
          && $0 != synchronousSendLaunchArgument
      }
      && (directImageCount == 0 || requestedCacheMode == .sharedModelCache)
      && (fixtureArguments.isEmpty
        || (directImageCount == 1
          && requestedConfiguration == configuration
          && generationAPI == .streaming))
      && (generationAPI == .streaming
        || (directImageCount == 1
          && requestedConfiguration == configuration
          && requestedCacheMode == .sharedModelCache))
      && (requestedConfiguration != gpuMainConfiguration
        || requestedCacheMode == .sharedModelCache)
      && !conflictingLaunchArguments.contains(where: arguments.contains)
      && !PhysicalRawImageDiagnosticContract.hasAnyPhysicalRawLaunchArgument(in: arguments)
      && !DerivedMapTuningV3Contract.hasAnyTuningLaunchArgument(in: arguments)
      && !DerivedMapBlindValidationV1Contract.hasAnyLaunchArgument(in: arguments)
  }

  static func configurationMarker(
    _ actual: InferenceConfiguration,
    expected: InferenceConfiguration =
      AppStoreRawImageV1PreparationDiagnosticContract.configuration,
    selectorPresent: Bool,
    cacheMode: ModelRuntimeEngineCacheMode,
    idleTimerDisabled: Bool,
    generationAPI: GenerationAPI = .streaming
  ) -> String {
    let profileSHA256 = cacheProfileSHA256(for: expected)
    let fields = [
      "selector=\(selectorPresent ? "present" : "missing")",
      "config=\(sanitizedToken(actual.id))",
      "expected_config=\(sanitizedToken(expected.id))",
      "config_match=\(actual == expected)",
      "model=\(sanitizedToken(descriptor.id))",
      "revision=\(sanitizedToken(descriptor.sourceRevision))",
      "expected_model_sha256=\(sanitizedToken(descriptor.expectedSHA256))",
      "backend=\(sanitizedToken(actual.engineBackend))",
      "vision=\(sanitizedToken(actual.visionBackend))",
      "context_tokens=\(actual.maxNumTokens)",
      "visual_tokens=\(actual.visualTokenBudget.map(String.init) ?? "-1")",
      "output_cap_tokens=\(BoundedGenerationPolicy.rawPhoto.maximumOutputTokens)",
      "prompt=\(sanitizedToken(actual.promptVersion))",
      "configured_transport=validated_sanitized_jpeg_image_data",
      "generation_api=\(generationAPI.rawValue)",
      "cache_mode=\(sanitizedToken(cacheMode.rawValue))",
      "cache_profile_sha256=\(sanitizedToken(profileSHA256))",
      "cache_schema=\(sanitizedToken(cacheSchema(for: expected)))",
      "idle_timer_disabled=\(idleTimerDisabled)",
    ]
    return "\(markerPrefix)_CONFIG \(fields.joined(separator: " "))"
  }

  static func receiptStartMarker() -> String {
    "\(markerPrefix)_RECEIPT_START model=\(sanitizedToken(descriptor.id)) expected_bytes=\(descriptor.expectedBytes)"
  }

  static func receiptVerifiedMarker(elapsedSeconds: Double) -> String {
    "\(markerPrefix)_RECEIPT_PASS receipt_verified=true location=application_bundle elapsed_ms=\(milliseconds(elapsedSeconds))"
  }

  static func engineInitializationStartMarker(priorState: EngineProcessState) -> String {
    "\(markerPrefix)_ENGINE_INIT_START prior_state=\(sanitizedToken(priorState.label))"
  }

  static func directFixtureReadyMarker(
    fixtureID: String,
    bundledSHA256: String,
    sanitizedSHA256: String
  ) -> String {
    let fields = [
      "fixture=\(sanitizedToken(fixtureID))",
      "fixture_bundle_sha256=\(sanitizedToken(bundledSHA256))",
      "sanitized_sha256=\(sanitizedToken(sanitizedSHA256))",
      "journal_container=ephemeral",
    ]
    return "\(markerPrefix)_FIXTURE_READY \(fields.joined(separator: " "))"
  }

  static func directImageRequestStartMarker(
    generationAPI: GenerationAPI = .streaming
  ) -> String {
    "\(markerPrefix)_IMAGE_REQUEST_START timeout_ms=32000 api=analyze_expected_sha256 transport=validated_sanitized_jpeg_image_data generation_api=\(generationAPI.rawValue) output_cap_tokens=\(BoundedGenerationPolicy.rawPhoto.maximumOutputTokens)"
  }

  static func nativeStageMarker(
    _ stage: NativeStage,
    elapsedSeconds: Double? = nil
  ) -> String {
    let base = "\(markerPrefix)_NATIVE_STAGE stage=\(stage.rawValue)"
    guard let elapsedSeconds else { return base }
    return "\(base) elapsed_ms=\(milliseconds(elapsedSeconds))"
  }

  static func strictSchemaErrorClass(_ error: Error) -> String {
    guard let parserError = error as? ObservationParserError else {
      return "strict_schema_unknown_failure"
    }
    switch parserError {
    case .invalidJSON:
      return "strict_schema_invalid_json"
    case .unknownKeys:
      return "strict_schema_unknown_keys"
    case .missingKeys:
      return "strict_schema_missing_keys"
    case .invalidValue(let field):
      return "strict_schema_invalid_value_\(sanitizedToken(field))"
    case .inconsistent:
      return "strict_schema_inconsistent"
    }
  }

  /// Predeclared synthetic regression expectations. These fixtures exercise
  /// transport, strict parsing, basic color distinction, and non-target
  /// abstention only; they are not clinical or real-photo validation.
  static func regressionExpectationSatisfied(
    _ suggestion: PhotoSuggestionV1,
    for fixture: RegressionFixture
  ) -> Bool {
    guard (try? PhotoSuggestionV1Parser.canonicalJSON(suggestion)) != nil else {
      return false
    }
    switch fixture {
    case .brown:
      return suggestion.imageUsable
        && suggestion.retakeReason == nil
        && suggestion.stoolPresence == .stool
        && ["brown", "light_brown", "dark_brown"].contains(
          suggestion.apparentColor ?? ""
        )
    case .green:
      return suggestion.imageUsable
        && suggestion.retakeReason == nil
        && suggestion.stoolPresence == .stool
        && suggestion.apparentColor == "green"
    case .control:
      return suggestion.imageUsable
        && suggestion.retakeReason == nil
        && suggestion.stoolPresence == .nonStool
        && suggestion.bristolType == nil
        && suggestion.mixedForm == .notSure
        && suggestion.apparentColor == nil
        && suggestion.redAppearingMaterial == .notSure
        && suggestion.blackTarryAppearance == .notSure
    }
  }

  /// Stable, path-free classes for failures that occur before CACHE_READY.
  /// Never render localized descriptions, NSError domains, codes, or URLs in a
  /// physical receipt because those values can contain private container paths.
  static func cachePreparationErrorClass(_ error: Error) -> String {
    if let cacheError = error as? GITimelineError {
      switch cacheError {
      case .evidenceAlreadyExists:
        return "evidence_already_exists"
      case .insufficientModelStorage:
        return "insufficient_model_storage"
      case .invalidModelDescriptor:
        return "invalid_model_descriptor"
      case .invalidModelReceipt:
        return "invalid_model_receipt"
      case .operationInProgress:
        return "operation_in_progress"
      default:
        return "gitimeline_error"
      }
    }
    if error is CancellationError { return "cache_preparation_cancelled" }
    if error is CocoaError || error is POSIXError { return "file_system_error" }
    return "unknown_error"
  }

  static func cacheReadyMarker(
    preparation: ModelRuntimeEngineCachePreparation
  ) -> String {
    let fields = [
      "cache_mode=\(sanitizedToken(preparation.mode.rawValue))",
      "cache_disposition=\(sanitizedToken(preparation.disposition.rawValue))",
      "backup_excluded=\(preparation.backupExcluded)",
      "protection=\(sanitizedToken(preparation.protectionClass))",
    ]
    return "\(markerPrefix)_CACHE_READY \(fields.joined(separator: " "))"
  }

  /// The Simulator filesystem does not expose NSFileProtectionKey even when
  /// the directory-creation helper applies the requested protection class.
  /// Keep the physical-device gate strict while allowing an explicitly
  /// identified Simulator diagnostic to report that platform limitation.
  static func cachePreparationMatches(
    _ preparation: ModelRuntimeEngineCachePreparation,
    expectedMode: ModelRuntimeEngineCacheMode,
    simulatorFileProtectionUnavailable: Bool
  ) -> Bool {
    let expectedProtection = expectedMode == .freshIsolatedDiagnosticCache
      ? "complete"
      : "complete_until_first_user_authentication"
    let protectionMatches = preparation.protectionClass == expectedProtection
      || (simulatorFileProtectionUnavailable
        && preparation.protectionClass == "unavailable")
    return preparation.mode == expectedMode
      && preparation.backupExcluded
      && protectionMatches
  }

  static func terminalMarker(
    passed: Bool,
    receiptSeconds: Double?,
    engineInitializationSeconds: Double?,
    totalSeconds: Double,
    engineState: EngineProcessState,
    cacheMode: ModelRuntimeEngineCacheMode?,
    errorClass: String,
    directImageRequested: Bool = false,
    imageRequestSeconds: Double? = nil,
    strictPhotoSuggestionParsed: Bool = false,
    canonicalOutputSHA256: String? = nil,
    suggestion: PhotoSuggestionV1? = nil,
    regressionFixture: RegressionFixture? = nil,
    regressionExpectationPassed: Bool? = nil,
    configuration: InferenceConfiguration =
      AppStoreRawImageV1PreparationDiagnosticContract.configuration
  ) -> String {
    let fields = [
      "outcome=\(passed ? "PASS" : "FAIL")",
      "receipt_ms=\(milliseconds(receiptSeconds))",
      "engine_init_ms=\(milliseconds(engineInitializationSeconds))",
      "total_ms=\(milliseconds(totalSeconds))",
      "engine_state=\(sanitizedToken(engineState.label))",
      "cache_mode=\(sanitizedToken(cacheMode?.rawValue ?? "invalid"))",
      "configuration=\(sanitizedToken(configuration.id))",
      "cache_profile_sha256=\(sanitizedToken(cacheProfileSHA256(for: configuration)))",
      "cache_schema=\(sanitizedToken(cacheSchema(for: configuration)))",
      "direct_image_requested=\(directImageRequested)",
      "image_request_ms=\(milliseconds(imageRequestSeconds))",
      "transport=validated_sanitized_jpeg_image_data",
      "expected_sha256_validated=\(directImageRequested && strictPhotoSuggestionParsed)",
      "strict_schema=\(strictPhotoSuggestionParsed)",
      "repair_used=false",
      "canonical_output_sha256=\(sanitizedToken(canonicalOutputSHA256 ?? "unavailable"))",
      "regression_fixture=\(sanitizedToken(regressionFixture?.rawValue ?? "unavailable"))",
      "regression_expectation=\(sanitizedToken(regressionExpectationPassed.map { $0 ? "PASS" : "FAIL" } ?? "not_run"))",
      "gemma_image_usable=\(suggestion.map { String($0.imageUsable) } ?? "unavailable")",
      "gemma_stool_presence=\(sanitizedToken(suggestion?.stoolPresence.rawValue ?? "unavailable"))",
      "gemma_bristol_type=\(suggestion?.bristolType.map(String.init) ?? "unavailable")",
      "gemma_mixed_form=\(sanitizedToken(suggestion?.mixedForm.rawValue ?? "unavailable"))",
      "gemma_apparent_color=\(sanitizedToken(suggestion?.apparentColor ?? "unavailable"))",
      "gemma_red_suggestion=\(sanitizedToken(suggestion?.redAppearingMaterial.rawValue ?? "unavailable"))",
      "gemma_black_tarry_suggestion=\(sanitizedToken(suggestion?.blackTarryAppearance.rawValue ?? "unavailable"))",
      "person_answers=unselected",
      "journal_container=ephemeral",
      "error_class=\(sanitizedToken(errorClass))",
    ]
    return "\(markerPrefix)_\(passed ? "PASS" : "FAIL") \(fields.joined(separator: " "))"
  }

  private static func milliseconds(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "-1" }
    // Console telemetry is diagnostic rather than a duration accumulator. Cap
    // the rendered value so a corrupt clock value cannot create an unbounded
    // marker or overflow an integer conversion.
    let cappedSeconds = min(seconds, 86_400)
    return String(Int64((cappedSeconds * 1_000).rounded()))
  }

  private static func sanitizedToken(_ raw: String) -> String {
    var token = ""
    for scalar in raw.unicodeScalars.prefix(96) {
      let value = scalar.value
      let isASCIIAlphaNumeric = (48...57).contains(value)
        || (65...90).contains(value)
        || (97...122).contains(value)
      if isASCIIAlphaNumeric || value == 45 || value == 46 || value == 95 {
        token.append(contentsOf: String(scalar))
      } else {
        token.append("_")
      }
    }
    return token.isEmpty ? "unknown" : token
  }
}

enum PhysicalRawImageDiagnosticPhase: String, Codable, Sendable {
  case started
  case receiptVerified = "receipt_verified"
  case fixturePrepared = "fixture_prepared"
  case engineReady = "engine_ready"
  case imageRequestStarted = "image_request_started"
  case structuredRequestStarted = "structured_request_started"
  case structuredRequestCompleted = "structured_request_completed"
  case structuredRepairStarted = "structured_repair_started"
  case structuredRepairCompleted = "structured_repair_completed"
  case structuredValidationCompleted = "structured_validation_completed"
  case completed
  case failed
}

enum PhysicalRawImageDiagnosticRequest: String, Codable, Equatable, Sendable {
  case brownColorProbe = "brown_color_probe"
  case controlColorProbe = "control_color_probe"
  case controlStructuredObservation = "control_structured_observation"
  case invalidConfiguration = "invalid_configuration"

  var fixtureID: String {
    switch self {
    case .brownColorProbe: return "brown"
    case .controlColorProbe, .controlStructuredObservation: return "control"
    case .invalidConfiguration: return "unknown"
    }
  }

  var requestKind: String {
    switch self {
    case .brownColorProbe, .controlColorProbe: return "dominant_color"
    case .controlStructuredObservation: return "structured_observation"
    case .invalidConfiguration: return "invalid_configuration"
    }
  }
}

enum PhysicalRawImageDiagnosticError: Error, Sendable {
  case wrongPlatform
  case configurationDrift
  case exactBundledReceiptUnavailable
  case unexpectedDominantColor
  case structuredExpectationFailed
  case structuredResultsNotDistinct

  var code: String {
    switch self {
    case .wrongPlatform: return "wrong_platform"
    case .configurationDrift: return "configuration_drift"
    case .exactBundledReceiptUnavailable: return "exact_bundled_receipt_unavailable"
    case .unexpectedDominantColor: return "unexpected_dominant_color"
    case .structuredExpectationFailed: return "structured_expectation_failed"
    case .structuredResultsNotDistinct: return "structured_results_not_distinct"
    }
  }
}

/// Sanitized, path-free checkpoint for the launch-only physical raw-image
/// diagnostic. Constant model/configuration fields prevent the harness from
/// silently drifting onto the disclosed text-only bridge.
struct PhysicalRawImageDiagnosticCheckpoint: Codable, Sendable {
  let runID: UUID
  let startedAt: Date
  let updatedAt: Date
  let phase: PhysicalRawImageDiagnosticPhase
  let stageHistory: [PhysicalRawImageDiagnosticPhase]
  let descriptorID: String
  let modelRevision: String
  let modelSHA256: String
  let configurationID: String
  let engineBackend: String
  let visionBackend: String
  let requestForm: String
  let promptVersion: String
  let visualTokenBudget: Int
  /// Readback of LiteRT-LM's process-global configured value. This does not
  /// independently prove which native vision graph executed.
  let configuredVisualTokenBudgetReadback: Int?
  let maxNumTokens: Int
  let topK: Int
  let topP: Float
  let temperature: Float
  let seed: Int
  let diagnosticRequest: PhysicalRawImageDiagnosticRequest
  let requestKind: String
  let fixtureID: String
  let bundledFixtureSHA256: String
  let sanitizedImageSHA256: String?
  let receiptVerified: Bool
  let preparationSeconds: Double?
  let imageRequestSeconds: Double?
  let totalSeconds: Double?
  let peakResidentMemoryBytes: UInt64?
  let dominantColor: DominantColorResult?
  let structuredInitialSeconds: Double?
  let structuredRepairSeconds: Double?
  let structuredSeconds: Double?
  let repairUsed: Bool
  let strictStructuredParsed: Bool
  let structuredExpectationPassed: Bool
  let structuredObservation: VisualObservation?
  let canonicalObservationSHA256: String?
  let outcome: String
  let failureStage: String?
  let errorClass: String?

  init(
    runID: UUID,
    startedAt: Date,
    updatedAt: Date,
    phase: PhysicalRawImageDiagnosticPhase,
    stageHistory: [PhysicalRawImageDiagnosticPhase],
    diagnosticRequest: PhysicalRawImageDiagnosticRequest = .brownColorProbe,
    fixtureID: String = PhysicalRawImageDiagnosticContract.fixtureID,
    bundledFixtureSHA256: String = PhysicalRawImageDiagnosticContract.bundledBrownFixtureSHA256,
    sanitizedImageSHA256: String? = nil,
    receiptVerified: Bool = false,
    preparationSeconds: Double? = nil,
    imageRequestSeconds: Double? = nil,
    totalSeconds: Double? = nil,
    peakResidentMemoryBytes: UInt64? = nil,
    dominantColor: DominantColorResult? = nil,
    configuredVisualTokenBudgetReadback: Int? = nil,
    structuredInitialSeconds: Double? = nil,
    structuredRepairSeconds: Double? = nil,
    structuredSeconds: Double? = nil,
    repairUsed: Bool = false,
    strictStructuredParsed: Bool = false,
    structuredExpectationPassed: Bool = false,
    structuredObservation: VisualObservation? = nil,
    canonicalObservationSHA256: String? = nil,
    outcome: String = "RUNNING",
    failureStage: String? = nil,
    errorClass: String? = nil
  ) {
    let descriptor = PhysicalRawImageDiagnosticContract.descriptor
    let configuration = PhysicalRawImageDiagnosticContract.configuration
    self.runID = runID
    self.startedAt = startedAt
    self.updatedAt = updatedAt
    self.phase = phase
    self.stageHistory = stageHistory
    descriptorID = descriptor.id
    modelRevision = descriptor.sourceRevision
    modelSHA256 = descriptor.expectedSHA256
    configurationID = configuration.id
    engineBackend = configuration.engineBackend
    visionBackend = configuration.visionBackend
    requestForm = configuration.imageMessageForm
    promptVersion = configuration.promptVersion
    visualTokenBudget = PhysicalRawImageDiagnosticContract.visualTokenBudget
    self.configuredVisualTokenBudgetReadback = configuredVisualTokenBudgetReadback
    maxNumTokens = configuration.maxNumTokens
    topK = configuration.topK
    topP = configuration.topP
    temperature = configuration.temperature
    seed = configuration.seed
    self.diagnosticRequest = diagnosticRequest
    requestKind = diagnosticRequest.requestKind
    self.fixtureID = fixtureID
    self.bundledFixtureSHA256 = bundledFixtureSHA256
    self.sanitizedImageSHA256 = sanitizedImageSHA256
    self.receiptVerified = receiptVerified
    self.preparationSeconds = preparationSeconds
    self.imageRequestSeconds = imageRequestSeconds
    self.totalSeconds = totalSeconds
    self.peakResidentMemoryBytes = peakResidentMemoryBytes
    self.dominantColor = dominantColor
    self.structuredInitialSeconds = structuredInitialSeconds
    self.structuredRepairSeconds = structuredRepairSeconds
    self.structuredSeconds = structuredSeconds
    self.repairUsed = repairUsed
    self.strictStructuredParsed = strictStructuredParsed
    self.structuredExpectationPassed = structuredExpectationPassed
    self.structuredObservation = structuredObservation
    self.canonicalObservationSHA256 = canonicalObservationSHA256
    self.outcome = outcome
    self.failureStage = failureStage
    self.errorClass = errorClass
  }
}

enum PhysicalRawImageDiagnosticContract {
  static let launchArgumentPrefix = "--run-physical-raw-image"
  static let launchArgument = "--run-physical-raw-image-one-shot"
  static let controlLaunchArgument = "--run-physical-raw-image-control-one-shot"
  static let structuredControlLaunchArgument =
    "--run-physical-raw-image-control-structured-one-shot"
  static let allLaunchArguments = [
    launchArgument,
    controlLaunchArgument,
    structuredControlLaunchArgument,
  ]
  static let conflictingCompletionLaunchArguments = [
    "--run-photo-evaluation-derived-map-iphone",
    "--run-photo-evaluation-raw-image-simulator",
    "--run-embedded-gemma-smoke",
    "--run-embedded-gemma-normal-flow",
    "--verify-embedded-gemma-normal-flow",
    "--run-overnight-normal-flow",
    "--verify-overnight-normal-flow",
    "--run-overnight-gemma-smoke",
  ]
  static let markerPrefix = "PHYSICAL_RAW_IMAGE_DIAGNOSTIC"
  static let fixtureID = "brown"
  static let controlFixtureID = "control"
  static let bundledBrownFixtureSHA256 = "fd8a75195b33e5faaf1e13aae801c97485be5a3a65b40c28c34920b2b8a0ee18"
  static let bundledControlFixtureSHA256 = "9cb76c4d0bc72096e3dc08db468000d1db6a792542d6f1f5a2ec3ad940897fc7"
  static let sanitizedControlFixtureSHA256 = "6d6ab9a6dd5d692bbc53c4a76c71faaa4b32c767c23101a207cf508dfccd1d1d"
  static let descriptor = ModelDescriptor.liteRTGemma4E4B
  static let configuration = InferenceConfiguration.physicalGPUCPUVision70
  static let visualTokenBudget = 70

  static func isRequested(in arguments: [String]) -> Bool {
    requestedRequest(in: arguments) != nil
  }

  static func requestedFixtureID(in arguments: [String]) -> String? {
    requestedRequest(in: arguments)?.fixtureID
  }

  static func requestedRequest(in arguments: [String]) -> PhysicalRawImageDiagnosticRequest? {
    guard !arguments.contains(PhysicalRawImageSuiteContract.launchArgument),
      !conflictingCompletionLaunchArguments.contains(where: arguments.contains)
    else { return nil }
    let physicalRawArguments = arguments.filter { $0.hasPrefix(launchArgumentPrefix) }
    guard physicalRawArguments.count == 1,
      let requestedArgument = physicalRawArguments.first,
      allLaunchArguments.contains(requestedArgument)
    else { return nil }
    switch requestedArgument {
    case launchArgument: return .brownColorProbe
    case controlLaunchArgument: return .controlColorProbe
    case structuredControlLaunchArgument: return .controlStructuredObservation
    default: return nil
    }
  }

  static func hasAnyPhysicalRawLaunchArgument(in arguments: [String]) -> Bool {
    arguments.contains { $0.hasPrefix(launchArgumentPrefix) }
  }

  static func structuredControlExpectationSatisfied(_ observation: VisualObservation) -> Bool {
    !observation.imageUsable
      && observation.qualityIssue == "not_target_image"
      && observation.apparentBristolType == nil
      && observation.apparentColor == "unable_to_assess"
      && observation.form == "unable_to_assess"
      && observation.redAppearingMaterial == "unable_to_assess"
      && observation.blackTarryAppearance == "unable_to_assess"
  }

  /// Records only an error type/case, never `localizedDescription`, because a
  /// native error message may contain a private local path or device detail.
  static func sanitizedErrorClass(_ error: Error) -> String {
    if let staged = error as? StagedInferenceError {
      return "StagedInferenceError.\(staged.stage.rawValue)"
    }
    if let diagnostic = error as? PhysicalRawImageDiagnosticError {
      return "PhysicalRawImageDiagnosticError.\(diagnostic.code)"
    }
    if let appError = error as? GITimelineError {
      return "GITimelineError.\(String(describing: appError))"
    }
    return sanitizedToken(String(reflecting: type(of: error)))
  }

  static func consoleMarker(
    for checkpoint: PhysicalRawImageDiagnosticCheckpoint,
    checkpointWritten: Bool
  ) -> String {
    let terminal = checkpoint.outcome == "DIAGNOSTIC_PASS"
      || checkpoint.outcome == "DIAGNOSTIC_PASS_AFTER_REPAIR"
      ? "PASS"
      : "FAIL"
    let contractFieldsStatus = checkpoint.receiptVerified
      ? "runtime_verified"
      : "expected_unverified"
    let fields = [
      "outcome=\(sanitizedToken(checkpoint.outcome))",
      "phase=\(checkpoint.phase.rawValue)",
      "contract_fields=\(contractFieldsStatus)",
      "model=\(sanitizedToken(checkpoint.descriptorID))",
      "revision=\(sanitizedToken(checkpoint.modelRevision))",
      "model_sha256=\(sanitizedToken(checkpoint.modelSHA256))",
      "config=\(sanitizedToken(checkpoint.configurationID))",
      "backend=\(sanitizedToken(checkpoint.engineBackend))",
      "vision=\(sanitizedToken(checkpoint.visionBackend))",
      "prompt=\(sanitizedToken(checkpoint.promptVersion))",
      "visual_tokens_expected=\(checkpoint.visualTokenBudget)",
      "visual_tokens_configured_request=\(checkpoint.configuredVisualTokenBudgetReadback.map(String.init) ?? "-1")",
      "vision_graph_telemetry=unavailable",
      "context_tokens=\(checkpoint.maxNumTokens)",
      "top_k=\(checkpoint.topK)",
      "top_p=\(checkpoint.topP)",
      "temperature=\(checkpoint.temperature)",
      "seed=\(checkpoint.seed)",
      "request_kind=\(sanitizedToken(checkpoint.requestKind))",
      "fixture=\(sanitizedToken(checkpoint.fixtureID))",
      "fixture_bundle_sha256=\(sanitizedToken(checkpoint.bundledFixtureSHA256))",
      "sanitized_sha256=\(sanitizedToken(checkpoint.sanitizedImageSHA256 ?? "unavailable"))",
      "receipt_verified=\(checkpoint.receiptVerified)",
      "prep_ms=\(milliseconds(checkpoint.preparationSeconds))",
      "request_ms=\(milliseconds(checkpoint.imageRequestSeconds))",
      "total_ms=\(milliseconds(checkpoint.totalSeconds))",
      "peak_resident_bytes=\(checkpoint.peakResidentMemoryBytes.map(String.init) ?? "-1")",
      "result=\(checkpoint.dominantColor?.rawValue ?? "none")",
      "structured_initial_ms=\(milliseconds(checkpoint.structuredInitialSeconds))",
      "structured_repair_ms=\(milliseconds(checkpoint.structuredRepairSeconds))",
      "structured_ms=\(milliseconds(checkpoint.structuredSeconds))",
      "repair_used=\(checkpoint.repairUsed)",
      "strict_structured=\(checkpoint.strictStructuredParsed)",
      "structured_expectation=\(checkpoint.structuredExpectationPassed)",
      "observation_sha256=\(sanitizedToken(checkpoint.canonicalObservationSHA256 ?? "unavailable"))",
      "failure_stage=\(sanitizedToken(checkpoint.failureStage ?? "none"))",
      "error_class=\(sanitizedToken(checkpoint.errorClass ?? "none"))",
      "checkpoint=\(checkpointWritten ? "written" : "unavailable")",
    ]
    return "\(markerPrefix)_\(terminal) \(fields.joined(separator: " "))"
  }

  static func fallbackFailureMarker(
    for error: Error,
    request: PhysicalRawImageDiagnosticRequest = .invalidConfiguration
  ) -> String {
    let now = Date()
    let bundledFixtureSHA256: String
    switch request {
    case .brownColorProbe:
      bundledFixtureSHA256 = bundledBrownFixtureSHA256
    case .controlColorProbe, .controlStructuredObservation:
      bundledFixtureSHA256 = bundledControlFixtureSHA256
    case .invalidConfiguration:
      bundledFixtureSHA256 = "unavailable"
    }
    let checkpoint = PhysicalRawImageDiagnosticCheckpoint(
      runID: UUID(),
      startedAt: now,
      updatedAt: now,
      phase: .failed,
      stageHistory: [.started, .failed],
      diagnosticRequest: request,
      fixtureID: request.fixtureID,
      bundledFixtureSHA256: bundledFixtureSHA256,
      outcome: "FAIL",
      failureStage: InferenceErrorStage.persistence.rawValue,
      errorClass: sanitizedErrorClass(error)
    )
    return consoleMarker(for: checkpoint, checkpointWritten: false)
  }

  private static func milliseconds(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "-1" }
    return String(Int64((seconds * 1_000).rounded()))
  }

  private static func sanitizedToken(_ raw: String) -> String {
    var token = ""
    for scalar in raw.unicodeScalars.prefix(120) {
      let value = scalar.value
      let isASCIIAlphaNumeric = (48...57).contains(value)
        || (65...90).contains(value)
        || (97...122).contains(value)
      if isASCIIAlphaNumeric || value == 45 || value == 46 || value == 95 {
        token.append(contentsOf: String(scalar))
      } else {
        token.append("_")
      }
    }
    return token.isEmpty ? "unknown" : token
  }
}

enum PhysicalRawImageSuitePhase: String, Codable, Sendable {
  case started
  case receiptVerified = "receipt_verified"
  case engineReady = "engine_ready"
  case fixtureStarted = "fixture_started"
  case fixturePrepared = "fixture_prepared"
  case colorRequestStarted = "color_request_started"
  case colorRequestCompleted = "color_request_completed"
  case structuredRequestStarted = "structured_request_started"
  case structuredRepairStarted = "structured_repair_started"
  case structuredRepairCompleted = "structured_repair_completed"
  case structuredRequestCompleted = "structured_request_completed"
  case structuredValidationCompleted = "structured_validation_completed"
  case fixtureCompleted = "fixture_completed"
  case completed
  case failed
}

struct PhysicalRawImageSuiteFixtureResult: Codable, Equatable, Sendable {
  let fixtureID: String
  let bundledFixtureSHA256: String
  var sanitizedImageSHA256: String?
  let expectedDominantColor: DominantColorResult
  var dominantColor: DominantColorResult?
  var dominantColorSeconds: Double?
  var structuredInitialSeconds: Double?
  var structuredRepairSeconds: Double?
  var structuredSeconds: Double?
  var repairUsed: Bool
  var strictStructuredParsed: Bool
  var structuredExpectationPassed: Bool
  var structuredObservation: VisualObservation?
  var canonicalObservationSHA256: String?
  var outcome: String
  var failureStage: String?
  var errorClass: String?
}

/// Path-free, raw-response-free state for the three-fixture physical suite.
/// Strict parsed observations and their canonical hashes establish comparison
/// without retaining model prose; field-level expectations prevent mere JSON
/// difference from passing.
struct PhysicalRawImageSuiteCheckpoint: Codable, Sendable {
  let runID: UUID
  let startedAt: Date
  let updatedAt: Date
  let phase: PhysicalRawImageSuitePhase
  let activeFixtureID: String?
  let stageHistory: [String]
  let descriptorID: String
  let modelRevision: String
  let modelSHA256: String
  let configurationID: String
  let engineBackend: String
  let visionBackend: String
  let requestForm: String
  let receiptVerified: Bool
  let preparationSeconds: Double?
  let totalSeconds: Double?
  let peakResidentMemoryBytes: UInt64?
  let fixtureResults: [PhysicalRawImageSuiteFixtureResult]
  let colorPassCount: Int
  let structuredParseCount: Int
  let structuredExpectationPassCount: Int
  let uniqueCanonicalObservationCount: Int
  let outcome: String
  let failureStage: String?
  let errorClass: String?

  init(
    runID: UUID,
    startedAt: Date,
    updatedAt: Date,
    phase: PhysicalRawImageSuitePhase,
    activeFixtureID: String? = nil,
    stageHistory: [String],
    receiptVerified: Bool = false,
    preparationSeconds: Double? = nil,
    totalSeconds: Double? = nil,
    peakResidentMemoryBytes: UInt64? = nil,
    fixtureResults: [PhysicalRawImageSuiteFixtureResult] = [],
    colorPassCount: Int = 0,
    structuredParseCount: Int = 0,
    structuredExpectationPassCount: Int = 0,
    uniqueCanonicalObservationCount: Int = 0,
    outcome: String = "RUNNING",
    failureStage: String? = nil,
    errorClass: String? = nil
  ) {
    let descriptor = PhysicalRawImageSuiteContract.descriptor
    let configuration = PhysicalRawImageSuiteContract.configuration
    self.runID = runID
    self.startedAt = startedAt
    self.updatedAt = updatedAt
    self.phase = phase
    self.activeFixtureID = activeFixtureID
    self.stageHistory = stageHistory
    descriptorID = descriptor.id
    modelRevision = descriptor.sourceRevision
    modelSHA256 = descriptor.expectedSHA256
    configurationID = configuration.id
    engineBackend = configuration.engineBackend
    visionBackend = configuration.visionBackend
    requestForm = configuration.imageMessageForm
    self.receiptVerified = receiptVerified
    self.preparationSeconds = preparationSeconds
    self.totalSeconds = totalSeconds
    self.peakResidentMemoryBytes = peakResidentMemoryBytes
    self.fixtureResults = fixtureResults
    self.colorPassCount = colorPassCount
    self.structuredParseCount = structuredParseCount
    self.structuredExpectationPassCount = structuredExpectationPassCount
    self.uniqueCanonicalObservationCount = uniqueCanonicalObservationCount
    self.outcome = outcome
    self.failureStage = failureStage
    self.errorClass = errorClass
  }
}

enum PhysicalRawImageSuiteContract {
  static let launchArgument = "--run-physical-raw-image-suite"
  static let markerPrefix = "PHYSICAL_RAW_IMAGE_SUITE"
  static let descriptor = ModelDescriptor.liteRTGemma4E4B
  static let configuration = InferenceConfiguration.physicalGPUCPUVision70
  static let fixtureIDs = ["brown", "green", "control"]
  static let bundledFixtureSHA256: [String: String] = [
    "brown": "fd8a75195b33e5faaf1e13aae801c97485be5a3a65b40c28c34920b2b8a0ee18",
    "green": "d9e82709870c9c18b8e48c5c1477ca4db525447828799d3b0b612f74140a6911",
    "control": "9cb76c4d0bc72096e3dc08db468000d1db6a792542d6f1f5a2ec3ad940897fc7",
  ]

  static func isRequested(in arguments: [String]) -> Bool {
    let physicalRawArguments = arguments.filter {
      $0.hasPrefix(PhysicalRawImageDiagnosticContract.launchArgumentPrefix)
    }
    return physicalRawArguments.count == 1
      && physicalRawArguments.first == launchArgument
      && !PhysicalRawImageDiagnosticContract.conflictingCompletionLaunchArguments.contains {
        arguments.contains($0)
      }
  }

  static func structuredExpectationSatisfied(
    fixtureID: String,
    observation: VisualObservation
  ) -> Bool {
    switch fixtureID {
    case "brown":
      return observation.imageUsable
        && ["brown", "light_brown", "dark_brown"].contains(observation.apparentColor)
    case "green":
      return observation.imageUsable && observation.apparentColor == "green"
    case "control":
      return !observation.imageUsable && observation.qualityIssue == "not_target_image"
    default:
      return false
    }
  }

  static func consoleMarker(
    for checkpoint: PhysicalRawImageSuiteCheckpoint,
    checkpointWritten: Bool
  ) -> String {
    let terminal = checkpoint.outcome == "SUITE_PASS" ? "PASS" : "FAIL"
    let colors = checkpoint.fixtureResults
      .map { "\(sanitizedToken($0.fixtureID))-\($0.dominantColor?.rawValue ?? "none")" }
      .joined(separator: "_")
    let fields = [
      "outcome=\(sanitizedToken(checkpoint.outcome))",
      "phase=\(checkpoint.phase.rawValue)",
      "model=\(sanitizedToken(checkpoint.descriptorID))",
      "revision=\(sanitizedToken(checkpoint.modelRevision))",
      "model_sha256=\(sanitizedToken(checkpoint.modelSHA256))",
      "config=\(sanitizedToken(checkpoint.configurationID))",
      "backend=\(sanitizedToken(checkpoint.engineBackend))",
      "vision=\(sanitizedToken(checkpoint.visionBackend))",
      "receipt_verified=\(checkpoint.receiptVerified)",
      "colors=\(sanitizedToken(colors.isEmpty ? "none" : colors))",
      "color_pass=\(checkpoint.colorPassCount)_of_3",
      "structured_parse=\(checkpoint.structuredParseCount)_of_3",
      "structured_expectations=\(checkpoint.structuredExpectationPassCount)_of_3",
      "unique_structured=\(checkpoint.uniqueCanonicalObservationCount)_of_3",
      "prep_ms=\(milliseconds(checkpoint.preparationSeconds))",
      "total_ms=\(milliseconds(checkpoint.totalSeconds))",
      "peak_resident_bytes=\(checkpoint.peakResidentMemoryBytes.map(String.init) ?? "-1")",
      "failure_stage=\(sanitizedToken(checkpoint.failureStage ?? "none"))",
      "error_class=\(sanitizedToken(checkpoint.errorClass ?? "none"))",
      "checkpoint=\(checkpointWritten ? "written" : "unavailable")",
    ]
    return "\(markerPrefix)_\(terminal) \(fields.joined(separator: " "))"
  }

  static func fallbackFailureMarker(for error: Error) -> String {
    let now = Date()
    let checkpoint = PhysicalRawImageSuiteCheckpoint(
      runID: UUID(),
      startedAt: now,
      updatedAt: now,
      phase: .failed,
      stageHistory: ["suite:started", "suite:failed"],
      outcome: "FAIL",
      failureStage: InferenceErrorStage.persistence.rawValue,
      errorClass: PhysicalRawImageDiagnosticContract.sanitizedErrorClass(error)
    )
    return consoleMarker(for: checkpoint, checkpointWritten: false)
  }

  private static func milliseconds(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "-1" }
    return String(Int64((seconds * 1_000).rounded()))
  }

  private static func sanitizedToken(_ raw: String) -> String {
    var token = ""
    for scalar in raw.unicodeScalars.prefix(160) {
      let value = scalar.value
      let isASCIIAlphaNumeric = (48...57).contains(value)
        || (65...90).contains(value)
        || (97...122).contains(value)
      if isASCIIAlphaNumeric || value == 45 || value == 46 || value == 95 {
        token.append(contentsOf: String(scalar))
      } else {
        token.append("_")
      }
    }
    return token.isEmpty ? "unknown" : token
  }
}

struct PhotoSuggestionEvaluationHarnessResult: Sendable {
  let evidenceURL: URL
  let consoleSummary: String
  let terminalStatus: String?

  init(evidenceURL: URL, consoleSummary: String, terminalStatus: String? = nil) {
    self.evidenceURL = evidenceURL
    self.consoleSummary = consoleSummary
    self.terminalStatus = terminalStatus
  }
}

private final class PhotoEvaluationResultRace: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<PhotoSuggestionEvaluationResult, Never>?
  private var resolved = false

  func install(_ continuation: CheckedContinuation<PhotoSuggestionEvaluationResult, Never>) {
    lock.lock()
    self.continuation = continuation
    lock.unlock()
  }

  @discardableResult
  func resolve(_ result: PhotoSuggestionEvaluationResult) -> Bool {
    lock.lock()
    guard !resolved, let continuation else {
      lock.unlock()
      return false
    }
    resolved = true
    self.continuation = nil
    lock.unlock()
    continuation.resume(returning: result)
    return true
  }
}

struct PhotoSuggestionEvaluationCheckpoint: Codable, Sendable {
  let runID: UUID
  let updatedAt: Date
  let route: PhotoEvaluationRoute
  let partition: PhotoEvaluationPartition
  let phase: String
  let pipelineVersion: String?
  let inFlightFixtureID: String?
  let baselineCompleted: Int
  let candidateCompleted: Int
  let expectedPerPipeline: Int
  let failureCode: String?
  let finalEvidenceRelativePath: String?
}

struct PhotoSuggestionEvaluationRunSummary: Codable, Sendable {
  let runID: UUID
  let startedAt: Date
  let finishedAt: Date
  let route: PhotoEvaluationRoute
  let executionLocation: InferenceExecutionLocation
  let partition: PhotoEvaluationPartition
  let manifestVersion: String
  let manifestSHA256: String
  let frozenAtUTC: String
  let frozenBeforeAccuracyCodeChanges: Bool
  let sourceCategory: String
  let containsRealHealthPhotos: Bool
  let fixtureCountPerPipeline: Int
  let descriptor: ModelDescriptor
  let receipt: ModelVerificationReceipt
  let baselineConfiguration: InferenceConfiguration
  let candidateConfiguration: InferenceConfiguration
  let manifestBaselineVersion: String
  let manifestCandidateVersion: String
  let memoryMethod: String
  let resourceLimits: PhotoCandidateResourceLimits
  let baselineResults: [PhotoSuggestionEvaluationResult]
  let candidateResults: [PhotoSuggestionEvaluationResult]
  let baselineStopReason: String?
  let candidateStopReason: String?
  let baselineMetrics: PhotoSuggestionMetrics?
  let candidateMetrics: PhotoSuggestionMetrics?
  let adoptionDecision: PhotoCandidateDecision?
  let completeIdenticalHoldout: Bool
  let recommendation: String
  let evidenceBoundary: String
}

enum PhotoSuggestionEvaluationHarnessError: LocalizedError {
  case wrongPlatform(String)
  case wrongBaselineConfiguration(String)
  case exactModelUnavailable
  case inputMissing
  case manifestHashMismatch
  case manifestPipelineMismatch(String)
  case assetMissing(String)
  case assetHashMismatch(String)
  case assetNotSanitizedSRGB(String)
  case modelReceiptUnavailable

  var errorDescription: String? {
    switch self {
    case .wrongPlatform(let message): return message
    case .wrongBaselineConfiguration(let id): return "The app-scoped baseline configuration was not the required frozen baseline: \(id)."
    case .exactModelUnavailable: return "The exact E4B descriptor is unavailable in this build."
    case .inputMissing: return "Copy the frozen PhotoSuggestionEvaluation manifest and assets into the app Documents container before running."
    case .manifestHashMismatch: return "The local evaluation manifest did not match the frozen SHA-256."
    case .manifestPipelineMismatch(let route): return "The manifest pipeline identifiers did not match the implemented \(route) comparison."
    case .assetMissing(let id): return "The frozen asset is missing for \(id)."
    case .assetHashMismatch(let id): return "The frozen sanitized-image hash did not match for \(id)."
    case .assetNotSanitizedSRGB(let id): return "The frozen asset is not a metadata-free sRGB JPEG for \(id)."
    case .modelReceiptUnavailable: return "The exact model verification receipt was unavailable."
    }
  }
}

/// Launch-only, local evidence harness. It has no ordinary UI entry point and
/// never installs a candidate. The app-scoped coordinator runs the baseline;
/// the candidate changes only the versioned prompt or extractor while reusing
/// that exact prepared session.
protocol PhotoEvaluationSessionRuntime: Sendable {
  func prepare(_ descriptor: ModelDescriptor) async throws -> EnginePreparationResult
  func invalidate(_ descriptor: ModelDescriptor) async
}

extension ModelRuntimeCoordinator: PhotoEvaluationSessionRuntime {}

enum PhotoEvaluationPreparedSession {
  /// Owns exactly one prepare and one final invalidation around both frozen
  /// pipelines. Cleanup is awaited on success and on every catchable failure.
  static func run<Value>(
    runtime: any PhotoEvaluationSessionRuntime,
    descriptor: ModelDescriptor,
    onPreparationFailure: (Error) -> Void = { _ in },
    operation: () async throws -> Value
  ) async throws -> Value {
    do { _ = try await runtime.prepare(descriptor) }
    catch {
      onPreparationFailure(error)
      throw error
    }
    do {
      let value = try await operation()
      await runtime.invalidate(descriptor)
      return value
    } catch {
      await runtime.invalidate(descriptor)
      throw error
    }
  }
}

enum DerivedMapTuningV3Error: Error, Equatable, LocalizedError {
  case launchConflict
  case wrongPlatform
  case manifestHashDrift
  case manifestContractDrift
  case partitionDrift
  case routeDrift
  case configurationDrift
  case modelDrift
  case fixtureSetMismatch
  case sessionPhaseDrift

  var errorDescription: String? {
    switch self {
    case .launchConflict: return "The v3 tuning launch route was missing, duplicated, or combined with another evaluation route."
    case .wrongPlatform: return "DERIVED_MAP_V3_TUNING_IPHONE must run on a physical iPhone."
    case .manifestHashDrift: return "The v3 tuning lane rejected a changed frozen manifest hash."
    case .manifestContractDrift: return "The frozen manifest contract changed; v3 tuning did not run."
    case .partitionDrift: return "The v3 tuning lane did not receive exactly its named tuning fixtures."
    case .routeDrift: return "The v3 tuning lane rejected a different evaluation route."
    case .configurationDrift: return "The v3 tuning baseline or candidate configuration changed."
    case .modelDrift: return "The v3 tuning lane rejected a changed model descriptor or receipt."
    case .fixtureSetMismatch: return "Baseline and v3 tuning metrics did not cover the identical tuning fixtures."
    case .sessionPhaseDrift: return "The v3 tuning baseline and candidate did not run in one ordered prepared session."
    }
  }
}

enum DerivedMapBlindValidationV1Error: Error, Equatable, LocalizedError {
  case launchConflict
  case wrongPlatform
  case inputMissing
  case alreadyConsumed
  case manifestHashDrift
  case manifestContractDrift
  case fixtureSetMismatch
  case assetMissing(String)
  case assetHashMismatch(String)
  case assetNotSanitizedSRGB(String)
  case configurationDrift
  case modelDrift

  var errorDescription: String? {
    switch self {
    case .launchConflict: return "The blind-validation route was missing, duplicated, or combined with another diagnostic route."
    case .wrongPlatform: return "BLIND_VALIDATION_V1_DERIVED_MAP_IPHONE must run on a physical iPhone."
    case .inputMissing: return "Copy the exact GIJournalBlindValidationV1 manifest and assets into the app Documents container."
    case .alreadyConsumed: return "Blind validation v1 is already consumed or previously started in this app container; it cannot be rerun."
    case .manifestHashDrift: return "The one-shot lane rejected a changed blind-validation manifest hash."
    case .manifestContractDrift: return "The fixed blind-validation manifest contract changed."
    case .fixtureSetMismatch: return "Baseline and candidate did not cover the identical fixed blind-validation fixture set."
    case .assetMissing(let id): return "The fixed blind-validation asset is missing for \(id)."
    case .assetHashMismatch(let id): return "The fixed blind-validation asset hash changed for \(id)."
    case .assetNotSanitizedSRGB(let id): return "The blind-validation asset is not a metadata-free sRGB JPEG for \(id)."
    case .configurationDrift: return "The production baseline or frozen v3 validation candidate changed."
    case .modelDrift: return "The blind-validation lane rejected a changed model descriptor or receipt."
    }
  }
}

enum DerivedMapBlindValidationV1OnlyPartition: String, Decodable, Equatable, Sendable {
  case holdout
}

struct DerivedMapBlindValidationV1AssetContract: Decodable, Equatable, Sendable {
  let sourceCategory: String
  let containsRealHealthPhotos: Bool
  let assetFormat: String
  let hashField: String
  let referenceLabelName: String
  let limitations: String

  enum CodingKeys: String, CodingKey {
    case sourceCategory = "source_category"
    case containsRealHealthPhotos = "contains_real_health_photos"
    case assetFormat = "asset_format"
    case hashField = "hash_field"
    case referenceLabelName = "reference_label_name"
    case limitations
  }
}

struct DerivedMapBlindValidationV1Pipeline: Decodable, Equatable, Sendable {
  let baseline: String
  let candidate: String
  let candidateStatus: String

  enum CodingKeys: String, CodingKey {
    case baseline
    case candidate
    case candidateStatus = "candidate_status"
  }
}

struct DerivedMapBlindValidationV1Pipelines: Decodable, Equatable, Sendable {
  let rawImageSimulator: DerivedMapBlindValidationV1Pipeline
  let derivedMapIPhone: DerivedMapBlindValidationV1Pipeline

  enum CodingKeys: String, CodingKey {
    case rawImageSimulator = "RAW_IMAGE_SIMULATOR"
    case derivedMapIPhone = "DERIVED_MAP_IPHONE"
  }
}

struct DerivedMapBlindValidationV1ManifestFixture: Decodable, Equatable, Sendable {
  let id: String
  let partition: DerivedMapBlindValidationV1OnlyPartition
  let asset: String
  let sanitizedImageSHA256: String
  let routes: [PhotoEvaluationRoute]
  let referenceTarget: String
  let referenceBristolType: Int?
  let referenceForm: String
  let expectedAbstention: Bool
  let expectedQualityIssue: String
  let runCondition: String

  enum CodingKeys: String, CodingKey {
    case id
    case partition
    case asset
    case sanitizedImageSHA256 = "sanitized_image_sha256"
    case routes
    case referenceTarget = "reference_target"
    case referenceBristolType = "reference_bristol_type"
    case referenceForm = "reference_form"
    case expectedAbstention = "expected_abstention"
    case expectedQualityIssue = "expected_quality_issue"
    case runCondition = "run_condition"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    guard DerivedMapBlindValidationV1Contract.expectedFixtureIDs.contains(id) else {
      throw DerivedMapBlindValidationV1Error.fixtureSetMismatch
    }
    do { partition = try values.decode(DerivedMapBlindValidationV1OnlyPartition.self, forKey: .partition) }
    catch { throw DerivedMapBlindValidationV1Error.manifestContractDrift }
    asset = try values.decode(String.self, forKey: .asset)
    sanitizedImageSHA256 = try values.decode(String.self, forKey: .sanitizedImageSHA256)
    routes = try values.decode([PhotoEvaluationRoute].self, forKey: .routes)
    referenceTarget = try values.decode(String.self, forKey: .referenceTarget)
    referenceBristolType = try values.decodeIfPresent(Int.self, forKey: .referenceBristolType)
    referenceForm = try values.decode(String.self, forKey: .referenceForm)
    expectedAbstention = try values.decode(Bool.self, forKey: .expectedAbstention)
    expectedQualityIssue = try values.decode(String.self, forKey: .expectedQualityIssue)
    runCondition = try values.decode(String.self, forKey: .runCondition)
  }

  var evaluationFixture: PhotoEvaluationFixture {
    PhotoEvaluationFixture(
      id: id,
      partition: .holdout,
      sanitizedImageSHA256: sanitizedImageSHA256,
      route: .derivedMapIPhone,
      referenceBristolType: referenceBristolType,
      referenceForm: referenceForm,
      expectedAbstention: expectedAbstention,
      expectedImageUsable: expectedQualityIssue == "none",
      expectedQualityIssue: expectedQualityIssue
    )
  }
}

struct DerivedMapBlindValidationV1Manifest: Decodable, Equatable, Sendable {
  let manifestVersion: String
  let frozenAtUTC: String
  let frozenBeforeAccuracyCodeChanges: Bool
  let assetContract: DerivedMapBlindValidationV1AssetContract
  let pipelines: DerivedMapBlindValidationV1Pipelines
  let fixtures: [DerivedMapBlindValidationV1ManifestFixture]

  enum CodingKeys: String, CodingKey {
    case manifestVersion = "manifest_version"
    case frozenAtUTC = "frozen_at_utc"
    case frozenBeforeAccuracyCodeChanges = "frozen_before_accuracy_code_changes"
    case assetContract = "asset_contract"
    case pipelines
    case fixtures
  }

  static func decodeAndValidate(_ data: Data) throws -> Self {
    let manifest: Self
    do { manifest = try JSONDecoder().decode(Self.self, from: data) }
    catch let error as DerivedMapBlindValidationV1Error { throw error }
    catch { throw DerivedMapBlindValidationV1Error.manifestContractDrift }
    try DerivedMapBlindValidationV1Contract.validate(manifest)
    return manifest
  }
}

/// Immutable policy for a single blind run. These acceptance thresholds were
/// fixed before any application result was produced: exact-label improvement;
/// no within-one/group regression; at least 7/8 correct controls without
/// baseline abstention regression; zero invalid, repair, failure, timeout, or
/// crash results; and no >10% maximum-latency or >128 MiB peak-RSS regression.
enum DerivedMapBlindValidationV1Contract {
  struct ExpectedFixture: Equatable, Sendable {
    let id: String
    let sanitizedImageSHA256: String
    let referenceTarget: String
    let referenceBristolType: Int?
    let referenceForm: String
    let expectedAbstention: Bool
    let expectedQualityIssue: String
  }

  static let lane = "DERIVED_MAP_V3_BLIND_VALIDATION_V1_ONE_SHOT"
  static let launchArgumentPrefix = "--run-photo-blind-validation-v3"
  static let launchArgument = "--run-photo-blind-validation-v3-iphone"
  static let inputDirectoryName = "GIJournalBlindValidationV1"
  static let manifestFilename = "blind-validation-v1-manifest.json"
  static let resultsDirectoryName = "blind-validation-v1-results"
  static let checkpointFilename = "blind-validation-v1-checkpoint.json"
  static let consumptionFilename = "blind-validation-v1-consumed.json"
  static let summaryFilename = "blind-validation-v1-summary.json"
  static let runFailedConsoleMarker = "PHOTO_BLIND_VALIDATION_V1_FAIL"
  static let eligibleStatus = "BLIND_VALIDATION_V1_ELIGIBLE_FOR_MANUAL_PROMOTION_REVIEW"
  static let rejectedStatus = "BLIND_VALIDATION_V1_CANDIDATE_REJECTED"
  static let incompleteStatus = "BLIND_VALIDATION_V1_RUN_INCOMPLETE"
  static let frozenManifestSHA256 = "4552ffbfe320c030687957ed64664fcb22acb01f9e1b491eb355d56287fef5be"
  static let frozenManifestVersion = "blind-validation-v1"
  static let frozenAtUTC = "2026-08-03T02:36:15Z"
  static let minimumCorrectControlAbstentions = 7
  static let allowedMaximumLatencyRegressionFraction = 0.10
  static let allowedPeakRSSRegressionBytes: UInt64 = 128 * 1_024 * 1_024
  static let perObservationTimeoutMilliseconds = 120_000.0
  static let evidenceBoundary = "Synthetic, privacy-safe engineering validation of the physical-iPhone derived-map/text-bridge route: Swift inspects each JPEG and Gemma receives text facts only. This is not raw-photo Gemma, clinical-validity, App Store, TestFlight, Airplane Mode, or general offline proof."
  static let baselineConfiguration = InferenceConfiguration.physicalCPUVisualBridge
  static let candidateConfiguration = InferenceConfiguration.physicalCPUVisualBridgeExtractorV3BlindValidationCandidate
  static let descriptor = ModelDescriptor.liteRTGemma4E4B

  static func consoleMarker(for status: String?) throws -> String {
    guard let status,
      [eligibleStatus, rejectedStatus, incompleteStatus].contains(status)
    else { throw DerivedMapBlindValidationV1Error.manifestContractDrift }
    return status
  }

  static let expectedFixtures = [
    ExpectedFixture(id: "bv01-type1-hard-lumps", sanitizedImageSHA256: "87250215cdb7f7c4d91b3fb64a427a7dc7e2cb57d9150a42e82bce33e4e914f4", referenceTarget: "target_like", referenceBristolType: 1, referenceForm: "hard_lumps", expectedAbstention: false, expectedQualityIssue: "none"),
    ExpectedFixture(id: "bv02-type2-lumpy-formed", sanitizedImageSHA256: "698a334376f89d241bf92558e4635736a95bacd6f3fb1624ea3bea9047bcc5c0", referenceTarget: "target_like", referenceBristolType: 2, referenceForm: "lumpy_formed", expectedAbstention: false, expectedQualityIssue: "none"),
    ExpectedFixture(id: "bv03-type3-cracked-formed", sanitizedImageSHA256: "825ee19a6b2dde499042edbdbcc1a79faebb82646baedaa9eed3f9f0af2142a2", referenceTarget: "target_like", referenceBristolType: 3, referenceForm: "cracked_formed", expectedAbstention: false, expectedQualityIssue: "none"),
    ExpectedFixture(id: "bv04-type4-smooth-formed", sanitizedImageSHA256: "7ff29f563d3f9afce7dce2daa8f57d762960c5df85d6cf4181622b74536f1e88", referenceTarget: "target_like", referenceBristolType: 4, referenceForm: "smooth_formed", expectedAbstention: false, expectedQualityIssue: "none"),
    ExpectedFixture(id: "bv05-type5-soft-blobs", sanitizedImageSHA256: "7e0c84e0f339c5cc7cdff20f4004fe5b734462575a60c76af226da9ec0cf7144", referenceTarget: "target_like", referenceBristolType: 5, referenceForm: "soft_blobs", expectedAbstention: false, expectedQualityIssue: "none"),
    ExpectedFixture(id: "bv06-type6-mushy", sanitizedImageSHA256: "4d7509045b738395fd366a2dcf171aff0bc09c321886c473153f7c7bdddf084c", referenceTarget: "target_like", referenceBristolType: 6, referenceForm: "mushy", expectedAbstention: false, expectedQualityIssue: "none"),
    ExpectedFixture(id: "bv07-type7-watery", sanitizedImageSHA256: "58af21df67f8540e46ea1ddeaf1078e18ba79140efa00e40b5472a753ba08e9e", referenceTarget: "target_like", referenceBristolType: 7, referenceForm: "watery", expectedAbstention: false, expectedQualityIssue: "none"),
    ExpectedFixture(id: "bv08-type4-smooth-dark", sanitizedImageSHA256: "d4dfab86b8052eb08740f8c24039a0b367ef45f0bfc120322e543b6e38feb3a2", referenceTarget: "target_like", referenceBristolType: 4, referenceForm: "smooth_formed", expectedAbstention: false, expectedQualityIssue: "none"),
    ExpectedFixture(id: "bv09-control-red-acrylic-beads", sanitizedImageSHA256: "05478fa4c59d00e1dbe60921bf864431c67207fb95e56a3d54cae965d7be2b27", referenceTarget: "non_target", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true, expectedQualityIssue: "not_target_image"),
    ExpectedFixture(id: "bv10-control-brown-wood-blocks", sanitizedImageSHA256: "1b3b6d191edfe62a429664ec492efe7aec12ad1b9247a7ba2c89661c9bf5382a", referenceTarget: "non_target", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true, expectedQualityIssue: "not_target_image"),
    ExpectedFixture(id: "bv11-control-green-polymer-prop", sanitizedImageSHA256: "250bad02ab5efac61849a3320b4b811b2f37c5be78c3fdf1b26a0d979d9c48f4", referenceTarget: "non_target", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true, expectedQualityIssue: "not_target_image"),
    ExpectedFixture(id: "bv12-control-terrazzo-tile", sanitizedImageSHA256: "b1d126e65a69d82e399d3650fc37b626169a27b9b7c905a8b33762fc5dbba46e", referenceTarget: "non_target", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true, expectedQualityIssue: "not_target_image"),
    ExpectedFixture(id: "bv13-control-intentionally-blurred", sanitizedImageSHA256: "8747cf225ef2f93707f2aa37409e6e589f3428bca38c9e0e9eea422df06acefc", referenceTarget: "ambiguous", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true, expectedQualityIssue: "blurred"),
    ExpectedFixture(id: "bv14-control-too-dark", sanitizedImageSHA256: "5f4d6adfef9c12440dbf580c6c6e5e2b196c7b5de5af098f7c6caf7f0621e4b3", referenceTarget: "ambiguous", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true, expectedQualityIssue: "too_dark"),
    ExpectedFixture(id: "bv15-control-obstructed", sanitizedImageSHA256: "72e400cbf8b35570d4402fc1b53cf9f8f8cf90f7c8f5d044c58e253644f9b90e", referenceTarget: "ambiguous", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true, expectedQualityIssue: "obstructed"),
    ExpectedFixture(id: "bv16-control-too-far", sanitizedImageSHA256: "87fa31d5fc492aa084f2ea1fc155d7a0b6d33cb8a88ee0022cf77e33596f5249", referenceTarget: "ambiguous", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true, expectedQualityIssue: "too_far"),
  ]
  static let expectedFixtureIDs = expectedFixtures.map(\.id)

  static func hasAnyLaunchArgument(in arguments: [String]) -> Bool {
    arguments.contains { $0.hasPrefix(launchArgumentPrefix) }
  }

  @MainActor
  static func validateLaunch(arguments: [String]) throws {
    let matches = arguments.filter { $0.hasPrefix(launchArgumentPrefix) }
    let conflicts = [
      PhotoSuggestionEvaluationHarness.derivedMapIPhoneLaunchArgument,
      PhotoSuggestionEvaluationHarness.rawImageSimulatorLaunchArgument,
      DerivedMapTuningV3Contract.launchArgument,
      "--run-embedded-gemma-smoke",
      "--run-embedded-gemma-normal-flow",
      "--verify-embedded-gemma-normal-flow",
      "--run-overnight-normal-flow",
      "--verify-overnight-normal-flow",
      "--run-overnight-gemma-smoke",
    ]
    guard matches == [launchArgument],
      !conflicts.contains(where: arguments.contains),
      !PhysicalRawImageDiagnosticContract.hasAnyPhysicalRawLaunchArgument(in: arguments)
    else { throw DerivedMapBlindValidationV1Error.launchConflict }
  }

  static func validateManifestHash(_ observed: String) throws {
    guard observed == frozenManifestSHA256 else {
      throw DerivedMapBlindValidationV1Error.manifestHashDrift
    }
  }

  static func validate(_ manifest: DerivedMapBlindValidationV1Manifest) throws {
    let unassigned = DerivedMapBlindValidationV1Pipeline(
      baseline: "unassigned-baseline",
      candidate: "unassigned-candidate",
      candidateStatus: "not_evaluated"
    )
    guard manifest.manifestVersion == frozenManifestVersion,
      manifest.frozenAtUTC == frozenAtUTC,
      manifest.frozenBeforeAccuracyCodeChanges,
      manifest.assetContract.sourceCategory == "built-in image generation; synthetic inanimate craft-material proxies",
      !manifest.assetContract.containsRealHealthPhotos,
      manifest.assetContract.assetFormat == "JPEG",
      manifest.assetContract.hashField == "sanitized_image_sha256",
      manifest.assetContract.referenceLabelName == "author_prompt_fixed_intended_label",
      !manifest.assetContract.limitations.isEmpty,
      manifest.pipelines.rawImageSimulator == unassigned,
      manifest.pipelines.derivedMapIPhone == unassigned,
      manifest.fixtures.map(\.id) == expectedFixtureIDs
    else { throw DerivedMapBlindValidationV1Error.manifestContractDrift }

    let expectedRoutes = [PhotoEvaluationRoute.rawImageSimulator, .derivedMapIPhone]
    for (fixture, expected) in zip(manifest.fixtures, expectedFixtures) {
      guard fixture.partition == .holdout,
        fixture.asset == "assets/\(expected.id).jpg",
        fixture.sanitizedImageSHA256 == expected.sanitizedImageSHA256,
        fixture.routes == expectedRoutes,
        fixture.referenceTarget == expected.referenceTarget,
        fixture.referenceBristolType == expected.referenceBristolType,
        fixture.referenceForm == expected.referenceForm,
        fixture.expectedAbstention == expected.expectedAbstention,
        fixture.expectedQualityIssue == expected.expectedQualityIssue,
        fixture.runCondition == "fixed blind holdout; no post-evaluation tuning"
      else { throw DerivedMapBlindValidationV1Error.manifestContractDrift }
      do {
        try BristolFormContract.validate(
          bristolType: fixture.referenceBristolType,
          form: fixture.referenceForm
        )
      } catch { throw DerivedMapBlindValidationV1Error.manifestContractDrift }
    }
  }

  static func validateRuntimeContract(
    baseline: InferenceConfiguration,
    candidate: InferenceConfiguration,
    descriptor observedDescriptor: ModelDescriptor
  ) throws {
    guard baseline == baselineConfiguration,
      candidate == candidateConfiguration,
      baseline.permitsBlindValidationOverride(candidate),
      !baseline.permitsEvaluationOverride(candidate),
      !baseline.permitsTuningOverride(candidate),
      InferenceConfiguration.runtimeDefault != candidate,
      observedDescriptor == descriptor
    else { throw DerivedMapBlindValidationV1Error.configurationDrift }
  }

  static func validateReceipt(_ receipt: ModelVerificationReceipt) throws {
    guard receipt.matches(descriptor),
      receipt.locationKind == .applicationBundle,
      receipt.appBuildIdentity == .current
    else { throw DerivedMapBlindValidationV1Error.modelDrift }
  }

  static func decision(
    baselineResults: [PhotoSuggestionEvaluationResult],
    candidateResults: [PhotoSuggestionEvaluationResult]
  ) throws -> DerivedMapBlindValidationV1Decision {
    try validateResults(baselineResults, pipeline: AnalysisPipelineVersion.derivedMapV1)
    try validateResults(
      candidateResults,
      pipeline: AnalysisPipelineVersion.derivedMapV3BlindValidation
    )
    let baseline = try PhotoSuggestionEvaluator.report(results: baselineResults)
    let candidate = try PhotoSuggestionEvaluator.report(results: candidateResults)
    var reasons = [String]()
    if candidate.exactAgreementCount <= baseline.exactAgreementCount {
      reasons.append("Candidate exact-label agreement did not improve over baseline.")
    }
    if candidate.withinOneAgreementCount < baseline.withinOneAgreementCount {
      reasons.append("Candidate within-one agreement regressed.")
    }
    if candidate.groupedAgreementCount < baseline.groupedAgreementCount {
      reasons.append("Candidate grouped agreement regressed.")
    }
    if candidate.labeledCoverageCount < baseline.labeledCoverageCount {
      reasons.append("Candidate target coverage regressed from baseline.")
    }
    if candidate.correctAbstentionCount < minimumCorrectControlAbstentions {
      reasons.append("Candidate produced fewer than 7 of 8 correct control abstentions.")
    }
    if candidate.correctAbstentionCount < baseline.correctAbstentionCount {
      reasons.append("Candidate control abstention regressed from baseline.")
    }
    let combined = baselineResults + candidateResults
    if combined.contains(where: { !$0.strictJSONValid || $0.parsePath == .invalid }) {
      reasons.append("At least one result was invalid.")
    }
    if combined.contains(where: { $0.parsePath == .repaired }) {
      reasons.append("At least one result required repair.")
    }
    if combined.contains(where: { $0.failureDescription != nil }) {
      reasons.append("At least one result failed.")
    }
    if combined.contains(where: { $0.failureDescription == "stage=timeout" }) {
      reasons.append("At least one result timed out.")
    }
    if combined.contains(where: \.crashed) {
      reasons.append("At least one result crashed.")
    }
    guard let baselineLatency = baseline.maximumLatencyMilliseconds,
      let candidateLatency = candidate.maximumLatencyMilliseconds,
      baseline.latencySampleCount == expectedFixtureIDs.count,
      candidate.latencySampleCount == expectedFixtureIDs.count
    else {
      reasons.append("Latency was not measured for every paired result.")
      return DerivedMapBlindValidationV1Decision(
        eligibleForManualPromotionReview: false,
        reasons: reasons,
        baseline: baseline,
        candidate: candidate
      )
    }
    if candidateLatency >= perObservationTimeoutMilliseconds {
      reasons.append("Candidate latency reached the predeclared observation timeout.")
    }
    let permittedLatency = baselineLatency
      * (1 + allowedMaximumLatencyRegressionFraction)
    if candidateLatency > permittedLatency {
      reasons.append("Candidate maximum latency regressed by more than 10 percent.")
    }
    guard let baselinePeak = baseline.peakMemoryBytes,
      let candidatePeak = candidate.peakMemoryBytes
    else {
      reasons.append("Peak RSS was not measured for both pipelines.")
      return DerivedMapBlindValidationV1Decision(
        eligibleForManualPromotionReview: false,
        reasons: reasons,
        baseline: baseline,
        candidate: candidate
      )
    }
    let (permittedPeak, overflowed) = baselinePeak.addingReportingOverflow(
      allowedPeakRSSRegressionBytes
    )
    if overflowed || candidatePeak > permittedPeak {
      reasons.append("Candidate peak RSS regressed by more than 128 MiB.")
    }
    return DerivedMapBlindValidationV1Decision(
      eligibleForManualPromotionReview: reasons.isEmpty,
      reasons: reasons,
      baseline: baseline,
      candidate: candidate
    )
  }

  private static func validateResults(
    _ results: [PhotoSuggestionEvaluationResult],
    pipeline: String
  ) throws {
    guard results.count == expectedFixtures.count,
      results.map(\.fixture.id) == expectedFixtureIDs,
      results.allSatisfy({
        $0.fixture.partition == .holdout
          && $0.fixture.route == .derivedMapIPhone
          && $0.pipelineVersion == pipeline
          && $0.promptVersion == baselineConfiguration.promptVersion
      })
    else { throw DerivedMapBlindValidationV1Error.fixtureSetMismatch }
    for (result, expected) in zip(results, expectedFixtures) {
      let fixture = result.fixture
      guard fixture.sanitizedImageSHA256 == expected.sanitizedImageSHA256,
        fixture.referenceBristolType == expected.referenceBristolType,
        fixture.referenceForm == expected.referenceForm,
        fixture.expectedAbstention == expected.expectedAbstention,
        fixture.expectedImageUsable == (expected.expectedQualityIssue == "none"),
        fixture.expectedQualityIssue == expected.expectedQualityIssue
      else { throw DerivedMapBlindValidationV1Error.fixtureSetMismatch }
    }
  }
}

struct DerivedMapBlindValidationV1Decision: Codable, Equatable, Sendable {
  let eligibleForManualPromotionReview: Bool
  let reasons: [String]
  let baseline: PhotoSuggestionMetrics
  let candidate: PhotoSuggestionMetrics
}

struct DerivedMapBlindValidationV1Thresholds: Codable, Equatable, Sendable {
  let minimumCorrectControlAbstentions: Int
  let allowedMaximumLatencyRegressionFraction: Double
  let allowedPeakRSSRegressionBytes: UInt64
  let perObservationTimeoutMilliseconds: Double

  static let frozen = Self(
    minimumCorrectControlAbstentions: DerivedMapBlindValidationV1Contract.minimumCorrectControlAbstentions,
    allowedMaximumLatencyRegressionFraction: DerivedMapBlindValidationV1Contract.allowedMaximumLatencyRegressionFraction,
    allowedPeakRSSRegressionBytes: DerivedMapBlindValidationV1Contract.allowedPeakRSSRegressionBytes,
    perObservationTimeoutMilliseconds: DerivedMapBlindValidationV1Contract.perObservationTimeoutMilliseconds
  )
}

struct DerivedMapBlindValidationV1Consumption: Codable, Sendable {
  let lane: String
  let runID: UUID
  let consumedAt: Date
  let manifestSHA256: String
  let fixtureIDs: [String]
  let state: String
}

enum DerivedMapBlindValidationV1ConsumptionStore {
  static func consume(
    runID: UUID,
    at url: URL,
    fileManager: FileManager,
    protect: (URL) throws -> Void
  ) throws {
    guard !fileManager.fileExists(atPath: url.path) else {
      throw DerivedMapBlindValidationV1Error.alreadyConsumed
    }
    let marker = DerivedMapBlindValidationV1Consumption(
      lane: DerivedMapBlindValidationV1Contract.lane,
      runID: runID,
      consumedAt: Date(),
      manifestSHA256: DerivedMapBlindValidationV1Contract.frozenManifestSHA256,
      fixtureIDs: DerivedMapBlindValidationV1Contract.expectedFixtureIDs,
      state: "CONSUMED_BEFORE_FIRST_MODEL_PREPARATION; RERUN_FORBIDDEN"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    do {
      try encoder.encode(marker).write(
        to: url,
        options: .withoutOverwriting
      )
      let handle = try FileHandle(forWritingTo: url)
      try handle.synchronize()
      try handle.close()
      try protect(url)
    } catch {
      if fileManager.fileExists(atPath: url.path) {
        throw DerivedMapBlindValidationV1Error.alreadyConsumed
      }
      throw error
    }
  }
}

struct DerivedMapBlindValidationV1Checkpoint: Codable, Sendable {
  let lane: String
  let runID: UUID
  let updatedAt: Date
  let phase: String
  let pipelineVersion: String?
  let inFlightFixtureID: String?
  let baselineCompleted: Int
  let candidateCompleted: Int
  let expectedPerPipeline: Int
  let failureCode: String?
  let finalEvidenceRelativePath: String?
}

struct DerivedMapBlindValidationV1RunSummary: Codable, Sendable {
  let lane: String
  let runID: UUID
  let startedAt: Date
  let finishedAt: Date
  let route: PhotoEvaluationRoute
  let executionLocation: InferenceExecutionLocation
  let partition: PhotoEvaluationPartition
  let manifestVersion: String
  let manifestSHA256: String
  let frozenAtUTC: String
  let frozenBeforeAccuracyCodeChanges: Bool
  let sourceCategory: String
  let containsRealHealthPhotos: Bool
  let fixtureCountPerPipeline: Int
  let descriptor: ModelDescriptor
  let receipt: ModelVerificationReceipt
  let baselineConfiguration: InferenceConfiguration
  let candidateConfiguration: InferenceConfiguration
  let preparedSessionContract: String
  let memoryMethod: String
  let thresholds: DerivedMapBlindValidationV1Thresholds
  let baselineResults: [PhotoSuggestionEvaluationResult]
  let candidateResults: [PhotoSuggestionEvaluationResult]
  let baselineStopReason: String?
  let candidateStopReason: String?
  let decision: DerivedMapBlindValidationV1Decision?
  let completeIdenticalFixtureSet: Bool
  let status: String
  let evidenceBoundary: String
  let productionDefaultMutation: String
}

private enum PhotoEvaluationFrozenManifestIdentity {
  static let sha256 = "7412c39492b6b9031b4768d1b94722861be346fb36841a1e527dcc6da9c41f20"
}

/// A one-case partition prevents this decoder from representing a holdout
/// fixture. Fixture decoding checks the ID, partition, and route before reading
/// any reference fields, so an injected non-tuning entry fails closed before
/// its labels can enter this process.
enum DerivedMapTuningV3OnlyPartition: String, Decodable, Equatable, Sendable {
  case tuning
}

struct DerivedMapTuningV3ManifestAssetContract: Decodable, Equatable, Sendable {
  let sourceCategory: String
  let containsRealHealthPhotos: Bool
  let assetFormat: String
  let hashField: String
  let limitations: String

  enum CodingKeys: String, CodingKey {
    case sourceCategory = "source_category"
    case containsRealHealthPhotos = "contains_real_health_photos"
    case assetFormat = "asset_format"
    case hashField = "hash_field"
    case limitations
  }
}

struct DerivedMapTuningV3ManifestPipelines: Decodable, Equatable, Sendable {
  let baseline: String
  let candidate: String
}

struct DerivedMapTuningV3ManifestFixture: Decodable, Equatable, Sendable {
  let id: String
  let partition: DerivedMapTuningV3OnlyPartition
  let route: PhotoEvaluationRoute
  let asset: String
  let sanitizedImageSHA256: String
  let referenceBristolType: Int?
  let referenceForm: String
  let expectedAbstention: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case partition
    case route
    case asset
    case sanitizedImageSHA256 = "sanitized_image_sha256"
    case referenceBristolType = "reference_bristol_type"
    case referenceForm = "reference_form"
    case expectedAbstention = "expected_abstention"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    guard DerivedMapTuningV3Contract.expectedFixtureIDs.contains(id) else {
      throw DerivedMapTuningV3Error.fixtureSetMismatch
    }
    do { partition = try values.decode(DerivedMapTuningV3OnlyPartition.self, forKey: .partition) }
    catch { throw DerivedMapTuningV3Error.partitionDrift }
    do { route = try values.decode(PhotoEvaluationRoute.self, forKey: .route) }
    catch { throw DerivedMapTuningV3Error.routeDrift }
    guard route == DerivedMapTuningV3Contract.route else {
      throw DerivedMapTuningV3Error.routeDrift
    }

    // Reference fields are intentionally decoded only after the fixture has
    // proven that it belongs to this exact tuning-only route.
    asset = try values.decode(String.self, forKey: .asset)
    sanitizedImageSHA256 = try values.decode(String.self, forKey: .sanitizedImageSHA256)
    referenceBristolType = try values.decodeIfPresent(Int.self, forKey: .referenceBristolType)
    referenceForm = try values.decode(String.self, forKey: .referenceForm)
    expectedAbstention = try values.decode(Bool.self, forKey: .expectedAbstention)
  }

  var evaluationFixture: PhotoEvaluationFixture {
    PhotoEvaluationFixture(
      id: id,
      partition: .tuning,
      sanitizedImageSHA256: sanitizedImageSHA256,
      route: route,
      referenceBristolType: referenceBristolType,
      referenceForm: referenceForm,
      expectedAbstention: expectedAbstention
    )
  }
}

/// Dedicated decoder for the separately frozen v3 tuning projection. Its type
/// graph has no holdout partition, holdout pipeline, or holdout-label API.
struct DerivedMapTuningV3Manifest: Decodable, Equatable, Sendable {
  let manifestVersion: String
  let frozenAtUTC: String
  let lane: String
  let route: PhotoEvaluationRoute
  let partition: DerivedMapTuningV3OnlyPartition
  let assetContract: DerivedMapTuningV3ManifestAssetContract
  let pipelines: DerivedMapTuningV3ManifestPipelines
  let fixtures: [DerivedMapTuningV3ManifestFixture]

  enum CodingKeys: String, CodingKey {
    case manifestVersion = "manifest_version"
    case frozenAtUTC = "frozen_at_utc"
    case lane
    case route
    case partition
    case assetContract = "asset_contract"
    case pipelines
    case fixtures
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    manifestVersion = try values.decode(String.self, forKey: .manifestVersion)
    frozenAtUTC = try values.decode(String.self, forKey: .frozenAtUTC)
    lane = try values.decode(String.self, forKey: .lane)
    do { route = try values.decode(PhotoEvaluationRoute.self, forKey: .route) }
    catch { throw DerivedMapTuningV3Error.routeDrift }
    guard route == DerivedMapTuningV3Contract.route else {
      throw DerivedMapTuningV3Error.routeDrift
    }
    do { partition = try values.decode(DerivedMapTuningV3OnlyPartition.self, forKey: .partition) }
    catch { throw DerivedMapTuningV3Error.partitionDrift }
    assetContract = try values.decode(
      DerivedMapTuningV3ManifestAssetContract.self,
      forKey: .assetContract
    )
    pipelines = try values.decode(DerivedMapTuningV3ManifestPipelines.self, forKey: .pipelines)

    guard manifestVersion == DerivedMapTuningV3Contract.frozenManifestVersion,
      frozenAtUTC == DerivedMapTuningV3Contract.frozenAtUTC,
      lane == DerivedMapTuningV3Contract.lane,
      assetContract.sourceCategory == "synthetic_non_health",
      !assetContract.containsRealHealthPhotos,
      assetContract.assetFormat == DerivedMapTuningV3Contract.assetFormat,
      assetContract.hashField == "sanitized_image_sha256",
      !assetContract.limitations.isEmpty,
      pipelines.baseline == AnalysisPipelineVersion.derivedMapV1,
      pipelines.candidate == AnalysisPipelineVersion.derivedMapV3Tuning
    else { throw DerivedMapTuningV3Error.manifestContractDrift }

    fixtures = try values.decode([DerivedMapTuningV3ManifestFixture].self, forKey: .fixtures)
    try Self.validateFixtures(fixtures)
  }

  static func decodeAndValidate(_ data: Data) throws -> DerivedMapTuningV3Manifest {
    do { return try JSONDecoder().decode(DerivedMapTuningV3Manifest.self, from: data) }
    catch let contractError as DerivedMapTuningV3Error { throw contractError }
    catch { throw DerivedMapTuningV3Error.manifestContractDrift }
  }

  private static func validateFixtures(
    _ fixtures: [DerivedMapTuningV3ManifestFixture]
  ) throws {
    guard fixtures.map(\.id) == DerivedMapTuningV3Contract.expectedFixtureIDs else {
      throw DerivedMapTuningV3Error.fixtureSetMismatch
    }
    for (fixture, expected) in zip(fixtures, DerivedMapTuningV3Contract.expectedFixtures) {
      guard fixture.partition == .tuning,
        fixture.route == DerivedMapTuningV3Contract.route,
        fixture.id == expected.id,
        fixture.asset == "assets/\(expected.id).jpg",
        fixture.sanitizedImageSHA256 == expected.sanitizedImageSHA256,
        fixture.referenceBristolType == expected.referenceBristolType,
        fixture.referenceForm == expected.referenceForm,
        fixture.expectedAbstention == expected.expectedAbstention
      else { throw DerivedMapTuningV3Error.manifestContractDrift }
      do {
        try BristolFormContract.validate(
          bristolType: fixture.referenceBristolType,
          form: fixture.referenceForm
        )
      } catch {
        throw DerivedMapTuningV3Error.manifestContractDrift
      }
    }
  }
}

/// Compile-time DEBUG/HACKATHON-only policy for engineering iteration. It
/// consumes a separately frozen tuning-only manifest and can select only the
/// exact t01-t12 derived-map fixtures.
/// It has no comparator, decision, recommendation, or default-install API.
enum DerivedMapTuningV3Contract {
  struct ExpectedFixture: Equatable, Sendable {
    let id: String
    let sanitizedImageSHA256: String
    let referenceBristolType: Int?
    let referenceForm: String
    let expectedAbstention: Bool
  }

  static let lane = "DERIVED_MAP_V3_TUNING_ONLY"
  static let launchArgumentPrefix = "--run-photo-tuning-derived-map-v3"
  static let launchArgument = "--run-photo-tuning-derived-map-v3-iphone"
  static let manifestFilename = "tuning-v3-manifest.json"
  static let route = PhotoEvaluationRoute.derivedMapIPhone
  static let partition = PhotoEvaluationPartition.tuning
  static let runCompleteConsoleMarker = "PHOTO_TUNING_V3_RUN_COMPLETE"
  static let metricsRecordedStatus = "TUNING_V3_ENGINEERING_METRICS_RECORDED"
  static let incompleteRunStatus = "TUNING_V3_RUN_INCOMPLETE"
  static let frozenManifestSHA256 = "e47384990b74fbc182519552422d5141260c7d43beecd5e4739ab2863a488f55"
  static let frozenManifestVersion = "gi-derived-map-v3-tuning-manifest-v1"
  static let frozenAtUTC = "2026-08-03T01:37:10Z"
  static let assetFormat = "metadata-stripped JPEG, quality 0.80, embedded sRGB IEC61966-2.1"
  static let expectedFixtures = [
    ExpectedFixture(id: "t01-type1-brown-lumps", sanitizedImageSHA256: "e83ba8778ea30d947cca0802dc22342547c001961d6d19b5bb82b3d8d07cd05e", referenceBristolType: 1, referenceForm: "hard_lumps", expectedAbstention: false),
    ExpectedFixture(id: "t02-type3-cracked-formed", sanitizedImageSHA256: "7ab0aef66c9dd7e1723a17271be858c0b762ab9c32795c3b1473fd19e28ef116", referenceBristolType: 3, referenceForm: "cracked_formed", expectedAbstention: false),
    ExpectedFixture(id: "t03-type5-soft-blobs", sanitizedImageSHA256: "984910bae71e8753d9904ee20e46fa7e00719bafc83278ce45fd06e84a2e4403", referenceBristolType: 5, referenceForm: "soft_blobs", expectedAbstention: false),
    ExpectedFixture(id: "t04-type7-watery-pool", sanitizedImageSHA256: "769a6ef45f1b7cfc641d59f3a91e32b731b4442fe350ed76a348ae931b309949", referenceBristolType: 7, referenceForm: "watery", expectedAbstention: false),
    ExpectedFixture(id: "t05-mixed-hard-loose", sanitizedImageSHA256: "f04cf1524eeb87d90055b954a3a4e047965c24f5f5b9769abcb711d3a68efc23", referenceBristolType: nil, referenceForm: "mixed", expectedAbstention: true),
    ExpectedFixture(id: "t06-severe-darkness", sanitizedImageSHA256: "5baa425c2afac1ca3ebda872f74a0c47cf1580afcdb3435017bf2586ed85055b", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true),
    ExpectedFixture(id: "t07-severe-glare", sanitizedImageSHA256: "c663e73094172a742f981b24f0e9e03ba748e11ac4ceceade80555ca2cac151a", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true),
    ExpectedFixture(id: "t08-brown-wood-block", sanitizedImageSHA256: "1f13896180c5b3f3f4fcc9cd2c632c2eb5349d490dc7f8141b6fc3f68b4d32ed", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true),
    ExpectedFixture(id: "t09-red-capsule", sanitizedImageSHA256: "acf3e57b8236eab4a88de33d34aa2961f2ca25e18f9774e9788b17ea61cd54cc", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true),
    ExpectedFixture(id: "t10-patterned-rug", sanitizedImageSHA256: "430d359f20988c60a947a9de7f42d45679100f78bbc4976f4499704764b09fe0", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true),
    ExpectedFixture(id: "t11-green-smooth-prop", sanitizedImageSHA256: "0eadcccc35f56b0b9bdd7f1bb092267ab9b4fc2b0c67a7f8f2080c34b9dd0a14", referenceBristolType: nil, referenceForm: "unable_to_assess", expectedAbstention: true),
    ExpectedFixture(id: "t12-type4-cold-start", sanitizedImageSHA256: "023ca013c9ce4eddbc6cb12a6647c5c14e3f5ad1255c8919a3ca5f4161deb3bc", referenceBristolType: 4, referenceForm: "smooth_formed", expectedAbstention: false),
  ]
  static let expectedFixtureIDs = expectedFixtures.map(\.id)
  static let baselineConfiguration = InferenceConfiguration.physicalCPUVisualBridge
  static let candidateConfiguration = InferenceConfiguration.physicalCPUVisualBridgeExtractorV3TuningCandidate
  static let descriptor = ModelDescriptor.liteRTGemma4E4B

  static func hasAnyTuningLaunchArgument(in arguments: [String]) -> Bool {
    arguments.contains { $0.hasPrefix(launchArgumentPrefix) }
  }

  @MainActor
  static func validateLaunch(arguments: [String]) throws {
    let tuningArguments = arguments.filter { $0.hasPrefix(launchArgumentPrefix) }
    let conflictingCompletionArguments = [
      PhotoSuggestionEvaluationHarness.derivedMapIPhoneLaunchArgument,
      PhotoSuggestionEvaluationHarness.rawImageSimulatorLaunchArgument,
      "--run-embedded-gemma-smoke",
      "--run-embedded-gemma-normal-flow",
      "--verify-embedded-gemma-normal-flow",
      "--run-overnight-normal-flow",
      "--verify-overnight-normal-flow",
      "--run-overnight-gemma-smoke",
    ]
    guard tuningArguments.count == 1,
      tuningArguments.first == launchArgument,
      !conflictingCompletionArguments.contains(where: arguments.contains),
      !PhysicalRawImageDiagnosticContract.hasAnyPhysicalRawLaunchArgument(in: arguments)
    else { throw DerivedMapTuningV3Error.launchConflict }
  }

  static func validateManifestHash(_ observed: String) throws {
    guard observed == frozenManifestSHA256 else {
      throw DerivedMapTuningV3Error.manifestHashDrift
    }
  }

  static func tuningFixtures(
    from manifest: DerivedMapTuningV3Manifest,
    requestedRoute: PhotoEvaluationRoute
  ) throws -> [DerivedMapTuningV3ManifestFixture] {
    guard requestedRoute == route else { throw DerivedMapTuningV3Error.routeDrift }
    guard manifest.manifestVersion == frozenManifestVersion,
      manifest.frozenAtUTC == frozenAtUTC,
      manifest.lane == lane,
      manifest.route == route,
      manifest.partition == .tuning,
      manifest.assetContract.sourceCategory == "synthetic_non_health",
      !manifest.assetContract.containsRealHealthPhotos,
      manifest.pipelines.baseline == AnalysisPipelineVersion.derivedMapV1,
      manifest.pipelines.candidate == AnalysisPipelineVersion.derivedMapV3Tuning
    else { throw DerivedMapTuningV3Error.manifestContractDrift }

    let fixtures = manifest.fixtures
    guard fixtures.map(\.id) == expectedFixtureIDs,
      fixtures.allSatisfy({ $0.partition == .tuning && $0.route == route })
    else { throw DerivedMapTuningV3Error.partitionDrift }
    return fixtures
  }

  static func validateRuntimeContract(
    baseline: InferenceConfiguration,
    candidate: InferenceConfiguration,
    descriptor observedDescriptor: ModelDescriptor
  ) throws {
    guard baseline == baselineConfiguration,
      candidate == candidateConfiguration,
      baseline.permitsTuningOverride(candidate),
      !baseline.permitsEvaluationOverride(candidate),
      InferenceConfiguration.runtimeDefault != candidate
    else { throw DerivedMapTuningV3Error.configurationDrift }
    guard observedDescriptor == descriptor else { throw DerivedMapTuningV3Error.modelDrift }
  }

  static func validateReceipt(_ receipt: ModelVerificationReceipt) throws {
    guard receipt.matches(descriptor),
      receipt.locationKind == .applicationBundle,
      receipt.appBuildIdentity == .current
    else { throw DerivedMapTuningV3Error.modelDrift }
  }

  static func engineeringMetrics(
    baselineResults: [PhotoSuggestionEvaluationResult],
    candidateResults: [PhotoSuggestionEvaluationResult]
  ) throws -> DerivedMapTuningV3EngineeringMetrics {
    let expectedIDs = Set(expectedFixtureIDs)
    guard baselineResults.count == expectedFixtureIDs.count,
      candidateResults.count == expectedFixtureIDs.count,
      baselineResults.allSatisfy({
        $0.fixture.partition == .tuning
          && $0.fixture.route == route
          && $0.pipelineVersion == AnalysisPipelineVersion.derivedMapV1
      }),
      candidateResults.allSatisfy({
        $0.fixture.partition == .tuning
          && $0.fixture.route == route
          && $0.pipelineVersion == AnalysisPipelineVersion.derivedMapV3Tuning
      })
    else { throw DerivedMapTuningV3Error.partitionDrift }

    guard Set(baselineResults.map(\.fixture.id)).count == baselineResults.count,
      Set(candidateResults.map(\.fixture.id)).count == candidateResults.count
    else { throw DerivedMapTuningV3Error.fixtureSetMismatch }
    let baselineByID = Dictionary(uniqueKeysWithValues: baselineResults.map { ($0.fixture.id, $0) })
    let candidateByID = Dictionary(uniqueKeysWithValues: candidateResults.map { ($0.fixture.id, $0) })
    guard Set(baselineByID.keys) == expectedIDs,
      Set(candidateByID.keys) == expectedIDs
    else { throw DerivedMapTuningV3Error.fixtureSetMismatch }
    for expected in expectedFixtures {
      guard let baseline = baselineByID[expected.id],
        let candidate = candidateByID[expected.id],
        fixture(baseline.fixture, matches: expected),
        fixture(candidate.fixture, matches: expected)
      else { throw DerivedMapTuningV3Error.fixtureSetMismatch }
    }
    return DerivedMapTuningV3EngineeringMetrics(
      lane: lane,
      baseline: try PhotoSuggestionEvaluator.report(results: baselineResults),
      candidate: try PhotoSuggestionEvaluator.report(results: candidateResults)
    )
  }

  private static func fixture(
    _ fixture: PhotoEvaluationFixture,
    matches expected: ExpectedFixture
  ) -> Bool {
    fixture.id == expected.id
      && fixture.partition == .tuning
      && fixture.route == route
      && fixture.sanitizedImageSHA256 == expected.sanitizedImageSHA256
      && fixture.referenceBristolType == expected.referenceBristolType
      && fixture.referenceForm == expected.referenceForm
      && fixture.expectedAbstention == expected.expectedAbstention
  }
}

struct DerivedMapTuningV3EngineeringMetrics: Codable, Equatable, Sendable {
  let lane: String
  let baseline: PhotoSuggestionMetrics
  let candidate: PhotoSuggestionMetrics
}

struct DerivedMapTuningV3Checkpoint: Codable, Sendable {
  let lane: String
  let runID: UUID
  let updatedAt: Date
  let route: PhotoEvaluationRoute
  let partition: PhotoEvaluationPartition
  let phase: String
  let pipelineVersion: String?
  let inFlightFixtureID: String?
  let baselineCompleted: Int
  let candidateCompleted: Int
  let expectedPerPipeline: Int
  let failureCode: String?
  let finalEvidenceRelativePath: String?
}

struct DerivedMapTuningV3RunSummary: Codable, Sendable {
  let lane: String
  let runID: UUID
  let startedAt: Date
  let finishedAt: Date
  let route: PhotoEvaluationRoute
  let executionLocation: InferenceExecutionLocation
  let partition: PhotoEvaluationPartition
  let manifestVersion: String
  let manifestSHA256: String
  let frozenAtUTC: String
  let sourceCategory: String
  let containsRealHealthPhotos: Bool
  let fixtureCountPerPipeline: Int
  let descriptor: ModelDescriptor
  let receipt: ModelVerificationReceipt
  let baselineConfiguration: InferenceConfiguration
  let candidateConfiguration: InferenceConfiguration
  let baselineResults: [PhotoSuggestionEvaluationResult]
  let candidateResults: [PhotoSuggestionEvaluationResult]
  let baselineStopReason: String?
  let candidateStopReason: String?
  let engineeringMetrics: DerivedMapTuningV3EngineeringMetrics?
  let completeIdenticalTuning: Bool
  let status: String
  let evidenceBoundary: String
}

@MainActor
final class DerivedMapTuningV3SessionPhases {
  enum Phase: Equatable, Sendable {
    case ready
    case baselineRunning
    case baselineComplete
    case candidateRunning
    case candidateComplete
    case failed
  }

  let sessionIdentity = UUID()
  private(set) var phase = Phase.ready
  private(set) var baselineAnalysisCount = 0
  private(set) var candidateAnalysisCount = 0

  func runBaselineAnalysis<Value>(
    _ operation: (UUID) async throws -> Value
  ) async throws -> Value {
    guard phase == .ready else { throw DerivedMapTuningV3Error.sessionPhaseDrift }
    phase = .baselineRunning
    do {
      let value = try await operation(sessionIdentity)
      baselineAnalysisCount += 1
      phase = .baselineComplete
      return value
    } catch {
      phase = .failed
      throw error
    }
  }

  func runCandidateAnalysis<Value>(
    _ operation: (UUID) async throws -> Value
  ) async throws -> Value {
    guard phase == .baselineComplete else {
      throw DerivedMapTuningV3Error.sessionPhaseDrift
    }
    phase = .candidateRunning
    do {
      let value = try await operation(sessionIdentity)
      candidateAnalysisCount += 1
      phase = .candidateComplete
      return value
    } catch {
      phase = .failed
      throw error
    }
  }
}

@MainActor
enum DerivedMapTuningV3Session {
  static func run<Value>(
    runtime: any PhotoEvaluationSessionRuntime,
    descriptor: ModelDescriptor,
    baseline: InferenceConfiguration,
    candidate: InferenceConfiguration,
    onPreparationFailure: (Error) -> Void = { _ in },
    operation: (DerivedMapTuningV3SessionPhases) async throws -> Value
  ) async throws -> Value {
    try DerivedMapTuningV3Contract.validateRuntimeContract(
      baseline: baseline,
      candidate: candidate,
      descriptor: descriptor
    )
    return try await PhotoEvaluationPreparedSession.run(
      runtime: runtime,
      descriptor: descriptor,
      onPreparationFailure: onPreparationFailure
    ) {
      try await operation(DerivedMapTuningV3SessionPhases())
    }
  }
}

@MainActor
final class PhotoSuggestionEvaluationHarness {
  static let derivedMapIPhoneLaunchArgument = "--run-photo-evaluation-derived-map-iphone"
  static let rawImageSimulatorLaunchArgument = "--run-photo-evaluation-raw-image-simulator"
  static let inputDirectoryName = "PhotoSuggestionEvaluation"
  static let frozenManifestSHA256 = PhotoEvaluationFrozenManifestIdentity.sha256

  private let baselineRuntime: ModelRuntimeCoordinator
  private let fileManager = FileManager.default

  init(baselineRuntime: ModelRuntimeCoordinator) {
    self.baselineRuntime = baselineRuntime
  }

  func runDerivedMapIPhone() async throws -> PhotoSuggestionEvaluationHarnessResult {
    #if targetEnvironment(simulator)
    throw PhotoSuggestionEvaluationHarnessError.wrongPlatform(
      "DERIVED_MAP_IPHONE must run on a physical iPhone, never in the Simulator."
    )
    #else
    return try await run(
      route: .derivedMapIPhone,
      baselineConfiguration: .physicalCPUVisualBridge,
      candidateConfiguration: .physicalCPUVisualBridgeExtractorV2Candidate
    )
    #endif
  }

  func runDerivedMapV3TuningIPhone() async throws -> PhotoSuggestionEvaluationHarnessResult {
    #if targetEnvironment(simulator)
    throw DerivedMapTuningV3Error.wrongPlatform
    #else
    return try await runDerivedMapV3Tuning()
    #endif
  }

  func runDerivedMapV3BlindValidationV1IPhone() async throws -> PhotoSuggestionEvaluationHarnessResult {
    #if targetEnvironment(simulator)
    throw DerivedMapBlindValidationV1Error.wrongPlatform
    #else
    return try await runDerivedMapV3BlindValidationV1()
    #endif
  }

  #if DEBUG
  func runRawImageSimulator() async throws -> PhotoSuggestionEvaluationHarnessResult {
    #if targetEnvironment(simulator)
    return try await run(
      route: .rawImageSimulator,
      baselineConfiguration: .simulatorCPUFallback,
      candidateConfiguration: .simulatorRawPromptV2Candidate
    )
    #else
    throw PhotoSuggestionEvaluationHarnessError.wrongPlatform(
      "RAW_IMAGE_SIMULATOR must run in the arm64 iPhone Simulator, never on a physical phone."
    )
    #endif
  }
  #endif

  private func runDerivedMapV3BlindValidationV1() async throws -> PhotoSuggestionEvaluationHarnessResult {
    let startedAt = Date()
    let runID = UUID()
    let contract = DerivedMapBlindValidationV1Contract.self
    let baselineConfiguration = contract.baselineConfiguration
    let candidateConfiguration = contract.candidateConfiguration
    let descriptor = contract.descriptor
    try contract.validateRuntimeContract(
      baseline: baselineConfiguration,
      candidate: candidateConfiguration,
      descriptor: descriptor
    )
    let configuredBaseline = await baselineRuntime.configurationSnapshot()
    guard configuredBaseline == baselineConfiguration else {
      throw DerivedMapBlindValidationV1Error.configurationDrift
    }

    let inputRoot = try blindValidationV1InputRoot()
    let manifestURL = inputRoot.appendingPathComponent(contract.manifestFilename)
    guard fileManager.fileExists(atPath: manifestURL.path) else {
      throw DerivedMapBlindValidationV1Error.inputMissing
    }
    let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
    try contract.validateManifestHash(Self.sha256(manifestData))
    let manifest = try DerivedMapBlindValidationV1Manifest.decodeAndValidate(manifestData)
    let assets = try manifest.fixtures.map { fixture in
      (fixture, try validatedBlindValidationV1AssetURL(fixture, under: inputRoot))
    }
    guard assets.map(\.0.id) == contract.expectedFixtureIDs else {
      throw DerivedMapBlindValidationV1Error.fixtureSetMismatch
    }

    // Consume the lane only after every frozen input and runtime property has
    // validated, but before model preparation or any observation can reveal a
    // result. A crash or failed run therefore cannot be repeated opportunistically.
    let stateRoot = try blindValidationV1StateRoot()
    try fileManager.createDirectory(at: stateRoot, withIntermediateDirectories: true)
    try AppFolders.protect(stateRoot)
    let consumptionURL = stateRoot.appendingPathComponent(contract.consumptionFilename)
    try DerivedMapBlindValidationV1ConsumptionStore.consume(
      runID: runID,
      at: consumptionURL,
      fileManager: fileManager,
      protect: { try AppFolders.protect($0) }
    )

    let resultsRoot = stateRoot.appendingPathComponent(
      contract.resultsDirectoryName,
      isDirectory: true
    )
    let runRoot = resultsRoot.appendingPathComponent(
      "blind-validation-v1-\(runID.uuidString.lowercased())",
      isDirectory: true
    )
    try fileManager.createDirectory(at: runRoot, withIntermediateDirectories: true)
    try AppFolders.protect(resultsRoot)
    try AppFolders.protect(runRoot)
    let checkpointURL = stateRoot.appendingPathComponent(contract.checkpointFilename)
    let expectedCount = assets.count
    try write(
      DerivedMapBlindValidationV1Checkpoint(
        lane: contract.lane,
        runID: runID,
        updatedAt: Date(),
        phase: "blind_validation_v1_preparing_baseline",
        pipelineVersion: baselineConfiguration.analysisPipelineVersion,
        inFlightFixtureID: nil,
        baselineCompleted: 0,
        candidateCompleted: 0,
        expectedPerPipeline: expectedCount,
        failureCode: nil,
        finalEvidenceRelativePath: nil
      ),
      to: checkpointURL
    )

    let execution = try await PhotoEvaluationPreparedSession.run(
      runtime: baselineRuntime,
      descriptor: descriptor,
      onPreparationFailure: { error in
        try? self.write(
          DerivedMapBlindValidationV1Checkpoint(
            lane: contract.lane,
            runID: runID,
            updatedAt: Date(),
            phase: "blind_validation_v1_failed_preparing_baseline",
            pipelineVersion: baselineConfiguration.analysisPipelineVersion,
            inFlightFixtureID: nil,
            baselineCompleted: 0,
            candidateCompleted: 0,
            expectedPerPipeline: expectedCount,
            failureCode: Self.failureCode(error),
            finalEvidenceRelativePath: nil
          ),
          to: checkpointURL
        )
      }
    ) {
      guard let receipt = try await self.baselineRuntime.receipt(for: descriptor) else {
        throw DerivedMapBlindValidationV1Error.modelDrift
      }
      try contract.validateReceipt(receipt)
      let baselineExecution = try await self.runBlindValidationV1Pipeline(
        assets: assets,
        configuration: baselineConfiguration,
        runtime: self.baselineRuntime,
        descriptor: descriptor,
        runID: runID,
        checkpointURL: checkpointURL,
        runRoot: runRoot,
        baselineCompleted: 0,
        candidateCompleted: 0,
        expectedCount: expectedCount
      )
      let baselineResults = baselineExecution.results
      var candidateResults = [PhotoSuggestionEvaluationResult]()
      var candidateStopReason: String?
      if baselineResults.count == expectedCount {
        try self.write(
          DerivedMapBlindValidationV1Checkpoint(
            lane: contract.lane,
            runID: runID,
            updatedAt: Date(),
            phase: "blind_validation_v1_reusing_prepared_session_for_candidate",
            pipelineVersion: candidateConfiguration.analysisPipelineVersion,
            inFlightFixtureID: nil,
            baselineCompleted: baselineResults.count,
            candidateCompleted: 0,
            expectedPerPipeline: expectedCount,
            failureCode: nil,
            finalEvidenceRelativePath: nil
          ),
          to: checkpointURL
        )
        do {
          let candidateExecution = try await self.runBlindValidationV1Pipeline(
            assets: assets,
            configuration: candidateConfiguration,
            runtime: self.baselineRuntime,
            descriptor: descriptor,
            runID: runID,
            checkpointURL: checkpointURL,
            runRoot: runRoot,
            baselineCompleted: baselineResults.count,
            candidateCompleted: 0,
            expectedCount: expectedCount
          )
          candidateResults = candidateExecution.results
          candidateStopReason = candidateExecution.repeatedFailureCode
        } catch {
          candidateStopReason = Self.failureCode(error)
          try? self.write(
            DerivedMapBlindValidationV1Checkpoint(
              lane: contract.lane,
              runID: runID,
              updatedAt: Date(),
              phase: "blind_validation_v1_failed_candidate",
              pipelineVersion: candidateConfiguration.analysisPipelineVersion,
              inFlightFixtureID: nil,
              baselineCompleted: baselineResults.count,
              candidateCompleted: candidateResults.count,
              expectedPerPipeline: expectedCount,
              failureCode: candidateStopReason,
              finalEvidenceRelativePath: nil
            ),
            to: checkpointURL
          )
        }
      } else {
        candidateStopReason = "not_run=blind_validation_baseline_incomplete"
      }
      return (
        receipt: receipt,
        baselineExecution: baselineExecution,
        candidateResults: candidateResults,
        candidateStopReason: candidateStopReason
      )
    }

    let baselineResults = execution.baselineExecution.results
    let candidateResults = execution.candidateResults
    let complete = baselineResults.count == expectedCount
      && candidateResults.count == expectedCount
    let decision = complete
      ? try contract.decision(
        baselineResults: baselineResults,
        candidateResults: candidateResults
      )
      : nil
    let status: String
    if !complete { status = contract.incompleteStatus }
    else if decision?.eligibleForManualPromotionReview == true {
      status = contract.eligibleStatus
    } else {
      status = contract.rejectedStatus
    }
    let summary = DerivedMapBlindValidationV1RunSummary(
      lane: contract.lane,
      runID: runID,
      startedAt: startedAt,
      finishedAt: Date(),
      route: .derivedMapIPhone,
      executionLocation: .currentAppLocal,
      partition: .holdout,
      manifestVersion: manifest.manifestVersion,
      manifestSHA256: contract.frozenManifestSHA256,
      frozenAtUTC: manifest.frozenAtUTC,
      frozenBeforeAccuracyCodeChanges: manifest.frozenBeforeAccuracyCodeChanges,
      sourceCategory: manifest.assetContract.sourceCategory,
      containsRealHealthPhotos: manifest.assetContract.containsRealHealthPhotos,
      fixtureCountPerPipeline: expectedCount,
      descriptor: descriptor,
      receipt: execution.receipt,
      baselineConfiguration: baselineConfiguration,
      candidateConfiguration: candidateConfiguration,
      preparedSessionContract: "ONE_PREPARED_MODEL_SESSION; baseline completed before candidate; one awaited final invalidation",
      memoryMethod: "task_vm_info.resident_size_peak sampled after each observation; process-lifetime high-water mark",
      thresholds: .frozen,
      baselineResults: baselineResults,
      candidateResults: candidateResults,
      baselineStopReason: execution.baselineExecution.repeatedFailureCode,
      candidateStopReason: execution.candidateStopReason,
      decision: decision,
      completeIdenticalFixtureSet: complete,
      status: status,
      evidenceBoundary: contract.evidenceBoundary,
      productionDefaultMutation: "NONE; validation can only make the candidate eligible for separate manual review"
    )
    let evidenceURL = runRoot.appendingPathComponent(contract.summaryFilename)
    try write(summary, to: evidenceURL)
    let relative = "\(contract.resultsDirectoryName)/\(runRoot.lastPathComponent)/\(contract.summaryFilename)"
    try write(
      DerivedMapBlindValidationV1Checkpoint(
        lane: contract.lane,
        runID: runID,
        updatedAt: Date(),
        phase: complete
          ? "blind_validation_v1_complete"
          : "blind_validation_v1_incomplete",
        pipelineVersion: nil,
        inFlightFixtureID: nil,
        baselineCompleted: baselineResults.count,
        candidateCompleted: candidateResults.count,
        expectedPerPipeline: expectedCount,
        failureCode: execution.baselineExecution.repeatedFailureCode
          ?? execution.candidateStopReason,
        finalEvidenceRelativePath: relative
      ),
      to: checkpointURL
    )
    let console = "lane=\(contract.lane) route=DERIVED_MAP_IPHONE partition=holdout baseline=\(baselineResults.count)/\(expectedCount) candidate=\(candidateResults.count)/\(expectedCount) status=\(status) default_mutation=none evidence=\(relative)"
    return PhotoSuggestionEvaluationHarnessResult(
      evidenceURL: evidenceURL,
      consoleSummary: console,
      terminalStatus: status
    )
  }

  private func runDerivedMapV3Tuning() async throws -> PhotoSuggestionEvaluationHarnessResult {
    let startedAt = Date()
    let runID = UUID()
    let baselineConfiguration = DerivedMapTuningV3Contract.baselineConfiguration
    let candidateConfiguration = DerivedMapTuningV3Contract.candidateConfiguration
    let descriptor = DerivedMapTuningV3Contract.descriptor
    let inputRoot = try tuningV3InputRoot()
    let manifestURL = inputRoot.appendingPathComponent(
      DerivedMapTuningV3Contract.manifestFilename
    )
    guard fileManager.fileExists(atPath: manifestURL.path) else {
      throw PhotoSuggestionEvaluationHarnessError.inputMissing
    }
    let manifestData = try Data(contentsOf: manifestURL)
    try DerivedMapTuningV3Contract.validateManifestHash(Self.sha256(manifestData))
    let manifest = try DerivedMapTuningV3Manifest.decodeAndValidate(manifestData)
    let tuningFixtures = try DerivedMapTuningV3Contract.tuningFixtures(
      from: manifest,
      requestedRoute: .derivedMapIPhone
    )
    try DerivedMapTuningV3Contract.validateRuntimeContract(
      baseline: baselineConfiguration,
      candidate: candidateConfiguration,
      descriptor: descriptor
    )
    let configuredBaseline = await baselineRuntime.configurationSnapshot()
    guard configuredBaseline == baselineConfiguration else {
      throw DerivedMapTuningV3Error.configurationDrift
    }
    let assets = try tuningFixtures.map { fixture in
      (fixture, try validatedTuningV3AssetURL(fixture, under: inputRoot))
    }
    let expectedCount = assets.count

    // The root, checkpoint, result files, and summary all carry an explicit
    // tuning-v3 label and never overlap the frozen holdout `results` tree.
    let resultsRoot = inputRoot.appendingPathComponent("tuning-results-v3", isDirectory: true)
    let runRoot = resultsRoot.appendingPathComponent(
      "tuning-v3-\(runID.uuidString.lowercased())",
      isDirectory: true
    )
    try fileManager.createDirectory(at: runRoot, withIntermediateDirectories: true)
    try AppFolders.protect(resultsRoot)
    try AppFolders.protect(runRoot)
    let checkpointURL = resultsRoot.appendingPathComponent(
      "active-derived-map-v3-tuning.json"
    )
    try write(
      DerivedMapTuningV3Checkpoint(
        lane: DerivedMapTuningV3Contract.lane,
        runID: runID,
        updatedAt: Date(),
        route: .derivedMapIPhone,
        partition: .tuning,
        phase: "tuning_v3_preparing_baseline",
        pipelineVersion: baselineConfiguration.analysisPipelineVersion,
        inFlightFixtureID: nil,
        baselineCompleted: 0,
        candidateCompleted: 0,
        expectedPerPipeline: expectedCount,
        failureCode: nil,
        finalEvidenceRelativePath: nil
      ),
      to: checkpointURL
    )

    let sessionExecution = try await DerivedMapTuningV3Session.run(
      runtime: baselineRuntime,
      descriptor: descriptor,
      baseline: baselineConfiguration,
      candidate: candidateConfiguration,
      onPreparationFailure: { error in
        try? self.write(
          DerivedMapTuningV3Checkpoint(
            lane: DerivedMapTuningV3Contract.lane,
            runID: runID,
            updatedAt: Date(),
            route: .derivedMapIPhone,
            partition: .tuning,
            phase: "tuning_v3_failed_preparing_baseline",
            pipelineVersion: baselineConfiguration.analysisPipelineVersion,
            inFlightFixtureID: nil,
            baselineCompleted: 0,
            candidateCompleted: 0,
            expectedPerPipeline: expectedCount,
            failureCode: Self.failureCode(error),
            finalEvidenceRelativePath: nil
          ),
          to: checkpointURL
        )
      }
    ) { phases in
      guard let receipt = try await baselineRuntime.receipt(for: descriptor) else {
        throw DerivedMapTuningV3Error.modelDrift
      }
      try DerivedMapTuningV3Contract.validateReceipt(receipt)

      let baselineExecution = try await phases.runBaselineAnalysis { _ in
        try await self.runTuningV3Pipeline(
          assets: assets,
          configuration: baselineConfiguration,
          runtime: baselineRuntime,
          descriptor: descriptor,
          runID: runID,
          checkpointURL: checkpointURL,
          runRoot: runRoot,
          baselineCompleted: 0,
          candidateCompleted: 0,
          expectedCount: expectedCount
        )
      }
      let baselineResults = baselineExecution.results
      var candidateResults: [PhotoSuggestionEvaluationResult] = []
      var candidateStopReason: String?
      if baselineResults.count == expectedCount {
        try self.write(
          DerivedMapTuningV3Checkpoint(
            lane: DerivedMapTuningV3Contract.lane,
            runID: runID,
            updatedAt: Date(),
            route: .derivedMapIPhone,
            partition: .tuning,
            phase: "tuning_v3_reusing_session_candidate",
            pipelineVersion: candidateConfiguration.analysisPipelineVersion,
            inFlightFixtureID: nil,
            baselineCompleted: baselineResults.count,
            candidateCompleted: 0,
            expectedPerPipeline: expectedCount,
            failureCode: nil,
            finalEvidenceRelativePath: nil
          ),
          to: checkpointURL
        )
        do {
          let candidateExecution = try await phases.runCandidateAnalysis { _ in
            try await self.runTuningV3Pipeline(
              assets: assets,
              configuration: candidateConfiguration,
              runtime: baselineRuntime,
              descriptor: descriptor,
              runID: runID,
              checkpointURL: checkpointURL,
              runRoot: runRoot,
              baselineCompleted: baselineResults.count,
              candidateCompleted: 0,
              expectedCount: expectedCount
            )
          }
          candidateResults = candidateExecution.results
          candidateStopReason = candidateExecution.repeatedFailureCode
        } catch {
          candidateStopReason = Self.failureCode(error)
          try? self.write(
            DerivedMapTuningV3Checkpoint(
              lane: DerivedMapTuningV3Contract.lane,
              runID: runID,
              updatedAt: Date(),
              route: .derivedMapIPhone,
              partition: .tuning,
              phase: "tuning_v3_failed_candidate",
              pipelineVersion: candidateConfiguration.analysisPipelineVersion,
              inFlightFixtureID: nil,
              baselineCompleted: baselineResults.count,
              candidateCompleted: candidateResults.count,
              expectedPerPipeline: expectedCount,
              failureCode: Self.failureCode(error),
              finalEvidenceRelativePath: nil
            ),
            to: checkpointURL
          )
        }
      } else {
        candidateStopReason = "not_run=tuning_baseline_incomplete"
      }
      return (
        receipt: receipt,
        baselineExecution: baselineExecution,
        candidateResults: candidateResults,
        candidateStopReason: candidateStopReason
      )
    }

    let baselineResults = sessionExecution.baselineExecution.results
    let candidateResults = sessionExecution.candidateResults
    let recordsComplete = baselineResults.count == expectedCount
      && candidateResults.count == expectedCount
    let metrics = recordsComplete
      ? try DerivedMapTuningV3Contract.engineeringMetrics(
        baselineResults: baselineResults,
        candidateResults: candidateResults
      )
      : nil
    let summary = DerivedMapTuningV3RunSummary(
      lane: DerivedMapTuningV3Contract.lane,
      runID: runID,
      startedAt: startedAt,
      finishedAt: Date(),
      route: .derivedMapIPhone,
      executionLocation: .currentAppLocal,
      partition: .tuning,
      manifestVersion: manifest.manifestVersion,
      manifestSHA256: DerivedMapTuningV3Contract.frozenManifestSHA256,
      frozenAtUTC: manifest.frozenAtUTC,
      sourceCategory: manifest.assetContract.sourceCategory,
      containsRealHealthPhotos: manifest.assetContract.containsRealHealthPhotos,
      fixtureCountPerPipeline: expectedCount,
      descriptor: descriptor,
      receipt: sessionExecution.receipt,
      baselineConfiguration: baselineConfiguration,
      candidateConfiguration: candidateConfiguration,
      baselineResults: baselineResults,
      candidateResults: candidateResults,
      baselineStopReason: sessionExecution.baselineExecution.repeatedFailureCode,
      candidateStopReason: sessionExecution.candidateStopReason,
      engineeringMetrics: metrics,
      completeIdenticalTuning: recordsComplete,
      status: recordsComplete
        ? DerivedMapTuningV3Contract.metricsRecordedStatus
        : DerivedMapTuningV3Contract.incompleteRunStatus,
      evidenceBoundary: "Synthetic tuning-only engineering metrics. Not locked-holdout, clinical, release, or production-default evidence."
    )
    let evidenceURL = runRoot.appendingPathComponent("tuning-v3-summary.json")
    try write(summary, to: evidenceURL)
    let relative = "tuning-results-v3/tuning-v3-\(runID.uuidString.lowercased())/tuning-v3-summary.json"
    try write(
      DerivedMapTuningV3Checkpoint(
        lane: DerivedMapTuningV3Contract.lane,
        runID: runID,
        updatedAt: Date(),
        route: .derivedMapIPhone,
        partition: .tuning,
        phase: recordsComplete ? "tuning_v3_records_complete" : "tuning_v3_records_incomplete",
        pipelineVersion: nil,
        inFlightFixtureID: nil,
        baselineCompleted: baselineResults.count,
        candidateCompleted: candidateResults.count,
        expectedPerPipeline: expectedCount,
        failureCode: sessionExecution.baselineExecution.repeatedFailureCode
          ?? sessionExecution.candidateStopReason,
        finalEvidenceRelativePath: relative
      ),
      to: checkpointURL
    )
    let console = "lane=\(DerivedMapTuningV3Contract.lane) route=\(PhotoEvaluationRoute.derivedMapIPhone.rawValue) partition=tuning baseline=\(baselineResults.count)/\(expectedCount) candidate=\(candidateResults.count)/\(expectedCount) status=\(summary.status) evidence=\(relative)"
    return PhotoSuggestionEvaluationHarnessResult(
      evidenceURL: evidenceURL,
      consoleSummary: console
    )
  }

  private func run(
    route: PhotoEvaluationRoute,
    baselineConfiguration: InferenceConfiguration,
    candidateConfiguration: InferenceConfiguration
  ) async throws -> PhotoSuggestionEvaluationHarnessResult {
    let startedAt = Date()
    let runID = UUID()
    let inputRoot = try evaluationInputRoot()
    let resultsRoot = inputRoot.appendingPathComponent("results", isDirectory: true)
    let runRoot = resultsRoot.appendingPathComponent(runID.uuidString.lowercased(), isDirectory: true)
    try fileManager.createDirectory(at: runRoot, withIntermediateDirectories: true)
    try AppFolders.protect(resultsRoot)
    try AppFolders.protect(runRoot)

    let manifestURL = inputRoot.appendingPathComponent("manifest.json")
    guard fileManager.fileExists(atPath: manifestURL.path) else {
      throw PhotoSuggestionEvaluationHarnessError.inputMissing
    }
    let manifestData = try Data(contentsOf: manifestURL)
    guard Self.sha256(manifestData) == Self.frozenManifestSHA256 else {
      throw PhotoSuggestionEvaluationHarnessError.manifestHashMismatch
    }
    let manifest = try PhotoEvaluationManifest.decodeAndValidate(manifestData)
    let manifestPipeline = manifest.pipelines.pipeline(for: route)
    try validatePipelineContract(
      route: route,
      manifestPipeline: manifestPipeline,
      baseline: baselineConfiguration,
      candidate: candidateConfiguration
    )

    let configuredBaseline = await baselineRuntime.configurationSnapshot()
    guard configuredBaseline == baselineConfiguration else {
      throw PhotoSuggestionEvaluationHarnessError.wrongBaselineConfiguration(configuredBaseline.id)
    }
    guard let descriptor = ModelCatalog.normalFlowSelection,
      descriptor == .liteRTGemma4E4B
    else { throw PhotoSuggestionEvaluationHarnessError.exactModelUnavailable }

    let frozenFixtures = manifest.fixtures(for: route, partition: .holdout)
    let assets = try frozenFixtures.map { fixture in
      (fixture, try validatedAssetURL(fixture, under: inputRoot))
    }
    let expectedCount = assets.count
    let checkpointURL = resultsRoot.appendingPathComponent("active-\(route.rawValue.lowercased()).json")
    try writeCheckpoint(
      .init(
        runID: runID,
        updatedAt: Date(),
        route: route,
        partition: .holdout,
        phase: "preparing_baseline",
        pipelineVersion: baselineConfiguration.analysisPipelineVersion,
        inFlightFixtureID: nil,
        baselineCompleted: 0,
        candidateCompleted: 0,
        expectedPerPipeline: expectedCount,
        failureCode: nil,
        finalEvidenceRelativePath: nil
      ),
      to: checkpointURL
    )

    let sessionExecution = try await PhotoEvaluationPreparedSession.run(
      runtime: baselineRuntime,
      descriptor: descriptor,
      onPreparationFailure: { error in
        try? self.writeCheckpoint(
          .init(
            runID: runID,
            updatedAt: Date(),
            route: route,
            partition: .holdout,
            phase: "failed_preparing_baseline",
            pipelineVersion: baselineConfiguration.analysisPipelineVersion,
            inFlightFixtureID: nil,
            baselineCompleted: 0,
            candidateCompleted: 0,
            expectedPerPipeline: expectedCount,
            failureCode: Self.failureCode(error),
            finalEvidenceRelativePath: nil
          ),
          to: checkpointURL
        )
      }
    ) {
      guard let receipt = try await baselineRuntime.receipt(for: descriptor),
        receipt.matches(descriptor)
      else { throw PhotoSuggestionEvaluationHarnessError.modelReceiptUnavailable }

      let baselineExecution = try await self.runPipeline(
        assets: assets,
        route: route,
        configuration: baselineConfiguration,
        runtime: baselineRuntime,
        descriptor: descriptor,
        runID: runID,
        checkpointURL: checkpointURL,
        runRoot: runRoot,
        baselineCompleted: 0,
        candidateCompleted: 0,
        expectedCount: expectedCount
      )
      let baselineResults = baselineExecution.results

      var candidateResults: [PhotoSuggestionEvaluationResult] = []
      var candidateStopReason: String?
      if baselineResults.count == expectedCount {
        try self.writeCheckpoint(
          .init(
            runID: runID,
            updatedAt: Date(),
            route: route,
            partition: .holdout,
            phase: "reusing_session_candidate",
            pipelineVersion: candidateConfiguration.analysisPipelineVersion,
            inFlightFixtureID: nil,
            baselineCompleted: baselineResults.count,
            candidateCompleted: 0,
            expectedPerPipeline: expectedCount,
            failureCode: nil,
            finalEvidenceRelativePath: nil
          ),
          to: checkpointURL
        )
        do {
          let candidateExecution = try await self.runPipeline(
            assets: assets,
            route: route,
            configuration: candidateConfiguration,
            runtime: baselineRuntime,
            descriptor: descriptor,
            runID: runID,
            checkpointURL: checkpointURL,
            runRoot: runRoot,
            baselineCompleted: baselineResults.count,
            candidateCompleted: 0,
            expectedCount: expectedCount
          )
          candidateResults = candidateExecution.results
          candidateStopReason = candidateExecution.repeatedFailureCode
        } catch {
          candidateStopReason = Self.failureCode(error)
          try? self.writeCheckpoint(
            .init(
              runID: runID,
              updatedAt: Date(),
              route: route,
              partition: .holdout,
              phase: "failed_candidate",
              pipelineVersion: candidateConfiguration.analysisPipelineVersion,
              inFlightFixtureID: nil,
              baselineCompleted: baselineResults.count,
              candidateCompleted: candidateResults.count,
              expectedPerPipeline: expectedCount,
              failureCode: Self.failureCode(error),
              finalEvidenceRelativePath: nil
            ),
            to: checkpointURL
          )
        }
      } else {
        candidateStopReason = "not_run=baseline_incomplete"
      }
      return (
        receipt: receipt,
        baselineExecution: baselineExecution,
        candidateResults: candidateResults,
        candidateStopReason: candidateStopReason
      )
    }
    let receipt = sessionExecution.receipt
    let baselineExecution = sessionExecution.baselineExecution
    let baselineResults = baselineExecution.results
    let candidateResults = sessionExecution.candidateResults
    let candidateStopReason = sessionExecution.candidateStopReason

    let complete = baselineResults.count == expectedCount && candidateResults.count == expectedCount
    let baselineMetrics = try? PhotoSuggestionEvaluator.report(results: baselineResults)
    let candidateMetrics = try? PhotoSuggestionEvaluator.report(results: candidateResults)
    let limits = PhotoCandidateResourceLimits(
      maximumLatencyMilliseconds: 120_000,
      maximumPeakMemoryBytes: ProcessInfo.processInfo.physicalMemory,
      allowedLatencyRegressionFraction: 0,
      allowedMemoryRegressionBytes: 0
    )
    let decision = complete
      ? try? PhotoCandidateComparator.compare(
        baseline: baselineResults,
        candidate: candidateResults,
        limits: limits
      )
      : nil
    let recommendation = decision?.adopted == true
      ? "CANDIDATE_ELIGIBLE_FOR_MANUAL_ADOPTION_REVIEW_NOT_INSTALLED"
      : "BASELINE_RETAINED"
    let boundary = route == .derivedMapIPhone
      ? "Swift inspected the sanitized image and Gemma received text facts only. This is not raw-photo Gemma evidence."
      : "Gemma received the sanitized image in the arm64 Simulator. This is not physical-iPhone evidence."
    let summary = PhotoSuggestionEvaluationRunSummary(
      runID: runID,
      startedAt: startedAt,
      finishedAt: Date(),
      route: route,
      executionLocation: .currentAppLocal,
      partition: .holdout,
      manifestVersion: manifest.manifestVersion,
      manifestSHA256: Self.frozenManifestSHA256,
      frozenAtUTC: manifest.frozenAtUTC,
      frozenBeforeAccuracyCodeChanges: manifest.frozenBeforeAccuracyCodeChanges,
      sourceCategory: manifest.assetContract.sourceCategory,
      containsRealHealthPhotos: manifest.assetContract.containsRealHealthPhotos,
      fixtureCountPerPipeline: expectedCount,
      descriptor: descriptor,
      receipt: receipt,
      baselineConfiguration: baselineConfiguration,
      candidateConfiguration: candidateConfiguration,
      manifestBaselineVersion: manifestPipeline.baseline,
      manifestCandidateVersion: manifestPipeline.candidate,
      memoryMethod: "task_vm_info.resident_size_peak sampled after each observation; process lifetime high-water mark",
      resourceLimits: limits,
      baselineResults: baselineResults,
      candidateResults: candidateResults,
      baselineStopReason: baselineExecution.repeatedFailureCode,
      candidateStopReason: candidateStopReason,
      baselineMetrics: baselineMetrics,
      candidateMetrics: candidateMetrics,
      adoptionDecision: decision,
      completeIdenticalHoldout: complete,
      recommendation: recommendation,
      evidenceBoundary: boundary
    )
    let evidenceURL = runRoot.appendingPathComponent("summary.json")
    try write(summary, to: evidenceURL)
    let relative = "results/\(runID.uuidString.lowercased())/summary.json"
    try writeCheckpoint(
      .init(
        runID: runID,
        updatedAt: Date(),
        route: route,
        partition: .holdout,
        phase: complete ? "complete" : "incomplete",
        pipelineVersion: nil,
        inFlightFixtureID: nil,
        baselineCompleted: baselineResults.count,
        candidateCompleted: candidateResults.count,
        expectedPerPipeline: expectedCount,
        failureCode: baselineExecution.repeatedFailureCode ?? candidateStopReason,
        finalEvidenceRelativePath: relative
      ),
      to: checkpointURL
    )
    let console = "route=\(route.rawValue) baseline=\(baselineResults.count)/\(expectedCount) candidate=\(candidateResults.count)/\(expectedCount) recommendation=\(recommendation) evidence=\(relative)"
    return PhotoSuggestionEvaluationHarnessResult(evidenceURL: evidenceURL, consoleSummary: console)
  }

  private func runBlindValidationV1Pipeline(
    assets: [(DerivedMapBlindValidationV1ManifestFixture, URL)],
    configuration: InferenceConfiguration,
    runtime: ModelRuntimeCoordinator,
    descriptor: ModelDescriptor,
    runID: UUID,
    checkpointURL: URL,
    runRoot: URL,
    baselineCompleted: Int,
    candidateCompleted: Int,
    expectedCount: Int
  ) async throws -> (results: [PhotoSuggestionEvaluationResult], repeatedFailureCode: String?) {
    let contract = DerivedMapBlindValidationV1Contract.self
    let isBaseline: Bool
    if configuration == contract.baselineConfiguration { isBaseline = true }
    else if configuration == contract.candidateConfiguration { isBaseline = false }
    else { throw DerivedMapBlindValidationV1Error.configurationDrift }

    var results = [PhotoSuggestionEvaluationResult]()
    var failureCounts = [String: Int]()
    for (fixture, assetURL) in assets {
      guard fixture.partition == .holdout,
        fixture.routes.contains(.derivedMapIPhone)
      else { throw DerivedMapBlindValidationV1Error.fixtureSetMismatch }
      try write(
        DerivedMapBlindValidationV1Checkpoint(
          lane: contract.lane,
          runID: runID,
          updatedAt: Date(),
          phase: isBaseline
            ? "blind_validation_v1_running_baseline"
            : "blind_validation_v1_running_candidate",
          pipelineVersion: configuration.analysisPipelineVersion,
          inFlightFixtureID: fixture.id,
          baselineCompleted: isBaseline ? results.count : baselineCompleted,
          candidateCompleted: isBaseline ? candidateCompleted : results.count,
          expectedPerPipeline: expectedCount,
          failureCode: nil,
          finalEvidenceRelativePath: nil
        ),
        to: checkpointURL
      )
      let result = await evaluate(
        fixture: fixture.evaluationFixture,
        assetURL: assetURL,
        route: .derivedMapIPhone,
        configuration: configuration,
        runtime: runtime,
        descriptor: descriptor,
        lane: .derivedMapV3BlindValidation
      )
      results.append(result)
      let filename = isBaseline
        ? "blind-validation-v1-baseline-results.json"
        : "blind-validation-v1-candidate-results.json"
      try write(results, to: runRoot.appendingPathComponent(filename))
      try write(
        DerivedMapBlindValidationV1Checkpoint(
          lane: contract.lane,
          runID: runID,
          updatedAt: Date(),
          phase: result.failureDescription == nil
            ? "blind_validation_v1_observation_recorded"
            : "blind_validation_v1_observation_failed",
          pipelineVersion: configuration.analysisPipelineVersion,
          inFlightFixtureID: result.failureDescription == nil ? nil : fixture.id,
          baselineCompleted: isBaseline ? results.count : baselineCompleted,
          candidateCompleted: isBaseline ? candidateCompleted : results.count,
          expectedPerPipeline: expectedCount,
          failureCode: result.failureDescription,
          finalEvidenceRelativePath: nil
        ),
        to: checkpointURL
      )
      if let code = result.failureDescription {
        failureCounts[code, default: 0] += 1
        if code == "stage=timeout" || failureCounts[code, default: 0] >= 2 {
          return (results, code)
        }
      }
    }
    return (results, nil)
  }

  private func runTuningV3Pipeline(
    assets: [(DerivedMapTuningV3ManifestFixture, URL)],
    configuration: InferenceConfiguration,
    runtime: ModelRuntimeCoordinator,
    descriptor: ModelDescriptor,
    runID: UUID,
    checkpointURL: URL,
    runRoot: URL,
    baselineCompleted: Int,
    candidateCompleted: Int,
    expectedCount: Int
  ) async throws -> (results: [PhotoSuggestionEvaluationResult], repeatedFailureCode: String?) {
    let isBaseline: Bool
    if configuration == DerivedMapTuningV3Contract.baselineConfiguration {
      isBaseline = true
    } else if configuration == DerivedMapTuningV3Contract.candidateConfiguration {
      isBaseline = false
    } else {
      throw DerivedMapTuningV3Error.configurationDrift
    }

    var results: [PhotoSuggestionEvaluationResult] = []
    var failureCounts: [String: Int] = [:]
    for (fixture, assetURL) in assets {
      guard fixture.partition == .tuning, fixture.route == .derivedMapIPhone else {
        throw DerivedMapTuningV3Error.partitionDrift
      }
      try write(
        DerivedMapTuningV3Checkpoint(
          lane: DerivedMapTuningV3Contract.lane,
          runID: runID,
          updatedAt: Date(),
          route: .derivedMapIPhone,
          partition: .tuning,
          phase: isBaseline ? "tuning_v3_running_baseline" : "tuning_v3_running_candidate",
          pipelineVersion: configuration.analysisPipelineVersion,
          inFlightFixtureID: fixture.id,
          baselineCompleted: isBaseline ? results.count : baselineCompleted,
          candidateCompleted: isBaseline ? candidateCompleted : results.count,
          expectedPerPipeline: expectedCount,
          failureCode: nil,
          finalEvidenceRelativePath: nil
        ),
        to: checkpointURL
      )
      let result = await evaluate(
        fixture: fixture.evaluationFixture,
        assetURL: assetURL,
        route: .derivedMapIPhone,
        configuration: configuration,
        runtime: runtime,
        descriptor: descriptor,
        lane: .derivedMapV3Tuning
      )
      guard result.fixture.partition == .tuning else {
        throw DerivedMapTuningV3Error.partitionDrift
      }
      results.append(result)
      let resultsFilename = isBaseline
        ? "tuning-v3-baseline-results.json"
        : "tuning-v3-candidate-results.json"
      try write(results, to: runRoot.appendingPathComponent(resultsFilename))
      try write(
        DerivedMapTuningV3Checkpoint(
          lane: DerivedMapTuningV3Contract.lane,
          runID: runID,
          updatedAt: Date(),
          route: .derivedMapIPhone,
          partition: .tuning,
          phase: result.failureDescription == nil
            ? "tuning_v3_observation_recorded"
            : "tuning_v3_observation_failed",
          pipelineVersion: configuration.analysisPipelineVersion,
          inFlightFixtureID: result.failureDescription == nil ? nil : fixture.id,
          baselineCompleted: isBaseline ? results.count : baselineCompleted,
          candidateCompleted: isBaseline ? candidateCompleted : results.count,
          expectedPerPipeline: expectedCount,
          failureCode: result.failureDescription,
          finalEvidenceRelativePath: nil
        ),
        to: checkpointURL
      )
      if let code = result.failureDescription {
        failureCounts[code, default: 0] += 1
        if code == "stage=timeout" || failureCounts[code, default: 0] >= 2 {
          return (results, code)
        }
      }
    }
    return (results, nil)
  }

  private func runPipeline(
    assets: [(PhotoEvaluationManifestFixture, URL)],
    route: PhotoEvaluationRoute,
    configuration: InferenceConfiguration,
    runtime: ModelRuntimeCoordinator,
    descriptor: ModelDescriptor,
    runID: UUID,
    checkpointURL: URL,
    runRoot: URL,
    baselineCompleted: Int,
    candidateCompleted: Int,
    expectedCount: Int
  ) async throws -> (results: [PhotoSuggestionEvaluationResult], repeatedFailureCode: String?) {
    var results: [PhotoSuggestionEvaluationResult] = []
    var failureCounts: [String: Int] = [:]
    for (fixture, assetURL) in assets {
      let isBaseline = configuration.analysisPipelineVersion.hasSuffix("v1")
      try writeCheckpoint(
        .init(
          runID: runID,
          updatedAt: Date(),
          route: route,
          partition: .holdout,
          phase: isBaseline ? "running_baseline" : "running_candidate",
          pipelineVersion: configuration.analysisPipelineVersion,
          inFlightFixtureID: fixture.id,
          baselineCompleted: isBaseline ? results.count : baselineCompleted,
          candidateCompleted: isBaseline ? candidateCompleted : results.count,
          expectedPerPipeline: expectedCount,
          failureCode: nil,
          finalEvidenceRelativePath: nil
        ),
        to: checkpointURL
      )
      let result = await evaluate(
        fixture: fixture.evaluationFixture(for: route),
        assetURL: assetURL,
        route: route,
        configuration: configuration,
        runtime: runtime,
        descriptor: descriptor
      )
      results.append(result)
      let resultsFilename = isBaseline ? "baseline-results.json" : "candidate-results.json"
      try write(results, to: runRoot.appendingPathComponent(resultsFilename))
      try writeCheckpoint(
        .init(
          runID: runID,
          updatedAt: Date(),
          route: route,
          partition: .holdout,
          phase: result.failureDescription == nil ? "observation_recorded" : "observation_failed",
          pipelineVersion: configuration.analysisPipelineVersion,
          inFlightFixtureID: result.failureDescription == nil ? nil : fixture.id,
          baselineCompleted: isBaseline ? results.count : baselineCompleted,
          candidateCompleted: isBaseline ? candidateCompleted : results.count,
          expectedPerPipeline: expectedCount,
          failureCode: result.failureDescription,
          finalEvidenceRelativePath: nil
        ),
        to: checkpointURL
      )
      if let code = result.failureDescription {
        failureCounts[code, default: 0] += 1
        if code == "stage=timeout" || failureCounts[code, default: 0] >= 2 {
          return (results, code)
        }
      }
    }
    return (results, nil)
  }

  private enum AnalysisLane {
    case frozenHoldout
    case derivedMapV3Tuning
    case derivedMapV3BlindValidation
  }

  private func evaluate(
    fixture: PhotoEvaluationFixture,
    assetURL: URL,
    route: PhotoEvaluationRoute,
    configuration: InferenceConfiguration,
    runtime: ModelRuntimeCoordinator,
    descriptor: ModelDescriptor,
    lane: AnalysisLane = .frozenHoldout
  ) async -> PhotoSuggestionEvaluationResult {
    let race = PhotoEvaluationResultRace()
    return await withCheckedContinuation { continuation in
      race.install(continuation)
      let analysisTask = Task { @MainActor in
        let result = await self.evaluateWithoutTimeout(
          fixture: fixture,
          assetURL: assetURL,
          route: route,
          configuration: configuration,
          runtime: runtime,
          descriptor: descriptor,
          lane: lane
        )
        race.resolve(result)
      }
      // The native generation call can monopolize an executor. Keep the
      // watchdog detached so its deadline is independent of that work.
      Task.detached(priority: .utility) {
        try? await Task.sleep(for: .seconds(120))
        let timedOut = PhotoSuggestionEvaluationResult(
          fixture: fixture,
          pipelineVersion: configuration.analysisPipelineVersion,
          promptVersion: configuration.promptVersion,
          suggestedBristolType: nil,
          suggestedForm: "unable_to_assess",
          abstained: true,
          strictJSONValid: false,
          parsePath: .invalid,
          latencyMilliseconds: 120_000,
          // A high-water sample taken from the watchdog is not attributable to
          // the in-flight observation, so leave it unmeasured.
          peakMemoryBytes: nil,
          failureDescription: "stage=timeout",
          crashed: false,
          userConfirmedCorrection: nil
        )
        if race.resolve(timedOut) { analysisTask.cancel() }
      }
    }
  }

  private func evaluateWithoutTimeout(
    fixture: PhotoEvaluationFixture,
    assetURL: URL,
    route: PhotoEvaluationRoute,
    configuration: InferenceConfiguration,
    runtime: ModelRuntimeCoordinator,
    descriptor: ModelDescriptor,
    lane: AnalysisLane
  ) async -> PhotoSuggestionEvaluationResult {
    let clock = ContinuousClock()
    let started = clock.now
    var observation: VisualObservation?
    var parsePath = PhotoParsePath.invalid
    var strictJSONValid = false
    var failureDescription: String?
    do {
      let initial: String
      switch lane {
      case .frozenHoldout:
        initial = try await runtime.analyzeForEvaluation(
          descriptor,
          draftURL: assetURL,
          configuration: configuration
        )
      case .derivedMapV3Tuning:
        guard route == .derivedMapIPhone, fixture.partition == .tuning else {
          throw DerivedMapTuningV3Error.partitionDrift
        }
        if configuration == DerivedMapTuningV3Contract.baselineConfiguration {
          initial = try await runtime.analyze(descriptor, draftURL: assetURL)
        } else if configuration == DerivedMapTuningV3Contract.candidateConfiguration {
          initial = try await runtime.analyzeForTuning(
            descriptor,
            draftURL: assetURL,
            configuration: configuration
          )
        } else {
          throw DerivedMapTuningV3Error.configurationDrift
        }
      case .derivedMapV3BlindValidation:
        guard route == .derivedMapIPhone, fixture.partition == .holdout else {
          throw DerivedMapBlindValidationV1Error.fixtureSetMismatch
        }
        if configuration == DerivedMapBlindValidationV1Contract.baselineConfiguration {
          initial = try await runtime.analyze(descriptor, draftURL: assetURL)
        } else if configuration == DerivedMapBlindValidationV1Contract.candidateConfiguration {
          initial = try await runtime.analyzeForBlindValidation(
            descriptor,
            draftURL: assetURL,
            configuration: configuration
          )
        } else {
          throw DerivedMapBlindValidationV1Error.configurationDrift
        }
      }
      do {
        observation = try ObservationParser.parse(initial)
        parsePath = .direct
        strictJSONValid = true
        await runtime.discardRepairContext(descriptor, draftURL: assetURL)
      } catch {
        let repaired = try await runtime.repair(
          descriptor,
          draftURL: assetURL,
          errors: error.localizedDescription
        )
        observation = try ObservationParser.parse(repaired)
        parsePath = .repaired
        strictJSONValid = true
      }
    } catch {
      await runtime.discardRepairContext(descriptor, draftURL: assetURL)
      failureDescription = Self.failureCode(error)
    }
    let latency = started.duration(to: clock.now).secondsDouble * 1_000
    let memory = Self.processResidentPeakBytes()
    return PhotoSuggestionEvaluationResult(
      fixture: fixture,
      pipelineVersion: configuration.analysisPipelineVersion,
      promptVersion: configuration.promptVersion,
      suggestedBristolType: observation?.apparentBristolType,
      suggestedForm: observation?.form ?? "unable_to_assess",
      abstained: observation?.apparentBristolType == nil,
      strictJSONValid: strictJSONValid,
      parsePath: parsePath,
      latencyMilliseconds: latency,
      peakMemoryBytes: memory,
      failureDescription: failureDescription,
      crashed: false,
      userConfirmedCorrection: nil,
      observedImageUsable: observation?.imageUsable,
      observedQualityIssue: observation?.qualityIssue
    )
  }

  private func tuningV3InputRoot() throws -> URL {
    let documents = try fileManager.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let direct = documents.appendingPathComponent(Self.inputDirectoryName, isDirectory: true)
    let filename = DerivedMapTuningV3Contract.manifestFilename
    if fileManager.fileExists(atPath: direct.appendingPathComponent(filename).path) {
      return direct
    }
    let copiedDirectory = direct.appendingPathComponent("photo-evaluation", isDirectory: true)
    if fileManager.fileExists(atPath: copiedDirectory.appendingPathComponent(filename).path) {
      return copiedDirectory
    }
    throw PhotoSuggestionEvaluationHarnessError.inputMissing
  }

  private func blindValidationV1InputRoot() throws -> URL {
    let documents = try fileManager.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let root = documents.appendingPathComponent(
      DerivedMapBlindValidationV1Contract.inputDirectoryName,
      isDirectory: true
    )
    guard fileManager.fileExists(atPath: root.appendingPathComponent(
      DerivedMapBlindValidationV1Contract.manifestFilename
    ).path) else { throw DerivedMapBlindValidationV1Error.inputMissing }
    return root
  }

  private func blindValidationV1StateRoot() throws -> URL {
    let applicationSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return applicationSupport.appendingPathComponent(
      "GIJournalBlindValidationV1State",
      isDirectory: true
    )
  }

  private func evaluationInputRoot() throws -> URL {
    let documents = try fileManager.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let direct = documents.appendingPathComponent(Self.inputDirectoryName, isDirectory: true)
    if fileManager.fileExists(atPath: direct.appendingPathComponent("manifest.json").path) {
      return direct
    }
    let copiedDirectory = direct.appendingPathComponent("photo-evaluation", isDirectory: true)
    if fileManager.fileExists(atPath: copiedDirectory.appendingPathComponent("manifest.json").path) {
      return copiedDirectory
    }
    throw PhotoSuggestionEvaluationHarnessError.inputMissing
  }

  private func validatedAssetURL(
    _ fixture: PhotoEvaluationManifestFixture,
    under inputRoot: URL
  ) throws -> URL {
    let root = inputRoot.standardizedFileURL
    let assetURL = root.appendingPathComponent(fixture.asset).standardizedFileURL
    guard assetURL.path.hasPrefix(root.path + "/"), fileManager.fileExists(atPath: assetURL.path) else {
      throw PhotoSuggestionEvaluationHarnessError.assetMissing(fixture.id)
    }
    let data = try Data(contentsOf: assetURL, options: .mappedIfSafe)
    guard Self.sha256(data) == fixture.sanitizedImageSHA256.lowercased() else {
      throw PhotoSuggestionEvaluationHarnessError.assetHashMismatch(fixture.id)
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetType(source) == "public.jpeg" as CFString,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      properties[kCGImagePropertyExifDictionary] == nil,
      properties[kCGImagePropertyGPSDictionary] == nil,
      properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelRGB as String,
      (properties[kCGImagePropertyProfileName] as? String)?.localizedCaseInsensitiveContains("sRGB") == true
    else { throw PhotoSuggestionEvaluationHarnessError.assetNotSanitizedSRGB(fixture.id) }
    return assetURL
  }

  private func validatedTuningV3AssetURL(
    _ fixture: DerivedMapTuningV3ManifestFixture,
    under inputRoot: URL
  ) throws -> URL {
    let root = inputRoot.standardizedFileURL
    let assetURL = root.appendingPathComponent(fixture.asset).standardizedFileURL
    guard assetURL.path.hasPrefix(root.path + "/"), fileManager.fileExists(atPath: assetURL.path) else {
      throw PhotoSuggestionEvaluationHarnessError.assetMissing(fixture.id)
    }
    let data = try Data(contentsOf: assetURL, options: .mappedIfSafe)
    guard Self.sha256(data) == fixture.sanitizedImageSHA256.lowercased() else {
      throw PhotoSuggestionEvaluationHarnessError.assetHashMismatch(fixture.id)
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetType(source) == "public.jpeg" as CFString,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      properties[kCGImagePropertyExifDictionary] == nil,
      properties[kCGImagePropertyGPSDictionary] == nil,
      properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelRGB as String,
      (properties[kCGImagePropertyProfileName] as? String)?.localizedCaseInsensitiveContains("sRGB") == true
    else { throw PhotoSuggestionEvaluationHarnessError.assetNotSanitizedSRGB(fixture.id) }
    return assetURL
  }

  private func validatedBlindValidationV1AssetURL(
    _ fixture: DerivedMapBlindValidationV1ManifestFixture,
    under inputRoot: URL
  ) throws -> URL {
    let root = inputRoot.standardizedFileURL
    let assetURL = root.appendingPathComponent(fixture.asset).standardizedFileURL
    guard assetURL.path.hasPrefix(root.path + "/"),
      fileManager.fileExists(atPath: assetURL.path)
    else { throw DerivedMapBlindValidationV1Error.assetMissing(fixture.id) }
    let data = try Data(contentsOf: assetURL, options: .mappedIfSafe)
    guard Self.sha256(data) == fixture.sanitizedImageSHA256.lowercased() else {
      throw DerivedMapBlindValidationV1Error.assetHashMismatch(fixture.id)
    }
    let permittedStructuralExifKeys: Set<String> = [
      "ColorSpace", "PixelXDimension", "PixelYDimension",
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetType(source) == "public.jpeg" as CFString,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      properties[kCGImagePropertyGPSDictionary] == nil,
      properties[kCGImagePropertyTIFFDictionary] == nil,
      properties[kCGImagePropertyIPTCDictionary] == nil,
      properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelRGB as String,
      (properties[kCGImagePropertyProfileName] as? String)?
        .localizedCaseInsensitiveContains("sRGB") == true,
      Set(
        ((properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:])
          .keys.map { $0 as String }
      ).isSubset(of: permittedStructuralExifKeys)
    else { throw DerivedMapBlindValidationV1Error.assetNotSanitizedSRGB(fixture.id) }
    return assetURL
  }

  private func validatePipelineContract(
    route: PhotoEvaluationRoute,
    manifestPipeline: PhotoEvaluationManifestPipeline,
    baseline: InferenceConfiguration,
    candidate: InferenceConfiguration
  ) throws {
    let implementedBaseline = baseline.analysisPipelineVersion
    let implementedCandidate = candidate.analysisPipelineVersion
    let manifestCandidateMatches = manifestPipeline.candidate == implementedCandidate
      || (route == .rawImageSimulator && manifestPipeline.candidate == "gi-observation-raw-v2-debug")
    guard manifestPipeline.baseline == implementedBaseline,
      manifestCandidateMatches,
      baseline != candidate,
      baseline.engineBackend == candidate.engineBackend,
      baseline.visionBackend == candidate.visionBackend,
      baseline.maxNumTokens == candidate.maxNumTokens,
      baseline.topK == candidate.topK,
      baseline.topP == candidate.topP,
      baseline.temperature == candidate.temperature,
      baseline.seed == candidate.seed,
      baseline.imageMessageForm == candidate.imageMessageForm
    else { throw PhotoSuggestionEvaluationHarnessError.manifestPipelineMismatch(route.rawValue) }

    switch route {
    case .derivedMapIPhone:
      guard baseline.promptVersion == candidate.promptVersion,
        !baseline.usesCandidatePixelExtractor,
        candidate.usesCandidatePixelExtractor
      else { throw PhotoSuggestionEvaluationHarnessError.manifestPipelineMismatch(route.rawValue) }
    case .rawImageSimulator:
      guard baseline.promptVersion != candidate.promptVersion,
        !baseline.usesCandidateRawPrompt,
        candidate.usesCandidateRawPrompt
      else { throw PhotoSuggestionEvaluationHarnessError.manifestPipelineMismatch(route.rawValue) }
    }
  }

  private func writeCheckpoint(
    _ checkpoint: PhotoSuggestionEvaluationCheckpoint,
    to url: URL
  ) throws {
    try write(checkpoint, to: url)
  }

  private func write<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(value).write(to: url, options: .atomic)
    try AppFolders.protect(url)
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func failureCode(_ error: Error) -> String {
    if let staged = error as? StagedInferenceError { return "stage=\(staged.stage.rawValue)" }
    if let harness = error as? PhotoSuggestionEvaluationHarnessError {
      return "harness=\(String(describing: harness))"
    }
    return "error_type=\(String(reflecting: type(of: error)))"
  }

  private static func processResidentPeakBytes() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return UInt64(info.resident_size_peak)
  }
}

/// Labeled, development-only input set reused for the single bounded 140 versus
/// 280 full-prefill comparison. The frozen manifest bytes remain unchanged;
/// neither arm can access the untouched validation partition.
struct RawPhotoV12TuningManifest: Decodable, Equatable, Sendable {
  struct Fixture: Decodable, Equatable, Sendable {
    let id: String
    let asset: String
    let sanitizedImageSHA256: String

    enum CodingKeys: String, CodingKey {
      case id
      case asset
      case sanitizedImageSHA256 = "sanitized_image_sha256"
    }
  }

  let manifestVersion: String
  let sourceManifestSHA256: String
  let partition: String
  let route: String
  let containsRealHealthPhotos: Bool
  let fixtures: [Fixture]

  enum CodingKeys: String, CodingKey {
    case manifestVersion = "manifest_version"
    case sourceManifestSHA256 = "source_manifest_sha256"
    case partition
    case route
    case containsRealHealthPhotos = "contains_real_health_photos"
    case fixtures
  }

  static func decodeAndValidate(_ data: Data) throws -> Self {
    guard let text = String(data: data, encoding: .utf8),
      text.range(of: "holdout", options: .caseInsensitive) == nil,
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(object.keys) == Set([
        "manifest_version",
        "source_manifest_sha256",
        "partition",
        "route",
        "contains_real_health_photos",
        "fixtures",
      ]),
      let rawFixtures = object["fixtures"] as? [[String: Any]],
      rawFixtures.count == RawPhotoV12TuningContract.orderedFixtures.count,
      rawFixtures.allSatisfy({
        Set($0.keys) == Set(["id", "asset", "sanitized_image_sha256"])
      })
    else { throw GITimelineError.syntheticFixtureIntegrity }

    let manifest = try JSONDecoder().decode(Self.self, from: data)
    guard manifest.manifestVersion == RawPhotoV12TuningContract.laneVersion,
      manifest.sourceManifestSHA256
        == RawPhotoV12TuningContract.sourceManifestSHA256,
      manifest.partition == "tuning",
      manifest.route == PhotoEvaluationRoute.rawImageSimulator.rawValue,
      manifest.containsRealHealthPhotos == false,
      Set(manifest.fixtures.map(\.id)).count == manifest.fixtures.count,
      manifest.fixtures.allSatisfy({ fixture in
        fixture.id.hasPrefix("t")
          && fixture.id.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
          }
          && fixture.asset.hasPrefix("assets/")
          && (fixture.asset as NSString).pathExtension.lowercased() == "jpg"
          && !(fixture.asset as NSString).pathComponents.contains("..")
          && fixture.sanitizedImageSHA256.count == 64
          && fixture.sanitizedImageSHA256.allSatisfy(\.isHexDigit)
      })
    else { throw GITimelineError.syntheticFixtureIntegrity }
    return manifest
  }
}

enum RawPhotoV12TuningContract {
  enum MarkerDisposition: Sendable {
    case success
    case failure
    case recordedBaselineSchemaFailure
  }

  enum Arm: String, CaseIterable, Sendable {
    case arm140
    case arm280

    var launchArgument: String {
      switch self {
      case .arm140:
        return "--run-gi-v1-full-prefill-normalization-ab-140"
      case .arm280:
        return "--run-gi-v1-full-prefill-normalization-ab-280"
      }
    }

    var configuration: InferenceConfiguration {
      switch self {
      case .arm140: return .appStoreRawImageV12SubjectGateTuning
      case .arm280: return .appStoreRawImageFullPrefill280
      }
    }
  }

  enum Screen: String, Sendable {
    case recordOnly = "record_only_morphology_proxy"
    case noForcedSingleForm = "no_forced_single_form"
    case technicalTooDark = "technical_too_dark"
    case technicalGlare = "technical_glare"
    case nonStool = "non_stool"
  }

  struct Fixture: Equatable, Sendable {
    let id: String
    let asset: String
    let sanitizedSHA256: String
    let screen: Screen

    var launchArgument: String { fixtureLaunchArgumentPrefix + id }
  }

  static let lane = "GI_V1_PHOTO_FULL_PREFILL_NORMALIZATION_AB_V1"
  static let comparisonFamily =
    "gi-v1-photo-full-prefill-normalization-policy-ab-v1"
  // This identifies the already-frozen development manifest, not a prompt or
  // binary version. Its bytes and hash are intentionally unchanged.
  static let laneVersion = "raw-photo-v12-subject-gate-tuning-v1"
  static let inputDirectoryName = "FullPrefillNormalizationABV1"
  static let manifestFilename = "manifest.json"
  static let frozenManifestSHA256 =
    "00d8e8bc11b8ba83d4cb624bc69e45542b7aae0420a45b17d66e52232d34e7bc"
  static let sourceManifestSHA256 =
    "7412c39492b6b9031b4768d1b94722861be346fb36841a1e527dcc6da9c41f20"
  static let candidatePromptSHA256 =
    "1b378173075b55724f3c68652b1561bfddcc2cdf75cd99360d4d53933edba583"
  static let fullPrefillSchemaSHA256 =
    "c44b50a1bf7b62b4b04cf2047036af8559b7f87168da83b755bd557519660533"
  static let fixtureLaunchArgumentPrefix =
    "--gi-v1-full-prefill-normalization-fixture-"
  static let terminalMarkerPrefix = "GI_V1_FULL_PREFILL_NORMALIZATION_AB"
  static let markerContract = "gi-v1-full-prefill-normalization-marker-v1"
  static let descriptor = ModelDescriptor.liteRTGemma4E4B
  static let baselineConfiguration =
    InferenceConfiguration.appStoreRawImageV12SubjectGateTuning
  static let candidateConfiguration =
    InferenceConfiguration.appStoreRawImageFullPrefill280
  static let orderedFixtures: [Fixture] = [
    Fixture(
      id: "t12-type4-cold-start",
      asset: "assets/t12-type4-cold-start.jpg",
      sanitizedSHA256: "023ca013c9ce4eddbc6cb12a6647c5c14e3f5ad1255c8919a3ca5f4161deb3bc",
      screen: .recordOnly
    ),
    Fixture(
      id: "t08-brown-wood-block",
      asset: "assets/t08-brown-wood-block.jpg",
      sanitizedSHA256: "1f13896180c5b3f3f4fcc9cd2c632c2eb5349d490dc7f8141b6fc3f68b4d32ed",
      screen: .nonStool
    ),
    Fixture(
      id: "t09-red-capsule",
      asset: "assets/t09-red-capsule.jpg",
      sanitizedSHA256: "acf3e57b8236eab4a88de33d34aa2961f2ca25e18f9774e9788b17ea61cd54cc",
      screen: .nonStool
    ),
    Fixture(
      id: "t10-patterned-rug",
      asset: "assets/t10-patterned-rug.jpg",
      sanitizedSHA256: "430d359f20988c60a947a9de7f42d45679100f78bbc4976f4499704764b09fe0",
      screen: .nonStool
    ),
    Fixture(
      id: "t11-green-smooth-prop",
      asset: "assets/t11-green-smooth-prop.jpg",
      sanitizedSHA256: "0eadcccc35f56b0b9bdd7f1bb092267ab9b4fc2b0c67a7f8f2080c34b9dd0a14",
      screen: .nonStool
    ),
    Fixture(
      id: "t06-severe-darkness",
      asset: "assets/t06-severe-darkness.jpg",
      sanitizedSHA256: "5baa425c2afac1ca3ebda872f74a0c47cf1580afcdb3435017bf2586ed85055b",
      screen: .technicalTooDark
    ),
    Fixture(
      id: "t07-severe-glare",
      asset: "assets/t07-severe-glare.jpg",
      sanitizedSHA256: "c663e73094172a742f981b24f0e9e03ba748e11ac4ceceade80555ca2cac151a",
      screen: .technicalGlare
    ),
    Fixture(
      id: "t05-mixed-hard-loose",
      asset: "assets/t05-mixed-hard-loose.jpg",
      sanitizedSHA256: "f04cf1524eeb87d90055b954a3a4e047965c24f5f5b9769abcb711d3a68efc23",
      screen: .noForcedSingleForm
    ),
    Fixture(
      id: "t01-type1-brown-lumps",
      asset: "assets/t01-type1-brown-lumps.jpg",
      sanitizedSHA256: "e83ba8778ea30d947cca0802dc22342547c001961d6d19b5bb82b3d8d07cd05e",
      screen: .recordOnly
    ),
    Fixture(
      id: "t02-type3-cracked-formed",
      asset: "assets/t02-type3-cracked-formed.jpg",
      sanitizedSHA256: "7ab0aef66c9dd7e1723a17271be858c0b762ab9c32795c3b1473fd19e28ef116",
      screen: .recordOnly
    ),
    Fixture(
      id: "t03-type5-soft-blobs",
      asset: "assets/t03-type5-soft-blobs.jpg",
      sanitizedSHA256: "984910bae71e8753d9904ee20e46fa7e00719bafc83278ce45fd06e84a2e4403",
      screen: .recordOnly
    ),
    Fixture(
      id: "t04-type7-watery-pool",
      asset: "assets/t04-type7-watery-pool.jpg",
      sanitizedSHA256: "769a6ef45f1b7cfc641d59f3a91e32b731b4442fe350ed76a348ae931b309949",
      screen: .recordOnly
    ),
  ]

  private static let conflictingArguments = [
    "--run-photo-evaluation-raw-image-simulator",
    "--run-photo-evaluation-derived-map-iphone",
    DerivedMapTuningV3Contract.launchArgument,
    DerivedMapBlindValidationV1Contract.launchArgument,
    PhysicalRawImageSuiteContract.launchArgument,
    AppStoreRawImageV1PreparationDiagnosticContract.launchArgument,
  ]

  static func isRequested(in arguments: [String]) -> Bool {
    arguments.contains { argument in
      Arm.allCases.map(\.launchArgument).contains(argument)
        || argument.hasPrefix(fixtureLaunchArgumentPrefix)
    }
  }

  static func requestedArm(in arguments: [String]) -> Arm? {
    let matches = Arm.allCases.filter { arm in
      arguments.filter { $0 == arm.launchArgument }.count == 1
    }
    guard matches.count == 1,
      Arm.allCases.reduce(0, { count, arm in
        count + arguments.filter { $0 == arm.launchArgument }.count
      }) == 1
    else { return nil }
    return matches[0]
  }

  static func requestedFixture(in arguments: [String]) -> Fixture? {
    let selectors = arguments.filter {
      $0.hasPrefix(fixtureLaunchArgumentPrefix)
    }
    guard selectors.count == 1, let selector = selectors.first else { return nil }
    return orderedFixtures.first { $0.launchArgument == selector }
  }

  static func isValidRequest(in arguments: [String]) -> Bool {
    guard let arm = requestedArm(in: arguments),
      requestedFixture(in: arguments) != nil,
      InferenceConfiguration.internalDiagnosticConfiguration(
        arguments: arguments
      ) == arm.configuration,
      arguments.filter({ $0 == diagnosticSelector(for: arm) }).count == 1,
      !conflictingArguments.contains(where: arguments.contains),
      !arguments.contains(where: {
        PhysicalRawImageDiagnosticContract.hasAnyPhysicalRawLaunchArgument(
          in: [$0]
        )
      }),
      !AppStoreRawImageV1PreparationDiagnosticContract
        .hasDiagnosticLaunchArgument(in: arguments)
    else { return false }
    return true
  }

  static func diagnosticSelector(for arm: Arm) -> String {
    switch arm {
    case .arm140:
      InferenceConfiguration.internalAppStoreRawImageV1CandidateLaunchArgument
    case .arm280:
      InferenceConfiguration.internalAppStoreRawImageV1Candidate280LaunchArgument
    }
  }

  static func validateManifest(
    _ manifest: RawPhotoV12TuningManifest
  ) -> Bool {
    guard manifest.fixtures.count == orderedFixtures.count else { return false }
    let mapped = Dictionary(
      uniqueKeysWithValues: manifest.fixtures.map { ($0.id, $0) }
    )
    return orderedFixtures.allSatisfy { expected in
      guard let actual = mapped[expected.id] else { return false }
      return actual.asset == expected.asset
        && actual.sanitizedImageSHA256.lowercased()
          == expected.sanitizedSHA256
    }
  }

  /// Hard semantic invariants shared by both arms. Morphology accuracy remains
  /// a scored comparison below; these checks prevent either budget from
  /// advancing after a subject, technical-abstention, or mixed-form failure.
  static func expectationSatisfied(
    _ suggestion: FullPrefillPhotoSuggestionV1,
    fixture: Fixture
  ) -> Bool {
    switch fixture.screen {
    case .recordOnly:
      return suggestion.imageUsable
        && suggestion.retakeReason == nil
        && suggestion.stoolPresence == .stool
    case .noForcedSingleForm:
      return suggestion.imageUsable
        && suggestion.retakeReason == nil
        && suggestion.stoolPresence == .stool
        && suggestion.bristolType == nil
        && suggestion.form == "mixed"
        && suggestion.mixedForm == .yes
    case .technicalTooDark:
      return !suggestion.imageUsable
        && suggestion.retakeReason == .tooDark
        && suggestion.stoolPresence == .uncertain
        && hasFullAbstention(suggestion)
    case .technicalGlare:
      return !suggestion.imageUsable
        && suggestion.retakeReason == .glare
        && suggestion.stoolPresence == .uncertain
        && hasFullAbstention(suggestion)
    case .nonStool:
      return suggestion.imageUsable
        && suggestion.retakeReason == nil
        && [.nonStool, .uncertain].contains(suggestion.stoolPresence)
        && hasFullAbstention(suggestion)
    }
  }

  struct SemanticScore: Equatable, Sendable {
    let subjectTechnicalPass: Bool
    let bristolWithinOne: Bool?
    let bristolExact: Bool?
    let formExact: Bool?
    let mixedExact: Bool?
    let fullAbstention: Bool?

    var points: Int {
      [subjectTechnicalPass, bristolWithinOne, bristolExact, formExact, mixedExact,
        fullAbstention]
        .compactMap { $0 }
        .filter { $0 }
        .count
    }

    var maximumPoints: Int {
      1 + [bristolWithinOne, bristolExact, formExact, mixedExact, fullAbstention]
        .compactMap { $0 }.count
    }
  }

  static func semanticScore(
    _ suggestion: FullPrefillPhotoSuggestionV1,
    fixture: Fixture
  ) -> SemanticScore {
    let expectedType: Int?
    switch fixture.id {
    case "t12-type4-cold-start": expectedType = 4
    case "t01-type1-brown-lumps": expectedType = 1
    case "t02-type3-cracked-formed": expectedType = 3
    case "t03-type5-soft-blobs": expectedType = 5
    case "t04-type7-watery-pool": expectedType = 7
    default: expectedType = nil
    }
    let bristolWithinOne = expectedType.map { expected in
      suggestion.bristolType.map { abs($0 - expected) <= 1 } ?? false
    }
    let bristolExact = expectedType.map { suggestion.bristolType == $0 }

    let expectedForm: String?
    if let expectedType {
      expectedForm = BristolFormContract.expectedForm(for: expectedType)
    } else if fixture.screen == .noForcedSingleForm {
      expectedForm = "mixed"
    } else {
      expectedForm = nil
    }
    let formExact = expectedForm.map { suggestion.form == $0 }

    let expectedMixed: PhotoSuggestionAnswer?
    if expectedType != nil { expectedMixed = .no }
    else if fixture.screen == .noForcedSingleForm { expectedMixed = .yes }
    else { expectedMixed = nil }

    let fullAbstention = [Screen.nonStool, .technicalTooDark, .technicalGlare]
      .contains(fixture.screen)
      ? hasFullAbstention(suggestion)
      : nil
    return SemanticScore(
      subjectTechnicalPass: expectationSatisfied(suggestion, fixture: fixture),
      bristolWithinOne: bristolWithinOne,
      bristolExact: bristolExact,
      formExact: formExact,
      mixedExact: expectedMixed.map { suggestion.mixedForm == $0 },
      fullAbstention: fullAbstention
    )
  }

  static func terminalMarker(
    disposition: MarkerDisposition,
    arm: Arm?,
    fixture: Fixture?,
    errorClass: String,
    journalIsolationAttested: Bool = false,
    inferenceLatencyMilliseconds: Int? = nil,
    endToEndLatencyMilliseconds: Int? = nil,
    peakMemoryBytes: UInt64? = nil,
    outputSHA256: String? = nil,
    suggestion: FullPrefillPhotoSuggestionV1? = nil,
    normalization: FullPrefillDependentFieldAbstentionV1.Result? = nil,
    rawCrossFieldContradiction: Bool? = nil,
    modelCallCount: Int? = nil,
    qualityGate: String = "unavailable",
    expectationPassed: Bool? = nil
  ) -> String {
    let configuration = arm?.configuration
    let score = suggestion.flatMap { suggestion in
      fixture.map { semanticScore(suggestion, fixture: $0) }
    }
    let outputKind: String
    if suggestion != nil {
      outputKind = "canonical_strict_json"
    } else if outputSHA256 != nil {
      outputKind = "raw_response_sha256_only"
    } else {
      outputKind = "unavailable"
    }
    let normalizedFieldsToken = normalization.map { result in
      result.normalizedFields.isEmpty
        ? "none" : result.normalizedFields.joined(separator: ".")
    } ?? "unavailable"
    let fields = [
      "lane=\(lane)",
      "comparison_family=\(comparisonFamily)",
      "marker_contract=\(markerContract)",
      "arm=\(sanitizedToken(arm?.rawValue ?? "unresolved"))",
      "fixture=\(sanitizedToken(fixture?.id ?? "unresolved"))",
      "fixture_sha256=\(sanitizedToken(fixture?.sanitizedSHA256 ?? "unavailable"))",
      "screen=\(sanitizedToken(fixture?.screen.rawValue ?? "unresolved"))",
      "model=\(sanitizedToken(descriptor.id))",
      "model_sha256=\(sanitizedToken(descriptor.expectedSHA256))",
      "config=\(sanitizedToken(configuration?.id ?? "unresolved"))",
      "prompt=\(sanitizedToken(configuration?.promptVersion ?? "unresolved"))",
      "prompt_sha256=\(candidatePromptSHA256)",
      "schema=\(FullPrefillPhotoSuggestionV1.schemaVersion)",
      "schema_key_count=10",
      "schema_sha256=\(fullPrefillSchemaSHA256)",
      "normalization_policy=\(FullPrefillDependentFieldAbstentionV1.policyVersion)",
      "quality_policy=\(PhotoTechnicalQualityAssessment.contractVersion)",
      "quality_gate=\(sanitizedToken(qualityGate))",
      "context_tokens=\(configuration?.maxNumTokens ?? -1)",
      "visual_tokens=\(configuration?.visualTokenBudget ?? -1)",
      "transport=validated_sanitized_jpeg_image_data",
      "manifest_sha256=\(frozenManifestSHA256)",
      "source_manifest_sha256=\(sourceManifestSHA256)",
      "partition=tuning",
      "holdout_manifest_access=false",
      "holdout_asset_access=false",
      "journal_container=\(journalIsolationAttested ? "ephemeral" : "unverified")",
      "isolation_attested=\(journalIsolationAttested)",
      "strict_schema=\(suggestion != nil)",
      "repair_used=false",
      "model_call_count=\(modelCallCount.map(String.init) ?? "-1")",
      "expectation_scored=\(expectationPassed != nil)",
      "expectation_pass=\(expectationPassed.map(String.init) ?? "not_scored")",
      "inference_latency_ms=\(inferenceLatencyMilliseconds.map(String.init) ?? "-1")",
      "end_to_end_latency_ms=\(endToEndLatencyMilliseconds.map(String.init) ?? "-1")",
      "peak_rss_bytes=\(peakMemoryBytes.map(String.init) ?? "-1")",
      "output_kind=\(outputKind)",
      "output_sha256=\(sanitizedToken(outputSHA256 ?? "unavailable"))",
      "raw_response_sha256=\(sanitizedToken(normalization?.rawResponseSHA256 ?? outputSHA256 ?? "unavailable"))",
      "normalization_occurred=\(normalization.map { String($0.normalizationOccurred) } ?? "unavailable")",
      "normalization_count=\(normalization.map { $0.normalizationOccurred ? "1" : "0" } ?? "unavailable")",
      "normalized_fields=\(sanitizedToken(normalizedFieldsToken))",
      "normalized_canonical_sha256=\(sanitizedToken(normalization?.normalizedCanonicalSHA256 ?? "unavailable"))",
      "raw_cross_field_contradiction=\(rawCrossFieldContradiction.map(String.init) ?? normalization.map { String($0.rawCrossFieldContradiction) } ?? "unavailable")",
      "image_usable=\(suggestion.map { String($0.imageUsable) } ?? "unavailable")",
      "retake_reason=\(sanitizedToken(suggestion.map { $0.retakeReason?.rawValue ?? "null" } ?? "unavailable"))",
      "stool_presence=\(sanitizedToken(suggestion?.stoolPresence.rawValue ?? "unavailable"))",
      "bristol_type=\(suggestion.map { $0.bristolType.map(String.init) ?? "null" } ?? "unavailable")",
      "form=\(sanitizedToken(suggestion?.form ?? "unavailable"))",
      "mixed_form=\(sanitizedToken(suggestion?.mixedForm.rawValue ?? "unavailable"))",
      "apparent_color=\(sanitizedToken(suggestion.map { $0.apparentColor ?? "null" } ?? "unavailable"))",
      "red_appearing_material=\(sanitizedToken(suggestion?.redAppearingMaterial.rawValue ?? "unavailable"))",
      "black_tarry_appearance=\(sanitizedToken(suggestion?.blackTarryAppearance.rawValue ?? "unavailable"))",
      "subject_technical_pass=\(score.map { String($0.subjectTechnicalPass) } ?? "unavailable")",
      "bristol_within_one=\(score.map { triStateToken($0.bristolWithinOne) } ?? "unavailable")",
      "bristol_exact=\(score.map { triStateToken($0.bristolExact) } ?? "unavailable")",
      "form_exact=\(score.map { triStateToken($0.formExact) } ?? "unavailable")",
      "mixed_exact=\(score.map { triStateToken($0.mixedExact) } ?? "unavailable")",
      "full_abstention=\(score.map { triStateToken($0.fullAbstention) } ?? "unavailable")",
      "semantic_points=\(score.map { String($0.points) } ?? "-1")",
      "semantic_max_points=\(score.map { String($0.maximumPoints) } ?? "-1")",
      "error=\(sanitizedToken(errorClass))",
    ]
    let outcome: String
    switch disposition {
    case .failure:
      outcome = "FAIL"
    case .recordedBaselineSchemaFailure:
      outcome = "FAIL"
    case .success:
      outcome = expectationPassed == false ? "FAIL" : "PASS"
    }
    return "\(terminalMarkerPrefix)_\(outcome) \(fields.joined(separator: " "))"
  }

  static func strictSchemaErrorClass(_ error: ObservationParserError) -> String {
    switch error {
    case .invalidJSON:
      return "strict_schema_invalid_json"
    case .unknownKeys:
      return "strict_schema_unknown_keys"
    case .missingKeys:
      return "strict_schema_missing_keys"
    case .invalidValue(let field):
      return "strict_schema_invalid_value_\(sanitizedToken(field))"
    case .inconsistent:
      return "strict_schema_inconsistent"
    }
  }

  static func sanitizedErrorClass(_ error: Error) -> String {
    if let staged = error as? StagedInferenceError {
      if staged.stage == .timeout { return "inference_deadline_exceeded" }
      return "StagedInferenceError.\(staged.stage.rawValue)"
    }
    if let app = error as? GITimelineError {
      return "GITimelineError.\(String(describing: app))"
    }
    if let parser = error as? ObservationParserError {
      return "ObservationParserError.\(String(describing: parser))"
    }
    return sanitizedToken(String(reflecting: type(of: error)))
  }

  private static func hasFullAbstention(
    _ suggestion: FullPrefillPhotoSuggestionV1
  ) -> Bool {
    suggestion.bristolType == nil
      && suggestion.form == "unable_to_assess"
      && suggestion.mixedForm == .notSure
      && suggestion.apparentColor == nil
      && suggestion.redAppearingMaterial == .notSure
      && suggestion.blackTarryAppearance == .notSure
  }

  private static func triStateToken(_ value: Bool?) -> String {
    value.map(String.init) ?? "not_scored"
  }

  private static func sanitizedToken(_ raw: String) -> String {
    var token = ""
    for scalar in raw.unicodeScalars.prefix(120) {
      let value = scalar.value
      let isASCIIAlphaNumeric = (48...57).contains(value)
        || (65...90).contains(value)
        || (97...122).contains(value)
      if isASCIIAlphaNumeric || value == 45 || value == 46 || value == 95 {
        token.append(contentsOf: String(scalar))
      } else {
        token.append("_")
      }
    }
    return token.isEmpty ? "unknown" : token
  }
}

@MainActor
final class RawPhotoV12TuningHarness {
  private let runtime: ModelRuntimeCoordinator
  private let journalIsolationAttested: Bool
  private let fileManager = FileManager.default

  init(
    runtime: ModelRuntimeCoordinator,
    journalIsolationAttested: Bool
  ) {
    self.runtime = runtime
    self.journalIsolationAttested = journalIsolationAttested
  }

  func run(arguments: [String]) async -> String {
    let contract = RawPhotoV12TuningContract.self
    let arm = contract.requestedArm(in: arguments)
    let fixture = contract.requestedFixture(in: arguments)
    guard contract.isValidRequest(in: arguments), let arm, let fixture else {
      return contract.terminalMarker(
        disposition: .failure,
        arm: arm,
        fixture: fixture,
        errorClass: "selector_or_argument_contract_invalid",
        journalIsolationAttested: journalIsolationAttested
      )
    }

    #if !targetEnvironment(simulator)
    return contract.terminalMarker(
      disposition: .failure,
      arm: arm,
      fixture: fixture,
      errorClass: "wrong_platform",
      journalIsolationAttested: journalIsolationAttested
    )
    #else
    guard journalIsolationAttested else {
      return contract.terminalMarker(
        disposition: .failure,
        arm: arm,
        fixture: fixture,
        errorClass: "journal_isolation_unattested",
        journalIsolationAttested: false
      )
    }
    let configured = await runtime.configurationSnapshot()
    guard configured == arm.configuration,
      configured.permitsRawPhotoV12TuningOverride(arm.configuration),
      ModelCatalog.normalFlowSelection == contract.descriptor
    else {
      return contract.terminalMarker(
        disposition: .failure,
        arm: arm,
        fixture: fixture,
        errorClass: "configuration_drift",
        journalIsolationAttested: journalIsolationAttested
      )
    }

    let clock = ContinuousClock()
    let endToEndStarted = clock.now
    do {
      guard let receipt = try await runtime.receipt(for: contract.descriptor),
        receipt.matches(contract.descriptor),
        receipt.locationKind == .applicationBundle,
        receipt.appBuildIdentity == .current
      else { throw GITimelineError.modelNotVerified }

      guard await runtime.prepareLocalAnalysis() == .ready else {
        throw GITimelineError.modelNotVerified
      }

      let inputRoot = try inputRoot()
      try validateBundledInputRoot(inputRoot)
      let manifestURL = inputRoot.appendingPathComponent(
        contract.manifestFilename
      )
      let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
      guard Self.sha256(manifestData) == contract.frozenManifestSHA256 else {
        throw GITimelineError.syntheticFixtureIntegrity
      }
      let manifest = try RawPhotoV12TuningManifest.decodeAndValidate(manifestData)
      guard contract.validateManifest(manifest),
        let manifestFixture = manifest.fixtures.first(where: { $0.id == fixture.id }),
        manifestFixture.asset == fixture.asset,
        manifestFixture.sanitizedImageSHA256.lowercased()
          == fixture.sanitizedSHA256
      else { throw GITimelineError.syntheticFixtureIntegrity }

      let assetURL = inputRoot.appendingPathComponent(fixture.asset)
        .standardizedFileURL
      guard assetURL.path.hasPrefix(inputRoot.standardizedFileURL.path + "/")
      else { throw GITimelineError.syntheticFixtureIntegrity }
      let assetData = try Data(contentsOf: assetURL, options: .mappedIfSafe)
      try ImageStore.validateSanitizedJournalJPEG(
        assetData,
        expectedSHA256: fixture.sanitizedSHA256
      )

      let quality = try PhotoTechnicalQualityAssessment.evaluate(assetData)
      let raw: String
      let inferenceLatency: Int
      let modelCallCount: Int
      let qualityGate: String
      if let reason = quality.retakeReason {
        raw = try FullPrefillPhotoSuggestionV1Parser.canonicalJSON(
          .technicalAbstention(reason: reason)
        )
        inferenceLatency = 0
        modelCallCount = 0
        qualityGate = reason.rawValue
      } else {
        let started = clock.now
        raw = try await runtime.analyzeForRawPhotoV12Tuning(
          contract.descriptor,
          draftURL: assetURL,
          expectedSHA256: fixture.sanitizedSHA256,
          configuration: arm.configuration
        )
        inferenceLatency = Int(
          (started.duration(to: clock.now).secondsDouble * 1_000).rounded()
        )
        modelCallCount = 1
        qualityGate = "passed_to_gemma"
      }
      let rawOutputSHA256 = Self.sha256(Data(raw.utf8))
      await runtime.discardRepairContext(
        contract.descriptor,
        draftURL: assetURL
      )
      let normalization: FullPrefillDependentFieldAbstentionV1.Result
      do {
        normalization = try FullPrefillDependentFieldAbstentionV1
          .parseAndNormalize(raw)
      } catch let parserError as ObservationParserError {
        let rawContradiction = try?
          FullPrefillDependentFieldAbstentionV1.rawCrossFieldContradiction(in: raw)
        return contract.terminalMarker(
          disposition: .failure,
          arm: arm,
          fixture: fixture,
          errorClass: contract.strictSchemaErrorClass(parserError),
          journalIsolationAttested: journalIsolationAttested,
          inferenceLatencyMilliseconds: inferenceLatency,
          endToEndLatencyMilliseconds: Int(
            (endToEndStarted.duration(to: clock.now).secondsDouble * 1_000).rounded()
          ),
          peakMemoryBytes: Self.processResidentPeakBytes(),
          outputSHA256: rawOutputSHA256,
          rawCrossFieldContradiction: rawContradiction,
          modelCallCount: modelCallCount,
          qualityGate: qualityGate
        )
      }
      let suggestion = normalization.normalizedSuggestion
      let expectation = contract.expectationSatisfied(
        suggestion,
        fixture: fixture
      )
      let withinDeadline = modelCallCount == 0 || inferenceLatency <= 30_000
      let passed = expectation && withinDeadline
      return contract.terminalMarker(
        disposition: passed ? .success : .failure,
        arm: arm,
        fixture: fixture,
        errorClass: passed
          ? "none"
          : (withinDeadline
            ? "fixture_expectation_failed" : "inference_deadline_exceeded"),
        journalIsolationAttested: journalIsolationAttested,
        inferenceLatencyMilliseconds: inferenceLatency,
        endToEndLatencyMilliseconds: Int(
          (endToEndStarted.duration(to: clock.now).secondsDouble * 1_000).rounded()
        ),
        peakMemoryBytes: Self.processResidentPeakBytes(),
        outputSHA256: rawOutputSHA256,
        suggestion: suggestion,
        normalization: normalization,
        modelCallCount: modelCallCount,
        qualityGate: qualityGate,
        expectationPassed: expectation
      )
    } catch {
      return contract.terminalMarker(
        disposition: .failure,
        arm: arm,
        fixture: fixture,
        errorClass: contract.sanitizedErrorClass(error),
        journalIsolationAttested: journalIsolationAttested,
        endToEndLatencyMilliseconds: Int(
          (endToEndStarted.duration(to: clock.now).secondsDouble * 1_000).rounded()
        ),
        peakMemoryBytes: Self.processResidentPeakBytes()
      )
    }
    #endif
  }

  private func inputRoot() throws -> URL {
    guard let resourceRoot = Bundle.main.resourceURL?.standardizedFileURL
    else { throw GITimelineError.syntheticFixtureIntegrity }
    let root = resourceRoot.appendingPathComponent(
      RawPhotoV12TuningContract.inputDirectoryName,
      isDirectory: true
    ).standardizedFileURL
    guard root.path.hasPrefix(resourceRoot.path + "/") else {
      throw GITimelineError.syntheticFixtureIntegrity
    }
    guard fileManager.fileExists(atPath: root.appendingPathComponent(
      RawPhotoV12TuningContract.manifestFilename
    ).path) else { throw GITimelineError.syntheticFixtureIntegrity }
    return root
  }

  private func validateBundledInputRoot(_ root: URL) throws {
    let expectedFiles = Set(
      [RawPhotoV12TuningContract.manifestFilename]
        + RawPhotoV12TuningContract.orderedFixtures.map(\.asset)
    )
    let keys: [URLResourceKey] = [
      .isDirectoryKey,
      .isRegularFileKey,
      .isSymbolicLinkKey,
    ]
    let rootValues = try root.resourceValues(forKeys: Set(keys))
    guard rootValues.isDirectory == true,
      rootValues.isSymbolicLink != true
    else { throw GITimelineError.syntheticFixtureIntegrity }
    guard let enumerator = fileManager.enumerator(
      at: root,
      includingPropertiesForKeys: keys,
      options: [],
      errorHandler: { _, _ in false }
    ) else { throw GITimelineError.syntheticFixtureIntegrity }

    var foundFiles = Set<String>()
    let rootPath = root.standardizedFileURL.path + "/"
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: Set(keys))
      guard values.isSymbolicLink != true else {
        throw GITimelineError.syntheticFixtureIntegrity
      }
      if values.isDirectory == true { continue }
      guard values.isRegularFile == true,
        url.standardizedFileURL.path.hasPrefix(rootPath)
      else { throw GITimelineError.syntheticFixtureIntegrity }
      let relativePath = String(
        url.standardizedFileURL.path.dropFirst(rootPath.count)
      )
      guard expectedFiles.contains(relativePath),
        foundFiles.insert(relativePath).inserted
      else { throw GITimelineError.syntheticFixtureIntegrity }
    }
    guard foundFiles == expectedFiles else {
      throw GITimelineError.syntheticFixtureIntegrity
    }
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func processResidentPeakBytes() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return UInt64(info.resident_size_peak)
  }
}

/// Hash-bound, label-free runtime plan for the internal synthetic vision
/// diagnostic. The evaluator manifest is deliberately not part of this bundle
/// contract, so fixture labels can never be concatenated into a model request.
struct SyntheticVisionV1RuntimePlan: Decodable, Sendable {
  struct Asset: Decodable, Equatable, Sendable {
    let opaqueID: String
    let relativePath: String
    let sha256: String
    let byteCount: Int

    enum CodingKeys: String, CodingKey {
      case opaqueID = "opaque_id"
      case relativePath = "relative_path"
      case sha256
      case byteCount = "byte_count"
    }
  }

  struct CommonConfiguration: Decodable, Equatable, Sendable {
    let modelArtifactSHA256: String
    let engineBackend: String
    let visionBackend: String
    let maxNumImages: Int
    let maxNumTokens: Int
    let topK: Int
    let topP: Double
    let temperature: Double
    let seed: Int
    let automaticToolCalling: Bool
    let nativeCallCountPerRequest: Int
    let repairCallCount: Int
    let imageMessageForm: String

    enum CodingKeys: String, CodingKey {
      case modelArtifactSHA256 = "model_artifact_sha256"
      case engineBackend = "engine_backend"
      case visionBackend = "vision_backend"
      case maxNumImages = "max_num_images"
      case maxNumTokens = "max_num_tokens"
      case topK = "top_k"
      case topP = "top_p"
      case temperature
      case seed
      case automaticToolCalling = "automatic_tool_calling"
      case nativeCallCountPerRequest = "native_call_count_per_request"
      case repairCallCount = "repair_call_count"
      case imageMessageForm = "image_message_form"
    }
  }

  struct Phase: Decodable, Equatable, Sendable {
    let initialProbeFixtureID: String?
    let sequence: [String]
    let visualTokenBudgetsInGateOrder: [Int]
    let promptRelativePath: String
    let promptSHA256: String
    let schemaRelativePath: String?
    let schemaSHA256: String?
    let maximumOutputTokens: Int
    let maximumUTF8Bytes: Int
    let coldRestartBoundariesAfterPositions: [Int]?
    let stopOnFailure: Bool?
    let scoreBoundary: String?
    let stopLowerBudgetAfterFailure: Bool?

    enum CodingKeys: String, CodingKey {
      case initialProbeFixtureID = "initial_probe_fixture_id"
      case sequence
      case visualTokenBudgetsInGateOrder = "visual_token_budgets_in_gate_order"
      case promptRelativePath = "prompt_relative_path"
      case promptSHA256 = "prompt_sha256"
      case schemaRelativePath = "schema_relative_path"
      case schemaSHA256 = "schema_sha256"
      case maximumOutputTokens = "maximum_output_tokens"
      case maximumUTF8Bytes = "maximum_utf8_bytes"
      case coldRestartBoundariesAfterPositions =
        "cold_restart_boundaries_after_positions"
      case stopOnFailure = "stop_on_failure"
      case scoreBoundary = "score_boundary"
      case stopLowerBudgetAfterFailure = "stop_lower_budget_after_failure"
    }
  }

  struct BudgetStage: Decodable, Equatable, Sendable {
    let visualTokenBudget: Int
    let phases: [String]
    let condition: String

    enum CodingKeys: String, CodingKey {
      case visualTokenBudget = "visual_token_budget"
      case phases
      case condition
    }
  }

  struct CancellationStale: Decodable, Equatable, Sendable {
    let cancelFixtureID: String
    let postRestartFixtureID: String
    let requiresDistinctProcessEpoch: Bool
    let oldRequestIDMustNotAppearAfterRestart: Bool

    enum CodingKeys: String, CodingKey {
      case cancelFixtureID = "cancel_fixture_id"
      case postRestartFixtureID = "post_restart_fixture_id"
      case requiresDistinctProcessEpoch = "requires_distinct_process_epoch"
      case oldRequestIDMustNotAppearAfterRestart =
        "old_request_id_must_not_appear_after_restart"
    }
  }

  struct TechnicalQuality: Decodable, Equatable, Sendable {
    let sequence: [String]
    let modelCallCountPerFixture: Int
    let executionBoundary: String

    enum CodingKeys: String, CodingKey {
      case sequence
      case modelCallCountPerFixture = "model_call_count_per_fixture"
      case executionBoundary = "execution_boundary"
    }
  }

  struct DesktopReferenceFallback: Decodable, Equatable, Sendable {
    let conditionalOnAppTransportFailure: Bool
    let upstreamCommit: String
    let officialMacOSArchiveSHA256: String
    let loadedRuntimeDylibSHA256: String
    let visualTokenBudget: Int
    let externalTimeoutSeconds: Int
    let maxImagesControl: String

    enum CodingKeys: String, CodingKey {
      case conditionalOnAppTransportFailure =
        "conditional_on_app_transport_failure"
      case upstreamCommit = "upstream_commit"
      case officialMacOSArchiveSHA256 = "official_macos_archive_sha256"
      case loadedRuntimeDylibSHA256 = "loaded_runtime_dylib_sha256"
      case visualTokenBudget = "visual_token_budget"
      case externalTimeoutSeconds = "external_timeout_seconds"
      case maxImagesControl = "max_images_control"
    }
  }

  let contractVersion: String
  let modelVisibleContract: String
  let assetIndex: [Asset]
  let commonConfiguration: CommonConfiguration
  let transport: Phase
  let primitive: Phase
  let fullPrefill: Phase
  let technicalQuality: TechnicalQuality
  let cancellationStaleOutput: CancellationStale
  let budgetStageGateOrder: [BudgetStage]
  let desktopReferenceFallback: DesktopReferenceFallback

  enum CodingKeys: String, CodingKey {
    case contractVersion = "contract_version"
    case modelVisibleContract = "model_visible_contract"
    case assetIndex = "asset_index"
    case commonConfiguration = "common_configuration"
    case transport
    case primitive
    case fullPrefill = "full_prefill"
    case technicalQuality = "technical_quality"
    case cancellationStaleOutput = "cancellation_stale_output"
    case budgetStageGateOrder = "budget_stage_gate_order"
    case desktopReferenceFallback = "desktop_reference_fallback"
  }

  static func decodeAndValidate(_ data: Data) throws -> Self {
    guard SyntheticVisionV1Contract.sha256(data)
      == SyntheticVisionV1Contract.runtimePlanSHA256,
      let text = String(data: data, encoding: .utf8),
      !SyntheticVisionV1Contract.forbiddenEvaluatorTokens.contains(where: {
        text.localizedCaseInsensitiveContains($0)
      }),
      let object = try JSONSerialization.jsonObject(with: data)
        as? [String: Any],
      Set(object.keys) == Set([
        "contract_version", "model_visible_contract", "asset_index",
        "common_configuration", "transport", "primitive", "full_prefill",
        "technical_quality",
        "cancellation_stale_output", "budget_stage_gate_order",
        "desktop_reference_fallback",
      ])
    else { throw GITimelineError.syntheticFixtureIntegrity }

    let plan = try JSONDecoder().decode(Self.self, from: data)
    let budgets = [280, 140, 70]
    let phases = ["transport", "primitive", "full_prefill"]
    let expectedConditions = [
      "initial", "all_vt280_gates_pass", "all_vt140_gates_pass",
    ]
    let expectedAssetIDs = (1...25).map { String(format: "pxp-%03d", $0) }
    let expectedAllIDs = (1...26).map { String(format: "pxp-%03d", $0) }
    let assetsByID = Dictionary(
      uniqueKeysWithValues: plan.assetIndex.map { ($0.opaqueID, $0) }
    )
    guard plan.contractVersion == SyntheticVisionV1Contract.runtimePlanVersion,
      plan.modelVisibleContract
        == "opaque sanitized path plus exact image bytes and one frozen prompt; evaluator manifest is never loaded",
      plan.assetIndex.count == 25,
      Set(plan.assetIndex.map(\.opaqueID)) == Set(expectedAssetIDs),
      assetsByID.count == plan.assetIndex.count,
      plan.assetIndex.allSatisfy({ asset in
        asset.relativePath == "sanitized/\(asset.opaqueID).jpg"
          && asset.byteCount > 0
          && ImageStore.isValidSHA256(asset.sha256)
      }),
      plan.commonConfiguration == SyntheticVisionV1Contract.commonConfiguration,
      plan.transport.initialProbeFixtureID == "pxp-002",
      plan.transport.sequence == ["pxp-002", "pxp-003", "pxp-002"],
      plan.transport.visualTokenBudgetsInGateOrder == budgets,
      plan.transport.promptRelativePath
        == "contracts/transport-probe-prompt-v1.txt",
      plan.transport.promptSHA256
        == SyntheticVisionExactDataProbeContract.transportPromptSHA256,
      plan.transport.schemaRelativePath == nil,
      plan.transport.schemaSHA256 == nil,
      plan.transport.maximumOutputTokens == 16,
      plan.transport.maximumUTF8Bytes == 64,
      plan.transport.stopOnFailure == true,
      plan.primitive.sequence.count == 32,
      plan.primitive.coldRestartBoundariesAfterPositions == [12],
      plan.primitive.visualTokenBudgetsInGateOrder == budgets,
      plan.primitive.promptRelativePath
        == "contracts/engineering-prompt-v1.txt",
      plan.primitive.promptSHA256
        == SyntheticVisionExactDataProbeContract.engineeringPromptSHA256,
      plan.primitive.schemaRelativePath
        == "contracts/engineering-schema-v1.json",
      plan.primitive.schemaSHA256
        == SyntheticVisionExactDataProbeContract.engineeringSchemaSHA256,
      plan.primitive.maximumOutputTokens == 128,
      plan.primitive.maximumUTF8Bytes == 2_048,
      plan.primitive.stopOnFailure == true,
      plan.fullPrefill.sequence
        == ["pxp-011", "pxp-012", "pxp-013", "pxp-014"],
      plan.fullPrefill.visualTokenBudgetsInGateOrder == budgets,
      plan.fullPrefill.promptRelativePath
        == "contracts/full-prefill-prompt-v1.txt",
      plan.fullPrefill.promptSHA256
        == SyntheticVisionExactDataProbeContract.fullPrefillPromptSHA256,
      plan.fullPrefill.schemaRelativePath
        == "contracts/full-prefill-schema-v1.json",
      plan.fullPrefill.schemaSHA256
        == SyntheticVisionExactDataProbeContract.fullPrefillSchemaSHA256,
      plan.fullPrefill.maximumOutputTokens == 128,
      plan.fullPrefill.maximumUTF8Bytes == 8_192,
      plan.fullPrefill.stopLowerBudgetAfterFailure == true,
      plan.technicalQuality == SyntheticVisionV1Contract.technicalQuality,
      plan.budgetStageGateOrder.count == budgets.count,
      zip(plan.budgetStageGateOrder, budgets).enumerated().allSatisfy({
        index, pair in
        pair.0.visualTokenBudget == pair.1
          && pair.0.phases == phases
          && pair.0.condition == expectedConditions[index]
      }),
      plan.cancellationStaleOutput
        == SyntheticVisionV1Contract.cancellationStale,
      plan.desktopReferenceFallback
        == SyntheticVisionV1Contract.desktopReferenceFallback,
      Set(
        [plan.transport.initialProbeFixtureID].compactMap { $0 }
          + plan.transport.sequence + plan.primitive.sequence
          + plan.fullPrefill.sequence
          + plan.technicalQuality.sequence
          + [plan.cancellationStaleOutput.cancelFixtureID,
            plan.cancellationStaleOutput.postRestartFixtureID]
      ).isSubset(of: Set(expectedAllIDs))
    else { throw GITimelineError.syntheticFixtureIntegrity }
    return plan
  }
}

enum SyntheticVisionV1Contract {
  enum Mode: String, CaseIterable, Codable, Sendable {
    case transportInitial = "transport_initial"
    case transportSequence = "transport_sequence"
    case primitiveA = "primitive_a"
    case primitiveB = "primitive_b"
    case fullPrefill = "full_prefill"
    case cancellation = "cancellation"
    case staleFollowup = "stale_followup"

    var launchArgument: String {
      "--run-gi-synthetic-vision-v1-\(rawValue.replacingOccurrences(of: "_", with: "-"))"
    }
  }

  struct Request: Equatable, Sendable {
    let mode: Mode
    let configuration: InferenceConfiguration
  }

  static let runtimePlanVersion = "gi-synthetic-vision-runtime-plan-v1"
  static let harnessVersion = "gi-synthetic-vision-harness-v1"
  static let markerVersion = "gi-synthetic-vision-marker-v1"
  static let inputDirectoryName = "SyntheticVisionV1"
  static let runtimePlanFilename = "runtime-plan.json"
  static let runtimePlanSHA256 =
    "c59791d85a275406253c9ec9d685f21ce32a018bdfa3008b2178d8a56b0ca993"
  static let receiptMarker = "GI_SYNTHETIC_VISION_V1_RECEIPT"
  static let batchPassMarker = "GI_SYNTHETIC_VISION_V1_BATCH_PASS"
  static let batchFailMarker = "GI_SYNTHETIC_VISION_V1_BATCH_FAIL"
  static let descriptor = ModelDescriptor.liteRTGemma4E4B
  static let forbiddenEvaluatorTokens = [
    "expected_primitive_vector", "expected_technical_reason", "purpose",
    "fixture_label", "bristol_label", "manifest.json",
  ]
  static let commonConfiguration =
    SyntheticVisionV1RuntimePlan.CommonConfiguration(
      modelArtifactSHA256:
        SyntheticVisionExactDataProbeContract.modelArtifactSHA256,
      engineBackend: "cpu",
      visionBackend: "cpu",
      maxNumImages: 1,
      maxNumTokens: 1_536,
      topK: 1,
      topP: 1,
      temperature: 0,
      seed: 0,
      automaticToolCalling: false,
      nativeCallCountPerRequest: 1,
      repairCallCount: 0,
      imageMessageForm:
        "Message(contents:[Content.imageData(exactSanitizedData),Content.text(frozenPrompt)])"
    )
  static let cancellationStale =
    SyntheticVisionV1RuntimePlan.CancellationStale(
      cancelFixtureID: "pxp-002",
      postRestartFixtureID: "pxp-003",
      requiresDistinctProcessEpoch: true,
      oldRequestIDMustNotAppearAfterRestart: true
    )
  static let technicalQuality =
    SyntheticVisionV1RuntimePlan.TechnicalQuality(
      sequence: ["pxp-022", "pxp-023", "pxp-024", "pxp-025", "pxp-026"],
      modelCallCountPerFixture: 0,
      executionBoundary: "app_native_quality_gate_before_any_model_runtime"
    )
  static let desktopReferenceFallback =
    SyntheticVisionV1RuntimePlan.DesktopReferenceFallback(
      conditionalOnAppTransportFailure: true,
      upstreamCommit: "2117fc4314670e00047bc8469783f02a68c33f0c",
      officialMacOSArchiveSHA256:
        "d23cf189ce8f6bb2556c0a023805e245d1ec862434e501eb60f353488033c1b5",
      loadedRuntimeDylibSHA256:
        "2235a70a11a35f471e53717b0060449e319472f6d2f86b7993eccd9c70812afe",
      visualTokenBudget: 280,
      externalTimeoutSeconds: 30,
      maxImagesControl: "not_exposed_by_unmodified_upstream_v0.15.0"
    )

  static func isRequested(in arguments: [String]) -> Bool {
    arguments.contains { argument in
      Mode.allCases.contains { $0.launchArgument == argument }
    }
  }

  static func requested(in arguments: [String]) -> Request? {
    let modes = Mode.allCases.filter { mode in
      arguments.filter { $0 == mode.launchArgument }.count == 1
    }
    guard modes.count == 1,
      let configuration = InferenceConfiguration
        .internalDiagnosticConfiguration(arguments: arguments),
      configuration.usesFullPrefillCandidate,
      let budget = configuration.visualTokenBudget,
      [70, 140, 280].contains(budget)
    else { return nil }
    if [.cancellation, .staleFollowup].contains(modes[0]), budget != 280 {
      return nil
    }
    return Request(mode: modes[0], configuration: configuration)
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func sanitizedToken(_ raw: String) -> String {
    let result = raw.unicodeScalars.prefix(120).map { scalar -> Character in
      let value = scalar.value
      let permitted = (48...57).contains(value) || (65...90).contains(value)
        || (97...122).contains(value) || value == 45 || value == 46
        || value == 95
      return permitted ? Character(String(scalar)) : "_"
    }
    return result.isEmpty ? "unknown" : String(result)
  }
}

struct SyntheticVisionV1ReceiptEnvelope: Codable, Equatable, Sendable {
  let harnessVersion: String
  let runtimePlanSHA256: String
  let mode: SyntheticVisionV1Contract.Mode
  let sequencePosition: Int
  let opaqueFixtureID: String
  let receipt: SyntheticVisionExactDataProbeReceipt
}

private actor SyntheticVisionV1ModelCallStartSignal {
  private var didStart = false

  func signal() { didStart = true }
  func hasStarted() -> Bool { didStart }
}

@MainActor
final class SyntheticVisionV1Harness {
  private let runtime: ModelRuntimeCoordinator
  private let journalIsolationAttested: Bool
  private let fileManager = FileManager.default

  init(
    runtime: ModelRuntimeCoordinator,
    journalIsolationAttested: Bool
  ) {
    self.runtime = runtime
    self.journalIsolationAttested = journalIsolationAttested
  }

  func run(arguments: [String]) async -> [String] {
    guard let request = SyntheticVisionV1Contract.requested(in: arguments)
    else {
      return [batchMarker(
        passed: false,
        request: nil,
        receiptCount: 0,
        error: "selector_or_mode_contract_invalid"
      )]
    }
    guard journalIsolationAttested else {
      return [batchMarker(
        passed: false,
        request: request,
        receiptCount: 0,
        error: "journal_isolation_unattested"
      )]
    }

    var emittedReceiptCount = 0
    do {
      let configured = await runtime.configurationSnapshot()
      guard configured == request.configuration,
        configured.permitsRawPhotoV12TuningOverride(request.configuration),
        ModelCatalog.normalFlowSelection == SyntheticVisionV1Contract.descriptor
      else { throw GITimelineError.invalidModelDescriptor }
      guard let verification = try await runtime.receipt(
        for: SyntheticVisionV1Contract.descriptor
      ),
        verification.matches(SyntheticVisionV1Contract.descriptor),
        verification.locationKind == .applicationBundle,
        verification.appBuildIdentity == .current
      else { throw GITimelineError.modelNotVerified }

      let inputRoot = try inputRoot()
      let planData = try Data(
        contentsOf: inputRoot.appendingPathComponent(
          SyntheticVisionV1Contract.runtimePlanFilename
        ),
        options: .mappedIfSafe
      )
      let plan = try SyntheticVisionV1RuntimePlan.decodeAndValidate(planData)
      try validateBundledInputRoot(inputRoot, plan: plan)
      guard await runtime.prepareLocalAnalysis() == .ready else {
        throw GITimelineError.modelNotVerified
      }

      let mode = request.mode
      let phase: SyntheticVisionV1RuntimePlan.Phase
      let fixtureIDs: [String]
      switch mode {
      case .transportInitial:
        phase = plan.transport
        fixtureIDs = [try required(plan.transport.initialProbeFixtureID)]
      case .transportSequence:
        phase = plan.transport
        fixtureIDs = plan.transport.sequence
      case .primitiveA:
        phase = plan.primitive
        fixtureIDs = Array(plan.primitive.sequence.prefix(12))
      case .primitiveB:
        phase = plan.primitive
        fixtureIDs = Array(plan.primitive.sequence.dropFirst(12))
      case .fullPrefill:
        phase = plan.fullPrefill
        fixtureIDs = plan.fullPrefill.sequence
      case .cancellation:
        phase = plan.primitive
        fixtureIDs = [plan.cancellationStaleOutput.cancelFixtureID]
      case .staleFollowup:
        phase = plan.primitive
        fixtureIDs = [plan.cancellationStaleOutput.postRestartFixtureID]
      }
      let promptData = try validatedResourceData(
        phase.promptRelativePath,
        expectedSHA256: phase.promptSHA256,
        under: inputRoot
      )
      let schemaData = try phase.schemaRelativePath.map { path in
        try validatedResourceData(
          path,
          expectedSHA256: try required(phase.schemaSHA256),
          under: inputRoot
        )
      }

      for (offset, fixtureID) in fixtureIDs.enumerated() {
        let position = mode == .primitiveB ? offset + 13 : offset + 1
        let receipt: SyntheticVisionExactDataProbeReceipt
        if mode == .cancellation {
          let startSignal = SyntheticVisionV1ModelCallStartSignal()
          let call = Task {
            try await self.runOne(
              fixtureID: fixtureID,
              plan: plan,
              promptData: promptData,
              schemaData: schemaData,
              inputRoot: inputRoot,
              configuration: request.configuration,
              onModelCallStarted: {
                Task { await startSignal.signal() }
              }
            )
          }
          for _ in 0..<1_000 {
            if await startSignal.hasStarted() { break }
            try? await Task.sleep(for: .milliseconds(10))
          }
          guard await startSignal.hasStarted() else {
            call.cancel()
            _ = try? await call.value
            throw GITimelineError.operationInProgress
          }
          call.cancel()
          receipt = try await call.value
        } else {
          receipt = try await runOne(
            fixtureID: fixtureID,
            plan: plan,
            promptData: promptData,
            schemaData: schemaData,
            inputRoot: inputRoot,
            configuration: request.configuration,
            onModelCallStarted: {}
          )
        }
        guard receipt.hasValidInternalIntegrity,
          receipt.configurationID == request.configuration.id,
          receipt.visualTokenBudget == request.configuration.visualTokenBudget,
          receipt.promptSHA256 == phase.promptSHA256,
          receipt.responseSchemaSHA256 == phase.schemaSHA256,
          receipt.expectedImageSHA256
            == plan.assetIndex.first(where: { $0.opaqueID == fixtureID })?.sha256
        else { throw GITimelineError.syntheticFixtureIntegrity }
        let marker = try receiptMarker(
          receipt,
          request: request,
          fixtureID: fixtureID,
          position: position
        )
        Self.emit(marker)
        emittedReceiptCount += 1
        let expectedTerminal: Bool
        if mode == .cancellation {
          expectedTerminal = receipt.terminal == .cancelled
            && receipt.modelCallStarted && receipt.modelCallCount == 1
            && receipt.repairCallCount == 0
            && receipt.nativeCallCompletionObserved
        } else {
          expectedTerminal = receipt.terminal == .success
        }
        guard expectedTerminal else {
          return [batchMarker(
            passed: false,
            request: request,
            receiptCount: emittedReceiptCount,
            error: receipt.terminal.rawValue
          )]
        }
      }
      return [batchMarker(
        passed: true,
        request: request,
        receiptCount: fixtureIDs.count,
        error: "none"
      )]
    } catch {
      return [batchMarker(
        passed: false,
        request: request,
        receiptCount: emittedReceiptCount,
        error: sanitizedError(error)
      )]
    }
  }

  private func runOne(
    fixtureID: String,
    plan: SyntheticVisionV1RuntimePlan,
    promptData: Data,
    schemaData: Data?,
    inputRoot: URL,
    configuration: InferenceConfiguration,
    onModelCallStarted: @escaping @Sendable () -> Void
  ) async throws -> SyntheticVisionExactDataProbeReceipt {
    guard let asset = plan.assetIndex.first(where: { $0.opaqueID == fixtureID })
    else { throw GITimelineError.syntheticFixtureIntegrity }
    let imageData = try validatedResourceData(
      asset.relativePath,
      expectedSHA256: asset.sha256,
      expectedByteCount: asset.byteCount,
      under: inputRoot
    )
    try ImageStore.validateSanitizedJournalJPEG(
      imageData,
      expectedSHA256: asset.sha256
    )
    return try await runtime.runSyntheticVisionExactDataProbe(
      SyntheticVisionV1Contract.descriptor,
      imageData: imageData,
      expectedImageSHA256: asset.sha256,
      promptData: promptData,
      responseSchemaData: schemaData,
      onModelCallStarted: onModelCallStarted,
      configuration: configuration
    )
  }

  private func inputRoot() throws -> URL {
    guard let resourceRoot = Bundle.main.resourceURL?.standardizedFileURL
    else { throw GITimelineError.syntheticFixtureIntegrity }
    let root = resourceRoot.appendingPathComponent(
      SyntheticVisionV1Contract.inputDirectoryName,
      isDirectory: true
    ).standardizedFileURL
    guard root.path.hasPrefix(resourceRoot.path + "/") else {
      throw GITimelineError.syntheticFixtureIntegrity
    }
    return root
  }

  private func validateBundledInputRoot(
    _ root: URL,
    plan: SyntheticVisionV1RuntimePlan
  ) throws {
    let expectedFiles = Set(
      [SyntheticVisionV1Contract.runtimePlanFilename]
        + plan.assetIndex.map(\.relativePath)
        + [plan.transport.promptRelativePath,
          plan.primitive.promptRelativePath,
          plan.fullPrefill.promptRelativePath]
        + [plan.primitive.schemaRelativePath,
          plan.fullPrefill.schemaRelativePath].compactMap { $0 }
    )
    let keys: Set<URLResourceKey> = [
      .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
    ]
    let rootValues = try root.resourceValues(forKeys: keys)
    guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true,
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: Array(keys),
        options: [],
        errorHandler: { _, _ in false }
      )
    else { throw GITimelineError.syntheticFixtureIntegrity }
    let rootPath = root.path + "/"
    var found = Set<String>()
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: keys)
      guard values.isSymbolicLink != true else {
        throw GITimelineError.syntheticFixtureIntegrity
      }
      if values.isDirectory == true { continue }
      guard values.isRegularFile == true,
        url.standardizedFileURL.path.hasPrefix(rootPath)
      else { throw GITimelineError.syntheticFixtureIntegrity }
      let relative = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
      guard expectedFiles.contains(relative), found.insert(relative).inserted
      else { throw GITimelineError.syntheticFixtureIntegrity }
    }
    guard found == expectedFiles else {
      throw GITimelineError.syntheticFixtureIntegrity
    }
  }

  private func validatedResourceData(
    _ relativePath: String,
    expectedSHA256: String,
    expectedByteCount: Int? = nil,
    under root: URL
  ) throws -> Data {
    guard !(relativePath as NSString).pathComponents.contains("..") else {
      throw GITimelineError.syntheticFixtureIntegrity
    }
    let url = root.appendingPathComponent(relativePath).standardizedFileURL
    guard url.path.hasPrefix(root.path + "/") else {
      throw GITimelineError.syntheticFixtureIntegrity
    }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard SyntheticVisionV1Contract.sha256(data) == expectedSHA256,
      expectedByteCount.map { $0 == data.count } ?? true
    else { throw GITimelineError.syntheticFixtureIntegrity }
    return data
  }

  private func receiptMarker(
    _ receipt: SyntheticVisionExactDataProbeReceipt,
    request: SyntheticVisionV1Contract.Request,
    fixtureID: String,
    position: Int
  ) throws -> String {
    let envelope = SyntheticVisionV1ReceiptEnvelope(
      harnessVersion: SyntheticVisionV1Contract.harnessVersion,
      runtimePlanSHA256: SyntheticVisionV1Contract.runtimePlanSHA256,
      mode: request.mode,
      sequencePosition: position,
      opaqueFixtureID: fixtureID,
      receipt: receipt
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(envelope)
    return [
      SyntheticVisionV1Contract.receiptMarker,
      "marker_contract=\(SyntheticVisionV1Contract.markerVersion)",
      "mode=\(request.mode.rawValue)",
      "visual_tokens=\(request.configuration.visualTokenBudget ?? -1)",
      "position=\(position)",
      "opaque_id=\(fixtureID)",
      "envelope_sha256=\(SyntheticVisionV1Contract.sha256(data))",
      "envelope_utf8_base64=\(data.base64EncodedString())",
    ].joined(separator: " ")
  }

  private func batchMarker(
    passed: Bool,
    request: SyntheticVisionV1Contract.Request?,
    receiptCount: Int,
    error: String
  ) -> String {
    [
      passed
        ? SyntheticVisionV1Contract.batchPassMarker
        : SyntheticVisionV1Contract.batchFailMarker,
      "marker_contract=\(SyntheticVisionV1Contract.markerVersion)",
      "runtime_plan_sha256=\(SyntheticVisionV1Contract.runtimePlanSHA256)",
      "mode=\(request?.mode.rawValue ?? "unresolved")",
      "visual_tokens=\(request?.configuration.visualTokenBudget ?? -1)",
      "process_id=\(SyntheticVisionExactDataProbeContract.processID)",
      "process_epoch=\(SyntheticVisionExactDataProbeContract.processEpochID)",
      "receipt_count=\(receiptCount)",
      "journal_isolation=\(journalIsolationAttested)",
      "error=\(SyntheticVisionV1Contract.sanitizedToken(error))",
    ].joined(separator: " ")
  }

  private func sanitizedError(_ error: Error) -> String {
    if let staged = error as? StagedInferenceError {
      return "StagedInferenceError.\(staged.stage.rawValue)"
    }
    if let app = error as? GITimelineError {
      return "GITimelineError.\(String(describing: app))"
    }
    return String(reflecting: type(of: error))
  }

  private func required<T>(_ value: T?) throws -> T {
    guard let value else { throw GITimelineError.syntheticFixtureIntegrity }
    return value
  }

  private static func emit(_ marker: String) {
    print(marker)
    fflush(stdout)
  }
}
#endif

#if HACKATHON_EMBEDDED_GEMMA
@preconcurrency import LiteRTLM
import CryptoKit
import Darwin
import Foundation
import GITimelineCore
import SwiftData
import UIKit

/// Synthetic fixtures available to the non-UI Hackathon acceptance harness.
/// This intentionally does not expose the DEBUG lab, model importer, model
/// picker, or fake provider in the committed Hackathon configuration.
enum EmbeddedGemmaHarnessFixture: String, CaseIterable, Codable, Sendable {
  case brown
  case green
  case control

  var resourceName: String {
    switch self {
    case .brown: return "synthetic-brown-clay.svg"
    case .green: return "synthetic-green-clay.svg"
    case .control: return "synthetic-control-geometric.svg"
    }
  }

  var expectedDominantColor: DominantColorResult {
    switch self {
    case .brown: return .brown
    case .green: return .green
    case .control: return .other
    }
  }

  var bundledSHA256: String {
    switch self {
    case .brown: return "fd8a75195b33e5faaf1e13aae801c97485be5a3a65b40c28c34920b2b8a0ee18"
    case .green: return "d9e82709870c9c18b8e48c5c1477ca4db525447828799d3b0b612f74140a6911"
    case .control: return "9cb76c4d0bc72096e3dc08db468000d1db6a792542d6f1f5a2ec3ad940897fc7"
    }
  }

  func verifiedBundledData(bundle: Bundle = .main) throws -> Data {
    guard let url = bundle.url(forResource: resourceName, withExtension: "png") else {
      throw GITimelineError.syntheticFixtureIntegrity
    }
    let data = try Data(contentsOf: url)
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard hash == bundledSHA256 else { throw GITimelineError.syntheticFixtureIntegrity }
    return data
  }
}

struct EmbeddedGemmaHarnessResult: Sendable {
  let evidenceURL: URL
  let consoleSummary: String
}

/// Preparation probe for either the exact public raw-photo control or its
/// internal GPU-main/CPU-vision70 A/B candidate. It writes no journal data and
/// uses the ordinary prepareLocalAnalysis path, whose 30-second caller deadline
/// contains the caller while a non-cooperative native initialization may continue
/// quarantined. Flushed stage markers localize that boundary for a bounded host run.
@MainActor
final class AppStoreRawImageV1PreparationDiagnosticHarness {
  private let runtime: ModelRuntimeCoordinator
  private let imageStore: ImageStore?

  init(runtime: ModelRuntimeCoordinator, imageStore: ImageStore? = nil) {
    self.runtime = runtime
    self.imageStore = imageStore
  }

  func run(arguments: [String]) async -> String {
    let contract = AppStoreRawImageV1PreparationDiagnosticContract.self
    let clock = ContinuousClock()
    let totalStart = clock.now
    var receiptSeconds: Double?
    let directImageRequested = contract.requestsDirectImageData(in: arguments)
    let generationAPI = contract.generationAPI(in: arguments) ?? .streaming
    let requestedCacheMode = contract.cacheMode(in: arguments)
    let actualCacheMode = await runtime.engineCacheModeSnapshot()
    let previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
    UIApplication.shared.isIdleTimerDisabled = true
    defer { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }

    guard contract.isValidRequest(in: arguments) else {
      let state = await runtime.engineState(contract.descriptor)
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: nil,
        engineInitializationSeconds: nil,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: state,
        cacheMode: actualCacheMode,
        errorClass: "selector_or_argument_contract_invalid"
      )
    }
    guard let expectedConfiguration = contract.requestedConfiguration(in: arguments)
    else {
      let state = await runtime.engineState(contract.descriptor)
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: nil,
        engineInitializationSeconds: nil,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: state,
        cacheMode: actualCacheMode,
        errorClass: "configuration_selector_unresolved"
      )
    }

    let configuration = await runtime.configurationSnapshot()
    emit(contract.configurationMarker(
      configuration,
      expected: expectedConfiguration,
      selectorPresent: true,
      cacheMode: actualCacheMode,
      idleTimerDisabled: UIApplication.shared.isIdleTimerDisabled,
      generationAPI: generationAPI
    ))
    guard configuration == expectedConfiguration,
      actualCacheMode == requestedCacheMode
    else {
      let state = await runtime.engineState(contract.descriptor)
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: nil,
        engineInitializationSeconds: nil,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: state,
        cacheMode: actualCacheMode,
        errorClass: "configuration_drift",
        configuration: expectedConfiguration
      )
    }

    // `prepareLocalAnalysis()` is the exact ordinary app preparation entry
    // point. Bind its catalog selection to this diagnostic's descriptor before
    // timing it so a future catalog change cannot produce misleading E4B
    // preparation evidence.
    guard ModelCatalog.normalFlowSelection == contract.descriptor else {
      let state = await runtime.engineState(contract.descriptor)
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: nil,
        engineInitializationSeconds: nil,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: state,
        cacheMode: actualCacheMode,
        errorClass: "normal_selection_drift",
        configuration: expectedConfiguration
      )
    }

    emit(contract.receiptStartMarker())
    let receiptStart = clock.now
    do {
      let receipt = try await runtime.receipt(for: contract.descriptor)
      receiptSeconds = receiptStart.duration(to: clock.now).secondsDouble
      guard let receipt,
        receipt.matches(contract.descriptor),
        receipt.locationKind == .applicationBundle,
        receipt.appBuildIdentity == .current
      else {
        let state = await runtime.engineState(contract.descriptor)
        return contract.terminalMarker(
          passed: false,
          receiptSeconds: receiptSeconds,
          engineInitializationSeconds: nil,
          totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
          engineState: state,
          cacheMode: actualCacheMode,
          errorClass: "exact_bundled_receipt_unavailable",
          configuration: expectedConfiguration
        )
      }
    } catch {
      receiptSeconds = receiptStart.duration(to: clock.now).secondsDouble
      let state = await runtime.engineState(contract.descriptor)
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: receiptSeconds,
        engineInitializationSeconds: nil,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: state,
        cacheMode: actualCacheMode,
        errorClass: "receipt_resolution_failed",
        configuration: expectedConfiguration
      )
    }
    emit(contract.receiptVerifiedMarker(elapsedSeconds: receiptSeconds ?? 0))

    do {
      let preparedCache = try await runtime.prepareEngineCache(
        for: contract.descriptor
      )
      #if targetEnvironment(simulator)
      let simulatorFileProtectionUnavailable = true
      #else
      let simulatorFileProtectionUnavailable = false
      #endif
      guard contract.cachePreparationMatches(
        preparedCache,
        expectedMode: actualCacheMode,
        simulatorFileProtectionUnavailable: simulatorFileProtectionUnavailable
      ) else {
        throw GITimelineError.invalidModelDescriptor
      }
      emit(contract.cacheReadyMarker(preparation: preparedCache))
    } catch {
      let state = await runtime.engineState(contract.descriptor)
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: receiptSeconds,
        engineInitializationSeconds: nil,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: state,
        cacheMode: actualCacheMode,
        errorClass: contract.cachePreparationErrorClass(error),
        configuration: expectedConfiguration
      )
    }

    let priorState = await runtime.engineState(contract.descriptor)
    emit(contract.engineInitializationStartMarker(priorState: priorState))
    let engineStart = clock.now
    let readiness = await runtime.prepareLocalAnalysis()
    let engineInitializationSeconds = engineStart.duration(to: clock.now).secondsDouble
    let terminalState = await runtime.engineState(contract.descriptor)
    let passed = readiness == .ready && terminalState == .ready
    guard passed else {
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: receiptSeconds,
        engineInitializationSeconds: engineInitializationSeconds,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: terminalState,
        cacheMode: actualCacheMode,
        errorClass: "runtime_not_ready",
        directImageRequested: directImageRequested,
        configuration: expectedConfiguration
      )
    }
    guard directImageRequested else {
      return contract.terminalMarker(
        passed: true,
        receiptSeconds: receiptSeconds,
        engineInitializationSeconds: engineInitializationSeconds,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: terminalState,
        cacheMode: actualCacheMode,
        errorClass: "none",
        configuration: expectedConfiguration
      )
    }
    guard let imageStore else {
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: receiptSeconds,
        engineInitializationSeconds: engineInitializationSeconds,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: terminalState,
        cacheMode: actualCacheMode,
        errorClass: "isolated_image_store_unavailable",
        directImageRequested: true,
        configuration: expectedConfiguration
      )
    }

    guard let fixture = contract.requestedRegressionFixture(in: arguments) else {
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: receiptSeconds,
        engineInitializationSeconds: engineInitializationSeconds,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: terminalState,
        cacheMode: actualCacheMode,
        errorClass: "fixture_selector_unresolved",
        directImageRequested: true,
        configuration: expectedConfiguration
      )
    }
    let prepared: PreparedDraft
    do {
      prepared = try imageStore.prepare(fixture.verifiedBundledData())
      guard prepared.reference.sha256 == fixture.sanitizedSHA256
      else { throw GITimelineError.syntheticFixtureIntegrity }
    } catch {
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: receiptSeconds,
        engineInitializationSeconds: engineInitializationSeconds,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: terminalState,
        cacheMode: actualCacheMode,
        errorClass: "synthetic_fixture_preparation_failed",
        directImageRequested: true,
        regressionFixture: fixture,
        configuration: expectedConfiguration
      )
    }
    defer { imageStore.deleteBestEffort(prepared.url) }
    emit(contract.directFixtureReadyMarker(
      fixtureID: fixture.rawValue,
      bundledSHA256: fixture.bundledSHA256,
      sanitizedSHA256: prepared.reference.sha256
    ))
    emit(contract.directImageRequestStartMarker(generationAPI: generationAPI))
    let imageRequestStart = clock.now
    let raw: String
    do {
      switch generationAPI {
      case .streaming:
        raw = try await runtime.analyze(
          contract.descriptor,
          draftURL: prepared.url,
          expectedSHA256: prepared.reference.sha256
        )
      case .synchronousDiagnostic:
        raw = try await runtime.analyzeSynchronouslyForDiagnostic(
          contract.descriptor,
          draftURL: prepared.url,
          expectedSHA256: prepared.reference.sha256
        )
      }
    } catch {
      // The synchronous API blocks in native WaitUntilDone and cannot be
      // cooperatively cancelled. If the outer deadline quarantined it, awaiting
      // repair cleanup would wait back through the blocked adapter and suppress
      // this terminal receipt. The host terminates this isolated process before
      // any later diagnostic launch.
      if generationAPI == .streaming {
        await runtime.discardRepairContext(contract.descriptor, draftURL: prepared.url)
      }
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: receiptSeconds,
        engineInitializationSeconds: engineInitializationSeconds,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: await runtime.engineState(contract.descriptor),
        cacheMode: actualCacheMode,
        errorClass: "direct_image_request_failed",
        directImageRequested: true,
        imageRequestSeconds: imageRequestStart.duration(to: clock.now).secondsDouble,
        regressionFixture: fixture,
        configuration: expectedConfiguration
      )
    }
    let imageRequestSeconds = imageRequestStart.duration(to: clock.now).secondsDouble
    await runtime.discardRepairContext(contract.descriptor, draftURL: prepared.url)
    let suggestion: PhotoSuggestionV1
    let canonical: String
    do {
      suggestion = try PhotoSuggestionV1Parser.parseCurrentRawOutput(raw)
      canonical = try PhotoSuggestionV1Parser.canonicalJSON(suggestion)
    } catch {
      return contract.terminalMarker(
        passed: false,
        receiptSeconds: receiptSeconds,
        engineInitializationSeconds: engineInitializationSeconds,
        totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
        engineState: await runtime.engineState(contract.descriptor),
        cacheMode: actualCacheMode,
        errorClass: contract.strictSchemaErrorClass(error),
        directImageRequested: true,
        imageRequestSeconds: imageRequestSeconds,
        regressionFixture: fixture,
        configuration: expectedConfiguration
      )
    }
    let canonicalOutputSHA256 = SHA256.hash(data: Data(canonical.utf8))
      .map { String(format: "%02x", $0) }.joined()
    let regressionExpectationPassed = contract.regressionExpectationSatisfied(
      suggestion,
      for: fixture
    )
    return contract.terminalMarker(
      passed: regressionExpectationPassed,
      receiptSeconds: receiptSeconds,
      engineInitializationSeconds: engineInitializationSeconds,
      totalSeconds: totalStart.duration(to: clock.now).secondsDouble,
      engineState: await runtime.engineState(contract.descriptor),
      cacheMode: actualCacheMode,
      errorClass: regressionExpectationPassed ? "none" : "fixture_expectation_failed",
      directImageRequested: true,
      imageRequestSeconds: imageRequestSeconds,
      strictPhotoSuggestionParsed: true,
      canonicalOutputSHA256: canonicalOutputSHA256,
      suggestion: suggestion,
      regressionFixture: fixture,
      regressionExpectationPassed: regressionExpectationPassed,
      configuration: expectedConfiguration
    )
  }

  private func emit(_ marker: String) {
    print(marker)
    fflush(stdout)
  }
}

struct PhysicalRawImageDiagnosticHarnessResult: Sendable {
  let consoleMarker: String
}

private struct PhysicalRawImageDiagnosticEvidenceStore {
  let checkpointURL: URL

  init(runID: UUID) throws {
    let root = try AppFolders.applicationSupport()
      .appendingPathComponent("CompletionEvidence", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try AppFolders.protect(root)
    let directory = root.appendingPathComponent(
      "physical-raw-image-one-shot-\(runID.uuidString.lowercased())",
      isDirectory: true
    )
    guard !FileManager.default.fileExists(atPath: directory.path) else {
      throw GITimelineError.evidenceAlreadyExists
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    try AppFolders.protect(directory)
    checkpointURL = directory.appendingPathComponent("checkpoint.json")
  }

  func write(_ checkpoint: PhysicalRawImageDiagnosticCheckpoint) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(checkpoint).write(to: checkpointURL, options: .atomic)
    try AppFolders.protect(checkpointURL)
  }
}

/// One synthetic image request for stage-level diagnosis only. This never uses
/// the app-scoped bridge coordinator, touches the journal store, or upgrades a
/// physical raw-image acceptance gate by itself.
@MainActor
final class PhysicalRawImageDiagnosticHarness {
  private let request: PhysicalRawImageDiagnosticRequest

  init(request: PhysicalRawImageDiagnosticRequest = .brownColorProbe) {
    self.request = request
  }

  func run() async throws -> PhysicalRawImageDiagnosticHarnessResult {
    let runID = UUID()
    let startedAt = Date()
    let clock = ContinuousClock()
    let totalStart = clock.now
    let descriptor = PhysicalRawImageDiagnosticContract.descriptor
    let configuration = PhysicalRawImageDiagnosticContract.configuration
    guard let fixture = EmbeddedGemmaHarnessFixture(rawValue: request.fixtureID) else {
      throw PhysicalRawImageDiagnosticError.configurationDrift
    }
    let runtime = ModelRuntimeCoordinator(configuration: configuration)
    let imageStore = ImageStore()
    let checkpointStore = try PhysicalRawImageDiagnosticEvidenceStore(runID: runID)

    var preparedDraft: PreparedDraft?
    var currentPhase = PhysicalRawImageDiagnosticPhase.started
    var stageHistory: [PhysicalRawImageDiagnosticPhase] = []
    var sanitizedImageSHA256: String?
    var receiptVerified = false
    var preparationSeconds: Double?
    var imageRequestSeconds: Double?
    var totalSeconds: Double?
    var peakResidentMemoryBytes: UInt64?
    var dominantColor: DominantColorResult?
    var configuredVisualTokenBudgetReadback: Int?
    var structuredInitialSeconds: Double?
    var structuredRepairSeconds: Double?
    var structuredSeconds: Double?
    var repairUsed = false
    var strictStructuredParsed = false
    var structuredExpectationPassed = false
    var structuredObservation: VisualObservation?
    var canonicalObservationSHA256: String?
    var outcome = "RUNNING"
    var failureStage: String?
    var errorClass: String?

    defer {
      if let preparedDraft { imageStore.deleteBestEffort(preparedDraft.url) }
    }

    func samplePeakMemory() {
      guard let sample = Self.processResidentPeakBytes() else { return }
      peakResidentMemoryBytes = max(peakResidentMemoryBytes ?? 0, sample)
    }

    func checkpoint(_ phase: PhysicalRawImageDiagnosticPhase) throws -> PhysicalRawImageDiagnosticCheckpoint {
      currentPhase = phase
      if stageHistory.last != phase { stageHistory.append(phase) }
      samplePeakMemory()
      let value = PhysicalRawImageDiagnosticCheckpoint(
        runID: runID,
        startedAt: startedAt,
        updatedAt: Date(),
        phase: phase,
        stageHistory: stageHistory,
        diagnosticRequest: request,
        fixtureID: fixture.rawValue,
        bundledFixtureSHA256: fixture.bundledSHA256,
        sanitizedImageSHA256: sanitizedImageSHA256,
        receiptVerified: receiptVerified,
        preparationSeconds: preparationSeconds,
        imageRequestSeconds: imageRequestSeconds,
        totalSeconds: totalSeconds,
        peakResidentMemoryBytes: peakResidentMemoryBytes,
        dominantColor: dominantColor,
        configuredVisualTokenBudgetReadback: configuredVisualTokenBudgetReadback,
        structuredInitialSeconds: structuredInitialSeconds,
        structuredRepairSeconds: structuredRepairSeconds,
        structuredSeconds: structuredSeconds,
        repairUsed: repairUsed,
        strictStructuredParsed: strictStructuredParsed,
        structuredExpectationPassed: structuredExpectationPassed,
        structuredObservation: structuredObservation,
        canonicalObservationSHA256: canonicalObservationSHA256,
        outcome: outcome,
        failureStage: failureStage,
        errorClass: errorClass
      )
      try checkpointStore.write(value)
      return value
    }

    _ = try checkpoint(.started)

    do {
      #if targetEnvironment(simulator)
      throw PhysicalRawImageDiagnosticError.wrongPlatform
      #else
      guard await runtime.configurationSnapshot() == configuration,
        !configuration.usesLocalPixelBridge
      else { throw PhysicalRawImageDiagnosticError.configurationDrift }

      guard let receipt = try await runtime.receipt(for: descriptor),
        receipt.matches(descriptor),
        receipt.locationKind == .applicationBundle,
        receipt.appBuildIdentity == .current
      else { throw PhysicalRawImageDiagnosticError.exactBundledReceiptUnavailable }
      receiptVerified = true
      _ = try checkpoint(.receiptVerified)

      let prepared = try imageStore.prepare(fixture.verifiedBundledData())
      preparedDraft = prepared
      sanitizedImageSHA256 = prepared.reference.sha256
      if request == .controlStructuredObservation,
        sanitizedImageSHA256 != PhysicalRawImageDiagnosticContract.sanitizedControlFixtureSHA256
      {
        throw GITimelineError.syntheticFixtureIntegrity
      }
      _ = try checkpoint(.fixturePrepared)

      let preparationStart = clock.now
      do {
        let preparation = try await runtime.prepare(descriptor)
        preparationSeconds = max(
          preparation.seconds,
          preparationStart.duration(to: clock.now).secondsDouble
        )
      } catch {
        preparationSeconds = preparationStart.duration(to: clock.now).secondsDouble
        throw error
      }
      guard await runtime.engineState(descriptor) == .ready else {
        throw StagedInferenceError(
          stage: .engineInitialization,
          underlying: GITimelineError.modelNotVerified
        )
      }
      // The process-global LiteRT flag is now scoped to the exact native stream
      // and restored immediately afterward. Record the immutable requested
      // configuration here; the stream-scoped lease is covered separately.
      configuredVisualTokenBudgetReadback = InferenceConfiguration.appStoreRawImageV1.visualTokenBudget
      guard configuredVisualTokenBudgetReadback
        == PhysicalRawImageDiagnosticContract.visualTokenBudget
      else {
        throw PhysicalRawImageDiagnosticError.configurationDrift
      }
      _ = try checkpoint(.engineReady)

      switch request {
      case .brownColorProbe, .controlColorProbe:
        _ = try checkpoint(.imageRequestStarted)
        let requestStart = clock.now
        let raw: String
        do {
          raw = try await runtime.dominantColorProbe(descriptor, draftURL: prepared.url)
          imageRequestSeconds = requestStart.duration(to: clock.now).secondsDouble
        } catch {
          imageRequestSeconds = requestStart.duration(to: clock.now).secondsDouble
          throw error
        }
        let parsed = try DominantColorResult.parse(raw)
        dominantColor = parsed
        guard parsed == fixture.expectedDominantColor else {
          throw PhysicalRawImageDiagnosticError.unexpectedDominantColor
        }
        outcome = "DIAGNOSTIC_PASS"

      case .controlStructuredObservation:
        _ = try checkpoint(.structuredRequestStarted)
        let structuredStart = clock.now
        let initialStart = clock.now
        let initial: String
        do {
          initial = try await runtime.analyze(descriptor, draftURL: prepared.url)
          structuredInitialSeconds = initialStart.duration(to: clock.now).secondsDouble
        } catch {
          structuredInitialSeconds = initialStart.duration(to: clock.now).secondsDouble
          structuredSeconds = structuredStart.duration(to: clock.now).secondsDouble
          throw error
        }
        structuredSeconds = structuredStart.duration(to: clock.now).secondsDouble
        _ = try checkpoint(.structuredRequestCompleted)

        let observation: VisualObservation
        do {
          observation = try ObservationParser.parse(initial)
          await runtime.discardRepairContext(descriptor, draftURL: prepared.url)
        } catch let parseError {
          repairUsed = true
          _ = try checkpoint(.structuredRepairStarted)
          let repairStart = clock.now
          let repaired: String
          do {
            repaired = try await runtime.repair(
              descriptor,
              draftURL: prepared.url,
              errors: parseError.localizedDescription
            )
            structuredRepairSeconds = repairStart.duration(to: clock.now).secondsDouble
          } catch {
            structuredRepairSeconds = repairStart.duration(to: clock.now).secondsDouble
            structuredSeconds = structuredStart.duration(to: clock.now).secondsDouble
            throw error
          }
          structuredSeconds = structuredStart.duration(to: clock.now).secondsDouble
          _ = try checkpoint(.structuredRepairCompleted)
          observation = try ObservationParser.parse(repaired)
        }

        strictStructuredParsed = true
        structuredObservation = observation
        structuredExpectationPassed =
          PhysicalRawImageDiagnosticContract.structuredControlExpectationSatisfied(observation)
        let canonical = try ObservationParser.canonicalJSON(observation)
        canonicalObservationSHA256 = Self.sha256(Data(canonical.utf8))
        guard structuredExpectationPassed else {
          throw PhysicalRawImageDiagnosticError.structuredExpectationFailed
        }
        _ = try checkpoint(.structuredValidationCompleted)
        outcome = repairUsed ? "DIAGNOSTIC_PASS_AFTER_REPAIR" : "DIAGNOSTIC_PASS"

      case .invalidConfiguration:
        throw PhysicalRawImageDiagnosticError.configurationDrift
      }
      totalSeconds = totalStart.duration(to: clock.now).secondsDouble
      await runtime.invalidate(descriptor)
      let finalCheckpoint = try checkpoint(.completed)
      return PhysicalRawImageDiagnosticHarnessResult(
        consoleMarker: PhysicalRawImageDiagnosticContract.consoleMarker(
          for: finalCheckpoint,
          checkpointWritten: true
        )
      )
      #endif
    } catch {
      failureStage = Self.failureStage(for: error, after: currentPhase)
      errorClass = PhysicalRawImageDiagnosticContract.sanitizedErrorClass(error)
      outcome = "FAIL"
      totalSeconds = totalStart.duration(to: clock.now).secondsDouble
      if let preparedDraft {
        await runtime.discardRepairContext(descriptor, draftURL: preparedDraft.url)
      }
      await runtime.invalidate(descriptor)
      let finalCheckpoint = try checkpoint(.failed)
      return PhysicalRawImageDiagnosticHarnessResult(
        consoleMarker: PhysicalRawImageDiagnosticContract.consoleMarker(
          for: finalCheckpoint,
          checkpointWritten: true
        )
      )
    }
  }

  private static func failureStage(
    for error: Error,
    after phase: PhysicalRawImageDiagnosticPhase
  ) -> String {
    if let staged = error as? StagedInferenceError { return staged.stage.rawValue }
    if let diagnostic = error as? PhysicalRawImageDiagnosticError {
      switch diagnostic {
      case .wrongPlatform: return "platform"
      case .configurationDrift: return "configuration"
      case .exactBundledReceiptUnavailable: return InferenceErrorStage.hash.rawValue
      case .unexpectedDominantColor,
        .structuredExpectationFailed,
        .structuredResultsNotDistinct:
        return InferenceErrorStage.parsing.rawValue
      }
    }
    if let appError = error as? GITimelineError {
      switch appError {
      case .invalidImage, .syntheticFixtureIntegrity:
        return InferenceErrorStage.imageEncoding.rawValue
      case .invalidDominantColorProbe:
        return InferenceErrorStage.parsing.rawValue
      default:
        break
      }
    }
    switch phase {
    case .started: return InferenceErrorStage.hash.rawValue
    case .receiptVerified: return InferenceErrorStage.imageEncoding.rawValue
    case .fixturePrepared: return InferenceErrorStage.engineInitialization.rawValue
    case .engineReady, .imageRequestStarted: return InferenceErrorStage.imageRequest.rawValue
    case .structuredRequestStarted: return InferenceErrorStage.imageRequest.rawValue
    case .structuredRequestCompleted: return InferenceErrorStage.parsing.rawValue
    case .structuredRepairStarted: return InferenceErrorStage.repair.rawValue
    case .structuredRepairCompleted: return InferenceErrorStage.parsing.rawValue
    case .structuredValidationCompleted: return InferenceErrorStage.persistence.rawValue
    case .completed, .failed: return InferenceErrorStage.persistence.rawValue
    }
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func processResidentPeakBytes() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return UInt64(info.resident_size_peak)
  }
}

struct PhysicalRawImageSuiteHarnessResult: Sendable {
  let consoleMarker: String
}

private struct PhysicalRawImageSuiteEvidenceStore {
  let checkpointURL: URL

  init(runID: UUID) throws {
    let root = try AppFolders.applicationSupport()
      .appendingPathComponent("CompletionEvidence", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try AppFolders.protect(root)
    let directory = root.appendingPathComponent(
      "physical-raw-image-suite-\(runID.uuidString.lowercased())",
      isDirectory: true
    )
    guard !FileManager.default.fileExists(atPath: directory.path) else {
      throw GITimelineError.evidenceAlreadyExists
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    try AppFolders.protect(directory)
    checkpointURL = directory.appendingPathComponent("checkpoint.json")
  }

  func write(_ checkpoint: PhysicalRawImageSuiteCheckpoint) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(checkpoint).write(to: checkpointURL, options: .atomic)
    try AppFolders.protect(checkpointURL)
  }
}

/// Three synthetic fixtures through the exact raw image-message and strict
/// structured parser paths. This launch-only suite owns a separate coordinator
/// and never opens the journal store or app UI. It is narrower than normal-flow
/// review/save/relaunch acceptance even when every fixture passes.
@MainActor
final class PhysicalRawImageSuiteHarness {
  func run() async throws -> PhysicalRawImageSuiteHarnessResult {
    let runID = UUID()
    let startedAt = Date()
    let clock = ContinuousClock()
    let totalStart = clock.now
    let descriptor = PhysicalRawImageSuiteContract.descriptor
    let configuration = PhysicalRawImageSuiteContract.configuration
    let runtime = ModelRuntimeCoordinator(configuration: configuration)
    let imageStore = ImageStore()
    let checkpointStore = try PhysicalRawImageSuiteEvidenceStore(runID: runID)

    var preparedDraft: PreparedDraft?
    var currentPhase = PhysicalRawImageSuitePhase.started
    var activeFixtureID: String?
    var stageHistory: [String] = []
    var receiptVerified = false
    var preparationSeconds: Double?
    var totalSeconds: Double?
    var peakResidentMemoryBytes: UInt64?
    var fixtureResults: [PhysicalRawImageSuiteFixtureResult] = []
    var outcome = "RUNNING"
    var failureStage: String?
    var errorClass: String?

    defer {
      if let preparedDraft { imageStore.deleteBestEffort(preparedDraft.url) }
    }

    func samplePeakMemory() {
      guard let sample = Self.processResidentPeakBytes() else { return }
      peakResidentMemoryBytes = max(peakResidentMemoryBytes ?? 0, sample)
    }

    func checkpoint(_ phase: PhysicalRawImageSuitePhase) throws -> PhysicalRawImageSuiteCheckpoint {
      currentPhase = phase
      let scope = activeFixtureID ?? "suite"
      let stage = "\(scope):\(phase.rawValue)"
      if stageHistory.last != stage { stageHistory.append(stage) }
      samplePeakMemory()
      let colorPassCount = fixtureResults.filter {
        $0.dominantColor == $0.expectedDominantColor
      }.count
      let structuredParseCount = fixtureResults.filter { $0.strictStructuredParsed }.count
      let structuredExpectationPassCount = fixtureResults.filter {
        $0.structuredExpectationPassed
      }.count
      let uniqueCanonicalObservationCount = Set(
        fixtureResults.compactMap(\.canonicalObservationSHA256)
      ).count
      let value = PhysicalRawImageSuiteCheckpoint(
        runID: runID,
        startedAt: startedAt,
        updatedAt: Date(),
        phase: phase,
        activeFixtureID: activeFixtureID,
        stageHistory: stageHistory,
        receiptVerified: receiptVerified,
        preparationSeconds: preparationSeconds,
        totalSeconds: totalSeconds,
        peakResidentMemoryBytes: peakResidentMemoryBytes,
        fixtureResults: fixtureResults,
        colorPassCount: colorPassCount,
        structuredParseCount: structuredParseCount,
        structuredExpectationPassCount: structuredExpectationPassCount,
        uniqueCanonicalObservationCount: uniqueCanonicalObservationCount,
        outcome: outcome,
        failureStage: failureStage,
        errorClass: errorClass
      )
      try checkpointStore.write(value)
      return value
    }

    _ = try checkpoint(.started)

    do {
      #if targetEnvironment(simulator)
      throw PhysicalRawImageDiagnosticError.wrongPlatform
      #else
      guard await runtime.configurationSnapshot() == configuration,
        !configuration.usesLocalPixelBridge
      else { throw PhysicalRawImageDiagnosticError.configurationDrift }

      guard let receipt = try await runtime.receipt(for: descriptor),
        receipt.matches(descriptor),
        receipt.locationKind == .applicationBundle,
        receipt.appBuildIdentity == .current
      else { throw PhysicalRawImageDiagnosticError.exactBundledReceiptUnavailable }
      receiptVerified = true
      _ = try checkpoint(.receiptVerified)

      let preparationStart = clock.now
      do {
        let preparation = try await runtime.prepare(descriptor)
        preparationSeconds = max(
          preparation.seconds,
          preparationStart.duration(to: clock.now).secondsDouble
        )
      } catch {
        preparationSeconds = preparationStart.duration(to: clock.now).secondsDouble
        throw error
      }
      guard await runtime.engineState(descriptor) == .ready else {
        throw StagedInferenceError(
          stage: .engineInitialization,
          underlying: GITimelineError.modelNotVerified
        )
      }
      _ = try checkpoint(.engineReady)

      for fixture in EmbeddedGemmaHarnessFixture.allCases {
        activeFixtureID = fixture.rawValue
        var fixtureResult = PhysicalRawImageSuiteFixtureResult(
          fixtureID: fixture.rawValue,
          bundledFixtureSHA256: fixture.bundledSHA256,
          sanitizedImageSHA256: nil,
          expectedDominantColor: fixture.expectedDominantColor,
          dominantColor: nil,
          dominantColorSeconds: nil,
          structuredInitialSeconds: nil,
          structuredRepairSeconds: nil,
          structuredSeconds: nil,
          repairUsed: false,
          strictStructuredParsed: false,
          structuredExpectationPassed: false,
          structuredObservation: nil,
          canonicalObservationSHA256: nil,
          outcome: "RUNNING",
          failureStage: nil,
          errorClass: nil
        )
        fixtureResults.append(fixtureResult)
        let resultIndex = fixtureResults.index(before: fixtureResults.endIndex)

        do {
          _ = try checkpoint(.fixtureStarted)
          let prepared = try imageStore.prepare(fixture.verifiedBundledData())
          preparedDraft = prepared
          fixtureResult.sanitizedImageSHA256 = prepared.reference.sha256
          fixtureResults[resultIndex] = fixtureResult
          _ = try checkpoint(.fixturePrepared)

          _ = try checkpoint(.colorRequestStarted)
          let colorStart = clock.now
          let colorRaw: String
          do {
            colorRaw = try await runtime.dominantColorProbe(descriptor, draftURL: prepared.url)
            fixtureResult.dominantColorSeconds = colorStart.duration(to: clock.now).secondsDouble
          } catch {
            fixtureResult.dominantColorSeconds = colorStart.duration(to: clock.now).secondsDouble
            throw error
          }
          let color = try DominantColorResult.parse(colorRaw)
          fixtureResult.dominantColor = color
          fixtureResults[resultIndex] = fixtureResult
          guard color == fixture.expectedDominantColor else {
            throw PhysicalRawImageDiagnosticError.unexpectedDominantColor
          }
          _ = try checkpoint(.colorRequestCompleted)

          _ = try checkpoint(.structuredRequestStarted)
          let structuredStart = clock.now
          let observation: VisualObservation
          do {
            let initialStart = clock.now
            let initial: String
            do {
              initial = try await runtime.analyze(descriptor, draftURL: prepared.url)
              fixtureResult.structuredInitialSeconds =
                initialStart.duration(to: clock.now).secondsDouble
            } catch {
              fixtureResult.structuredInitialSeconds =
                initialStart.duration(to: clock.now).secondsDouble
              fixtureResult.structuredSeconds =
                structuredStart.duration(to: clock.now).secondsDouble
              fixtureResults[resultIndex] = fixtureResult
              throw error
            }
            fixtureResult.structuredSeconds = structuredStart.duration(to: clock.now).secondsDouble
            fixtureResults[resultIndex] = fixtureResult
            _ = try checkpoint(.structuredRequestCompleted)
            do {
              observation = try ObservationParser.parse(initial)
              await runtime.discardRepairContext(descriptor, draftURL: prepared.url)
            } catch {
              fixtureResult.repairUsed = true
              fixtureResults[resultIndex] = fixtureResult
              _ = try checkpoint(.structuredRepairStarted)
              let repairStart = clock.now
              let repaired: String
              do {
                repaired = try await runtime.repair(
                  descriptor,
                  draftURL: prepared.url,
                  errors: "Strict schema parse failed."
                )
                fixtureResult.structuredRepairSeconds =
                  repairStart.duration(to: clock.now).secondsDouble
              } catch {
                fixtureResult.structuredRepairSeconds =
                  repairStart.duration(to: clock.now).secondsDouble
                fixtureResult.structuredSeconds =
                  structuredStart.duration(to: clock.now).secondsDouble
                fixtureResults[resultIndex] = fixtureResult
                throw error
              }
              fixtureResult.structuredSeconds =
                structuredStart.duration(to: clock.now).secondsDouble
              fixtureResults[resultIndex] = fixtureResult
              _ = try checkpoint(.structuredRepairCompleted)
              observation = try ObservationParser.parse(repaired)
            }
            fixtureResult.structuredSeconds = structuredStart.duration(to: clock.now).secondsDouble
          } catch {
            fixtureResult.structuredSeconds = structuredStart.duration(to: clock.now).secondsDouble
            throw error
          }
          fixtureResult.strictStructuredParsed = true
          fixtureResult.structuredExpectationPassed =
            PhysicalRawImageSuiteContract.structuredExpectationSatisfied(
              fixtureID: fixture.rawValue,
              observation: observation
            )
          fixtureResult.structuredObservation = observation
          let canonical = try ObservationParser.canonicalJSON(observation)
          fixtureResult.canonicalObservationSHA256 = Self.sha256(Data(canonical.utf8))
          guard fixtureResult.structuredExpectationPassed else {
            throw PhysicalRawImageDiagnosticError.structuredExpectationFailed
          }
          fixtureResult.outcome = "PASS"
          fixtureResults[resultIndex] = fixtureResult
          _ = try checkpoint(.structuredValidationCompleted)
          imageStore.deleteBestEffort(prepared.url)
          preparedDraft = nil
          _ = try checkpoint(.fixtureCompleted)
        } catch {
          if let preparedDraft {
            await runtime.discardRepairContext(descriptor, draftURL: preparedDraft.url)
          }
          fixtureResult.failureStage = Self.failureStage(for: error, after: currentPhase)
          fixtureResult.errorClass = PhysicalRawImageDiagnosticContract.sanitizedErrorClass(error)
          fixtureResult.outcome = "FAIL"
          fixtureResults[resultIndex] = fixtureResult
          throw error
        }
      }

      activeFixtureID = nil
      let uniqueStructured = Set(fixtureResults.compactMap(\.canonicalObservationSHA256)).count
      guard uniqueStructured == EmbeddedGemmaHarnessFixture.allCases.count else {
        throw PhysicalRawImageDiagnosticError.structuredResultsNotDistinct
      }
      outcome = "SUITE_PASS"
      totalSeconds = totalStart.duration(to: clock.now).secondsDouble
      await runtime.invalidate(descriptor)
      let finalCheckpoint = try checkpoint(.completed)
      return PhysicalRawImageSuiteHarnessResult(
        consoleMarker: PhysicalRawImageSuiteContract.consoleMarker(
          for: finalCheckpoint,
          checkpointWritten: true
        )
      )
      #endif
    } catch {
      failureStage = Self.failureStage(for: error, after: currentPhase)
      errorClass = PhysicalRawImageDiagnosticContract.sanitizedErrorClass(error)
      outcome = "FAIL"
      totalSeconds = totalStart.duration(to: clock.now).secondsDouble
      if let preparedDraft {
        await runtime.discardRepairContext(descriptor, draftURL: preparedDraft.url)
      }
      await runtime.invalidate(descriptor)
      let finalCheckpoint = try checkpoint(.failed)
      return PhysicalRawImageSuiteHarnessResult(
        consoleMarker: PhysicalRawImageSuiteContract.consoleMarker(
          for: finalCheckpoint,
          checkpointWritten: true
        )
      )
    }
  }

  private static func failureStage(
    for error: Error,
    after phase: PhysicalRawImageSuitePhase
  ) -> String {
    if let staged = error as? StagedInferenceError { return staged.stage.rawValue }
    if let diagnostic = error as? PhysicalRawImageDiagnosticError {
      switch diagnostic {
      case .wrongPlatform: return "platform"
      case .configurationDrift: return "configuration"
      case .exactBundledReceiptUnavailable: return InferenceErrorStage.hash.rawValue
      case .unexpectedDominantColor,
        .structuredExpectationFailed,
        .structuredResultsNotDistinct:
        return InferenceErrorStage.parsing.rawValue
      }
    }
    if let appError = error as? GITimelineError {
      switch appError {
      case .invalidImage, .syntheticFixtureIntegrity:
        return InferenceErrorStage.imageEncoding.rawValue
      case .invalidDominantColorProbe:
        return InferenceErrorStage.parsing.rawValue
      default:
        break
      }
    }
    switch phase {
    case .started: return InferenceErrorStage.hash.rawValue
    case .receiptVerified: return InferenceErrorStage.engineInitialization.rawValue
    case .engineReady, .fixtureStarted, .fixturePrepared:
      return InferenceErrorStage.imageEncoding.rawValue
    case .colorRequestStarted: return InferenceErrorStage.imageRequest.rawValue
    case .colorRequestCompleted, .structuredRequestStarted:
      return InferenceErrorStage.parsing.rawValue
    case .structuredRepairStarted: return InferenceErrorStage.repair.rawValue
    case .structuredRepairCompleted, .structuredRequestCompleted:
      return InferenceErrorStage.parsing.rawValue
    case .structuredValidationCompleted, .fixtureCompleted:
      return InferenceErrorStage.persistence.rawValue
    case .completed, .failed: return InferenceErrorStage.persistence.rawValue
    }
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func processResidentPeakBytes() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return UInt64(info.resident_size_peak)
  }
}

struct EmbeddedGemmaSmokeRun: Codable, Sendable {
  let fixture: EmbeddedGemmaHarnessFixture
  let sanitizedImageSHA256: String?
  let dominantColorRaw: String?
  let dominantColor: DominantColorResult?
  let dominantColorSeconds: Double?
  let structuredRaw: String?
  let structuredObservation: VisualObservation?
  let structuredSeconds: Double?
  let repairUsed: Bool
  let failureStage: InferenceErrorStage?
  let outcome: String
}

struct EmbeddedGemmaSmokeSummary: Codable, Sendable {
  let startedAt: Date
  let finishedAt: Date
  let descriptor: ModelDescriptor
  let configuration: InferenceConfiguration
  let executionLocation: InferenceExecutionLocation
  let receipt: ModelVerificationReceipt
  let preparationSeconds: Double
  let engineWasReadyBeforeRun: Bool
  let runs: [EmbeddedGemmaSmokeRun]
  let brownGreenControlPassed: Bool
  let structuredPassCount: Int
  let outcome: String
}

struct EmbeddedGemmaNormalFlowSummary: Codable, Sendable {
  let runID: UUID
  let startedAt: Date
  let finishedAt: Date
  let descriptor: ModelDescriptor
  let configuration: InferenceConfiguration
  let executionLocation: InferenceExecutionLocation
  let fixture: EmbeddedGemmaHarnessFixture
  let automaticAnalysisReachedReview: Bool
  let originalObservation: VisualObservation
  let reviewedObservation: VisualObservation
  let editedField: String
  let outstandingSuggestionsAtSave: Int
  let savePassed: Bool
  let historyEntryFound: Bool
  let imageExists: Bool
  let provenance: String
  let savedModelID: String?
  let savedConfiguration: InferenceConfiguration?
  let savedExecutionLocation: InferenceExecutionLocation?
  let outcome: String
}

struct EmbeddedGemmaNormalFlowRelaunchSummary: Codable, Sendable {
  let verifiedAt: Date
  let runID: UUID
  let entryFoundAfterRelaunch: Bool
  let reviewedObservationReopened: Bool
  let humanEditPersisted: Bool
  let modelProvenancePersisted: Bool
  let imageReopened: Bool
  let outcome: String
}

enum EmbeddedGemmaHarnessError: LocalizedError {
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .failed(let message): return message
    }
  }
}

/// Launch-argument-only acceptance surface for the signed embedded-model app.
/// It shares the exact app-scoped coordinator, image sanitizer, parser,
/// NewEntryViewModel, EntryStore, and SwiftData container used by normal UI.
/// No view or navigation route exposes this type.
@MainActor
final class EmbeddedGemmaCompletionHarness {
  static let smokeLaunchArgument = "--run-embedded-gemma-smoke"
  static let normalFlowLaunchArgument = "--run-embedded-gemma-normal-flow"
  static let relaunchVerifyArgument = "--verify-embedded-gemma-normal-flow"
  static let defaultsRunIDKey = "EmbeddedGemmaNormalFlowRunID"

  private let runtime: ModelRuntimeCoordinator
  private let context: ModelContext
  private let imageStore: ImageStore
  private let userDefaults: UserDefaults

  init(
    runtime: ModelRuntimeCoordinator,
    context: ModelContext,
    imageStore: ImageStore? = nil,
    userDefaults: UserDefaults = .standard
  ) {
    self.runtime = runtime
    self.context = context
    self.imageStore = imageStore ?? ImageStore()
    self.userDefaults = userDefaults
  }

  func runSmoke() async throws -> EmbeddedGemmaHarnessResult {
    let startedAt = Date()
    let descriptor = try exactDescriptor()
    let configuration = await runtime.configurationSnapshot()
    try requireExpectedBackends(configuration)
    let engineWasReady = await runtime.engineState(descriptor) == .ready
    let clock = ContinuousClock()
    let preparationStart = clock.now
    let readiness = await runtime.prepareLocalAnalysis()
    let preparationSeconds = preparationStart.duration(to: clock.now).secondsDouble
    guard readiness == .ready else {
      throw EmbeddedGemmaHarnessError.failed("Embedded model verification or engine preparation did not reach ready.")
    }
    guard let receipt = try await runtime.receipt(for: descriptor),
      receipt.matches(descriptor),
      receipt.locationKind == .applicationBundle
    else {
      throw EmbeddedGemmaHarnessError.failed("The exact bundled-model receipt was not available.")
    }

    var runs: [EmbeddedGemmaSmokeRun] = []
    for fixture in EmbeddedGemmaHarnessFixture.allCases {
      runs.append(await runSmokeFixture(fixture, descriptor: descriptor))
    }

    let colors = Dictionary(uniqueKeysWithValues: runs.compactMap { run in
      run.dominantColor.map { (run.fixture, $0) }
    })
    let colorPassed = colors[.brown] == .brown
      && colors[.green] == .green
      && colors[.control] == .other
    let structuredPassCount = runs.filter { $0.structuredObservation != nil }.count
    let allPassed = colorPassed
      && structuredPassCount == EmbeddedGemmaHarnessFixture.allCases.count
      && runs.allSatisfy { $0.outcome == "PASS" }
    let summary = EmbeddedGemmaSmokeSummary(
      startedAt: startedAt,
      finishedAt: Date(),
      descriptor: descriptor,
      configuration: configuration,
      executionLocation: .currentAppLocal,
      receipt: receipt,
      preparationSeconds: preparationSeconds,
      engineWasReadyBeforeRun: engineWasReady,
      runs: runs,
      brownGreenControlPassed: colorPassed,
      structuredPassCount: structuredPassCount,
      outcome: allPassed ? "PASS" : "FAIL"
    )
    let evidenceURL = try save(summary, stem: "embedded-gemma-smoke")
    guard allPassed else {
      throw EmbeddedGemmaHarnessError.failed("One or more real image-plus-text smoke checks failed; local evidence was saved.")
    }
    return EmbeddedGemmaHarnessResult(
      evidenceURL: evidenceURL,
      consoleSummary: "brown=BROWN green=GREEN control=OTHER structured=\(structuredPassCount)/3 backend=\(configuration.engineBackend)/vision-\(configuration.visionBackend)"
    )
  }

  func runNormalFlow() async throws -> EmbeddedGemmaHarnessResult {
    let startedAt = Date()
    let runID = UUID()
    let priorRunID = userDefaults.string(forKey: Self.defaultsRunIDKey)
      .flatMap(UUID.init(uuidString:))
    let descriptor = try exactDescriptor()
    let configuration = await runtime.configurationSnapshot()
    try requireExpectedBackends(configuration)
    guard await runtime.prepareLocalAnalysis() == .ready else {
      throw EmbeddedGemmaHarnessError.failed("The embedded runtime was not ready for normal-flow acceptance.")
    }
    let viewModel = NewEntryViewModel(
      imageStore: imageStore,
      store: EntryStore(context: context),
      inference: CoordinatedInferenceService(runtime: runtime, descriptor: descriptor),
      descriptor: descriptor,
      modelVerified: true,
      engineReady: true,
      configuration: configuration,
      executionLocation: .currentAppLocal,
      analysisTimeout: .seconds(120),
      autoAnalysisEnabled: true
    )
    let fixture = EmbeddedGemmaHarnessFixture.brown
    try viewModel.prepareImageData(fixture.verifiedBundledData())

    for _ in 0..<1_800 {
      switch viewModel.flowState {
      case .reviewing, .failed:
        break
      default:
        try await Task.sleep(for: .milliseconds(100))
        continue
      }
      break
    }
    guard case .reviewing = viewModel.flowState,
      let original = viewModel.reviewedObservation
    else {
      throw EmbeddedGemmaHarnessError.failed("Automatic photo attachment did not reach editable review.")
    }

    let editedField: ReviewField
    if original.imageUsable {
      editedField = .bristolType
      let replacementType = original.apparentBristolType == 4 ? 6 : 4
      let replacementForm = BristolFormContract.expectedForm(for: replacementType)!
      viewModel.updateReview(field: .bristolType) {
        VisualObservation(
          imageUsable: $0.imageUsable,
          qualityIssue: $0.qualityIssue,
          apparentBristolType: replacementType,
          apparentColor: $0.apparentColor,
          form: replacementForm,
          redAppearingMaterial: $0.redAppearingMaterial,
          blackTarryAppearance: $0.blackTarryAppearance
        )
      }
      for field in ReviewField.allCases where field != editedField {
        viewModel.confirmReviewField(field)
      }
    } else {
      editedField = .photoUsable
      viewModel.updateReview { _ in
        VisualObservation(
          imageUsable: true,
          qualityIssue: "none",
          apparentBristolType: 4,
          apparentColor: "brown",
          form: "smooth_formed",
          redAppearingMaterial: "unable_to_assess",
          blackTarryAppearance: "unable_to_assess"
        )
      }
    }
    let reviewed = try requireReviewedObservation(viewModel)
    // These fields are deliberately human-only in the public UI. Supply
    // deterministic non-clinical answers in this synthetic harness so the
    // acceptance path exercises the complete current save contract without
    // implying that Gemma inferred symptoms or urgency from the fixture.
    viewModel.painScore = 0
    viewModel.urgency = UrgencyLevel.none
    viewModel.redBlood = .no
    viewModel.blackTarry = .no
    switch ClinicalValidation.conditionalQuestion(for: reviewed.apparentBristolType) {
    case .strainingOrIncomplete:
      viewModel.strainingOrIncomplete = .no
      viewModel.leakageOrAccident = nil
    case .leakageOrAccident:
      viewModel.strainingOrIncomplete = nil
      viewModel.leakageOrAccident = .no
    case nil:
      viewModel.strainingOrIncomplete = nil
      viewModel.leakageOrAccident = nil
    }
    let outstandingAtSave = viewModel.outstandingReviewCount
    guard outstandingAtSave == 0, viewModel.canSave else {
      throw EmbeddedGemmaHarnessError.failed("Review suggestions were not fully resolved before save.")
    }
    let note = "\(DemoDataPolicy.notePrefix) · embedded acceptance · \(runID.uuidString)"
    viewModel.note = note
    viewModel.save()

    guard let entryID = viewModel.savedEntryID else {
      throw EmbeddedGemmaHarnessError.failed("The reviewed entry did not complete its transaction.")
    }
    let entries = try context.fetch(FetchDescriptor<EntryRecord>())
    guard let entry = entries.first(where: { $0.id == entryID && $0.note == note }) else {
      throw EmbeddedGemmaHarnessError.failed("The saved entry did not appear in the History data source.")
    }
    let provenance = try decodeProvenance(entry.modelProvenanceJSON)
    let imageExists = entry.imageFilename
      .flatMap { imageStore.imageURL(filename: $0) }
      .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    let allPassed = entry.observation == reviewed
      && entry.provenance == EntryProvenance.ai_edited.rawValue
      && entry.modelID == descriptor.modelID
      && provenance?.configuration == configuration
      && provenance?.executionLocation == .currentAppLocal
      && imageExists
    let summary = EmbeddedGemmaNormalFlowSummary(
      runID: runID,
      startedAt: startedAt,
      finishedAt: Date(),
      descriptor: descriptor,
      configuration: configuration,
      executionLocation: .currentAppLocal,
      fixture: fixture,
      automaticAnalysisReachedReview: true,
      originalObservation: original,
      reviewedObservation: reviewed,
      editedField: editedField.rawValue,
      outstandingSuggestionsAtSave: outstandingAtSave,
      savePassed: viewModel.savedEntryID == entryID,
      historyEntryFound: true,
      imageExists: imageExists,
      provenance: entry.provenance,
      savedModelID: entry.modelID,
      savedConfiguration: provenance?.configuration,
      savedExecutionLocation: provenance?.executionLocation,
      outcome: allPassed ? "PASS" : "FAIL"
    )
    let evidenceURL = try save(summary, stem: "embedded-gemma-normal-flow")
    guard allPassed else {
      throw EmbeddedGemmaHarnessError.failed("One or more automatic review/save/history checks failed; local evidence was saved.")
    }
    if let priorRunID, priorRunID != runID {
      let priorNote = "\(DemoDataPolicy.notePrefix) · embedded acceptance · \(priorRunID.uuidString)"
      if let priorEntry = entries.first(where: { $0.note == priorNote }) {
        _ = try? EntryStore(context: context).delete(priorEntry, imageStore: imageStore)
      }
    }
    userDefaults.set(runID.uuidString, forKey: Self.defaultsRunIDKey)
    return EmbeddedGemmaHarnessResult(
      evidenceURL: evidenceURL,
      consoleSummary: "auto_analysis=PASS review=PASS edit=\(editedField.rawValue) save=PASS history=PASS"
    )
  }

  func verifyNormalFlowAfterRelaunch() throws -> EmbeddedGemmaHarnessResult {
    let descriptor = try exactDescriptor()
    guard let stored = userDefaults.string(forKey: Self.defaultsRunIDKey),
      let runID = UUID(uuidString: stored)
    else {
      throw EmbeddedGemmaHarnessError.failed("No prior embedded normal-flow marker was found.")
    }
    let note = "\(DemoDataPolicy.notePrefix) · embedded acceptance · \(runID.uuidString)"
    let entries = try context.fetch(FetchDescriptor<EntryRecord>())
    guard let entry = entries.first(where: { $0.note == note }) else {
      throw EmbeddedGemmaHarnessError.failed("The embedded acceptance entry was not found after relaunch.")
    }
    let provenance = try decodeProvenance(entry.modelProvenanceJSON)
    let reviewedReopened = entry.observation != nil
    let editPersisted = entry.originalAIJSON != nil
      && entry.reviewedJSON != nil
      && entry.originalAIJSON != entry.reviewedJSON
      && entry.provenance == EntryProvenance.ai_edited.rawValue
    let provenancePersisted = entry.modelID == descriptor.modelID
      && provenance?.configuration == .runtimeDefault
      && provenance?.executionLocation == .currentAppLocal
    let imageReopened = entry.imageFilename
      .flatMap { imageStore.imageURL(filename: $0) }
      .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    let allPassed = reviewedReopened && editPersisted && provenancePersisted && imageReopened
    let summary = EmbeddedGemmaNormalFlowRelaunchSummary(
      verifiedAt: Date(),
      runID: runID,
      entryFoundAfterRelaunch: true,
      reviewedObservationReopened: reviewedReopened,
      humanEditPersisted: editPersisted,
      modelProvenancePersisted: provenancePersisted,
      imageReopened: imageReopened,
      outcome: allPassed ? "PASS" : "FAIL"
    )
    let evidenceURL = try save(summary, stem: "embedded-gemma-normal-flow-relaunch")
    guard allPassed else {
      throw EmbeddedGemmaHarnessError.failed("One or more relaunch persistence checks failed; local evidence was saved.")
    }
    return EmbeddedGemmaHarnessResult(
      evidenceURL: evidenceURL,
      consoleSummary: "relaunch=PASS reviewed=PASS edit=PASS provenance=PASS image=PASS"
    )
  }

  private func runSmokeFixture(
    _ fixture: EmbeddedGemmaHarnessFixture,
    descriptor: ModelDescriptor
  ) async -> EmbeddedGemmaSmokeRun {
    var prepared: PreparedDraft?
    var colorRaw: String?
    var color: DominantColorResult?
    var colorSeconds: Double?
    var structuredRaw: String?
    var observation: VisualObservation?
    var structuredSeconds: Double?
    var repairUsed = false
    var failureStage: InferenceErrorStage?

    do {
      prepared = try imageStore.prepare(fixture.verifiedBundledData())
    } catch {
      failureStage = .imageEncoding
    }

    if let prepared {
      do {
        let clock = ContinuousClock()
        let colorStart = clock.now
        let raw = try await runtime.dominantColorProbe(descriptor, draftURL: prepared.url)
        colorSeconds = colorStart.duration(to: clock.now).secondsDouble
        colorRaw = raw
        color = try DominantColorResult.parse(raw)
      } catch {
        failureStage = (error as? StagedInferenceError)?.stage ?? .parsing
      }
    }

    if let prepared {
      let clock = ContinuousClock()
      let structuredStart = clock.now
      do {
        let initial = try await runtime.analyze(descriptor, draftURL: prepared.url)
        structuredRaw = initial
        do {
          observation = try ObservationParser.parse(initial)
          await runtime.discardRepairContext(descriptor, draftURL: prepared.url)
        } catch {
          repairUsed = true
          let repaired = try await runtime.repair(
            descriptor,
            draftURL: prepared.url,
            errors: error.localizedDescription
          )
          structuredRaw = "INITIAL\n\(initial)\n\nREPAIR\n\(repaired)"
          observation = try ObservationParser.parse(repaired)
        }
      } catch {
        await runtime.discardRepairContext(descriptor, draftURL: prepared.url)
        failureStage = failureStage ?? (error as? StagedInferenceError)?.stage ?? .parsing
      }
      structuredSeconds = structuredStart.duration(to: clock.now).secondsDouble
    }

    if let prepared { imageStore.deleteBestEffort(prepared.url) }
    let passed = color == fixture.expectedDominantColor && observation != nil && failureStage == nil
    return EmbeddedGemmaSmokeRun(
      fixture: fixture,
      sanitizedImageSHA256: prepared?.reference.sha256,
      dominantColorRaw: colorRaw,
      dominantColor: color,
      dominantColorSeconds: colorSeconds,
      structuredRaw: structuredRaw,
      structuredObservation: observation,
      structuredSeconds: structuredSeconds,
      repairUsed: repairUsed,
      failureStage: failureStage,
      outcome: passed ? "PASS" : "FAIL"
    )
  }

  private func exactDescriptor() throws -> ModelDescriptor {
    guard let descriptor = ModelCatalog.normalFlowSelection,
      descriptor == .liteRTGemma4E4B
    else {
      throw EmbeddedGemmaHarnessError.failed("The Hackathon build did not select the exact embedded E4B descriptor.")
    }
    return descriptor
  }

  private func requireExpectedBackends(_ configuration: InferenceConfiguration) throws {
    let expected = InferenceConfiguration.embeddedHarnessExpectedConfiguration(
      arguments: ProcessInfo.processInfo.arguments
    )
    guard configuration == expected else {
      throw EmbeddedGemmaHarnessError.failed("The configured main/vision backends did not match this platform's pinned acceptance configuration.")
    }
  }

  private func requireReviewedObservation(_ viewModel: NewEntryViewModel) throws -> VisualObservation {
    guard let reviewed = viewModel.reviewedObservation else {
      throw EmbeddedGemmaHarnessError.failed("The reviewed observation disappeared before save.")
    }
    return reviewed
  }

  private func decodeProvenance(_ json: String?) throws -> InferenceProvenanceSnapshot? {
    guard let data = json?.data(using: .utf8) else { return nil }
    return try JSONDecoder().decode(InferenceProvenanceSnapshot.self, from: data)
  }

  private func save<T: Encodable>(_ value: T, stem: String) throws -> URL {
    let directory = try AppFolders.applicationSupport()
      .appendingPathComponent("CompletionEvidence", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try AppFolders.protect(directory)
    let url = directory.appendingPathComponent("\(stem)-\(UUID().uuidString.lowercased()).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(value).write(to: url, options: .atomic)
    try AppFolders.protect(url)
    return url
  }
}
#endif
