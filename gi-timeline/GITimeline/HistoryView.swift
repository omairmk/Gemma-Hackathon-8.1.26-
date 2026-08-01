import SwiftUI
import SwiftData

enum HistoryPresentation {
  static let manualAnalysisText = "No AI analysis was saved."
  static func reportedValue(_ value: String?) -> String { value.map(humanReadableHistoryValue) ?? "Not recorded" }
  static func entryCount(_ count: Int) -> String { "\(count) \(count == 1 ? "entry" : "entries") · stored locally" }
}

@MainActor final class HistoryDeletionCoordinator: ObservableObject {
  @Published var pendingDelete: EntryRecord?
  @Published var errorMessage: String?
  private let store: EntryStoring
  private let imageStore: ImageStore

  init(store: EntryStoring, imageStore: ImageStore) {
    self.store = store
    self.imageStore = imageStore
  }

  func request(_ entry: EntryRecord) { pendingDelete = entry }
  func setConfirmationPresented(_ presented: Bool) { if !presented { pendingDelete = nil } }
  func setAlertPresented(_ presented: Bool) { if !presented { errorMessage = nil } }

  func confirm() {
    guard let pendingDelete else { return }
    do {
      try store.delete(pendingDelete, imageStore: imageStore)
      self.pendingDelete = nil
    } catch {
      errorMessage = error.localizedDescription
      self.pendingDelete = nil
    }
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
  @Binding private var requestedEntryID: UUID?

  @MainActor init(store: EntryStoring, requestedEntryID: Binding<UUID?> = .constant(nil)) {
    _deletion = StateObject(wrappedValue: HistoryDeletionCoordinator(store: store, imageStore: ImageStore()))
    _requestedEntryID = requestedEntryID
  }

  private var developerToolsVisible: Bool {
    #if DEBUG
    ProcessInfo.processInfo.arguments.contains("--show-developer-tools")
    #else
    false
    #endif
  }

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("History")
            .font(.largeTitle.bold())
            .accessibilityAddTraits(.isHeader)

          if entries.isEmpty {
            ContentUnavailableView(
              "No entries yet",
              systemImage: "clock",
              description: Text("Attach a photo from New Entry to begin your timeline.")
            )
            .frame(maxWidth: .infinity, minHeight: 360)
            .accessibilityIdentifier("historyEmptyState")
          } else {
            VStack(spacing: 0) {
              ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                NavigationLink(value: entry.id) {
                  HistoryRow(entry: entry)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("historyEntry")
                .contextMenu {
                  Button("Delete", role: .destructive) { deletion.request(entry) }
                }
                if index < entries.count - 1 { Divider().padding(.leading, 86) }
              }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(HistoryPresentation.entryCount(entries.count))
              .font(.footnote)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
          }

          Text("Prototype — not medical advice")
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .padding(.bottom, 24)
      }
      .background(Color(.systemGroupedBackground))
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: UUID.self) { entryID in
        if let entry = entries.first(where: { $0.id == entryID }) {
          EntryDetailView(entry: entry, deletion: deletion)
        } else {
          ContentUnavailableView("Entry unavailable", systemImage: "exclamationmark.triangle")
        }
      }
      .task {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-preview-history-detail"),
          path.isEmpty, let entry = entries.first
        {
          path = [entry.id]
        }
        #endif
        openRequestedEntryIfAvailable()
      }
      .onChange(of: requestedEntryID) { _, _ in
        openRequestedEntryIfAvailable()
      }
      .onChange(of: entries.map(\.id)) { _, _ in
        openRequestedEntryIfAvailable()
      }
      .toolbar {
        #if DEBUG
        if developerToolsVisible, entries.contains(where: DemoDataPolicy.isSyntheticDemo) {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Reset Demo") { showResetDemoConfirmation = true }
              .accessibilityIdentifier("resetDemo")
          }
        }
        #endif
      }
      .confirmationDialog("Remove synthetic demo entries?", isPresented: $showResetDemoConfirmation, titleVisibility: .visible) {
        Button("Reset Demo", role: .destructive) { deletion.resetSyntheticDemoEntries(entries) }
        Button("Cancel", role: .cancel) {}
      } message: { Text("Only bundled synthetic demo entries will be removed.") }
      .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deletion.pendingDelete != nil }, set: deletion.setConfirmationPresented), titleVisibility: .visible) {
        Button("Delete", role: .destructive) { deletion.confirm() }
        Button("Cancel", role: .cancel) {}
      } message: { Text("This removes the entry and its stored photo.") }
      .alert("Could not delete entry", isPresented: Binding(get: { deletion.errorMessage != nil }, set: deletion.setAlertPresented)) {
        Button("OK", role: .cancel) {}
      } message: { Text(deletion.errorMessage ?? "") }
    }
  }

  private func openRequestedEntryIfAvailable() {
    guard let entryID = requestedEntryID,
      entries.contains(where: { $0.id == entryID })
    else { return }
    path = [entryID]
    requestedEntryID = nil
  }
}

private struct HistoryRow: View {
  let entry: EntryRecord
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top, spacing: 14) {
            historyThumbnail
            dateAndTime
            Spacer(minLength: 8)
            chevron
          }
          summary
        }
      } else {
        HStack(spacing: 14) {
          historyThumbnail
          VStack(alignment: .leading, spacing: 5) {
            dateAndTime
            summary
          }
          Spacer(minLength: 8)
          chevron
        }
      }
    }
    .padding(12)
    .contentShape(Rectangle())
  }

  private var dateAndTime: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(entry.capturedAt, format: .dateTime.month(.abbreviated).day().year())
        .font(.headline)
      Text(entry.capturedAt, format: .dateTime.hour().minute())
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(primarySummary)
        .font(.subheadline.weight(.medium))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("historyEntrySummary")
      if let secondarySummary {
        Text(secondarySummary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("historyEntrySecondarySummary")
      }
    }
  }

  private var chevron: some View {
    Image(systemName: "chevron.right")
      .font(.caption.bold())
      .foregroundStyle(.tertiary)
  }

  private var primarySummary: String {
    guard let observation = entry.observation else { return "Photo entry" }
    let type = observation.apparentBristolType.map(String.init) ?? "—"
    return "Type \(type) · \(humanReadableHistoryValue(observation.apparentColor).lowercased())"
  }

  private var secondarySummary: String? {
    if !entry.flagSummary.isEmpty { return entry.flagSummary }
    guard let form = entry.observation?.form, form != "unable_to_assess" else { return nil }
    return humanReadableHistoryValue(form)
  }

  @ViewBuilder private var historyThumbnail: some View {
    if let filename = entry.imageFilename,
      let url = ImageStore().imageURL(filename: filename),
      let image = UIImage(contentsOfFile: url.path)
    {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    } else {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.quaternary)
        .frame(width: 64, height: 64)
        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
    }
  }
}

struct EntryDetailView: View {
  let entry: EntryRecord
  @ObservedObject var deletion: HistoryDeletionCoordinator
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var showDeleteConfirmation = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(entry.capturedAt, format: .dateTime.month(.wide).day().year())
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)
        Text(entry.capturedAt, format: .dateTime.hour().minute())
          .font(.headline)
          .foregroundStyle(.secondary)

        photo

        if entry.provenance == EntryProvenance.manual.rawValue {
          Text(HistoryPresentation.manualAnalysisText)
            .foregroundStyle(.secondary)
            .detailCard()
        } else if let observation = entry.observation {
          VStack(alignment: .leading, spacing: 14) {
            HStack {
              Text("Observations").font(.title3.bold())
              Spacer()
              Label("Reviewed", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if entry.provenance == EntryProvenance.ai_edited.rawValue {
              Text("Edited during review").font(.caption).foregroundStyle(.secondary)
            }
            if observation.imageUsable {
              detailRow("Bristol type", observation.apparentBristolType.map { "Type \($0)" } ?? "Not recorded")
              detailRow("Apparent color", humanReadableHistoryValue(observation.apparentColor))
              detailRow("Form", humanReadableHistoryValue(observation.form))
              detailRow("Red-appearing material", humanReadableHistoryValue(observation.redAppearingMaterial))
              detailRow("Black or tarry appearance", humanReadableHistoryValue(observation.blackTarryAppearance))
              detailRow("Image quality", "Usable")
            } else {
              detailRow("Image quality", humanReadableHistoryValue(observation.qualityIssue))
            }
          }
          .detailCard()
        }

        VStack(alignment: .leading, spacing: 14) {
          Text("Symptoms and context").font(.title3.bold())
          detailRow("Red blood", HistoryPresentation.reportedValue(entry.redBlood))
          detailRow("Black or tarry stool", HistoryPresentation.reportedValue(entry.blackTarry))
          detailRow("Dizziness or fainting", HistoryPresentation.reportedValue(entry.dizziness))
          detailRow("Severe or worsening pain", HistoryPresentation.reportedValue(entry.severePain))
          detailRow("Note", HistoryPresentation.reportedValue(DemoDataPolicy.presentedNote(for: entry)))
        }
        .detailCard()

        Text("Prototype — not medical advice")
          .font(.footnote).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      }
      .padding(20)
      .padding(.bottom, 28)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Entry detail")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("entryDetail")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Delete entry", systemImage: "trash", role: .destructive) {
          showDeleteConfirmation = true
        }
        .accessibilityIdentifier("deleteEntry")
      }
    }
    .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
      Button("Delete", role: .destructive) {
        deletion.request(entry)
        deletion.confirm()
        if deletion.errorMessage == nil { dismiss() }
      }
      Button("Cancel", role: .cancel) {}
    } message: { Text("This removes the entry and its stored photo.") }
  }

  @ViewBuilder private var photo: some View {
    if let url = ImageStore().imageURL(filename: entry.imageFilename),
      let image = UIImage(contentsOfFile: url.path)
    {
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: 380)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    } else {
      ContentUnavailableView("Image unavailable", systemImage: "photo")
        .frame(maxWidth: .infinity, minHeight: 220)
        .detailCard()
    }
  }

  private func detailRow(_ label: String, _ value: String) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 4) {
          Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(value)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("detailValue.\(label)")
        }
      } else {
        LabeledContent {
          Text(value)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("detailValue.\(label)")
        } label: {
          Text(label)
        }
      }
    }
  }
}

private struct DetailCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(16)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

private extension View {
  func detailCard() -> some View { modifier(DetailCardModifier()) }
}

private func humanReadableHistoryValue(_ value: String) -> String {
  value.replacingOccurrences(of: "_", with: " ").capitalized
}
