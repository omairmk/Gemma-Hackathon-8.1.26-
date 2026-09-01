import SwiftUI
import SwiftData
import UIKit
import GITimelineCore
#if HACKATHON_EMBEDDED_GEMMA
import Darwin
#endif

enum AppRuntime {
  static var isUnitTesting: Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCTestConfigurationFilePath"] != nil
      || environment["XCTestBundlePath"] != nil
      || environment["XCInjectBundleInto"] != nil
      || environment["XCInjectBundle"] != nil
      || NSClassFromString("XCTest.XCTestCase") != nil
      || NSClassFromString("XCTestCase") != nil
  }
}

#if DEBUG || HACKATHON_EMBEDDED_GEMMA
enum AppEvaluationLaunchPolicy {
  static func isTuning(_ arguments: [String]) -> Bool {
    DerivedMapTuningV3Contract.hasAnyTuningLaunchArgument(in: arguments)
  }

  static func isBlindValidation(_ arguments: [String]) -> Bool {
    DerivedMapBlindValidationV1Contract.hasAnyLaunchArgument(in: arguments)
  }

  static func isRawPhotoV12Tuning(_ arguments: [String]) -> Bool {
    RawPhotoV12TuningContract.isRequested(in: arguments)
  }

  static func isSyntheticVisionV1(_ arguments: [String]) -> Bool {
    SyntheticVisionV1Contract.isRequested(in: arguments)
  }

  static func isolatesJournal(_ arguments: [String]) -> Bool {
    isTuning(arguments) || isBlindValidation(arguments)
      || isRawPhotoV12Tuning(arguments)
      || isSyntheticVisionV1(arguments)
      || AppStoreRawImageV1PreparationDiagnosticContract
        .hasDiagnosticLaunchArgument(in: arguments)
  }
}

/// A plain, single candidate selector is the product-UI physical
/// qualification route. Fixture/diagnostic arguments stay isolated and never
/// open the journal UI. The shipping default remains unchanged.
enum V1CandidateProductQualificationLaunchPolicy {
  static func presentsProductUI(_ arguments: [String]) -> Bool {
    arguments.filter {
      $0 == InferenceConfiguration.internalAppStoreRawImageV1CandidateLaunchArgument
    }.count == 1
      && InferenceConfiguration.internalDiagnosticConfiguration(
        arguments: arguments
      ) == .appStoreRawImageV12SubjectGateTuning
      && !AppEvaluationLaunchPolicy.isolatesJournal(arguments)
      && !PhysicalRawImageDiagnosticContract.hasAnyPhysicalRawLaunchArgument(
        in: arguments
      )
  }
}
#endif

#if HACKATHON_EMBEDDED_GEMMA
/// Explicit internal selector used to exercise the same configuration as the
/// public App Store raw-photo route from a diagnostic-capable Hackathon build.
enum AppStoreRawImageV1InternalContract {
  static let launchArgument =
    InferenceConfiguration.internalAppStoreRawImageV1LaunchArgument

  static func isEnabled(_ arguments: [String]) -> Bool {
    InferenceConfiguration.internalDiagnosticConfiguration(arguments: arguments) != nil
  }

  /// A malformed preparation-diagnostic launch must still stay on the isolated
  /// blank store while it emits a selector-contract failure marker.
  static func shouldIsolate(_ arguments: [String]) -> Bool {
    (isEnabled(arguments)
      && !V1CandidateProductQualificationLaunchPolicy.presentsProductUI(arguments))
      || AppStoreRawImageV1PreparationDiagnosticContract.hasDiagnosticLaunchArgument(
        in: arguments
      )
  }
}

@MainActor
private struct AppStoreRawImageV1HarnessStorage {
  let imageStore: ImageStore
  let userDefaults: UserDefaults

  static func makeImageStore() throws -> ImageStore {
    let root = try AppFolders.applicationSupport()
      .appendingPathComponent("CompletionEvidence", isDirectory: true)
      .appendingPathComponent("InternalRawImageV1Working", isDirectory: true)
      .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
    let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    return ImageStore(draftsDirectory: drafts, imagesDirectory: images)
  }

  static func make() throws -> Self {
    guard let defaults = UserDefaults(
      suiteName: "com.omairmkhan.GITimeline.InternalRawImageV1Harness"
    ) else {
      throw CocoaError(.fileWriteUnknown)
    }
    return Self(
      imageStore: try makeImageStore(),
      userDefaults: defaults
    )
  }
}
#endif

@main struct GITimelineApp: App {
  @State private var persistence: PersistenceBootstrap.Result
  @State private var didPerformProtectedDataCatchUpRetry = false
  let inferenceRuntime: ModelRuntimeCoordinator

  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  private var isIsolatedEvaluationLaunch: Bool {
    AppEvaluationLaunchPolicy.isolatesJournal(ProcessInfo.processInfo.arguments)
  }
  #endif

  #if HACKATHON_EMBEDDED_GEMMA
  private var isIsolatedPhysicalRawLaunch: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    return PhysicalRawImageDiagnosticContract.hasAnyPhysicalRawLaunchArgument(in: arguments)
  }

  private var isInternalRawImageCandidateLaunch: Bool {
    AppStoreRawImageV1InternalContract.shouldIsolate(ProcessInfo.processInfo.arguments)
  }
  #endif

  /// Deterministic appearance for screenshot/UI-test launches. An ordinary
  /// launch leaves this nil so the app continues to follow the system setting.
  private var uiPreviewColorScheme: ColorScheme? {
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--ui-preview-dark") { return .dark }
    if arguments.contains("--ui-preview-light") { return .light }
    #endif
    return nil
  }

  init() {
      #if DEBUG || HACKATHON_EMBEDDED_GEMMA
      let launchArguments = ProcessInfo.processInfo.arguments
      #if HACKATHON_EMBEDDED_GEMMA
      if let diagnosticConfiguration =
        InferenceConfiguration.internalDiagnosticConfiguration(arguments: launchArguments)
      {
        let cachePolicy: ModelRuntimeEngineCachePolicy
        if SyntheticVisionV1Contract.isRequested(in: launchArguments) {
          cachePolicy = .freshIsolatedDiagnosticCache(runID: UUID())
        } else if AppStoreRawImageV1PreparationDiagnosticContract.isValidRequest(
          in: launchArguments
        ) {
          switch AppStoreRawImageV1PreparationDiagnosticContract.cacheMode(
            in: launchArguments
          ) {
          case .freshIsolatedDiagnosticCache:
            cachePolicy = .freshIsolatedDiagnosticCache(runID: UUID())
          case .freshCachesRootDiagnosticCache:
            cachePolicy = .freshCachesRootDiagnosticCache(
              runID: UUID(),
              replaceExistingDiagnosticRoot: true
            )
          default:
            cachePolicy = .sharedModelCache
          }
        } else {
          cachePolicy = .sharedModelCache
        }
        inferenceRuntime = ModelRuntimeCoordinator(
          configuration: diagnosticConfiguration,
          engineCachePolicy: cachePolicy
        )
      } else if AppEvaluationLaunchPolicy.isolatesJournal(launchArguments) {
        // A dedicated exact configuration on the app-scoped coordinator keeps
        // the static production default immutable while allowing one shared
        // baseline/v3 tuning session for this isolated launch.
        inferenceRuntime = ModelRuntimeCoordinator(
          configuration: DerivedMapTuningV3Contract.baselineConfiguration
        )
      } else {
        inferenceRuntime = ModelRuntimeCoordinator()
      }
      #else
      if AppEvaluationLaunchPolicy.isolatesJournal(launchArguments) {
        // A dedicated exact configuration on the app-scoped coordinator keeps
        // the static production default immutable while allowing one shared
        // baseline/v3 tuning session for this isolated launch.
        inferenceRuntime = ModelRuntimeCoordinator(
          configuration: DerivedMapTuningV3Contract.baselineConfiguration
        )
      } else {
        inferenceRuntime = ModelRuntimeCoordinator()
      }
      #endif
      #else
      inferenceRuntime = ModelRuntimeCoordinator()
      #endif
      #if DEBUG
      let usesEphemeralUITestStore = ProcessInfo.processInfo.arguments.contains("--ui-test-ephemeral-store")
      #else
      let usesEphemeralUITestStore = false
      #endif
      #if HACKATHON_EMBEDDED_GEMMA
      let arguments = ProcessInfo.processInfo.arguments
      let usesPhysicalRawImageDiagnosticStore =
        PhysicalRawImageDiagnosticContract.hasAnyPhysicalRawLaunchArgument(in: arguments)
      let usesInternalRawImageCandidateStore =
        AppStoreRawImageV1InternalContract.shouldIsolate(arguments)
      #else
      let usesPhysicalRawImageDiagnosticStore = false
      let usesInternalRawImageCandidateStore = false
      #endif
      #if DEBUG || HACKATHON_EMBEDDED_GEMMA
      let usesIsolatedEvaluationStore = AppEvaluationLaunchPolicy.isolatesJournal(
        ProcessInfo.processInfo.arguments
      )
      #else
      let usesIsolatedEvaluationStore = false
      #endif
      let initialPersistence: PersistenceBootstrap.Result
      if AppRuntime.isUnitTesting || usesEphemeralUITestStore
        || usesPhysicalRawImageDiagnosticStore || usesIsolatedEvaluationStore
        || usesInternalRawImageCandidateStore
      {
        initialPersistence = PersistenceBootstrap.makeEphemeral()
      } else {
        // Render a non-writable launch state before opening or reconciling a
        // potentially large protected journal. The cooperative reconciliation
        // task yields between retained photos so launch remains responsive.
        initialPersistence = .checking
      }
      _persistence = State(initialValue: initialPersistence)
      #if DEBUG || HACKATHON_EMBEDDED_GEMMA
      // The Documents/Import drop path is a development and hackathon model-
      // import surface. The public manual-first build contains no model; an
      // internal embedded-model build uses only its verified payload.
      if initialPersistence.permitsJournalPresentation,
        !usesPhysicalRawImageDiagnosticStore, !usesIsolatedEvaluationStore,
        !usesInternalRawImageCandidateStore
      { _ = try? AppFolders.importFolder() }
      #endif
      if initialPersistence.permitsJournalPresentation, !AppRuntime.isUnitTesting,
        !usesPhysicalRawImageDiagnosticStore, !usesIsolatedEvaluationStore,
        !usesInternalRawImageCandidateStore
      {
        AppFolders.enforceStoreProtection()
      }
  }
  var body: some Scene {
    WindowGroup {
      launchRoot
    }
  }

  @ViewBuilder private var launchRoot: some View {
    if persistence.state == .checking {
      PersistenceCheckingView()
        .task { await openJournalAfterCheckingFrame() }
    } else if persistence.permitsJournalPresentation, let modelContainer = persistence.modelContainer {
      Group {
        #if DEBUG || HACKATHON_EMBEDDED_GEMMA
        if isIsolatedEvaluationLaunch {
          Color.clear.accessibilityHidden(true)
        } else {
          #if HACKATHON_EMBEDDED_GEMMA
          if isIsolatedPhysicalRawLaunch || isInternalRawImageCandidateLaunch {
            Color.clear.accessibilityHidden(true)
          } else {
            AppRootView(inferenceRuntime: inferenceRuntime)
          }
          #else
          AppRootView(inferenceRuntime: inferenceRuntime)
          #endif
        }
        #else
        #if HACKATHON_EMBEDDED_GEMMA
        if isIsolatedPhysicalRawLaunch || isInternalRawImageCandidateLaunch {
          Color.clear.accessibilityHidden(true)
        } else {
          AppRootView(inferenceRuntime: inferenceRuntime)
        }
        #else
        AppRootView(inferenceRuntime: inferenceRuntime)
        #endif
        #endif
      }
      .preferredColorScheme(uiPreviewColorScheme)
        #if DEBUG
        .task {
          let arguments = ProcessInfo.processInfo.arguments
          if DerivedMapTuningV3Contract.hasAnyTuningLaunchArgument(in: arguments) {
            do {
              try DerivedMapTuningV3Contract.validateLaunch(arguments: arguments)
              let result = try await PhotoSuggestionEvaluationHarness(
                baselineRuntime: inferenceRuntime
              ).runDerivedMapV3TuningIPhone()
              print("\(DerivedMapTuningV3Contract.runCompleteConsoleMarker) \(result.consoleSummary) \(result.evidenceURL.lastPathComponent)")
            } catch {
              print("PHOTO_TUNING_V3_FAIL \(error.localizedDescription)")
            }
          } else if arguments.contains(PhotoSuggestionEvaluationHarness.rawImageSimulatorLaunchArgument) {
            do {
              let result = try await PhotoSuggestionEvaluationHarness(baselineRuntime: inferenceRuntime).runRawImageSimulator()
              print("PHOTO_SUGGESTION_EVALUATION_PASS \(result.consoleSummary) \(result.evidenceURL.lastPathComponent)")
            } catch {
              print("PHOTO_SUGGESTION_EVALUATION_FAIL \(error.localizedDescription)")
            }
          } else if arguments.contains("--run-overnight-gemma-smoke") {
            do {
              let lab = DeviceInferenceLabViewModel(runtime: inferenceRuntime)
              let evidenceURL = try await lab.runOvernightSmoke()
              print("OVERNIGHT_GEMMA_SMOKE_PASS \(evidenceURL.lastPathComponent)")
            } catch {
              print("OVERNIGHT_GEMMA_SMOKE_FAIL \(error.localizedDescription)")
            }
          } else if arguments.contains(OvernightNormalFlowRunner.launchRunArgument) {
            do {
              let runner = OvernightNormalFlowRunner(
                runtime: inferenceRuntime,
                context: ModelContext(modelContainer)
              )
              let evidenceURL = try await runner.run()
              print("OVERNIGHT_NORMAL_FLOW_PASS \(evidenceURL.lastPathComponent)")
            } catch {
              print("OVERNIGHT_NORMAL_FLOW_FAIL \(error.localizedDescription)")
            }
          } else if arguments.contains(OvernightNormalFlowRunner.launchVerifyArgument) {
            do {
              let runner = OvernightNormalFlowRunner(
                runtime: inferenceRuntime,
                context: ModelContext(modelContainer)
              )
              let evidenceURL = try runner.verifyAfterRelaunch()
              print("OVERNIGHT_NORMAL_FLOW_RELAUNCH_PASS \(evidenceURL.lastPathComponent)")
            } catch {
              print("OVERNIGHT_NORMAL_FLOW_RELAUNCH_FAIL \(error.localizedDescription)")
            }
          }
        }
        #endif
        #if HACKATHON_EMBEDDED_GEMMA
        .task {
          let arguments = ProcessInfo.processInfo.arguments
          let physicalRawImageDiagnosticRequest =
            PhysicalRawImageDiagnosticContract.requestedRequest(in: arguments)
          let runsPhysicalRawImageDiagnostic = physicalRawImageDiagnosticRequest != nil
          let runsPhysicalRawImageSuite = PhysicalRawImageSuiteContract.isRequested(in: arguments)
          let hasPhysicalRawImageLaunchArgument =
            PhysicalRawImageDiagnosticContract.hasAnyPhysicalRawLaunchArgument(in: arguments)
          let hasTuningLaunchArgument =
            DerivedMapTuningV3Contract.hasAnyTuningLaunchArgument(in: arguments)
          let hasBlindValidationLaunchArgument =
            DerivedMapBlindValidationV1Contract.hasAnyLaunchArgument(in: arguments)
          let runsRawPhotoV12Tuning =
            RawPhotoV12TuningContract.isRequested(in: arguments)
          let runsSyntheticVisionV1 =
            SyntheticVisionV1Contract.isRequested(in: arguments)
          do {
            if runsSyntheticVisionV1 {
              let markers = await SyntheticVisionV1Harness(
                runtime: inferenceRuntime,
                journalIsolationAttested: persistence.isEphemeral
              ).run(arguments: arguments)
              for marker in markers {
                print(marker)
                fflush(stdout)
              }
            } else if runsRawPhotoV12Tuning {
              let marker = await RawPhotoV12TuningHarness(
                runtime: inferenceRuntime,
                journalIsolationAttested: persistence.isEphemeral
              ).run(arguments: arguments)
              print(marker)
              fflush(stdout)
            } else if hasBlindValidationLaunchArgument {
              try DerivedMapBlindValidationV1Contract.validateLaunch(arguments: arguments)
              let result = try await PhotoSuggestionEvaluationHarness(
                baselineRuntime: inferenceRuntime
              ).runDerivedMapV3BlindValidationV1IPhone()
              let marker = try DerivedMapBlindValidationV1Contract.consoleMarker(
                for: result.terminalStatus
              )
              print("\(marker) \(result.consoleSummary) \(result.evidenceURL.lastPathComponent)")
            } else if hasTuningLaunchArgument {
              try DerivedMapTuningV3Contract.validateLaunch(arguments: arguments)
              let result = try await PhotoSuggestionEvaluationHarness(
                baselineRuntime: inferenceRuntime
              ).runDerivedMapV3TuningIPhone()
              print("\(DerivedMapTuningV3Contract.runCompleteConsoleMarker) \(result.consoleSummary) \(result.evidenceURL.lastPathComponent)")
            } else if runsPhysicalRawImageSuite {
              let result = try await PhysicalRawImageSuiteHarness().run()
              print(result.consoleMarker)
            } else if let physicalRawImageDiagnosticRequest {
              let result = try await PhysicalRawImageDiagnosticHarness(
                request: physicalRawImageDiagnosticRequest
              ).run()
              print(result.consoleMarker)
            } else if hasPhysicalRawImageLaunchArgument {
              throw PhysicalRawImageDiagnosticError.configurationDrift
            } else if arguments.contains(PhotoSuggestionEvaluationHarness.derivedMapIPhoneLaunchArgument) {
              let result = try await PhotoSuggestionEvaluationHarness(baselineRuntime: inferenceRuntime).runDerivedMapIPhone()
              print("PHOTO_SUGGESTION_EVALUATION_PASS \(result.consoleSummary) \(result.evidenceURL.lastPathComponent)")
            } else if AppStoreRawImageV1PreparationDiagnosticContract
              .hasDiagnosticLaunchArgument(in: arguments)
            {
              let diagnosticImageStore =
                AppStoreRawImageV1PreparationDiagnosticContract
                  .requestsDirectImageData(in: arguments)
                ? try AppStoreRawImageV1HarnessStorage.makeImageStore()
                : nil
              let marker = await AppStoreRawImageV1PreparationDiagnosticHarness(
                runtime: inferenceRuntime,
                imageStore: diagnosticImageStore
              ).run(arguments: arguments)
              print(marker)
              fflush(stdout)
            } else {
              let internalStorage = AppStoreRawImageV1InternalContract.isEnabled(arguments)
                ? try AppStoreRawImageV1HarnessStorage.make()
                : nil
              let harness = EmbeddedGemmaCompletionHarness(
                runtime: inferenceRuntime,
                context: ModelContext(modelContainer),
                imageStore: internalStorage?.imageStore ?? ImageStore(),
                userDefaults: internalStorage?.userDefaults ?? .standard
              )
              if arguments.contains(EmbeddedGemmaCompletionHarness.smokeLaunchArgument) {
                let result = try await harness.runSmoke()
                print("EMBEDDED_GEMMA_SMOKE_PASS \(result.consoleSummary) \(result.evidenceURL.lastPathComponent)")
              } else if arguments.contains(EmbeddedGemmaCompletionHarness.normalFlowLaunchArgument) {
                let result = try await harness.runNormalFlow()
                print("EMBEDDED_GEMMA_NORMAL_FLOW_PASS \(result.consoleSummary) \(result.evidenceURL.lastPathComponent)")
              } else if arguments.contains(EmbeddedGemmaCompletionHarness.relaunchVerifyArgument) {
                let result = try harness.verifyNormalFlowAfterRelaunch()
                print("EMBEDDED_GEMMA_RELAUNCH_PASS \(result.consoleSummary) \(result.evidenceURL.lastPathComponent)")
              }
            }
          } catch {
            if runsRawPhotoV12Tuning {
              print(RawPhotoV12TuningContract.terminalMarker(
                disposition: .failure,
                arm: RawPhotoV12TuningContract.requestedArm(in: arguments),
                fixture: RawPhotoV12TuningContract.requestedFixture(in: arguments),
                errorClass: RawPhotoV12TuningContract.sanitizedErrorClass(error),
                journalIsolationAttested: persistence.isEphemeral
              ))
              fflush(stdout)
            } else if hasBlindValidationLaunchArgument {
              print("\(DerivedMapBlindValidationV1Contract.runFailedConsoleMarker) \(error.localizedDescription)")
            } else if hasTuningLaunchArgument {
              print("PHOTO_TUNING_V3_FAIL \(error.localizedDescription)")
            } else if runsPhysicalRawImageSuite {
              print(PhysicalRawImageSuiteContract.fallbackFailureMarker(for: error))
            } else if runsPhysicalRawImageDiagnostic || hasPhysicalRawImageLaunchArgument {
              print(PhysicalRawImageDiagnosticContract.fallbackFailureMarker(
                for: error,
                request: physicalRawImageDiagnosticRequest ?? .invalidConfiguration
              ))
            } else {
              print("EMBEDDED_GEMMA_COMPLETION_FAIL \(error.localizedDescription)")
            }
          }
        }
        #endif
      .modelContainer(modelContainer)
    } else if let modelContainer = persistence.modelContainer {
      PersistenceRecoveryView(
        message: persistence.recoveryMessage,
        reason: persistence.recoveryReason,
        retry: beginJournalRetry,
        retryIfProtectedDataIsAlreadyAvailable: retryProtectedDataAfterSubscriptionRace
      )
        .modelContainer(modelContainer)
    } else {
      PersistenceRecoveryView(
        message: persistence.recoveryMessage,
        reason: persistence.recoveryReason,
        retry: beginJournalRetry,
        retryIfProtectedDataIsAlreadyAvailable: retryProtectedDataAfterSubscriptionRace
      )
    }
  }

  @MainActor private func openJournalAfterCheckingFrame() async {
    guard persistence.state == .checking else { return }
    let result = await PersistenceBootstrap.openAppJournal()
    if result.permitsJournalPresentation {
      #if DEBUG || HACKATHON_EMBEDDED_GEMMA
      _ = try? AppFolders.importFolder()
      #endif
      AppFolders.enforceStoreProtection()
    }
    persistence = result
  }

  private func beginJournalRetry() {
    // The checking view owns the asynchronous retry. Setting this state never
    // clears, renames, replaces, or creates a canonical on-disk journal.
    guard persistence.state != .checking else { return }
    persistence = .checking
  }

  private func retryProtectedDataAfterSubscriptionRace() {
    guard persistence.recoveryReason == .protectedDataUnavailable,
      !didPerformProtectedDataCatchUpRetry,
      UIApplication.shared.isProtectedDataAvailable
    else { return }
    didPerformProtectedDataCatchUpRetry = true
    beginJournalRetry()
  }
}

private struct PersistenceCheckingView: View {
  var body: some View {
    VStack(spacing: 16) {
      ProgressView()
        .controlSize(.large)
      Text("Checking your protected local journal…")
        .font(.headline)
      Text("GI Journal will not show a new or empty journal while this check is in progress.")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("persistenceChecking")
  }
}

private struct PersistenceRecoveryView: View {
  let message: String?
  let reason: PersistenceBootstrap.RecoveryReason?
  let retry: () -> Void
  let retryIfProtectedDataIsAlreadyAvailable: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Image(systemName: "externaldrive.badge.exclamationmark")
        .font(.system(size: 42))
        .foregroundStyle(.orange)
        .accessibilityHidden(true)
      Text("Journal unavailable")
        .font(.title2.bold())
      Text(message ?? "GI Journal could not safely open its local journal. It will not substitute a new or empty journal.")
      Text("This screen intentionally does not show a new or empty journal. Do not reset or delete the app while GI Journal checks the existing local journal.")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Button("Try Again", action: retry)
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Attempts to reopen the existing local journal without changing it.")
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task {
      if reason == .protectedDataUnavailable {
        retryIfProtectedDataIsAlreadyAvailable()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
      if reason == .protectedDataUnavailable {
        retry()
      }
    }
  }
}

private struct EraseStatus {
  let message: String
  let isSuccess: Bool
}

private enum JournalEraseRecoveryState {
  case working
  case pending(String)
}

struct AppRootView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.scenePhase) private var scenePhase
  let inferenceRuntime: ModelRuntimeCoordinator
  @State private var selectedTab: AppTab
  @State private var requestedHistoryEntryID: UUID?
  @State private var eraseRecoveryState: JournalEraseRecoveryState?
  @State private var eraseStatus: EraseStatus?
  @State private var journalUIIdentity = UUID()
  @StateObject private var privacyShieldWindow = GIJournalPrivacyShieldWindow()

  enum AppTab: Hashable { case log, journal, settings }

  init(inferenceRuntime: ModelRuntimeCoordinator) {
    self.inferenceRuntime = inferenceRuntime
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    let showHistory = arguments.contains("--show-history")
      || arguments.contains("--ui-preview-history-detail")
    _selectedTab = State(initialValue: showHistory ? .journal : .log)
    #else
    _selectedTab = State(initialValue: .log)
    #endif
    _requestedHistoryEntryID = State(initialValue: nil)
    _eraseRecoveryState = State(initialValue: nil)
    _eraseStatus = State(initialValue: nil)
  }

  var body: some View {
    ZStack {
      if let eraseRecoveryState {
        JournalEraseRecoveryView(
          state: eraseRecoveryState,
          retry: retryPendingErase
        )
      } else {
        TabView(selection: $selectedTab) {
          NewEntryTab(store: EntryStore(context: context), runtime: inferenceRuntime)
            .tabItem { Label("Log", systemImage: "plus.circle.fill") }
            .tag(AppTab.log)
          HistoryView(store: EntryStore(context: context), requestedEntryID: $requestedHistoryEntryID)
            .tabItem { Label("Journal", systemImage: "list.bullet") }
            .tag(AppTab.journal)
          GIJournalSettingsView(
            eraseStatus: $eraseStatus,
            beginErase: beginConfirmedErase
          )
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(AppTab.settings)
        }
        .id(journalUIIdentity)
        .privacySensitive()
      }

      if scenePhase != .active {
        GIJournalPrivacyCurtain()
          .zIndex(1_000)
          .transition(.identity)
      }
    }
    .task {
      try? AppFolders.purgeExports()
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-test-seed-journal") {
        seedSyntheticUITestJournal(imageStore: ImageStore())
      }
      #endif
      if !AppRuntime.isUnitTesting { AppFolders.enforceStoreProtection() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .giTimelineShowHistory)) { notification in
      requestedHistoryEntryID = notification.object as? UUID
      selectedTab = .journal
    }
    .onAppear {
      privacyShieldWindow.update(for: scenePhase)
    }
    .onChange(of: scenePhase) { _, phase in
      privacyShieldWindow.update(for: phase)
    }
  }

  private func beginConfirmedErase() {
    guard eraseRecoveryState == nil else { return }
    // This must be synchronous and precede the first await or marker write.
    // Retained inference tasks and view models can never become writable again
    // after the durable marker is eventually cleared. Rotating the view
    // identity also guarantees a marker-absent pre-commit failure reconstructs
    // fresh stores under the new epoch and runs ordinary draft restoration.
    JournalWriteEpoch.shared.invalidateCurrentWriters()
    journalUIIdentity = UUID()
    eraseStatus = nil
    eraseRecoveryState = .working
    performErase(resuming: false)
  }

  private func retryPendingErase() {
    eraseRecoveryState = .working
    performErase(resuming: true)
  }

  private func performErase(resuming: Bool) {
    Task { @MainActor in
      await Task.yield()
      let eraser = JournalDataEraser(context: context)
      do {
        let summary: JournalDataEraseSummary
        if resuming {
          summary = try eraser.resumeOrRestartConfirmedErase()
        } else {
          summary = try eraser.eraseAllJournalData()
        }
        guard summary.completedWithoutWarnings, try !eraser.hasPendingErase() else {
          throw JournalDataErasePendingFailure(
            stage: .fileCleanup,
            recordsDeleted: summary.recordsDeleted,
            filesDeleted: summary.filesDeleted,
            cleanupFailureCount: summary.fileCleanupFailures,
            underlyingDescription: "A protected erase marker remains."
          )
        }
        NotificationCenter.default.post(name: .giJournalDataErased, object: nil)
        eraseStatus = EraseStatus(
          message: "All journal data was erased from this iPhone.",
          isSuccess: true
        )
        eraseRecoveryState = nil
      } catch let pending as JournalDataErasePendingFailure {
        eraseRecoveryState = .pending(pending.localizedDescription)
      } catch {
        do {
          if try eraser.hasPendingErase() {
            eraseRecoveryState = .pending(
              "Your confirmed erase is still pending. Journal views and changes remain blocked until retry finishes."
            )
          } else {
            eraseStatus = EraseStatus(
              message: "Erase could not start. Your existing journal remains available. \(error.localizedDescription)",
              isSuccess: false
            )
            eraseRecoveryState = nil
          }
        } catch {
          // Inability to prove marker absence is itself a fail-closed state.
          eraseRecoveryState = .pending(
            "GI Journal could not verify whether the confirmed erase finished. Journal views and changes remain blocked; unlock this iPhone if needed, then try again."
          )
        }
      }
    }
  }

  #if DEBUG
  /// Deterministic non-health evidence for screenshots. This is reachable only
  /// in an explicitly ephemeral UI-test store and never in an ordinary launch.
  @MainActor private func seedSyntheticUITestJournal(imageStore: ImageStore) {
    guard ProcessInfo.processInfo.arguments.contains("--ui-test-ephemeral-store") else { return }
    let seedMarker = "ui_evidence_synthetic"
    guard ((try? context.fetch(FetchDescriptor<EntryRecord>())) ?? []).contains(where: { $0.demoKind == seedMarker }) == false else { return }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let store = EntryStore(context: context)
    let specs: [(daysAgo: Int, hour: Int, type: Int, pain: Int, marked: Bool, fixture: SyntheticFixture?)] = [
      (8, 9, 2, 4, true, .brown),
      (6, 14, 4, 2, false, nil),
      (3, 8, 4, 1, true, .green),
      (1, 18, 6, 1, false, nil),
      (0, 10, 5, 0, false, .brown),
    ]

    do {
      for (index, spec) in specs.enumerated() {
        let id = UUID()
        let day = calendar.date(byAdding: .day, value: -spec.daysAgo, to: today) ?? today
        let capturedAt = calendar.date(byAdding: .hour, value: spec.hour, to: day) ?? day
        let prepared = try spec.fixture.map { try imageStore.prepare($0.verifiedBundledData()) }
        let loose = spec.type >= 6
        let input = EntryInput(
          id: id,
          capturedAt: capturedAt,
          draftURL: prepared?.url,
          imageSHA256: prepared?.reference.sha256,
          redBlood: .no,
          blackTarry: .no,
          dizziness: .no,
          severePain: .no,
          note: "Synthetic non-health UI evidence entry \(index + 1).",
          painScore: spec.pain,
          urgency: spec.pain >= 4 ? .moderate : UrgencyLevel.none,
          confirmedBristolType: spec.type,
          confirmedPhotoUsable: prepared == nil ? nil : true,
          mixedForm: .no,
          strainingOrIncomplete: loose ? nil : .no,
          leakageOrAccident: loose ? .no : nil,
          analysisSource: .manual,
          markedForDiscussionAt: spec.marked ? capturedAt : nil,
          provenance: .manual,
          reviewedAt: nil,
          originalAIJSON: nil,
          reviewedJSON: nil,
          modelID: nil,
          modelProvenanceJSON: nil,
          demoKind: seedMarker,
          imageFilename: prepared == nil ? nil : "\(id.uuidString).jpg"
        )
        try store.save(input, imageStore: imageStore)
        if let prepared { imageStore.deleteBestEffort(prepared.url) }
      }

      let timeline = ClinicalTimelineStore(context: context)
      let treatmentDate = calendar.date(byAdding: .day, value: -4, to: today) ?? today
      try timeline.addTreatmentEvent(
        kind: .startedTreatment,
        name: "Synthetic treatment marker",
        doseOrNote: "UI evidence only",
        effectiveDate: treatmentDate
      )
      for offset in -10...0 where offset != -2 {
        let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        try timeline.setDailyCompletion(.yes, for: date)
      }
      print("GI_JOURNAL_UI_EVIDENCE_SEEDED entries=\(specs.count)")
    } catch {
      context.rollback()
      print("GI_JOURNAL_UI_EVIDENCE_SEED_FAILED \(error.localizedDescription)")
    }
  }
  #endif
}

private struct JournalEraseRecoveryView: View {
  let state: JournalEraseRecoveryState
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Image(systemName: "trash.slash.fill")
        .font(.system(size: 42))
        .foregroundStyle(GIJournalTheme.safety)
        .accessibilityHidden(true)
      Text("Finishing local erase")
        .font(.title2.bold())
      switch state {
      case .working:
        ProgressView("Finishing the confirmed erase…")
      case .pending(let message):
        Text(message)
        Text("The journal is intentionally unavailable so a later erase retry cannot remove newly written data. Keep the app installed while this finishes.")
          .font(.footnote)
          .foregroundStyle(GIJournalTheme.secondaryText)
        Button("Try Again", action: retry)
          .buttonStyle(GIJournalPrimaryButtonStyle())
          .accessibilityIdentifier("retryPendingJournalErase")
      }
      Spacer()
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(GIJournalTheme.canvas)
  }
}

private struct GIJournalPrivacyCurtain: View {
  var body: some View {
    ZStack {
      GIJournalTheme.canvas.ignoresSafeArea()
      VStack(spacing: 14) {
        Image(systemName: "lock.shield.fill")
          .font(.system(size: 42, weight: .semibold))
          .foregroundStyle(GIJournalTheme.primary)
          .accessibilityHidden(true)
        Text("GI Journal")
          .font(.title2.bold())
        Text("Hidden while the app is inactive")
          .font(.subheadline)
          .foregroundStyle(GIJournalTheme.secondaryText)
      }
      .padding(24)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("GI Journal is hidden for privacy while inactive")
  }
}

/// A separate scene window sits above sheets and full-screen covers while the
/// app is inactive, so camera, PDF, and treatment presentations cannot remain
/// visible in the app-switcher snapshot. The in-tree overlay remains as an
/// immediate fallback while this window is installed.
@MainActor final class GIJournalPrivacyShieldWindow: ObservableObject {
  private weak var capturedScene: UIWindowScene?
  // Keep each scene's hosting controller alive for this app-root lifetime.
  // Tearing it down synchronously while UIKit is completing a foreground
  // transition can produce unbalanced appearance callbacks.
  private var shieldWindows: [ObjectIdentifier: UIWindow] = [:]

  func update(for phase: ScenePhase) {
    if phase == .active {
      capturedScene = resolveScene() ?? capturedScene
      hide()
    } else {
      show(in: capturedScene ?? resolveScene())
    }
  }

  private func resolveScene() -> UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first(where: { scene in scene.windows.contains(where: \.isKeyWindow) })
      ?? scenes.first(where: { $0.activationState != .unattached })
  }

  private func show(in scene: UIWindowScene?) {
    guard let scene else { return }
    capturedScene = scene
    let sceneID = ObjectIdentifier(scene)
    if let existing = shieldWindows[sceneID] {
      existing.isHidden = false
      return
    }
    let controller = UIHostingController(rootView: GIJournalPrivacyCurtain())
    controller.view.backgroundColor = UIColor.systemBackground
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
    window.backgroundColor = UIColor.systemBackground
    window.rootViewController = controller
    window.isHidden = false
    shieldWindows[sceneID] = window
  }

  private func hide() {
    for window in shieldWindows.values {
      window.isHidden = true
    }
  }
}

private enum GIJournalPublicContact {
  static var privacyPolicyURL: URL? { httpsURL(forInfoKey: "GIPrivacyPolicyURL") }
  static var supportURL: URL? { httpsURL(forInfoKey: "GISupportURL") }

  private static func httpsURL(forInfoKey key: String) -> URL? {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
      let components = URLComponents(string: raw),
      components.scheme?.lowercased() == "https",
      components.host?.isEmpty == false
    else { return nil }
    return components.url
  }
}

private struct GIJournalSettingsView: View {
  @Binding var eraseStatus: EraseStatus?
  let beginErase: () -> Void
  @State private var showEraseFirstStep = false
  @State private var showEraseFinalStep = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          #if MANUAL_FALLBACK_RELEASE
          disclosureRow("Works without a developer server", detail: "Journal entry, camera photo attachment, editing, and PDF creation do not use a developer server. Apple Photos may need a connection before it can provide an iCloud-only item you select.", symbol: "wifi.slash")
          #elseif APPSTORE_RELEASE || HACKATHON_EMBEDDED_GEMMA
          disclosureRow("Fully offline processing", detail: "After installation, journal entry, camera photos, and suggestions for photos already available to this app work without an internet connection. Apple Photos may need a connection before it can provide an iCloud-only item you select.", symbol: "wifi.slash")
          #else
          disclosureRow("Offline by design", detail: "Journal entry works without an internet connection. Photo suggestions are available only when an authorized compatible model is installed locally; they never use a network service.", symbol: "wifi.slash")
          #endif
          disclosureRow("No account", detail: "There is no sign-in, identity profile, or developer-managed account.", symbol: "person.crop.circle.badge.xmark")
          disclosureRow("No app-managed developer access", detail: "GI Journal does not automatically send journal data or photos to the developer and provides no account, backend journal access, or app-managed sync. A PDF leaves only when you choose its destination.", symbol: "server.rack")
          disclosureRow("No analytics, tracking, or ads", detail: "The app contains no analytics, tracking, advertising, or behavioral-marketing service.", symbol: "hand.raised.fill")
          disclosureRow("Saved through normal restarts", detail: AppFolders.restartRetentionLine, symbol: "arrow.clockwise.circle")
            .accessibilityIdentifier("restartDurabilityDisclosure")
        } header: {
          settingsSectionHeader("Private by design")
        }

        Section {
          Text("Local privacy notice")
            .font(.headline)
            .foregroundStyle(GIJournalTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)

          #if MANUAL_FALLBACK_RELEASE
          settingsBody("Journal entries can include dates, bowel-movement and symptom answers, notes, and photos. Older compatible entries may also retain their original model provenance. They remain inside this app's protected local container unless you explicitly export a PDF. GI Journal requests backup exclusion for its app-created journal files; iOS controls backup behavior.")
          #else
          settingsBody("Journal entries can include dates, bowel-movement and symptom answers, notes, photos, and on-device suggestion provenance. They remain inside this app's protected local container unless you explicitly export a PDF. GI Journal requests backup exclusion for its app-created journal files; iOS controls backup behavior.")
          #endif
          settingsBody(AppFolders.restartRetentionLine)
          settingsBody(AppFolders.dataLossLine)
          #if MANUAL_FALLBACK_RELEASE
          settingsBody("Attached photos are redrawn as metadata-free, bounded JPEGs for local storage. This public version does not analyze them or use them to prefill fields. The values you enter and save drive the journal and its summaries.")
          #else
          settingsBody("Attached photos are redrawn as metadata-free, bounded JPEGs before local analysis and storage. User-confirmed and user-reported values drive clinical journal values and aggregates. The original on-device suggestion remains local and is used only for provenance and the visible count of photo suggestions changed during review.")
          #endif
          settingsBody("PDF export happens only when you request it. A PDF saved outside GI Journal is governed by the destination you choose and cannot restore the journal.")
        }

        Section {
          NavigationLink("Privacy policy") {
            GIJournalPrivacyPolicyView()
          }
          .accessibilityIdentifier("privacyPolicy")
          NavigationLink("Technical support") {
            GIJournalSupportView()
          }
          .accessibilityIdentifier("technicalSupport")
        } header: {
          settingsSectionHeader("Privacy and support")
        }

        #if MANUAL_FALLBACK_RELEASE
        Section("Manual photo attachments") {
          Text(GIJournalPublicManualLaneCopy.photoAttachmentDisclosure)
        }
        #else
        Section("Photo suggestions") {
          #if APPSTORE_RELEASE
          #if MANUAL_FALLBACK_RELEASE
          Text("This build does not include automatic photo analysis. An attached photo stays with a complete manual entry and is not sent to the developer.")
          #else
          Text("GI Journal uses an on-device photo-suggestion pipeline. Photos and suggestions are not sent to the developer. You can always log without a photo.")
          #endif
          #elseif HACKATHON_EMBEDDED_GEMMA
          Text("This internal build uses the full embedded Gemma 4 E4B model through LiteRT-LM. Its ordinary photo-suggestion route gives Gemma a simplified picture summary created on this device; direct prepared-image bytes are used only by isolated engineering diagnostics. Nothing is uploaded to the developer or model provider. You can always log without a photo.")
          #else
          Text("This internal build does not bundle the public-release Gemma model. If an authorized compatible model is installed locally, a prepared photo is processed on this device into a conservative, editable suggestion; otherwise you can log without a photo. The model provider does not receive the photo, prompt, suggestion, or journal record.")
          Text("Public release model identity")
            .font(.subheadline.weight(.semibold))
          let model = ModelDescriptor.liteRTGemma4E4B
          modelIdentityRow("Family", model.family)
          modelIdentityRow("Model", model.modelID)
          modelIdentityRow("Artifact", model.artifactFilename)
          modelIdentityRow("Revision", model.sourceRevision)
          modelIdentityRow("SHA-256", model.expectedSHA256)
          #endif
        }
        #endif

        Section("Using GI Journal with your care team") {
          Text("GI Journal records observations. It does not diagnose conditions or recommend treatment. Use the journal with your established care team.")
        }

        Section("Third-party acknowledgments") {
          Text(GIJournalThirdPartyAcknowledgments.summary)
          #if !APPSTORE_RELEASE
          if GIJournalThirdPartyAcknowledgments.includesGemmaModelLink {
            let model = ModelDescriptor.liteRTGemma4E4B
            Link("Pinned Gemma 4 E4B model", destination: URL(string: model.sourceURL)!)
          }
          Link("Apache License 2.0", destination: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!)
          Link("LiteRT-LM source", destination: URL(string: "https://github.com/google-ai-edge/LiteRT-LM")!)
          #endif
          NavigationLink("Licenses and notices") {
            ThirdPartyNoticesView()
          }
          .accessibilityIdentifier("thirdPartyNotices")
        }

        Section("About") {
          LabeledContent("Version", value: version)
          LabeledContent("Build", value: build)
        }

        Section {
          Button(role: .destructive) {
            eraseStatus = nil
            showEraseFirstStep = true
          } label: {
            Label("Erase All Journal Data…", systemImage: "trash")
          }
          .accessibilityIdentifier("eraseAllJournalData")

          if let eraseStatus {
            Label(eraseStatus.message, systemImage: eraseStatus.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(eraseStatus.isSuccess ? GIJournalTheme.primary : GIJournalTheme.safety)
              .accessibilityIdentifier("eraseJournalDataStatus")
          }
        } header: {
          Text("Erase local data")
        } footer: {
          Text("This permanently removes every journal entry, legacy local timeline record, no-bowel-movement marker, stored journal photo, unfinished draft, and temporary export. It never removes installed model assets or the app.")
        }
      }
      .navigationTitle("Settings")
      .confirmationDialog(
        "Erase all journal data?",
        isPresented: $showEraseFirstStep,
        titleVisibility: .visible
      ) {
        Button("Continue to Final Confirmation", role: .destructive) {
          showEraseFinalStep = true
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This affects all journal records and local journal files on this iPhone and cannot be undone.")
      }
      .alert("Final confirmation", isPresented: $showEraseFinalStep) {
        Button("Erase All Journal Data", role: .destructive, action: beginErase)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Permanently erase all journal records, photos, drafts, and temporary PDF exports? Any installed model assets will remain in place.")
      }
    }
  }

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
  }

  private var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
  }

  private func disclosureRow(_ title: String, detail: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.body)
        .foregroundStyle(GIJournalTheme.primary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(GIJournalTheme.text)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func settingsSectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.headline)
      .foregroundStyle(GIJournalTheme.text)
      .textCase(nil)
  }

  private func settingsBody(_ text: String) -> some View {
    Text(text)
      .foregroundStyle(GIJournalTheme.text)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func modelIdentityRow(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(GIJournalTheme.secondaryText)
      Text(value)
        .font(.caption.monospaced())
        .textSelection(.enabled)
    }
    .accessibilityElement(children: .combine)
  }

}

enum GIJournalThirdPartyAcknowledgments {
  static var summary: String {
    #if MANUAL_FALLBACK_RELEASE
    "This public manual-first build does not include or run a third-party AI model or runtime. No third-party analytics or advertising SDK is included."
    #elseif APPSTORE_RELEASE || HACKATHON_EMBEDDED_GEMMA
    "The embedded Gemma 4 E4B model and the LiteRT-LM on-device runtime are provided by Google and the LiteRT community under the Apache License 2.0. Their inclusion does not imply endorsement of GI Journal. No third-party analytics or advertising SDK is included."
    #else
    "The public release model is Gemma 4 E4B, used through the LiteRT-LM on-device runtime from Google and the LiteRT community under the Apache License 2.0. This internal build does not bundle that model. No third-party analytics or advertising SDK is included."
    #endif
  }

  static var includesGemmaModelLink: Bool {
    #if MANUAL_FALLBACK_RELEASE
    false
    #else
    true
    #endif
  }
}

enum GIJournalPublicManualLaneCopy {
  static let photoAttachmentDisclosure =
    "This public version contains no model. It stores an attached photo with the manual entry and can include it in a PDF. It does not analyze the photo or use it to prefill journal fields."

  static let privacyPhotoDisclosure =
    "A photo selected for an entry is redrawn as a bounded, metadata-free JPEG for local storage. This public version contains no model, does not analyze the photo, and does not use the photo to prefill fields."
}

private struct GIJournalPrivacyPolicyView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        #if MANUAL_FALLBACK_RELEASE
        Text("GI Journal keeps entries, retained photo copies, day markers, drafts, temporary exports, and any historical provenance already attached to an older compatible entry in this app's protected local container. It does not automatically transmit or collect that content for the developer. The developer operates no account, journal server, analytics, advertising, tracking, remote-inference, sync, or automatic journal-backup service and has no app-managed access to the journal.")
        Text(GIJournalPublicManualLaneCopy.privacyPhotoDisclosure)
        #else
        Text("GI Journal keeps entries, retained photo copies, day markers, drafts, suggestion provenance, and temporary exports in this app's protected local container. It does not automatically transmit or collect that content for the developer. The developer operates no account, journal server, analytics, advertising, tracking, remote-inference, sync, or automatic journal-backup service and has no app-managed access to the journal.")
        Text("A photo selected for an entry is redrawn as a bounded, metadata-free JPEG before local processing and storage. If this build has photo suggestions enabled, analysis stays on this iPhone; it is not sent to a server, the developer, or a model provider.")
        #endif
        Text(AppFolders.restartRetentionLine)
        Text("A PDF leaves GI Journal only when you choose a destination. The destination's privacy and retention terms then apply. \(AppFolders.dataLossLine)")
        Text("GI Journal does not automatically collect health data, photos, identifiers, diagnostics, usage data, prompts, or model output for the developer. Someone can still voluntarily disclose information outside the app, including by sharing a PDF or sending a support message; do not send journal photos, shared PDFs, or other sensitive health information to support.")
        if let url = GIJournalPublicContact.privacyPolicyURL {
          Link("View the current policy online", destination: url)
            .accessibilityIdentifier("privacyPolicyOnline")
        } else {
          Text("The online policy address is not configured in this internal build.")
            .foregroundStyle(GIJournalTheme.secondaryText)
        }
      }
      .font(.body)
      .foregroundStyle(GIJournalTheme.text)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .navigationTitle("Privacy policy")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct GIJournalSupportView: View {
  @Environment(\.openURL) private var openURL

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 12) {
          supportSectionHeader("Product support")
        Text("Use product support for installation, access, journal, export, or app-behavior questions. Do not send journal photos, exported PDFs, or other sensitive health information.")
          .font(.body)
          .foregroundStyle(GIJournalTheme.text)
        if let url = GIJournalPublicContact.supportURL {
          Button {
            openURL(url)
          } label: {
            Label("Open technical support", systemImage: "arrow.up.right.square")
              .font(.body.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
            .buttonStyle(.plain)
            .foregroundStyle(GIJournalTheme.primary)
            .accessibilityIdentifier("supportOnline")
            .accessibilityHint("Opens the public support website")
        } else {
          Text("The public support address is not configured in this internal build.")
            .font(.body)
            .foregroundStyle(GIJournalTheme.secondaryText)
        }
        }
        .giJournalCard()

        VStack(alignment: .leading, spacing: 12) {
          supportSectionHeader("Medical questions")
          Group {
        #if MANUAL_FALLBACK_RELEASE
            Text("Technical support cannot interpret journal entries or attached photos. For medical questions, use your established care team.")
        #else
            Text("Technical support cannot interpret journal entries or photo suggestions. For medical questions, use your established care team.")
        #endif
          }
          .font(.body)
          .foregroundStyle(GIJournalTheme.text)
        }
        .giJournalCard()
      }
      .padding(GIJournalTheme.pageInset)
    }
    .background(GIJournalTheme.canvas)
    .navigationTitle("Technical support")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func supportSectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.title3.bold())
      .foregroundStyle(GIJournalTheme.text)
      .accessibilityAddTraits(.isHeader)
  }
}

private struct ThirdPartyNoticesView: View {
  private let notices: String

  init(bundle: Bundle = .main) {
    if let url = bundle.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
       let text = try? String(contentsOf: url, encoding: .utf8),
       !text.isEmpty {
      notices = text
    } else {
      notices = "The bundled third-party notices could not be displayed."
    }
  }

  var body: some View {
    ScrollView {
      Text(notices)
        .font(.footnote.monospaced())
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    .navigationTitle("Licenses and notices")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("thirdPartyNoticesText")
  }
}
