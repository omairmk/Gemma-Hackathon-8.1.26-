import PhotosUI
import SwiftUI
import UIKit
import GITimelineCore

extension Notification.Name {
  static let giTimelineShowHistory = Notification.Name("GITimelineShowHistory")
}

struct NewEntryTab: View {
  let store: EntryStoring
  let runtime: ModelRuntimeCoordinator
  @State private var viewModel: NewEntryViewModel?

  var body: some View {
    Group {
      if let viewModel {
        NewEntryView(viewModel: viewModel, runtime: runtime)
      } else {
        ProgressView("Getting things ready…")
          .task { viewModel = await makeViewModel() }
      }
    }
  }

  private func makeViewModel() async -> NewEntryViewModel {
    let configuration = await runtime.configurationSnapshot()
    let launchArguments = ProcessInfo.processInfo.arguments
    #if DEBUG
    if launchArguments.contains("--ui-test-fake-gemma") || launchArguments.contains("--ui-test-first-run") {
      let response = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
      let scripts: [MockInferenceService.Script]
      if launchArguments.contains("--ui-test-inference-failure") {
        scripts = [.malformed("not json"), .malformed("still not json")]
      } else {
        let delay: UInt64 = (launchArguments.contains("--ui-preview-analyzing") || launchArguments.contains("--ui-test-slow-fake-gemma"))
          ? 8_000_000_000
          : 300_000_000
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
        runtimeBadgeOverride: "UI demo · local model not connected",
        modelLabelOverride: "Deterministic UI-test provider",
        autoAnalysisEnabled: true
      )
      if launchArguments.contains("--ui-preview-sample-selected")
        || launchArguments.contains("--ui-preview-analyzing")
        || launchArguments.contains("--ui-preview-result")
        || launchArguments.contains("--ui-preview-error")
      {
        viewModel.prepareDemoFixture(.brown)
      }
      if launchArguments.contains("--ui-preview-result") {
        for _ in 0..<100 where viewModel.isBusy || !viewModel.hasAnalysis {
          try? await Task.sleep(for: .milliseconds(100))
        }
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
        configuration: configuration,
        autoAnalysisEnabled: true
      )
    }
    let readiness = await runtime.localAnalysisReadiness()
    let ready = readiness == .ready
    let viewModel = NewEntryViewModel(
      imageStore: ImageStore(),
      store: store,
      inference: CoordinatedInferenceService(runtime: runtime, descriptor: descriptor),
      descriptor: descriptor,
      modelVerified: ready,
      engineReady: ready,
      configuration: configuration,
      modelImportOperation: { descriptor in try await runtime.importModel(descriptor) },
      autoAnalysisEnabled: true
    )
    #if DEBUG
    if launchArguments.contains("--ui-preview-real-sample-selected")
      || launchArguments.contains("--ui-preview-real-analyzing")
      || launchArguments.contains("--ui-preview-real-result")
    {
      viewModel.prepareDemoFixture(.brown)
    }
    #endif
    return viewModel
  }
}

struct NewEntryView: View {
  @ObservedObject var viewModel: NewEntryViewModel
  let runtime: ModelRuntimeCoordinator
  @AppStorage("giTimeline.didCompleteFirstRun") private var didCompleteFirstRun = false
  @State private var showInformation = false
  @State private var showCamera = false
  #if DEBUG
  @State private var uiTestFirstRunVisible = ProcessInfo.processInfo.arguments.contains("--ui-test-first-run")
  @State private var showInferenceLab = false
  @State private var showModelImport = false
  #endif

  private var isUITest: Bool {
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    return arguments.contains("--ui-test-fake-gemma") || arguments.contains("--skip-first-run")
    #else
    return false
    #endif
  }

  private var usesDeterministicUITestProvider: Bool {
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    return arguments.contains("--ui-test-fake-gemma") || arguments.contains("--ui-test-first-run")
    #else
    return false
    #endif
  }

  private var developerToolsVisible: Bool {
    #if DEBUG
    ProcessInfo.processInfo.arguments.contains("--show-developer-tools")
    #else
    false
    #endif
  }

  private var shouldPresentFirstRun: Bool {
    #if DEBUG
    return (!didCompleteFirstRun || uiTestFirstRunVisible) && !isUITest
    #else
    return !didCompleteFirstRun && !isUITest
    #endif
  }

  private func completeFirstRun() {
    didCompleteFirstRun = true
    #if DEBUG
    uiTestFirstRunVisible = false
    #endif
  }

  var body: some View {
    NavigationStack {
      Group {
        switch viewModel.flowState {
        case .empty, .preparingPhoto:
          NewEntryStartView(viewModel: viewModel, runtime: runtime, showCamera: $showCamera)
        case .reading:
          ReadingPhotoView(viewModel: viewModel)
        case .reviewing:
          ReviewEntryView(viewModel: viewModel)
        case .saving:
          ReviewEntryView(viewModel: viewModel, saving: true)
        case .saved(let entryID):
          SavedEntryView(entryID: entryID, viewModel: viewModel)
        case .failed(_, let message):
          EntryFlowFailureView(
            message: message,
            viewModel: viewModel,
            showCamera: $showCamera,
            retryRuntime: { Task { await viewModel.prepareAutomaticRuntime(using: runtime, retry: true) } },
            prepareRuntime: { await viewModel.prepareAutomaticRuntime(using: runtime) }
          )
        }
      }
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("About GI Timeline", systemImage: "info.circle") { showInformation = true }
            .accessibilityIdentifier("showInformation")
        }
        #if DEBUG
        if developerToolsVisible {
          ToolbarItem(placement: .topBarLeading) {
            Menu("Developer", systemImage: "wrench.and.screwdriver") {
              Button("Inference Lab") { showInferenceLab = true }
              Button("Import model") { showModelImport = true }
                .disabled(!viewModel.canImportModel)
            }
            .accessibilityIdentifier("openDeveloperTools")
          }
        }
        #endif
      }
    }
    .background(Color(.systemGroupedBackground))
    .fullScreenCover(isPresented: Binding(
      get: { shouldPresentFirstRun },
      set: { if !$0 { completeFirstRun() } }
    )) {
      FirstRunInformationView(primaryButtonTitle: "Continue", completion: completeFirstRun)
    }
    .sheet(isPresented: $showInformation) {
      FirstRunInformationView(primaryButtonTitle: "Done") { showInformation = false }
    }
    .fullScreenCover(isPresented: $showCamera) {
      CameraCaptureView { data in
        guard let data else { return }
        do { try viewModel.prepareImageData(data) }
        catch { return }
        Task { await viewModel.prepareAutomaticRuntime(using: runtime) }
      }
      .ignoresSafeArea()
    }
    #if DEBUG
    .sheet(isPresented: $showInferenceLab, onDismiss: {
      Task { await viewModel.refreshRuntimeReadiness(using: runtime) }
    }) { DeviceInferenceLabTab(runtime: runtime) }
    .sheet(isPresented: $showModelImport) { ModelImportSheet(viewModel: viewModel) }
    #endif
  }
}

private struct NewEntryStartView: View {
  @ObservedObject var viewModel: NewEntryViewModel
  let runtime: ModelRuntimeCoordinator
  @Binding var showCamera: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("New Entry")
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)

        VStack(alignment: .leading, spacing: 8) {
          Text("Photo in, reviewed entry out")
            .font(.headline)
          Text("Attach a photo. Observations are proposed automatically and you review every field before saving.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .nativeCard()

        VStack(alignment: .leading, spacing: 12) {
          Text("Photo")
            .font(.headline)
          PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
            NativeActionRow(title: "Choose a photo", systemImage: "photo.on.rectangle")
          }
          .buttonStyle(.plain)
          .disabled(!viewModel.canReplaceOrClear)
          .accessibilityIdentifier("choosePhoto")
          .onChange(of: viewModel.selectedItem) { _, _ in
            Task {
              await viewModel.loadSelection()
              guard viewModel.currentDraftURL != nil else { return }
              await viewModel.prepareAutomaticRuntime(using: runtime)
            }
          }

          Divider().padding(.leading, 44)

          Button {
            showCamera = true
          } label: {
            NativeActionRow(title: "Take a photo", systemImage: "camera")
          }
          .buttonStyle(.plain)
          .disabled(!viewModel.canReplaceOrClear || !UIImagePickerController.isSourceTypeAvailable(.camera))
          .accessibilityIdentifier("takePhoto")
        }
        .nativeCard(padding: 0)

        if case .preparingPhoto = viewModel.flowState {
          HStack(spacing: 12) {
            ProgressView()
            Text("Preparing photo…")
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .nativeCard()
          .accessibilityIdentifier("preparingPhoto")
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-developer-tools")
          || ProcessInfo.processInfo.arguments.contains("--ui-test-fake-gemma")
        {
          VStack(alignment: .leading, spacing: 12) {
            Text("Synthetic developer fixtures").font(.headline)
            HStack {
              demoButton(.brown, title: "Brown")
              demoButton(.green, title: "Green")
              demoButton(.control, title: "Control")
            }
          }
          .nativeCard()
        }
        #endif

        Text("Prototype — not medical advice")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      }
      .padding(20)
    }
    .background(Color(.systemGroupedBackground))
  }

  #if DEBUG
  private func demoButton(_ fixture: SyntheticFixture, title: String) -> some View {
    Button(title) { viewModel.prepareDemoFixture(fixture) }
      .buttonStyle(.bordered)
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier("demo\(title)")
  }
  #endif
}

private struct ReadingPhotoView: View {
  @ObservedObject var viewModel: NewEntryViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var scanPosition: CGFloat = -0.2

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .firstTextBaseline) {
          Text("Reading photo")
            .font(.largeTitle.bold())
            .accessibilityAddTraits(.isHeader)
          Spacer()
          Button("Cancel") { viewModel.cancelReading() }
            .disabled(!viewModel.canReplaceOrClear && !viewModel.isBusy)
            .accessibilityIdentifier("cancelReading")
        }

        ZStack(alignment: .bottomLeading) {
          if let image = viewModel.selectedImage {
            image
              .resizable()
              .scaledToFit()
              .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 440)
              .background(Color(.secondarySystemGroupedBackground))
          }
          if !reduceMotion {
            GeometryReader { geometry in
              Rectangle()
                .fill(Color.accentColor.opacity(0.72))
                .frame(height: 2)
                .shadow(color: Color.accentColor.opacity(0.55), radius: 8)
                .offset(y: max(0, geometry.size.height * scanPosition))
            }
            .allowsHitTesting(false)
          }
          Label("Reading photo", systemImage: "sparkles")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("readingPhotoHero")

        VStack(spacing: 0) {
          ForEach(Array(ReviewField.allCases.enumerated()), id: \.element) { index, field in
            HStack(spacing: 12) {
              ProgressView()
                .controlSize(.small)
              VStack(alignment: .leading, spacing: 6) {
                Text(field.title).font(.subheadline.weight(.medium))
                RoundedRectangle(cornerRadius: 3)
                  .fill(Color.secondary.opacity(0.14))
                  .frame(height: 8)
                  .frame(maxWidth: index.isMultiple(of: 2) ? 150 : 200)
              }
              Spacer()
            }
            .padding(.vertical, 14)
            if index < ReviewField.allCases.count - 1 { Divider() }
          }
        }
        .nativeCard()
        .accessibilityIdentifier("readingObservationSkeletons")
      }
      .padding(20)
    }
    .background(Color(.systemGroupedBackground))
    .task {
      guard !reduceMotion else { return }
      scanPosition = -0.1
      withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
        scanPosition = 0.95
      }
    }
  }
}

private struct ReviewEntryView: View {
  @ObservedObject var viewModel: NewEntryViewModel
  var saving = false
  @State private var revealedFieldCount = 0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Review entry")
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)

        ZStack(alignment: .bottomLeading) {
          if let image = viewModel.selectedImage {
            image.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 320)
          }
          Text(viewModel.capturedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

        DatePicker("Date and time", selection: $viewModel.capturedAt)
          .nativeCard()

        HStack {
          Text("Observations").font(.title2.bold())
          Spacer()
          if viewModel.outstandingReviewCount > 0 {
            Text("\(viewModel.outstandingReviewCount) to review")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.blue)
          } else {
            Label("Reviewed", systemImage: "checkmark.circle.fill")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.green)
          }
        }

        if let observation = viewModel.reviewedObservation {
          VStack(spacing: 12) {
            ReviewFieldCard(field: .bristolType, viewModel: viewModel) {
              Picker("Bristol type", selection: Binding(
                get: { observation.apparentBristolType ?? 4 },
                set: { newValue in
                  viewModel.updateReview(field: .bristolType) {
                    VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: newValue, apparentColor: $0.apparentColor, form: $0.form, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: $0.blackTarryAppearance)
                  }
                }
              )) {
                ForEach(1...7, id: \.self) { Text("Type \($0) · \(bristolLabel($0))").tag($0) }
              }
            }
            .opacity(revealedFieldCount >= 1 ? 1 : 0)

            ReviewFieldCard(field: .apparentColor, viewModel: viewModel) {
              valuePicker("Apparent color", value: observation.apparentColor, options: Array(ObservationParser.colors).sorted()) { value in
                viewModel.updateReview(field: .apparentColor) {
                  VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: value, form: $0.form, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: $0.blackTarryAppearance)
                }
              }
              .accessibilityIdentifier("reviewPicker.apparentColor")
            }
            .opacity(revealedFieldCount >= 2 ? 1 : 0)

            ReviewFieldCard(field: .form, viewModel: viewModel) {
              valuePicker("Form", value: observation.form, options: Array(ObservationParser.forms).sorted()) { value in
                viewModel.updateReview(field: .form) {
                  VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: $0.apparentColor, form: value, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: $0.blackTarryAppearance)
                }
              }
            }
            .opacity(revealedFieldCount >= 3 ? 1 : 0)

            ReviewFieldCard(field: .visibleFeatures, viewModel: viewModel) {
              valuePicker("Red-appearing material", value: observation.redAppearingMaterial, options: Array(ObservationParser.materialStates).sorted()) { value in
                viewModel.updateReview(field: .visibleFeatures) {
                  VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: $0.apparentColor, form: $0.form, redAppearingMaterial: value, blackTarryAppearance: $0.blackTarryAppearance)
                }
              }
              valuePicker("Black or tarry appearance", value: observation.blackTarryAppearance, options: Array(ObservationParser.materialStates).sorted()) { value in
                viewModel.updateReview(field: .visibleFeatures) {
                  VisualObservation(imageUsable: $0.imageUsable, qualityIssue: $0.qualityIssue, apparentBristolType: $0.apparentBristolType, apparentColor: $0.apparentColor, form: $0.form, redAppearingMaterial: $0.redAppearingMaterial, blackTarryAppearance: value)
                }
              }
            }
            .opacity(revealedFieldCount >= 4 ? 1 : 0)

            ReviewFieldCard(field: .imageQuality, viewModel: viewModel) {
              Picker("Photo usable", selection: Binding(
                get: { observation.imageUsable },
                set: { usable in setImageUsable(usable, current: observation) }
              )) {
                Text("Usable").tag(true)
                Text("Could be clearer").tag(false)
              }
              if !observation.imageUsable {
                valuePicker("Quality issue", value: observation.qualityIssue, options: Array(ObservationParser.qualityIssues.subtracting(["none"])).sorted()) { value in
                  viewModel.updateReview(field: .imageQuality) { _ in unusableObservation(issue: value) }
                }
              }
            }
            .opacity(revealedFieldCount >= 5 ? 1 : 0)
          }
        }

        DisclosureGroup("Symptoms and context (optional)") {
          VStack(spacing: 14) {
            symptomToggle("Red blood", value: $viewModel.redBlood)
            symptomToggle("Black or tarry stool", value: $viewModel.blackTarry)
            symptomToggle("Dizziness or fainting", value: $viewModel.dizziness)
            symptomToggle("Severe or worsening pain", value: $viewModel.severePain)
            TextField("Note (optional)", text: $viewModel.note, axis: .vertical)
              .lineLimit(3...6)
              .accessibilityIdentifier("noteField")
              .onChange(of: viewModel.note) { _, value in
                if value.count > 500 { viewModel.note = String(value.prefix(500)) }
              }
          }
          .padding(.top, 12)
        }
        .nativeCard()

        if viewModel.safetyVisible {
          Text(SafetyRules.message)
            .font(.footnote)
            .foregroundStyle(.red)
            .nativeCard()
        }

        Button {
          viewModel.save()
        } label: {
          HStack {
            Spacer()
            if saving { ProgressView().tint(.white) }
            Text(saving ? "Saving…" : "Save reviewed entry").fontWeight(.semibold)
            Spacer()
          }
          .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!viewModel.canSave || saving)
        .accessibilityIdentifier("saveEntry")

        if viewModel.outstandingReviewCount > 0 {
          Text("Review all five suggested fields before saving.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-fake-gemma"), viewModel.outstandingReviewCount > 0 {
          Button("Confirm remaining suggestions") {
            for field in ReviewField.allCases where viewModel.reviewState(for: field) == .suggested {
              viewModel.confirmReviewField(field)
            }
          }
          .accessibilityIdentifier("uiTestConfirmRemaining")
        }
        #endif

        Text("Prototype — not medical advice")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      }
      .padding(20)
    }
    .background(Color(.systemGroupedBackground))
    .task {
      guard revealedFieldCount == 0 else { return }
      for count in 1...ReviewField.allCases.count {
        withAnimation(.easeOut(duration: 0.18)) { revealedFieldCount = count }
        try? await Task.sleep(for: .milliseconds(70))
      }
    }
  }

  private func bristolLabel(_ type: Int) -> String {
    switch type {
    case 1: "separate hard pieces"
    case 2: "firm and lumpy"
    case 3: "formed with cracks"
    case 4: "smooth and formed"
    case 5: "soft pieces"
    case 6: "mushy pieces"
    case 7: "watery"
    default: "not recorded"
    }
  }

  private func valuePicker(_ label: String, value: String, options: [String], onChange: @escaping (String) -> Void) -> some View {
    Picker(label, selection: Binding(get: { value }, set: onChange)) {
      ForEach(options, id: \.self) { Text(humanReadable($0)).tag($0) }
    }
  }

  private func setImageUsable(_ usable: Bool, current: VisualObservation) {
    if usable {
      viewModel.updateReview(field: .imageQuality) { _ in
        VisualObservation(
          imageUsable: true,
          qualityIssue: "none",
          apparentBristolType: current.apparentBristolType ?? 4,
          apparentColor: current.apparentColor == "unable_to_assess" ? "brown" : current.apparentColor,
          form: current.form == "unable_to_assess" ? "smooth_formed" : current.form,
          redAppearingMaterial: current.redAppearingMaterial == "unable_to_assess" ? "not_observed" : current.redAppearingMaterial,
          blackTarryAppearance: current.blackTarryAppearance == "unable_to_assess" ? "not_observed" : current.blackTarryAppearance
        )
      }
    } else {
      viewModel.updateReview(field: .imageQuality) { _ in unusableObservation(issue: current.qualityIssue == "none" ? "other" : current.qualityIssue) }
    }
  }

  private func unusableObservation(issue: String) -> VisualObservation {
    VisualObservation(imageUsable: false, qualityIssue: issue, apparentBristolType: nil, apparentColor: "unable_to_assess", form: "unable_to_assess", redAppearingMaterial: "unable_to_assess", blackTarryAppearance: "unable_to_assess")
  }

  private func symptomToggle(_ title: String, value: Binding<SymptomFlag?>) -> some View {
    Toggle(title, isOn: Binding(
      get: { value.wrappedValue == .yes },
      set: { value.wrappedValue = $0 ? .yes : .no }
    ))
  }
}

private struct ReviewFieldCard<Content: View>: View {
  let field: ReviewField
  @ObservedObject var viewModel: NewEntryViewModel
  @ViewBuilder let content: () -> Content
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        withAnimation { expanded.toggle() }
      } label: {
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 4) {
            Text(field.title).font(.headline).foregroundStyle(.primary)
            reviewBadge
          }
          Spacer()
          Image(systemName: expanded ? "chevron.up" : "chevron.down")
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("reviewField.\(field.rawValue)")

      if expanded {
        VStack(alignment: .leading, spacing: 12) { content() }
        if viewModel.reviewState(for: field) == .suggested {
          Button("Confirm suggestion") { viewModel.confirmReviewField(field) }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("confirmReview.\(field.rawValue)")
        }
      }
    }
    .nativeCard()
  }

  @ViewBuilder private var reviewBadge: some View {
    switch viewModel.reviewState(for: field) {
    case .suggested:
      Text("Suggested")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.blue)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.blue.opacity(0.12), in: Capsule())
    case .confirmed:
      Label("Confirmed", systemImage: "checkmark.circle.fill")
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    case .edited:
      Label("Edited", systemImage: "pencil.circle.fill")
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
  }
}

private struct EntryFlowFailureView: View {
  let message: String
  @ObservedObject var viewModel: NewEntryViewModel
  @Binding var showCamera: Bool
  let retryRuntime: () -> Void
  let prepareRuntime: () async -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(viewModel.reviewSession == nil ? "Couldn’t read photo" : "Couldn’t save entry")
          .font(.largeTitle.bold())
        if let image = viewModel.selectedImage {
          image.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 340)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        Label(message, systemImage: "exclamationmark.circle")
          .foregroundStyle(.secondary)
          .nativeCard()

        if !viewModel.isModelVerified || !viewModel.isEngineReady {
          Button("Try setup again", action: retryRuntime)
            .buttonStyle(.borderedProminent).controlSize(.large)
            .accessibilityIdentifier("retryLocalSetup")
        } else if viewModel.reviewSession?.isComplete == true {
          Button("Try saving again") { viewModel.retrySave() }
            .buttonStyle(.borderedProminent).controlSize(.large)
        } else if viewModel.currentDraftURL != nil {
          Button("Try reading again") { viewModel.retryAnalysis() }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .accessibilityIdentifier("retryReading")
        }

        PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
          Label("Choose another photo", systemImage: "photo.on.rectangle")
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.canReplaceOrClear)
        .onChange(of: viewModel.selectedItem) { _, _ in
          Task {
            await viewModel.loadSelection()
            guard viewModel.currentDraftURL != nil else { return }
            await prepareRuntime()
          }
        }

        Button("Start over", role: .destructive) { viewModel.clear() }
          .frame(maxWidth: .infinity, minHeight: 44)
          .disabled(!viewModel.canReplaceOrClear)
      }
      .padding(20)
    }
    .background(Color(.systemGroupedBackground))
  }
}

private struct SavedEntryView: View {
  let entryID: UUID
  @ObservedObject var viewModel: NewEntryViewModel

  var body: some View {
    VStack(spacing: 22) {
      Spacer()
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 68))
        .foregroundStyle(.blue)
        .accessibilityHidden(true)
      Text("Entry saved").font(.largeTitle.bold())
      Text("It was added to your timeline.")
        .foregroundStyle(.secondary)
      Button("View entry") {
        NotificationCenter.default.post(name: .giTimelineShowHistory, object: entryID)
      }
      .buttonStyle(.borderedProminent).controlSize(.large)
      .accessibilityIdentifier("viewSavedEntry")
      Button("Add another") { viewModel.startAnotherEntry() }
        .buttonStyle(.bordered).controlSize(.large)
        .accessibilityIdentifier("addAnotherEntry")
      Spacer()
      Text("Prototype — not medical advice")
        .font(.footnote).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(24)
    .background(Color(.systemGroupedBackground))
  }
}

struct FirstRunInformationView: View {
  let primaryButtonTitle: String
  let completion: () -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "camera.fill")
              .font(.system(size: 30, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 64, height: 64)
              .background(Color.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("GI Timeline").font(.largeTitle.bold())
            Text("A dated record of bowel movements you can review and bring to a clinician.")
              .font(.title3).foregroundStyle(.secondary)
          }

          VStack(spacing: 22) {
            benefit("Designed to run locally", detail: "Photo observations are designed for analysis on this device.", icon: "iphone")
            benefit("Fields are filled in for you", detail: "Visible observations are proposed after you attach a photo.", icon: "wand.and.stars")
            benefit("You review before saving", detail: "Nothing proposed is recorded until every field is reviewed.", icon: "checkmark.circle")
          }

          Button(primaryButtonTitle, action: completion)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("firstRunContinue")

          Text("Prototype — not medical advice")
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
      }
      .background(Color(.systemGroupedBackground))
    }
  }

  private func benefit(_ title: String, detail: String, icon: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(.blue)
        .frame(width: 34)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
        Text(detail).font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }
}

private struct NativeActionRow: View {
  let title: String
  let systemImage: String
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: systemImage).foregroundStyle(.blue).frame(width: 28)
      Text(title).foregroundStyle(.primary)
      Spacer()
      Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
    }
    .frame(minHeight: 52)
    .padding(.horizontal, 16)
    .contentShape(Rectangle())
  }
}

private struct NativeCardModifier: ViewModifier {
  let padding: CGFloat
  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

private extension View {
  func nativeCard(padding: CGFloat = 16) -> some View { modifier(NativeCardModifier(padding: padding)) }
}

private func humanReadable(_ value: String) -> String {
  value.replacingOccurrences(of: "_", with: " ").capitalized
}

#if DEBUG
struct ModelImportSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var viewModel: NewEntryViewModel
  @State private var message: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("Developer fallback") {
          Text("Copy \(viewModel.modelArtifactFilename) to the app’s Documents/Import folder.")
          Text("Trusted descriptor SHA-256: \(viewModel.modelExpectedHashLabel)").font(.caption).textSelection(.enabled)
        }
        if let message { Text(message).foregroundStyle(.secondary) }
        Button(viewModel.isImportingModel ? "Importing…" : "Verify and import") {
          Task {
            do {
              let result = try await viewModel.importStagedModel()
              message = "Verified \(result.receipt.importedSHA256)."
            } catch { message = error.localizedDescription }
          }
        }
        .disabled(!viewModel.canImportModel)
      }
      .navigationTitle("Import model")
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }
  }
}

struct ProductBadges: View {
  let runtimeLabel: String?
  init(runtimeLabel: String? = nil) { self.runtimeLabel = runtimeLabel }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let runtimeLabel {
        Text(runtimeLabel).font(.caption.weight(.semibold)).accessibilityIdentifier("runtimeBadge")
      }
      Text("Prototype — not medical advice").font(.caption).foregroundStyle(.secondary)
    }
  }
}
#endif

struct CameraCaptureView: UIViewControllerRepresentable {
  let completion: (Data?) -> Void
  @Environment(\.dismiss) private var dismiss

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let controller = UIImagePickerController()
    controller.sourceType = .camera
    controller.cameraCaptureMode = .photo
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let parent: CameraCaptureView
    init(parent: CameraCaptureView) { self.parent = parent }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.95)
      parent.completion(data)
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.completion(nil)
      parent.dismiss()
    }
  }
}
