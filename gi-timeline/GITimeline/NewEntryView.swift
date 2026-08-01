import PhotosUI
import SwiftUI
import GITimelineCore

struct NewEntryTab: View {
  let store: EntryStoring
  let runtime: ModelRuntimeCoordinator
  @State private var viewModel: NewEntryViewModel?
  var body: some View {
    Group {
      if let viewModel { NewEntryView(viewModel: viewModel, runtime: runtime) }
      else { ProgressView().task { viewModel = await makeViewModel() } }
    }
  }
  private func makeViewModel() async -> NewEntryViewModel {
    let configuration = await runtime.configurationSnapshot()
    let launchArguments = ProcessInfo.processInfo.arguments
    #if DEBUG
    let arguments = launchArguments
    if arguments.contains("--ui-test-fake-gemma") {
      let response = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
      let scripts: [MockInferenceService.Script]
      if arguments.contains("--ui-test-inference-failure") {
        scripts = [.malformed("not json"), .malformed("still not json")]
      } else {
        let delay: UInt64 = arguments.contains("--ui-preview-analyzing") ? 8_000_000_000 : 600_000_000
        scripts = [.slow(response, nanoseconds: delay)]
      }
      let viewModel = NewEntryViewModel(
        imageStore: ImageStore(),
        store: store,
        inference: MockInferenceService(scripts: scripts),
        descriptor: nil,
        modelVerified: true,
        engineReady: true,
        configuration: configuration,
        runtimeBadgeOverride: "UI demo · Gemma not connected",
        modelLabelOverride: "Deterministic UI-test provider"
      )
      if arguments.contains("--ui-preview-sample-selected")
        || arguments.contains("--ui-preview-analyzing")
        || arguments.contains("--ui-preview-result")
        || arguments.contains("--ui-preview-error")
      {
        viewModel.prepareDemoFixture(.brown)
      }
      if arguments.contains("--ui-preview-analyzing")
        || arguments.contains("--ui-preview-result")
        || arguments.contains("--ui-preview-error")
      {
        viewModel.analyze()
      }
      return viewModel
    }
    #endif
    guard let descriptor = ModelCatalog.normalFlowSelection else {
      return NewEntryViewModel(
        imageStore: ImageStore(),
        store: store,
        inference: UnavailableInferenceService(),
        descriptor: nil,
        modelVerified: false,
        configuration: configuration
      )
    }
    let verified = (try? await runtime.receipt(for: descriptor)) != nil
    let engineReady = await runtime.engineState(descriptor) == .ready
    let service = CoordinatedInferenceService(runtime: runtime, descriptor: descriptor)
    let viewModel = NewEntryViewModel(
      imageStore: ImageStore(),
      store: store,
      inference: service,
      descriptor: descriptor,
      modelVerified: verified,
      engineReady: engineReady,
      configuration: configuration,
      modelImportOperation: { descriptor in try await runtime.importModel(descriptor) }
    )
    #if DEBUG
    if launchArguments.contains("--ui-preview-real-sample-selected")
      || launchArguments.contains("--ui-preview-real-analyzing")
      || launchArguments.contains("--ui-preview-real-result")
    {
      viewModel.prepareDemoFixture(.brown)
    }
    if launchArguments.contains("--ui-preview-real-analyzing")
      || launchArguments.contains("--ui-preview-real-result")
    {
      if !viewModel.isEngineReady { await viewModel.prepareModel() }
      viewModel.analyze()
    }
    if launchArguments.contains("--ui-preview-real-result") {
      for _ in 0..<900 where viewModel.isBusy { try? await Task.sleep(for: .milliseconds(100)) }
    }
    #endif
    return viewModel
  }
}

struct NewEntryView: View {
  @ObservedObject var viewModel: NewEntryViewModel
  let runtime: ModelRuntimeCoordinator
  @State private var showModelImport = false
  #if DEBUG
  @State private var showInferenceLab = false
  #endif
  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
      Form {
        Section {
          Text("Document with Gemma").font(.title2.bold())
          Text("Choose an image, let Gemma describe visible features, then review every field before saving.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        ProductBadges(runtimeLabel: viewModel.runtimeBadgeLabel)
        #if DEBUG
        Section("Try a demo image") {
          Text("Bundled synthetic images contain no health data.").font(.caption).foregroundStyle(.secondary)
          HStack {
            demoButton(.brown, systemImage: "circle.fill")
            demoButton(.green, systemImage: "leaf.fill")
            demoButton(.control, systemImage: "square.on.circle")
          }
        }
        #endif
        Section("Photo") {
          PhotosPicker(selection: $viewModel.selectedItem, matching: .images) { Label("Choose a photo", systemImage: "photo") }
            .disabled(!viewModel.canReplaceOrClear)
            .accessibilityIdentifier("choosePhoto")
            .onChange(of: viewModel.selectedItem) { _, _ in Task { await viewModel.loadSelection() } }
          if let image = viewModel.selectedImage {
            image.resizable().scaledToFit().frame(maxHeight: 220)
              .accessibilityIdentifier("selectedImagePreview")
              .id("selectedImagePreview")
          }
          if viewModel.selectedImage == nil {
            Text("A photo is required to save.").font(.footnote)
          } else {
            #if DEBUG
            if let fixture = viewModel.selectedDemoFixture {
              Label("Bundled synthetic \(fixture.rawValue) demo image ready", systemImage: "checkmark.shield")
                .font(.footnote).foregroundStyle(.secondary)
            } else {
              Text("Image ready — review it before saving.").font(.footnote)
            }
            #else
            Text("Image ready — review it before saving.").font(.footnote)
            #endif
          }
        }
        Section("Entry") { DatePicker("Date and time", selection: $viewModel.capturedAt) }
        Section("Local model") {
          Text(viewModel.modelLabel).font(.footnote)
          Text(viewModel.modelStatusText).font(.caption).foregroundStyle(.secondary)
          if viewModel.canPrepareModel {
            Button("Prepare local model") { Task { await viewModel.prepareModel() } }
              .accessibilityIdentifier("prepareGemma")
          }
          if let seconds = viewModel.initializationSeconds {
            Text("Initialization: \(seconds, format: .number.precision(.fractionLength(2))) s").font(.caption)
          }
        }
        Section {
          DisclosureGroup("Symptoms and context (optional)") {
            symptom("Red blood", value: $viewModel.redBlood)
            symptom("Black or tarry stool", value: $viewModel.blackTarry)
            symptom("Dizziness or fainting", value: $viewModel.dizziness)
            symptom("Severe or worsening pain", value: $viewModel.severePain)
            TextField("Note (optional)", text: $viewModel.note, axis: .vertical)
              .lineLimit(3...6)
              .accessibilityIdentifier("noteField")
              .onChange(of: viewModel.note) { _, value in if value.count > 500 { viewModel.note = String(value.prefix(500)) } }
          }
        }
        if viewModel.safetyVisible { Section { Text(SafetyRules.message).foregroundStyle(.red) } }
        if let observation = viewModel.reviewedObservation {
          ReviewPanel(observation: observation, viewModel: viewModel)
            .id("reviewPanel")
        }
        if let status = viewModel.statusMessage {
          Section {
            if viewModel.isBusy { ProgressView(status) }
            else { Text(status).foregroundStyle(.secondary) }
          }
          .accessibilityIdentifier("analysisStatus")
          .id("analysisStatus")
        }
        Section {
          Button("Analyze with Gemma") { viewModel.analyze() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canAnalyze)
            .accessibilityIdentifier("analyzeWithGemma")
          if let reason = viewModel.analyzeUnavailableReason {
            Text(reason).font(.caption).foregroundStyle(.secondary)
          }
          Button(viewModel.hasAnalysis ? "Save Reviewed Entry" : "Save Entry") { viewModel.save() }.disabled(!viewModel.canSave)
            .accessibilityIdentifier("saveEntry")
          Button("Clear", role: .destructive) { viewModel.clear() }.disabled(!viewModel.canReplaceOrClear)
            .accessibilityIdentifier("clearEntry")
        }
        Section { Text(AppFolders.privacyLine).font(.footnote) }
      }.navigationTitle("New Entry")
      .toolbar {
        #if DEBUG
        ToolbarItem(placement: .topBarLeading) {
          Button("Developer", systemImage: "wrench.and.screwdriver") { showInferenceLab = true }
            .accessibilityIdentifier("openInferenceLab")
        }
        #endif
        ToolbarItem(placement: .topBarTrailing) { Button("Import model") { showModelImport = true }.disabled(!viewModel.canImportModel) }
      }
      .sheet(isPresented: $showModelImport) { ModelImportSheet(viewModel: viewModel) }
      #if DEBUG
      .sheet(isPresented: $showInferenceLab, onDismiss: {
        Task { await viewModel.refreshRuntimeReadiness(using: runtime) }
      }) { DeviceInferenceLabTab(runtime: runtime) }
      #endif
      .task {
        try? await Task.sleep(for: .milliseconds(250))
        scrollForCurrentState(using: proxy)
      }
      .onChange(of: viewModel.isBusy) { _, isBusy in
        if isBusy { withAnimation { proxy.scrollTo("analysisStatus", anchor: .center) } }
      }
      .onChange(of: viewModel.hasAnalysis) { _, hasAnalysis in
        if hasAnalysis { withAnimation { proxy.scrollTo("reviewPanel", anchor: .top) } }
      }
      .onChange(of: viewModel.statusMessage) { _, status in
        if status != nil, !viewModel.isBusy { withAnimation { proxy.scrollTo("analysisStatus", anchor: .center) } }
      }
      }
    }
  }
  private func scrollForCurrentState(using proxy: ScrollViewProxy) {
    let arguments = ProcessInfo.processInfo.arguments
    if viewModel.hasAnalysis || arguments.contains("--ui-preview-real-result") {
      proxy.scrollTo("reviewPanel", anchor: .top)
    } else if viewModel.isBusy || arguments.contains("--ui-preview-real-analyzing") || arguments.contains("--ui-preview-analyzing") {
      proxy.scrollTo("analysisStatus", anchor: .center)
    } else if arguments.contains("--ui-preview-real-sample-selected") || arguments.contains("--ui-preview-sample-selected") {
      proxy.scrollTo("selectedImagePreview", anchor: .top)
    } else if viewModel.statusMessage != nil || arguments.contains("--ui-preview-error") {
      proxy.scrollTo("analysisStatus", anchor: .center)
    }
  }
  #if DEBUG
  private func demoButton(_ fixture: SyntheticFixture, systemImage: String) -> some View {
    Button {
      viewModel.prepareDemoFixture(fixture)
    } label: {
      VStack(spacing: 6) {
        Image(systemName: systemImage).font(.title2)
        Text(fixture == .control ? "Control" : fixture.rawValue.capitalized).font(.caption.weight(.semibold))
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .disabled(!viewModel.canReplaceOrClear)
    .accessibilityIdentifier("demo\(fixture.rawValue.capitalized)")
  }
  #endif
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
  @State private var message: String?
  var body: some View {
    NavigationStack { Form {
      Section("Finder transfer") {
        Text("Copy \(viewModel.modelArtifactFilename) to this app’s Documents/Import folder.").font(.footnote)
        Text("Trusted descriptor SHA-256: \(viewModel.modelExpectedHashLabel)").font(.caption).textSelection(.enabled)
        Text("The staged source is retained after import; importing does not authorize deletion.").font(.caption).foregroundStyle(.secondary)
      }
      if let message { Text(message).foregroundStyle(.secondary) }
      Button(viewModel.isImportingModel ? "Importing…" : "Verify and import") {
        Task {
          do {
            let result = try await viewModel.importStagedModel()
            message = "Verified SHA-256 \(result.receipt.importedSHA256) imported. Source retained."
          } catch { message = error.localizedDescription }
        }
      }.disabled(!viewModel.canImportModel)
    }.navigationTitle("Import model").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.disabled(viewModel.isImportingModel) } } }
  }
}

struct ProductBadges: View {
  let runtimeLabel: String?
  init(runtimeLabel: String? = nil) { self.runtimeLabel = runtimeLabel }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let runtimeLabel {
        let isDisconnectedDemo = runtimeLabel.hasPrefix("UI demo")
        Text(runtimeLabel)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 9).padding(.vertical, 6)
          .background((isDisconnectedDemo ? Color.gray : Color.green).opacity(0.16), in: Capsule())
          .accessibilityIdentifier("runtimeBadge")
      }
      Text("Prototype — not medical advice")
        .font(.caption)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.orange.opacity(0.16), in: Capsule())
    }
  }
}

struct ReviewPanel: View {
  let observation: VisualObservation
  @ObservedObject var viewModel: NewEntryViewModel
  var body: some View {
    Section("AI-assisted observation") {
      attributedRow {
        Picker("Image usable", selection: Binding(
          get: { observation.imageUsable },
          set: setImageUsable
        )) {
          Text("Yes").tag(true)
          Text("No").tag(false)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("reviewImageUsable")
      }
      if !observation.imageUsable { Text("Image quality: \(observation.qualityIssue.replacingOccurrences(of: "_", with: " ")) — assessment not possible") }
      else {
        attributedRow { Picker("Bristol type", selection: Binding(get: { observation.apparentBristolType.map(String.init) ?? "none" }, set: { value in viewModel.updateReview { VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: Int(value), apparentColor: $0.apparentColor, form: $0.form, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: $0.blackTarryAppearance) } })) { Text("None").tag("none"); ForEach(1...7, id: \.self) { Text(String($0)).tag(String($0)) } } }
        enumPicker("Apparent color", value: observation.apparentColor, options: Array(ObservationParser.colors).sorted()) { value in viewModel.updateReview { VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: value, form: $0.form, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: $0.blackTarryAppearance) } }
          .accessibilityIdentifier("reviewApparentColor")
        enumPicker("Form", value: observation.form, options: Array(ObservationParser.forms).sorted()) { value in viewModel.updateReview { VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: $0.apparentColor, form: value, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: $0.blackTarryAppearance) } }
          .accessibilityIdentifier("reviewForm")
        enumPicker("Red-appearing material", value: observation.redAppearingMaterial, options: Array(ObservationParser.materialStates).sorted()) { value in viewModel.updateReview { VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: $0.apparentColor, form: $0.form, redAppearingMaterial: value, blackTarryAppearance: $0.blackTarryAppearance) } }
        enumPicker("Black/tarry appearance", value: observation.blackTarryAppearance, options: Array(ObservationParser.materialStates).sorted()) { value in viewModel.updateReview { VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: $0.apparentColor, form: $0.form, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: value) } }
      }
      if !observation.imageUsable {
        enumPicker(
          "Quality issue",
          value: observation.qualityIssue,
          options: Array(ObservationParser.qualityIssues.subtracting(["none"])).sorted(),
          onChange: setQualityIssue
        )
      } else {
        attributedRow { LabeledContent("Quality issue", value: "None") }
      }
    }
  }
  private func setImageUsable(_ usable: Bool) {
    viewModel.updateReview { current in
      if usable {
        return VisualObservation(
          imageUsable: true,
          qualityIssue: "none",
          apparentBristolType: current.apparentBristolType ?? 4,
          apparentColor: current.apparentColor == "unable_to_assess" ? "brown" : current.apparentColor,
          form: current.form == "unable_to_assess" ? "smooth_formed" : current.form,
          redAppearingMaterial: current.redAppearingMaterial == "unable_to_assess" ? "not_observed" : current.redAppearingMaterial,
          blackTarryAppearance: current.blackTarryAppearance == "unable_to_assess" ? "not_observed" : current.blackTarryAppearance
        )
      }
      return VisualObservation(
        imageUsable: false,
        qualityIssue: current.qualityIssue == "none" ? "other" : current.qualityIssue,
        apparentBristolType: nil,
        apparentColor: "unable_to_assess",
        form: "unable_to_assess",
        redAppearingMaterial: "unable_to_assess",
        blackTarryAppearance: "unable_to_assess"
      )
    }
  }
  private func setQualityIssue(_ value: String) {
    viewModel.updateReview { _ in
      VisualObservation(
        imageUsable: false,
        qualityIssue: value,
        apparentBristolType: nil,
        apparentColor: "unable_to_assess",
        form: "unable_to_assess",
        redAppearingMaterial: "unable_to_assess",
        blackTarryAppearance: "unable_to_assess"
      )
    }
  }
  private func enumPicker(_ label: String, value: String, options: [String], onChange: @escaping (String) -> Void) -> some View { attributedRow { Picker(label, selection: Binding(get: { value }, set: onChange)) { ForEach(options, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) } } } }
  private func attributedRow<Row: View>(@ViewBuilder _ row: () -> Row) -> some View {
    VStack(alignment: .leading, spacing: 2) { row(); Text("AI-assisted observation").font(.caption2).foregroundStyle(.secondary) }
  }
}
