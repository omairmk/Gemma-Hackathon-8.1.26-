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
}

struct HistoryView: View {
  @Query(sort: \EntryRecord.capturedAt, order: .reverse) private var entries: [EntryRecord]
  @StateObject private var deletion: HistoryDeletionCoordinator
  @MainActor init(store: EntryStoring) { _deletion = StateObject(wrappedValue: HistoryDeletionCoordinator(store: store, imageStore: ImageStore())) }
  var body: some View {
    NavigationStack {
      List {
        ProductBadges()
        ForEach(entries) { entry in
          NavigationLink { EntryDetailView(entry: entry) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(entry.capturedAt, style: .date); Text(entry.capturedAt, style: .time).font(.caption)
              Text(entry.flagSummary.isEmpty ? "Not recorded" : entry.flagSummary).font(.caption)
              if let observation = entry.observation { Text("Bristol \(observation.apparentBristolType.map(String.init) ?? "none") · \(observation.apparentColor.replacingOccurrences(of: "_", with: " "))").font(.caption) }
              if entry.imageUnavailable { Text("Image unavailable").foregroundStyle(.secondary).font(.caption) }
            }
          }
          .swipeActions { Button("Delete", role: .destructive) { deletion.request(entry) } }
        }
      }
      .navigationTitle("History")
      .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deletion.pendingDelete != nil }, set: deletion.setConfirmationPresented), titleVisibility: .visible) {
        Button("Delete", role: .destructive) { deletion.confirm() }
      }
      .alert("Could not delete entry", isPresented: Binding(get: { deletion.errorMessage != nil }, set: deletion.setAlertPresented)) { Button("OK", role: .cancel) {} } message: { Text(deletion.errorMessage ?? "") }
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
        report("Note", entry.note)
      }
      if entry.provenance == EntryProvenance.manual.rawValue { Section { Text(HistoryPresentation.manualAnalysisText) } }
      else if let observation = entry.observation {
        Section("AI-assisted observation, reviewed by you") {
          if entry.provenance == EntryProvenance.ai_edited.rawValue { Text("(edited)").font(.caption) }
          if !observation.imageUsable { row("Image quality", "\(observation.qualityIssue) — assessment not possible") }
          else { row("Bristol type", observation.apparentBristolType.map(String.init) ?? "none"); row("Apparent color", observation.apparentColor); row("Form", observation.form); row("Red-appearing material", observation.redAppearingMaterial); row("Black/tarry appearance", observation.blackTarryAppearance) }
        }
        if let model = entry.modelID { Text(model).font(.footnote).foregroundStyle(.secondary) }
      }
    }.navigationTitle("Entry")
  }
  @ViewBuilder private func report(_ label: String, _ value: String?) -> some View { LabeledContent(label, value: HistoryPresentation.reportedValue(value)) }
  @ViewBuilder private func row(_ label: String, _ value: String) -> some View { LabeledContent(label, value: value.replacingOccurrences(of: "_", with: " ")) }
}
