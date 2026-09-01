import Foundation
import SwiftUI
import SwiftData
import GITimelineCore

// Retained only as source-level migration context. The public app does not
// compile or expose the retired treatment-comparison experience.
#if GI_JOURNAL_LEGACY_TREATMENT_UI

/// A presentation-only projection. The clinical layer supplies these already
/// calculated strings; this view must not infer treatment effects itself.
struct GIJournalProgressPresentation: Equatable {
  struct Window: Equatable, Identifiable {
    let id: String
    let title: String
    let dateRange: String
    let recordedEntries: String
    let completeness: String
    let frequency: String
    let details: [String]

    init(id: String, title: String, dateRange: String, recordedEntries: String, completeness: String, frequency: String, details: [String] = []) {
      self.id = id
      self.title = title
      self.dateRange = dateRange
      self.recordedEntries = recordedEntries
      self.completeness = completeness
      self.frequency = frequency
      self.details = details
    }
  }

  let treatmentName: String
  let treatmentDate: String
  let transitionSummary: String
  let before: Window
  let after: Window
  let dataQuality: String

  static func detailLines(for summary: TreatmentWindowSummary) -> [String] {
    let consistencies = summary.consistencies
    return [
      "Confirmed Bristol groups (n=\(summary.bristolGroups.denominator)): Type 1–2 \(percentage(summary.bristolGroups.type1To2, of: summary.bristolGroups.denominator)) · Type 3–5 \(percentage(summary.bristolGroups.type3To5, of: summary.bristolGroups.denominator)) · Type 6–7 \(percentage(summary.bristolGroups.type6To7, of: summary.bristolGroups.denominator))",
      "Confirmed form counts (n=\(summary.bristolGroups.denominator)): hard \(consistencies.hard) · formed \(consistencies.formed) · soft \(consistencies.soft) · loose \(consistencies.loose) · watery \(consistencies.watery)",
      "Mixed form confirmed (reported separately): \(consistencies.mixedConfirmed)",
      "Median recorded pain: \(summary.medianPain.map { String(format: "%.1f", $0) } ?? "Not recorded") (n=\(summary.painDenominator))",
      "Severe urgency (could not wait): \(summary.severeUrgency.count) (n=\(summary.severeUrgency.denominator))",
      "Straining or incomplete emptying: yes \(summary.strainingYes.count) (n=\(summary.strainingYes.denominator) applicable answers)",
      "Leakage or accident: yes \(summary.leakageYes.count) (n=\(summary.leakageYes.denominator) applicable answers)",
      "Photos marked unclear: \(summary.unusablePhotoCount) · Original on-device photo suggestions changed during review: \(summary.bristolCorrectionCount) (uses locally retained suggestion provenance)",
      "Red blood: yes \(summary.redBloodYes.count), not sure \(summary.redBloodUnsure.count) (n=\(summary.redBloodYes.denominator)); black/tarry: yes \(summary.blackTarryYes.count), not sure \(summary.blackTarryUnsure.count) (n=\(summary.blackTarryYes.denominator))."
    ]
  }

  private static func percentage(_ count: Int, of total: Int) -> String {
    total == 0 ? "Not recorded" : "\(Int((Double(count) / Double(total) * 100).rounded()))%"
  }

  static func dateRange(for interval: LocalDayInterval, calendar: Calendar = .current) -> String {
    guard interval.totalDays > 0 else { return "No after days observed yet" }
    let rangeEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
    return "\(dateString(interval.start)) – \(dateString(rangeEnd))"
  }

  private static func dateString(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).day().year())
  }
}

private struct TreatmentEditorRoute: Identifiable, Equatable {
  enum Mode: Equatable {
    case add
    case edit(UUID)
  }

  let id = UUID()
  let mode: Mode
}

struct GIJournalProgressView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \EntryRecord.capturedAt, order: .forward) private var entries: [EntryRecord]
  @Query(sort: \DailyCompletionRecord.dayStart, order: .forward) private var completions: [DailyCompletionRecord]
  @Query(sort: \TreatmentEventRecord.effectiveDate, order: .reverse) private var treatments: [TreatmentEventRecord]
  var presentation: GIJournalProgressPresentation?
  @State private var helpRoute: GIJournalHelpRoute?
  @State private var selectedTreatmentID: UUID?
  @State private var treatmentEditorRoute: TreatmentEditorRoute?
  @State private var treatmentPendingDeletionID: UUID?
  @State private var showDeleteConfirmation = false
  @State private var deletionErrorMessage: String?
  @State private var unavailableTreatmentMessage: String?

  private var activePresentation: GIJournalProgressPresentation? {
    presentation ?? selectedTreatment.flatMap(makePresentation(for:))
  }
  private var selectedTreatment: TreatmentEventRecord? {
    if let selectedTreatmentID,
       let selected = treatments.first(where: { $0.id == selectedTreatmentID }) {
      return selected
    }
    return treatments.first
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Before and after a change")
              .font(.largeTitle.bold())
              .foregroundStyle(GIJournalTheme.text)
              .accessibilityAddTraits(.isHeader)
            Text("Compare what you recorded around one treatment change.")
              .foregroundStyle(GIJournalTheme.secondaryText)
            HStack {
              Spacer()
              GIJournalHelpButton(route: .comparison, routeToPresent: $helpRoute)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
          }

          if !treatments.isEmpty, presentation == nil {
            VStack(alignment: .leading, spacing: 12) {
              Picker("Treatment change", selection: Binding(get: { selectedTreatment?.id }, set: { selectedTreatmentID = $0 })) {
                ForEach(treatments, id: \.id) { treatment in
                  Text("\(treatment.kind?.displayName ?? "Treatment change"): \(treatment.name)").tag(treatment.id as UUID?)
                }
              }
              .pickerStyle(.navigationLink)

              if let selectedTreatment {
                HStack(spacing: 12) {
                  Button("Edit") {
                    treatmentEditorRoute = TreatmentEditorRoute(mode: .edit(selectedTreatment.id))
                  }
                  .buttonStyle(.bordered)
                  .frame(minHeight: 44)
                  .accessibilityLabel("Edit selected treatment change")
                  .accessibilityIdentifier("editSelectedTreatmentChange")

                  Button("Delete", role: .destructive) {
                    treatmentPendingDeletionID = selectedTreatment.id
                    showDeleteConfirmation = true
                  }
                  .buttonStyle(.bordered)
                  .frame(minHeight: 44)
                  .accessibilityLabel("Delete selected treatment change")
                  .accessibilityIdentifier("deleteSelectedTreatmentChange")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
              }
            }
            .giJournalCard()
          }

          if let presentation = activePresentation {
            VStack(alignment: .leading, spacing: 6) {
              Text("Treatment change: \(presentation.treatmentName) · \(presentation.treatmentDate)")
                .font(.subheadline.weight(.semibold))
              Text(presentation.transitionSummary)
                .font(.footnote)
            }
            .foregroundStyle(GIJournalTheme.secondaryText)
            .giJournalCard()

            VStack(spacing: 16) {
              progressCard(presentation.before)
              progressCard(presentation.after)
            }

            VStack(alignment: .leading, spacing: 8) {
              Text("Data quality").font(.headline)
              Text(presentation.dataQuality)
                .foregroundStyle(GIJournalTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .giJournalCard()

            Text("This journal summarizes user-recorded observations. It does not diagnose a condition, measure inflammation, recommend treatment, or replace clinician assessment.")
              .font(.footnote)
              .foregroundStyle(GIJournalTheme.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
          } else {
            ContentUnavailableView(
              "Add a treatment change to compare entries",
              systemImage: "chart.bar.xaxis",
              description: Text("A treatment change is a date marker that helps compare your journal before and after something changed. It does not track doses or tell you what treatment to use.")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
            Button("Add treatment change") {
              treatmentEditorRoute = TreatmentEditorRoute(mode: .add)
            }
              .buttonStyle(GIJournalPrimaryButtonStyle())
          }
        }
        .padding(GIJournalTheme.pageInset)
        .padding(.bottom, 28)
      }
      .background(GIJournalTheme.canvas)
      .navigationBarTitleDisplayMode(.inline)
    }
    .sheet(item: $helpRoute) { GIJournalHelpSheet(route: $0) }
    .sheet(item: $treatmentEditorRoute) { route in
      switch route.mode {
      case .add:
        GIJournalTreatmentEventSheet(context: modelContext)
      case .edit(let treatmentID):
        if let treatment = treatments.first(where: { $0.id == treatmentID }) {
          GIJournalTreatmentEventSheet(context: modelContext, treatmentEvent: treatment)
        } else {
          TreatmentEventUnavailableSheet()
        }
      }
    }
    .confirmationDialog(
      "Delete treatment change?",
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete treatment change", role: .destructive) { deletePendingTreatment() }
      Button("Cancel", role: .cancel) { treatmentPendingDeletionID = nil }
    } message: {
      Text("This permanently deletes the selected date marker. It does not delete journal entries.")
    }
    .alert(
      "Couldn’t delete treatment change",
      isPresented: Binding(
        get: { deletionErrorMessage != nil },
        set: { if !$0 { deletionErrorMessage = nil } }
      )
    ) {
      Button("OK") { deletionErrorMessage = nil }
    } message: {
      Text(deletionErrorMessage ?? "The treatment change was not deleted.")
    }
    .alert(
      "Treatment change unavailable",
      isPresented: Binding(
        get: { unavailableTreatmentMessage != nil },
        set: { if !$0 { unavailableTreatmentMessage = nil } }
      )
    ) {
      Button("OK") { unavailableTreatmentMessage = nil }
    } message: {
      Text(unavailableTreatmentMessage ?? "That treatment change is no longer available.")
    }
    .onChange(of: treatments.map(\.id)) { _, treatmentIDs in
      if let selectedTreatmentID, !treatmentIDs.contains(selectedTreatmentID) {
        self.selectedTreatmentID = treatmentIDs.first
      }
      if let route = treatmentEditorRoute,
         case .edit(let treatmentID) = route.mode,
         !treatmentIDs.contains(treatmentID) {
        treatmentEditorRoute = nil
        unavailableTreatmentMessage = "That treatment change was removed before your edit could be saved. No new treatment change was created."
      }
      if let treatmentPendingDeletionID, !treatmentIDs.contains(treatmentPendingDeletionID) {
        self.treatmentPendingDeletionID = nil
        showDeleteConfirmation = false
      }
    }
  }

  private func deletePendingTreatment() {
    guard let treatmentPendingDeletionID,
          let index = treatments.firstIndex(where: { $0.id == treatmentPendingDeletionID }) else {
      self.treatmentPendingDeletionID = nil
      selectedTreatmentID = treatments.first?.id
      return
    }

    let treatment = treatments[index]
    let nextSelection: UUID? = if treatments.indices.contains(index + 1) {
      treatments[index + 1].id
    } else if index > treatments.startIndex {
      treatments[index - 1].id
    } else {
      nil
    }

    do {
      try ClinicalTimelineStore(context: modelContext).deleteTreatmentEvent(treatment)
      selectedTreatmentID = nextSelection
      self.treatmentPendingDeletionID = nil
    } catch {
      selectedTreatmentID = treatment.id
      self.treatmentPendingDeletionID = nil
      deletionErrorMessage = error.localizedDescription
    }
  }

  private func progressCard(_ window: GIJournalProgressPresentation.Window) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(window.title).font(.title3.bold())
      Text(window.dateRange)
        .font(.subheadline)
        .foregroundStyle(GIJournalTheme.secondaryText)
      Divider()
      LabeledContent("Recorded bowel movements", value: window.recordedEntries)
      LabeledContent("Complete days", value: window.completeness)
      LabeledContent("Recorded frequency", value: window.frequency)
      ForEach(window.details, id: \.self) { detail in
        Text(detail)
          .font(.footnote)
          .foregroundStyle(GIJournalTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .giJournalCard()
  }

  private func makePresentation(for treatment: TreatmentEventRecord) -> GIJournalProgressPresentation? {
    guard let event = treatment.snapshot else { return nil }
    let clinicalEntries = entries.map { entry in
      ClinicalEntrySnapshot(
        id: entry.id,
        capturedAt: entry.capturedAt,
        confirmedBristolType: entry.effectiveConfirmedBristolType,
        suggestedBristolType: entry.originalObservation?.apparentBristolType,
        hasOriginalAIObservation: entry.originalObservation != nil,
        confirmedPhotoUsable: entry.confirmedPhotoUsable,
        mixedForm: entry.mixedFormAnswer,
        painScore: entry.painScore,
        urgency: entry.urgencyLevel,
        strainingOrIncomplete: entry.strainingOrIncompleteAnswer,
        leakageOrAccident: entry.leakageOrAccidentAnswer,
        redBlood: entry.redBlood.flatMap(ClinicalTriState.init(rawValue:)),
        blackTarry: entry.blackTarry.flatMap(ClinicalTriState.init(rawValue:))
      )
    }
    let result = TreatmentResponseCalculator().compare(event: event, entries: clinicalEntries, completions: completions.compactMap(\.snapshot), today: Date())
    return GIJournalProgressPresentation(
      treatmentName: "\(event.kind.displayName): \(event.name)",
      treatmentDate: dateString(result.transitionDate),
      transitionSummary: "Change day excluded: \(dateString(result.transitionDate)) · \(result.transitionEntryCount) recorded bowel \(result.transitionEntryCount == 1 ? "movement" : "movements")",
      before: window("Before", result.before),
      after: window(result.after.interval.isPartial ? "After so far — \(result.after.interval.totalDays) of 7 days" : "After", result.after),
      dataQuality: "Before: \(result.before.completeDays) of \(result.before.interval.totalDays) days confirmed complete. After: \(result.after.completeDays) of \(result.after.interval.totalDays) days confirmed complete."
    )
  }

  private func window(_ title: String, _ summary: TreatmentWindowSummary) -> GIJournalProgressPresentation.Window {
    return .init(
      id: title,
      title: title,
      dateRange: GIJournalProgressPresentation.dateRange(for: summary.interval),
      recordedEntries: "\(summary.entriesRecorded)",
      completeness: "\(summary.completeDays) of \(summary.interval.totalDays)",
      frequency: summary.completeDayFrequency.map { String(format: "%.1f", $0) } ?? "Insufficient complete-day data",
      details: GIJournalProgressPresentation.detailLines(for: summary)
    )
  }

  private func dateString(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day().year()) }
}

private struct TreatmentEventUnavailableSheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ContentUnavailableView(
        "Treatment change unavailable",
        systemImage: "calendar.badge.exclamationmark",
        description: Text("This treatment change was removed. Close this sheet and choose another record.")
      )
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .navigationTitle("Treatment change unavailable")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}
#endif
