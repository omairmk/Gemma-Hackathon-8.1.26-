import PhotosUI
import SwiftUI
import SwiftData
import UIKit
import GITimelineCore

extension Notification.Name {
  static let giTimelineShowHistory = Notification.Name("GITimelineShowHistory")
  static let giJournalDataErased = Notification.Name("GIJournalDataErased")
}

#if INTERNAL_QWEN3_QA
/// Process-wide holder so the QA launch path never constructs more than one
/// Qwen3HybridPhotoSuggestionEngine (each construction loads the ~2GB MLX
/// snapshot) and never arms the autorun coordinator more than once, even if
/// NewEntryTab's .task body runs twice under some launch conditions.
@MainActor
private enum Qwen3QAHarnessState {
  static let engine = Qwen3HybridPhotoSuggestionEngine()
  static var autorunStarted = false
  /// Process-wide holder for the single NewEntryViewModel the QA launch path
  /// ever constructs. Without this, a root rebuild that re-runs
  /// NewEntryTab's .task body (and therefore makeViewModel()) would hand the
  /// visible view a second, independent NewEntryViewModel while the
  /// already-spawned Qwen3QAAutorunCoordinator keeps driving the first one —
  /// the coordinator's prepareImageData/attach calls would land on a view
  /// model no view ever observes.
  static var viewModel: NewEntryViewModel?
}
#endif

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
    .onReceive(NotificationCenter.default.publisher(for: .giJournalDataErased)) { _ in
      viewModel?.resetAfterJournalErase()
    }
  }

  private func makeViewModel() async -> NewEntryViewModel {
    let launchArguments = ProcessInfo.processInfo.arguments
    let runtimeConfiguration = await runtime.configurationSnapshot()
    #if DEBUG
    let configuration = launchArguments.contains("--ui-test-full-prefill-candidate")
      ? InferenceConfiguration.appStoreRawImageV12SubjectGateTuning
      : runtimeConfiguration
    #else
    let configuration = runtimeConfiguration
    #endif
    #if DEBUG
    // The UI-test store is deliberately in-memory, while unfinished drafts are
    // file-backed. Do not let a prior UI-test launch restore its file-backed
    // fixture into the next independent screenshot scenario. Production and
    // non-ephemeral Debug launches retain normal interrupted-draft recovery.
    let skipsDraftRecovery = launchArguments.contains("--ui-test-ephemeral-store")
    #else
    let skipsDraftRecovery = false
    #endif
    #if DEBUG
    if launchArguments.contains("--ui-test-fake-gemma") || launchArguments.contains("--ui-test-first-run") {
      let response = configuration.usesRawPhotoV12SubjectGateTuning
        ? "{\"schema_version\":\"gi-photo-full-prefill-v1\",\"image_usable\":true,\"retake_reason\":null,\"stool_presence\":\"stool\",\"bristol_type\":4,\"form\":\"smooth_formed\",\"mixed_form\":\"no\",\"apparent_color\":\"brown\",\"red_appearing_material\":\"yes\",\"black_tarry_appearance\":\"not_sure\"}"
        : "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":4,\"apparent_color\":\"brown\",\"form\":\"smooth_formed\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
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
      #if DEBUG
      if launchArguments.contains("--ui-test-low-quality-retake") {
        try? viewModel.prepareImageData(Self.lowQualityUITestJPEG())
      }
      #endif
      if launchArguments.contains("--ui-preview-safety") {
        viewModel.enterManualMode()
        viewModel.updateConfirmedBristolType(4)
        viewModel.updateMixedForm(.no)
        viewModel.painScore = 2
        viewModel.urgency = UrgencyLevel.none
        viewModel.strainingOrIncomplete = .no
        viewModel.redBlood = .yes
        viewModel.blackTarry = .no
        viewModel.dizziness = .no
        viewModel.severePain = .no
      }
      if !skipsDraftRecovery { viewModel.restoreUnfinishedDraftIfAvailable() }
      return viewModel
    }
    #endif

    #if INTERNAL_QWEN3_QA
    if launchArguments.contains("--qwen3-decomposed-internal-qa") {
      // If a root rebuild re-runs NewEntryTab's .task (and therefore this
      // function) after the first construction, return the same
      // NewEntryViewModel instance rather than building a second one: the
      // already-spawned Qwen3QAAutorunCoordinator (below) captured the first
      // instance, and only the first construction runs draft recovery /
      // arms the coordinator.
      if let existingViewModel = Qwen3QAHarnessState.viewModel {
        return existingViewModel
      }
      let qwen3QAEngine = Qwen3QAHarnessState.engine
      let viewModel = NewEntryViewModel(
        imageStore: ImageStore(),
        store: store,
        inference: UnavailableInferenceService(),
        photoSuggestionEngine: qwen3QAEngine,
        descriptor: nil,
        modelVerified: false,
        engineReady: false,
        configuration: configuration,
        runtimeBadgeOverride: "Internal Qwen3 QA · local bundled snapshot required",
        modelLabelOverride: "Qwen3-VL-2B internal qualification only",
        analysisTimeout: .seconds(60),
        autoAnalysisEnabled: true
      )
      if !skipsDraftRecovery { viewModel.restoreUnfinishedDraftIfAvailable() }
      Qwen3QAHarnessState.viewModel = viewModel
      if launchArguments.contains(Qwen3QAAutorunCoordinator.launchArgument), !Qwen3QAHarnessState.autorunStarted {
        Qwen3QAHarnessState.autorunStarted = true
        Task { @MainActor in
          await Qwen3QAAutorunCoordinator(viewModel: viewModel, engine: qwen3QAEngine).run()
        }
      }
      return viewModel
    }
    #endif

    guard let descriptor = ModelCatalog.normalFlowSelection else {
      let viewModel = NewEntryViewModel(
        imageStore: ImageStore(),
        store: store,
        inference: UnavailableInferenceService(),
        descriptor: nil,
        modelVerified: false,
        configuration: configuration,
        autoAnalysisEnabled: false
      )
      if !skipsDraftRecovery { viewModel.restoreUnfinishedDraftIfAvailable() }
      return viewModel
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
    if !skipsDraftRecovery { viewModel.restoreUnfinishedDraftIfAvailable() }
    return viewModel
  }

  #if DEBUG
  private static func lowQualityUITestJPEG() -> Data {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(
      size: CGSize(width: 512, height: 512),
      format: format
    ).image { context in
      UIColor.black.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
    }.jpegData(compressionQuality: 0.9) ?? Data()
  }
  #endif
}

struct NewEntryView: View {
  @Environment(\.modelContext) private var modelContext
  @ObservedObject var viewModel: NewEntryViewModel
  let runtime: ModelRuntimeCoordinator
  @AppStorage("giTimeline.didCompleteFirstRun") private var didCompleteFirstRun = false
  @State private var showInformation = false
  @State private var showCamera = false
  @State private var showNoBowelMovement = false
  @State private var noBowelMovementStatus: String?
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
        if viewModel.isDraftRecoveryBlocked {
          DraftRecoveryBlockedView(viewModel: viewModel)
        } else {
          switch viewModel.flowState {
          case .empty, .preparingPhoto:
            NewEntryStartView(
              viewModel: viewModel,
              runtime: runtime,
              showCamera: $showCamera,
              noBowelMovementStatus: noBowelMovementStatus,
              recordNoBowelMovement: { showNoBowelMovement = true }
            )
          case .confirmingSubject:
            ReadingPhotoView(viewModel: viewModel)
          case .reading:
            ReadingPhotoView(viewModel: viewModel)
          case .reviewing, .manual:
            ReviewEntryView(viewModel: viewModel, showCamera: $showCamera)
          case .saving:
            ReviewEntryView(
              viewModel: viewModel,
              saving: true,
              showCamera: $showCamera
            )
          case .saved(let entryID):
            SavedEntryView(entryID: entryID, viewModel: viewModel)
              .onAppear { noBowelMovementStatus = nil }
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
      }
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Help & About", systemImage: "questionmark.circle") { showInformation = true }
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
    .alert(
      "Unfinished draft unavailable",
      isPresented: Binding(
        get: { viewModel.draftRestorationNotice != nil },
        set: { if !$0 { viewModel.dismissDraftRestorationNotice() } }
      )
      ) {
      Button("Try Again") { viewModel.retryDraftRestoration() }
      Button("Keep local files", role: .cancel) { viewModel.dismissDraftRestorationNotice() }
      if viewModel.canDiscardUnavailableDraft {
        Button("Discard unfinished draft", role: .destructive) { viewModel.discardUnrestorableDraft() }
      }
    } message: {
      Text(viewModel.draftRestorationNotice ?? "")
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
      viewModel.retryDraftRestoration()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
      viewModel.handleAppBecameInactive()
    }
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
        #if !MANUAL_FALLBACK_RELEASE
        Task { await viewModel.prepareAutomaticRuntime(using: runtime) }
        #endif
      }
      .ignoresSafeArea()
    }
    .sheet(isPresented: $showNoBowelMovement) {
      NoBowelMovementSheet { date, recorded in
        noBowelMovementStatus = recorded
          ? "No bowel movement recorded for \(date.formatted(date: .abbreviated, time: .omitted))."
          : "No-bowel-movement marker removed for \(date.formatted(date: .abbreviated, time: .omitted))."
      }
      .modelContext(modelContext)
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
  let noBowelMovementStatus: String?
  let recordNoBowelMovement: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("Add to your journal")
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)

        VStack(alignment: .leading, spacing: 8) {
          Text(viewModel.usesPublicManualFallback
            ? "Attach a photo to a manual entry, or continue without one. Complete the entry, then save it."
            : "Add a photo for an on-device suggestion, or enter details yourself. Review the entry, then save it.")
            .font(.subheadline)
            .foregroundStyle(GIJournalTheme.secondaryText)
        }
        .nativeCard()

        VStack(alignment: .leading, spacing: 12) {
          Button {
            showCamera = true
          } label: {
            NativeActionRow(title: "Take photo", systemImage: "camera")
          }
          .buttonStyle(.plain)
          .disabled(!viewModel.canReplaceOrClear || !UIImagePickerController.isSourceTypeAvailable(.camera))
          .accessibilityIdentifier("takePhoto")
          Divider().padding(.leading, 44)
          PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
            NativeActionRow(title: "Choose from library", systemImage: "photo.on.rectangle")
          }
          .buttonStyle(.plain)
          .disabled(!viewModel.canReplaceOrClear)
          .accessibilityIdentifier("choosePhoto")
          .onChange(of: viewModel.selectedItem) { _, _ in
            Task {
              await viewModel.loadSelection()
              #if !MANUAL_FALLBACK_RELEASE
              guard viewModel.currentDraftURL != nil else { return }
              await viewModel.prepareAutomaticRuntime(using: runtime)
              #endif
            }
          }
        }
        .giJournalCard(padding: 0)

        Text(viewModel.usesPublicManualFallback
          ? "For a clearer journal photo, use even light and keep the full bowel movement in frame."
          : "For a clearer suggestion, use even light and keep the full bowel movement in frame.")
          .font(.footnote)
          .foregroundStyle(GIJournalTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)

        Button("Enter details without a photo") { viewModel.enterManualMode() }
          .font(.body.weight(.semibold))
          .foregroundStyle(GIJournalTheme.primary)
          .frame(minHeight: 44)
          .disabled(!viewModel.canReplaceOrClear)
          .accessibilityIdentifier("logWithoutPhoto")

        Button(action: recordNoBowelMovement) {
          Label("Record no bowel movement", systemImage: "calendar.badge.minus")
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(GIJournalSecondaryButtonStyle())
        .disabled(!viewModel.canReplaceOrClear)
        .accessibilityIdentifier("recordNoBowelMovement")

        if let noBowelMovementStatus {
          Label(noBowelMovementStatus, systemImage: "checkmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(GIJournalTheme.primary)
            .accessibilityIdentifier("noBowelMovementStatus")
        }

        if case .preparingPhoto = viewModel.flowState {
          HStack(spacing: 12) {
            ProgressView()
            Text("Preparing photo…")
              .foregroundStyle(GIJournalTheme.secondaryText)
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

        Text("GI Journal records observations for you to review with your care team.")
          .font(.footnote)
          .foregroundStyle(GIJournalTheme.secondaryText)
          .frame(maxWidth: .infinity)
      }
      .padding(20)
    }
    .background(GIJournalTheme.canvas)
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

private struct NoBowelMovementSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \DailyCompletionRecord.dayStart, order: .reverse) private var completions: [DailyCompletionRecord]
  @State private var date = Date()
  @State private var errorMessage: String?
  let completion: (Date, Bool) -> Void

  private var existingMarker: DailyCompletionRecord? {
    let key = TreatmentResponseCalculator().dayKey(for: date)
    return completions.first { $0.dayKey == key && $0.answer == .noBowelMovement }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
        } header: {
          Text("No bowel movement")
        } footer: {
          Text("Add a dated journal marker only when there was no bowel movement that day.")
        }

        Section {
          if existingMarker == nil {
            Button("Save marker") { save(recorded: true) }
              .frame(maxWidth: .infinity)
              .accessibilityIdentifier("saveNoBowelMovement")
          } else {
            Label("No bowel movement is recorded for this date.", systemImage: "checkmark.circle.fill")
              .foregroundStyle(GIJournalTheme.primary)
            Button("Remove marker", role: .destructive) { save(recorded: false) }
              .accessibilityIdentifier("removeNoBowelMovement")
          }
        }
      }
      .navigationTitle("No bowel movement")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
      .alert("Could not update journal", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private func save(recorded: Bool) {
    do {
      try ClinicalTimelineStore(context: modelContext).setNoBowelMovement(recorded, for: date)
      completion(date, recorded)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct DraftRecoveryBlockedView: View {
  @ObservedObject var viewModel: NewEntryViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Image(systemName: "lock.fill")
        .font(.system(size: 38))
        .foregroundStyle(GIJournalTheme.primary)
        .accessibilityHidden(true)
      Text("Unfinished draft needs attention")
        .font(.title2.bold())
        .accessibilityAddTraits(.isHeader)
      Text(viewModel.draftRestorationNotice ?? "GI Journal kept an unfinished local draft unchanged. Reopen or explicitly discard it before starting another entry.")
        .foregroundStyle(GIJournalTheme.secondaryText)
      Button("Try reopening draft") { viewModel.retryDraftRestoration() }
        .buttonStyle(GIJournalPrimaryButtonStyle())
        .accessibilityIdentifier("retryUnfinishedDraft")
      if viewModel.canDiscardUnavailableDraft {
        Button("Discard unfinished draft", role: .destructive) {
          viewModel.discardUnrestorableDraft()
        }
        .accessibilityIdentifier("discardUnavailableDraft")
      }
      Spacer()
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(GIJournalTheme.canvas)
  }
}

private struct ReadingPhotoView: View {
  @ObservedObject var viewModel: NewEntryViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var scanPosition: CGFloat = -0.2

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .firstTextBaseline) {
          Text("Preparing a suggestion…")
            .font(.largeTitle.bold())
            .accessibilityAddTraits(.isHeader)
          Spacer()
          Button("Cancel") { viewModel.cancelReading() }
            .disabled(!viewModel.canReplaceOrClear && !viewModel.isBusy)
            .accessibilityIdentifier("cancelReading")
        }

        Text("This may take a moment. Keep GI Journal open.")
          .font(.subheadline)
          .foregroundStyle(GIJournalTheme.secondaryText)

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
          Label("Preparing a suggestion", systemImage: "sparkles")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preparing a suggestion")
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
        .accessibilityHidden(true)
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
  @Binding var showCamera: Bool
  @State private var helpRoute: GIJournalHelpRoute?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Review your entry")
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)

        if !viewModel.hasAnalysis,
          viewModel.currentDraftURL != nil,
          let fallbackMessage = viewModel.statusMessage
        {
          Label(fallbackMessage, systemImage: "pencil.and.list.clipboard")
            .font(.subheadline)
            .foregroundStyle(GIJournalTheme.secondaryText)
            .giJournalCard()
            .accessibilityIdentifier("manualSuggestionFallback")
        }

        if let recommendation = viewModel.photoQualityRecommendation,
          recommendation.severity == .borderline
        {
          VStack(alignment: .leading, spacing: 12) {
            Label("A clearer photo may help", systemImage: "camera.metering.center.weighted")
              .font(.headline)
            Text(recommendation.message)
              .font(.subheadline)
              .foregroundStyle(GIJournalTheme.secondaryText)
            HStack {
              Button("Take another photo") { showCamera = true }
                .buttonStyle(.bordered)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                .accessibilityIdentifier("borderlineTakeAnotherPhoto")
              Button("Keep this photo") { viewModel.keepBorderlinePhoto() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("keepBorderlinePhoto")
            }
          }
          .giJournalCard()
          .accessibilityIdentifier("borderlinePhotoQualityRecommendation")
        }

        if let image = viewModel.selectedImage {
          ZStack(alignment: .bottomLeading) {
            image.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 320)
            Text(viewModel.capturedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 10)
              .padding(.vertical, 7)
              .background(.regularMaterial, in: Capsule())
              .padding(12)
          }
          .frame(maxWidth: .infinity)
          .background(GIJournalTheme.surface)
          .clipShape(RoundedRectangle(cornerRadius: GIJournalTheme.cornerRadius, style: .continuous))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Photo attached for review")
          .accessibilityIdentifier("reviewPhoto")
        }

        if viewModel.hasAnalysis {
          GIJournalSuggestionDisclosure(
            source: viewModel.analysisSource.rawValue,
            helpRoute: $helpRoute
          )
          .accessibilityIdentifier("photoSuggestionDisclosure")
        }

        DatePicker("Date and time", selection: $viewModel.capturedAt)
          .giJournalCard()

        VStack(alignment: .leading, spacing: 14) {
          HStack {
            Text(viewModel.hasAnalysis
              ? "Suggested from this photo — review and change anything that is not right."
              : "Enter details")
              .font(.title2.bold())
            Spacer()
          }
          if viewModel.hasAnalysis {
            Text(viewModel.usesProviderNeutralPhotoReview
              ? "On-device photo analysis prefilled every photo-observable value below. Change anything that is not right; the one save action adopts all currently displayed values."
              : "Photo suggestions prefilled every photo-observable value below. Change anything that is not right; the one save action adopts all currently displayed values.")
              .font(.footnote)
              .foregroundStyle(GIJournalTheme.secondaryText)
              .accessibilityIdentifier("suggestionsNotYetConfirmed")
          }

          if viewModel.usesPublicManualFallback
            || viewModel.usesProviderNeutralManualPhotoReview
          {
            Picker(viewModel.usesPublicManualFallback
              ? "Entry subject" : "Photo subject", selection: Binding(
              get: { viewModel.confirmedStoolPresence },
              set: { viewModel.updateStoolPresence($0) }
            )) {
              Text("Choose").tag(nil as StoolPresence?)
              Text("Bowel movement").tag(StoolPresence.stool as StoolPresence?)
              Text("Different subject").tag(StoolPresence.nonStool as StoolPresence?)
              Text("Not sure").tag(StoolPresence.uncertain as StoolPresence?)
            }
            .accessibilityIdentifier(viewModel.usesPublicManualFallback
              ? "manualEntrySubject" : "providerNeutralManualSubject")
            .accessibilityValue(
              Self.stoolPresenceLabel(viewModel.confirmedStoolPresence)
            )
            .accessibilityHint(viewModel.usesPublicManualFallback
              ? "Choose what this journal entry records."
              : "Choose what the retained photo appears to show.")
          } else if viewModel.hasAnalysis
            && (viewModel.usesFullPrefillCandidate
              || viewModel.usesProviderNeutralPhotoReview)
          {
            Picker("Photo subject", selection: Binding(
              get: { viewModel.confirmedStoolPresence },
              set: { viewModel.updateStoolPresence($0) }
            )) {
              Text("Bowel movement").tag(StoolPresence.stool as StoolPresence?)
              Text("Different subject").tag(StoolPresence.nonStool as StoolPresence?)
              Text("Not sure").tag(StoolPresence.uncertain as StoolPresence?)
            }
            .accessibilityIdentifier("stoolPresenceSuggestion")
            .accessibilityHint("Editable on-device suggestion for what the photo appears to show.")
            aiReadHint("subject")
          }

          if viewModel.usesPublicManualFallback
            || viewModel.usesProviderNeutralManualPhotoReview
          {
            Picker("Apparent color", selection: Binding(
              get: { viewModel.apparentColor },
              set: { viewModel.updateApparentColor($0) }
            )) {
              Text("Choose").tag(nil as String?)
              ForEach(Self.apparentColors, id: \.self) { value in
                Text(Self.apparentColorLabel(value)).tag(value as String?)
              }
            }
            .accessibilityIdentifier(viewModel.usesPublicManualFallback
              ? "manualApparentColor" : "providerNeutralManualApparentColor")
            .accessibilityValue(
              viewModel.apparentColor.map(Self.apparentColorLabel) ?? "Choose"
            )
            .accessibilityHint("Choose the closest visible color, or Unable to assess.")
          } else if viewModel.hasAnalysis, let color = viewModel.apparentColor {
            Picker("Apparent color", selection: Binding(
              get: { color },
              set: { viewModel.updateApparentColor($0) }
            )) {
              ForEach(Self.apparentColors, id: \.self) { value in
                Text(Self.apparentColorLabel(value)).tag(value)
              }
            }
            .accessibilityIdentifier("apparentColor")
            .accessibilityHint("Suggested from this photo and not yet confirmed. Change it if needed before confirming the complete entry.")
            aiReadHint("apparentColor")
          }

          if viewModel.currentDraftURL != nil {
            GIJournalBooleanRows(
              title: "Was this photo clear enough to use as a reference?",
              helper: "Choose No if it is hidden, too dark, too blurry, or too small to compare. You can still enter the stool type yourself.",
              selection: Binding(
                get: { viewModel.confirmedPhotoUsable },
                set: { viewModel.updateConfirmedPhotoUsable($0) }
              ),
              accessibilityIdentifierPrefix:
                viewModel.usesProviderNeutralManualPhotoReview
                  ? "providerNeutralManualPhotoUsability" : nil
            )
            .accessibilityHint(viewModel.hasAnalysis
              ? "Suggested from this photo and not yet confirmed."
              : "Choose an answer for the attached photo.")
          } else if viewModel.usesPublicManualFallback {
            Text("No photo attached. Photo usability and a retake recommendation do not apply.")
              .font(.footnote)
              .foregroundStyle(GIJournalTheme.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("manualNoPhotoUsability")
          }

          if (viewModel.usesPublicManualFallback
              && viewModel.currentDraftURL != nil)
            || viewModel.usesProviderNeutralManualPhotoReview
            || (viewModel.hasAnalysis
              && (viewModel.usesFullPrefillCandidate
                || viewModel.usesProviderNeutralPhotoReview))
          {
            Picker("Retake recommendation", selection: Binding(
              get: { viewModel.confirmedRetakeReason },
              set: { viewModel.updateRetakeReason($0) }
            )) {
              Text("No retake recommended").tag(nil as PhotoRetakeReason?)
              Text("Too dark").tag(PhotoRetakeReason.tooDark as PhotoRetakeReason?)
              Text("Blurred").tag(PhotoRetakeReason.blurred as PhotoRetakeReason?)
              Text("Obstructed").tag(PhotoRetakeReason.obstructed as PhotoRetakeReason?)
              Text("Too far away").tag(PhotoRetakeReason.tooFar as PhotoRetakeReason?)
              Text("Glare").tag(PhotoRetakeReason.glare as PhotoRetakeReason?)
              Text("Other technical issue").tag(PhotoRetakeReason.other as PhotoRetakeReason?)
            }
            .accessibilityIdentifier(viewModel.usesPublicManualFallback
              ? "manualRetakeReason"
              : (viewModel.usesProviderNeutralManualPhotoReview
                ? "providerNeutralManualRetakeReason"
                : "retakeReasonSuggestion"))
            .accessibilityValue(
              Self.retakeReasonLabel(viewModel.confirmedRetakeReason)
            )
            .accessibilityHint(viewModel.usesPublicManualFallback
              ? "Choose a technical reason only when the attached photo is not clear enough."
              : (viewModel.usesProviderNeutralManualPhotoReview
                ? "Edit the retained photo's technical retake reason."
                : "Editable on-device technical retake recommendation."))
          }

          GIJournalStoolTypePicker(
            selection: Binding(
              get: { viewModel.confirmedBristolType },
              set: { viewModel.updateConfirmedBristolType($0) }
            ),
            helpRoute: $helpRoute,
            suggestedType: viewModel.suggestedBristolType
          )
          .accessibilityHint(viewModel.hasAnalysis
            ? "Suggested from this photo and not yet confirmed."
            : "Choose the closest stool type, including Unable to tell.")
          aiReadHint("bristol")

          if viewModel.usesPublicManualFallback
            || viewModel.usesProviderNeutralManualPhotoReview
            || (viewModel.hasAnalysis
              && (viewModel.usesFullPrefillCandidate
                || viewModel.usesProviderNeutralPhotoReview))
          {
            Picker("Form", selection: Binding(
              get: { viewModel.confirmedForm },
              set: { viewModel.updateConfirmedForm($0) }
            )) {
              ForEach(Self.forms, id: \.self) { form in
                Text(Self.formLabel(form)).tag(form as String?)
              }
            }
            .accessibilityIdentifier(viewModel.usesPublicManualFallback
              ? "manualForm"
              : (viewModel.usesProviderNeutralManualPhotoReview
                ? "providerNeutralManualForm" : "formSuggestion"))
            .accessibilityValue(
              viewModel.confirmedForm.map(Self.formLabel) ?? "Choose"
            )
            .accessibilityHint(viewModel.usesPublicManualFallback
              ? "Choose the closest form. Changing it keeps Bristol and mixed form consistent."
              : (viewModel.usesProviderNeutralManualPhotoReview
                ? "Choose the closest form. Changing it keeps Bristol and mixed form consistent."
                : "Editable on-device form suggestion. Changing it keeps Bristol and mixed form consistent."))
          }

          GIJournalClinicalTriStateRows(
            title: "Did this bowel movement include more than one clearly different stool type?",
            helper: "For example, hard pieces and loose stool in the same bowel movement.",
            accessibilityIdentifierPrefix: "mixedForm",
            selection: Binding(
              get: { viewModel.mixedForm },
              set: { viewModel.updateMixedForm($0) }
            )
          )
          .accessibilityHint(viewModel.hasAnalysis
            ? "Suggested from this photo and not yet confirmed."
            : "Choose Yes, No, or Not sure.")
          aiReadHint("mixedForm")

          if viewModel.hasAnalysis
            && (viewModel.usesFullPrefillCandidate
              || viewModel.usesProviderNeutralPhotoReview)
          {
            symptomChoices(
              "Possible red/blood-like appearance",
              helper: "Appearance-only AI suggestion. It does not confirm blood or bleeding. Review or change Yes, No, or Not sure before the single final confirmation.",
              accessibilityName: "Possible red or blood-like appearance",
              identifierPrefix: "redMaterial",
              accessibilityHint: "Editable on-device appearance suggestion. Choose Yes, No, or Not sure.",
              value: $viewModel.redBlood
            )
            aiReadHint("redMaterial")
            if viewModel.usesProviderNeutralPhotoReview {
              symptomChoices(
                "Possible unusually black appearance",
                helper: "Appearance-only AI suggestion. It does not confirm melena or a diagnosis. Review or change Yes, No, or Not sure before the single final confirmation.",
                accessibilityName: "Possible unusually black appearance",
                identifierPrefix: "blackAppearance",
                accessibilityHint: "Editable on-device appearance suggestion. Choose Yes, No, or Not sure.",
                value: $viewModel.blackAppearance
              )
              aiReadHint("blackAppearance")
              symptomChoices(
                "Possible tar-like appearance",
                helper: "Appearance-only AI suggestion. It does not confirm physical stickiness, melena, or a diagnosis. Review or change Yes, No, or Not sure before the single final confirmation.",
                accessibilityName: "Possible tar-like appearance",
                identifierPrefix: "blackTarry",
                accessibilityHint: "Editable on-device appearance suggestion. Choose Yes, No, or Not sure.",
                value: $viewModel.blackTarry
              )
              aiReadHint("blackTarry")
            } else {
              symptomChoices(
                "Possible black/tar-like appearance",
                helper: "Appearance-only AI suggestion. It does not confirm melena or a diagnosis. Review or change Yes, No, or Not sure before the single final confirmation.",
                accessibilityName: "Possible black or tar-like appearance",
                identifierPrefix: "blackTarry",
                accessibilityHint: "Editable on-device appearance suggestion. Choose Yes, No, or Not sure.",
                value: $viewModel.blackTarry
              )
              aiReadHint("blackTarry")
            }
          }
        }
        .giJournalCard()

        VStack(alignment: .leading, spacing: 16) {
          Text("Details you noticed").font(.title2.bold())
          GIJournalUrgencyRows(selection: $viewModel.urgency, helpRoute: $helpRoute)
          GIJournalPainControl(score: $viewModel.painScore)
          if !viewModel.hasAnalysis
            || (!viewModel.usesFullPrefillCandidate
              && !viewModel.usesProviderNeutralPhotoReview)
          {
            symptomChoices(
              "Possible red/blood-like appearance",
              helper: viewModel.usesPublicManualFallback
                ? "This records an appearance only and does not confirm blood or bleeding."
                : (viewModel.usesProviderNeutralManualPhotoReview
                  ? "Record what the photo appears to show. This does not confirm blood or bleeding."
                  : viewModel.redSuggestionHint),
              accessibilityName: "Possible red or blood-like appearance",
              identifierPrefix: "redMaterial",
              accessibilityHint: "Choose Yes, No, or Not sure.",
              value: $viewModel.redBlood
            )
            if viewModel.usesPublicManualFallback
              || viewModel.usesProviderNeutralManualPhotoReview
            {
              symptomChoices(
                "Possible unusually black appearance",
                helper: viewModel.usesPublicManualFallback
                  ? "This records visible color only and does not confirm melena or a diagnosis."
                  : "Record what the photo appears to show. This does not confirm melena or a diagnosis.",
                accessibilityName: "Possible unusually black appearance",
                identifierPrefix: "blackAppearance",
                accessibilityHint: "Choose Yes, No, or Not sure.",
                value: $viewModel.blackAppearance
              )
              symptomChoices(
                "Possible tar-like appearance",
                helper: viewModel.usesPublicManualFallback
                  ? "This records a glossy, smeared, coating-like, or tar-like look only; it does not confirm physical stickiness or melena."
                  : "Record a glossy, smeared, coating-like, or tar-like look only; this does not confirm physical stickiness or melena.",
                accessibilityName: "Possible tar-like appearance",
                identifierPrefix: "blackTarry",
                accessibilityHint: "Choose Yes, No, or Not sure.",
                value: $viewModel.blackTarry
              )
            } else {
              symptomChoices(
                "Possible black/tar-like appearance",
                helper: viewModel.blackSuggestionHint,
                accessibilityName: "Possible black or tar-like appearance",
                identifierPrefix: "blackTarry",
                accessibilityHint: "Choose Yes, No, or Not sure.",
                value: $viewModel.blackTarry
              )
            }
          }

          switch ClinicalValidation.conditionalQuestion(for: viewModel.confirmedBristolType) {
          case .strainingOrIncomplete:
            GIJournalClinicalTriStateRows(title: "Did you strain a lot or still feel you needed to go?", accessibilityIdentifierPrefix: "strainingOrIncomplete", selection: $viewModel.strainingOrIncomplete)
          case .leakageOrAccident:
            GIJournalClinicalTriStateRows(title: "Was there leakage or loss of control?", accessibilityIdentifierPrefix: "leakageOrAccident", selection: $viewModel.leakageOrAccident)
          case nil:
            EmptyView()
          }

          TextField("Anything else you want to remember? (optional)", text: $viewModel.note, axis: .vertical)
            .lineLimit(3...6)
            .accessibilityIdentifier("noteField")
            .onChange(of: viewModel.note) { _, value in
              if value.count > 500 { viewModel.note = String(value.prefix(500)) }
            }
        }
        .giJournalCard()

      }
      .padding(20)
      .padding(.bottom, 84)
    }
    .background(GIJournalTheme.canvas)
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 6) {
        Button(
          saving ? "Saving…" : (viewModel.usesPublicManualFallback
            ? "Save entry"
            : (viewModel.hasAnalysis
              ? "Accept all suggestions and save"
              : "Save entry"))
        ) { viewModel.save() }
          .buttonStyle(GIJournalPrimaryButtonStyle())
          .disabled(!viewModel.canSave || saving)
          .accessibilityIdentifier("saveEntry")
          .accessibilityHint(viewModel.usesPublicManualFallback
            ? "Saves the complete manual entry."
            : (viewModel.hasAnalysis
              ? "Confirms the complete displayed entry once and saves it."
              : "Saves the complete entry."))
        if !viewModel.canSave {
          Text(viewModel.usesPublicManualFallback
            ? "Complete the entry subject, Bristol or unable-to-assess choice, form, mixed form, apparent color, and the red, unusual-black, and tar-like appearance answers. If a photo is attached, also review its usability and retake recommendation."
            : "Review the subject, photo usability, Bristol, form, mixed form, color, and every appearance answer before saving.")
            .font(.body)
            .foregroundStyle(GIJournalTheme.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(viewModel.usesPublicManualFallback
              ? "Save disabled. Complete the required manual entry fields before saving."
              : "Save disabled. Complete the required review answers before saving.")
            .accessibilityIdentifier("saveEntryDisabledReason")
        }
      }
      .padding(.horizontal, GIJournalTheme.pageInset)
      .padding(.top, 10)
      .padding(.bottom, 8)
      .background {
        GIJournalTheme.surface
          .overlay(alignment: .top) {
            Rectangle()
              .fill(GIJournalTheme.border)
              .frame(height: 1)
          }
      }
    }
    .sheet(item: $helpRoute) { GIJournalHelpSheet(route: $0) }
  }

  private static let apparentColors = [
    "brown", "light_brown", "dark_brown", "green", "yellow", "orange",
    "red_appearing", "black_appearing", "pale_or_clay_appearing", "mixed", "unable_to_assess",
  ]

  private static let forms = [
    "hard_lumps", "lumpy_formed", "cracked_formed", "smooth_formed",
    "soft_blobs", "mushy", "watery", "mixed", "unable_to_assess",
  ]

  private static func formLabel(_ value: String) -> String {
    value == "unable_to_assess"
      ? "Unable to tell"
      : value.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private static func stoolPresenceLabel(_ value: StoolPresence?) -> String {
    switch value {
    case .stool: "Bowel movement"
    case .nonStool: "Different subject"
    case .uncertain: "Not sure"
    case nil: "Choose"
    }
  }

  private static func retakeReasonLabel(_ value: PhotoRetakeReason?) -> String {
    value?.displayName ?? "No retake recommended"
  }

  private static func apparentColorLabel(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: " ").capitalized
  }

  /// Stable AI-suggestion text records the model's original answer while the
  /// adjacent control stays editable. Provider-neutral V2 hints are receipt-
  /// derived; the legacy internal full-prefill candidate uses the same exact
  /// appearance-only copy directly from its authenticated suggestion.
  @ViewBuilder private func aiReadHint(_ key: String) -> some View {
    let hint: String? = if viewModel.usesProviderNeutralPhotoReview {
      viewModel.aiReadHints[key]
    } else if viewModel.usesFullPrefillCandidate {
      switch key {
      case "redMaterial": viewModel.redSuggestionHint
      case "blackTarry": viewModel.blackSuggestionHint
      default: nil
      }
    } else {
      nil
    }
    if let hint {
      Text(hint)
        .font(.footnote)
        .foregroundStyle(GIJournalTheme.secondaryText)
        .accessibilityIdentifier("aiReadHint_\(key)")
    }
  }

  private func symptomChoices(
    _ title: String,
    helper: String? = nil,
    accessibilityName: String,
    identifierPrefix: String,
    accessibilityHint: String,
    value: Binding<SymptomFlag?>
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.headline)
      if let helper {
        Text(helper).font(.footnote).foregroundStyle(GIJournalTheme.secondaryText)
      }
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: 8) {
          symptomChoiceButtons(
            value,
            accessibilityName: accessibilityName,
            identifierPrefix: identifierPrefix,
            accessibilityHint: accessibilityHint
          )
        }
      } else {
        HStack(spacing: 8) {
          symptomChoiceButtons(
            value,
            accessibilityName: accessibilityName,
            identifierPrefix: identifierPrefix,
            accessibilityHint: accessibilityHint
          )
        }
      }
    }
  }

  @ViewBuilder private func symptomChoiceButtons(
    _ value: Binding<SymptomFlag?>,
    accessibilityName: String,
    identifierPrefix: String,
    accessibilityHint: String
  ) -> some View {
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
      .accessibilityIdentifier("\(identifierPrefix)_\(option.rawValue)")
      .accessibilityLabel("\(accessibilityName), \(option == .unsure ? "Not sure" : option.rawValue.capitalized)")
      .accessibilityValue(value.wrappedValue == option ? "Selected" : "Not selected")
      .accessibilityHint(accessibilityHint)
    }
  }
}

private struct EntryFlowFailureView: View {
  let message: String
  @ObservedObject var viewModel: NewEntryViewModel
  @Binding var showCamera: Bool
  let retryRuntime: () -> Void
  let prepareRuntime: () async -> Void

  private var hardQualityRecommendation: PhotoQualityRecommendation? {
    guard let recommendation = viewModel.photoQualityRecommendation,
      recommendation.severity == .hard
    else { return nil }
    return recommendation
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(hardQualityRecommendation != nil
          ? "A clearer photo may help"
          : (viewModel.canSave ? "Couldn’t save entry" : "We couldn’t prepare a suggestion"))
          .font(.largeTitle.bold())
        if let image = viewModel.selectedImage {
          image.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 340)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityLabel("Photo attached to this unsaved entry")
            .accessibilityIdentifier(hardQualityRecommendation == nil
              ? "failedEntryPhoto" : "lowQualityRetainedPhoto")
        }
        Text(hardQualityRecommendation?.message
          ?? (viewModel.canSave
            ? message
            : "Your photo is still here. Choose the closest stool type yourself to continue."))
          .foregroundStyle(GIJournalTheme.secondaryText)
          .giJournalCard()
          .accessibilityIdentifier(hardQualityRecommendation == nil
            ? "entryFlowFailureMessage" : "lowPhotoQualityRecommendation")

        if hardQualityRecommendation != nil {
          Button("Take another photo") { showCamera = true }
            .buttonStyle(GIJournalPrimaryButtonStyle())
            .disabled(
              !viewModel.canReplaceOrClear
                || !UIImagePickerController.isSourceTypeAvailable(.camera)
            )
            .accessibilityIdentifier("takeAnotherLowQualityPhoto")

          Button("Keep photo and continue manually") {
            viewModel.keepLowQualityPhotoAndContinueManually()
          }
          .buttonStyle(.bordered)
          .frame(maxWidth: .infinity, minHeight: 44)
          .accessibilityIdentifier("keepLowQualityPhotoManual")
        } else if viewModel.canSave {
          Button("Try saving again") { viewModel.retrySave() }
            .buttonStyle(.borderedProminent).controlSize(.large)
        } else if viewModel.requiresFullAppRestart {
          Text("Photo suggestions are unavailable until you fully quit and reopen GI Journal. You can still enter this entry manually.")
            .font(.subheadline)
            .foregroundStyle(GIJournalTheme.secondaryText)
            .giJournalCard()
            .accessibilityIdentifier("restartAppForPhotoSuggestions")
        } else if !viewModel.isModelVerified || !viewModel.isEngineReady {
          Button("Try setup again", action: retryRuntime)
            .buttonStyle(.borderedProminent).controlSize(.large)
            .accessibilityIdentifier("retryLocalSetup")
        } else if viewModel.currentDraftURL != nil {
          Button("Try reading again") { viewModel.retryAnalysis() }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .accessibilityIdentifier("retryReading")
        }

        if hardQualityRecommendation == nil,
          !viewModel.canSave,
          viewModel.reviewSession == nil
        {
          Button("Enter details manually") { viewModel.enterManualMode() }
            .buttonStyle(GIJournalPrimaryButtonStyle())
            .accessibilityIdentifier("manualAfterSuggestionFailure")
        }

        PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
          Label(
            hardQualityRecommendation == nil
              ? "Choose another photo"
              : "Choose another photo from library",
            systemImage: "photo.on.rectangle"
          )
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
    .background(GIJournalTheme.canvas)
  }
}

private struct SavedEntryView: View {
  let entryID: UUID
  @ObservedObject var viewModel: NewEntryViewModel
  @AccessibilityFocusState private var savedHeadingIsFocused: Bool

  var body: some View {
    VStack(spacing: 22) {
      Spacer()
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 68))
        .foregroundStyle(GIJournalTheme.primary)
        .accessibilityHidden(true)
      Text("Entry saved")
        .font(.largeTitle.bold())
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($savedHeadingIsFocused)
      Text("It was added to your journal.")
        .foregroundStyle(GIJournalTheme.secondaryText)
      if viewModel.savedSafetyGuidance == .contactClinician {
        Text(SafetyRules.message)
          .font(.body)
          .foregroundStyle(GIJournalTheme.text)
          .giJournalCard()
          .accessibilityIdentifier("confirmedSafetyGuidance")
      } else if viewModel.savedSafetyGuidance == .uncertain {
        Text(SafetyRules.uncertainMessage)
          .font(.body)
          .foregroundStyle(GIJournalTheme.text)
          .giJournalCard()
          .accessibilityIdentifier("confirmedSafetyGuidance")
      }
      Button("View entry") {
        NotificationCenter.default.post(name: .giTimelineShowHistory, object: entryID)
      }
      .buttonStyle(.borderedProminent).controlSize(.large)
      .accessibilityIdentifier("viewSavedEntry")
      Button("Add another") { viewModel.startAnotherEntry() }
        .buttonStyle(.bordered).controlSize(.large)
        .accessibilityIdentifier("addAnotherEntry")
      Spacer()
      Text("This journal records observations you reviewed. It does not diagnose a condition or recommend treatment.")
        .font(.footnote).foregroundStyle(GIJournalTheme.secondaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(24)
    .background(GIJournalTheme.canvas)
    .onAppear {
      DispatchQueue.main.async { savedHeadingIsFocused = true }
    }
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
              .foregroundStyle(GIJournalTheme.surface)
              .frame(width: 64, height: 64)
              .background(GIJournalTheme.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
              .accessibilityHidden(true)
            Text("GI Journal")
              .font(.largeTitle.bold())
              .accessibilityAddTraits(.isHeader)
            Text("Keep a simple GI journal to review with your gastroenterologist.")
              .font(.title3).foregroundStyle(GIJournalTheme.secondaryText)
          }

          VStack(spacing: 22) {
            #if MANUAL_FALLBACK_RELEASE
            benefit("Private and works offline", detail: "After installation, journal entry, camera photos, editing, and PDF creation work without a developer server. Apple Photos may need a connection before it can provide an iCloud-only item you select; the original asset remains governed by Photos and iCloud settings. There is no developer account, journal server, sync, analytics, or advertising. GI Journal requests backup exclusion for its app-created journal copy; iOS controls backup behavior.", icon: "lock.shield")
            #else
            benefit("Private and works offline", detail: "After installation, journal entry, camera photos, and suggestions for photos already available to this app work without an internet connection. Apple Photos may need a connection before it can provide an iCloud-only item you select; the original asset remains governed by Photos and iCloud settings. There is no developer account, journal server, sync, analytics, or advertising. GI Journal requests backup exclusion for its app-created journal copy; iOS controls backup behavior.", icon: "lock.shield")
            #endif
            benefit("Saved through normal restarts", detail: AppFolders.restartRetentionLine, icon: "arrow.clockwise.circle")
            benefit("Saved on this iPhone", detail: AppFolders.dataLossLine, icon: "iphone")
            #if MANUAL_FALLBACK_RELEASE
            benefit("Photos are optional", detail: "Attach a photo to a manual entry or continue without one. This public version stores the photo with the entry but does not analyze it or use it to prefill fields.", icon: "camera")
            benefit("You enter; you save", detail: "Complete the entry yourself, review the displayed values, and save once.", icon: "checkmark.circle")
            #else
            benefit("Photo suggestions are optional", detail: "You can add a photo for a suggestion or enter the details yourself.", icon: "camera")
            benefit("Photo suggestions; you confirm", detail: "Review the complete entry and change anything needed before one confirmation saves it.", icon: "checkmark.circle")
            #endif
            benefit("Made for conversations", detail: "Your reviewed record can help you discuss patterns with a clinician.", icon: "text.book.closed")
          }

          Button(primaryButtonTitle, action: completion)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("firstRunContinue")

          Text("GI Journal is for documentation and does not replace guidance from your care team.")
            .font(.footnote).foregroundStyle(GIJournalTheme.secondaryText)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
      }
      .background(GIJournalTheme.canvas)
    }
  }

  private func benefit(_ title: String, detail: String, icon: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(GIJournalTheme.primary)
        .frame(width: 34)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
        Text(detail).font(.subheadline).foregroundStyle(GIJournalTheme.secondaryText)
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
