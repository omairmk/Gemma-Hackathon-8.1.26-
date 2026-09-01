import Foundation
import SwiftData
import UIKit

/// Opens the user's canonical local journal conservatively.  A failure never
/// deletes, replaces, migrates manually, or falls back to an empty disk store.
/// The only fallback is an in-memory container used to render a blocking
/// recovery screen; the normal journal UI is never attached in that state.
enum PersistenceBootstrap {
  enum State: Equatable {
    case checking
    case ready
    case blockingRecovery
  }

  enum RecoveryReason: Equatable {
    case journalUnavailable
    case pendingErase
    case protectedDataUnavailable
    case reconciliationFailed
  }

  struct Result {
    let state: State
    let modelContainer: ModelContainer?
    let recoveryMessage: String?
    let recoveryReason: RecoveryReason?
    /// Retained only long enough for the app-level bootstrap to distinguish a
    /// complete-protection denial from a corrupt/unopenable store. Never shown
    /// directly to the user or used to replace the canonical store.
    let openingError: Error?
    /// Runtime attestation used only by isolated diagnostic harnesses. Public
    /// journal containers and blocking fallback containers never set this.
    let isEphemeral: Bool

    init(
      state: State,
      modelContainer: ModelContainer?,
      recoveryMessage: String?,
      recoveryReason: RecoveryReason?,
      openingError: Error?,
      isEphemeral: Bool = false
    ) {
      self.state = state
      self.modelContainer = modelContainer
      self.recoveryMessage = recoveryMessage
      self.recoveryReason = recoveryReason
      self.openingError = openingError
      self.isEphemeral = isEphemeral
    }

    var permitsJournalPresentation: Bool { state == .ready }

    static var checking: Result {
      Result(
        state: .checking,
        modelContainer: nil,
        recoveryMessage: nil,
        recoveryReason: nil,
        openingError: nil
      )
    }
  }

  typealias PublicStoreOpener = (URL) throws -> ModelContainer
  typealias RecoveryContainerMaker = () throws -> ModelContainer
  typealias PendingEraseResumer = (ModelContext) throws -> JournalDataEraseSummary?
  typealias JournalReconciler = (ModelContext) async throws -> Void
  typealias ProtectedDataAvailability = @MainActor () -> Bool

  static func open(
    publicStoreURL: URL,
    openPublicStore: PublicStoreOpener? = nil,
    makeRecoveryContainer: RecoveryContainerMaker? = nil
  ) -> Result {
    let publicOpener = openPublicStore ?? PersistenceSchema.openPublicStore
    let recoveryMaker = makeRecoveryContainer ?? PersistenceSchema.makeInMemoryContainer
    do {
      return Result(
        state: .ready,
        modelContainer: try publicOpener(publicStoreURL),
        recoveryMessage: nil,
        recoveryReason: nil,
        openingError: nil
      )
    } catch {
      // Deliberately do not touch publicStoreURL here. In particular, do not
      // remove the SQLite file, WAL, or SHM, and do not substitute a new store.
      let recoveryContainer = try? recoveryMaker()
      return Result(
        state: .blockingRecovery,
        modelContainer: recoveryContainer,
        recoveryMessage: "GI Journal could not safely open its local journal. Your existing journal was not changed. Keep the app installed and contact support before resetting or deleting app data.",
        recoveryReason: .journalUnavailable,
        openingError: error
      )
    }
  }

  @MainActor static func openAppJournal(
    publicStoreURL: URL? = nil,
    openPublicStore: PublicStoreOpener? = nil,
    makeRecoveryContainer: RecoveryContainerMaker? = nil,
    resumePendingErase: PendingEraseResumer? = nil,
    reconcileJournal: JournalReconciler? = nil,
    protectedDataIsAvailable: ProtectedDataAvailability? = nil
  ) async -> Result {
    do {
      let dataIsAvailable = protectedDataIsAvailable ?? {
        UIApplication.shared.isProtectedDataAvailable
      }
      guard dataIsAvailable() else { return protectedDataRecoveryResult() }
      let resolvedStoreURL: URL
      if let publicStoreURL {
        resolvedStoreURL = publicStoreURL
      } else {
        resolvedStoreURL = try AppFolders.storeURL()
      }
      let result = open(
        publicStoreURL: resolvedStoreURL,
        openPublicStore: openPublicStore,
        makeRecoveryContainer: makeRecoveryContainer
      )
      guard result.permitsJournalPresentation, let container = result.modelContainer else {
        if !dataIsAvailable()
          || result.openingError.map({
            ImageStore.isProtectedDataReadFailure(
              $0,
              protectedDataIsAvailable: dataIsAvailable()
            )
          }) == true
        {
          return protectedDataRecoveryResult()
        }
        return result
      }
      let context = ModelContext(container)
      let eraseResumer = resumePendingErase ?? { context in
        try JournalDataEraser(context: context).resumePendingEraseIfNeeded()
      }
      do {
        // An erase-pending marker is written before the database transaction.
        // Finish that requested erase before any normal journal view can read
        // or restore local records, drafts, images, or exports.
        if let summary = try eraseResumer(context),
          !summary.completedWithoutWarnings
        {
          // Defensive compatibility for any older eraser implementation that
          // returned warnings instead of throwing while retaining its marker.
          throw JournalDataErasePendingFailure(
            stage: .fileCleanup,
            recordsDeleted: summary.recordsDeleted,
            filesDeleted: summary.filesDeleted,
            cleanupFailureCount: summary.fileCleanupFailures,
            underlyingDescription: "A protected erase marker remains."
          )
        }
      } catch {
        if ImageStore.isProtectedDataReadFailure(
          error,
          protectedDataIsAvailable: dataIsAvailable()
        ) {
          return protectedDataRecoveryResult()
        }
        return Result(
          state: .blockingRecovery,
          modelContainer: try? PersistenceSchema.makeInMemoryContainer(),
          recoveryMessage: "GI Journal has a confirmed local erase that has not safely finished. Journal entry is blocked so newly written data cannot be erased by a later retry. Unlock this iPhone if needed, then try again; keep the app installed while local cleanup is pending.",
          recoveryReason: .pendingErase,
          openingError: nil
        )
      }
      let reconciler = reconcileJournal ?? { context in
        try await EntryStore(context: context).reconcile(imageStore: ImageStore())
      }
      do {
        // Reconcile the database/photo transaction boundary before any
        // journal view receives this context. A reboot or process termination
        // may leave a queued promotion/deletion that is safe to restore or
        // finalize, but an uncertain reconciliation must block rather than be
        // silently discarded after writable UI appears.
        try await reconciler(context)
        return result
      } catch {
        if ImageStore.isProtectedDataReadFailure(
          error,
          protectedDataIsAvailable: dataIsAvailable()
        ) {
          return protectedDataRecoveryResult()
        }
        return Result(
          state: .blockingRecovery,
          modelContainer: try? PersistenceSchema.makeInMemoryContainer(),
          recoveryMessage: "GI Journal could not safely check its local journal and retained photos after restart. No replacement or empty journal was substituted; some conservative local file checks may already have completed. Try again and keep the app installed while this check is pending.",
          recoveryReason: .reconciliationFailed,
          openingError: nil
        )
      }
    } catch {
      let dataIsAvailable = protectedDataIsAvailable ?? {
        UIApplication.shared.isProtectedDataAvailable
      }
      if ImageStore.isProtectedDataReadFailure(
        error,
        protectedDataIsAvailable: dataIsAvailable()
      ) {
        return protectedDataRecoveryResult()
      }
      return recoveryResult()
    }
  }

  static func makeEphemeral() -> Result {
    do {
      return Result(
        state: .ready,
        modelContainer: try PersistenceSchema.makeInMemoryContainer(),
        recoveryMessage: nil,
        recoveryReason: nil,
        openingError: nil,
        isEphemeral: true
      )
    } catch {
      return recoveryResult()
    }
  }

  private static func recoveryResult() -> Result {
    Result(
      state: .blockingRecovery,
      modelContainer: try? PersistenceSchema.makeInMemoryContainer(),
      recoveryMessage: "GI Journal could not safely open its local journal. Your existing journal was not changed. Keep the app installed and contact support before resetting or deleting app data.",
      recoveryReason: .journalUnavailable,
      openingError: nil
    )
  }

  private static func protectedDataRecoveryResult() -> Result {
    Result(
      state: .blockingRecovery,
      modelContainer: try? PersistenceSchema.makeInMemoryContainer(),
      recoveryMessage: "GI Journal's protected local data is temporarily unavailable. Unlock this iPhone, then try again. The app will not substitute a new or empty journal.",
      recoveryReason: .protectedDataUnavailable,
      openingError: nil
    )
  }
}
