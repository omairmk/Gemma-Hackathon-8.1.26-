import SwiftUI
import SwiftData
import GITimelineCore

enum HistoryPresentation {
  static let manualAnalysisText = "Entered by you without a photo suggestion."
  static func reportedValue(_ value: String?) -> String { value.map(humanReadableHistoryValue) ?? "Not recorded" }
  static func triState(_ value: ClinicalTriState?) -> String { value?.displayName ?? "Not recorded" }
}

enum JournalPhotoPresentation {
  static func canDisplay(_ entry: EntryRecord) -> Bool {
    entry.imageFilename != nil && !entry.imageUnavailable
  }

  static func unavailableTitle(for entry: EntryRecord) -> String {
    entry.imageFilename == nil ? "No photo attached" : "Photo unavailable"
  }
}

@MainActor final class HistoryDeletionCoordinator: ObservableObject {
  @Published var pendingDelete: EntryRecord?
  @Published var errorMessage: String?
  @Published var noticeMessage: String?
  private let store: EntryStoring
  private let imageStore: ImageStore

  init(store: EntryStoring, imageStore: ImageStore) {
    self.store = store
    self.imageStore = imageStore
  }

  func request(_ entry: EntryRecord) {
    errorMessage = nil
    noticeMessage = nil
    pendingDelete = entry
  }
  func setConfirmationPresented(_ presented: Bool) { if !presented { pendingDelete = nil } }
  func setAlertPresented(_ presented: Bool) { if !presented { errorMessage = nil } }
  func setNoticePresented(_ presented: Bool) { if !presented { noticeMessage = nil } }
  func confirm() {
    guard let pendingDelete else { return }
    do {
      let outcome = try store.delete(pendingDelete, imageStore: imageStore)
      if outcome == .recordDeletedPhotoCleanupPending {
        noticeMessage = "The journal entry was deleted and its photo is no longer shown. Protected local photo cleanup is still pending and will be retried on a later app launch."
      }
    }
    catch { errorMessage = error.localizedDescription }
    self.pendingDelete = nil
  }
  func setMarked(_ marked: Bool, for entry: EntryRecord) {
    do { try store.setDiscussionMark(marked, for: entry) }
    catch { errorMessage = error.localizedDescription }
  }
  #if DEBUG
  func resetSyntheticDemoEntries(_ entries: [EntryRecord]) {
    do {
      for entry in entries where DemoDataPolicy.isSyntheticDemo(entry) {
        if try store.delete(entry, imageStore: imageStore) == .recordDeletedPhotoCleanupPending {
          noticeMessage = "Synthetic demo entries were deleted, but protected local photo cleanup is still pending and will be retried on a later app launch."
        }
      }
    }
    catch { errorMessage = error.localizedDescription }
  }
  #endif
}

private enum JournalFilter: String, CaseIterable, Identifiable { case all, marked; var id: String { rawValue } }

struct HistoryView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \EntryRecord.capturedAt, order: .reverse) private var entries: [EntryRecord]
  @Query(sort: \DailyCompletionRecord.dayStart, order: .reverse) private var completions: [DailyCompletionRecord]
  @StateObject private var deletion: HistoryDeletionCoordinator
  @State private var filter: JournalFilter = .all
  #if DEBUG
  @State private var showResetDemoConfirmation = false
  #endif
  @State private var path: [UUID] = []
  @State private var helpRoute: GIJournalHelpRoute?
  @State private var showJournalExport = false
  @Binding private var requestedEntryID: UUID?
  private let store: EntryStoring

  @MainActor init(store: EntryStoring, requestedEntryID: Binding<UUID?> = .constant(nil)) {
    self.store = store
    _deletion = StateObject(wrappedValue: HistoryDeletionCoordinator(store: store, imageStore: ImageStore()))
    _requestedEntryID = requestedEntryID
  }

  private var displayedEntries: [EntryRecord] { filter == .all ? entries : entries.filter(\.isMarkedForDiscussion) }
  private var journalDays: [(Date, [EntryRecord])] {
    let calendar = Calendar.current
    let calculator = TreatmentResponseCalculator(calendar: calendar, timeZone: calendar.timeZone)
    var grouped = Dictionary(grouping: displayedEntries) { calendar.startOfDay(for: $0.capturedAt) }
    if filter == .all {
      for marker in completions where marker.answer == .noBowelMovement {
        let day = calculator.localDayStart(forDayKey: marker.dayKey) ?? calendar.startOfDay(for: marker.dayStart)
        grouped[day, default: []] += []
      }
    }
    return grouped
      .sorted { $0.key > $1.key }
      .map { ($0.key, $0.value.sorted { $0.capturedAt > $1.capturedAt }) }
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
          HStack(alignment: .firstTextBaseline) {
            Text("Journal").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Spacer()
            GIJournalHelpButton(route: .discussionMark, routeToPresent: $helpRoute)
          }
          Text("You choose which entries to mark. GI Journal does not determine which entries are medically concerning.")
            .font(.footnote).foregroundStyle(GIJournalTheme.secondaryText)
          Picker("Entries to show", selection: $filter) {
            Text("All").tag(JournalFilter.all)
            Text("Marked").tag(JournalFilter.marked)
          }
          .pickerStyle(.segmented)
          .accessibilityLabel("Journal filter")

          if journalDays.isEmpty {
            ContentUnavailableView(
              filter == .marked ? "No marked entries" : "No journal entries yet",
              systemImage: filter == .marked ? "bookmark" : "list.bullet",
              description: Text(filter == .marked ? "Mark an entry when you want to find it later or include it in a focused PDF." : "Add a journal entry, or record a day with no bowel movement.")
            )
            .frame(maxWidth: .infinity, minHeight: 300)
            .accessibilityIdentifier(filter == .marked ? "markedEmptyState" : "journalEmptyState")
          } else {
            ForEach(journalDays, id: \.0) { day, dayEntries in
              JournalDaySection(
                day: day,
                entries: dayEntries,
                completion: completion(for: day),
                deletion: deletion,
                path: $path
              )
            }
          }
        }
        .padding(GIJournalTheme.pageInset)
        .padding(.bottom, 28)
      }
      .background(GIJournalTheme.canvas)
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: UUID.self) { entryID in
        if let entry = entries.first(where: { $0.id == entryID }) {
          EntryDetailView(entry: entry, store: store, deletion: deletion)
        }
        else { ContentUnavailableView("Journal entry unavailable", systemImage: "exclamationmark.triangle") }
      }
      .task { openRequestedEntryIfAvailable() }
      .onChange(of: requestedEntryID) { _, _ in openRequestedEntryIfAvailable() }
      .onChange(of: entries.map(\.id)) { _, _ in openRequestedEntryIfAvailable() }
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Export PDF", systemImage: "square.and.arrow.up") { showJournalExport = true }
            .accessibilityHint("Opens journal PDF export")
          Button("Help & About", systemImage: "questionmark.circle") { helpRoute = .helpAbout }
            .accessibilityLabel("Help and About")
        }
        #if DEBUG
        if developerToolsVisible, entries.contains(where: DemoDataPolicy.isSyntheticDemo) {
          ToolbarItem(placement: .topBarLeading) { Button("Reset Demo") { showResetDemoConfirmation = true }.accessibilityIdentifier("resetDemo") }
        }
        #endif
      }
      #if DEBUG
      .confirmationDialog("Remove synthetic demo entries?", isPresented: $showResetDemoConfirmation, titleVisibility: .visible) {
        Button("Reset Demo", role: .destructive) { deletion.resetSyntheticDemoEntries(entries) }
        Button("Cancel", role: .cancel) {}
      } message: { Text("Only bundled synthetic demo entries will be removed.") }
      #endif
      .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deletion.pendingDelete != nil }, set: deletion.setConfirmationPresented), titleVisibility: .visible) {
        Button("Delete", role: .destructive) { deletion.confirm() }
        Button("Cancel", role: .cancel) {}
      } message: { Text("This removes the entry and its stored photo.") }
      .alert("Could not update journal", isPresented: Binding(get: { deletion.errorMessage != nil }, set: deletion.setAlertPresented)) {
        Button("OK", role: .cancel) {}
      } message: { Text(deletion.errorMessage ?? "") }
      .alert("Entry deleted", isPresented: Binding(get: { deletion.noticeMessage != nil }, set: deletion.setNoticePresented)) {
        Button("OK", role: .cancel) {}
      } message: { Text(deletion.noticeMessage ?? "") }
    }
    .sheet(item: $helpRoute) { GIJournalHelpSheet(route: $0) }
    .sheet(isPresented: $showJournalExport) {
      JournalExportSheet(entries: entries, completions: completions, treatmentEvents: [])
    }
  }

  private func completion(for day: Date) -> DailyCompletionRecord? {
    let calculator = TreatmentResponseCalculator()
    let key = calculator.dayKey(for: day)
    return completions.first { $0.dayKey == key }
  }
  private func openRequestedEntryIfAvailable() {
    guard let entryID = requestedEntryID, entries.contains(where: { $0.id == entryID }) else { return }
    path = [entryID]; requestedEntryID = nil
  }
}

private struct JournalDaySection: View {
  let day: Date
  let entries: [EntryRecord]
  let completion: DailyCompletionRecord?
  @ObservedObject var deletion: HistoryDeletionCoordinator
  @Binding var path: [UUID]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
          .font(.headline)
        Spacer()
      }
      if completion?.answer == .noBowelMovement {
        Label("No bowel movement recorded", systemImage: "calendar.badge.minus")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(GIJournalTheme.primary)
          .accessibilityIdentifier("noBowelMovementJournalMarker")
      }
      if !entries.isEmpty {
        VStack(spacing: 0) {
          ForEach(entries) { entry in
            HStack(spacing: 10) {
              NavigationLink(value: entry.id) { JournalRow(entry: entry) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("journalEntry")
              Button {
                deletion.setMarked(!entry.isMarkedForDiscussion, for: entry)
              } label: {
                Image(systemName: entry.isMarkedForDiscussion ? "bookmark.fill" : "bookmark")
                  .font(.body.weight(.semibold))
              }
              .frame(width: 44, height: 44)
              .buttonStyle(.plain)
              .foregroundStyle(entry.isMarkedForDiscussion ? GIJournalTheme.discussion : GIJournalTheme.secondaryText)
              .accessibilityLabel(entry.isMarkedForDiscussion ? "Remove discussion mark" : "Mark for discussion")
            }
            if entry.id != entries.last?.id { Divider().padding(.leading, 76) }
          }
        }
        .giJournalCard(padding: 4)
      }
    }
  }
}

private struct JournalRow: View {
  let entry: EntryRecord
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) { rowHeader; summary }
      } else {
        HStack(spacing: 12) { thumbnail; VStack(alignment: .leading, spacing: 5) { rowHeader; summary }; Spacer(minLength: 0) }
      }
    }
    .padding(12)
    .contentShape(Rectangle())
  }
  private var rowHeader: some View {
    HStack(spacing: 8) {
      if dynamicTypeSize.isAccessibilitySize { thumbnail }
      Text(entry.capturedAt, format: .dateTime.hour().minute()).font(.headline)
      if entry.isMarkedForDiscussion { GIJournalBadge(title: "Marked for discussion", symbol: "bookmark.fill", foreground: GIJournalTheme.discussion, background: GIJournalTheme.discussionSurface) }
      Spacer(minLength: 0)
    }
  }
  private var summary: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(entry.confirmedStoolForm.displayName.replacingOccurrences(of: " - ", with: " — "))
        .font(.subheadline.weight(.medium)).foregroundStyle(GIJournalTheme.text).fixedSize(horizontal: false, vertical: true)
      Text(contextSummary).font(.caption).foregroundStyle(GIJournalTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
    }
  }
  private var contextSummary: String {
    var items = ["Pain: \(entry.painScore.map(String.init) ?? "Not recorded")/10", entry.urgencyLevel?.displayName ?? "Urgency not recorded"]
    if entry.mixedFormAnswer == .yes { items.append("Mixed form") }
    return items.joined(separator: " · ")
  }
  @ViewBuilder private var thumbnail: some View {
    if JournalPhotoPresentation.canDisplay(entry),
      let filename = entry.imageFilename,
      let url = ImageStore().imageURL(filename: filename),
      let image = UIImage(contentsOfFile: url.path) {
      Image(uiImage: image).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("Photo attached")
    } else {
      RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GIJournalTheme.tintedSurface).frame(width: 52, height: 52).overlay(Image(systemName: "photo").foregroundStyle(GIJournalTheme.secondaryText))
        .accessibilityLabel(JournalPhotoPresentation.unavailableTitle(for: entry))
    }
  }
}

struct EntryDetailView: View {
  @Bindable var entry: EntryRecord
  let store: EntryStoring
  @ObservedObject var deletion: HistoryDeletionCoordinator
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var showDeleteConfirmation = false
  @State private var showEditor = false
  @State private var helpRoute: GIJournalHelpRoute?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(entry.capturedAt, format: .dateTime.month(.wide).day().year()).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
        Text(entry.capturedAt, format: .dateTime.hour().minute()).font(.headline).foregroundStyle(GIJournalTheme.secondaryText)
        photo
        VStack(alignment: .leading, spacing: 12) {
          Text("Journal entry").font(.title3.bold())
          detailRow("Stool type", entry.confirmedStoolForm.displayName.replacingOccurrences(of: " - ", with: " — "))
          detailRow("Consistency", humanReadableHistoryValue(entry.confirmedConsistency.rawValue))
          if let color = entry.confirmedEntrySnapshot?
            .personConfirmedApparentColor ?? entry.observation?.apparentColor
          {
            detailRow("Apparent color", humanReadableHistoryValue(color))
          }
          if let form = entry.confirmedEntrySnapshot?.personConfirmedForm {
            detailRow("Form", humanReadableHistoryValue(form))
          }
          detailRow("Mixed form", HistoryPresentation.triState(entry.mixedFormAnswer))
          if let subject = entry.confirmedEntrySnapshot?.personConfirmedStoolPresence {
            detailRow(entry.savedAnalysisSource == .manual
              ? "Entry subject" : "Photo subject", subject == .stool
              ? "Bowel movement"
              : subject == .nonStool ? "Different subject" : "Not sure")
          }
          if entry.imageFilename != nil {
            detailRow(
              entry.analysisPipelineVersion
                == "gi-v1-direct-sanitized-jpeg-constrained-v1"
                ? "Person confirmed the photo clearly showed the bowel movement"
                : "Photo clearly showed it",
              entry.confirmedPhotoUsable == true
                ? "Yes" : entry.confirmedPhotoUsable == false ? "No" : "Not recorded"
            )
            if let reason = entry.confirmedEntrySnapshot?
              .personConfirmedRetakeReason
            {
              detailRow("Retake recommendation", reason.displayName)
            }
          }
        }.giJournalCard()
        GIJournalSuggestionDisclosure(source: entry.savedAnalysisSource?.rawValue, helpRoute: $helpRoute)
        VStack(alignment: .leading, spacing: 12) {
          Text("Details you noticed").font(.title3.bold())
          detailRow("Pain", entry.painScore.map { "\($0) out of 10" } ?? "Not recorded")
          detailRow("Urgency", entry.urgencyLevel?.displayName ?? "Not recorded")
          detailRow("Possible red/blood-like appearance", HistoryPresentation.reportedValue(entry.redBlood))
          if entry.confirmedEntrySnapshot?.typedFieldProvenance[.blackAppearance]
            != nil
          {
            detailRow(
              "Possible unusually black appearance",
              HistoryPresentation.reportedValue(
                entry.blackAppearanceAnswer?.rawValue
              )
            )
            detailRow(
              "Possible tar-like appearance",
              HistoryPresentation.reportedValue(entry.blackTarry)
            )
          } else {
            detailRow("Possible black/tar-like appearance", HistoryPresentation.reportedValue(entry.blackTarry))
          }
          if let answer = entry.strainingOrIncompleteAnswer { detailRow("Straining or incomplete emptying", answer.displayName) }
          if let answer = entry.leakageOrAccidentAnswer { detailRow("Leakage or loss of control", answer.displayName) }
          detailRow("Note", HistoryPresentation.reportedValue(DemoDataPolicy.presentedNote(for: entry)))
        }.giJournalCard()
        if safetyGuidance == .contactClinician {
          Text(SafetyRules.message).giJournalCard()
        } else if safetyGuidance == .uncertain {
          Text(SafetyRules.uncertainMessage).giJournalCard()
        }
        Text("This entry records observations and is not a diagnosis or treatment recommendation.")
          .font(.footnote).foregroundStyle(GIJournalTheme.secondaryText)
      }
      .padding(GIJournalTheme.pageInset).padding(.bottom, 28)
    }
    .background(GIJournalTheme.canvas)
    .navigationTitle("Journal entry")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("entryDetail")
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Edit entry", systemImage: "pencil") { showEditor = true }
          .accessibilityIdentifier("editEntry")
        Button(entry.isMarkedForDiscussion ? "Remove discussion mark" : "Mark for discussion", systemImage: entry.isMarkedForDiscussion ? "bookmark.fill" : "bookmark") { deletion.setMarked(!entry.isMarkedForDiscussion, for: entry) }
          .tint(entry.isMarkedForDiscussion ? GIJournalTheme.discussion : GIJournalTheme.primary)
        Button("Delete entry", systemImage: "trash", role: .destructive) { showDeleteConfirmation = true }.accessibilityIdentifier("deleteEntry")
      }
    }
    .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
      Button("Delete", role: .destructive) { deletion.request(entry); deletion.confirm(); if deletion.errorMessage == nil { dismiss() } }
      Button("Cancel", role: .cancel) {}
    } message: { Text("This removes the entry and its stored photo.") }
    .sheet(item: $helpRoute) { GIJournalHelpSheet(route: $0) }
    .sheet(isPresented: $showEditor) { EntryEditorSheet(entry: entry, store: store) }
  }

  private var safetyGuidance: SafetyGuidance {
    SafetyRules.guidance(
      redBlood: entry.redBlood.flatMap(SymptomFlag.init(rawValue:)),
      blackTarry: entry.blackTarry.flatMap(SymptomFlag.init(rawValue:))
    )
  }

  @ViewBuilder private var photo: some View {
    if JournalPhotoPresentation.canDisplay(entry),
      let filename = entry.imageFilename,
      let url = ImageStore().imageURL(filename: filename),
      let image = UIImage(contentsOfFile: url.path) {
      Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 380).background(GIJournalTheme.surface).clipShape(RoundedRectangle(cornerRadius: GIJournalTheme.cornerRadius, style: .continuous))
        .accessibilityLabel("Photo attached to this journal entry")
    } else {
      ContentUnavailableView(JournalPhotoPresentation.unavailableTitle(for: entry), systemImage: "photo").frame(maxWidth: .infinity, minHeight: 180).giJournalCard()
    }
  }
  private func detailRow(_ label: String, _ value: String) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 4) { Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(GIJournalTheme.secondaryText); Text(value).fixedSize(horizontal: false, vertical: true) } }
      else { LabeledContent(label) { Text(value).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true) } }
    }
  }
}

enum EntryEditorDismissPolicy {
  static func disablesInteractiveDismiss(
    persistenceReady: Bool,
    hasUnsavedEdit: Bool,
    persistenceBlocked: Bool,
    isSaving: Bool,
    saveCommittedCleanupPending: Bool
  ) -> Bool {
    !persistenceReady || hasUnsavedEdit || persistenceBlocked
      || isSaving || saveCommittedCleanupPending
  }
}

private struct EntryEditorSheet: View {
  let entry: EntryRecord
  let store: EntryStoring
  private let editDraftStore: EntryEditDraftStore
  private let baselineInput: EntryEditInput
  private let baselineFingerprint: String?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var draft: EntryEditInput
  @State private var helpRoute: GIJournalHelpRoute?
  @State private var errorMessage: String?
  @State private var isSaving = false
  @State private var draftPersistenceReady = false
  @State private var draftPersistenceBlocked = false
  @State private var saveCommittedCleanupPending = false

  @MainActor init(
    entry: EntryRecord,
    store: EntryStoring,
    editDraftStore: EntryEditDraftStore? = nil
  ) {
    self.entry = entry
    self.store = store
    self.editDraftStore = editDraftStore ?? EntryEditDraftStore()
    let input = EntryEditInput(entry: entry)
    self.baselineInput = input
    self.baselineFingerprint = try? EntryRecordFingerprint.make(for: entry)
    _draft = State(initialValue: input)
  }

  private var hasUnsavedEdit: Bool { draft != baselineInput }
  private var isSubjectFirstCandidateEntry: Bool {
    entry.analysisPipelineVersion == "gi-v1-direct-sanitized-jpeg-constrained-v1"
  }
  private var isFullPrefillEntry: Bool {
    entry.confirmedEntrySnapshot?.typedFieldProvenance[.stoolPresence] != nil
      && entry.confirmedEntrySnapshot?.typedFieldProvenance[.form] != nil
  }
  private var hasIndependentBlackAppearance: Bool {
    entry.confirmedEntrySnapshot?.typedFieldProvenance[.blackAppearance] != nil
  }
  private var independentCandidateAnswersComplete: Bool {
    !isSubjectFirstCandidateEntry
      || (draft.redBlood != nil && draft.blackTarry != nil)
  }
  private var fullPrefillEditIsConsistent: Bool {
    guard isFullPrefillEntry else { return true }
    let value = draft.normalizedForPersistence()
    guard let subject = value.stoolPresence,
      let form = value.form,
      let mixed = value.mixedForm,
      let apparentColor = value.apparentColor,
      value.redBlood != nil,
      (!hasIndependentBlackAppearance || value.blackAppearance != nil),
      value.blackTarry != nil
    else { return false }
    if entry.imageFilename == nil {
      guard value.confirmedPhotoUsable == nil,
        value.retakeReason == nil
      else { return false }
    } else {
      guard let usable = value.confirmedPhotoUsable,
        usable ? value.retakeReason == nil : value.retakeReason != nil
      else { return false }
    }
    if value.confirmedPhotoUsable == false {
      return value.confirmedBristolType == nil
        && form == "unable_to_assess"
        && mixed == .unsure
        && apparentColor == "unable_to_assess"
        && value.redBlood == .unsure
        && (!hasIndependentBlackAppearance
          || value.blackAppearance == .unsure)
        && value.blackTarry == .unsure
    }
    if subject != .stool {
      let morphologyAbstains = value.confirmedBristolType == nil
        && form == "unable_to_assess"
        && mixed == .unsure
      if hasIndependentBlackAppearance { return morphologyAbstains }
      return morphologyAbstains
        && apparentColor == "unable_to_assess"
        && value.redBlood == .unsure
        && value.blackTarry == .unsure
    }
    switch mixed {
    case .no:
      guard let type = value.confirmedBristolType else { return false }
      return BristolFormContract.expectedForm(for: type) == form
    case .yes:
      return value.confirmedBristolType == nil && form == "mixed"
    case .unsure:
      return value.confirmedBristolType == nil
        && form == "unable_to_assess"
    }
  }

  private var clinicalErrors: [ClinicalValidationError] {
    ClinicalValidation.validate(
      confirmedBristolType: draft.confirmedBristolType,
      painScore: draft.painScore,
      mixedForm: draft.mixedForm,
      strainingOrIncomplete: draft.strainingOrIncomplete,
      leakageOrAccident: draft.leakageOrAccident
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          DatePicker("Date and time", selection: $draft.capturedAt)
            .giJournalCard()

          VStack(alignment: .leading, spacing: 14) {
            Text("Entry details").font(.title2.bold())
            if JournalPhotoPresentation.canDisplay(entry),
              !isSubjectFirstCandidateEntry
            {
              GIJournalBooleanRows(
                title: "Was this photo clear enough to use as a reference?",
                selection: Binding(
                  get: { draft.confirmedPhotoUsable },
                  set: { updatePhotoUsability($0) }
                )
              )
            }
            if isFullPrefillEntry, draft.confirmedPhotoUsable == false {
              Picker("Retake recommendation", selection: Binding(
                get: { draft.retakeReason ?? .other },
                set: { draft.retakeReason = $0 }
              )) {
                ForEach(Self.technicalRetakeReasons, id: \.self) { reason in
                  Text(reason.displayName).tag(reason)
                }
              }
              .accessibilityIdentifier("editRetakeReason")
            }
            if isFullPrefillEntry {
              Picker(entry.savedAnalysisSource == .manual
                ? "Entry subject" : "Photo subject", selection: Binding(
                get: { draft.stoolPresence ?? .uncertain },
                set: { updateStoolPresence($0) }
              )) {
                Text("Bowel movement").tag(StoolPresence.stool)
                Text("Different subject").tag(StoolPresence.nonStool)
                Text("Not sure").tag(StoolPresence.uncertain)
              }
              .accessibilityIdentifier("editStoolPresence")
            }
            if draft.apparentColor != nil, draft.confirmedPhotoUsable != false {
              Picker("Apparent color", selection: Binding(
                get: { draft.apparentColor ?? "unable_to_assess" },
                set: { draft.apparentColor = $0 }
              )) {
                ForEach(Self.apparentColors, id: \.self) { value in
                  Text(Self.label(value)).tag(value)
                }
              }
              .accessibilityIdentifier("editApparentColor")
            }
            GIJournalStoolTypePicker(
              selection: Binding(
                get: { draft.confirmedBristolType },
                set: { updateBristolType($0) }
              ),
              helpRoute: $helpRoute
            )
            if isFullPrefillEntry {
              Picker("Form", selection: Binding(
                get: { draft.form ?? "unable_to_assess" },
                set: { updateForm($0) }
              )) {
                ForEach(Self.forms, id: \.self) { form in
                  Text(Self.label(form)).tag(form)
                }
              }
              .accessibilityIdentifier("editForm")
            }
            GIJournalClinicalTriStateRows(
              title: "Did this bowel movement include more than one clearly different stool type?",
              accessibilityIdentifierPrefix: "editMixedForm",
              selection: Binding(
                get: { draft.mixedForm },
                set: { updateMixedForm($0) }
              )
            )
          }
          .giJournalCard()

          VStack(alignment: .leading, spacing: 16) {
            Text("Details you noticed").font(.title2.bold())
            GIJournalUrgencyRows(selection: $draft.urgency, helpRoute: $helpRoute)
            GIJournalPainControl(score: $draft.painScore)
            symptomChoices("Possible red/blood-like appearance", value: $draft.redBlood)
            Text("This records an appearance only and does not confirm blood or bleeding.")
              .font(.footnote)
              .foregroundStyle(GIJournalTheme.secondaryText)
            if hasIndependentBlackAppearance {
              symptomChoices(
                "Possible unusually black appearance",
                value: $draft.blackAppearance
              )
              Text("This records visible color only and does not confirm melena or a diagnosis.")
                .font(.footnote)
                .foregroundStyle(GIJournalTheme.secondaryText)
              symptomChoices(
                "Possible tar-like appearance",
                value: $draft.blackTarry
              )
              Text("This records a glossy, smeared, coating-like, or tar-like look only; it does not confirm physical stickiness or melena.")
                .font(.footnote)
                .foregroundStyle(GIJournalTheme.secondaryText)
            } else {
              symptomChoices("Possible black/tar-like appearance", value: $draft.blackTarry)
              Text("This records visible appearance only; it does not establish material, texture, or a medical finding.")
                .font(.footnote)
                .foregroundStyle(GIJournalTheme.secondaryText)
            }

            switch ClinicalValidation.conditionalQuestion(for: draft.confirmedBristolType) {
            case .strainingOrIncomplete:
              GIJournalClinicalTriStateRows(
                title: "Did you strain a lot or still feel you needed to go?",
                accessibilityIdentifierPrefix: "editStrainingOrIncomplete",
                selection: $draft.strainingOrIncomplete
              )
            case .leakageOrAccident:
              GIJournalClinicalTriStateRows(
                title: "Was there leakage or loss of control?",
                accessibilityIdentifierPrefix: "editLeakageOrAccident",
                selection: $draft.leakageOrAccident
              )
            case nil:
              EmptyView()
            }

            TextField(
              "Anything else you want to remember? (optional)",
              text: Binding(get: { draft.note ?? "" }, set: { draft.note = $0 }),
              axis: .vertical
            )
            .lineLimit(3...6)
            .accessibilityIdentifier("editNoteField")
            .onChange(of: draft.note) { _, value in
              if let value, value.count > 500 { draft.note = String(value.prefix(500)) }
            }
          }
          .giJournalCard()
        }
        .padding(GIJournalTheme.pageInset)
        .padding(.bottom, 24)
      }
      .disabled(!draftPersistenceReady || saveCommittedCleanupPending)
      .background(GIJournalTheme.canvas)
      .navigationTitle("Edit entry")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(saveCommittedCleanupPending ? "Close" : "Cancel") { cancel() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isSaving ? "Saving…" : "Save changes") { save() }
            .disabled(
              isSaving || !draftPersistenceReady || draftPersistenceBlocked
                || saveCommittedCleanupPending || !hasUnsavedEdit
                || !clinicalErrors.isEmpty || !independentCandidateAnswersComplete
                || !fullPrefillEditIsConsistent
            )
            .accessibilityIdentifier("saveEntryChanges")
        }
      }
      .interactiveDismissDisabled(
        EntryEditorDismissPolicy.disablesInteractiveDismiss(
          persistenceReady: draftPersistenceReady,
          hasUnsavedEdit: hasUnsavedEdit,
          persistenceBlocked: draftPersistenceBlocked,
          isSaving: isSaving,
          saveCommittedCleanupPending: saveCommittedCleanupPending
        )
      )
      .task { restoreUnfinishedEdit() }
      .onChange(of: draft) { _, value in persistUnfinishedEdit(value) }
      .sheet(item: $helpRoute) { GIJournalHelpSheet(route: $0) }
      .alert("Could not finish editing", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private func updateBristolType(_ type: Int?) {
    draft.confirmedBristolType = type
    if isFullPrefillEntry {
      if let type, let form = BristolFormContract.expectedForm(for: type) {
        draft.form = form
        draft.mixedForm = .no
      } else {
        draft.form = "unable_to_assess"
        draft.mixedForm = .unsure
      }
    }
    switch ClinicalValidation.conditionalQuestion(for: type) {
    case .strainingOrIncomplete: draft.leakageOrAccident = nil
    case .leakageOrAccident: draft.strainingOrIncomplete = nil
    case nil:
      draft.strainingOrIncomplete = nil
      draft.leakageOrAccident = nil
    }
  }

  private func updateStoolPresence(_ presence: StoolPresence) {
    draft.stoolPresence = presence
    if presence != .stool {
      applyDependentAbstention(clearAppearanceFields: false)
    }
  }

  private func updateForm(_ form: String) {
    guard Self.forms.contains(form) else { return }
    draft.form = form
    switch form {
    case "mixed":
      draft.confirmedBristolType = nil
      draft.mixedForm = .yes
    case "unable_to_assess":
      draft.confirmedBristolType = nil
      draft.mixedForm = .unsure
    default:
      draft.confirmedBristolType = Self.bristolType(for: form)
      draft.mixedForm = .no
    }
  }

  private func updateMixedForm(_ answer: ClinicalTriState?) {
    draft.mixedForm = answer
    guard isFullPrefillEntry else { return }
    switch answer {
    case .yes:
      draft.confirmedBristolType = nil
      draft.form = "mixed"
    case .unsure:
      draft.confirmedBristolType = nil
      draft.form = "unable_to_assess"
    case .no:
      if let type = draft.confirmedBristolType {
        draft.form = BristolFormContract.expectedForm(for: type)
      }
    case nil:
      break
    }
  }

  private func applyDependentAbstention(
    clearAppearanceFields: Bool
  ) {
    draft.confirmedBristolType = nil
    draft.form = "unable_to_assess"
    draft.mixedForm = .unsure
    if clearAppearanceFields || !hasIndependentBlackAppearance {
      draft.apparentColor = "unable_to_assess"
      draft.redBlood = .unsure
      if hasIndependentBlackAppearance { draft.blackAppearance = .unsure }
      draft.blackTarry = .unsure
    }
    draft.strainingOrIncomplete = nil
    draft.leakageOrAccident = nil
  }

  private func updatePhotoUsability(_ usable: Bool?) {
    draft.confirmedPhotoUsable = usable
    if usable == false {
      draft.retakeReason = draft.retakeReason ?? .other
      draft.apparentColor = "unable_to_assess"
      if isFullPrefillEntry {
        draft.stoolPresence = .uncertain
        applyDependentAbstention(clearAppearanceFields: true)
      }
    } else {
      draft.retakeReason = nil
    }
  }

  private func save() {
    guard !isSaving, draftPersistenceReady, !draftPersistenceBlocked,
      hasUnsavedEdit, clinicalErrors.isEmpty,
      fullPrefillEditIsConsistent,
      let baselineFingerprint
    else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let updateDate = Date()
      let expectedPostSaveFingerprint = try store.expectedUpdateFingerprint(
        for: entry,
        input: draft,
        baselineFingerprint: baselineFingerprint,
        at: updateDate
      )
      try editDraftStore.save(
        input: draft,
        entryID: entry.id,
        baselineRecordFingerprint: baselineFingerprint,
        pendingSave: true,
        expectedPostSaveRecordFingerprint: expectedPostSaveFingerprint
      )
      try store.update(
        entry,
        with: draft,
        baselineFingerprint: baselineFingerprint,
        at: updateDate
      )
      if editDraftStore.remove(entryID: entry.id) {
        dismiss()
      } else {
        saveCommittedCleanupPending = true
        errorMessage = EntryEditDraftError.cleanupFailed.localizedDescription
      }
    } catch {
      // A failed SwiftData transaction leaves the row at its baseline. Making
      // the marker non-pending is best effort; restart resolution independently
      // proves the same fact from the full-record fingerprint.
      try? editDraftStore.save(
        input: draft,
        entryID: entry.id,
        baselineRecordFingerprint: baselineFingerprint,
        pendingSave: false
      )
      if error as? GITimelineError == .entryTransactionConflict {
        draftPersistenceBlocked = true
      }
      errorMessage = error.localizedDescription
    }
  }

  private func restoreUnfinishedEdit() {
    guard !draftPersistenceReady else { return }
    guard baselineFingerprint != nil else {
      draftPersistenceBlocked = true
      draftPersistenceReady = true
      errorMessage = EntryEditDraftError.invalidContents.localizedDescription
      return
    }
    switch editDraftStore.resume(for: entry) {
    case .none:
      draftPersistenceReady = true
    case .resumed(let snapshot):
      draft = snapshot.input
      draftPersistenceReady = true
    case .committedCleanupFinished:
      // The prior process saved this exact edit; do not present its old form
      // as an unsaved change or write another update timestamp.
      dismiss()
    case .committedCleanupPending(let message):
      saveCommittedCleanupPending = true
      draftPersistenceReady = true
      errorMessage = message
    case .temporarilyUnavailable(let message),
      .unavailable(let message), .conflict(let message):
      draftPersistenceBlocked = true
      draftPersistenceReady = true
      errorMessage = message
    }
  }

  private func persistUnfinishedEdit(_ value: EntryEditInput) {
    guard draftPersistenceReady, !saveCommittedCleanupPending,
      let baselineFingerprint
    else { return }
    do {
      if value == baselineInput {
        guard editDraftStore.remove(entryID: entry.id) else {
          throw EntryEditDraftError.cleanupFailed
        }
      } else {
        try editDraftStore.save(
          input: value,
          entryID: entry.id,
          baselineRecordFingerprint: baselineFingerprint,
          pendingSave: false
        )
      }
      draftPersistenceBlocked = false
    } catch {
      draftPersistenceBlocked = true
      errorMessage = error.localizedDescription
    }
  }

  private func cancel() {
    guard !isSaving else { return }
    if !editDraftStore.removeBeforeDismiss(entryID: entry.id, dismiss: { dismiss() }) {
      errorMessage = EntryEditDraftError.cleanupFailed.localizedDescription
    }
  }

  private func symptomChoices(_ title: String, value: Binding<SymptomFlag?>) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.headline)
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 8) { symptomButtons(value) }
      } else {
        HStack(spacing: 8) { symptomButtons(value) }
      }
    }
  }

  @ViewBuilder private func symptomButtons(_ value: Binding<SymptomFlag?>) -> some View {
    ForEach(SymptomFlag.allCases, id: \.self) { option in
      Button {
        value.wrappedValue = option
      } label: {
        HStack(spacing: 7) {
          Image(systemName: value.wrappedValue == option ? "checkmark.circle.fill" : "circle")
          Text(option == .unsure ? "Not sure" : option.rawValue.capitalized)
          Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 10)
        .background(value.wrappedValue == option ? GIJournalTheme.tintedSurface : GIJournalTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(value.wrappedValue == option ? GIJournalTheme.primary : GIJournalTheme.border, lineWidth: 1) }
      }
      .buttonStyle(.plain)
      .foregroundStyle(value.wrappedValue == option ? GIJournalTheme.primary : GIJournalTheme.text)
      .accessibilityValue(value.wrappedValue == option ? "Selected" : "Not selected")
    }
  }

  private static let apparentColors = [
    "brown", "light_brown", "dark_brown", "green", "yellow", "orange",
    "red_appearing", "black_appearing", "pale_or_clay_appearing", "mixed", "unable_to_assess",
  ]
  private static let technicalRetakeReasons: [PhotoRetakeReason] = [
    .tooDark, .blurred, .obstructed, .tooFar, .glare, .other,
  ]
  private static let forms = [
    "hard_lumps", "lumpy_formed", "cracked_formed", "smooth_formed",
    "soft_blobs", "mushy", "watery", "mixed", "unable_to_assess",
  ]
  private static func bristolType(for form: String) -> Int? {
    switch form {
    case "hard_lumps": return 1
    case "lumpy_formed": return 2
    case "cracked_formed": return 3
    case "smooth_formed": return 4
    case "soft_blobs": return 5
    case "mushy": return 6
    case "watery": return 7
    default: return nil
    }
  }
  private static func label(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
  }
}

private func humanReadableHistoryValue(_ value: String) -> String { value.replacingOccurrences(of: "_", with: " ").capitalized }
