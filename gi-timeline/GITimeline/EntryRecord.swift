import Foundation
import SwiftData
import GITimelineCore

@Model final class EntryRecord {
  @Attribute(.unique) var id: UUID
  var capturedAt: Date
  var imageFilename: String?
  var imageSHA256: String?
  var redBlood: String?
  var blackTarry: String?
  var dizziness: String?
  var severePain: String?
  var note: String?
  // Schema-only fields. The app deliberately exposes no UI for these.
  var painScore: Int?
  var urgency: String?
  var bm24h: Int?
  var provenance: String
  var reviewedAt: Date?
  var originalAIJSON: String?
  var reviewedJSON: String?
  var modelID: String?
  var imageUnavailable: Bool
  var createdAt: Date
  var updatedAt: Date

  init(input: EntryInput) {
    id = input.id; capturedAt = input.capturedAt; imageFilename = input.imageFilename; imageSHA256 = input.imageSHA256
    redBlood = input.redBlood?.rawValue; blackTarry = input.blackTarry?.rawValue; dizziness = input.dizziness?.rawValue; severePain = input.severePain?.rawValue
    note = input.note; provenance = input.provenance.rawValue; reviewedAt = input.reviewedAt; originalAIJSON = input.originalAIJSON; reviewedJSON = input.reviewedJSON; modelID = input.modelID
    imageUnavailable = false; createdAt = Date(); updatedAt = Date()
  }

  var observation: VisualObservation? { reviewedJSON.flatMap { try? ObservationParser.parse($0) } }
  var flagSummary: String {
    let flags = [("Red blood", redBlood), ("Black/tarry", blackTarry), ("Dizziness", dizziness), ("Severe pain", severePain)]
    return flags.compactMap { label, value in value.map { "\(label): \($0)" } }.joined(separator: " · ")
  }
}

enum EntryProvenance: String { case manual, ai_unedited, ai_edited }

struct EntryInput {
  let id: UUID
  let capturedAt: Date
  let draftURL: URL
  let imageSHA256: String
  let redBlood: GITimelineCore.SymptomFlag?
  let blackTarry: GITimelineCore.SymptomFlag?
  let dizziness: GITimelineCore.SymptomFlag?
  let severePain: GITimelineCore.SymptomFlag?
  let note: String?
  let provenance: EntryProvenance
  let reviewedAt: Date?
  let originalAIJSON: String?
  let reviewedJSON: String?
  let modelID: String?
  let imageFilename: String
}
