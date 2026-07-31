import SwiftUI
import SwiftData

enum AppRuntime {
  static var isUnitTesting: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }
}

@main struct GITimelineApp: App {
  let modelContainer: ModelContainer
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
  var body: some Scene { WindowGroup { AppRootView() }.modelContainer(modelContainer) }
}

struct AppRootView: View {
  @Environment(\.modelContext) private var context
  var body: some View {
    TabView {
      NewEntryTab(store: EntryStore(context: context)).tabItem { Label("New Entry", systemImage: "plus.circle") }
      HistoryView(store: EntryStore(context: context)).tabItem { Label("History", systemImage: "clock") }
    }
    .task {
      let images = ImageStore()
      images.sweepDrafts(keeping: nil)
      try? EntryStore(context: context).reconcile(imageStore: images)
      if !AppRuntime.isUnitTesting { AppFolders.enforceStoreProtection() }
    }
  }
}
