import Foundation
import CryptoKit
import GITimelineCore

/// Conservative route-isolation identity for the LiteRT engine and its cache.
/// It intentionally includes some route provenance that may be legacy-only or
/// conversation-scoped; prompt, sampler, and parser settings remain excluded.
struct LiteRTEngineCacheProfileV1: Codable, Equatable, Sendable {
  static let currentFormat = "gi-litert-engine-cache-profile-v2"

  let format: String
  let modelDescriptorID: String
  let modelCacheNamespace: String
  let modelArtifactFilename: String
  let modelExpectedBytes: Int64
  let modelSHA256: String
  let liteRTLMRevision: String
  let swiftWrapperCompileInputSHA256: String
  let linkedRuntimeIdentity: String
  let engineBackend: String
  let visionBackend: String
  let audioBackend: String
  let mainCPUThreadCount: String
  let maxNumImages: String
  let maxNumTokens: Int
  let cacheMode: String
  let mainThreadPolicy: String
  let visionThreadPolicy: String
  let audioThreadPolicy: String
  let textLoraPolicy: String
  let audioLoraPolicy: String
  let benchmarkMode: String
  let speculativeDecodingMode: String
  let visualTokenBudget: String

  enum CodingKeys: String, CodingKey {
    case format
    case modelDescriptorID = "model_descriptor_id"
    case modelCacheNamespace = "model_cache_namespace"
    case modelArtifactFilename = "model_artifact_filename"
    case modelExpectedBytes = "model_expected_bytes"
    case modelSHA256 = "model_sha256"
    case liteRTLMRevision = "litert_lm_revision"
    case swiftWrapperCompileInputSHA256 = "swift_wrapper_compile_input_sha256"
    case linkedRuntimeIdentity = "linked_runtime_identity"
    case engineBackend = "engine_backend"
    case visionBackend = "vision_backend"
    case audioBackend = "audio_backend"
    case mainCPUThreadCount = "main_cpu_thread_count"
    case maxNumImages = "max_num_images"
    case maxNumTokens = "max_num_tokens"
    case cacheMode = "cache_mode"
    case mainThreadPolicy = "main_thread_policy"
    case visionThreadPolicy = "vision_thread_policy"
    case audioThreadPolicy = "audio_thread_policy"
    case textLoraPolicy = "text_lora_policy"
    case audioLoraPolicy = "audio_lora_policy"
    case benchmarkMode = "benchmark_mode"
    case speculativeDecodingMode = "speculative_decoding_mode"
    case visualTokenBudget = "visual_token_budget"
  }

  init(descriptor: ModelDescriptor, configuration: InferenceConfiguration) {
    format = Self.currentFormat
    modelDescriptorID = descriptor.id
    modelCacheNamespace = descriptor.cacheNamespace
    modelArtifactFilename = descriptor.artifactFilename
    modelExpectedBytes = descriptor.expectedBytes
    modelSHA256 = descriptor.expectedSHA256.lowercased()
    liteRTLMRevision = AppFolders.liteRTLMRevision
    swiftWrapperCompileInputSHA256 = AppFolders.liteRTLMWrapperCompileInputSHA256
    linkedRuntimeIdentity = "vendored-swift-wrapper@\(swiftWrapperCompileInputSHA256)+CLiteRTLM@\(AppFolders.liteRTLMRevision)"
    engineBackend = configuration.engineBackend
    visionBackend = configuration.visionBackend
    audioBackend = "disabled"
    mainCPUThreadCount = configuration.mainCPUThreadCount.map(String.init)
      ?? "runtime-default"
    maxNumImages = configuration.maxNumImages.map(String.init)
      ?? "runtime-default"
    maxNumTokens = configuration.maxNumTokens
    cacheMode = "explicit-app-scoped-directory"
    mainThreadPolicy = configuration.engineBackend == "cpu"
      ? (configuration.mainCPUThreadCount.map { "explicit-\($0)" }
        ?? "litert-lm-revision-default")
      : "not-applicable"
    visionThreadPolicy = configuration.visionBackend == "cpu"
      ? "litert-lm-revision-default"
      : "not-applicable"
    audioThreadPolicy = "disabled"
    textLoraPolicy = "disabled"
    audioLoraPolicy = "disabled"
    benchmarkMode = "disabled"
    speculativeDecodingMode = "runtime-default-nil"
    visualTokenBudget = configuration.visualTokenBudget.map(String.init)
      ?? "runtime-default"
  }

  var canonicalData: Data {
    get throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return try encoder.encode(self)
    }
  }

  var sha256: String {
    get throws {
      try SHA256.hash(data: canonicalData).map {
        String(format: "%02x", $0)
      }.joined()
    }
  }

  func matches(
    descriptor: ModelDescriptor,
    configuration: InferenceConfiguration
  ) -> Bool {
    self == Self(descriptor: descriptor, configuration: configuration)
  }
}

/// Path-free explanation of how the derived LiteRT cache was selected. This
/// never describes journal state and is used only by internal diagnostics.
enum ModelCacheDisposition: String, Equatable, Sendable {
  case validatedVersionedReuse = "validated_versioned_reuse"
  case compatibleLegacyReuse = "compatible_legacy_reuse"
  case coldVersionedCache = "cold_versioned_cache"
  case freshDiagnosticCache = "fresh_diagnostic_cache"
}

struct ModelCacheResolution: Equatable, Sendable {
  let url: URL
  let disposition: ModelCacheDisposition
}

enum DemoDataPolicy {
  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  static let notePrefix = "Synthetic Gemma demo"
  static func isSyntheticDemo(_ entry: EntryRecord) -> Bool {
    entry.demoKind != nil
  }
  static func isSyntheticDemoNote(_ note: String?) -> Bool {
    note?.hasPrefix(notePrefix) == true
  }
  #endif
  static func presentedNote(for entry: EntryRecord) -> String? {
    #if DEBUG || HACKATHON_EMBEDDED_GEMMA
    guard let demoKind = entry.demoKind else { return entry.note }
    return "Bundled synthetic \(demoKind) demo image"
    #else
    return entry.note
    #endif
  }
}

enum AppFolders {
  static let liteRTLMRevision = "2117fc4314670e00047bc8469783f02a68c33f0c"
  static let liteRTLMWrapperCompileInputSHA256 =
    "22c81184a1bad821ea7c890c167fa0a75089ba774beaf8176a0d3b99290d842d"
  /// V5 conservatively isolates derived cache bytes by the vendored wrapper
  /// identity and reviewed route configuration. The identity includes the
  /// app's one-photo boundary and conversation visual-token budget even though
  /// LiteRT v0.15's native max-images setter is legacy-only and the visual
  /// budget is conversation-scoped. Earlier schemas remain untouched and
  /// cannot qualify this profile as warm.
  static let liteRTCacheSchemaVersion = "v5"
  static let modelCacheCompletionReceiptFilename =
    ".gi-litert-engine-complete-v2.json"

  static func liteRTCacheSchema(
    for profile: LiteRTEngineCacheProfileV1
  ) throws -> String {
    "litert-\(liteRTLMRevision)-\(liteRTCacheSchemaVersion)-\(try profile.sha256)"
  }

  private struct ModelCacheCompletionReceipt: Codable, Equatable {
    static let currentFormat = "gi-litert-engine-cache-complete-v2"
    static let engineReadinessStage = "engine-initialized-only"

    let format: String
    let cacheSchema: String
    let engineProfileFormat: String
    let engineProfileSHA256: String
    let readinessStage: String
    let modelDescriptorID: String
    let modelSHA256: String
    let liteRTLMRevision: String
    let cachePath: String
    let cacheIdentity: String
    let cacheManifestSHA256: String
    let cacheFileCount: Int

    enum CodingKeys: String, CodingKey {
      case format
      case cacheSchema = "cache_schema"
      case engineProfileFormat = "engine_profile_format"
      case engineProfileSHA256 = "engine_profile_sha256"
      case readinessStage = "readiness_stage"
      case modelDescriptorID = "model_descriptor_id"
      case modelSHA256 = "model_sha256"
      case liteRTLMRevision = "litert_lm_revision"
      case cachePath = "cache_path"
      case cacheIdentity = "cache_identity"
      case cacheManifestSHA256 = "cache_manifest_sha256"
      case cacheFileCount = "cache_file_count"
    }
  }

  private struct ModelCacheManifestEntry: Codable {
    let relativePath: String
    let byteCount: UInt64
    let fileIdentity: String
    /// APFS changes this opaque identifier when file contents change. Binding
    /// it avoids a multi-gigabyte launch-time rehash while still invalidating a
    /// receipt after a same-inode, same-size in-place mutation. If the volume
    /// cannot provide an identifier, receipt validation fails closed.
    let contentGenerationIdentifier: String

    enum CodingKeys: String, CodingKey {
      case relativePath = "relative_path"
      case byteCount = "byte_count"
      case fileIdentity = "file_identity"
      case contentGenerationIdentifier = "content_generation_identifier"
    }
  }

  private struct ModelCacheManifest {
    let sha256: String
    let fileCount: Int
  }
  static let restartRetentionLine = "Saved logs are designed to remain in this app's local container when you close and reopen GI Journal, restart this iPhone and unlock it, or install an in-place app update."
  static let dataLossLine = "GI Journal stores its live journal on this iPhone and does not upload it to the developer. GI Journal requests exclusion from automatic device backup; iOS controls backup behavior. Deleting or reinstalling GI Journal, erasing, losing, or resetting this iPhone, or a storage failure may permanently lose entries and photos. You can create a photo-inclusive PDF for your records, but a PDF cannot restore the journal or create journal entries."

  static func applicationSupport() throws -> URL {
    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("GITimeline", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try excludeFromBackup(base)
    try protect(base)
    return base
  }
  static func drafts() throws -> URL { try directory("Drafts", excludedFromBackup: true) }
  /// Per-entry unfinished edits are local journal state, separate from the
  /// new-entry photo draft and excluded from automatic backup with the live
  /// journal. No photo bytes, paths, or model response are stored here.
  static func entryEditDrafts() throws -> URL {
    let url = try drafts().appendingPathComponent("EntryEdits", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try excludeFromBackup(url)
    try protect(url)
    return url
  }
  static func images() throws -> URL { try directory("Images", excludedFromBackup: true) }
  /// Temporary, protected and excluded from device backup. Journal images and
  /// the SwiftData store never live under this directory.
  static func exports() throws -> URL { try directory("Exports", excludedFromBackup: true) }
  static func models() throws -> URL { try directory("Models", excludedFromBackup: true) }
  static func modelDirectory(for descriptor: ModelDescriptor) throws -> URL {
    let url = try models().appendingPathComponent(descriptor.cacheNamespace, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try protect(url)
    return url
  }
  static func modelURL(for descriptor: ModelDescriptor) throws -> URL {
    try modelDirectory(for: descriptor).appendingPathComponent(descriptor.artifactFilename)
  }
  /// LiteRT program/weight caches are derived from the signed model and can be
  /// regenerated fully offline. Keep them in Library/Caches, separate from the
  /// journal and imported-model tree, so iOS may purge them and so they remain
  /// available after the first device unlock. An exact, structurally safe
  /// cache created by an earlier version under Application Support is reused
  /// in place rather than abandoned or copied; that upgrade path never reads
  /// outside the derived LiteRT cache subtree and never requires a second
  /// model-sized allocation.
  static func modelCache(
    for descriptor: ModelDescriptor,
    configuration: InferenceConfiguration = .runtimeDefault,
    cachesDirectory: URL? = nil,
    legacyApplicationSupportRoot: URL? = nil,
    availableCapacityOverride: Int64? = nil,
    allowLegacyApplicationSupportReuse: Bool = true
  ) throws -> URL {
    try modelCacheResolution(
      for: descriptor,
      configuration: configuration,
      cachesDirectory: cachesDirectory,
      legacyApplicationSupportRoot: legacyApplicationSupportRoot,
      availableCapacityOverride: availableCapacityOverride,
      allowLegacyApplicationSupportReuse: allowLegacyApplicationSupportReuse
    ).url
  }

  static func modelCacheResolution(
    for descriptor: ModelDescriptor,
    configuration: InferenceConfiguration = .runtimeDefault,
    cachesDirectory: URL? = nil,
    legacyApplicationSupportRoot: URL? = nil,
    availableCapacityOverride: Int64? = nil,
    allowLegacyApplicationSupportReuse: Bool = true
  ) throws -> ModelCacheResolution {
    try modelCacheResolution(
      for: descriptor,
      profile: LiteRTEngineCacheProfileV1(
        descriptor: descriptor,
        configuration: configuration
      ),
      cachesDirectory: cachesDirectory,
      legacyApplicationSupportRoot: legacyApplicationSupportRoot,
      availableCapacityOverride: availableCapacityOverride,
      allowLegacyApplicationSupportReuse: allowLegacyApplicationSupportReuse
    )
  }

  static func modelCache(
    for descriptor: ModelDescriptor,
    profile: LiteRTEngineCacheProfileV1,
    cachesDirectory: URL? = nil,
    legacyApplicationSupportRoot: URL? = nil,
    availableCapacityOverride: Int64? = nil,
    allowLegacyApplicationSupportReuse: Bool = true
  ) throws -> URL {
    try modelCacheResolution(
      for: descriptor,
      profile: profile,
      cachesDirectory: cachesDirectory,
      legacyApplicationSupportRoot: legacyApplicationSupportRoot,
      availableCapacityOverride: availableCapacityOverride,
      allowLegacyApplicationSupportReuse: allowLegacyApplicationSupportReuse
    ).url
  }

  static func modelCacheResolution(
    for descriptor: ModelDescriptor,
    profile: LiteRTEngineCacheProfileV1,
    cachesDirectory: URL? = nil,
    legacyApplicationSupportRoot: URL? = nil,
    availableCapacityOverride: Int64? = nil,
    allowLegacyApplicationSupportReuse: Bool = true
  ) throws -> ModelCacheResolution {
    guard profile.modelDescriptorID == descriptor.id,
      profile.modelCacheNamespace == descriptor.cacheNamespace,
      profile.modelArtifactFilename == descriptor.artifactFilename,
      profile.modelExpectedBytes == descriptor.expectedBytes,
      profile.modelSHA256.caseInsensitiveCompare(descriptor.expectedSHA256) == .orderedSame,
      profile.liteRTLMRevision == liteRTLMRevision
    else {
      throw GITimelineError.invalidModelDescriptor
    }
    let cacheSchema = try liteRTCacheSchema(for: profile)
    // A custom Caches root is a test seam and must not accidentally discover
    // or reuse the host app's real Application Support cache. Tests that cover
    // upgrade behavior pass both roots explicitly.
    let shouldConsiderLegacyCache = allowLegacyApplicationSupportReuse
      && (cachesDirectory == nil || legacyApplicationSupportRoot != nil)
    let systemCaches: URL
    if let cachesDirectory {
      systemCaches = cachesDirectory
    } else {
      systemCaches = try FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    }
    if FileManager.default.fileExists(atPath: systemCaches.path) {
      let values = try systemCaches.resourceValues(forKeys: [.isSymbolicLinkKey])
      guard values.isSymbolicLink != true else {
        throw GITimelineError.invalidModelDescriptor
      }
    }
    let resolvedSystemCaches = systemCaches.resolvingSymlinksInPath()
      .standardizedFileURL
    let requestedApplicationSupportRoot: URL
    if let legacyApplicationSupportRoot {
      requestedApplicationSupportRoot = legacyApplicationSupportRoot
    } else {
      requestedApplicationSupportRoot = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
      ).appendingPathComponent("GITimeline", isDirectory: true)
    }
    if FileManager.default.fileExists(
      atPath: requestedApplicationSupportRoot.path
    ) {
      let values = try requestedApplicationSupportRoot.resourceValues(
        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
      )
      guard values.isDirectory == true,
        values.isSymbolicLink != true,
        (try? FileManager.default.destinationOfSymbolicLink(
          atPath: requestedApplicationSupportRoot.path
        )) == nil
      else {
        throw GITimelineError.invalidModelDescriptor
      }
    } else if (try? FileManager.default.destinationOfSymbolicLink(
      atPath: requestedApplicationSupportRoot.path
    )) != nil {
      throw GITimelineError.invalidModelDescriptor
    }
    let applicationSupportRoot = requestedApplicationSupportRoot
      .resolvingSymlinksInPath().standardizedFileURL
    guard !isSameOrDescendant(resolvedSystemCaches, of: applicationSupportRoot),
      !isSameOrDescendant(applicationSupportRoot, of: resolvedSystemCaches)
    else {
      throw GITimelineError.invalidModelDescriptor
    }
    let appCaches = resolvedSystemCaches.appendingPathComponent(
      "GITimeline",
      isDirectory: true
    )
    let liteRTRoot = appCaches.appendingPathComponent("LiteRT", isDirectory: true)
    let schemaRoot = liteRTRoot.appendingPathComponent(
      cacheSchema,
      isDirectory: true
    )
    let descriptorRoot = schemaRoot.appendingPathComponent(
      descriptor.cacheNamespace,
      isDirectory: true
    )
    let cache = descriptorRoot.appendingPathComponent("Cache", isDirectory: true)
    for candidate in [appCaches, liteRTRoot, schemaRoot, descriptorRoot, cache] {
      if FileManager.default.fileExists(atPath: candidate.path) {
        let values = try candidate.resourceValues(
          forKeys: [.isSymbolicLinkKey, .isDirectoryKey]
        )
        guard values.isSymbolicLink != true,
          values.isDirectory == true,
          (try? FileManager.default.destinationOfSymbolicLink(
            atPath: candidate.path
          )) == nil
        else {
          throw GITimelineError.invalidModelDescriptor
        }
      }
    }
    if validModelCacheCompletionReceipt(
      for: descriptor,
      profile: profile,
      cacheURL: cache
    ) {
      try hardenCachesRootDirectories(
        [appCaches, liteRTRoot, schemaRoot, descriptorRoot, cache]
      )
      return ModelCacheResolution(
        url: cache,
        disposition: .validatedVersionedReuse
      )
    }

    // Before the Caches layout existed, LiteRT wrote here. Reuse only this
    // exact cache subtree when the immutable runtime configuration permits it.
    // The shipping raw-photo configuration deliberately opts out: historical
    // caches at this location can belong to another configuration and are not
    // valid evidence for CPU-text/CPU-vision raw-photo engine readiness. Opting out leaves the
    // legacy derived cache untouched and selects the versioned Library/Caches
    // location. A missing receipt is allowed solely for the one-way compatible
    // upgrade case; once a receipt exists it must validate, so malformed or
    // stale upgrade state cannot silently qualify as warm.
    let legacyCache = applicationSupportRoot
      .appendingPathComponent("Models", isDirectory: true)
      .appendingPathComponent(descriptor.cacheNamespace, isDirectory: true)
      .appendingPathComponent("Cache", isDirectory: true)
    if shouldConsiderLegacyCache {
      if let reusableLegacyCache = try reusableLegacyModelCache(
        for: descriptor,
        profile: profile,
        cacheURL: legacyCache
      ) {
        try excludeFromBackup(reusableLegacyCache)
        try protectUntilFirstUserAuthentication(reusableLegacyCache)
        return ModelCacheResolution(
          url: reusableLegacyCache,
          disposition: .compatibleLegacyReuse
        )
      }
    }

    // Reclaim an invalid exact-profile derived cache before measuring free
    // space. Otherwise stale cache bytes can keep capacity below the gate and
    // permanently prevent their own safe regeneration. This reset cannot
    // cross into an earlier schema, another V5 profile, Application Support,
    // or journal data.
    try resetInvalidVersionedCacheIfNeeded(
      for: descriptor,
      profile: profile,
      cacheURL: cache,
      descriptorRoot: descriptorRoot
    )
    let capacity = try availableCapacityOverride ?? resolvedSystemCaches.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey]
    ).volumeAvailableCapacityForImportantUsage
    guard let capacity, capacity >= descriptor.expectedBytes else {
      throw GITimelineError.insufficientModelStorage
    }
    try FileManager.default.createDirectory(
      at: resolvedSystemCaches,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: cache,
      withIntermediateDirectories: true
    )
    let resolvedCache = cache.resolvingSymlinksInPath().standardizedFileURL
    guard isSameOrDescendant(resolvedCache, of: resolvedSystemCaches),
      !isSameOrDescendant(resolvedCache, of: applicationSupportRoot)
    else {
      throw GITimelineError.invalidModelDescriptor
    }
    try hardenCachesRootDirectories(
      [appCaches, liteRTRoot, schemaRoot, descriptorRoot, cache]
    )
    return ModelCacheResolution(
      url: cache,
      disposition: .coldVersionedCache
    )
  }

  private static func hardenCachesRootDirectories(_ directories: [URL]) throws {
    for directory in directories {
      try excludeFromBackup(directory)
      try protectUntilFirstUserAuthentication(directory)
    }
  }

  /// An invalid V5 receipt must never hand a nonempty cache from the wrong or
  /// damaged profile back to LiteRT. Only the exact recreatable V5 cache and its
  /// adjacent receipt are removed; earlier schemas, legacy Application Support, journal,
  /// draft and image paths are structurally outside this boundary.
  private static func resetInvalidVersionedCacheIfNeeded(
    for descriptor: ModelDescriptor,
    profile: LiteRTEngineCacheProfileV1,
    cacheURL: URL,
    descriptorRoot: URL
  ) throws {
    let expectedSchema = try liteRTCacheSchema(for: profile)
    let normalizedRoot = descriptorRoot.standardizedFileURL
    let normalizedCache = cacheURL.standardizedFileURL
    guard normalizedRoot.lastPathComponent == descriptor.cacheNamespace,
      normalizedRoot.deletingLastPathComponent().lastPathComponent == expectedSchema,
      normalizedCache.deletingLastPathComponent() == normalizedRoot,
      normalizedCache.lastPathComponent == "Cache"
    else {
      throw GITimelineError.invalidModelDescriptor
    }
    let receiptURL = modelCacheCompletionReceiptURL(for: normalizedCache)
    guard receiptURL.deletingLastPathComponent() == normalizedRoot else {
      throw GITimelineError.invalidModelDescriptor
    }
    for target in [receiptURL, normalizedCache] {
      let exists = FileManager.default.fileExists(atPath: target.path)
        || (try? FileManager.default.destinationOfSymbolicLink(
          atPath: target.path
        )) != nil
      if exists { try FileManager.default.removeItem(at: target) }
    }
  }

  private static func reusableLegacyModelCache(
    for descriptor: ModelDescriptor,
    profile: LiteRTEngineCacheProfileV1,
    cacheURL: URL
  ) throws -> URL? {
    let receiptURL = modelCacheCompletionReceiptURL(for: cacheURL)
    let receiptExists = FileManager.default.fileExists(atPath: receiptURL.path)
      || (try? FileManager.default.destinationOfSymbolicLink(
        atPath: receiptURL.path
      )) != nil
    let cacheExists = FileManager.default.fileExists(atPath: cacheURL.path)
      || (try? FileManager.default.destinationOfSymbolicLink(
        atPath: cacheURL.path
      )) != nil
    guard cacheExists else {
      // A receipt without its cache is invalid upgrade state, not permission
      // to allocate another model-sized cache beside unknown legacy residue.
      if receiptExists { throw GITimelineError.invalidModelReceipt }
      return nil
    }
    let cache = try validatedSharedModelCacheURL(
      cacheURL,
      descriptor: descriptor,
      profile: profile
    )
    let manifest = try modelCacheManifest(at: cache)
    guard manifest.fileCount > 0 else {
      if receiptExists { throw GITimelineError.invalidModelReceipt }
      return nil
    }
    if receiptExists {
      guard validModelCacheCompletionReceipt(
        for: descriptor,
        profile: profile,
        cacheURL: cache
      ) else {
        throw GITimelineError.invalidModelReceipt
      }
    }
    return cache
  }

  /// Records that LiteRT successfully initialized its engine with this exact
  /// shared cache. Callers first invoke this after `Engine.initialize()` and
  /// refresh it after successful conversation construction because configured
  /// modality caches may be populated lazily. Cache contents alone are
  /// deliberately never treated as proof of a complete warm cache.
  static func recordSuccessfulEngineInitializationIfSharedModelCache(
    for descriptor: ModelDescriptor,
    profile: LiteRTEngineCacheProfileV1,
    cacheURL: URL
  ) throws {
    guard let cache = try? validatedSharedModelCacheURL(
      cacheURL,
      descriptor: descriptor,
      profile: profile
    ) else { return }
    try recordSuccessfulEngineInitialization(
      for: descriptor,
      profile: profile,
      cacheURL: cache
    )
  }

  /// Strict writer used by the shared-cache success hook and deterministic
  /// validation tests. Unlike the hook above, an invalid shared-cache identity
  /// is an error rather than a diagnostic-cache no-op.
  static func recordSuccessfulEngineInitialization(
    for descriptor: ModelDescriptor,
    configuration: InferenceConfiguration = .runtimeDefault,
    cacheURL: URL
  ) throws {
    try recordSuccessfulEngineInitialization(
      for: descriptor,
      profile: LiteRTEngineCacheProfileV1(
        descriptor: descriptor,
        configuration: configuration
      ),
      cacheURL: cacheURL
    )
  }

  static func recordSuccessfulEngineInitialization(
    for descriptor: ModelDescriptor,
    profile: LiteRTEngineCacheProfileV1,
    cacheURL: URL
  ) throws {
    let cache = try validatedSharedModelCacheURL(
      cacheURL,
      descriptor: descriptor,
      profile: profile
    )
    let manifest = try modelCacheManifest(at: cache)
    guard manifest.fileCount > 0 else {
      throw GITimelineError.invalidModelDescriptor
    }
    let receiptURL = modelCacheCompletionReceiptURL(for: cache)
    if FileManager.default.fileExists(atPath: receiptURL.path) {
      let values = try receiptURL.resourceValues(
        forKeys: [.isSymbolicLinkKey, .isRegularFileKey]
      )
      guard values.isSymbolicLink != true,
        values.isRegularFile == true,
        (try? FileManager.default.destinationOfSymbolicLink(
          atPath: receiptURL.path
        )) == nil
      else {
        throw GITimelineError.invalidModelDescriptor
      }
    } else if (try? FileManager.default.destinationOfSymbolicLink(
      atPath: receiptURL.path
    )) != nil {
      throw GITimelineError.invalidModelDescriptor
    }

    let receipt = ModelCacheCompletionReceipt(
      format: ModelCacheCompletionReceipt.currentFormat,
      cacheSchema: try liteRTCacheSchema(for: profile),
      engineProfileFormat: profile.format,
      engineProfileSHA256: try profile.sha256,
      readinessStage: ModelCacheCompletionReceipt.engineReadinessStage,
      modelDescriptorID: descriptor.id,
      modelSHA256: descriptor.expectedSHA256,
      liteRTLMRevision: liteRTLMRevision,
      cachePath: cache.path,
      cacheIdentity: try modelCacheIdentity(at: cache),
      cacheManifestSHA256: manifest.sha256,
      cacheFileCount: manifest.fileCount
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(receipt).write(to: receiptURL, options: .atomic)
    try excludeFromBackup(receiptURL)
    try protectUntilFirstUserAuthentication(receiptURL)
    guard validModelCacheCompletionReceipt(
      for: descriptor,
      profile: profile,
      cacheURL: cache
    ) else {
      throw GITimelineError.invalidModelReceipt
    }
  }

  static func modelCacheCompletionReceiptURL(for cacheURL: URL) -> URL {
    cacheURL.standardizedFileURL.deletingLastPathComponent()
      .appendingPathComponent(
        modelCacheCompletionReceiptFilename,
        isDirectory: false
      )
  }

  private static func validModelCacheCompletionReceipt(
    for descriptor: ModelDescriptor,
    profile: LiteRTEngineCacheProfileV1,
    cacheURL: URL
  ) -> Bool {
    guard let cache = try? validatedSharedModelCacheURL(
      cacheURL,
      descriptor: descriptor,
      profile: profile
    ),
      let manifest = try? modelCacheManifest(at: cache),
      manifest.fileCount > 0
    else { return false }
    let receiptURL = modelCacheCompletionReceiptURL(for: cache)
    guard FileManager.default.fileExists(atPath: receiptURL.path),
      let values = try? receiptURL.resourceValues(
        forKeys: [
          .fileSizeKey,
          .isRegularFileKey,
          .isSymbolicLinkKey,
        ]
      ),
      values.isRegularFile == true,
      values.isSymbolicLink != true,
      (values.fileSize ?? 0) > 0,
      (values.fileSize ?? Int.max) <= 16_384,
      (try? FileManager.default.destinationOfSymbolicLink(
        atPath: receiptURL.path
      )) == nil,
      let data = try? Data(contentsOf: receiptURL),
      let receipt = try? JSONDecoder().decode(
        ModelCacheCompletionReceipt.self,
        from: data
      ),
      let identity = try? modelCacheIdentity(at: cache)
    else { return false }
    return receipt == ModelCacheCompletionReceipt(
      format: ModelCacheCompletionReceipt.currentFormat,
      cacheSchema: (try? liteRTCacheSchema(for: profile)) ?? "invalid",
      engineProfileFormat: profile.format,
      engineProfileSHA256: (try? profile.sha256) ?? "invalid",
      readinessStage: ModelCacheCompletionReceipt.engineReadinessStage,
      modelDescriptorID: descriptor.id,
      modelSHA256: descriptor.expectedSHA256,
      liteRTLMRevision: liteRTLMRevision,
      cachePath: cache.path,
      cacheIdentity: identity,
      cacheManifestSHA256: manifest.sha256,
      cacheFileCount: manifest.fileCount
    )
  }

  private static func validatedSharedModelCacheURL(
    _ cacheURL: URL,
    descriptor: ModelDescriptor,
    profile: LiteRTEngineCacheProfileV1
  ) throws -> URL {
    guard cacheURL.isFileURL else {
      throw GITimelineError.invalidModelDescriptor
    }
    let cache = cacheURL.standardizedFileURL
    let descriptorRoot = cache.deletingLastPathComponent()
    guard cache.lastPathComponent == "Cache",
      descriptorRoot.lastPathComponent == descriptor.cacheNamespace
    else {
      throw GITimelineError.invalidModelDescriptor
    }
    let parent = descriptorRoot.deletingLastPathComponent()
    let directories: [URL]
    if parent.lastPathComponent == (try liteRTCacheSchema(for: profile)) {
      let liteRTRoot = parent.deletingLastPathComponent()
      let appCaches = liteRTRoot.deletingLastPathComponent()
      guard liteRTRoot.lastPathComponent == "LiteRT",
        appCaches.lastPathComponent == "GITimeline"
      else {
        throw GITimelineError.invalidModelDescriptor
      }
      directories = [appCaches, liteRTRoot, parent, descriptorRoot, cache]
    } else if parent.lastPathComponent == "Models" {
      let applicationSupportRoot = parent.deletingLastPathComponent()
      guard applicationSupportRoot.lastPathComponent == "GITimeline" else {
        throw GITimelineError.invalidModelDescriptor
      }
      directories = [applicationSupportRoot, parent, descriptorRoot, cache]
    } else {
      throw GITimelineError.invalidModelDescriptor
    }
    for directory in directories {
      guard FileManager.default.fileExists(atPath: directory.path) else {
        throw GITimelineError.invalidModelDescriptor
      }
      let values = try directory.resourceValues(
        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
      )
      guard values.isDirectory == true,
        values.isSymbolicLink != true,
        (try? FileManager.default.destinationOfSymbolicLink(
          atPath: directory.path
        )) == nil
      else {
        throw GITimelineError.invalidModelDescriptor
      }
    }
    let resolved = cache.resolvingSymlinksInPath().standardizedFileURL
    guard resolved.path == cache.path else {
      throw GITimelineError.invalidModelDescriptor
    }
    return cache
  }

  private static func modelCacheIdentity(at cacheURL: URL) throws -> String {
    let attributes = try FileManager.default.attributesOfItem(
      atPath: cacheURL.path
    )
    guard let systemNumber = attributes[.systemNumber] as? NSNumber,
      let fileNumber = attributes[.systemFileNumber] as? NSNumber
    else {
      throw GITimelineError.invalidModelDescriptor
    }
    return "\(systemNumber.uint64Value):\(fileNumber.uint64Value)"
  }

  private static func modelCacheManifest(
    at cacheURL: URL
  ) throws -> ModelCacheManifest {
    let cache = cacheURL.standardizedFileURL
    let rootPrefix = cache.path + "/"
    let keys: Set<URLResourceKey> = [
      .generationIdentifierKey,
      .isDirectoryKey,
      .isRegularFileKey,
      .isSymbolicLinkKey,
    ]
    var enumerationError: Error?
    guard let enumerator = FileManager.default.enumerator(
      at: cache,
      includingPropertiesForKeys: Array(keys),
      options: [],
      errorHandler: { _, error in
        enumerationError = error
        return false
      }
    ) else {
      throw GITimelineError.invalidModelDescriptor
    }
    var entries: [ModelCacheManifestEntry] = []
    while let candidate = enumerator.nextObject() as? URL {
      let normalized = candidate.standardizedFileURL
      guard normalized.path.hasPrefix(rootPrefix) else {
        throw GITimelineError.invalidModelDescriptor
      }
      let values = try normalized.resourceValues(forKeys: keys)
      guard values.isSymbolicLink != true,
        (try? FileManager.default.destinationOfSymbolicLink(
          atPath: normalized.path
        )) == nil
      else {
        throw GITimelineError.invalidModelDescriptor
      }
      if values.isDirectory == true { continue }
      guard values.isRegularFile == true else {
        throw GITimelineError.invalidModelDescriptor
      }
      let attributes = try FileManager.default.attributesOfItem(atPath: normalized.path)
      guard let byteCount = attributes[.size] as? NSNumber,
        let generationIdentifier = values.generationIdentifier as? Data
      else {
        throw GITimelineError.invalidModelDescriptor
      }
      entries.append(ModelCacheManifestEntry(
        relativePath: String(normalized.path.dropFirst(rootPrefix.count)),
        byteCount: byteCount.uint64Value,
        fileIdentity: try modelCacheIdentity(at: normalized),
        contentGenerationIdentifier: generationIdentifier.base64EncodedString()
      ))
    }
    guard enumerationError == nil else {
      throw GITimelineError.invalidModelDescriptor
    }
    entries.sort { $0.relativePath < $1.relativePath }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let canonical = try encoder.encode(entries)
    let sha256 = SHA256.hash(data: canonical).map {
      String(format: "%02x", $0)
    }.joined()
    return ModelCacheManifest(sha256: sha256, fileCount: entries.count)
  }
  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  /// Creates a one-run cache outside the normal model cache. This exists only
  /// to distinguish shared-cache state from native engine behavior in an
  /// isolated internal preparation probe; it never contains journal data.
  static func freshRawImagePreparationCache(
    for descriptor: ModelDescriptor,
    runID: UUID,
    baseDirectory: URL? = nil,
    availableCapacityOverride: Int64? = nil
  ) throws -> URL {
    guard descriptor == .liteRTGemma4E4B else {
      throw GITimelineError.invalidModelDescriptor
    }
    let appSupportRoot = try applicationSupport().resolvingSymlinksInPath()
      .standardizedFileURL
    let base: URL
    if let baseDirectory {
      if FileManager.default.fileExists(atPath: baseDirectory.path) {
        let values = try baseDirectory.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true,
          (try? FileManager.default.destinationOfSymbolicLink(
            atPath: baseDirectory.path
          )) == nil
        else {
          throw GITimelineError.invalidModelDescriptor
        }
      }
      let resolvedBase = baseDirectory.resolvingSymlinksInPath().standardizedFileURL
      guard !isSameOrDescendant(resolvedBase, of: appSupportRoot) else {
        throw GITimelineError.invalidModelDescriptor
      }
      try FileManager.default.createDirectory(
        at: baseDirectory,
        withIntermediateDirectories: true
      )
      base = baseDirectory.resolvingSymlinksInPath().standardizedFileURL
    } else {
      base = appSupportRoot
    }
    let capacity = try availableCapacityOverride ?? base.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey]
    ).volumeAvailableCapacityForImportantUsage
    let requiredCapacity = descriptor.expectedBytes.multipliedReportingOverflow(by: 2)
    guard !requiredCapacity.overflow, let capacity,
      capacity >= requiredCapacity.partialValue
    else {
      throw GITimelineError.insufficientModelStorage
    }
    let completionRoot = base.appendingPathComponent(
      "CompletionEvidence",
      isDirectory: true
    )
    let evidenceRoot = completionRoot
      .appendingPathComponent("InternalRawImageV1PreparationCache", isDirectory: true)
    let runRoot = evidenceRoot.appendingPathComponent(
      runID.uuidString.lowercased(),
      isDirectory: true
    )
    let cache = runRoot.appendingPathComponent("Cache", isDirectory: true)
    for candidate in [completionRoot, evidenceRoot] {
      if FileManager.default.fileExists(atPath: candidate.path) {
        let values = try candidate.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
          throw GITimelineError.invalidModelDescriptor
        }
      }
      if (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
        throw GITimelineError.invalidModelDescriptor
      }
    }
    if FileManager.default.fileExists(atPath: evidenceRoot.path),
      !(try FileManager.default.contentsOfDirectory(atPath: evidenceRoot.path)).isEmpty
    {
      throw GITimelineError.evidenceAlreadyExists
    }
    guard !FileManager.default.fileExists(atPath: runRoot.path) else {
      throw GITimelineError.invalidModelDescriptor
    }
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let resolvedCache = cache.resolvingSymlinksInPath().standardizedFileURL
    guard isSameOrDescendant(resolvedCache, of: base),
      !isSameOrDescendant(resolvedCache, of: appSupportRoot.appendingPathComponent(
        "Models",
        isDirectory: true
      )),
      !isSameOrDescendant(resolvedCache, of: appSupportRoot.appendingPathComponent(
        "Drafts",
        isDirectory: true
      )),
      !isSameOrDescendant(resolvedCache, of: appSupportRoot.appendingPathComponent(
        "Images",
        isDirectory: true
      ))
    else {
      throw GITimelineError.invalidModelDescriptor
    }
    for directory in [evidenceRoot, runRoot, cache] {
      try excludeFromBackup(directory)
      try protect(directory)
    }
    return cache
  }

  /// Creates a one-run LiteRT cache beneath the system Caches directory rather
  /// than Application Support. This HACKATHON/DEBUG-only control distinguishes
  /// production-container Application Support metadata from native engine
  /// behavior without moving or reading journal data.
  static func freshCachesRootRawImagePreparationCache(
    for descriptor: ModelDescriptor,
    runID: UUID,
    baseDirectory: URL? = nil,
    availableCapacityOverride: Int64? = nil,
    replaceExistingDiagnosticRoot: Bool = false
  ) throws -> URL {
    guard descriptor == .liteRTGemma4E4B else {
      throw GITimelineError.invalidModelDescriptor
    }
    let appSupportRoot = try applicationSupport().resolvingSymlinksInPath()
      .standardizedFileURL
    let requestedBase: URL
    if let baseDirectory {
      requestedBase = baseDirectory
    } else {
      requestedBase = try FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      ).appendingPathComponent("GITimeline", isDirectory: true)
    }
    if FileManager.default.fileExists(atPath: requestedBase.path) {
      let values = try requestedBase.resourceValues(forKeys: [.isSymbolicLinkKey])
      guard values.isSymbolicLink != true,
        (try? FileManager.default.destinationOfSymbolicLink(
          atPath: requestedBase.path
        )) == nil
      else {
        throw GITimelineError.invalidModelDescriptor
      }
    }
    let resolvedRequestedBase = requestedBase.resolvingSymlinksInPath()
      .standardizedFileURL
    guard !isSameOrDescendant(resolvedRequestedBase, of: appSupportRoot),
      !isSameOrDescendant(appSupportRoot, of: resolvedRequestedBase)
    else {
      throw GITimelineError.invalidModelDescriptor
    }
    try FileManager.default.createDirectory(
      at: requestedBase,
      withIntermediateDirectories: true
    )
    let base = requestedBase.resolvingSymlinksInPath().standardizedFileURL
    guard !isSameOrDescendant(base, of: appSupportRoot),
      !isSameOrDescendant(appSupportRoot, of: base)
    else {
      throw GITimelineError.invalidModelDescriptor
    }
    let evidenceRootName = "InternalRawImageV1PreparationCaches"
    let evidenceRoot = base.appendingPathComponent(
      evidenceRootName,
      isDirectory: true
    )
    guard evidenceRoot.lastPathComponent == evidenceRootName,
      evidenceRoot.deletingLastPathComponent() == base,
      !replaceExistingDiagnosticRoot || base.lastPathComponent == "GITimeline"
    else {
      throw GITimelineError.invalidModelDescriptor
    }
    let runRoot = evidenceRoot.appendingPathComponent(
      runID.uuidString.lowercased(),
      isDirectory: true
    )
    let cache = runRoot.appendingPathComponent("Cache", isDirectory: true)
    for candidate in [base, evidenceRoot] {
      if FileManager.default.fileExists(atPath: candidate.path) {
        let values = try candidate.resourceValues(
          forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
          throw GITimelineError.invalidModelDescriptor
        }
      }
      if (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
        throw GITimelineError.invalidModelDescriptor
      }
    }
    if FileManager.default.fileExists(atPath: evidenceRoot.path) {
      let existingEntries = try FileManager.default.contentsOfDirectory(
        at: evidenceRoot,
        includingPropertiesForKeys: nil
      )
      if !existingEntries.isEmpty {
        guard replaceExistingDiagnosticRoot else {
          throw GITimelineError.evidenceAlreadyExists
        }
        try validateReplaceableFreshCachesRoot(
          evidenceRoot,
          expectedBase: base,
          expectedRootName: evidenceRootName
        )
        try FileManager.default.removeItem(at: evidenceRoot)
      }
    }
    guard !FileManager.default.fileExists(atPath: runRoot.path) else {
      throw GITimelineError.invalidModelDescriptor
    }
    // Reclaim only the structurally validated, recreatable diagnostic root
    // before measuring capacity. The normal LiteRT cache and every journal path
    // are siblings or live under Application Support and are never candidates.
    let capacity = try availableCapacityOverride ?? base.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey]
    ).volumeAvailableCapacityForImportantUsage
    let requiredCapacity = descriptor.expectedBytes.multipliedReportingOverflow(by: 2)
    guard !requiredCapacity.overflow, let capacity,
      capacity >= requiredCapacity.partialValue
    else {
      throw GITimelineError.insufficientModelStorage
    }
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let resolvedCache = cache.resolvingSymlinksInPath().standardizedFileURL
    guard isSameOrDescendant(resolvedCache, of: base),
      !isSameOrDescendant(resolvedCache, of: appSupportRoot)
    else {
      throw GITimelineError.invalidModelDescriptor
    }
    for directory in [base, evidenceRoot, runRoot, cache] {
      try excludeFromBackup(directory)
      try protectUntilFirstUserAuthentication(directory)
    }
    return cache
  }

  /// Validates the complete shape of the one retained, recreatable diagnostic
  /// cache before the explicit physical selector may rotate it. Nothing is
  /// removed when an unexpected entry, file type, or symlink is encountered.
  private static func validateReplaceableFreshCachesRoot(
    _ evidenceRoot: URL,
    expectedBase: URL,
    expectedRootName: String
  ) throws {
    let normalizedRoot = evidenceRoot.standardizedFileURL
    guard expectedBase.lastPathComponent == "GITimeline",
      normalizedRoot.lastPathComponent == expectedRootName,
      normalizedRoot.deletingLastPathComponent() == expectedBase,
      let rootValues = try? normalizedRoot.resourceValues(
        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
      ),
      rootValues.isDirectory == true,
      rootValues.isSymbolicLink != true,
      (try? FileManager.default.destinationOfSymbolicLink(
        atPath: normalizedRoot.path
      )) == nil
    else {
      throw GITimelineError.invalidModelDescriptor
    }

    let runEntries = try FileManager.default.contentsOfDirectory(
      at: normalizedRoot,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
    )
    guard runEntries.count == 1 else {
      throw GITimelineError.invalidModelDescriptor
    }
    let runRoot = runEntries[0].standardizedFileURL
    guard runRoot.deletingLastPathComponent() == normalizedRoot,
      let runID = UUID(uuidString: runRoot.lastPathComponent),
      runID.uuidString.lowercased() == runRoot.lastPathComponent,
      let runValues = try? runRoot.resourceValues(
        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
      ),
      runValues.isDirectory == true,
      runValues.isSymbolicLink != true,
      (try? FileManager.default.destinationOfSymbolicLink(
        atPath: runRoot.path
      )) == nil
    else {
      throw GITimelineError.invalidModelDescriptor
    }

    let cacheEntries = try FileManager.default.contentsOfDirectory(
      at: runRoot,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
    )
    guard cacheEntries.count == 1 else {
      throw GITimelineError.invalidModelDescriptor
    }
    let cache = cacheEntries[0].standardizedFileURL
    guard cache.lastPathComponent == "Cache",
      cache.deletingLastPathComponent() == runRoot,
      let cacheValues = try? cache.resourceValues(
        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
      ),
      cacheValues.isDirectory == true,
      cacheValues.isSymbolicLink != true,
      (try? FileManager.default.destinationOfSymbolicLink(
        atPath: cache.path
      )) == nil
    else {
      throw GITimelineError.invalidModelDescriptor
    }

    let rootPrefix = cache.path + "/"
    let keys: Set<URLResourceKey> = [
      .isDirectoryKey,
      .isRegularFileKey,
      .isSymbolicLinkKey,
    ]
    var enumerationError: Error?
    guard let enumerator = FileManager.default.enumerator(
      at: cache,
      includingPropertiesForKeys: Array(keys),
      options: [],
      errorHandler: { _, error in
        enumerationError = error
        return false
      }
    ) else {
      throw GITimelineError.invalidModelDescriptor
    }
    while let candidate = enumerator.nextObject() as? URL {
      let normalized = candidate.standardizedFileURL
      guard normalized.path.hasPrefix(rootPrefix),
        let values = try? normalized.resourceValues(forKeys: keys),
        values.isSymbolicLink != true,
        (values.isDirectory == true || values.isRegularFile == true),
        (try? FileManager.default.destinationOfSymbolicLink(
          atPath: normalized.path
        )) == nil
      else {
        throw GITimelineError.invalidModelDescriptor
      }
    }
    guard enumerationError == nil else {
      throw GITimelineError.invalidModelDescriptor
    }
  }

  #endif
  private static func isSameOrDescendant(_ candidate: URL, of root: URL) -> Bool {
    let candidatePath = candidate.standardizedFileURL.path
    let rootPath = root.standardizedFileURL.path
    return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
  }
  static func receiptURL(for descriptor: ModelDescriptor) throws -> URL {
    let directory = try models().appendingPathComponent("Receipts", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try protect(directory)
    return directory.appendingPathComponent("\(descriptor.id).json")
  }
  #if DEBUG
  static func inferenceEvidence() throws -> URL {
    let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent(".devdata_inference", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try protect(directory)
    return directory
  }
  #endif
  static func storeURL() throws -> URL { try applicationSupport().appendingPathComponent("GITimeline.store") }
  /// A protected write-ahead marker for an explicitly confirmed erase-all.
  /// It intentionally lives beside (not inside) the erased journal folders so
  /// a terminated erase can resume before the journal is shown again.
  static func erasePendingMarkerURL() throws -> URL {
    try applicationSupport().appendingPathComponent("erase-pending.v1.json", isDirectory: false)
  }
  static func storeFiles() throws -> [URL] {
    let store = try storeURL()
    return [store, URL(fileURLWithPath: store.path + "-wal"), URL(fileURLWithPath: store.path + "-shm")]
  }
  static func enforceStoreProtection(requireAllStoreFiles: Bool = false) {
    guard let urls = try? storeFiles() else { return }
    for url in urls where FileManager.default.fileExists(atPath: url.path) {
      try? excludeFromBackup(url)
      try? protect(url)
    }
    PrivacyDiagnostics.assertCompleteProtection(at: urls, requireExisting: requireAllStoreFiles)
  }
  static func importFolder() throws -> URL {
    let url = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Import", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  @MainActor static func writeExport(
    _ data: Data,
    filename: String,
    writeGate: JournalWriteGate? = nil
  ) throws -> URL {
    guard filename == (filename as NSString).lastPathComponent,
          filename.hasSuffix(".pdf"), !filename.isEmpty else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    let gate = writeGate ?? .app
    // A PDF render may have spent seconds on a detached executor. Its gate was
    // captured before that work began, so this check permanently rejects a
    // pre-erase render even after the durable marker has been cleared.
    try gate.requireWritable()
    let directory = try exports()
    let destination = directory.appendingPathComponent(filename, isDirectory: false)
    let partial = directory.appendingPathComponent(".\(UUID().uuidString).partial", isDirectory: false)
    do {
      try data.write(to: partial, options: [.atomic, .completeFileProtection])
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: partial, to: destination)
      // Moving the complete-protection partial is the final commit. The parent
      // directory is already excluded from backup; hardening after commit is
      // best effort so a complete PDF is never reported as a failed write.
      try? protect(destination)
      try? excludeFromBackup(destination)
      return destination
    } catch {
      try? FileManager.default.removeItem(at: partial)
      throw error
    }
  }

  /// Purges partial and stale exports only. Call with the default cutoff at
  /// launch to remove leftovers from an interrupted preview/share lifecycle.
  @MainActor static func purgeExports(
    olderThan cutoff: Date = Date(),
    keeping: Set<URL> = [],
    writeGate: JournalWriteGate? = nil
  ) throws {
    let gate = writeGate ?? .app
    try gate.requireWritable()
    let directory = try exports().standardizedFileURL
    let keptPaths = Set(keeping.map { $0.standardizedFileURL.path })
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
    for candidate in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) {
      let normalized = candidate.standardizedFileURL
      guard normalized.deletingLastPathComponent() == directory, !keptPaths.contains(normalized.path) else { continue }
      let values = try normalized.resourceValues(forKeys: Set(keys))
      guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
      let isPartial = normalized.pathExtension == "partial"
      if isPartial || (values.contentModificationDate ?? .distantPast) <= cutoff {
        try gate.requireWritable()
        try FileManager.default.removeItem(at: normalized)
      }
    }
  }

  @MainActor static func removeExport(
    _ url: URL,
    writeGate: JournalWriteGate? = nil
  ) throws {
    let gate = writeGate ?? .app
    try gate.requireWritable()
    let directory = try exports().standardizedFileURL
    let normalized = url.standardizedFileURL
    guard normalized.deletingLastPathComponent() == directory else { return }
    let values = try? normalized.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return }
    try FileManager.default.removeItem(at: normalized)
  }
  private static func directory(_ name: String, excludedFromBackup: Bool) throws -> URL {
    let url = try applicationSupport().appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var values = URLResourceValues(); values.isExcludedFromBackup = excludedFromBackup
    var mutable = url; try mutable.setResourceValues(values)
    try protect(url)
    return url
  }
  static func journalDataDirectories() throws -> [URL] {
    [try images(), try drafts(), try exports()]
  }
  static func excludeFromBackup(_ url: URL) throws {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutable = url
    try mutable.setResourceValues(values)
  }
  static func protect(_ url: URL) throws {
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
  }
  static func protectUntilFirstUserAuthentication(_ url: URL) throws {
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
  }
}

enum GITimelineError: LocalizedError, Equatable {
  case noImage, invalidImage, invalidPhotoAttachment, imageHashMismatch, ambiguousPhotoState, photoRecoveryRequired, entryTransactionConflict, invalidEntryProvenance, invalidClinicalEntry, noteTooLong, modelHashMismatch, modelSizeMismatch, insufficientModelStorage, missingRepairContext, operationInProgress, missingModelDescriptor, invalidModelDescriptor, invalidModelReceipt, modelNotVerified, engineInitializationInProgress
  #if DEBUG || HACKATHON_EMBEDDED_GEMMA
  case invalidDominantColorProbe, syntheticFixtureIntegrity, evidenceAlreadyExists
  #endif
  var errorDescription: String? {
    switch self {
    case .noImage: return "Select a photo before saving."
    case .invalidImage: return "The selected item could not be prepared as an image."
    case .invalidPhotoAttachment: return "The saved photo information was incomplete. Your entry was not changed."
    case .imageHashMismatch: return "The selected photo changed before it could be saved. Your entry was not changed."
    case .ambiguousPhotoState: return "GI Journal found two local copies of a photo and kept both unchanged. Your entry was not changed."
    case .photoRecoveryRequired: return "GI Journal could not confirm that the saved photo matches this draft. The draft and local photo were left unchanged. Your entry was not changed."
    case .entryTransactionConflict: return "GI Journal found a saved entry with the same local transaction identity but different contents. The saved entry and pending draft were left unchanged."
    case .invalidEntryProvenance: return "The photo suggestion record was incomplete. Your entry was not changed."
    case .invalidClinicalEntry: return "Complete the required journal details before saving."
    case .noteTooLong: return "Notes are limited to 500 characters."
    case .modelHashMismatch: return "The model hash did not match. The Import copy was retained."
    case .modelSizeMismatch: return "The model size did not match its immutable descriptor. The Import copy was retained."
    case .insufficientModelStorage: return "At least twice the model size must be free before importing."
    case .missingRepairContext: return "The analysis repair context was no longer available."
    case .operationInProgress: return "Wait for the current local operation to finish."
    case .missingModelDescriptor: return "No physically accepted model is selected for this build."
    case .invalidModelDescriptor: return "The model descriptor contains an invalid identity or unsafe path component."
    case .invalidModelReceipt: return "The on-disk model verification receipt is missing or does not match this candidate."
    case .modelNotVerified: return "Verify the exact model file before initializing the engine."
    case .engineInitializationInProgress: return "The local engine is already initializing."
    #if DEBUG || HACKATHON_EMBEDDED_GEMMA
    case .invalidDominantColorProbe: return "The dominant-color response was not exactly BROWN, GREEN, or OTHER."
    case .syntheticFixtureIntegrity: return "The bundled synthetic fixture did not match its project-recorded hash."
    case .evidenceAlreadyExists: return "Evidence for this run already exists and was not overwritten."
    #endif
    }
  }
}

enum JournalWriteGateError: Error, LocalizedError, Equatable {
  case erasePending
  case eraseStateUnavailable
  case staleWriter

  var errorDescription: String? {
    switch self {
    case .erasePending:
      return "A confirmed erase is still pending. GI Journal will not accept new journal data until that erase finishes."
    case .eraseStateUnavailable:
      return "GI Journal could not verify whether a confirmed erase is pending, so journal changes are temporarily blocked."
    case .staleWriter:
      return "This journal operation began before a confirmed erase and can no longer change journal data."
    }
  }
}

/// A process-local generation token for journal writers. Confirming erase
/// rotates the token synchronously, before any asynchronous cleanup begins.
/// Stores created before that point remain permanently stale even after the
/// durable erase marker is cleared; newly reconstructed stores capture the new
/// token and can restore an untouched pre-commit draft when erase never began.
@MainActor final class JournalWriteEpoch {
  static let shared = JournalWriteEpoch()

  private var token = UUID()

  func invalidateCurrentWriters() {
    token = UUID()
  }

  fileprivate func captureToken() -> UUID { token }
  fileprivate func isCurrent(_ candidate: UUID) -> Bool { candidate == token }
}

/// A synchronous main-actor gate in front of every journal-store mutation.
/// The app's normal gate is backed by the durable erase marker; tests can
/// supply an exact marker probe without touching the app container.
@MainActor struct JournalWriteGate {
  typealias PendingEraseProbe = @MainActor () throws -> Bool
  typealias EpochProbe = @MainActor () -> Bool

  private let pendingEraseProbe: PendingEraseProbe
  private let epochProbe: EpochProbe

  init(
    pendingEraseProbe: @escaping PendingEraseProbe,
    epoch: JournalWriteEpoch? = nil
  ) {
    self.pendingEraseProbe = pendingEraseProbe
    if let epoch {
      let capturedToken = epoch.captureToken()
      self.epochProbe = { epoch.isCurrent(capturedToken) }
    } else {
      self.epochProbe = { true }
    }
  }

  func requireWritable() throws {
    guard epochProbe() else { throw JournalWriteGateError.staleWriter }
    do {
      guard try !pendingEraseProbe() else { throw JournalWriteGateError.erasePending }
    } catch let error as JournalWriteGateError {
      throw error
    } catch {
      // An unreadable protected marker is not evidence that no erase exists.
      throw JournalWriteGateError.eraseStateUnavailable
    }
  }

  static var app: JournalWriteGate {
    JournalWriteGate(
      pendingEraseProbe: {
        try JournalDataErasePendingMarkerStore(
          urlProvider: { try AppFolders.erasePendingMarkerURL() },
          fileManager: .default
        ).hasPendingErase()
      },
      epoch: .shared
    )
  }

  static var unrestricted: JournalWriteGate {
    JournalWriteGate(pendingEraseProbe: { false })
  }
}
