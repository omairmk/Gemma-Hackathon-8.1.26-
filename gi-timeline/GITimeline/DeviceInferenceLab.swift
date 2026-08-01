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
      liteRTLMRevision: "f73637c57f0940b53da184e0d5adfc52a4e55eef",
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

#if HACKATHON_EMBEDDED_GEMMA
import CryptoKit
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

  init(runtime: ModelRuntimeCoordinator, context: ModelContext) {
    self.runtime = runtime
    self.context = context
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
    let priorRunID = UserDefaults.standard.string(forKey: Self.defaultsRunIDKey)
      .flatMap(UUID.init(uuidString:))
    let descriptor = try exactDescriptor()
    let configuration = await runtime.configurationSnapshot()
    try requireExpectedBackends(configuration)
    guard await runtime.prepareLocalAnalysis() == .ready else {
      throw EmbeddedGemmaHarnessError.failed("The embedded runtime was not ready for normal-flow acceptance.")
    }
    let viewModel = NewEntryViewModel(
      imageStore: ImageStore(),
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
      editedField = .form
      let replacement = original.form == "mushy" ? "smooth_formed" : "mushy"
      viewModel.updateReview(field: .form) {
        VisualObservation(
          imageUsable: $0.imageUsable,
          qualityIssue: $0.qualityIssue,
          apparentBristolType: $0.apparentBristolType,
          apparentColor: $0.apparentColor,
          form: replacement,
          redAppearingMaterial: $0.redAppearingMaterial,
          blackTarryAppearance: $0.blackTarryAppearance
        )
      }
    } else {
      editedField = .imageQuality
      let replacement = original.qualityIssue == "too_dark" ? "blurred" : "too_dark"
      viewModel.updateReview(field: .imageQuality) { _ in
        VisualObservation(
          imageUsable: false,
          qualityIssue: replacement,
          apparentBristolType: nil,
          apparentColor: "unable_to_assess",
          form: "unable_to_assess",
          redAppearingMaterial: "unable_to_assess",
          blackTarryAppearance: "unable_to_assess"
        )
      }
    }
    for field in ReviewField.allCases where field != editedField {
      viewModel.confirmReviewField(field)
    }
    let reviewed = try requireReviewedObservation(viewModel)
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
      .flatMap { ImageStore().imageURL(filename: $0) }
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
        try? EntryStore(context: context).delete(priorEntry, imageStore: ImageStore())
      }
    }
    UserDefaults.standard.set(runID.uuidString, forKey: Self.defaultsRunIDKey)
    return EmbeddedGemmaHarnessResult(
      evidenceURL: evidenceURL,
      consoleSummary: "auto_analysis=PASS review=PASS edit=\(editedField.rawValue) save=PASS history=PASS"
    )
  }

  func verifyNormalFlowAfterRelaunch() throws -> EmbeddedGemmaHarnessResult {
    let descriptor = try exactDescriptor()
    guard let stored = UserDefaults.standard.string(forKey: Self.defaultsRunIDKey),
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
      .flatMap { ImageStore().imageURL(filename: $0) }
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
    let imageStore = ImageStore()
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
    #if targetEnvironment(simulator)
    let expectedMain = "cpu"
    #else
    let expectedMain = "gpu"
    #endif
    guard configuration.engineBackend == expectedMain,
      configuration.visionBackend == "cpu"
    else {
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
