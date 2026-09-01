import CryptoKit
import Foundation
import SwiftData

// This is a synthetic predecessor-schema-shaped fixture generator. It runs
// under the current recorded toolchain; it does not execute a predecessor app
// binary or claim that the predecessor toolchain produced the resulting store.
private let provenanceCommit = "8eb4722f4055f8e2912cb20192c695deb067d8a3"
private let artifactKind = "synthetic_predecessor_schema_shaped"
private let artifactNotice = "Synthetic predecessor-schema-shaped SwiftData fixture generated now with the recorded current toolchain; it is not a store or binary produced by the predecessor commit or toolchain."
private let scopeNotice = "Schema and persisted-row compatibility only; this fixture contains no photo bytes and makes no photo-durability claim. Separate tests cover photo storage and relaunch."
private let generatorModuleName = "GITimeline"
private let generatorSourceRelativePath = "Scripts/GenerateLegacyPredecessorStoreFixture.swift"
private let expectedModelNames: Set<String> = [
  "EntryRecord", "DailyCompletionRecord", "TreatmentEventRecord"
]
private let expectedFixtureFileNames: Set<String> = [
  "legacy-predecessor.store",
  "legacy-predecessor.store-shm",
  "legacy-predecessor.store-wal"
]
private let manifestFilename = "legacy-predecessor-store-manifest.json"
private let expectedSourceBlobs: [String: String] = [
  "gi-timeline/GITimeline/EntryRecord.swift": "2cb0db60f3fa64d7403b14bc3ef76bfb7f60de03",
  "gi-timeline/GITimeline/ClinicalTimelineRecords.swift": "2fc1691723eb6fdcd8e46ae9caf79ed3cfd7ca00",
  "gi-timeline/GITimeline/GITimelineApp.swift": "67ad9ae22172d26f813612125154544bfee64ff4"
]

@Model private final class EntryRecord {
  @Attribute(.unique) var id: UUID
  var capturedAt: Date
  var imageFilename: String?
  var imageSHA256: String?
  var redBlood: String?
  var blackTarry: String?
  var dizziness: String?
  var severePain: String?
  var note: String?
  var painScore: Int?
  var urgency: String?
  var bm24h: Int?
  var confirmedBristolType: Int?
  var confirmedPhotoUsable: Bool?
  var mixedForm: String?
  var strainingOrIncomplete: String?
  var leakageOrAccident: String?
  var analysisSource: String?
  var analysisPipelineVersion: String?
  var markedForDiscussionAt: Date?
  var provenance: String
  var reviewedAt: Date?
  var originalAIJSON: String?
  var reviewedJSON: String?
  var modelID: String?
  var modelProvenanceJSON: String?
  var demoKind: String?
  var imageUnavailable: Bool
  var createdAt: Date
  var updatedAt: Date

  init() {
    id = UUID(uuidString: "9C8C46CE-8A8C-4B4E-9A0D-137A4E93B905")!
    capturedAt = Date(timeIntervalSince1970: 1_735_732_800)
    imageFilename = "synthetic-predecessor-photo.jpg"
    imageSHA256 = "b36c8f0e88f0b2e7ef2b9846dbafe5079c3dd03d7f2e9f39524b07ce0d3e9a84"
    redBlood = "no"; blackTarry = "unsure"; dizziness = "no"; severePain = "yes"
    note = "Synthetic immutable predecessor-store record."
    painScore = 6; urgency = "severe"; bm24h = 3
    confirmedBristolType = 6; confirmedPhotoUsable = true
    mixedForm = "yes"; strainingOrIncomplete = "no"; leakageOrAccident = "unsure"
    analysisSource = "gemma"; analysisPipelineVersion = "predecessor-v1"
    markedForDiscussionAt = Date(timeIntervalSince1970: 1_735_733_100)
    provenance = "ai_edited"; reviewedAt = Date(timeIntervalSince1970: 1_735_733_040)
    originalAIJSON = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":5,\"apparent_color\":\"brown\",\"form\":\"soft_blobs\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
    reviewedJSON = "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":6,\"apparent_color\":\"brown\",\"form\":\"mushy\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}"
    modelID = "synthetic-predecessor-model"
    modelProvenanceJSON = "{\"family\":\"synthetic\",\"executionLocation\":\"device\"}"
    demoKind = "predecessor-store-fixture"
    imageUnavailable = false
    createdAt = Date(timeIntervalSince1970: 1_735_732_700)
    updatedAt = Date(timeIntervalSince1970: 1_735_733_100)
  }
}

@Model private final class DailyCompletionRecord {
  @Attribute(.unique) var dayKey: String
  var dayStart: Date
  var answerRawValue: String
  var createdAt: Date
  var updatedAt: Date

  init() {
    dayKey = "2025-01-01"
    dayStart = Date(timeIntervalSince1970: 1_735_689_600)
    answerRawValue = "yes"
    createdAt = Date(timeIntervalSince1970: 1_735_690_000)
    updatedAt = Date(timeIntervalSince1970: 1_735_690_600)
  }
}

@Model private final class TreatmentEventRecord {
  @Attribute(.unique) var id: UUID
  var effectiveDate: Date
  var kindRawValue: String
  var name: String
  var doseOrNote: String?
  var createdAt: Date
  var updatedAt: Date

  init() {
    id = UUID(uuidString: "8261ABF3-0D11-4F70-980B-72A19E9D6A1C")!
    effectiveDate = Date(timeIntervalSince1970: 1_735_776_000)
    kindRawValue = "startedTreatment"
    name = "Synthetic predecessor treatment"
    doseOrNote = "10 mg daily"
    createdAt = Date(timeIntervalSince1970: 1_735_776_100)
    updatedAt = Date(timeIntervalSince1970: 1_735_776_200)
  }
}

private struct GenerationEnvironment: Codable, Equatable {
  let xcodeVersion: String
  let xcodeBuildVersion: String
  let swiftCompilerVersion: String
  let swiftTarget: String
  let macOSProductVersion: String
  let macOSBuildVersion: String
  let systemSQLiteVersion: String
}

private struct Manifest: Codable, Equatable {
  struct FileHash: Codable, Equatable {
    let name: String
    let sha256: String
    let bytes: Int
  }

  let fixtureVersion: Int
  let artifactKind: String
  let artifactNotice: String
  let scopeNotice: String
  let provenanceCommit: String
  let sourceBlobs: [String: String]
  let generatorModuleName: String
  let generatorSourceSHA256: String
  let generationEnvironment: GenerationEnvironment
  let files: [FileHash]
  let expectedValues: [String: String]
}

private struct ProvenanceValidation {
  let sourceBlobs: [String: String]
  let generatorSourceSHA256: String
}

private enum FixtureGeneratorError: Error, LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case .message(let message): return message
    }
  }
}

private let expectedValues: [String: String] = [
  "entryID": "9C8C46CE-8A8C-4B4E-9A0D-137A4E93B905",
  "entryCapturedAt": "1735732800",
  "entryImageFilename": "synthetic-predecessor-photo.jpg",
  "entryImageSHA256": "b36c8f0e88f0b2e7ef2b9846dbafe5079c3dd03d7f2e9f39524b07ce0d3e9a84",
  "entryRedBlood": "no",
  "entryBlackTarry": "unsure",
  "entryDizziness": "no",
  "entrySeverePain": "yes",
  "entryNote": "Synthetic immutable predecessor-store record.",
  "entryPainScore": "6",
  "entryUrgency": "severe",
  "entryBM24H": "3",
  "entryConfirmedBristolType": "6",
  "entryConfirmedPhotoUsable": "true",
  "entryMixedForm": "yes",
  "entryStrainingOrIncomplete": "no",
  "entryLeakageOrAccident": "unsure",
  "entryAnalysisSource": "gemma",
  "entryAnalysisPipelineVersion": "predecessor-v1",
  "entryMarkedForDiscussionAt": "1735733100",
  "entryProvenance": "ai_edited",
  "entryReviewedAt": "1735733040",
  "entryOriginalAIJSON": "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":5,\"apparent_color\":\"brown\",\"form\":\"soft_blobs\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}",
  "entryReviewedJSON": "{\"image_usable\":true,\"quality_issue\":\"none\",\"apparent_bristol_type\":6,\"apparent_color\":\"brown\",\"form\":\"mushy\",\"red_appearing_material\":\"not_observed\",\"black_tarry_appearance\":\"not_observed\"}",
  "entryModelID": "synthetic-predecessor-model",
  "entryModelProvenanceJSON": "{\"family\":\"synthetic\",\"executionLocation\":\"device\"}",
  "entryDemoKind": "predecessor-store-fixture",
  "entryImageUnavailable": "false",
  "entryCreatedAt": "1735732700",
  "entryUpdatedAt": "1735733100",
  "dailyCompletionDayKey": "2025-01-01",
  "dailyCompletionDayStart": "1735689600",
  "dailyCompletionAnswer": "yes",
  "dailyCompletionCreatedAt": "1735690000",
  "dailyCompletionUpdatedAt": "1735690600",
  "treatmentID": "8261ABF3-0D11-4F70-980B-72A19E9D6A1C",
  "treatmentEffectiveDate": "1735776000",
  "treatmentKind": "startedTreatment",
  "treatmentName": "Synthetic predecessor treatment",
  "treatmentDoseOrNote": "10 mg daily",
  "treatmentCreatedAt": "1735776100",
  "treatmentUpdatedAt": "1735776200"
]

private func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func sha256(_ url: URL) throws -> String {
  sha256(try Data(contentsOf: url))
}

private func runTool(_ executable: String, _ arguments: [String]) throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  let output = Pipe()
  let errorOutput = Pipe()
  process.standardOutput = output
  process.standardError = errorOutput
  try process.run()
  process.waitUntilExit()
  let stdout = output.fileHandleForReading.readDataToEndOfFile()
  let stderr = errorOutput.fileHandleForReading.readDataToEndOfFile()
  guard process.terminationStatus == 0 else {
    let detail = String(decoding: stderr, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    throw FixtureGeneratorError.message(
      "tool failed (\(executable) \(arguments.joined(separator: " "))): \(detail)"
    )
  }
  return String(decoding: stdout, as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func runGit(repositoryRoot: URL, _ arguments: [String]) throws -> String {
  try runTool("/usr/bin/git", ["-C", repositoryRoot.path] + arguments)
}

private let modelStartRegex = try! NSRegularExpression(
  pattern: #"^\s*@Model\s+(?:(?:private|fileprivate|internal|package|public)\s+)?final\s+class\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{"#
)
private let storedPropertyRegex = try! NSRegularExpression(
  pattern: #"^\s*(?:@Attribute\([^)]*\)\s+)?var\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*.+$"#
)

private func firstCapture(of expression: NSRegularExpression, in line: String) -> String? {
  let wholeLine = NSRange(line.startIndex..<line.endIndex, in: line)
  guard let match = expression.firstMatch(in: line, range: wholeLine),
    match.numberOfRanges > 1,
    let range = Range(match.range(at: 1), in: line)
  else { return nil }
  return String(line[range])
}

private func matches(_ expression: NSRegularExpression, _ line: String) -> Bool {
  let wholeLine = NSRange(line.startIndex..<line.endIndex, in: line)
  return expression.firstMatch(in: line, range: wholeLine) != nil
}

private func normalizedDeclaration(_ line: String) -> String {
  line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func persistedDeclarations(in source: String, label: String) throws -> [String: [String]] {
  var declarations: [String: [String]] = [:]
  var activeModel: String?
  var activeProperties: [String] = []

  for rawLine in source.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
    let line = String(rawLine)
    if activeModel == nil, let modelName = firstCapture(of: modelStartRegex, in: line) {
      guard expectedModelNames.contains(modelName) else {
        throw FixtureGeneratorError.message("unexpected @Model \(modelName) in \(label)")
      }
      guard declarations[modelName] == nil else {
        throw FixtureGeneratorError.message("duplicate @Model \(modelName) in \(label)")
      }
      activeModel = modelName
      activeProperties = []
      continue
    }

    guard let modelName = activeModel else { continue }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("init(") || trimmed.hasPrefix("init (") {
      guard !activeProperties.isEmpty else {
        throw FixtureGeneratorError.message("@Model \(modelName) has no persisted declarations in \(label)")
      }
      declarations[modelName] = activeProperties
      activeModel = nil
      activeProperties = []
      continue
    }
    if firstCapture(of: modelStartRegex, in: line) != nil {
      throw FixtureGeneratorError.message("nested or unterminated @Model \(modelName) in \(label)")
    }
    if matches(storedPropertyRegex, line) {
      activeProperties.append(normalizedDeclaration(line))
    }
  }

  if let activeModel {
    throw FixtureGeneratorError.message("@Model \(activeModel) has no initializer boundary in \(label)")
  }
  return declarations
}

private func mergeDeclarations(
  _ source: [String: [String]],
  into destination: inout [String: [String]],
  label: String
) throws {
  for (model, properties) in source {
    guard destination[model] == nil else {
      throw FixtureGeneratorError.message("duplicate historical @Model \(model) while reading \(label)")
    }
    destination[model] = properties
  }
}

private func validateProvenance(repositoryRoot: URL) throws -> ProvenanceValidation {
  let generatorSourceURL = repositoryRoot.appendingPathComponent(generatorSourceRelativePath)
  let generatorSourceData = try Data(contentsOf: generatorSourceURL)
  guard let generatorSource = String(data: generatorSourceData, encoding: .utf8) else {
    throw FixtureGeneratorError.message("generator source is not UTF-8: \(generatorSourceURL.path)")
  }
  let generatedDeclarations = try persistedDeclarations(
    in: generatorSource,
    label: generatorSourceRelativePath
  )
  guard Set(generatedDeclarations.keys) == expectedModelNames else {
    throw FixtureGeneratorError.message(
      "generator @Model set drifted: \(generatedDeclarations.keys.sorted())"
    )
  }

  var resolvedBlobs: [String: String] = [:]
  var predecessorDeclarations: [String: [String]] = [:]
  for path in expectedSourceBlobs.keys.sorted() {
    let object = "\(provenanceCommit):\(path)"
    let blob = try runGit(repositoryRoot: repositoryRoot, ["rev-parse", object])
    guard blob == expectedSourceBlobs[path] else {
      throw FixtureGeneratorError.message(
        "predecessor blob mismatch for \(path): expected \(expectedSourceBlobs[path]!), got \(blob)"
      )
    }
    resolvedBlobs[path] = blob

    if path.hasSuffix("EntryRecord.swift") || path.hasSuffix("ClinicalTimelineRecords.swift") {
      let predecessorSource = try runGit(repositoryRoot: repositoryRoot, ["show", object])
      try mergeDeclarations(
        persistedDeclarations(in: predecessorSource, label: object),
        into: &predecessorDeclarations,
        label: object
      )
    }
  }
  guard Set(predecessorDeclarations.keys) == expectedModelNames else {
    throw FixtureGeneratorError.message(
      "predecessor @Model set drifted: \(predecessorDeclarations.keys.sorted())"
    )
  }

  for model in expectedModelNames.sorted() {
    guard generatedDeclarations[model] == predecessorDeclarations[model] else {
      throw FixtureGeneratorError.message(
        "persisted declaration drift for \(model)\n"
          + "generator: \(generatedDeclarations[model] ?? [])\n"
          + "predecessor: \(predecessorDeclarations[model] ?? [])"
      )
    }
  }
  return ProvenanceValidation(
    sourceBlobs: resolvedBlobs,
    generatorSourceSHA256: sha256(generatorSourceData)
  )
}

private func currentGenerationEnvironment() throws -> GenerationEnvironment {
  let xcodeLines = try runTool("/usr/bin/xcodebuild", ["-version"])
    .split(whereSeparator: { $0.isNewline }).map(String.init)
  guard xcodeLines.count >= 2,
    xcodeLines[0].hasPrefix("Xcode "),
    xcodeLines[1].hasPrefix("Build version ")
  else { throw FixtureGeneratorError.message("unexpected xcodebuild -version output") }

  let swiftLines = try runTool("/usr/bin/xcrun", ["--sdk", "macosx", "swiftc", "--version"])
    .split(whereSeparator: { $0.isNewline }).map(String.init)
  guard let swiftCompilerVersion = swiftLines.first,
    let swiftTarget = swiftLines.first(where: { $0.hasPrefix("Target: ") })
  else { throw FixtureGeneratorError.message("unexpected swiftc --version output") }

  let sqliteOutput = try runTool("/usr/bin/sqlite3", ["--version"])
  guard let sqliteVersion = sqliteOutput.split(whereSeparator: { $0.isWhitespace }).first else {
    throw FixtureGeneratorError.message("unexpected sqlite3 --version output")
  }

  return GenerationEnvironment(
    xcodeVersion: String(xcodeLines[0].dropFirst("Xcode ".count)),
    xcodeBuildVersion: String(xcodeLines[1].dropFirst("Build version ".count)),
    swiftCompilerVersion: swiftCompilerVersion,
    swiftTarget: String(swiftTarget.dropFirst("Target: ".count)),
    macOSProductVersion: try runTool("/usr/bin/sw_vers", ["-productVersion"]),
    macOSBuildVersion: try runTool("/usr/bin/sw_vers", ["-buildVersion"]),
    systemSQLiteVersion: String(sqliteVersion)
  )
}

private func regularFiles(at directory: URL) throws -> [URL] {
  try FileManager.default.contentsOfDirectory(
    at: directory,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
  ).filter {
    try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
  }.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func makeStore(at directory: URL, repositoryRoot: URL) throws {
  _ = try validateProvenance(repositoryRoot: repositoryRoot)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  guard try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
    throw FixtureGeneratorError.message("refusing to create a fixture in non-empty directory: \(directory.path)")
  }
  let store = directory.appendingPathComponent("legacy-predecessor.store")
  let schema = Schema([EntryRecord.self, DailyCompletionRecord.self, TreatmentEventRecord.self])
  let configuration = ModelConfiguration(generatorModuleName, schema: schema, url: store, cloudKitDatabase: .none)
  let container = try ModelContainer(for: schema, configurations: [configuration])
  let context = ModelContext(container)
  context.autosaveEnabled = false
  context.insert(EntryRecord())
  context.insert(DailyCompletionRecord())
  context.insert(TreatmentEventRecord())
  try context.save()
}

private func writeManifest(at directory: URL, repositoryRoot: URL) throws {
  let provenance = try validateProvenance(repositoryRoot: repositoryRoot)
  let files = try regularFiles(at: directory).filter { $0.lastPathComponent != manifestFilename }
  guard Set(files.map(\.lastPathComponent)) == expectedFixtureFileNames else {
    throw FixtureGeneratorError.message(
      "unexpected generated fixture file set: \(files.map(\.lastPathComponent))"
    )
  }
  let hashes = try files.map { url in
    Manifest.FileHash(
      name: url.lastPathComponent,
      sha256: try sha256(url),
      bytes: try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    )
  }
  let manifest = Manifest(
    fixtureVersion: 2,
    artifactKind: artifactKind,
    artifactNotice: artifactNotice,
    scopeNotice: scopeNotice,
    provenanceCommit: provenanceCommit,
    sourceBlobs: provenance.sourceBlobs,
    generatorModuleName: generatorModuleName,
    generatorSourceSHA256: provenance.generatorSourceSHA256,
    generationEnvironment: try currentGenerationEnvironment(),
    files: hashes,
    expectedValues: expectedValues
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(manifest).write(
    to: directory.appendingPathComponent(manifestFilename),
    options: .atomic
  )
}

private func verifyManifest(at directory: URL, repositoryRoot: URL) throws {
  let provenance = try validateProvenance(repositoryRoot: repositoryRoot)
  let manifestURL = directory.appendingPathComponent(manifestFilename)
  let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
  guard manifest.fixtureVersion == 2,
    manifest.artifactKind == artifactKind,
    manifest.artifactNotice == artifactNotice,
    manifest.scopeNotice == scopeNotice,
    manifest.provenanceCommit == provenanceCommit,
    manifest.sourceBlobs == provenance.sourceBlobs,
    manifest.generatorModuleName == generatorModuleName,
    manifest.generatorSourceSHA256 == provenance.generatorSourceSHA256,
    manifest.generationEnvironment == (try currentGenerationEnvironment()),
    manifest.expectedValues == expectedValues
  else { throw FixtureGeneratorError.message("manifest provenance or expected values do not match the reviewed generator") }

  let allFiles = try regularFiles(at: directory)
  guard Set(allFiles.map(\.lastPathComponent)) == expectedFixtureFileNames.union([manifestFilename]),
    manifest.files.count == expectedFixtureFileNames.count,
    Set(manifest.files.map(\.name)) == expectedFixtureFileNames
  else { throw FixtureGeneratorError.message("fixture directory or manifest file set is incomplete") }

  for file in manifest.files {
    let url = directory.appendingPathComponent(file.name)
    guard try sha256(url) == file.sha256,
      try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == file.bytes
    else { throw FixtureGeneratorError.message("fixture hash or size mismatch for \(file.name)") }
  }
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let command = arguments.dropFirst().first else {
  fputs("usage: GenerateLegacyPredecessorStoreFixture validate|create|manifest|verify <fixture-dir> <repository-root>\n", stderr)
  exit(64)
}
let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
let repositoryRoot = URL(fileURLWithPath: arguments[3], isDirectory: true)
do {
  switch command {
  case "validate": _ = try validateProvenance(repositoryRoot: repositoryRoot)
  case "create": try makeStore(at: directory, repositoryRoot: repositoryRoot)
  case "manifest": try writeManifest(at: directory, repositoryRoot: repositoryRoot)
  case "verify": try verifyManifest(at: directory, repositoryRoot: repositoryRoot)
  default: throw FixtureGeneratorError.message("unknown generator command: \(command)")
  }
} catch {
  fputs("legacy predecessor fixture generation failed: \(error.localizedDescription)\n", stderr)
  exit(1)
}
