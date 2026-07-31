import Foundation
import SwiftData

@MainActor protocol EntryStoring: AnyObject {
  func save(_ input: EntryInput, imageStore: ImageStore) throws
  func delete(_ entry: EntryRecord, imageStore: ImageStore) throws
  func reconcile(imageStore: ImageStore) throws
}

enum EntryStoreFailurePoint {
  case afterInsertBeforeSave
  case afterDeleteBeforeSave
}

@MainActor final class EntryStore: EntryStoring {
  typealias FailureInjector = (EntryStoreFailurePoint) throws -> Void

  private let context: ModelContext
  private let failureInjector: FailureInjector?

  init(context: ModelContext, failureInjector: FailureInjector? = nil) {
    self.context = context
    self.failureInjector = failureInjector
    context.autosaveEnabled = false
  }

  func save(_ input: EntryInput, imageStore: ImageStore) throws {
    if (input.note?.count ?? 0) > 500 { throw GITimelineError.noteTooLong }
    let target = try imageStore.promotedURL(for: input.id)
    do {
      try imageStore.copyDraft(input.draftURL, to: target) // copy, never move
      let entry = EntryRecord(input: input)
      context.insert(entry)
      try failureInjector?(.afterInsertBeforeSave)
      try context.save()
      AppFolders.enforceStoreProtection(requireAllStoreFiles: true)
      PrivacyDiagnostics.assertCompleteProtection(at: [target.deletingLastPathComponent(), input.draftURL.deletingLastPathComponent()])
    } catch {
      context.rollback() // required: prevents a retry from retaining a phantom insert
      imageStore.deleteBestEffort(target)
      throw error
    }
  }

  func delete(_ entry: EntryRecord, imageStore: ImageStore) throws {
    let image = imageStore.imageURL(filename: entry.imageFilename)
    context.delete(entry)
    do {
      try failureInjector?(.afterDeleteBeforeSave)
      try context.save()
      AppFolders.enforceStoreProtection(requireAllStoreFiles: true)
      PrivacyDiagnostics.assertCompleteProtection(at: [try imageStore.imagesDirectory(), try imageStore.draftsDirectory()])
    } catch {
      context.rollback()
      throw error // image and visible object remain on failure
    }
    if let image { imageStore.deleteBestEffort(image) }
    #if DEBUG
    if let image { assert(!FileManager.default.fileExists(atPath: image.path), "Deleted entry image must be absent.") }
    #endif
  }

  func reconcile(imageStore: ImageStore) throws {
    let entries = try context.fetch(FetchDescriptor<EntryRecord>())
    let referenced = Set(entries.compactMap(\.imageFilename))
    let folder = try imageStore.imagesDirectory()
    PrivacyDiagnostics.assertCompleteProtection(at: [folder, try imageStore.draftsDirectory()])
    for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where !referenced.contains(url.lastPathComponent) { try? FileManager.default.removeItem(at: url) }
    var changed = false
    for entry in entries {
      let missing = entry.imageFilename.map { !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) } ?? true
      if entry.imageUnavailable != missing { entry.imageUnavailable = missing; entry.updatedAt = Date(); changed = true }
    }
    if changed { try context.save(); AppFolders.enforceStoreProtection() }
  }
}

/// Fault-injecting test store that exercises the real EntryStore transaction
/// and its real ModelContext.rollback() paths using an in-memory container.
@MainActor final class FailingEntryStore: EntryStoring {
  private final class FailureState {
    var failNextSave = false
    var failNextDelete = false
    var rollbackCount = 0
  }

  private let state: FailureState
  private let container: ModelContainer
  private let context: ModelContext
  private let realStore: EntryStore
  private(set) var lastCopiedURL: URL?

  var failNextSave: Bool {
    get { state.failNextSave }
    set { state.failNextSave = newValue }
  }
  var failNextDelete: Bool {
    get { state.failNextDelete }
    set { state.failNextDelete = newValue }
  }
  var rollbackCount: Int { state.rollbackCount }
  var records: [EntryRecord] { (try? context.fetch(FetchDescriptor<EntryRecord>())) ?? [] }

  init() throws {
    let state = FailureState()
    let schema = Schema([EntryRecord.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    let context = ModelContext(container)
    self.state = state
    self.container = container
    self.context = context
    self.realStore = EntryStore(context: context) { point in
      switch point {
      case .afterInsertBeforeSave where state.failNextSave:
        state.failNextSave = false
        state.rollbackCount += 1
        throw CocoaError(.fileWriteUnknown)
      case .afterDeleteBeforeSave where state.failNextDelete:
        state.failNextDelete = false
        state.rollbackCount += 1
        throw CocoaError(.fileWriteUnknown)
      default:
        break
      }
    }
  }

  func save(_ input: EntryInput, imageStore: ImageStore) throws {
    lastCopiedURL = try imageStore.promotedURL(for: input.id)
    try realStore.save(input, imageStore: imageStore)
  }

  func delete(_ entry: EntryRecord, imageStore: ImageStore) throws {
    try realStore.delete(entry, imageStore: imageStore)
  }

  func reconcile(imageStore: ImageStore) throws {
    try realStore.reconcile(imageStore: imageStore)
  }
}
