import Foundation

public enum PhotoEvaluationRoute: String, Codable, CaseIterable, Sendable {
  case rawImageSimulator = "RAW_IMAGE_SIMULATOR"
  case derivedMapIPhone = "DERIVED_MAP_IPHONE"
}

public enum PhotoEvaluationPartition: String, Codable, Sendable {
  case tuning
  case holdout
}

public enum PhotoParsePath: String, Codable, Sendable {
  case direct
  case repaired
  case invalid
}

public struct PhotoEvaluationManifestAssetContract: Codable, Equatable, Sendable {
  public let sourceCategory: String
  public let containsRealHealthPhotos: Bool
  public let assetFormat: String
  public let hashField: String
  public let referenceLabelName: String
  public let limitations: String

  enum CodingKeys: String, CodingKey {
    case sourceCategory = "source_category"
    case containsRealHealthPhotos = "contains_real_health_photos"
    case assetFormat = "asset_format"
    case hashField = "hash_field"
    case referenceLabelName = "reference_label_name"
    case limitations
  }
}

public struct PhotoEvaluationManifestPipeline: Codable, Equatable, Sendable {
  public let baseline: String
  public let candidate: String
  public let candidateStatus: String

  enum CodingKeys: String, CodingKey {
    case baseline
    case candidate
    case candidateStatus = "candidate_status"
  }
}

public struct PhotoEvaluationManifestPipelines: Codable, Equatable, Sendable {
  public let rawImageSimulator: PhotoEvaluationManifestPipeline
  public let derivedMapIPhone: PhotoEvaluationManifestPipeline

  enum CodingKeys: String, CodingKey {
    case rawImageSimulator = "RAW_IMAGE_SIMULATOR"
    case derivedMapIPhone = "DERIVED_MAP_IPHONE"
  }

  public func pipeline(for route: PhotoEvaluationRoute) -> PhotoEvaluationManifestPipeline {
    switch route {
    case .rawImageSimulator: return rawImageSimulator
    case .derivedMapIPhone: return derivedMapIPhone
    }
  }
}

public struct PhotoEvaluationManifestFixture: Codable, Equatable, Sendable {
  public let id: String
  public let partition: PhotoEvaluationPartition
  public let asset: String
  public let sanitizedImageSHA256: String
  public let routes: [PhotoEvaluationRoute]
  public let referenceTarget: String
  public let referenceBristolType: Int?
  public let referenceForm: String
  public let expectedAbstention: Bool
  public let expectedQualityIssue: String
  public let runCondition: String

  enum CodingKeys: String, CodingKey {
    case id
    case partition
    case asset
    case sanitizedImageSHA256 = "sanitized_image_sha256"
    case routes
    case referenceTarget = "reference_target"
    case referenceBristolType = "reference_bristol_type"
    case referenceForm = "reference_form"
    case expectedAbstention = "expected_abstention"
    case expectedQualityIssue = "expected_quality_issue"
    case runCondition = "run_condition"
  }

  public func evaluationFixture(for route: PhotoEvaluationRoute) -> PhotoEvaluationFixture {
    PhotoEvaluationFixture(
      id: id,
      partition: partition,
      sanitizedImageSHA256: sanitizedImageSHA256,
      route: route,
      referenceBristolType: referenceBristolType,
      referenceForm: referenceForm,
      expectedAbstention: expectedAbstention,
      expectedImageUsable: expectedQualityIssue == "none",
      expectedQualityIssue: expectedQualityIssue
    )
  }
}

public struct PhotoEvaluationManifest: Codable, Equatable, Sendable {
  public let manifestVersion: String
  public let frozenAtUTC: String
  public let frozenBeforeAccuracyCodeChanges: Bool
  public let assetContract: PhotoEvaluationManifestAssetContract
  public let pipelines: PhotoEvaluationManifestPipelines
  public let fixtures: [PhotoEvaluationManifestFixture]

  enum CodingKeys: String, CodingKey {
    case manifestVersion = "manifest_version"
    case frozenAtUTC = "frozen_at_utc"
    case frozenBeforeAccuracyCodeChanges = "frozen_before_accuracy_code_changes"
    case assetContract = "asset_contract"
    case pipelines
    case fixtures
  }

  public static func decodeAndValidate(_ data: Data) throws -> PhotoEvaluationManifest {
    let manifest = try JSONDecoder().decode(PhotoEvaluationManifest.self, from: data)
    try manifest.validate()
    return manifest
  }

  public func fixtures(
    for route: PhotoEvaluationRoute,
    partition: PhotoEvaluationPartition
  ) -> [PhotoEvaluationManifestFixture] {
    fixtures.filter { $0.partition == partition && $0.routes.contains(route) }
      .sorted { $0.id < $1.id }
  }

  public func validate() throws {
    guard !manifestVersion.isEmpty, frozenBeforeAccuracyCodeChanges else {
      throw PhotoEvaluationManifestError.notFrozen
    }
    guard !assetContract.containsRealHealthPhotos else {
      throw PhotoEvaluationManifestError.realHealthPhotosNotAllowed
    }
    guard assetContract.hashField == "sanitized_image_sha256" else {
      throw PhotoEvaluationManifestError.invalidHashField
    }

    var ids = Set<String>()
    for fixture in fixtures {
      guard ids.insert(fixture.id).inserted else {
        throw PhotoEvaluationManifestError.duplicateFixture(fixture.id)
      }
      guard !fixture.id.isEmpty, fixture.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
        throw PhotoEvaluationManifestError.invalidFixtureID(fixture.id)
      }
      guard Self.isSafeAssetPath(fixture.asset) else {
        throw PhotoEvaluationManifestError.unsafeAssetPath(fixture.id)
      }
      guard fixture.sanitizedImageSHA256.count == 64,
        fixture.sanitizedImageSHA256.allSatisfy(\.isHexDigit)
      else {
        throw PhotoEvaluationManifestError.invalidSanitizedHash(fixture.id)
      }
      guard !fixture.routes.isEmpty, Set(fixture.routes).count == fixture.routes.count else {
        throw PhotoEvaluationManifestError.invalidRoutes(fixture.id)
      }
      guard ["target_like", "ambiguous", "non_target"].contains(fixture.referenceTarget),
        ObservationParser.qualityIssues.contains(fixture.expectedQualityIssue)
      else {
        throw PhotoEvaluationManifestError.invalidReference(fixture.id)
      }
      do {
        try BristolFormContract.validate(
          bristolType: fixture.referenceBristolType,
          form: fixture.referenceForm
        )
      } catch {
        throw PhotoEvaluationManifestError.invalidReference(fixture.id)
      }
      if fixture.expectedAbstention == false, fixture.referenceBristolType == nil {
        throw PhotoEvaluationManifestError.invalidReference(fixture.id)
      }
    }

    for route in PhotoEvaluationRoute.allCases {
      guard !fixtures(for: route, partition: .tuning).isEmpty,
        !fixtures(for: route, partition: .holdout).isEmpty
      else { throw PhotoEvaluationManifestError.missingPartition(route) }
      let pipeline = pipelines.pipeline(for: route)
      guard !pipeline.baseline.isEmpty, !pipeline.candidate.isEmpty,
        pipeline.baseline != pipeline.candidate
      else { throw PhotoEvaluationManifestError.invalidPipeline(route) }
    }
  }

  private static func isSafeAssetPath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), path.hasPrefix("assets/"),
      (path as NSString).pathExtension.lowercased() == "jpg"
    else { return false }
    let components = (path as NSString).pathComponents
    return !components.contains(".") && !components.contains("..")
  }
}

public enum PhotoEvaluationManifestError: Error, Equatable, LocalizedError {
  case notFrozen
  case realHealthPhotosNotAllowed
  case invalidHashField
  case duplicateFixture(String)
  case invalidFixtureID(String)
  case unsafeAssetPath(String)
  case invalidSanitizedHash(String)
  case invalidRoutes(String)
  case invalidReference(String)
  case missingPartition(PhotoEvaluationRoute)
  case invalidPipeline(PhotoEvaluationRoute)

  public var errorDescription: String? {
    switch self {
    case .notFrozen: return "The photo evaluation manifest is not marked frozen before tuning."
    case .realHealthPhotosNotAllowed: return "This local harness accepts only a manifest that excludes real health photos."
    case .invalidHashField: return "The manifest must bind results with sanitized_image_sha256."
    case .duplicateFixture(let id): return "Duplicate manifest fixture: \(id)."
    case .invalidFixtureID(let id): return "Unsafe or invalid manifest fixture identifier: \(id)."
    case .unsafeAssetPath(let id): return "Unsafe manifest asset path for \(id)."
    case .invalidSanitizedHash(let id): return "Invalid sanitized image hash for \(id)."
    case .invalidRoutes(let id): return "Invalid route list for \(id)."
    case .invalidReference(let id): return "Invalid construction reference for \(id)."
    case .missingPartition(let route): return "The manifest is missing a tuning or holdout partition for \(route.rawValue)."
    case .invalidPipeline(let route): return "The manifest pipeline versions are invalid for \(route.rawValue)."
    }
  }
}

public struct PhotoEvaluationFixture: Codable, Equatable, Sendable {
  public let id: String
  public let partition: PhotoEvaluationPartition
  public let sanitizedImageSHA256: String
  public let route: PhotoEvaluationRoute
  public let referenceBristolType: Int?
  public let referenceForm: String
  public let expectedAbstention: Bool
  /// Optional so result files written before quality-semantics evaluation remain decodable.
  public let expectedImageUsable: Bool?
  /// Optional so result files written before quality-semantics evaluation remain decodable.
  public let expectedQualityIssue: String?

  public init(
    id: String,
    partition: PhotoEvaluationPartition,
    sanitizedImageSHA256: String,
    route: PhotoEvaluationRoute,
    referenceBristolType: Int?,
    referenceForm: String,
    expectedAbstention: Bool,
    expectedImageUsable: Bool? = nil,
    expectedQualityIssue: String? = nil
  ) {
    self.id = id
    self.partition = partition
    self.sanitizedImageSHA256 = sanitizedImageSHA256
    self.route = route
    self.referenceBristolType = referenceBristolType
    self.referenceForm = referenceForm
    self.expectedAbstention = expectedAbstention
    self.expectedImageUsable = expectedImageUsable
    self.expectedQualityIssue = expectedQualityIssue
  }
}

/// One immutable evaluation observation. It intentionally stores no image
/// contents or file paths; the sanitized hash binds the result to the frozen
/// local fixture without putting pixels in logs or reports.
public struct PhotoSuggestionEvaluationResult: Codable, Equatable, Sendable {
  public let fixture: PhotoEvaluationFixture
  public let pipelineVersion: String
  public let promptVersion: String
  public let suggestedBristolType: Int?
  public let suggestedForm: String
  public let abstained: Bool
  public let strictJSONValid: Bool
  public let parsePath: PhotoParsePath
  public let latencyMilliseconds: Double?
  public let peakMemoryBytes: UInt64?
  public let failureDescription: String?
  public let crashed: Bool
  public let userConfirmedCorrection: Bool?
  /// Optional so result files written before quality-semantics evaluation remain decodable.
  public let observedImageUsable: Bool?
  /// Optional so result files written before quality-semantics evaluation remain decodable.
  public let observedQualityIssue: String?

  public init(
    fixture: PhotoEvaluationFixture,
    pipelineVersion: String,
    promptVersion: String,
    suggestedBristolType: Int?,
    suggestedForm: String,
    abstained: Bool,
    strictJSONValid: Bool,
    parsePath: PhotoParsePath,
    latencyMilliseconds: Double? = nil,
    peakMemoryBytes: UInt64? = nil,
    failureDescription: String? = nil,
    crashed: Bool = false,
    userConfirmedCorrection: Bool? = nil,
    observedImageUsable: Bool? = nil,
    observedQualityIssue: String? = nil
  ) {
    self.fixture = fixture
    self.pipelineVersion = pipelineVersion
    self.promptVersion = promptVersion
    self.suggestedBristolType = suggestedBristolType
    self.suggestedForm = suggestedForm
    self.abstained = abstained
    self.strictJSONValid = strictJSONValid
    self.parsePath = parsePath
    self.latencyMilliseconds = latencyMilliseconds
    self.peakMemoryBytes = peakMemoryBytes
    self.failureDescription = failureDescription
    self.crashed = crashed
    self.userConfirmedCorrection = userConfirmedCorrection
    self.observedImageUsable = observedImageUsable
    self.observedQualityIssue = observedQualityIssue
  }

  public var bristolFormConsistent: Bool {
    BristolFormContract.isValid(bristolType: suggestedBristolType, form: suggestedForm)
  }

  public var failed: Bool {
    failureDescription != nil || crashed || !strictJSONValid || parsePath == .invalid
  }
}

public struct PhotoConfusionCell: Codable, Equatable, Sendable {
  public let reference: String
  public let suggestion: String
  public let count: Int

  public init(reference: String, suggestion: String, count: Int) {
    self.reference = reference
    self.suggestion = suggestion
    self.count = count
  }
}

public struct PhotoSuggestionMetrics: Codable, Equatable, Sendable {
  public let route: PhotoEvaluationRoute
  public let pipelineVersion: String
  public let promptVersion: String
  public let fixtureCount: Int
  public let referenceLabeledCount: Int
  public let exactAgreementCount: Int
  public let withinOneAgreementCount: Int
  public let groupedAgreementCount: Int
  public let expectedAbstentionCount: Int
  public let correctAbstentionCount: Int
  public let coverageCount: Int
  public let labeledCoverageCount: Int
  public let strictJSONValidCount: Int
  public let bristolFormConsistentCount: Int
  public let directParseCount: Int
  public let repairedParseCount: Int
  public let invalidParseCount: Int
  public let correctionEvaluableCount: Int
  public let correctionCount: Int
  public let latencySampleCount: Int
  public let meanLatencyMilliseconds: Double?
  public let maximumLatencyMilliseconds: Double?
  public let peakMemoryBytes: UInt64?
  public let failureCount: Int
  public let crashCount: Int
  public let confusion: [PhotoConfusionCell]

  public var exactAgreement: Double? { Self.ratio(exactAgreementCount, referenceLabeledCount) }
  public var withinOneAgreement: Double? { Self.ratio(withinOneAgreementCount, referenceLabeledCount) }
  public var groupedAgreement: Double? { Self.ratio(groupedAgreementCount, referenceLabeledCount) }
  public var correctAbstention: Double? { Self.ratio(correctAbstentionCount, expectedAbstentionCount) }
  public var coverage: Double? { Self.ratio(coverageCount, fixtureCount) }
  public var labeledCoverage: Double? { Self.ratio(labeledCoverageCount, referenceLabeledCount) }
  public var strictJSONValidity: Double? { Self.ratio(strictJSONValidCount, fixtureCount) }
  public var correctionRate: Double? { Self.ratio(correctionCount, correctionEvaluableCount) }

  private static func ratio(_ numerator: Int, _ denominator: Int) -> Double? {
    guard denominator > 0 else { return nil }
    return Double(numerator) / Double(denominator)
  }
}

public enum PhotoSuggestionEvaluationError: Error, Equatable, LocalizedError {
  case emptyResults
  case mixedRoutes
  case mixedPipelines
  case duplicateFixture(String)
  case tuningResultInHoldoutComparison(String)
  case fixtureSetMismatch
  case sanitizedHashMismatch(String)

  public var errorDescription: String? {
    switch self {
    case .emptyResults: return "The evaluation result set is empty."
    case .mixedRoutes: return "A route-separated evaluation report cannot combine routes."
    case .mixedPipelines: return "One report cannot combine pipeline or prompt versions."
    case .duplicateFixture(let id): return "Duplicate fixture result: \(id)."
    case .tuningResultInHoldoutComparison(let id): return "Candidate comparison requires holdout-only results; found \(id)."
    case .fixtureSetMismatch: return "Baseline and candidate must use the identical frozen holdout."
    case .sanitizedHashMismatch(let id): return "Baseline and candidate hashes differ for \(id)."
    }
  }
}

public enum PhotoSuggestionEvaluator {
  public static func report(
    results: [PhotoSuggestionEvaluationResult]
  ) throws -> PhotoSuggestionMetrics {
    guard let first = results.first else { throw PhotoSuggestionEvaluationError.emptyResults }
    guard results.allSatisfy({ $0.fixture.route == first.fixture.route }) else {
      throw PhotoSuggestionEvaluationError.mixedRoutes
    }
    guard results.allSatisfy({
      $0.pipelineVersion == first.pipelineVersion && $0.promptVersion == first.promptVersion
    }) else {
      throw PhotoSuggestionEvaluationError.mixedPipelines
    }
    try requireUniqueFixtures(results)

    let labeled = results.filter { $0.fixture.referenceBristolType != nil }
    let exact = labeled.filter { result in
      result.suggestedBristolType == result.fixture.referenceBristolType
    }.count
    let withinOne = labeled.filter { result in
      guard let reference = result.fixture.referenceBristolType,
        let suggestion = result.suggestedBristolType
      else { return false }
      return abs(reference - suggestion) <= 1
    }.count
    let grouped = labeled.filter { result in
      guard let reference = result.fixture.referenceBristolType,
        let suggestion = result.suggestedBristolType
      else { return false }
      return clinicalGroup(reference) == clinicalGroup(suggestion)
    }.count
    let expectedAbstentions = results.filter(\.fixture.expectedAbstention)
    let correctAbstentions = expectedAbstentions.filter { result in
      result.abstained
        && result.suggestedBristolType == nil
        && matchesExpectedQualitySemantics(result)
        && result.strictJSONValid
        && result.parsePath != .invalid
        && !result.crashed
        && result.failureDescription == nil
    }.count
    let covered = results.filter { $0.suggestedBristolType != nil && !$0.failed }
    let labeledCovered = labeled.filter { $0.suggestedBristolType != nil && !$0.failed }
    let latencies = results.compactMap(\.latencyMilliseconds).filter { $0.isFinite && $0 >= 0 }
    let memory = results.compactMap(\.peakMemoryBytes).max()
    let correctionValues = results.compactMap(\.userConfirmedCorrection)

    var confusionCounts: [String: Int] = [:]
    for result in results {
      let reference = confusionReference(result)
      let suggestion = confusionSuggestion(result)
      confusionCounts["\(reference)\u{1F}\(suggestion)", default: 0] += 1
    }
    let confusion = confusionCounts.map { key, count -> PhotoConfusionCell in
      let values = key.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
      return PhotoConfusionCell(reference: String(values[0]), suggestion: String(values[1]), count: count)
    }.sorted {
      ($0.reference, $0.suggestion) < ($1.reference, $1.suggestion)
    }

    return PhotoSuggestionMetrics(
      route: first.fixture.route,
      pipelineVersion: first.pipelineVersion,
      promptVersion: first.promptVersion,
      fixtureCount: results.count,
      referenceLabeledCount: labeled.count,
      exactAgreementCount: exact,
      withinOneAgreementCount: withinOne,
      groupedAgreementCount: grouped,
      expectedAbstentionCount: expectedAbstentions.count,
      correctAbstentionCount: correctAbstentions,
      coverageCount: covered.count,
      labeledCoverageCount: labeledCovered.count,
      strictJSONValidCount: results.filter(\.strictJSONValid).count,
      bristolFormConsistentCount: results.filter { $0.strictJSONValid && $0.bristolFormConsistent }.count,
      directParseCount: results.filter { $0.parsePath == .direct }.count,
      repairedParseCount: results.filter { $0.parsePath == .repaired }.count,
      invalidParseCount: results.filter { $0.parsePath == .invalid }.count,
      correctionEvaluableCount: correctionValues.count,
      correctionCount: correctionValues.filter { $0 }.count,
      latencySampleCount: latencies.count,
      meanLatencyMilliseconds: latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count),
      maximumLatencyMilliseconds: latencies.max(),
      peakMemoryBytes: memory,
      failureCount: results.filter(\.failed).count,
      crashCount: results.filter(\.crashed).count,
      confusion: confusion
    )
  }

  /// Produces one report per route. No aggregate that could blur the Simulator
  /// raw-image tier with physical-phone derived-map evidence is returned.
  public static func routeSeparatedReports(
    results: [PhotoSuggestionEvaluationResult]
  ) throws -> [PhotoEvaluationRoute: [PhotoSuggestionMetrics]] {
    let byRoute = Dictionary(grouping: results, by: { $0.fixture.route })
    var reports: [PhotoEvaluationRoute: [PhotoSuggestionMetrics]] = [:]
    for (route, routeResults) in byRoute {
      let byPipeline = Dictionary(grouping: routeResults) {
        "\($0.pipelineVersion)\u{1F}\($0.promptVersion)"
      }
      reports[route] = try byPipeline.values.map(report(results:)).sorted {
        ($0.pipelineVersion, $0.promptVersion) < ($1.pipelineVersion, $1.promptVersion)
      }
    }
    return reports
  }

  private static func requireUniqueFixtures(_ results: [PhotoSuggestionEvaluationResult]) throws {
    var ids = Set<String>()
    for result in results where !ids.insert(result.fixture.id).inserted {
      throw PhotoSuggestionEvaluationError.duplicateFixture(result.fixture.id)
    }
  }

  /// Historical fixtures without quality labels retain their prior abstention
  /// semantics. Once a fixture carries a label, a missing or mismatched observed
  /// value fails closed instead of counting a null Bristol type as sufficient.
  private static func matchesExpectedQualitySemantics(
    _ result: PhotoSuggestionEvaluationResult
  ) -> Bool {
    if let expectedImageUsable = result.fixture.expectedImageUsable,
      result.observedImageUsable != expectedImageUsable
    {
      return false
    }
    if let expectedQualityIssue = result.fixture.expectedQualityIssue,
      result.observedQualityIssue != expectedQualityIssue
    {
      return false
    }
    return true
  }

  private static func clinicalGroup(_ type: Int) -> String {
    switch type {
    case 1...2: return "1-2"
    case 3...5: return "3-5"
    case 6...7: return "6-7"
    default: return "invalid"
    }
  }

  private static func confusionReference(_ result: PhotoSuggestionEvaluationResult) -> String {
    if let type = result.fixture.referenceBristolType { return "TYPE_\(type)" }
    return result.fixture.expectedAbstention ? "ABSTAIN" : "UNLABELED"
  }

  private static func confusionSuggestion(_ result: PhotoSuggestionEvaluationResult) -> String {
    if result.failed { return "FAILURE" }
    if let type = result.suggestedBristolType { return "TYPE_\(type)" }
    return "ABSTAIN"
  }
}

public struct PhotoCandidateResourceLimits: Codable, Equatable, Sendable {
  public let maximumLatencyMilliseconds: Double
  public let maximumPeakMemoryBytes: UInt64
  public let allowedLatencyRegressionFraction: Double
  public let allowedMemoryRegressionBytes: UInt64

  public init(
    maximumLatencyMilliseconds: Double,
    maximumPeakMemoryBytes: UInt64,
    allowedLatencyRegressionFraction: Double = 0,
    allowedMemoryRegressionBytes: UInt64 = 0
  ) {
    self.maximumLatencyMilliseconds = maximumLatencyMilliseconds
    self.maximumPeakMemoryBytes = maximumPeakMemoryBytes
    self.allowedLatencyRegressionFraction = max(0, allowedLatencyRegressionFraction)
    self.allowedMemoryRegressionBytes = allowedMemoryRegressionBytes
  }
}

public struct PhotoCandidateDecision: Codable, Equatable, Sendable {
  public let adopted: Bool
  public let reasons: [String]
  public let baseline: PhotoSuggestionMetrics
  public let candidate: PhotoSuggestionMetrics

  public init(
    adopted: Bool,
    reasons: [String],
    baseline: PhotoSuggestionMetrics,
    candidate: PhotoSuggestionMetrics
  ) {
    self.adopted = adopted
    self.reasons = reasons
    self.baseline = baseline
    self.candidate = candidate
  }
}

public enum PhotoCandidateComparator {
  public static func compare(
    baseline: [PhotoSuggestionEvaluationResult],
    candidate: [PhotoSuggestionEvaluationResult],
    limits: PhotoCandidateResourceLimits
  ) throws -> PhotoCandidateDecision {
    try requireIdenticalHoldout(baseline: baseline, candidate: candidate)
    let baselineMetrics = try PhotoSuggestionEvaluator.report(results: baseline)
    let candidateMetrics = try PhotoSuggestionEvaluator.report(results: candidate)
    guard baselineMetrics.route == candidateMetrics.route else {
      throw PhotoSuggestionEvaluationError.mixedRoutes
    }

    var reasons = [String]()
    if candidateMetrics.exactAgreementCount <= baselineMetrics.exactAgreementCount {
      reasons.append("Locked-holdout exact Bristol agreement did not improve.")
    }
    if candidateMetrics.withinOneAgreementCount < baselineMetrics.withinOneAgreementCount {
      reasons.append("Within-one-type agreement regressed.")
    }
    if candidateMetrics.groupedAgreementCount < baselineMetrics.groupedAgreementCount {
      reasons.append("Clinically useful group agreement regressed.")
    }
    if candidateMetrics.correctAbstentionCount < baselineMetrics.correctAbstentionCount {
      reasons.append("Correct abstention regressed.")
    }
    if candidateMetrics.labeledCoverageCount < baselineMetrics.labeledCoverageCount {
      reasons.append("Coverage on reference-labeled fixtures regressed.")
    }
    if candidateMetrics.strictJSONValidCount < baselineMetrics.strictJSONValidCount {
      reasons.append("Strict-JSON validity regressed.")
    }
    if candidateMetrics.bristolFormConsistentCount < baselineMetrics.bristolFormConsistentCount {
      reasons.append("Bristol/form consistency regressed.")
    }
    if candidateMetrics.repairedParseCount > baselineMetrics.repairedParseCount {
      reasons.append("The candidate required more parse repairs.")
    }
    if candidateMetrics.failureCount > baselineMetrics.failureCount {
      reasons.append("Failure count regressed.")
    }
    if candidateMetrics.crashCount > baselineMetrics.crashCount {
      reasons.append("Crash count regressed.")
    }
    compareLatency(baseline: baselineMetrics, candidate: candidateMetrics, limits: limits, reasons: &reasons)
    compareMemory(baseline: baselineMetrics, candidate: candidateMetrics, limits: limits, reasons: &reasons)

    return PhotoCandidateDecision(
      adopted: reasons.isEmpty,
      reasons: reasons,
      baseline: baselineMetrics,
      candidate: candidateMetrics
    )
  }

  private static func requireIdenticalHoldout(
    baseline: [PhotoSuggestionEvaluationResult],
    candidate: [PhotoSuggestionEvaluationResult]
  ) throws {
    guard !baseline.isEmpty, !candidate.isEmpty else {
      throw PhotoSuggestionEvaluationError.emptyResults
    }
    for result in baseline + candidate where result.fixture.partition != .holdout {
      throw PhotoSuggestionEvaluationError.tuningResultInHoldoutComparison(result.fixture.id)
    }
    let baselineMap = try mapByFixture(baseline)
    let candidateMap = try mapByFixture(candidate)
    guard Set(baselineMap.keys) == Set(candidateMap.keys) else {
      throw PhotoSuggestionEvaluationError.fixtureSetMismatch
    }
    for id in baselineMap.keys {
      guard let baselineResult = baselineMap[id], let candidateResult = candidateMap[id] else {
        throw PhotoSuggestionEvaluationError.fixtureSetMismatch
      }
      guard baselineResult.fixture.sanitizedImageSHA256 == candidateResult.fixture.sanitizedImageSHA256 else {
        throw PhotoSuggestionEvaluationError.sanitizedHashMismatch(id)
      }
      guard baselineResult.fixture.route == candidateResult.fixture.route,
        baselineResult.fixture.referenceBristolType == candidateResult.fixture.referenceBristolType,
        baselineResult.fixture.referenceForm == candidateResult.fixture.referenceForm,
        baselineResult.fixture.expectedAbstention == candidateResult.fixture.expectedAbstention
      else {
        throw PhotoSuggestionEvaluationError.fixtureSetMismatch
      }
    }
  }

  private static func mapByFixture(
    _ results: [PhotoSuggestionEvaluationResult]
  ) throws -> [String: PhotoSuggestionEvaluationResult] {
    var mapped: [String: PhotoSuggestionEvaluationResult] = [:]
    for result in results {
      guard mapped[result.fixture.id] == nil else {
        throw PhotoSuggestionEvaluationError.duplicateFixture(result.fixture.id)
      }
      mapped[result.fixture.id] = result
    }
    return mapped
  }

  private static func compareLatency(
    baseline: PhotoSuggestionMetrics,
    candidate: PhotoSuggestionMetrics,
    limits: PhotoCandidateResourceLimits,
    reasons: inout [String]
  ) {
    guard let candidateMaximum = candidate.maximumLatencyMilliseconds else {
      reasons.append("Candidate latency was not measured.")
      return
    }
    if candidateMaximum > limits.maximumLatencyMilliseconds {
      reasons.append("Candidate latency exceeded the absolute limit.")
    }
    guard let baselineMaximum = baseline.maximumLatencyMilliseconds else {
      reasons.append("Baseline latency was not measured on the identical holdout.")
      return
    }
    let permitted = baselineMaximum * (1 + limits.allowedLatencyRegressionFraction)
    if candidateMaximum > permitted {
      reasons.append("Candidate latency regressed beyond the allowed margin.")
    }
  }

  private static func compareMemory(
    baseline: PhotoSuggestionMetrics,
    candidate: PhotoSuggestionMetrics,
    limits: PhotoCandidateResourceLimits,
    reasons: inout [String]
  ) {
    guard let candidatePeak = candidate.peakMemoryBytes else {
      reasons.append("Candidate peak memory was not measured.")
      return
    }
    if candidatePeak > limits.maximumPeakMemoryBytes {
      reasons.append("Candidate peak memory exceeded the absolute limit.")
    }
    guard let baselinePeak = baseline.peakMemoryBytes else {
      reasons.append("Baseline peak memory was not measured on the identical holdout.")
      return
    }
    let (permitted, overflowed) = baselinePeak.addingReportingOverflow(limits.allowedMemoryRegressionBytes)
    if overflowed || candidatePeak > permitted {
      reasons.append("Candidate peak memory regressed beyond the allowed margin.")
    }
  }
}
