import SwiftUI
import GITimelineCore
import SwiftData

/// The ordinary-user labels intentionally stay separate from parser tokens and
/// persistence enums. This prevents technical raw values from leaking into UI.
enum GIJournalCopy {
  static func stoolType(_ type: Int) -> String {
    switch type {
    case 1: "Type 1 — separate hard lumps"
    case 2: "Type 2 — firm and lumpy"
    case 3: "Type 3 — formed with surface cracks"
    case 4: "Type 4 — smooth and formed"
    case 5: "Type 5 — soft pieces with clear edges"
    case 6: "Type 6 — mushy or fluffy pieces"
    case 7: "Type 7 — watery, with no solid pieces"
    default: "Unable to tell"
    }
  }

  static func consistency(for bristolType: Int?) -> String {
    switch bristolType {
    case 1, 2: "Hard"
    case 3, 4: "Formed"
    case 5: "Soft"
    case 6: "Loose"
    case 7: "Watery"
    default: "Unable to tell"
    }
  }
}

struct GIJournalStoolTypePicker: View {
  @Binding var selection: Int?
  @Binding var helpRoute: GIJournalHelpRoute?
  var suggestedType: Int? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Stool type").font(.headline)
          Text("Bristol Stool Scale, Types 1–7")
            .font(.footnote)
            .foregroundStyle(GIJournalTheme.secondaryText)
        }
        Spacer()
        GIJournalHelpButton(route: .stoolTypes, routeToPresent: $helpRoute)
      }

      if let suggestedType {
        GIJournalBadge(title: "Suggested: \(GIJournalCopy.stoolType(suggestedType))", symbol: "sparkles")
          .accessibilityLabel("Suggested: \(GIJournalCopy.stoolType(suggestedType))")
      }

      VStack(spacing: 8) {
        ForEach(1...7, id: \.self) { type in
          stoolTypeButton(type)
        }
        stoolTypeButton(nil)
      }
    }
    .giJournalCard()
  }

  private func stoolTypeButton(_ type: Int?) -> some View {
    Button {
      selection = type
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: selection == type ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(selection == type ? GIJournalTheme.primary : GIJournalTheme.secondaryText)
          .font(.title3)
        Text(type.map(GIJournalCopy.stoolType) ?? "Unable to tell")
          .font(.body)
          .multilineTextAlignment(.leading)
          .foregroundStyle(GIJournalTheme.text)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(type.map(GIJournalCopy.stoolType) ?? "Unable to tell")
    .accessibilityValue(selection == type ? "Selected" : "Not selected")
    .accessibilityAddTraits(selection == type ? .isSelected : [])
  }
}

/// Uses the core enum directly so an unanswered value stays nil rather than
/// being translated through an interface-only String.
struct GIJournalClinicalTriStateRows: View {
  let title: String
  var helper: String? = nil
  let accessibilityIdentifierPrefix: String
  @Binding var selection: ClinicalTriState?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
        .foregroundStyle(GIJournalTheme.text)
        .fixedSize(horizontal: false, vertical: true)
      if let helper {
        Text(helper)
          .font(.footnote)
          .foregroundStyle(GIJournalTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) { optionButtons }
      } else {
        HStack(spacing: 8) { optionButtons }
      }
    }
  }

  @ViewBuilder private var optionButtons: some View {
    ForEach(ClinicalTriState.allCases, id: \.self) { value in
      Button {
        selection = value
      } label: {
        HStack(spacing: 7) {
          Image(systemName: selection == value ? "checkmark.circle.fill" : "circle")
          Text(label(for: value))
          Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 10)
        .background(selection == value ? GIJournalTheme.tintedSurface : GIJournalTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(selection == value ? GIJournalTheme.primary : GIJournalTheme.border, lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
      .foregroundStyle(selection == value ? GIJournalTheme.primary : GIJournalTheme.text)
      .accessibilityIdentifier("\(accessibilityIdentifierPrefix)_\(value.rawValue)")
      .accessibilityLabel("\(title) \(label(for: value))")
      .accessibilityValue(selection == value ? "Selected" : "Not selected")
    }
  }

  private func label(for value: ClinicalTriState) -> String {
    switch value {
    case .no: "No"
    case .unsure: "Not sure"
    case .yes: "Yes"
    }
  }
}

struct GIJournalBooleanRows: View {
  let title: String
  var helper: String? = nil
  @Binding var selection: Bool?
  var noLabel = "No"
  var yesLabel = "Yes"
  var accessibilityIdentifierPrefix: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.headline)
      if let helper {
        Text(helper)
          .font(.footnote)
          .foregroundStyle(GIJournalTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: 8) {
        option(label: noLabel, value: false)
        option(label: yesLabel, value: true)
      }
    }
  }

  private func option(label: String, value: Bool) -> some View {
    Button { selection = value } label: {
      HStack(spacing: 7) {
        Image(systemName: selection == value ? "checkmark.circle.fill" : "circle")
        Text(label)
        Spacer(minLength: 0)
      }
      .font(.subheadline.weight(.semibold))
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.horizontal, 10)
      .background(selection == value ? GIJournalTheme.tintedSurface : GIJournalTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(selection == value ? GIJournalTheme.primary : GIJournalTheme.border, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(selection == value ? GIJournalTheme.primary : GIJournalTheme.text)
    .accessibilityIdentifier(accessibilityIdentifierPrefix.map {
      "\($0)_\(value ? "yes" : "no")"
    } ?? "")
    .accessibilityValue(selection == value ? "Selected" : "Not selected")
  }
}

struct GIJournalUrgencyRows: View {
  @Binding var selection: UrgencyLevel?
  @Binding var helpRoute: GIJournalHelpRoute?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("How hard was it to wait for a toilet?")
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        GIJournalHelpButton(route: .urgency, routeToPresent: $helpRoute)
      }
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) { optionButtons }
      } else {
        HStack(spacing: 8) { optionButtons }
      }
    }
  }

  @ViewBuilder private var optionButtons: some View {
    ForEach(UrgencyLevel.allCases, id: \.self) { value in
      Button { selection = value } label: {
        HStack(spacing: 7) {
          Image(systemName: selection == value ? "checkmark.circle.fill" : "circle")
          Text(label(for: value))
          Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 10)
        .background(selection == value ? GIJournalTheme.tintedSurface : GIJournalTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(selection == value ? GIJournalTheme.primary : GIJournalTheme.border, lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
      .foregroundStyle(selection == value ? GIJournalTheme.primary : GIJournalTheme.text)
      .accessibilityValue(selection == value ? "Selected" : "Not selected")
    }
  }

  private func label(for value: UrgencyLevel) -> String {
    switch value {
    case .none: "No urgency"
    case .moderate: "Had to hurry"
    case .severe: "Could not wait"
    }
  }
}

struct GIJournalPainControl: View {
  @Binding var score: Int?

  private var safeScore: Binding<Double> {
    Binding(
      get: { Double(score ?? 0) },
      set: { score = Int($0.rounded()) }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Pain with this bowel movement")
          .font(.headline)
          .foregroundStyle(GIJournalTheme.text)
        Spacer()
        Text(score.map { "\($0) / 10" } ?? "Not answered")
          .font(.headline.monospacedDigit())
          .foregroundStyle(GIJournalTheme.text)
          .accessibilityLabel(score.map { "\($0) out of 10" } ?? "Not answered")
      }
      if score == nil {
        Button("Set pain score") { score = 0 }
          .buttonStyle(GIJournalSecondaryButtonStyle())
          .accessibilityHint("Sets the score to zero. You can then adjust it from zero to ten.")
      } else {
        Slider(value: safeScore, in: 0...10, step: 1)
          .tint(GIJournalTheme.primary)
          .accessibilityLabel("Pain with this bowel movement")
          .accessibilityValue("\(score ?? 0) out of 10")
      }
      HStack {
        Text("0 — no pain")
        Spacer()
        Text("10 — worst pain you can imagine")
          .multilineTextAlignment(.trailing)
      }
      .font(.footnote)
      .foregroundStyle(GIJournalTheme.secondaryText)
    }
  }
}

struct GIJournalSuggestionDisclosure: View {
  let source: String?
  @Binding var helpRoute: GIJournalHelpRoute?
  /// This remains false until a physical-iPhone raw-image gate is observed by
  /// the lead. Simulator-only evidence must never unlock raw-image claims.
  var rawImageOnDeviceAccepted = false

  private var explanation: String {
    switch source {
    case "gemma_derived_map":
      "On-device suggestion: GI Journal created a simplified picture summary on this iPhone. The embedded Gemma model received only that summary, not the photo. Review the prefilled entry, change anything that is not right, then confirm it once."
    case "gemma_raw_image" where rawImageOnDeviceAccepted:
      "On-device suggestion: GI Journal used the selected photo on this iPhone. Please confirm or change the result."
    case "gemma_raw_image":
      "A photo suggestion can be wrong. Review the prefilled entry, change anything that is not right, then confirm it once."
    case "on_device_photo_suggestion":
      "On-device suggestion: GI Journal used the selected photo with the selected local model on this iPhone. Review every prefilled value, change anything that is not right, then confirm the complete entry once."
    default:
      "Entered by you without a photo suggestion."
    }
  }

  var body: some View {
    Group {
      if source == nil || source == "manual" {
        Text("This entry was entered manually. Any attached photo is stored with the entry and was not analyzed or used to prefill fields.")
          .font(.footnote)
          .foregroundStyle(GIJournalTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("manualEntryDisclosure")
          .giJournalCard()
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Text("A still photo cannot confirm blood, bleeding, physical stickiness, melena, diagnosis, urgency, cause, or treatment. Every value is an editable appearance suggestion.")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(GIJournalTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("photoSuggestionAlwaysVisibleLimitations")
          DisclosureGroup("About this suggestion") {
            VStack(alignment: .leading, spacing: 10) {
            Text(explanation)
              .font(.footnote)
              .foregroundStyle(GIJournalTheme.secondaryText)
            Button("How photo suggestions work") { helpRoute = .photoSuggestions }
              .font(.footnote.weight(.semibold))
              .foregroundStyle(GIJournalTheme.primary)
            }
            .padding(.top, 6)
          }
          .font(.subheadline.weight(.semibold))
        }
        .giJournalCard()
      }
    }
  }
}

#if GI_JOURNAL_LEGACY_TREATMENT_UI
struct GIJournalDailyCompletenessCard: View {
  let answer: DailyCompletionAnswer?
  let update: (DailyCompletionAnswer?) -> Void
  @State private var helpRoute: GIJournalHelpRoute?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("Did you record every bowel movement today?")
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        GIJournalHelpButton(route: .dailyCompleteness, routeToPresent: $helpRoute)
      }
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 8) { answerButtons }
      } else {
        HStack(spacing: 8) { answerButtons }
      }
    }
    .giJournalCard()
    .sheet(item: $helpRoute) { GIJournalHelpSheet(route: $0) }
  }

  @ViewBuilder private var answerButtons: some View {
    choice("Yes", value: .yes)
    choice("No", value: .no)
    Button("Not answered") { update(nil) }
      .font(.subheadline.weight(.semibold))
      .frame(maxWidth: .infinity, minHeight: 44)
      .foregroundStyle(answer == nil ? GIJournalTheme.primary : GIJournalTheme.secondaryText)
      .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(answer == nil ? GIJournalTheme.primary : GIJournalTheme.border, lineWidth: 1) }
  }

  private func choice(_ title: String, value: DailyCompletionAnswer) -> some View {
    Button(title) { update(value) }
      .font(.subheadline.weight(.semibold))
      .frame(maxWidth: .infinity, minHeight: 44)
      .foregroundStyle(answer == value ? GIJournalTheme.primary : GIJournalTheme.text)
      .background(answer == value ? GIJournalTheme.tintedSurface : GIJournalTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(answer == value ? GIJournalTheme.primary : GIJournalTheme.border, lineWidth: 1) }
      .accessibilityValue(answer == value ? "Selected" : "Not selected")
  }
}

struct GIJournalTreatmentEventSheet: View {
  let context: ModelContext
  let treatmentEvent: TreatmentEventRecord?
  @Environment(\.dismiss) private var dismiss
  @State private var kind: TreatmentEventKind
  @State private var name: String
  @State private var doseOrNote: String
  @State private var effectiveDate: Date
  @State private var errorMessage: String?

  init(context: ModelContext, treatmentEvent: TreatmentEventRecord? = nil) {
    self.context = context
    self.treatmentEvent = treatmentEvent
    _kind = State(initialValue: treatmentEvent?.kind ?? .startedTreatment)
    _name = State(initialValue: treatmentEvent?.name ?? "")
    _doseOrNote = State(initialValue: treatmentEvent?.doseOrNote ?? "")
    _effectiveDate = State(initialValue: treatmentEvent?.effectiveDate ?? Date())
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Treatment change") {
          Picker("Event type", selection: $kind) {
            ForEach(TreatmentEventKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
          }
          .accessibilityIdentifier("treatmentEventKindPicker")
          TextField("Name", text: $name)
            .accessibilityIdentifier("treatmentEventNameField")
          TextField("Dose or note (optional)", text: $doseOrNote, axis: .vertical)
            .accessibilityIdentifier("treatmentEventNoteField")
          DatePicker("Effective date", selection: $effectiveDate, displayedComponents: .date)
            .accessibilityIdentifier("treatmentEventEffectiveDatePicker")
          Text("A treatment change is a date marker that helps compare your journal before and after something changed. It does not track doses or tell you what treatment to use.")
            .font(.footnote)
            .foregroundStyle(GIJournalTheme.secondaryText)
        }
        if let errorMessage { Text(errorMessage).foregroundStyle(GIJournalTheme.safety) }
      }
      .navigationTitle(treatmentEvent == nil ? "Add treatment change" : "Edit treatment change")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            do {
              let store = ClinicalTimelineStore(context: context)
              if let treatmentEvent {
                try store.updateTreatmentEvent(
                  treatmentEvent,
                  kind: kind,
                  name: name,
                  doseOrNote: doseOrNote,
                  effectiveDate: effectiveDate
                )
              } else {
                try store.addTreatmentEvent(
                  kind: kind,
                  name: name,
                  doseOrNote: doseOrNote,
                  effectiveDate: effectiveDate
                )
              }
              dismiss()
            } catch { errorMessage = error.localizedDescription }
          }
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityIdentifier("saveTreatmentChange")
        }
      }
    }
  }
}
#endif
