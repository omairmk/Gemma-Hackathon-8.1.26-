import Foundation
import SwiftData

/// The first explicitly named schema for the public release.  The model
/// declarations intentionally remain in their existing files so their entity
/// names and persisted property names do not change while legacy stores are
/// being qualified.
enum GIJournalSchemaV1: VersionedSchema {
  static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

  static var models: [any PersistentModel.Type] {
    [EntryRecord.self, DailyCompletionRecord.self, TreatmentEventRecord.self]
  }
}

/// There is no migration stage yet: V1 is a compatibility foundation for the
/// existing, generated SwiftData schema.  Future releases add a new version
/// and an explicit stage here; they must not change V1 in place.
enum GIJournalSchemaMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] { [GIJournalSchemaV1.self] }
  static var stages: [MigrationStage] { [] }
}

enum PersistenceSchema {
  static let storeName = "GITimeline"

  static var current: Schema {
    Schema(GIJournalSchemaV1.models, version: GIJournalSchemaV1.versionIdentifier)
  }

  static func publicConfiguration(url: URL) -> ModelConfiguration {
    ModelConfiguration(storeName, schema: current, url: url, cloudKitDatabase: .none)
  }

  static func inMemoryConfiguration() -> ModelConfiguration {
    ModelConfiguration(schema: current, isStoredInMemoryOnly: true)
  }

  static func openPublicStore(at url: URL) throws -> ModelContainer {
    try ModelContainer(
      for: current,
      migrationPlan: GIJournalSchemaMigrationPlan.self,
      configurations: [publicConfiguration(url: url)]
    )
  }

  static func makeInMemoryContainer() throws -> ModelContainer {
    try ModelContainer(for: current, configurations: [inMemoryConfiguration()])
  }
}
