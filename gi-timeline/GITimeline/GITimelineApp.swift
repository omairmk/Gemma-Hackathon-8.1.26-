import SwiftUI
import SwiftData

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

@main struct GITimelineApp: App {
  let modelContainer: ModelContainer
  let inferenceRuntime = ModelRuntimeCoordinator()
  init() {
    do {
      let schema = Schema([EntryRecord.self])
      let configuration: ModelConfiguration
      if AppRuntime.isUnitTesting {
        configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
      } else {
        configuration = ModelConfiguration("GITimeline", schema: schema, url: try AppFolders.storeURL(), cloudKitDatabase: .none)
      }
      modelContainer = try ModelContainer(for: schema, configurations: [configuration])
      _ = try AppFolders.importFolder()
      if !AppRuntime.isUnitTesting { AppFolders.enforceStoreProtection() }
    }
    catch { fatalError("SwiftData container could not be created: \(error)") }
  }
  var body: some Scene {
    WindowGroup {
      AppRootView(inferenceRuntime: inferenceRuntime)
        #if DEBUG
        .task {
          let arguments = ProcessInfo.processInfo.arguments
          if arguments.contains("--run-overnight-gemma-smoke") {
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
          do {
            let harness = EmbeddedGemmaCompletionHarness(
              runtime: inferenceRuntime,
              context: ModelContext(modelContainer)
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
          } catch {
            print("EMBEDDED_GEMMA_COMPLETION_FAIL \(error.localizedDescription)")
          }
        }
        #endif
    }
    .modelContainer(modelContainer)
  }
}

struct AppRootView: View {
  @Environment(\.modelContext) private var context
  let inferenceRuntime: ModelRuntimeCoordinator
  @State private var selectedTab: AppTab
  @State private var requestedHistoryEntryID: UUID?

  enum AppTab: Hashable { case newEntry, history }

  init(inferenceRuntime: ModelRuntimeCoordinator) {
    self.inferenceRuntime = inferenceRuntime
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    let showHistory = arguments.contains("--show-history")
      || arguments.contains("--ui-preview-history-detail")
    _selectedTab = State(initialValue: showHistory ? .history : .newEntry)
    #else
    _selectedTab = State(initialValue: .newEntry)
    #endif
    _requestedHistoryEntryID = State(initialValue: nil)
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      NewEntryTab(store: EntryStore(context: context), runtime: inferenceRuntime)
        .tabItem { Label("New Entry", systemImage: "plus.circle") }
        .tag(AppTab.newEntry)
      HistoryView(store: EntryStore(context: context), requestedEntryID: $requestedHistoryEntryID)
        .tabItem { Label("History", systemImage: "clock") }
        .tag(AppTab.history)
    }
    .task {
      let images = ImageStore()
      images.sweepDrafts(keeping: nil)
      try? EntryStore(context: context).reconcile(imageStore: images)
      if !AppRuntime.isUnitTesting { AppFolders.enforceStoreProtection() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .giTimelineShowHistory)) { notification in
      requestedHistoryEntryID = notification.object as? UUID
      selectedTab = .history
    }
  }
}
