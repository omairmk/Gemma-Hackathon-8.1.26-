import SwiftUI
import SwiftData

enum HistoryPresentation {
  static let manualAnalysisText = "No AI analysis was saved."
  static func reportedValue(_ value: String?) -> String { value ?? "Not recorded" }
}

@MainActor final class HistoryDeletionCoordinator: ObservableObject {
  @Published var pendingDelete: EntryRecord?
  @Published var errorMessage: String?
  private let store: EntryStoring
  private let imageStore: ImageStore

  init(store: EntryStoring, imageStore: ImageStore) { self.store = store; self.imageStore = imageStore }
  func request(_ entry: EntryRecord) { pendingDelete = entry }
  func setConfirmationPresented(_ presented: Bool) { if !presented { pendingDelete = nil } }
  func setAlertPresented(_ presented: Bool) { if !presented { errorMessage = nil } }
  func confirm() {
    guard let pendingDelete else { return }
    do { try store.delete(pendingDelete, imageStore: imageStore); self.pendingDelete = nil }
    catch { errorMessage = error.localizedDescription; self.pendingDelete = nil }
  }
  func resetSyntheticDemoEntries(_ entries: [EntryRecord]) {
    do {
      for entry in entries where DemoDataPolicy.isSyntheticDemo(entry) {
        try store.delete(entry, imageStore: imageStore)
      }
    } catch { errorMessage = error.localizedDescription }
  }
}

struct HistoryView: View {
  @Query(sort: \EntryRecord.capturedAt, order: .reverse) private var entries: [EntryRecord]
  @StateObject private var deletion: HistoryDeletionCoordinator
  @State private var showResetDemoConfirmation = false
  @State private var path: [UUID] = []
  @MainActor init(store: EntryStoring) { _deletion = StateObject(wrappedValue: HistoryDeletionCoordinator(store: store, imageStore: ImageStore())) }
  var body: some View {
    NavigationStack(path: $path) {
      List {
        ProductBadges()
        if entries.isEmpty {
          ContentUnavailableView(
            "No entries yet",
            systemImage: "clock",
            description: Text("Analyze a demo image or save a manual entry to begin your timeline.")
          )
          .accessibilityIdentifier("historyEmptyState")
        }
        ForEach(entries) { entry in
          NavigationLink(value: entry.id) {
            HStack(spacing: 12) {
              historyThumbnail(entry)
              VStack(alignment: .leading, spacing: 4) {
                Text(entry.capturedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.headline)
                if let observation = entry.observation {
                  Text("Bristol \(observation.apparentBristolType.map(String.init) ?? "none") · \(observation.apparentColor.replacingOccurrences(of: "_", with: " "))")
                    .font(.subheadline)
                } else { Text("Manual entry").font(.subheadline) }
                if DemoDataPolicy.isSyntheticDemo(entry) {
                  Text("Synthetic demo").font(.caption).foregroundStyle(.secondary)
                } else if !entry.flagSummary.isEmpty {
                  Text(entry.flagSummary).font(.caption).foregroundStyle(.secondary)
                }
                if let runtime = entry.savedRuntimeLabel {
                  Text(runtime).font(.caption2).foregroundStyle(entry.isUIDemoProvider ? Color.orange : Color.secondary)
                }
                if entry.imageUnavailable { Text("Image unavailable").foregroundStyle(.secondary).font(.caption) }
              }
            }
          }
          .accessibilityIdentifier("historyEntry")
          .swipeActions { Button("Delete", role: .destructive) { deletion.request(entry) } }
        }
      }
      .navigationTitle("History")
      .navigationDestination(for: UUID.self) { entryID in
        if let entry = entries.first(where: { $0.id == entryID }) {
          EntryDetailView(entry: entry)
        } else {
          ContentUnavailableView("Entry unavailable", systemImage: "exclamationmark.triangle")
        }
      }
      .task {
        guard ProcessInfo.processInfo.arguments.contains("--ui-preview-history-detail"),
          path.isEmpty, let entry = entries.first
        else { return }
        path = [entry.id]
      }
      .toolbar {
        if entries.contains(where: DemoDataPolicy.isSyntheticDemo) {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Reset Demo") { showResetDemoConfirmation = true }
              .accessibilityIdentifier("resetDemo")
          }
        }
      }
      .confirmationDialog("Remove synthetic demo entries?", isPresented: $showResetDemoConfirmation, titleVisibility: .visible) {
        Button("Reset Demo", role: .destructive) { deletion.resetSyntheticDemoEntries(entries) }
        Button("Cancel", role: .cancel) {}
      } message: { Text("Only bundled synthetic demo entries will be removed.") }
      .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deletion.pendingDelete != nil }, set: deletion.setConfirmationPresented), titleVisibility: .visible) {
        Button("Delete", role: .destructive) { deletion.confirm() }
      }
      .alert("Could not delete entry", isPresented: Binding(get: { deletion.errorMessage != nil }, set: deletion.setAlertPresented)) { Button("OK", role: .cancel) {} } message: { Text(deletion.errorMessage ?? "") }
    }
  }
  @ViewBuilder private func historyThumbnail(_ entry: EntryRecord) -> some View {
    if let filename = entry.imageFilename,
      let url = ImageStore().imageURL(filename: filename),
      let image = UIImage(contentsOfFile: url.path)
    {
      Image(uiImage: image).resizable().scaledToFill()
        .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12))
    } else {
      RoundedRectangle(cornerRadius: 12).fill(.quaternary)
        .frame(width: 64, height: 64)
        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
    }
  }
}

struct EntryDetailView: View {
  let entry: EntryRecord
  var body: some View {
    List {
      if let url = ImageStore().imageURL(filename: entry.imageFilename), let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280) }
      else { Text("Image unavailable").foregroundStyle(.secondary) }
      Section("You reported") {
        report("Red blood", entry.redBlood); report("Black or tarry stool", entry.blackTarry); report("Dizziness or fainting", entry.dizziness); report("Severe or worsening pain", entry.severePain)
        report("Note", DemoDataPolicy.presentedNote(for: entry))
      }
      if entry.provenance == EntryProvenance.manual.rawValue { Section { Text(HistoryPresentation.manualAnalysisText) } }
      else if let observation = entry.observation {
        Section(entry.isUIDemoProvider ? "UI demo observation, reviewed by you" : "AI-assisted observation, reviewed by you") {
          if entry.provenance == EntryProvenance.ai_edited.rawValue { Text("(edited)").font(.caption) }
          if !observation.imageUsable { row("Image quality", "\(observation.qualityIssue) — assessment not possible") }
          else { row("Bristol type", observation.apparentBristolType.map(String.init) ?? "none"); row("Apparent color", observation.apparentColor); row("Form", observation.form); row("Red-appearing material", observation.redAppearingMaterial); row("Black/tarry appearance", observation.blackTarryAppearance) }
        }
        if let runtime = entry.savedRuntimeLabel {
          Text(runtime).font(.footnote).foregroundStyle(entry.isUIDemoProvider ? Color.orange : Color.secondary)
        }
        if let model = entry.modelID { Text(model).font(.caption2).foregroundStyle(.secondary) }
      }
    }.navigationTitle("Entry").accessibilityIdentifier("entryDetail")
  }
  @ViewBuilder private func report(_ label: String, _ value: String?) -> some View { LabeledContent(label, value: HistoryPresentation.reportedValue(value)) }
  @ViewBuilder private func row(_ label: String, _ value: String) -> some View { LabeledContent(label, value: value.replacingOccurrences(of: "_", with: " ")) }
}
