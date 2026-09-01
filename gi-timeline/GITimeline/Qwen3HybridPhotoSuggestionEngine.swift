#if INTERNAL_QWEN3_QA
import CoreGraphics
import CoreImage
import CryptoKit
import Darwin
import Foundation
import GITimelineCore
import ImageIO
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import os
import Tokenizers
import UIKit

/// An internal qualification profile, selected only by an exact launch
/// argument. The 1024-pixel route is an explicit QA experiment; 512 remains
/// the baseline and the 256-pixel route remains an observability/resource
/// fallback whose output is deliberately fused as unqualified.
private enum Qwen3InternalQAPreprocessProfile: String, Sendable {
  case pixels1024 = "1024"
  case pixels512 = "512"
  case pixels256 = "256"

  static let launchArgumentPrefix = "--qwen3-decomposed-preprocess="

  static func selected(from arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
    let overrides = arguments.filter { $0.hasPrefix(launchArgumentPrefix) }
    guard overrides.count <= 1 else { return nil }
    guard let override = overrides.first else { return .pixels512 }
    switch override {
    case "--qwen3-decomposed-preprocess=1024": return .pixels1024
    case "--qwen3-decomposed-preprocess=512": return .pixels512
    case "--qwen3-decomposed-preprocess=256": return .pixels256
    default: return nil
    }
  }

  var pixelEdge: Int {
    switch self {
    case .pixels1024: return 1024
    case .pixels512: return 512
    case .pixels256: return 256
    }
  }

  var pixelBudget: Int { pixelEdge * pixelEdge }

  /// 256 preserves the established 512 derivative and asks only the Qwen
  /// processor to downsample. 1024 uses a true 1024 square derivative.
  var derivativeEdge: Int { self == .pixels256 ? 512 : pixelEdge }

  var expectedPatchEdge: Int {
    switch self {
    case .pixels1024: return 64
    case .pixels512: return 32
    case .pixels256: return 16
    }
  }

  var preprocessingVersion: String {
    switch self {
    case .pixels1024: return PhotoSuggestionPreprocessingEvidence.qwen1024Version
    case .pixels512: return PhotoSuggestionPreprocessingEvidence.qwen512Version
    case .pixels256: return PhotoSuggestionPreprocessingEvidence.qwen256Version
    }
  }

  var expectedPostMergeVisualTokenCount: Int {
    expectedPatchEdge * expectedPatchEdge / 4
  }

  var permitsSemanticQualification: Bool { self != .pixels256 }
}

private enum Qwen3PhysicalThermalState: String, Codable, Sendable {
  case nominal
  case fair
  case serious
  case critical
  case unknown

  static var current: Self {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return .nominal
    case .fair: return .fair
    case .serious: return .serious
    case .critical: return .critical
    @unknown default: return .unknown
    }
  }
}

private func qwen3PhysicalEvidenceSHA256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// The evidence journal intentionally records no file path or image bytes. It
/// is armed only by the internal physical-QA launch argument and stays inside
/// this app's data container for manual, local collection after a run.
private struct Qwen3PhysicalEvidenceEvent: Codable, Sendable {
  static let schemaVersion = "qwen3-decomposed-physical-evidence-v2"

  let schemaVersion: String
  let event: String
  let timestamp: Date
  let profile: String?
  let requestID: String?
  let analyzedImageSHA256: String?
  let analyzedPixelWidth: Int?
  let analyzedPixelHeight: Int?
  let requestedProfile: String?
  let effectiveProfile: String?
  let preprocessingVersion: String?
  let sourcePixelWidth: Int?
  let sourcePixelHeight: Int?
  let effectiveSourcePixelWidth: Int?
  let effectiveSourcePixelHeight: Int?
  let derivativePixelWidth: Int?
  let derivativePixelHeight: Int?
  let derivativeContentPixelWidth: Int?
  let derivativeContentPixelHeight: Int?
  let deterministicDerivativePixelWidth: Int?
  let deterministicDerivativePixelHeight: Int?
  let deterministicDerivativeRGBASHA256: String?
  let sourceWasUpscaled: Bool?
  let pixelBudget: Int?
  let expectedFrameT: Int?
  let expectedFrameH: Int?
  let expectedFrameW: Int?
  let postMergeVisualTokenCount: Int?
  let derivativeRGBASHA256: String?
  let preparedTensorSHA256: String?
  let frameT: Int?
  let frameH: Int?
  let frameW: Int?
  let preprocessLatencyMilliseconds: Int?
  let availableMemoryBytes: UInt64?
  let mlxActiveMemoryBytes: Int?
  let mlxPeakMemoryBytes: Int?
  let mlxCacheMemoryBytes: Int?
  let hostPeakRSSBytes: Int?
  let fieldRecord: Qwen3DecomposedRawFieldRecord?
  let modelLoadLatencyMilliseconds: Int?
  let modelCallCount: Int?
  let requestLatencyMilliseconds: Int?
  let failureReason: String?
  let requiresFullAppRestart: Bool?
  let partialRawUTF8Base64: String?
  let partialRawUTF8SHA256: String?
  let fusedCanonicalJSON: String?
  let detail: String?
  let thermalState: Qwen3PhysicalThermalState

  init(
    event: String,
    profile: Qwen3InternalQAPreprocessProfile? = nil,
    requestID: UUID? = nil,
    analyzedImageSHA256: String? = nil,
    analyzedPixelWidth: Int? = nil,
    analyzedPixelHeight: Int? = nil,
    requestedProfile: String? = nil,
    effectiveProfile: String? = nil,
    preprocessingVersion: String? = nil,
    sourcePixelWidth: Int? = nil,
    sourcePixelHeight: Int? = nil,
    effectiveSourcePixelWidth: Int? = nil,
    effectiveSourcePixelHeight: Int? = nil,
    derivativePixelWidth: Int? = nil,
    derivativePixelHeight: Int? = nil,
    derivativeContentPixelWidth: Int? = nil,
    derivativeContentPixelHeight: Int? = nil,
    deterministicDerivativePixelWidth: Int? = nil,
    deterministicDerivativePixelHeight: Int? = nil,
    deterministicDerivativeRGBASHA256: String? = nil,
    sourceWasUpscaled: Bool? = nil,
    pixelBudget: Int? = nil,
    expectedFrameT: Int? = nil,
    expectedFrameH: Int? = nil,
    expectedFrameW: Int? = nil,
    postMergeVisualTokenCount: Int? = nil,
    derivativeRGBASHA256: String? = nil,
    preparedTensorSHA256: String? = nil,
    frameT: Int? = nil,
    frameH: Int? = nil,
    frameW: Int? = nil,
    preprocessLatencyMilliseconds: Int? = nil,
    availableMemoryBytes: UInt64? = nil,
    mlxActiveMemoryBytes: Int? = nil,
    mlxPeakMemoryBytes: Int? = nil,
    mlxCacheMemoryBytes: Int? = nil,
    hostPeakRSSBytes: Int? = nil,
    fieldRecord: Qwen3DecomposedRawFieldRecord? = nil,
    modelLoadLatencyMilliseconds: Int? = nil,
    modelCallCount: Int? = nil,
    requestLatencyMilliseconds: Int? = nil,
    failureReason: String? = nil,
    requiresFullAppRestart: Bool? = nil,
    partialRawUTF8: Data? = nil,
    fusedCanonicalJSON: String? = nil,
    detail: String? = nil
  ) {
    self.schemaVersion = Self.schemaVersion
    self.event = event
    self.timestamp = Date()
    self.profile = profile?.rawValue
    self.requestID = requestID?.uuidString
    self.analyzedImageSHA256 = analyzedImageSHA256
    self.analyzedPixelWidth = analyzedPixelWidth
    self.analyzedPixelHeight = analyzedPixelHeight
    self.requestedProfile = requestedProfile
    self.effectiveProfile = effectiveProfile
    self.preprocessingVersion = preprocessingVersion
    self.sourcePixelWidth = sourcePixelWidth
    self.sourcePixelHeight = sourcePixelHeight
    self.effectiveSourcePixelWidth = effectiveSourcePixelWidth
    self.effectiveSourcePixelHeight = effectiveSourcePixelHeight
    self.derivativePixelWidth = derivativePixelWidth
    self.derivativePixelHeight = derivativePixelHeight
    self.derivativeContentPixelWidth = derivativeContentPixelWidth
    self.derivativeContentPixelHeight = derivativeContentPixelHeight
    self.deterministicDerivativePixelWidth = deterministicDerivativePixelWidth
    self.deterministicDerivativePixelHeight = deterministicDerivativePixelHeight
    self.deterministicDerivativeRGBASHA256 = deterministicDerivativeRGBASHA256
    self.sourceWasUpscaled = sourceWasUpscaled
    self.pixelBudget = pixelBudget
    self.expectedFrameT = expectedFrameT
    self.expectedFrameH = expectedFrameH
    self.expectedFrameW = expectedFrameW
    self.postMergeVisualTokenCount = postMergeVisualTokenCount
    self.derivativeRGBASHA256 = derivativeRGBASHA256
    self.preparedTensorSHA256 = preparedTensorSHA256
    self.frameT = frameT
    self.frameH = frameH
    self.frameW = frameW
    self.preprocessLatencyMilliseconds = preprocessLatencyMilliseconds
    self.availableMemoryBytes = availableMemoryBytes
    self.mlxActiveMemoryBytes = mlxActiveMemoryBytes
    self.mlxPeakMemoryBytes = mlxPeakMemoryBytes
    self.mlxCacheMemoryBytes = mlxCacheMemoryBytes
    self.hostPeakRSSBytes = hostPeakRSSBytes
    self.fieldRecord = fieldRecord
    self.modelLoadLatencyMilliseconds = modelLoadLatencyMilliseconds
    self.modelCallCount = modelCallCount
    self.requestLatencyMilliseconds = requestLatencyMilliseconds
    self.failureReason = failureReason
    self.requiresFullAppRestart = requiresFullAppRestart
    self.partialRawUTF8Base64 = partialRawUTF8?.base64EncodedString()
    self.partialRawUTF8SHA256 = partialRawUTF8.map(qwen3PhysicalEvidenceSHA256)
    self.fusedCanonicalJSON = fusedCanonicalJSON
    self.detail = detail
    self.thermalState = .current
  }
}

private actor Qwen3PhysicalEvidenceJournal {
  private static let enableLaunchArgument = "--qwen3-physical-evidence-jsonl"
  private static let directoryName = "Qwen3DecomposedPhysicalQA"
  private static let fileName = "physical-runs.jsonl"

  private let enabled: Bool
  private var fileURL: URL?
  private var lastThermalState: Qwen3PhysicalThermalState?
  private var latestFieldOrdinal = [String: Int]()
  private var journalProfile: Qwen3InternalQAPreprocessProfile?
  private var activeRequestContext: ActiveRequestContext?
  private var notificationObserverTokens = [NSObjectProtocol]()

  private struct ActiveRequestContext: Sendable {
    let profile: Qwen3InternalQAPreprocessProfile
    let requestID: UUID
    let imageSHA256: String
  }

  init(arguments: [String] = ProcessInfo.processInfo.arguments) {
    enabled = arguments.contains(Self.enableLaunchArgument)
  }

  func journalReady(profile: Qwen3InternalQAPreprocessProfile) {
    journalProfile = profile
    startObservingNotificationsIfNeeded()
    append(Qwen3PhysicalEvidenceEvent(event: "journal_ready", profile: profile))
  }

  func profileRejected() {
    append(Qwen3PhysicalEvidenceEvent(
      event: "profile_rejected", detail: "exact_1024_512_or_256_required"
    ))
  }

  func modelLoadSucceeded(
    profile: Qwen3InternalQAPreprocessProfile,
    latencyMilliseconds: Int
  ) {
    append(Qwen3PhysicalEvidenceEvent(
      event: "model_load_succeeded", profile: profile,
      modelLoadLatencyMilliseconds: latencyMilliseconds
    ))
  }

  func modelLoadFailed(
    profile: Qwen3InternalQAPreprocessProfile,
    latencyMilliseconds: Int,
    error: Error
  ) {
    append(Qwen3PhysicalEvidenceEvent(
      event: "model_load_failed", profile: profile,
      modelLoadLatencyMilliseconds: latencyMilliseconds,
      detail: String(describing: type(of: error))
    ))
  }

  func requestStarted(
    profile: Qwen3InternalQAPreprocessProfile,
    input: PreparedPhotoSuggestionInput
  ) {
    latestFieldOrdinal[input.requestID.uuidString] = 0
    activeRequestContext = ActiveRequestContext(
      profile: profile, requestID: input.requestID, imageSHA256: input.sha256
    )
    append(Qwen3PhysicalEvidenceEvent(
      event: "request_started", profile: profile, requestID: input.requestID,
      analyzedImageSHA256: input.sha256,
      analyzedPixelWidth: input.pixelWidth,
      analyzedPixelHeight: input.pixelHeight,
      requestedProfile: profile.rawValue,
      effectiveProfile: profile.rawValue,
      preprocessingVersion: profile.preprocessingVersion,
      sourcePixelWidth: input.pixelWidth,
      sourcePixelHeight: input.pixelHeight,
      derivativePixelWidth: profile.derivativeEdge,
      derivativePixelHeight: profile.derivativeEdge,
      pixelBudget: profile.pixelBudget,
      expectedFrameT: 1,
      expectedFrameH: profile.expectedPatchEdge,
      expectedFrameW: profile.expectedPatchEdge,
      postMergeVisualTokenCount: profile.expectedPostMergeVisualTokenCount
    ))
  }

  func preprocessCompleted(
    profile: Qwen3InternalQAPreprocessProfile,
    requestID: UUID,
    imageSHA256: String,
    evidence: PhotoSuggestionPreprocessingEvidence
  ) {
    append(Qwen3PhysicalEvidenceEvent(
      event: "preprocess_completed", profile: profile, requestID: requestID,
      analyzedImageSHA256: imageSHA256,
      requestedProfile: evidence.requestedProfile,
      effectiveProfile: evidence.effectiveProfile,
      preprocessingVersion: evidence.preprocessingVersion,
      sourcePixelWidth: evidence.sourcePixelWidth,
      sourcePixelHeight: evidence.sourcePixelHeight,
      effectiveSourcePixelWidth: evidence.effectiveSourcePixelWidth,
      effectiveSourcePixelHeight: evidence.effectiveSourcePixelHeight,
      derivativePixelWidth: evidence.derivativePixelWidth,
      derivativePixelHeight: evidence.derivativePixelHeight,
      derivativeContentPixelWidth: evidence.derivativeContentPixelWidth,
      derivativeContentPixelHeight: evidence.derivativeContentPixelHeight,
      deterministicDerivativePixelWidth: evidence.deterministicDerivativePixelWidth,
      deterministicDerivativePixelHeight: evidence.deterministicDerivativePixelHeight,
      deterministicDerivativeRGBASHA256: evidence.deterministicDerivativeRGBASHA256,
      sourceWasUpscaled: evidence.sourceWasUpscaled,
      pixelBudget: evidence.pixelBudget,
      expectedFrameT: evidence.expectedFrameT,
      expectedFrameH: evidence.expectedFrameH,
      expectedFrameW: evidence.expectedFrameW,
      postMergeVisualTokenCount: evidence.postMergeVisualTokenCount,
      derivativeRGBASHA256: evidence.derivativeRGBASHA256,
      preparedTensorSHA256: evidence.preparedTensorSHA256,
      frameT: evidence.actualFrameT,
      frameH: evidence.actualFrameH,
      frameW: evidence.actualFrameW,
      preprocessLatencyMilliseconds: evidence.preprocessLatencyMilliseconds,
      availableMemoryBytes: evidence.availableMemoryBytes,
      mlxActiveMemoryBytes: evidence.mlxActiveMemoryBytes,
      mlxPeakMemoryBytes: evidence.mlxPeakMemoryBytes,
      mlxCacheMemoryBytes: evidence.mlxCacheMemoryBytes,
      hostPeakRSSBytes: evidence.hostPeakRSSBytes
    ))
  }

  func retryAt512Available(
    requestID: UUID,
    imageSHA256: String,
    reason: PhotoSuggestionFailureReason
  ) {
    append(Qwen3PhysicalEvidenceEvent(
      event: "retry_at_512_available", profile: .pixels1024,
      requestID: requestID, analyzedImageSHA256: imageSHA256,
      requestedProfile: Qwen3InternalQAPreprocessProfile.pixels1024.rawValue,
      effectiveProfile: nil,
      detail: "reason=\(reason.rawValue);automatic_fallback=false;requires_explicit_512_retry=true"
    ))
  }

  func fieldCompleted(
    profile: Qwen3InternalQAPreprocessProfile,
    requestID: UUID,
    record: Qwen3DecomposedRawFieldRecord
  ) {
    latestFieldOrdinal[requestID.uuidString] = record.modelCallOrdinal
    append(Qwen3PhysicalEvidenceEvent(
      event: "field_completed", profile: profile, requestID: requestID,
      analyzedImageSHA256: record.analyzedImageSHA256,
      preparedTensorSHA256: record.preparedTensorSHA256,
      fieldRecord: record
    ))
    if let warning = memoryPressureThreshold(for: record) {
      append(Qwen3PhysicalEvidenceEvent(
        event: "memory_pressure_threshold", profile: profile, requestID: requestID,
        analyzedImageSHA256: record.analyzedImageSHA256,
        preparedTensorSHA256: record.preparedTensorSHA256,
        fieldRecord: record, detail: warning
      ))
    }
  }

  func cancellationRequested(
    profile: Qwen3InternalQAPreprocessProfile?,
    requestID: UUID
  ) {
    append(Qwen3PhysicalEvidenceEvent(
      event: "cancellation_requested", profile: profile, requestID: requestID,
      detail: "field_ordinal=\(latestFieldOrdinal[requestID.uuidString] ?? 0)"
    ))
  }

  func quarantineSet(
    profile: Qwen3InternalQAPreprocessProfile?,
    requestID: UUID
  ) {
    append(Qwen3PhysicalEvidenceEvent(
      event: "quarantine_set", profile: profile, requestID: requestID,
      requiresFullAppRestart: true,
      detail: "field_ordinal=\(latestFieldOrdinal[requestID.uuidString] ?? 0)"
    ))
    clearActiveRequest(for: requestID)
  }

  func staleOrLateResultRejected(
    profile: Qwen3InternalQAPreprocessProfile,
    requestID: UUID,
    imageSHA256: String,
    detail: String
  ) {
    append(Qwen3PhysicalEvidenceEvent(
      event: "stale_or_late_result_rejected", profile: profile, requestID: requestID,
      analyzedImageSHA256: imageSHA256, requiresFullAppRestart: true, detail: detail
    ))
    clearActiveRequest(for: requestID)
  }

  func requestFailed(
    profile: Qwen3InternalQAPreprocessProfile,
    error: PhotoSuggestionEngineError
  ) {
    append(Qwen3PhysicalEvidenceEvent(
      event: "request_failed", profile: profile, requestID: error.requestID,
      analyzedImageSHA256: error.analyzedImageSHA256,
      modelCallCount: error.modelCallCount, failureReason: error.reason.rawValue,
      requiresFullAppRestart: error.requiresFullAppRestart,
      partialRawUTF8: error.rawOutputUTF8
    ))
    clearActiveRequest(for: error.requestID)
  }

  func requestCompleted(
    profile: Qwen3InternalQAPreprocessProfile,
    requestID: UUID,
    imageSHA256: String,
    run: PhotoSuggestionRun
  ) {
    append(Qwen3PhysicalEvidenceEvent(
      event: "request_completed", profile: profile, requestID: requestID,
      analyzedImageSHA256: imageSHA256,
      modelCallCount: run.receipt.modelCallCount,
      requestLatencyMilliseconds: run.receipt.latencyMilliseconds,
      fusedCanonicalJSON: run.canonicalParsedJSON
    ))
    clearActiveRequest(for: requestID)
  }

  func resourceFallbackNotAdmitted(
    profile: Qwen3InternalQAPreprocessProfile,
    requestID: UUID,
    imageSHA256: String,
    modelCallCount: Int
  ) {
    append(Qwen3PhysicalEvidenceEvent(
      event: "resource_fallback_not_semantically_admitted",
      profile: profile, requestID: requestID, analyzedImageSHA256: imageSHA256,
      modelCallCount: modelCallCount,
      detail: "all_fields_unqualified_manual_fallback_required"
    ))
  }

  /// Evidence-only instrumentation for the foreground-submission gate (see
  /// Qwen3HybridPhotoSuggestionEngine.waitForForegroundBeforeGPUSubmission,
  /// below): records GPU-submission pause/resume/timeout observed while
  /// gating the model load and each per-field generate call on
  /// UIApplication.shared.applicationState. Mirrors autorunNote's
  /// detail-string pattern (defined later in this file) under its own event
  /// tag so gate evidence stays distinguishable from qa_autorun_note
  /// entries. Never affects control flow.
  func foregroundGateNote(detail: String) {
    append(Qwen3PhysicalEvidenceEvent(event: "foreground_gate_note", detail: detail))
  }

  private func startObservingNotificationsIfNeeded() {
    guard enabled, notificationObserverTokens.isEmpty else { return }
    let center = NotificationCenter.default
    notificationObserverTokens = [
      center.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        Task { await self?.memoryWarningNotification() }
      },
      center.addObserver(
        forName: ProcessInfo.thermalStateDidChangeNotification,
        object: ProcessInfo.processInfo,
        queue: nil
      ) { [weak self] _ in
        Task { await self?.thermalStateNotification() }
      },
    ]
  }

  private func memoryWarningNotification() {
    let context = activeRequestContext
    append(Qwen3PhysicalEvidenceEvent(
      event: "memory_warning_notification",
      profile: context?.profile ?? journalProfile,
      requestID: context?.requestID,
      analyzedImageSHA256: context?.imageSHA256,
      detail: "UIApplication.didReceiveMemoryWarningNotification"
    ))
  }

  private func thermalStateNotification() {
    let context = activeRequestContext
    append(Qwen3PhysicalEvidenceEvent(
      event: "thermal_state_notification",
      profile: context?.profile ?? journalProfile,
      requestID: context?.requestID,
      analyzedImageSHA256: context?.imageSHA256,
      detail: "ProcessInfo.thermalStateDidChangeNotification"
    ))
  }

  private func clearActiveRequest(for requestID: UUID) {
    guard activeRequestContext?.requestID == requestID else { return }
    activeRequestContext = nil
    latestFieldOrdinal.removeValue(forKey: requestID.uuidString)
  }

  private func append(_ event: Qwen3PhysicalEvidenceEvent) {
    guard enabled else { return }
    do {
      let url = try journalFileURL()
      if lastThermalState != event.thermalState {
        try appendLine(Qwen3PhysicalEvidenceEvent(
          event: "thermal_state_changed",
          profile: event.profile.flatMap(Qwen3InternalQAPreprocessProfile.init(rawValue:)),
          requestID: event.requestID.flatMap(UUID.init(uuidString:)),
          detail: "current=\(event.thermalState.rawValue)"
        ), to: url)
        lastThermalState = event.thermalState
      }
      try appendLine(event, to: url)
    } catch {
      // Evidence capture must never block the retained-draft manual fallback.
    }
  }

  private func journalFileURL() throws -> URL {
    if let fileURL { return fileURL }
    let manager = FileManager.default
    let appSupport = try manager.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true
    ).standardizedFileURL
    var directory = appSupport.appendingPathComponent(Self.directoryName, isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    var excluded = URLResourceValues()
    excluded.isExcludedFromBackup = true
    try directory.setResourceValues(excluded)
    var candidate = directory.appendingPathComponent(Self.fileName, isDirectory: false)
    guard candidate.standardizedFileURL.path.hasPrefix(directory.path + "/") else {
      throw CocoaError(.fileNoSuchFile)
    }
    if !manager.fileExists(atPath: candidate.path) {
      guard manager.createFile(
        atPath: candidate.path,
        contents: nil,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
      ) else { throw CocoaError(.fileWriteUnknown) }
    }
    let attributes = try manager.attributesOfItem(atPath: candidate.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    try manager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: candidate.path
    )
    try candidate.setResourceValues(excluded)
    fileURL = candidate
    return candidate
  }

  private func appendLine(_ event: Qwen3PhysicalEvidenceEvent, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(event)
    data.append(0x0A)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
  }

  private func memoryPressureThreshold(for record: Qwen3DecomposedRawFieldRecord) -> String? {
    let physicalMemory = Double(ProcessInfo.processInfo.physicalMemory)
    guard physicalMemory > 0 else { return nil }
    if let hostPeakRSSBytes = record.hostPeakRSSBytes,
      Double(hostPeakRSSBytes) >= physicalMemory * 0.8
    {
      return "host_peak_rss_at_or_above_80pct_physical_memory"
    }
    if let mlxPeakMemoryBytes = record.mlxPeakMemoryBytes,
      Double(mlxPeakMemoryBytes) >= physicalMemory * 0.8
    {
      return "mlx_peak_memory_at_or_above_80pct_physical_memory"
    }
    return nil
  }
}

/// Internal-only Qwen3 qualification engine. The normal app target neither
/// compiles nor selects this type. It is deliberately independent from the
/// shipping LiteRT route and admits only a bundled, hash-verified snapshot.
actor Qwen3HybridPhotoSuggestionEngine: PhotoSuggestionEngine {
  private static let modelID = "mlx-community/Qwen3-VL-2B-Instruct-4bit"
  private static let modelRevision = "9c4f5209e57b31f4b9dfba735de3fb983739c9cc"
  private static let snapshotDirectoryName = "Qwen3Snapshot"
  private static let analysisPipelineVersion = "qwen3-decomposed-seven-field-v1"

  private static let snapshotManifest: [String: String] = [
    ".gitattributes": "34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930",
    "README.md": "ede73d0babc5bc8fa1eeaed1f9564eab6e5094500e5561f94235a15c96aa1cf0",
    "added_tokens.json": "c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680",
    "chat_template.jinja": "3636d0f0bd6bef02654cdffdc447b79cb2cef8ab02cc75267345946291a489e4",
    "chat_template.json": "6f8a6a55027e3da5160105556cda5dd69f6423f1c32645f6730d32de7773d0c4",
    "config.json": "6e992843f82cbaf02e8eae2f1c803f8a56f70951fa8a1f30fc1bf8d9ec2d7ec3",
    "generation_config.json": "1e241830b48b397cb0900101421df5450baddc7adf01e5fc86b5615865f3bae4",
    "merges.txt": "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5",
    "model.safetensors": "4750d95a2162829e127a94e83ac350d498d02070aab216c4687da48804a06ffb",
    "model.safetensors.index.json": "30ba24b1c93436450f2e202de402058ecea7417cf66785d4c73e52d1575e6d97",
    "preprocessor_config.json": "93585062a80db5e8ca038efc7726a3e6411d9db948472d81d63c6303993be8c5",
    "special_tokens_map.json": "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd",
    "tokenizer.json": "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4",
    "tokenizer_config.json": "81ec7bb9530159b326c0bef1d0b6c33d392090524014ea3f0123a3c1eb9c2af5",
    "video_preprocessor_config.json": "59c5c9eb52182eb14c06ffb10ca9effd29adce5f238a95de23ca14a38dbd2cb1",
    "vocab.json": "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910",
  ]

  private struct LoadedResources: Sendable {
    let container: ModelContainer
    let snapshotURL: URL
    let identity: PhotoSuggestionEngineIdentity
    let profile: Qwen3InternalQAPreprocessProfile
  }

  private struct QADerivativeProvenance {
    struct ContentRect {
      let x: Int
      let y: Int
      let width: Int
      let height: Int

      init(_ rect: HybridContentRect) {
        x = rect.x
        y = rect.y
        width = rect.width
        height = rect.height
      }

      init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
      }
    }

    let decodedWidth: Int
    let decodedHeight: Int
    let derivativeWidth: Int
    let derivativeHeight: Int
    let derivativeRGBASHA256: String
    let contentRect: ContentRect

    init(_ provenance: HybridDerivativeProvenance) {
      decodedWidth = provenance.decodedWidth
      decodedHeight = provenance.decodedHeight
      derivativeWidth = provenance.derivativeWidth
      derivativeHeight = provenance.derivativeHeight
      derivativeRGBASHA256 = provenance.derivativeRGBASHA256
      contentRect = ContentRect(provenance.contentRect)
    }

    init(
      decodedWidth: Int,
      decodedHeight: Int,
      derivativeWidth: Int,
      derivativeHeight: Int,
      derivativeRGBASHA256: String,
      contentRect: ContentRect
    ) {
      self.decodedWidth = decodedWidth
      self.decodedHeight = decodedHeight
      self.derivativeWidth = derivativeWidth
      self.derivativeHeight = derivativeHeight
      self.derivativeRGBASHA256 = derivativeRGBASHA256
      self.contentRect = contentRect
    }
  }

  private struct QAPreparedDerivative {
    let rgba: Data
    let provenance: QADerivativeProvenance
  }

  private struct PreparedRequest {
    let derivativeImage: CIImage
    let derivativeProvenance: QADerivativeProvenance
    let deterministicDerivativeProvenance: QADerivativeProvenance
    let imageSHA256: String
    let pixelEvidence: HybridPixelEvidence
  }

  private struct PreparedRunEvidence {
    let decomposed: Qwen3DecomposedRunEvidence
    let preprocessing: PhotoSuggestionPreprocessingEvidence
  }

  private struct CompletionEvidence {
    let stopReason: String
    let generationTokenCount: Int
  }

  private struct ExecutionFailure: Error, Sendable {
    let reason: PhotoSuggestionFailureReason
    let modelCallCount: Int
    let partialRawUTF8: Data?
  }

  private var resources: LoadedResources?
  private var preparationTask: Task<LoadedResources, Error>?
  private var activeRequestID: UUID?
  private var activeTask: Task<PhotoSuggestionRun, Error>?
  private var quarantinedAfterCancellation = false
  private let physicalEvidenceJournal = Qwen3PhysicalEvidenceJournal()

  func prepare() async throws -> PhotoSuggestionEngineIdentity {
    guard let profile = Qwen3InternalQAPreprocessProfile.selected() else {
      await physicalEvidenceJournal.profileRejected()
      throw ExecutionFailure(reason: .invalidInput, modelCallCount: 0, partialRawUTF8: nil)
    }
    await physicalEvidenceJournal.journalReady(profile: profile)
    await physicalEvidenceJournal.memoryHeadroom(stage: "prepare_entry", profile: profile)
    if let resources {
      guard resources.profile == profile else {
        throw ExecutionFailure(reason: .staleRequest, modelCallCount: 0, partialRawUTF8: nil)
      }
      return resources.identity
    }
    if let preparationTask {
      do {
        let loaded = try await withTaskCancellationHandler {
          try await preparationTask.value
        } onCancel: {
          preparationTask.cancel()
        }
        try Task.checkCancellation()
        guard loaded.profile == profile else {
          throw ExecutionFailure(reason: .staleRequest, modelCallCount: 0, partialRawUTF8: nil)
        }
        resources = loaded
        self.preparationTask = nil
        return loaded.identity
      } catch {
        self.preparationTask = nil
        throw error
      }
    }

    let journal = physicalEvidenceJournal
    let task = Task {
      let startedAt = Date()
      do {
        let loaded = try await Self.loadResources(profile: profile, journal: journal)
        await journal.modelLoadSucceeded(
          profile: profile,
          latencyMilliseconds: Self.milliseconds(from: startedAt, to: Date())
        )
        return loaded
      } catch {
        await journal.modelLoadFailed(
          profile: profile,
          latencyMilliseconds: Self.milliseconds(from: startedAt, to: Date()),
          error: error
        )
        throw error
      }
    }
    preparationTask = task
    do {
      let loaded = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      try Task.checkCancellation()
      resources = loaded
      preparationTask = nil
      return loaded.identity
    } catch {
      preparationTask = nil
      throw error
    }
  }

  func suggest(_ input: PreparedPhotoSuggestionInput) async throws -> PhotoSuggestionRun {
    guard let resources else {
      throw engineError(
        input: input, identity: nil, startedAt: Date(), reason: .unavailable,
        modelCallCount: 0, partialRawUTF8: nil, requiresFullAppRestart: false
      )
    }
    guard !quarantinedAfterCancellation, activeRequestID == nil else {
      let error = engineError(
        input: input, identity: resources.identity, startedAt: Date(), reason: .staleRequest,
        modelCallCount: 0, partialRawUTF8: nil,
        requiresFullAppRestart: quarantinedAfterCancellation
      )
      await physicalEvidenceJournal.staleOrLateResultRejected(
        profile: resources.profile, requestID: input.requestID,
        imageSHA256: input.sha256,
        detail: quarantinedAfterCancellation ? "engine_quarantined" : "active_request_exists"
      )
      throw error
    }

    let startedAt = Date()
    let journal = physicalEvidenceJournal
    await journal.requestStarted(profile: resources.profile, input: input)
    let task = Task {
      try await Self.buildRun(
        resources: resources, input: input,
        profile: resources.profile, physicalEvidenceJournal: journal
      )
    }
    activeRequestID = input.requestID
    activeTask = task

    do {
      let run = try await task.value
      guard activeRequestID == input.requestID, !quarantinedAfterCancellation else {
        let error = engineError(
          input: input, identity: resources.identity, startedAt: startedAt, reason: .staleRequest,
          modelCallCount: Qwen3DecomposedField.allCases.count, partialRawUTF8: run.rawOutputUTF8,
          requiresFullAppRestart: true
        )
        await journal.staleOrLateResultRejected(
          profile: resources.profile, requestID: input.requestID,
          imageSHA256: input.sha256, detail: "completed_after_cancellation_or_replacement"
        )
        throw error
      }
      activeRequestID = nil
      activeTask = nil
      await journal.requestCompleted(
        profile: resources.profile, requestID: input.requestID,
        imageSHA256: input.sha256, run: run
      )
      await journal.memoryHeadroom(
        stage: "after_request", profile: resources.profile, extra: Self.mlxMemoryExtra()
      )
      return run
    } catch {
      if activeRequestID == input.requestID {
        activeRequestID = nil
        activeTask = nil
      }
      if let error = error as? PhotoSuggestionEngineError {
        if resources.profile == .pixels1024, error.reason != .cancelled {
          await journal.retryAt512Available(
            requestID: input.requestID, imageSHA256: input.sha256, reason: error.reason
          )
        }
        await journal.requestFailed(profile: resources.profile, error: error)
        throw error
      }
      if let failure = error as? ExecutionFailure {
        let error = engineError(
          input: input, identity: resources.identity, startedAt: startedAt,
          reason: failure.reason, modelCallCount: failure.modelCallCount,
          partialRawUTF8: failure.partialRawUTF8,
          requiresFullAppRestart: quarantinedAfterCancellation || failure.reason == .cancelled
        )
        if resources.profile == .pixels1024, failure.reason != .cancelled {
          await journal.retryAt512Available(
            requestID: input.requestID, imageSHA256: input.sha256, reason: failure.reason
          )
        }
        await journal.requestFailed(profile: resources.profile, error: error)
        throw error
      }
      let error = engineError(
        input: input, identity: resources.identity, startedAt: startedAt,
        reason: Task.isCancelled ? .cancelled : .runtimeFailure,
        modelCallCount: 0, partialRawUTF8: nil,
        requiresFullAppRestart: quarantinedAfterCancellation || Task.isCancelled
      )
      if resources.profile == .pixels1024, !Task.isCancelled {
        await journal.retryAt512Available(
          requestID: input.requestID, imageSHA256: input.sha256, reason: .runtimeFailure
        )
      }
      await journal.requestFailed(profile: resources.profile, error: error)
      throw error
    }
  }

  func cancel(requestID: UUID) async -> PhotoSuggestionCancellationDisposition {
    guard activeRequestID == requestID, let activeTask else { return .noActiveRequest }
    // Native generation cancellation is quarantined rather than reused. The
    // ViewModel already ignores a late result by request ID; clearing the
    // active identity makes that protection explicit at this boundary too.
    let profile = resources?.profile
    activeTask.cancel()
    activeRequestID = nil
    self.activeTask = nil
    quarantinedAfterCancellation = true
    await physicalEvidenceJournal.cancellationRequested(profile: profile, requestID: requestID)
    await physicalEvidenceJournal.quarantineSet(profile: profile, requestID: requestID)
    return .fullAppRestartRequired
  }

  /// Foreground-submission gate (root cause: crash
  /// GITimeline-2026-08-23-105415.ips — mlx::core::gpu::check_error throws
  /// from inside a Metal completion handler while procRole is not
  /// foreground, an uncatchable process abort). MLX aborts the whole
  /// process if GPU work is *submitted* while the app is not foreground;
  /// clean suspension before any submission is safe. Both GPU-submission
  /// points in this engine — the model load in loadResources(profile:
  /// journal:) and each of the seven per-field generate calls in
  /// makeRunEvidence(...) — await this immediately beforehand, at the last
  /// point before that submission.
  ///
  /// Fast path (app already .active): a single MainActor state read, zero
  /// journal writes — byte-identical to having no gate at all. Only once
  /// the app is found not .active does it start polling (~250ms) and
  /// journaling the pause/resume, up to a 120s budget; on exhaustion it
  /// throws the same ExecutionFailure shape the engine already throws for a
  /// native CancellationError (see the `catch is CancellationError` arms in
  /// buildRun and makeRunEvidence below), so suggest(_:)'s existing
  /// translation to PhotoSuggestionEngineError — and NewEntryViewModel's
  /// existing manual-fallback handling — applies unchanged.
  ///
  /// The MainActor read is an async hop (MainActor.run, matching this
  /// codebase's existing hop pattern — see InferenceService.swift), never a
  /// semaphore: this always runs off the main thread, so blocking it would
  /// risk the very foreground transition being waited for.
  private static func waitForForegroundBeforeGPUSubmission(
    label: String,
    modelCallCount: Int,
    partialRawUTF8: Data?,
    journal: Qwen3PhysicalEvidenceJournal
  ) async throws {
    if await MainActor.run(body: { UIApplication.shared.applicationState == .active }) {
      return
    }
    await journal.foregroundGateNote(detail: "generation_paused_app_inactive=\(label)")
    let pauseStartedAt = DispatchTime.now().uptimeNanoseconds
    let budgetNanoseconds: UInt64 = 120_000_000_000
    while true {
      try Task.checkCancellation()
      if await MainActor.run(body: { UIApplication.shared.applicationState == .active }) {
        let waitedMilliseconds = Int(
          (DispatchTime.now().uptimeNanoseconds - pauseStartedAt) / 1_000_000
        )
        await journal.foregroundGateNote(
          detail: "generation_resumed_app_active=\(label);waited_ms=\(waitedMilliseconds)"
        )
        return
      }
      if DispatchTime.now().uptimeNanoseconds - pauseStartedAt >= budgetNanoseconds {
        await journal.foregroundGateNote(detail: "generation_gate_timeout=\(label)")
        throw ExecutionFailure(
          reason: .cancelled, modelCallCount: modelCallCount, partialRawUTF8: partialRawUTF8
        )
      }
      try await Task.sleep(for: .milliseconds(250))
    }
  }

  private static func loadResources(
    profile: Qwen3InternalQAPreprocessProfile,
    journal: Qwen3PhysicalEvidenceJournal
  ) async throws -> LoadedResources {
    await journal.memoryHeadroom(stage: "hash_entry", profile: profile, extra: mlxMemoryExtra())
    let snapshotURL = try verifiedBundledSnapshot()
    await journal.snapshotVerified(profile: profile)
    try await waitForForegroundBeforeGPUSubmission(
      label: "model_load", modelCallCount: 0, partialRawUTF8: nil, journal: journal
    )
    let container = try await VLMModelFactory.shared.loadContainer(
      from: snapshotURL,
      using: #huggingFaceTokenizerLoader()
    )
    // A caller may abandon model preparation before any photo request exists.
    // Do not retain a late load or begin later GPU work after that cancellation.
    try Task.checkCancellation()
    let loadMemory = Memory.snapshot()
    await journal.memoryHeadroom(
      stage: "after_load", profile: profile,
      extra: "mlx_active=\(loadMemory.activeMemory);mlx_peak=\(loadMemory.peakMemory);mlx_cache=\(loadMemory.cacheMemory)"
    )
    let identity = PhotoSuggestionEngineIdentity(
      providerID: "internal-qwen3-qualification",
      modelID: modelID,
      modelRevision: modelRevision,
      modelArtifactSHA256: snapshotManifest["model.safetensors"]!,
      runtimeID: "MLX Swift",
      runtimeVersion: "0.31.6; MLX Swift LM 3.31.4",
      promptVersion: Qwen3DecomposedContract.promptSetVersion,
      promptSHA256: Qwen3DecomposedContract.promptSetSHA256,
      parserVersion: Qwen3DecomposedContract.parserVersion,
      schemaVersion: PhotoSuggestionPayloadV2.schemaVersion,
      preprocessingVersion: profile.preprocessingVersion,
      analysisPipelineVersion: analysisPipelineVersion
    )
    return LoadedResources(
      container: container, snapshotURL: snapshotURL, identity: identity, profile: profile
    )
  }

  private static func verifiedBundledSnapshot() throws -> URL {
    guard let resourcesURL = Bundle.main.resourceURL else { throw ExecutionFailure(
      reason: .unavailable, modelCallCount: 0, partialRawUTF8: nil
    ) }
    let snapshotURL = resourcesURL.appendingPathComponent(snapshotDirectoryName, isDirectory: true)
    let manager = FileManager.default
    let rootAttributes = try manager.attributesOfItem(atPath: snapshotURL.path)
    guard rootAttributes[.type] as? FileAttributeType == .typeDirectory else {
      throw ExecutionFailure(reason: .unavailable, modelCallCount: 0, partialRawUTF8: nil)
    }
    let actualPaths = Set(try manager.subpathsOfDirectory(atPath: snapshotURL.path))
    guard actualPaths == Set(snapshotManifest.keys), actualPaths.count == snapshotManifest.count else {
      throw ExecutionFailure(reason: .unavailable, modelCallCount: 0, partialRawUTF8: nil)
    }
    for (relativePath, expectedSHA256) in snapshotManifest {
      let fileURL = snapshotURL.appendingPathComponent(relativePath, isDirectory: false)
      let attributes = try manager.attributesOfItem(atPath: fileURL.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular,
        try streamingSHA256(of: fileURL) == expectedSHA256
      else { throw ExecutionFailure(reason: .unavailable, modelCallCount: 0, partialRawUTF8: nil) }
    }
    return snapshotURL
  }

  private static func buildRun(
    resources: LoadedResources,
    input: PreparedPhotoSuggestionInput,
    profile: Qwen3InternalQAPreprocessProfile,
    physicalEvidenceJournal: Qwen3PhysicalEvidenceJournal
  ) async throws -> PhotoSuggestionRun {
    let startedAt = Date()
    do {
      try Task.checkCancellation()
      let preparedRequest = try prepareRequest(input, profile: profile)
      try Task.checkCancellation()
      let preparedRunEvidence = try await resources.container.perform(nonSendable: preparedRequest) {
        context, preparedRequest in
        try await makeRunEvidence(
          context: context,
          snapshotURL: resources.snapshotURL,
          requestID: input.requestID,
          preparedRequest: preparedRequest,
          profile: profile,
          physicalEvidenceJournal: physicalEvidenceJournal
        )
      }
      try Task.checkCancellation()
      let fused = try Qwen3DecomposedFusion.fuse(preparedRunEvidence.decomposed)
      let rawOutputUTF8 = Data(fused.canonicalV2JSON.utf8)
      let endedAt = Date()
      let provenance = PhotoSuggestionDecomposedProvenance(
        runEvidence: preparedRunEvidence.decomposed,
        qualificationVersion: Qwen3DecomposedContract.qualificationPolicyVersion,
        fusionVersion: Qwen3DecomposedFusion.fusionVersion,
        fusedCanonicalJSON: fused.canonicalV2JSON
      )
      let receipt = PhotoSuggestionEngineReceipt(
        requestID: input.requestID,
        identity: resources.identity,
        analyzedImageSHA256: preparedRequest.imageSHA256,
        analyzedPixelWidth: input.pixelWidth,
        analyzedPixelHeight: input.pixelHeight,
        startedAt: startedAt,
        endedAt: endedAt,
        latencyMilliseconds: milliseconds(from: startedAt, to: endedAt),
        rawOutputUTF8Base64: rawOutputUTF8.base64EncodedString(),
        rawOutputUTF8SHA256: sha256(rawOutputUTF8),
        rawOutputUTF8ByteCount: rawOutputUTF8.count,
        canonicalParsedJSON: fused.canonicalV2JSON,
        modelCallCount: Qwen3DecomposedField.allCases.count,
        repairCallCount: 0,
        decomposedFieldProvenance: provenance,
        preprocessingEvidence: preparedRunEvidence.preprocessing
      )
      _ = try receipt.validate(rawOutputUTF8: rawOutputUTF8)
      return PhotoSuggestionRun(
        suggestion: fused.suggestion,
        rawOutputUTF8: rawOutputUTF8,
        canonicalParsedJSON: fused.canonicalV2JSON,
        receipt: receipt
      )
    } catch let failure as ExecutionFailure {
      throw failure
    } catch is CancellationError {
      throw ExecutionFailure(reason: .cancelled, modelCallCount: 0, partialRawUTF8: nil)
    } catch {
      throw ExecutionFailure(reason: .runtimeFailure, modelCallCount: 0, partialRawUTF8: nil)
    }
  }

  private static func prepareRequest(
    _ input: PreparedPhotoSuggestionInput,
    profile: Qwen3InternalQAPreprocessProfile
  ) throws -> PreparedRequest {
    guard input.url.isFileURL else {
      throw ExecutionFailure(reason: .invalidInput, modelCallCount: 0, partialRawUTF8: nil)
    }
    let sourceData = try Data(contentsOf: input.url, options: [.mappedIfSafe])
    try ImageStore.validateSanitizedJournalJPEG(sourceData, expectedSHA256: input.sha256)
    guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
      let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
      decoded.width == input.pixelWidth,
      decoded.height == input.pixelHeight
    else { throw ExecutionFailure(reason: .invalidInput, modelCallCount: 0, partialRawUTF8: nil) }

    let decodedRGBA = try canonicalSRGBRGBA(decoded)
    let baselineDerivative = try HybridImagePreparer.prepare(
      heldSourceImageData: sourceData,
      decodedRGBA: decodedRGBA
    )
    let selectedDerivative = profile.derivativeEdge == HybridImagePreparer.canvasSize
      ? baselineDerivative
      : try HybridImagePreparer.prepare(
        heldSourceImageData: sourceData,
        decodedRGBA: decodedRGBA,
        hostOnlyCanvasSize: profile.derivativeEdge
      )
    let modelDerivative = QAPreparedDerivative(
      rgba: selectedDerivative.rgba,
      provenance: QADerivativeProvenance(selectedDerivative.provenance)
    )
    let derivativeFrame = try HybridRGBAFrame(
      width: modelDerivative.provenance.derivativeWidth,
      height: modelDerivative.provenance.derivativeHeight,
      rgba: modelDerivative.rgba
    )
    let baselineFrame = try HybridRGBAFrame(
      width: HybridImagePreparer.canvasSize,
      height: HybridImagePreparer.canvasSize,
      rgba: baselineDerivative.rgba
    )
    return PreparedRequest(
      derivativeImage: try ciImage(from: derivativeFrame),
      derivativeProvenance: modelDerivative.provenance,
      deterministicDerivativeProvenance: QADerivativeProvenance(baselineDerivative.provenance),
      imageSHA256: input.sha256,
      pixelEvidence: HybridPixelAnalyzer.evaluate(baselineFrame)
    )
  }

  private static func makeRunEvidence(
    context: ModelContext,
    snapshotURL: URL,
    requestID: UUID,
    preparedRequest: PreparedRequest,
    profile: Qwen3InternalQAPreprocessProfile,
    physicalEvidenceJournal: Qwen3PhysicalEvidenceJournal
  ) async throws -> PreparedRunEvidence {
    var completedFields = [Qwen3DecomposedRawFieldRecord]()
    var startedCalls = 0
    do {
      try Task.checkCancellation()
      let configurationData = try Data(
        contentsOf: snapshotURL.appendingPathComponent("preprocessor_config.json")
      )
      let configuration = try JSONDecoder().decode(
        Qwen3VLProcessorConfiguration.self, from: configurationData
      )
      let processor = Qwen3VLProcessor(configuration, tokenizer: context.tokenizer)
      // This is the sole Qwen preprocessing invocation. Its ProcessedImage is
      // retained by identity across the seven fresh-cache field inputs below.
      let preprocessStartedAt = DispatchTime.now().uptimeNanoseconds
      let (pixels, frame) = try processor.preprocess(
        images: [preparedRequest.derivativeImage],
        processing: .init(
          resize: nil, minPixels: profile.pixelBudget, maxPixels: profile.pixelBudget
        )
      )
      let processedImage = LMInput.ProcessedImage(pixels: pixels, frames: [frame])
      let tensorData = processedImage.pixels.asData().data
      let tensorSHA256 = sha256(tensorData)
      try Task.checkCancellation()
      guard frame.t == 1,
        frame.h == profile.expectedPatchEdge,
        frame.w == profile.expectedPatchEdge,
        ImageStore.isValidSHA256(tensorSHA256)
      else { throw ExecutionFailure(reason: .invalidOutput, modelCallCount: 0, partialRawUTF8: nil) }
      let preprocessMemory = Memory.snapshot()
      let derivative = preparedRequest.derivativeProvenance
      let deterministicDerivative = preparedRequest.deterministicDerivativeProvenance
      let preprocessingEvidence = PhotoSuggestionPreprocessingEvidence(
        requestedProfile: profile.rawValue,
        effectiveProfile: profile.rawValue,
        preprocessingVersion: profile.preprocessingVersion,
        sourcePixelWidth: derivative.decodedWidth,
        sourcePixelHeight: derivative.decodedHeight,
        effectiveSourcePixelWidth: min(derivative.decodedWidth, derivative.contentRect.width),
        effectiveSourcePixelHeight: min(derivative.decodedHeight, derivative.contentRect.height),
        derivativePixelWidth: derivative.derivativeWidth,
        derivativePixelHeight: derivative.derivativeHeight,
        derivativeContentPixelWidth: derivative.contentRect.width,
        derivativeContentPixelHeight: derivative.contentRect.height,
        deterministicDerivativePixelWidth: deterministicDerivative.derivativeWidth,
        deterministicDerivativePixelHeight: deterministicDerivative.derivativeHeight,
        deterministicDerivativeRGBASHA256: deterministicDerivative.derivativeRGBASHA256,
        sourceWasUpscaled: derivative.contentRect.width > derivative.decodedWidth
          || derivative.contentRect.height > derivative.decodedHeight,
        pixelBudget: profile.pixelBudget,
        expectedFrameT: 1,
        expectedFrameH: profile.expectedPatchEdge,
        expectedFrameW: profile.expectedPatchEdge,
        actualFrameT: frame.t,
        actualFrameH: frame.h,
        actualFrameW: frame.w,
        postMergeVisualTokenCount: profile.expectedPostMergeVisualTokenCount,
        derivativeRGBASHA256: derivative.derivativeRGBASHA256,
        preparedTensorSHA256: tensorSHA256,
        preprocessLatencyMilliseconds: Int(
          (DispatchTime.now().uptimeNanoseconds - preprocessStartedAt) / 1_000_000
        ),
        availableMemoryBytes: UInt64(max(0, os_proc_available_memory())),
        mlxActiveMemoryBytes: preprocessMemory.activeMemory,
        mlxPeakMemoryBytes: preprocessMemory.peakMemory,
        mlxCacheMemoryBytes: preprocessMemory.cacheMemory,
        hostPeakRSSBytes: hostPeakRSSBytes(),
        thermalState: Qwen3PhysicalThermalState.current.rawValue
      )
      await physicalEvidenceJournal.preprocessCompleted(
        profile: profile, requestID: requestID,
        imageSHA256: preparedRequest.imageSHA256, evidence: preprocessingEvidence
      )
      await physicalEvidenceJournal.memoryHeadroom(
        stage: "before_prefill", profile: profile, extra: mlxMemoryExtra()
      )

      for (index, field) in Qwen3DecomposedField.allCases.enumerated() {
        try Task.checkCancellation()
        let userInput = UserInput(
          chat: [.user(field.prompt, images: [.ciImage(preparedRequest.derivativeImage)])],
          processing: .init(
            resize: nil, minPixels: profile.pixelBudget, maxPixels: profile.pixelBudget
          )
        )
        let messages = Qwen3VLMessageGenerator().generate(from: userInput)
        let templateTokens = try context.tokenizer.applyChatTemplate(
          messages: messages,
          tools: userInput.tools,
          additionalContext: userInput.additionalContext
        )
        let expandedTokens = try expandImagePlaceholder(
          promptTokens: templateTokens,
          frame: frame,
          mergeSize: configuration.mergeSize,
          tokenizer: context.tokenizer
        )
        let textTokens = MLXArray(expandedTokens).expandedDimensions(axis: 0)
        let fieldInput = LMInput(
          text: .init(tokens: textTokens, mask: ones(like: textTokens).asType(.int8)),
          image: processedImage
        )
        let fieldStartedAt = DispatchTime.now().uptimeNanoseconds
        startedCalls += 1
        try await waitForForegroundBeforeGPUSubmission(
          label: field.rawValue, modelCallCount: startedCalls,
          partialRawUTF8: partialEvidenceData(completedFields),
          journal: physicalEvidenceJournal
        )
        let stream = try generateTokens(
          input: fieldInput,
          cache: nil,
          parameters: generationParameters,
          context: context,
          includeStopToken: false,
          wiredMemoryTicket: nil
        )
        var tokenIDs = [Int]()
        var completion: CompletionEvidence?
        for await event in stream {
          try Task.checkCancellation()
          switch event {
          case .token(let token): tokenIDs.append(token)
          case .info(let info):
            guard completion == nil else {
              throw ExecutionFailure(
                reason: .invalidOutput, modelCallCount: startedCalls,
                partialRawUTF8: partialEvidenceData(completedFields)
              )
            }
            completion = completionEvidence(info)
          }
        }
        guard let completion,
          completion.generationTokenCount == tokenIDs.count,
          completion.stopReason != "cancelled"
        else {
          throw ExecutionFailure(
            reason: Task.isCancelled ? .cancelled : .invalidOutput,
            modelCallCount: startedCalls,
            partialRawUTF8: partialEvidenceData(completedFields)
          )
        }
        let rawText = context.tokenizer.decode(tokenIds: tokenIDs, skipSpecialTokens: false)
        let rawUTF8 = Data(rawText.utf8)
        let memory = Memory.snapshot()
        let record = Qwen3DecomposedRawFieldRecord(
          field: field,
          prompt: field.prompt,
          promptSHA256: Qwen3DecomposedContract.promptSHA256(for: field),
          analyzedImageSHA256: preparedRequest.imageSHA256,
          preparedTensorSHA256: tensorSHA256,
          rawTokenIDs: tokenIDs,
          rawText: rawText,
          rawUTF8Base64: rawUTF8.base64EncodedString(),
          rawUTF8SHA256: sha256(rawUTF8),
          parsed: Qwen3DecomposedLabelParser.parse(rawText, for: field),
          qualified: profile.permitsSemanticQualification
            && Qwen3DecomposedContract.qualifiedFields.contains(field),
          generationCacheID: "\(requestID.uuidString)-nil-cache-\(index + 1)",
          usedFreshGenerationCache: true,
          stopReason: completion.stopReason,
          latencyMilliseconds: Int((DispatchTime.now().uptimeNanoseconds - fieldStartedAt) / 1_000_000),
          mlxActiveMemoryBytes: memory.activeMemory,
          mlxCacheMemoryBytes: memory.cacheMemory,
          mlxPeakMemoryBytes: memory.peakMemory,
          hostPeakRSSBytes: hostPeakRSSBytes(),
          modelCallOrdinal: index + 1
        )
        completedFields.append(record)
        await physicalEvidenceJournal.fieldCompleted(
          profile: profile, requestID: requestID, record: record
        )
      }
      let evidence = Qwen3DecomposedRunEvidence(
        analyzedImageSHA256: preparedRequest.imageSHA256,
        preparedTensorSHA256: tensorSHA256,
        pixelEvidence: preparedRequest.pixelEvidence,
        fields: completedFields
      )
      try evidence.validate()
      guard profile.permitsSemanticQualification else {
        await physicalEvidenceJournal.resourceFallbackNotAdmitted(
          profile: profile, requestID: requestID,
          imageSHA256: preparedRequest.imageSHA256, modelCallCount: startedCalls
        )
        throw ExecutionFailure(
          reason: .invalidOutput, modelCallCount: startedCalls,
          partialRawUTF8: partialEvidenceData(completedFields)
        )
      }
      return PreparedRunEvidence(
        decomposed: evidence,
        preprocessing: preprocessingEvidence
      )
    } catch let failure as ExecutionFailure {
      throw failure
    } catch is CancellationError {
      throw ExecutionFailure(
        reason: .cancelled, modelCallCount: startedCalls,
        partialRawUTF8: partialEvidenceData(completedFields)
      )
    } catch {
      throw ExecutionFailure(
        reason: .runtimeFailure, modelCallCount: startedCalls,
        partialRawUTF8: partialEvidenceData(completedFields)
      )
    }
  }

  // 8 gives headroom for the longest labels in
  // Qwen3DecomposedField.allowedLabels plus EOS; temperature stays 0 and EOS
  // ends generation early, so qualified-field outputs are unchanged.
  // Verified on hardware that the budget is NOT why the subject head emits
  // "nonst": at maxTokens 8 the model still generates "nonst" then a natural
  // EOS (device-evidence-2026-08-24/maxtok8-formed-brown.jsonl). That
  // greedy-decode artifact is handled by the label parser's
  // unambiguous-prefix acceptance, not by widening this budget.
  private static let generationParameters = GenerateParameters(
    maxTokens: 8, maxKVSize: nil, kvBits: nil, kvGroupSize: 64, quantizedKVStart: 0,
    kvScheme: nil, temperature: 0, topP: 1, topK: 0, minP: 0,
    repetitionPenalty: nil, repetitionContextSize: 20, presencePenalty: nil,
    presenceContextSize: 20, frequencyPenalty: nil, frequencyContextSize: 20,
    prefillStepSize: 512, seed: 0
  )

  private static func canonicalSRGBRGBA(_ image: CGImage) throws -> HybridRGBAFrame {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    var rgba = Data(count: image.width * image.height * 4)
    let rendered = rgba.withUnsafeMutableBytes { raw -> Bool in
      guard let context = CGContext(
        data: raw.baseAddress,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return false }
      context.interpolationQuality = .none
      // Core Graphics draws into this bitmap with a bottom-left coordinate
      // system by default. Flip once so the first stored row remains the
      // canonical upright top row declared by HybridDerivativeProvenance.
      context.translateBy(x: 0, y: CGFloat(image.height))
      context.scaleBy(x: 1, y: -1)
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return true
    }
    guard rendered else { throw ExecutionFailure(reason: .invalidInput, modelCallCount: 0, partialRawUTF8: nil) }
    return try HybridRGBAFrame(width: image.width, height: image.height, rgba: rgba)
  }

  private static func ciImage(from frame: HybridRGBAFrame) throws -> CIImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    guard let provider = CGDataProvider(data: frame.rgba as CFData),
      let image = CGImage(
        width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: frame.width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
      )
    else { throw ExecutionFailure(reason: .invalidInput, modelCallCount: 0, partialRawUTF8: nil) }
    return CIImage(cgImage: image)
  }

  private static func expandImagePlaceholder(
    promptTokens: [Int],
    frame: THW,
    mergeSize: Int,
    tokenizer: any MLXLMCommon.Tokenizer
  ) throws -> [Int] {
    let placeholder = tokenizer.encode(text: "<|vision_start|><|image_pad|><|vision_end|>")
    let ranges = subsequenceRanges(of: placeholder, in: promptTokens)
    guard ranges.count == 1 else {
      throw ExecutionFailure(reason: .invalidOutput, modelCallCount: 0, partialRawUTF8: nil)
    }
    let paddingCount = frame.product / (mergeSize * mergeSize)
    let replacement = tokenizer.encode(
      text: "<|vision_start|>" + String(repeating: "<|image_pad|>", count: paddingCount) + "<|vision_end|>"
    )
    let range = ranges[0]
    return Array(promptTokens[..<range.lowerBound]) + replacement + Array(promptTokens[range.upperBound...])
  }

  private static func subsequenceRanges(of needle: [Int], in haystack: [Int]) -> [Range<Int>] {
    guard !needle.isEmpty, needle.count <= haystack.count else { return [] }
    return (0...(haystack.count - needle.count)).compactMap { index in
      Array(haystack[index..<(index + needle.count)]) == needle ? index..<(index + needle.count) : nil
    }
  }

  private static func completionEvidence(_ info: GenerateCompletionInfo) -> CompletionEvidence {
    let stopReason: String
    switch info.stopReason {
    case .stop: stopReason = "stop"
    case .length: stopReason = "length"
    case .cancelled: stopReason = "cancelled"
    }
    return CompletionEvidence(
      stopReason: stopReason,
      generationTokenCount: info.generationTokenCount
    )
  }

  private func engineError(
    input: PreparedPhotoSuggestionInput,
    identity: PhotoSuggestionEngineIdentity?,
    startedAt: Date,
    reason: PhotoSuggestionFailureReason,
    modelCallCount: Int,
    partialRawUTF8: Data?,
    requiresFullAppRestart: Bool
  ) -> PhotoSuggestionEngineError {
    PhotoSuggestionEngineError(
      requestID: input.requestID,
      reason: reason,
      identity: identity,
      analyzedImageSHA256: input.sha256,
      startedAt: startedAt,
      endedAt: Date(),
      modelCallCount: modelCallCount,
      repairCallCount: 0,
      rawOutputUTF8: partialRawUTF8,
      rawOutputUTF8SHA256: partialRawUTF8.map(Self.sha256),
      requiresFullAppRestart: requiresFullAppRestart
    )
  }

  private static func partialEvidenceData(_ records: [Qwen3DecomposedRawFieldRecord]) -> Data? {
    guard !records.isEmpty else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try? encoder.encode(records)
  }

  private static func streamingSHA256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
      digest.update(data: chunk)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func milliseconds(from start: Date, to end: Date) -> Int {
    Int((end.timeIntervalSince(start) * 1_000).rounded())
  }

  private static func hostPeakRSSBytes() -> Int {
    var usage = rusage()
    return getrusage(RUSAGE_SELF, &usage) == 0 ? Int(usage.ru_maxrss) : 0
  }

  /// Same `extra` string format used at the after_load memoryHeadroom site,
  /// factored out so the journal-only memory-headroom insertions (hash_entry,
  /// before_prefill, after_request) do not each hand-roll it.
  private static func mlxMemoryExtra() -> String {
    let memory = Memory.snapshot()
    return "mlx_active=\(memory.activeMemory);mlx_peak=\(memory.peakMemory);mlx_cache=\(memory.cacheMemory)"
  }
}
#endif

#if INTERNAL_QWEN3_QA
// MARK: - Unattended physical-QA autorun
//
// Everything below drives this app through the five frozen synthetic
// controls end-to-end, unattended, then exits the process with a status
// code an overnight runner can check (0 = all five reached a qualified
// review; 3 = any fixture failed, quarantined, or timed out). It writes no
// expected answer, label, or clinical field-value vocabulary anywhere: the
// only strings recorded are the fixture ids below (bookkeeping labels from
// lane/Tools/generate_small_controls.py, not model output) and content
// hashes. See lane/Tools/pin_autorun_controls.py for how the constants
// immediately below are produced and independently re-verified; paste its
// stdout over this block verbatim to regenerate.

// MACHINE-GENERATED by lane/Tools/pin_autorun_controls.py — DO NOT HAND-EDIT.
// Regenerate with: python3 lane/Tools/pin_autorun_controls.py
// Then paste this entire block verbatim over the previous one below.
// Fixed attach order: formed-brown, loose-yellow, red-visible, black-glossy, blank-unusable.
private struct Qwen3QAFixture: Sendable {
  let id: String
  let base64: String
  let sha256: String
  let byteCount: Int
}

private let qwen3QAFixtures: [Qwen3QAFixture] = [
  Qwen3QAFixture(id: "formed-brown", base64: "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", sha256: "4deae91617420220ee5434bfa3305099a3db9c2405ca3846539938b3de8ecda7", byteCount: 2088),
  Qwen3QAFixture(id: "loose-yellow", base64: "iVBORw0KGgoAAAANSUhEUgAAAgAAAAIACAIAAAB7GkOtAAAImUlEQVR42u3dwa3qQBAFUcdD/GRDAmyR2I+DwELjrvN1Imj0bwk9DMf38wYg6HACAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAFwBQABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAABcAUAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEgI7X8+EIIADce8f/z9lBABg+9MIAAoC5lwQQACy+HoAAYPTFAAQAoy8GIAAYfTEAAbD7KAEIgN1HCRAA7D5KgABg91ECBADTjwwgANh9lAABwPQjAwgAph8ZQAAw/cgAAoDpRwYQAEw/MoAAYPqRAQQA048MIACYfmQAAcD0IwMIgPVHA0AATD8yAAJg+pEBEADrjwaAAJh+ZAAEwPqjASAA1h8NAAEw/cgACID1RwNAAKw/GoAAYPqRAQQA648GIABYfzQAAcD6owEIANYfDUAAsP5oAAKA9UcDEADrDxqAAFh/0AAEwPqDBiAA1h80AAGw/qABCID1Bw1AAKw/aAACYP1BAxAA6w8agAAIAAgAAmD9QQMQAOsPGoAAWH/QAARAAEAAEADrDxqAAFh/0AABcAIBQAAQAKw/GoAAYP1RAgQAu4AYIADWH8QAAbD+XGet5QhKgAAIwNiJ/+WfAyoBAmD9Q6MvBkqAAAiA3VcCJUAArL/dVwIZQAAEwPprgAwgANY/Pf0yIAMIgADU118DZAABEIDu+muADCAA1r+7/hogAwiAAAgAMoAAWH8BQAMQAAEorL8GyAACIADeAaABCID1FwBkAAEQAAFAAxAAAfAcADIgAFh/TwKjAQIgAPguIDRAAAQA3waKDAiAAOD3ANAAAbD+bFICp9YABEAAWiVwWA1AAAQgFAMH1AAEQADG5sER0AABEABAAwTA+gMaIAACAGiAAAgAaIDtFgABAA1AAAQANAABEADQAARAAEAAEAABAA1AAAQANAABEADQAAEQAEAABMD6AxogABoAaIAACAAgAAIgAIAGCIAAAAIgAAIAaIAACADz+RlLDRAAAWD4yvsVewEQAAHA7iuBBgiAAGD6ZUAABEAAMP0yoAECIABYfw0QAAHQAKy/BgiAAAgA1l8DNEAABAABEAABEAABILz+GqABAiAAeAeAAAiABiAACIAACAA+BYQGCIAA4DkABEAABABPAiMAAqAB+C4gBEAABADfBooGCIAAsFkJnE4ABEADmNwGRxAAARAAQAAEQADAGxQNEAANgA3/UCEACIAAUP+okgAgABqAT6kKgAAgACQfVRMAAUAA8KCyAAgAGkDv24oEQAAQAARAAAQADSCz/pEG2DQBEAA0wDsABEADEAABEAAEAJ8C0gABQAPwHID1FwA0AE8CC4AACAD4LiABEAANgBuXoHwoOyYAGkClCo4gAAIgAIAACIAGgAAgABoAAoAACAAIgACgASAAAoAGgAAIABoA1l8AEAAQAAFAA0AABEADAAEQAA0ArL8AaAAgAAKgAYAACIAGAAIgABoAWH8B0ABAAARAAwABEAANAKy/AGgAIAACoAGA9RcADQAEQAA0ABAAAdAAwPoLgAyAACAAGgDWHwHQABAABEAGwPoLABoA1l8A0AAQAAFABsD6CwAaAAIgAMgAWH8BQAbA+gsAGgACIADIAFh/AUAGwPoLADIA1l8AkAEQAAFABsD6CwAyANZfAJABsP4CgAyA9RcAZADr73+6AKAEWH8EABnA+iMAKAHWHwFACbD+CABKgPVHAFACrD8CgBhg/QXACRADTL8AgBhg/QUA9ADrLwAwIAnqZfoRAIaHwTsY648AcO9yeNdi+hEA0ADrjwCADJh+BAA0wPojACADph8BABkw/QgAyIDpRwBABkw/AgAyYPoRAJAB048AgAyYfgEAlMDuCwCgBHZfAAAlsPsCACRL4GUVACAUAy+fAAChGHiZBACo9MALIQCuAIkkODICAEOC4QgIAAACAIAAACAAAAgAAAIAIACuACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAgAAAIAgAAAIAAAXO8E67QBEr9EAykAAAAASUVORK5CYII=", sha256: "59ede3a965547888addb6b8b446c17a9c4378ea986275f888e5f5f9f02064a77", byteCount: 2258),
  Qwen3QAFixture(id: "red-visible", base64: "iVBORw0KGgoAAAANSUhEUgAAAgAAAAIACAIAAAB7GkOtAAAH70lEQVR42u3dwY2DMABEUZcE/ddAH1wjcTc1RDnEnnmrV4EjzV92gYzncwNQaDgCAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAFwCgACAIAAACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAACAIAAACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAC4BQABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAA+Mp1nA4BAYA99np9PiYEAALHXSQQADD0woAAgKEXBgQAc48kIABYfPQAAcDcIwkIAEYfMUAAsPjoAQKA0UcMEACMPmKAAGD3UQIEAKOPGCAA2H2UAAHA7qMECIDdt0ooAQJg90EJEAC7D0qAAJh+kAEEwO6DEiAAph9kQACw+6AEAoDpBxkQAEw/yIAAYPpBBgQA0w8yIACYfpABAcD0gwwIAKYfZEAAsP6gAQJg+gEZEADTD8iAAFh/QAMEwPQXm3M6BGRAAKx/7MT/8uMA0QABMP1Foy8GyIAAWH+7rwRogABYf7uvBGiAAJh+668ByIAAWP/q6ZcBNEAArH/7+muABiAA1r93/TVAAxAA69+7/hqgAQiA6RcAZAABsP4CgAYgANa/Yf01AA0QAAFwBYAAIADWXwDQAATA+gsAGoAAWH/PAaABAoD19yQwGiAAWH/vAkIDBEAA8DZQBEAArD8LN8DhowECYP27SuCo0QABEICuEjhYBEAArH9RDBwgGiAA1j82Dw4BDRAAAQAEQACsP6ABAiAAgAAIgPUHNEAABAAQAAEQAEAABMD6AxogAAIACIAACAAgAAJg/QENEAABAAEQAAEABEAABAAQAAEQAEAABEAAAAEQAAEABEAABAAQAAGw/oAGCIAGkM/XWFp/ARAAwlfet9gLgAAIAHZfCQRAAAQA0y8DAiAAAoDplwEBEAABwPprgAAIgABg/TVAAARAALD+GiAAAqABCIAAWH8BEACK118DBEAABABXAAiAAGgAAoD1FwABwF1ACIAACACeA0AABEAD8CQw1l8ABADvAkIABEAD2CADDtP6C4AA0FUCRycAAqABJLfBIVh/AdAAwPoLgACACxQBEAANgAX/UWH9EQANoP1WJeuPAAgA7lIVAAFAA6h8VM36CwAagAeVrb8AoAH0va3I+gsAGoAAWH8BQAOoWf/UBhguARAANKD0CsBwCYAGIAB+/UcANAANsP4IgAygAZHrb6AEQAPQAOuPAGgAMuDPPgiABqAE7vdHADSA/Cp4yxsCIANg+hEADQDrjwBoAFh/BEAGwPQLABoA1l8AkAEw/QKABoD1FwBkAEy/ACADYPoFAA0A6y8AyACYfgFABsD0CwAyAKZfAJABMP0CgAxg+hEAZADTjwAgA5h+BAAlwO4jADJgRDD9CIASgN1HAGQATD8CoARg9xEAJQC7jwAoAdh9BEAJwO4jAEoAdh8BEAMw+gKAEoDdFwDEAKOPACAGGH0EAD3A4iMAiAFGHwFAEjD3CAB6YIUtPgIAkmDuEQAQBkOPAIAwGHoEAKIj4WNCAGCPojgEBAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABABAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABABAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABAAAAQBAAAAQAAAEAAABAEAAABAAAAQAAAEAQAAAEAAABABAABwBgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAgAAAIAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAgAgAAAIAAACAAAAgCAAAAgAAAIAAACAIAAACAAAAgAAP/3AheSf6VXGGHcAAAAAElFTkSuQmCC", sha256: "8f31b49966fdd4c31b2ea2ce1b7062daee81960d4d312b260af48210a5d38c7e", byteCount: 2088),
  Qwen3QAFixture(id: "black-glossy", base64: "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", sha256: "243a63da852fa182a1720ba8af417d3e973da44c2a0bd6d7b255272af83720fd", byteCount: 2087),
  Qwen3QAFixture(id: "blank-unusable", base64: "iVBORw0KGgoAAAANSUhEUgAAAgAAAAIACAIAAAB7GkOtAAAFn0lEQVR42u3VMQ0AAAgEsfevlJUEAXhgpUkV3HKZLgAeigQABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAABqACgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAgAGoAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAAAYgAYABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAIABqABgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgBgACoAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGACAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGACAAQBgAAAYAAAGAIABAGAAABgAAAYAgAEAYAAAGAAABgCAAQBgAAAYAAAGAIABAGAAANwsMwmoDRR+3gIAAAAASUVORK5CYII=", sha256: "5c86ed41bb0cb85ea6cc28b00dd104e7a72b52bbfdcb729dd79a19c87b8438a2", byteCount: 1496),
]
private enum Qwen3QAFixtureVerificationError: Error, Sendable {
  case malformedBase64(String)
  case byteCountMismatch(String)
  case hashMismatch(String)
}

/// Fail-closed decode of one embedded fixture. Mirrors the SHA256 hex idiom
/// used by qwen3PhysicalEvidenceSHA256 above (defined near :80): every byte
/// is re-decoded and re-hashed against the pinned table before use, so a
/// single corrupted or hand-edited literal can never silently reach the
/// model.
private func verifiedFixtureData(_ fixture: Qwen3QAFixture) throws -> Data {
  guard let data = Data(base64Encoded: fixture.base64) else {
    throw Qwen3QAFixtureVerificationError.malformedBase64(fixture.id)
  }
  guard data.count == fixture.byteCount else {
    throw Qwen3QAFixtureVerificationError.byteCountMismatch(fixture.id)
  }
  guard qwen3PhysicalEvidenceSHA256(data) == fixture.sha256 else {
    throw Qwen3QAFixtureVerificationError.hashMismatch(fixture.id)
  }
  return data
}

extension Qwen3PhysicalEvidenceJournal {
  func autorunStarted() {
    append(Qwen3PhysicalEvidenceEvent(event: "qa_autorun_started"))
  }

  func autorunFixtureAttached(ordinal: Int, fixtureID: String, imageSHA256: String) {
    append(Qwen3PhysicalEvidenceEvent(
      event: "qa_autorun_fixture_attached",
      analyzedImageSHA256: imageSHA256,
      detail: "ordinal=\(ordinal);fixture=\(fixtureID)"
    ))
  }

  func autorunCompleted(detail: String) {
    append(Qwen3PhysicalEvidenceEvent(event: "qa_autorun_completed", detail: detail))
  }

  func autorunFailed(detail: String) {
    append(Qwen3PhysicalEvidenceEvent(event: "qa_autorun_failed", detail: detail))
  }

  /// Evidence-only instrumentation for the QA-harness idle-timer/backgrounding
  /// fix: records device-awake state and UIApplication state-transition
  /// events observed during the autorun. Never affects control flow.
  func autorunNote(detail: String) {
    append(Qwen3PhysicalEvidenceEvent(event: "qa_autorun_note", detail: detail))
  }

  /// Evidence-only instrumentation: records the process's headroom before
  /// hitting its dirty-memory jetsam limit (see `os_proc_available_memory()`)
  /// at a named stage. Never affects control flow.
  func memoryHeadroom(
    stage: String,
    profile: Qwen3InternalQAPreprocessProfile,
    extra: String = ""
  ) {
    let availableBytes = os_proc_available_memory()
    var detail = "stage=\(stage);os_proc_available_memory=\(availableBytes)"
    if !extra.isEmpty {
      detail += ";\(extra)"
    }
    append(Qwen3PhysicalEvidenceEvent(event: "memory_headroom", profile: profile, detail: detail))
  }

  /// Evidence-only instrumentation: records headroom immediately after the
  /// bundled snapshot's manifest hashes have been verified, before the
  /// weights are materialized into memory.
  func snapshotVerified(profile: Qwen3InternalQAPreprocessProfile) {
    let availableBytes = os_proc_available_memory()
    append(Qwen3PhysicalEvidenceEvent(
      event: "snapshot_verified", profile: profile,
      detail: "os_proc_available_memory=\(availableBytes)"
    ))
  }
}

extension Qwen3HybridPhotoSuggestionEngine {
  /// Internal QA-only forwarding accessor. Exposes the engine's single
  /// existing evidence journal instance (physicalEvidenceJournal, near
  /// :535) so the autorun coordinator can emit through it without any new
  /// journal instance ever being created. fileprivate (not the default
  /// internal): its return type, Qwen3PhysicalEvidenceJournal, is itself
  /// only file-visible (private at top level == fileprivate), and Swift
  /// requires a declaration's access level to be no wider than any type it
  /// exposes — `internal func … -> Qwen3PhysicalEvidenceJournal` does not
  /// compile.
  fileprivate func qaAutorunEvidenceJournal() -> Qwen3PhysicalEvidenceJournal {
    physicalEvidenceJournal
  }
}

extension Qwen3PhysicalEvidenceJournal {
  /// Evidence-only instrumentation: recorded instead of qa_autorun_started
  /// when a second Qwen3QAAutorunCoordinator.run() call is suppressed
  /// (defense in depth — engine/coordinator singleton-ness is enforced in
  /// NewEntryView.swift). Deliberately not qa_autorun_failed: the overnight
  /// runner's validator treats that event as a whole-file failure, and a
  /// suppressed duplicate start is not a fixture failure.
  func autorunDuplicateSuppressed() {
    append(Qwen3PhysicalEvidenceEvent(event: "qa_autorun_duplicate_suppressed"))
  }
}

/// Drives the five frozen fixtures through the app sequentially and
/// unattended, then exits the process. Armed only when the caller (in
/// NewEntryView.swift, itself gated on --qwen3-decomposed-internal-qa) also
/// observes --qwen3-qa-autorun; this type is never referenced outside
/// INTERNAL_QWEN3_QA.
@MainActor
final class Qwen3QAAutorunCoordinator {
  static let launchArgument = "--qwen3-qa-autorun"
  static let attachFixtureArgumentPrefix = "--qwen3-qa-attach-fixture="

  /// Diagnostic-only (INTERNAL_QWEN3_QA): separates "app loses foreground
  /// ~10s after launch" (external) from "app loses foreground when the next
  /// fixture is attached" (in-app) by holding after clear() for N seconds
  /// before attaching the next fixture, journaling app state each second.
  /// Absent (or <= 0), the autorun's event sequence is unchanged except for
  /// the new at_attach probe notes emitted unconditionally below.
  static let interFixtureDelayArgumentPrefix = "--qwen3-qa-inter-fixture-delay-seconds="

  private static func parsedInterFixtureDelaySeconds(
    from arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> Int {
    guard let match = arguments.first(where: { $0.hasPrefix(interFixtureDelayArgumentPrefix) })
    else { return 0 }
    let valueString = String(match.dropFirst(interFixtureDelayArgumentPrefix.count))
    guard let value = Int(valueString), value > 0 else { return 0 }
    return value
  }

  /// Host-driven device sweep (INTERNAL_QWEN3_QA): when present together
  /// with launchArgument and the QA gate (--qwen3-decomposed-internal-qa),
  /// drives every *.png/*.jpg/*.jpeg pushed (e.g. via devicectl) into
  /// Library/Application Support/Qwen3QAEvalSets/<name>/ through the SAME
  /// attach path the five frozen fixtures use below, INSTEAD of those five
  /// fixtures. Unlike qwen3QAFixtures, these images are never bundled or
  /// hash-pinned; evidence is instead joined back to the host-side manifest
  /// by filename + file_sha256 (see the eval_image / eval_image_skipped
  /// notes in runEvalSet(name:journal:interFixtureDelaySeconds:) below).
  static let evalSetArgumentPrefix = "--qwen3-qa-eval-set="
  private static let evalSetsDirectoryName = "Qwen3QAEvalSets"

  private static func parsedEvalSetName(
    from arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> String? {
    guard let match = arguments.first(where: { $0.hasPrefix(evalSetArgumentPrefix) }) else {
      return nil
    }
    let name = String(match.dropFirst(evalSetArgumentPrefix.count))
    return name.isEmpty ? nil : name
  }

  private let viewModel: NewEntryViewModel
  private let engine: Qwen3HybridPhotoSuggestionEngine
  private let clock = ContinuousClock()
  private var notificationObserverTokens = [NSObjectProtocol]()

  init(viewModel: NewEntryViewModel, engine: Qwen3HybridPhotoSuggestionEngine) {
    self.viewModel = viewModel
    self.engine = engine
  }

  private enum TerminalOutcome {
    case success
    case failure(reason: String)
  }

  /// Defense in depth: NewEntryView.swift's Qwen3QAHarnessState is what
  /// actually prevents a second coordinator from ever being constructed;
  /// this guards the same invariant at the call-site boundary in case
  /// run() is ever reached twice some other way.
  private static var hasStarted = false

  /// Root-cause fix (QA-harness only): during an unattended physical run the
  /// screen auto-locks ~10s after launch, backgrounding the app, and the
  /// second fixture's first Metal command buffer then fails with
  /// "Insufficient Permission (to submit GPU work from background)" — MLX
  /// throws from a Metal completion handler and the process SIGABRTs.
  /// Disabling the idle timer for the coordinator's lifetime keeps the
  /// device awake so GPU submission never crosses that background boundary.
  private func setIdleTimerDisabled(_ disabled: Bool) {
    UIApplication.shared.isIdleTimerDisabled = disabled
  }

  private func appStateDescription() -> String {
    switch UIApplication.shared.applicationState {
    case .active: return "active"
    case .inactive: return "inactive"
    case .background: return "background"
    @unknown default: return "unknown"
    }
  }

  /// Evidence-only: if the idle-timer fix above is ever bypassed (manual
  /// lock button, system alert, Control Center, incoming call, etc.), these
  /// confirm it in the journal rather than silently losing the causal
  /// thread back to the documented root cause. Tokens are kept for the
  /// coordinator's lifetime, mirroring the pattern the engine's own
  /// notification observers use (see Qwen3PhysicalEvidenceJournal, ~:347).
  private func startObservingAppStateNotifications(journal: Qwen3PhysicalEvidenceJournal) {
    guard notificationObserverTokens.isEmpty else { return }
    let center = NotificationCenter.default
    let observedNotifications: [(Notification.Name, String)] = [
      (UIApplication.didEnterBackgroundNotification, "didEnterBackgroundNotification"),
      (UIApplication.willResignActiveNotification, "willResignActiveNotification"),
      (UIApplication.didBecomeActiveNotification, "didBecomeActiveNotification"),
    ]
    notificationObserverTokens = observedNotifications.map { name, label in
      center.addObserver(forName: name, object: nil, queue: nil) { _ in
        Task { await journal.autorunNote(detail: "app_state_event=\(label)") }
      }
    }
  }

  func run() async {
    let journal = await engine.qaAutorunEvidenceJournal()
    guard !Self.hasStarted else {
      await journal.autorunDuplicateSuppressed()
      return
    }
    Self.hasStarted = true
    await journal.autorunStarted()
    setIdleTimerDisabled(true)
    await journal.autorunNote(detail: "idle_timer_disabled=true;app_state=\(appStateDescription())")
    startObservingAppStateNotifications(journal: journal)
    let interFixtureDelaySeconds = Self.parsedInterFixtureDelaySeconds()

    if let evalSetName = Self.parsedEvalSetName() {
      await runEvalSet(
        name: evalSetName,
        journal: journal,
        interFixtureDelaySeconds: interFixtureDelaySeconds
      )
    }

    var analyzedSHAs = [String]()

    if let attachArgument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(Self.attachFixtureArgumentPrefix) }) {
      let fixtureID = String(attachArgument.dropFirst(Self.attachFixtureArgumentPrefix.count))
      guard let fixture = qwen3QAFixtures.first(where: { $0.id == fixtureID }) else {
        await failClosed(journal: journal, ordinal: 1, fixtureID: fixtureID, reason: "attach_fixture_unknown")
      }

      let attachData: Data
      do {
        attachData = try verifiedFixtureData(fixture)
      } catch {
        await failClosed(journal: journal, ordinal: 1, fixtureID: fixture.id, reason: "fixture_verification_failed")
      }

      do {
        try viewModel.prepareImageData(attachData)
      } catch {
        await failClosed(journal: journal, ordinal: 1, fixtureID: fixture.id, reason: "prepare_image_data_threw")
      }

      guard case .reading(_, let attachAnalyzedSHA) = viewModel.flowState else {
        await failClosed(journal: journal, ordinal: 1, fixtureID: fixture.id, reason: "attach_did_not_enter_reading")
      }

      // Attach-only path for the on-device UI test (Step 5): unlike the
      // five-fixture sweep below, we deliberately RETURN rather than exit —
      // the app must stay interactive so an XCUITest can drive review,
      // accept-all, edit, save, relaunch, and PDF export against real UI.
      // fixtureID here (not a new parameter) carries the ";mode=attach_only"
      // tag through the existing autorunFixtureAttached(ordinal:fixtureID:
      // imageSHA256:) helper so its detail string comes out exactly
      // "ordinal=1;fixture=<id>;mode=attach_only" without touching that
      // helper (defined outside this class, in the extension above).
      await journal.autorunFixtureAttached(
        ordinal: 1,
        fixtureID: "\(fixture.id);mode=attach_only",
        imageSHA256: attachAnalyzedSHA
      )
      return
    }

    for (index, fixture) in qwen3QAFixtures.enumerated() {
      let ordinal = index + 1
      let budget: Duration = index == 0 ? .seconds(600) : .seconds(180)

      let data: Data
      do {
        data = try verifiedFixtureData(fixture)
      } catch {
        await failClosed(journal: journal, ordinal: ordinal, fixtureID: fixture.id, reason: "fixture_verification_failed")
      }

      do {
        try viewModel.prepareImageData(data)
      } catch {
        await failClosed(journal: journal, ordinal: ordinal, fixtureID: fixture.id, reason: "prepare_image_data_threw")
      }
      // installPrepared sets .reading(draftID:imageHash:) synchronously,
      // under @MainActor, before prepareImageData(_:) returns to us here —
      // race-free (NewEntryViewModel.swift ~:912). A silent no-op (thrown
      // by nothing: canReplaceOrClear was simply false) or landing on any
      // other state (e.g. .confirmingSubject) is the dangerous case the
      // architect spec calls out: fail closed with a precise reason rather
      // than assume the call took effect or poll until timeout. imageHash
      // here is the sanitized-JPEG hash the engine will actually analyze —
      // not the source PNG's own hash — so it is what later reappears as
      // analyzedImageSHA256 in this same fixture's journal events.
      guard case .reading(_, let analyzedSHA) = viewModel.flowState else {
        await failClosed(journal: journal, ordinal: ordinal, fixtureID: fixture.id, reason: "attach_did_not_enter_reading")
      }

      await journal.autorunNote(
        detail: "probe=at_attach;ordinal=\(ordinal);app_state=\(appStateDescription());brightness=\(String(format: "%.2f", UIScreen.main.brightness))"
      )
      await journal.autorunFixtureAttached(ordinal: ordinal, fixtureID: fixture.id, imageSHA256: analyzedSHA)

      switch await awaitTerminalState(budget: budget) {
      case .failure(let reason):
        await failClosed(journal: journal, ordinal: ordinal, fixtureID: fixture.id, reason: reason)
      case .success:
        analyzedSHAs.append(analyzedSHA)
      }

      let isLastFixture = index == qwen3QAFixtures.count - 1
      guard !isLastFixture else { continue }

      // The terminal-state check above only returns .success once flowState
      // has already published .reviewing, and isBusy is cleared in the same
      // defer-guarded update as flowState in NewEntryViewModel — so isBusy
      // should already be false here. Poll briefly and fail closed rather
      // than assume, since clear() cancels analysisTask and a live cancel
      // trips the engine's quarantine.
      let settleDeadline = clock.now.advanced(by: .seconds(5))
      while viewModel.isBusy, clock.now < settleDeadline {
        try? await Task.sleep(for: .milliseconds(100))
      }
      if viewModel.isBusy {
        await failClosed(journal: journal, ordinal: ordinal, fixtureID: fixture.id, reason: "busy_after_terminal_state")
      }

      viewModel.clear()
      if viewModel.isDraftRecoveryBlocked || !viewModel.canReplaceOrClear {
        await failClosed(journal: journal, ordinal: ordinal, fixtureID: fixture.id, reason: "post_clear_blocked")
      }

      if interFixtureDelaySeconds > 0 {
        let nextOrdinal = ordinal + 1
        for second in 1...interFixtureDelaySeconds {
          try? await Task.sleep(for: .seconds(1))
          await journal.autorunNote(
            detail: "probe=pre_attach;ordinal=\(nextOrdinal);t=\(second);app_state=\(appStateDescription());brightness=\(String(format: "%.2f", UIScreen.main.brightness));idle_timer_disabled=\(UIApplication.shared.isIdleTimerDisabled)"
          )
        }
      }
    }

    let detail = "fixtures=\(qwen3QAFixtures.count);analyzed=\(analyzedSHAs.joined(separator: ","))"
    await journal.autorunCompleted(detail: detail)
    setIdleTimerDisabled(false)
    exit(0)
  }

  /// Instead-of-the-five-frozen-fixtures mode: enumerates externally pushed
  /// images and drives each through the same attach→analyze mechanism as
  /// the loop in run() above (prepareImageData(_:) → confirm .reading →
  /// awaitTerminalState → settle/clear), reusing failClosed for any
  /// analysis-level problem (timeout, manual fallback, failed state,
  /// requires-full-app-restart, busy-after-terminal, post-clear-blocked) so
  /// those keep exactly the same exit(3)/qa_autorun_failed semantics as the
  /// frozen sweep. A file that cannot be read or attached is instead
  /// skipped (eval_image_skipped) and the sweep continues: unlike the
  /// hash-pinned qwen3QAFixtures, these images are not pre-verified, so one
  /// bad file must not abort evidence collection for the rest of the set.
  private func runEvalSet(
    name: String,
    journal: Qwen3PhysicalEvidenceJournal,
    interFixtureDelaySeconds: Int
  ) async -> Never {
    let imageURLs = Self.evalSetImageURLs(setName: name)
    guard !imageURLs.isEmpty else {
      await journal.autorunNote(detail: "eval_set_missing=\(name)")
      setIdleTimerDisabled(false)
      exit(0)
    }

    // A launch that follows an earlier sweep in the same container restores
    // that sweep's draft via DraftSnapshotStore, and prepareImageData
    // silently no-ops while canReplaceOrClear is false — observed as 22×
    // attach_did_not_enter_reading when this sweep ran after the frozen
    // sweep. Start from a cleared entry state, and fail closed if the
    // restored state cannot be cleared.
    viewModel.clear()
    if viewModel.isDraftRecoveryBlocked || !viewModel.canReplaceOrClear {
      await journal.autorunNote(detail: "eval_set_blocked=restored_state_not_clearable")
      setIdleTimerDisabled(false)
      exit(3)
    }

    for (index, imageURL) in imageURLs.enumerated() {
      let ordinal = index + 1
      let filename = imageURL.lastPathComponent
      let fixtureLabel = "eval_set=\(name);file=\(filename)"
      let budget: Duration = index == 0 ? .seconds(600) : .seconds(180)

      let data: Data
      do {
        data = try Data(contentsOf: imageURL)
      } catch {
        await journal.autorunNote(detail: "eval_image_skipped=\(filename);reason=read_failed")
        continue
      }

      // Journaled before attach (and therefore before analysis starts) so
      // host-side scoring can join this run's journal to the manifest by
      // filename even if analysis itself later crashes the process.
      await journal.autorunNote(
        detail: "eval_image=\(filename);file_sha256=\(qwen3PhysicalEvidenceSHA256(data))"
      )

      do {
        try viewModel.prepareImageData(data)
      } catch {
        await journal.autorunNote(detail: "eval_image_skipped=\(filename);reason=prepare_image_data_threw")
        continue
      }

      guard case .reading = viewModel.flowState else {
        await journal.autorunNote(detail: "eval_image_skipped=\(filename);reason=attach_did_not_enter_reading")
        continue
      }

      switch await awaitTerminalState(budget: budget) {
      case .failure(let reason):
        await failClosed(journal: journal, ordinal: ordinal, fixtureID: fixtureLabel, reason: reason)
      case .success:
        break
      }

      let isLastImage = index == imageURLs.count - 1
      guard !isLastImage else { continue }

      // Mirrors the settle-then-clear step between frozen fixtures above:
      // clear() cancels analysisTask, and a live cancel trips the engine's
      // quarantine, so we poll briefly rather than assume isBusy is already
      // false.
      let settleDeadline = clock.now.advanced(by: .seconds(5))
      while viewModel.isBusy, clock.now < settleDeadline {
        try? await Task.sleep(for: .milliseconds(100))
      }
      if viewModel.isBusy {
        await failClosed(journal: journal, ordinal: ordinal, fixtureID: fixtureLabel, reason: "busy_after_terminal_state")
      }

      viewModel.clear()
      if viewModel.isDraftRecoveryBlocked || !viewModel.canReplaceOrClear {
        await failClosed(journal: journal, ordinal: ordinal, fixtureID: fixtureLabel, reason: "post_clear_blocked")
      }

      if interFixtureDelaySeconds > 0 {
        let nextOrdinal = ordinal + 1
        for second in 1...interFixtureDelaySeconds {
          try? await Task.sleep(for: .seconds(1))
          await journal.autorunNote(
            detail: "probe=pre_attach;ordinal=\(nextOrdinal);t=\(second);app_state=\(appStateDescription());brightness=\(String(format: "%.2f", UIScreen.main.brightness));idle_timer_disabled=\(UIApplication.shared.isIdleTimerDisabled)"
          )
        }
      }
    }

    await journal.autorunCompleted(detail: "eval_set=\(name);images=\(imageURLs.count)")
    setIdleTimerDisabled(false)
    exit(0)
  }

  /// Enumerates Library/Application Support/Qwen3QAEvalSets/<name>/ for
  /// *.png/*.jpg/*.jpeg files pushed in beforehand (e.g. via devicectl),
  /// sorted by filename. Returns an empty array if the directory is
  /// missing, unreadable, or has no matching files — runEvalSet(name:
  /// journal:interFixtureDelaySeconds:) treats all three identically as
  /// "eval_set_missing".
  private static func evalSetImageURLs(setName: String) -> [URL] {
    let manager = FileManager.default
    guard let appSupport = try? manager.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true
    ) else { return [] }
    let directory = appSupport
      .appendingPathComponent(evalSetsDirectoryName, isDirectory: true)
      .appendingPathComponent(setName, isDirectory: true)
    guard let entries = try? manager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    ) else { return [] }
    let allowedExtensions: Set<String> = ["png", "jpg", "jpeg"]
    return entries
      .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  private func awaitTerminalState(budget: Duration) async -> TerminalOutcome {
    let deadline = clock.now.advanced(by: budget)
    while clock.now < deadline {
      if viewModel.requiresFullAppRestart {
        return .failure(reason: "requires_full_app_restart")
      }
      switch viewModel.flowState {
      case .reviewing:
        if viewModel.hasAnalysis { return .success }
      case .manual:
        return .failure(reason: "manual_fallback")
      case .failed:
        return .failure(reason: "failed_state")
      default:
        break
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return .failure(reason: "timeout")
  }

  private func failClosed(
    journal: Qwen3PhysicalEvidenceJournal,
    ordinal: Int,
    fixtureID: String,
    reason: String
  ) async -> Never {
    await journal.autorunFailed(detail: "ordinal=\(ordinal);fixture=\(fixtureID);reason=\(reason)")
    setIdleTimerDisabled(false)
    exit(3)
  }
}
#endif
