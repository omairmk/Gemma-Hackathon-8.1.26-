import PhotosUI
import SwiftUI
import GITimelineCore

struct NewEntryTab: View {
  let store: EntryStoring
  @State private var viewModel: NewEntryViewModel?
  var body: some View {
    Group {
      if let viewModel { NewEntryView(viewModel: viewModel) }
      else { ProgressView().task { viewModel = makeViewModel() } }
    }
  }
  private func makeViewModel() -> NewEntryViewModel {
    let modelURL = (try? AppFolders.models().appendingPathComponent("gemma-4-E4B-it.litertlm")) ?? URL(fileURLWithPath: "/missing-model")
    let cacheURL = (try? AppFolders.modelCache()) ?? URL(fileURLWithPath: NSTemporaryDirectory())
    try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
    let modelReady = FileManager.default.fileExists(atPath: modelURL.path)
    return NewEntryViewModel(imageStore: ImageStore(), store: store, inference: InferenceService(modelURL: modelURL, cacheURL: cacheURL), modelReady: modelReady)
  }
}

struct NewEntryView: View {
  @ObservedObject var viewModel: NewEntryViewModel
  @State private var showModelImport = false
  var body: some View {
    NavigationStack {
      Form {
        ProductBadges()
        Section("Photo") {
          PhotosPicker(selection: $viewModel.selectedItem, matching: .images) { Label("Select photo", systemImage: "photo") }
            .disabled(!viewModel.canReplaceOrClear)
            .onChange(of: viewModel.selectedItem) { _, _ in Task { await viewModel.loadSelection() } }
          if let image = viewModel.selectedImage { image.resizable().scaledToFit().frame(maxHeight: 220) }
          Text("A photo is required to save.").font(.footnote)
        }
        Section("Entry") { DatePicker("Date and time", selection: $viewModel.capturedAt) }
        Section {
          DisclosureGroup("Symptoms and context (optional)") {
            symptom("Red blood", value: $viewModel.redBlood)
            symptom("Black or tarry stool", value: $viewModel.blackTarry)
            symptom("Dizziness or fainting", value: $viewModel.dizziness)
            symptom("Severe or worsening pain", value: $viewModel.severePain)
            TextField("Note (optional)", text: $viewModel.note, axis: .vertical).lineLimit(3...6).onChange(of: viewModel.note) { _, value in if value.count > 500 { viewModel.note = String(value.prefix(500)) } }
          }
        }
        if viewModel.safetyVisible { Section { Text(SafetyRules.message).foregroundStyle(.red) } }
        if let observation = viewModel.reviewedObservation { ReviewPanel(observation: observation, viewModel: viewModel) }
        if let status = viewModel.statusMessage { Section { Text(status).foregroundStyle(.secondary) } }
        Section {
          Button("Analyze on this iPhone") { viewModel.analyze() }.disabled(!viewModel.canAnalyze)
          Button(viewModel.hasAnalysis ? "Save Reviewed Entry" : "Save Entry") { viewModel.save() }.disabled(!viewModel.canSave)
          Button("Clear", role: .destructive) { viewModel.clear() }.disabled(!viewModel.canReplaceOrClear)
        }
        Section { Text(AppFolders.privacyLine).font(.footnote) }
      }.navigationTitle("New Entry")
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Import model") { showModelImport = true }.disabled(!viewModel.canImportModel) } }
      .sheet(isPresented: $showModelImport) { ModelImportSheet(viewModel: viewModel) }
    }
  }
  private func symptom(_ title: String, value: Binding<SymptomFlag?>) -> some View {
    Picker(title, selection: value) {
      Text("Yes").tag(SymptomFlag.yes as SymptomFlag?)
      Text("No").tag(SymptomFlag.no as SymptomFlag?)
      Text("Unsure").tag(SymptomFlag.unsure as SymptomFlag?)
    }.pickerStyle(.segmented)
  }
}

struct ModelImportSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var viewModel: NewEntryViewModel
  @State private var sha256 = ""
  @State private var message: String?
  var body: some View {
    NavigationStack { Form {
      Section("Finder transfer") { Text("Copy \(ModelImporter.sourceFilename) to this app’s Documents/Import folder, then enter its verified download SHA-256.").font(.footnote); TextField("SHA-256", text: $sha256).textInputAutocapitalization(.never).autocorrectionDisabled() }
      if let message { Text(message).foregroundStyle(.secondary) }
      Button(viewModel.isImportingModel ? "Importing…" : "Verify and import") {
        Task {
          do {
            _ = try await viewModel.importStagedModel(expectedSHA256: sha256)
            message = "Verified SHA-256 \(sha256.lowercased()) imported."
          } catch { message = error.localizedDescription }
        }
      }.disabled(sha256.count != 64 || !viewModel.canImportModel)
    }.navigationTitle("Import model").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.disabled(viewModel.isImportingModel) } } }
  }
}

struct ProductBadges: View { var body: some View { HStack { Text("Runs locally on this iPhone").font(.caption).padding(5).background(.green.opacity(0.15), in: Capsule()); Text("Documentation only — not diagnosis").font(.caption).padding(5).background(.orange.opacity(0.15), in: Capsule()) } } }

struct ReviewPanel: View {
  let observation: VisualObservation
  @ObservedObject var viewModel: NewEntryViewModel
  var body: some View {
    Section("AI-assisted observation") {
      if !observation.imageUsable { Text("Image quality: \(observation.qualityIssue.replacingOccurrences(of: "_", with: " ")) — assessment not possible") }
      else {
        attributedRow { Picker("Bristol type", selection: Binding(get: { observation.apparentBristolType.map(String.init) ?? "none" }, set: { value in viewModel.updateReview { VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: Int(value), apparentColor: $0.apparentColor, form: $0.form, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: $0.blackTarryAppearance) } })) { Text("None").tag("none"); ForEach(1...7, id: \.self) { Text(String($0)).tag(String($0)) } } }
        enumPicker("Apparent color", value: observation.apparentColor, options: Array(ObservationParser.colors).sorted()) { value in viewModel.updateReview { VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: value, form: $0.form, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: $0.blackTarryAppearance) } }
        enumPicker("Form", value: observation.form, options: Array(ObservationParser.forms).sorted()) { value in viewModel.updateReview { VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: $0.apparentColor, form: value, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: $0.blackTarryAppearance) } }
        enumPicker("Red-appearing material", value: observation.redAppearingMaterial, options: Array(ObservationParser.materialStates).sorted()) { value in viewModel.updateReview { VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: $0.apparentColor, form: $0.form, redAppearingMaterial: value, blackTarryAppearance: $0.blackTarryAppearance) } }
        enumPicker("Black/tarry appearance", value: observation.blackTarryAppearance, options: Array(ObservationParser.materialStates).sorted()) { value in viewModel.updateReview { VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: $0.apparentColor, form: $0.form, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: value) } }
      }
    }
  }
  private func enumPicker(_ label: String, value: String, options: [String], onChange: @escaping (String) -> Void) -> some View { attributedRow { Picker(label, selection: Binding(get: { value }, set: onChange)) { ForEach(options, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) } } } }
  private func attributedRow<Row: View>(@ViewBuilder _ row: () -> Row) -> some View {
    VStack(alignment: .leading, spacing: 2) { row(); Text("AI-assisted observation").font(.caption2).foregroundStyle(.secondary) }
  }
}
