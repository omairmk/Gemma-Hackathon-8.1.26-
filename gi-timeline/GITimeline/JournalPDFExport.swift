import Foundation
import CoreText
import ImageIO
import PDFKit
import SwiftUI
import UIKit
import GITimelineCore

@MainActor enum JournalExportSnapshotFactory {
  static func make(
    entries: [EntryRecord],
    completions: [DailyCompletionRecord],
    treatmentEvents: [TreatmentEventRecord],
    range: JournalExportRange,
    scope: JournalExportScope,
    generatedAt: Date = Date(),
    calendar: Calendar = .current,
    timeZone: TimeZone = .current
  ) throws -> JournalExportSnapshot {
    let builder = JournalExportBuilder(calendar: calendar, timeZone: timeZone)
    let boundaries = try builder.boundaries(for: range)
    // Strict parsing is intentionally limited to the selected range/scope. A
    // malformed out-of-range legacy row must not block an unrelated report.
    let selectedEntries = entries.filter {
      $0.capturedAt >= boundaries.start && $0.capturedAt < boundaries.end
        && (scope == .allEntries || $0.isMarkedForDiscussion)
    }
    let exportEntries = try selectedEntries.map(makeExportEntry)
    let completionSnapshots = completions.compactMap(\.snapshot)
    return try builder.build(
      range: range,
      scope: scope,
      entries: exportEntries,
      completions: completionSnapshots,
      treatmentMarkers: [],
      generatedAt: generatedAt
    )
  }

  private static func makeExportEntry(_ entry: EntryRecord) throws -> JournalExportEntry {
    let photoState: JournalPhotoState
    let photoSHA256: String?
    switch (entry.imageFilename, entry.imageSHA256, entry.imageUnavailable) {
    case (nil, nil, false):
      photoState = .noPhoto
      photoSHA256 = nil
    case let (filename?, hash?, false):
      guard filename == "\(entry.id.uuidString).jpg",
        ImageStore.isSafeImageFilename(filename),
        ImageStore.isValidSHA256(hash)
      else { throw JournalExportValidationError.photoIntegrity }
      photoState = .available(filename: filename)
      photoSHA256 = hash
    default:
      throw JournalExportValidationError.photoIntegrity
    }

    let modelSuggestion: StoredModelVisualSuggestion?
    if let raw = entry.originalAIJSON {
      do {
        if let provenanceRaw = entry.modelProvenanceJSON {
          if entry.savedAnalysisSource == .onDevicePhotoSuggestion {
            guard let rawData = raw.data(using: .utf8),
              let receipt = try? PhotoSuggestionEngineReceipt.decode(
                provenanceRaw
              ),
              receipt.canonicalJSON == provenanceRaw,
              receipt.identity.modelID == entry.modelID,
              receipt.identity.analysisPipelineVersion
                == entry.analysisPipelineVersion,
              receipt.analyzedImageSHA256 == entry.imageSHA256
            else { throw JournalExportValidationError.entryIntegrity }
            modelSuggestion = .fullPrefillV2(
              try receipt.validate(rawOutputUTF8: rawData)
            )
          } else {
            guard let data = provenanceRaw.data(using: .utf8) else {
              throw JournalExportValidationError.entryIntegrity
            }
            let provenance = try JSONDecoder().decode(
              InferenceProvenanceSnapshot.self,
              from: data
            )
            modelSuggestion = try provenance.resolvedSuggestion(
              rawResponse: raw
            )
          }
        } else {
          modelSuggestion = try StoredModelVisualSuggestion.parse(raw)
        }
      } catch { throw JournalExportValidationError.entryIntegrity }
    } else {
      modelSuggestion = nil
    }

    let reviewed: StoredReviewedEntry?
    if let raw = entry.reviewedJSON {
      do { reviewed = try StoredReviewedEntry.parse(raw) }
      catch { throw JournalExportValidationError.entryIntegrity }
    } else {
      reviewed = nil
    }

    let hasPhoto = photoState.hasExpectedPhoto
    let confirmedSnapshot: ConfirmedEntrySnapshotV1?
    let legacyReviewedObservation: VisualObservation?
    switch reviewed {
    case .confirmedV1(let snapshot):
      do { try snapshot.validate(hasPhoto: hasPhoto, hasModelSuggestion: modelSuggestion != nil) }
      catch { throw JournalExportValidationError.entryIntegrity }
      confirmedSnapshot = snapshot
      legacyReviewedObservation = nil
    case .legacyObservation(let observation):
      confirmedSnapshot = nil
      legacyReviewedObservation = observation
    case nil:
      guard modelSuggestion == nil else { throw JournalExportValidationError.entryIntegrity }
      confirmedSnapshot = nil
      legacyReviewedObservation = nil
    }

    let suggestedVisual = modelSuggestion.map(makeSuggestedVisual)
    let confirmedColor = humanAcceptedColor(
      confirmedSnapshot?.personConfirmedApparentColor
        ?? legacyReviewedObservation?.apparentColor
    )
    let confirmedPhotoUsable = confirmedSnapshot?.personConfirmedPhotoUsable
      ?? entry.confirmedPhotoUsable
      ?? legacyReviewedObservation?.imageUsable
    let provenance: [ConfirmationField: FieldConfirmationProvenance]
    if let confirmedSnapshot {
      provenance = confirmedSnapshot.typedFieldProvenance
    } else {
      provenance = legacyProvenance(
        entry: entry,
        modelSuggestion: modelSuggestion,
        reviewedObservation: legacyReviewedObservation,
        confirmedColor: confirmedColor,
        confirmedPhotoUsable: confirmedPhotoUsable
      )
    }

    return JournalExportEntry(
      id: entry.id,
      capturedAt: entry.capturedAt,
      confirmedBristolType: entry.effectiveConfirmedBristolType,
      mixedForm: entry.mixedFormAnswer,
      painScore: entry.painScore,
      urgency: entry.urgencyLevel,
      strainingOrIncomplete: entry.strainingOrIncompleteAnswer,
      leakageOrAccident: entry.leakageOrAccidentAnswer,
      redBlood: entry.redBlood.flatMap(ClinicalTriState.init(rawValue:)),
      blackAppearance: entry.blackAppearanceAnswer.map {
        ClinicalTriState(rawValue: $0.rawValue)!
      },
      blackTarry: entry.blackTarry.flatMap(ClinicalTriState.init(rawValue:)),
      dizziness: entry.dizziness.flatMap(ClinicalTriState.init(rawValue:)),
      severeOrWorseningPain: entry.severePain.flatMap(ClinicalTriState.init(rawValue:)),
      note: entry.note,
      markedForDiscussionAt: entry.markedForDiscussionAt,
      photoState: photoState,
      photoSHA256: photoSHA256,
      suggestedVisual: suggestedVisual,
      confirmedPhotoUsable: confirmedPhotoUsable,
      initiallyAcceptedPhotoUsable:
        confirmedSnapshot?.initiallyAcceptedPhotoUsable,
      initiallyAcceptedRetakeReason:
        confirmedSnapshot?.initiallyAcceptedRetakeReason,
      initiallyAcceptedStoolPresence:
        confirmedSnapshot?.initiallyAcceptedStoolPresence,
      initiallyAcceptedBristolType:
        confirmedSnapshot?.initiallyAcceptedBristolType,
      initiallyAcceptedForm: confirmedSnapshot?.initiallyAcceptedForm,
      initiallyAcceptedMixedForm:
        confirmedSnapshot?.initiallyAcceptedMixedForm,
      initiallyAcceptedApparentColor: humanAcceptedColor(
        confirmedSnapshot?.initiallyAcceptedApparentColor
      ),
      initiallyAcceptedRed: confirmedSnapshot?.initiallyAcceptedRed.map {
        ClinicalTriState(rawValue: $0.rawValue)!
      },
      initiallyAcceptedBlackAppearance:
        confirmedSnapshot?.initiallyAcceptedBlackAppearance.map {
          ClinicalTriState(rawValue: $0.rawValue)!
        },
      initiallyAcceptedBlackTarry:
        confirmedSnapshot?.initiallyAcceptedBlackTarry.map {
          ClinicalTriState(rawValue: $0.rawValue)!
        },
      confirmedRetakeReason:
        confirmedSnapshot?.personConfirmedRetakeReason,
      personConfirmedSubject: confirmedSnapshot?.personConfirmedSubject,
      confirmedStoolPresence: confirmedSnapshot?.personConfirmedStoolPresence,
      confirmedForm: confirmedSnapshot?.personConfirmedForm,
      confirmedApparentColor: confirmedColor,
      fieldProvenance: provenance
    )
  }

  private static func makeSuggestedVisual(
    _ stored: StoredModelVisualSuggestion
  ) -> JournalSuggestedVisual {
    let observation = stored.visualObservation
    return JournalSuggestedVisual(
      stoolPresence: stored.stoolPresenceSuggestion,
      retakeReason: stored.retakeReasonSuggestion,
      bristolType: observation.apparentBristolType,
      form: stored.formSuggestion,
      mixedForm: stored.mixedFormSuggestion,
      apparentColor: normalizedColor(observation.apparentColor),
      redAppearance: appearanceAnswer(observation.redAppearingMaterial),
      blackAppearance: stored.blackAppearanceSuggestion.map {
        appearanceAnswer($0)
      },
      blackTarryAppearance: appearanceAnswer(observation.blackTarryAppearance)
    )
  }

  private static func legacyProvenance(
    entry: EntryRecord,
    modelSuggestion: StoredModelVisualSuggestion?,
    reviewedObservation: VisualObservation?,
    confirmedColor: String?,
    confirmedPhotoUsable: Bool?
  ) -> [ConfirmationField: FieldConfirmationProvenance] {
    guard let modelSuggestion else {
      return Dictionary(uniqueKeysWithValues: ConfirmationField.allCases.map {
        ($0, .manualNoSuggestion)
      })
    }
    let suggested = modelSuggestion.visualObservation
    let suggestedMixed = modelSuggestion.mixedFormSuggestion
    var valuesMatch: [ConfirmationField: Bool] = [
      .photoUsable: suggested.imageUsable == confirmedPhotoUsable,
      .retakeReason: modelSuggestion.retakeReasonSuggestion
        == entry.confirmedEntrySnapshot?.personConfirmedRetakeReason,
      .stoolPresence: true,
      .bristolType: suggested.apparentBristolType == entry.effectiveConfirmedBristolType,
      .form: true,
      .mixedForm: suggestedMixed == entry.mixedFormAnswer,
      .apparentColor: normalizedColor(suggested.apparentColor)
        == normalizedColor(confirmedColor),
      .redMaterial: appearanceAnswer(suggested.redAppearingMaterial)
        == entry.redBlood.flatMap(ClinicalTriState.init(rawValue:)),
      .blackTarry: appearanceAnswer(suggested.blackTarryAppearance)
        == entry.blackTarry.flatMap(ClinicalTriState.init(rawValue:)),
    ]
    let fields: [ConfirmationField]
    if let black = modelSuggestion.blackAppearanceSuggestion {
      valuesMatch[.blackAppearance] = appearanceAnswer(black)
        == entry.blackAppearanceAnswer.map {
          ClinicalTriState(rawValue: $0.rawValue)!
        }
      fields = ConfirmationField.allCases
    } else {
      fields = ConfirmationField.allCases.filter { $0 != .blackAppearance }
    }
    return Dictionary(uniqueKeysWithValues: fields.map { field in
      (field, valuesMatch[field] == true ? .acceptedUnchanged : .editedBeforeConfirmation)
    })
  }

  private static func appearanceAnswer(_ raw: String) -> ClinicalTriState {
    switch raw {
    case "apparent": return .yes
    case "not_observed": return .no
    default: return .unsure
    }
  }

  private static func appearanceAnswer(
    _ answer: PhotoSuggestionAnswer
  ) -> ClinicalTriState {
    switch answer {
    case .yes: return .yes
    case .no: return .no
    case .notSure: return .unsure
    }
  }

  private static func normalizedColor(_ raw: String?) -> String? {
    guard let raw, raw != "unable_to_assess", !raw.isEmpty else { return nil }
    return raw
  }

  /// Human-accepted values retain the explicit editable abstention sentinel.
  /// Model/schema null remains absent through `normalizedColor(_:)` above.
  private static func humanAcceptedColor(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    return raw
  }
}

enum JournalPDFExportError: Error, LocalizedError {
  case invalidPhotoDirectory
  case photoIntegrity
  case renderFailed

  var errorDescription: String? {
    switch self {
    case .invalidPhotoDirectory: return "The journal photo directory was unavailable."
    case .photoIntegrity: return "One or more attached journal photos could not be verified. Restart and unlock this iPhone, then try again, or choose a range that does not include the affected entry. No PDF was created."
    case .renderFailed: return "GI Journal could not create this PDF. Your journal was not changed."
    }
  }
}

struct JournalPDFRenderer: Sendable {
  private let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

  func render(snapshot: JournalExportSnapshot, photoDirectory: URL) throws -> Data {
    guard photoDirectory.isFileURL else { throw JournalPDFExportError.invalidPhotoDirectory }
    // Freeze and verify every selected photo before opening the PDF graphics
    // context. The writer receives only immutable decoded images and never
    // reopens a mutable filesystem path while drawing.
    let thumbnails = try preflightPhotos(
      entries: snapshot.entries,
      photoDirectory: photoDirectory
    )
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = [
      kCGPDFContextTitle as String: "GI Journal",
      kCGPDFContextCreator as String: "GI Journal"
    ]
    let renderer = UIGraphicsPDFRenderer(bounds: pageBounds, format: format)
    let data = renderer.pdfData { context in
      let writer = PDFPageWriter(
        context: context,
        pageBounds: pageBounds,
        snapshot: snapshot,
        photoThumbnails: thumbnails
      )
      writer.render()
    }
    guard !data.isEmpty else { throw JournalPDFExportError.renderFailed }
    return data
  }

  private func preflightPhotos(
    entries: [JournalExportEntry],
    photoDirectory: URL
  ) throws -> [UUID: UIImage] {
    let root = photoDirectory.standardizedFileURL
    let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true,
      Set(entries.map(\.id)).count == entries.count
    else { throw JournalPDFExportError.invalidPhotoDirectory }

    var thumbnails: [UUID: UIImage] = [:]
    var expectedPhotoIDs = Set<UUID>()
    for entry in entries {
      switch entry.photoState {
      case .noPhoto:
        guard entry.photoSHA256 == nil else { throw JournalPDFExportError.photoIntegrity }
      case .unavailable:
        throw JournalPDFExportError.photoIntegrity
      case .available(let filename):
        guard filename == "\(entry.id.uuidString).jpg",
          ImageStore.isSafeImageFilename(filename),
          let expectedHash = entry.photoSHA256,
          ImageStore.isValidSHA256(expectedHash),
          expectedPhotoIDs.insert(entry.id).inserted
        else { throw JournalPDFExportError.photoIntegrity }

        let candidate = root.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
        guard candidate.deletingLastPathComponent() == root else {
          throw JournalPDFExportError.photoIntegrity
        }
        do {
          let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
          guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw JournalPDFExportError.photoIntegrity
          }
          let bytes = try Data(contentsOf: candidate, options: .mappedIfSafe)
          try ImageStore.validateSanitizedJournalJPEG(bytes, expectedSHA256: expectedHash)
          guard let thumbnail = boundedSRGBThumbnail(from: bytes),
            thumbnails.updateValue(thumbnail, forKey: entry.id) == nil
          else { throw JournalPDFExportError.photoIntegrity }
        } catch {
          throw JournalPDFExportError.photoIntegrity
        }
      }
    }
    guard Set(thumbnails.keys) == expectedPhotoIDs else {
      throw JournalPDFExportError.photoIntegrity
    }
    return thumbnails
  }

  private func boundedSRGBThumbnail(from data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(
      data as CFData,
      [kCGImageSourceShouldCache: false] as CFDictionary
    ) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 800,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
      decoded.width > 0, decoded.height > 0,
      decoded.width <= 800, decoded.height <= 800,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let output = CGContext(
        data: nil,
        width: decoded.width,
        height: decoded.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    output.interpolationQuality = .high
    output.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
    guard let sRGB = output.makeImage() else { return nil }
    return UIImage(cgImage: sRGB, scale: 1, orientation: .up)
  }
}

private final class PDFPageWriter {
  private let context: UIGraphicsPDFRendererContext
  private let pageBounds: CGRect
  private let snapshot: JournalExportSnapshot
  private let photoThumbnails: [UUID: UIImage]
  private let margin: CGFloat = 48
  private let footerTop: CGFloat
  private let repeatedHeaderHeight: CGFloat = 22
  private var y: CGFloat = 0
  private var pageNumber = 0
  private var contentWidth: CGFloat { pageBounds.width - margin * 2 }

  private let evergreen = UIColor(red: 20 / 255, green: 107 / 255, blue: 84 / 255, alpha: 1)
  private let textColor = UIColor(red: 23 / 255, green: 34 / 255, blue: 29 / 255, alpha: 1)
  private let secondary = UIColor(red: 83 / 255, green: 97 / 255, blue: 90 / 255, alpha: 1)
  private let amber = UIColor(red: 166 / 255, green: 93 / 255, blue: 0, alpha: 1)

  private lazy var dayFormatter: DateFormatter = makeFormatter("MMM d, yyyy")
  private lazy var timestampFormatter: DateFormatter = makeFormatter("MMM d, yyyy 'at' h:mm a")
  private lazy var generatedFormatter: DateFormatter = makeFormatter("MMM d, yyyy 'at' h:mm a zzz")

  init(
    context: UIGraphicsPDFRendererContext,
    pageBounds: CGRect,
    snapshot: JournalExportSnapshot,
    photoThumbnails: [UUID: UIImage]
  ) {
    self.context = context
    self.pageBounds = pageBounds
    self.snapshot = snapshot
    self.photoThumbnails = photoThumbnails
    self.footerTop = pageBounds.height - 42
  }

  func render() {
    beginPage()
    drawText("GI Journal", font: .systemFont(ofSize: 25, weight: .bold), color: evergreen, spacingAfter: 8)
    drawText(
      "\(dayFormatter.string(from: snapshot.startOfFirstDay)) through \(dayFormatter.string(from: snapshot.startAfterLastDay.addingTimeInterval(-1)))",
      font: .systemFont(ofSize: 13, weight: .semibold), color: textColor, spacingAfter: 4
    )
    drawText("Generated \(generatedFormatter.string(from: snapshot.generatedAt))", font: .systemFont(ofSize: 9.5), color: secondary, spacingAfter: 3)
    drawText("\(snapshot.entries.count) entries | \(snapshot.scope.displayName)", font: .systemFont(ofSize: 10.5, weight: .semibold), color: textColor, spacingAfter: 3)
    drawText("Photos included: every attached photo for the selected entries was verified before this report was created and is included as a smaller copy.", font: .systemFont(ofSize: 10.5), color: textColor, spacingAfter: 8)
    if snapshot.entries.contains(where: { $0.suggestedVisual != nil }) {
      drawCallout("Photo suggestions are appearance-only, may be wrong, and are not diagnoses. “Suggested from photo” records the on-device model output; “Person confirmed” records the person's final reviewed values.", color: evergreen)
    } else if snapshot.photoBearingEntryCount > 0 {
      drawCallout("Attached photos belong to manual entries. This public version did not analyze them or use them to prefill fields.", color: evergreen)
    }

    if snapshot.scope == .markedForDiscussion {
      drawCallout("Filtered export: only entries the user marked for discussion are included. This is not the complete journal for the selected dates.", color: amber)
      drawSectionHeading("Summary of exported marked entries")
      drawText("Exported entries: \(snapshot.entries.count)", font: .systemFont(ofSize: 10.5), color: textColor, spacingAfter: 10)
    } else if let summary = snapshot.recordedDataSummary {
      drawRecordedSummary(summary)
    }

    drawNoBowelMovementDays()
    drawSectionHeading("Journal entries")
    for (index, entry) in snapshot.entries.enumerated() {
      drawEntry(entry, ordinal: index + 1)
    }

    drawSectionHeading("Important information")
    drawText(
      "Entries marked “for discussion” were selected by the user and are not an app assessment of severity. This report summarizes user-recorded and user-confirmed observations. It does not diagnose a condition, measure inflammation, determine urgency, recommend treatment, or replace clinician assessment. An unmarked entry is not a safety signal or reassurance.",
      font: .systemFont(ofSize: 9.5), color: secondary, spacingAfter: 4
    )
    drawFooter()
  }

  private func drawRecordedSummary(_ summary: JournalRecordedDataSummary) {
    drawSectionHeading("Recorded-data summary")
    drawText("Recorded bowel movements: \(summary.entryCount)", font: .systemFont(ofSize: 10.5), color: textColor, spacingAfter: 2)
    drawText("Confirmed stool types: \(summary.confirmedTypeCount) (Types 1-2: \(summary.type1To2Count), Types 3-5: \(summary.type3To5Count), Types 6-7: \(summary.type6To7Count))", font: .systemFont(ofSize: 10.5), color: textColor, spacingAfter: 2)
    drawText("Mixed form confirmed: \(summary.mixedFormConfirmedCount)", font: .systemFont(ofSize: 10.5), color: textColor, spacingAfter: 2)
    drawText("Days confirmed complete: \(summary.completeDays) of \(summary.totalDays)", font: .systemFont(ofSize: 10.5), color: textColor, spacingAfter: 2)
    if let frequency = summary.completeDayFrequency {
      drawText(String(format: "Recorded bowel movements per confirmed-complete day: %.2f", frequency), font: .systemFont(ofSize: 10.5), color: textColor, spacingAfter: 10)
    } else {
      drawText("Insufficient complete-day data", font: .systemFont(ofSize: 10.5), color: textColor, spacingAfter: 10)
    }
  }

  private func drawNoBowelMovementDays() {
    guard !snapshot.noBowelMovementDays.isEmpty else { return }
    drawSectionHeading("Days with no bowel movement")
    for day in snapshot.noBowelMovementDays {
      drawText(dayFormatter.string(from: day), font: .systemFont(ofSize: 10.5), color: textColor, spacingAfter: 3)
    }
    y += 7
  }

  private func drawEntry(_ entry: JournalExportEntry, ordinal: Int) {
    let thumbnail: UIImage?
    switch entry.photoState {
    case .available:
      thumbnail = photoThumbnails[entry.id]
      precondition(thumbnail != nil, "Every expected PDF photo must be preflighted before rendering.")
    case .noPhoto:
      thumbnail = nil
    case .unavailable:
      preconditionFailure("Unavailable expected photos must fail before PDF rendering begins.")
    }
    let photoSize = thumbnail.map { fittedSize(for: $0.size, maximumWidth: min(contentWidth, 320), maximumHeight: 210) }
    let fields = entryFields(entry)
    let minimum = 28 + (photoSize?.height ?? 14) + 18
    let headingFont = UIFont.systemFont(ofSize: 13, weight: .bold)
    let fieldFont = UIFont.systemFont(ofSize: 10.5)
    let photoBlockHeight: CGFloat
    if let photoSize {
      photoBlockHeight = photoSize.height + 7
        + estimatedTextHeight("Photo included", font: .systemFont(ofSize: 9.5), width: contentWidth, spacingAfter: 5)
    } else {
      photoBlockHeight = estimatedTextHeight("No photo attached", font: .systemFont(ofSize: 10, weight: .semibold), width: contentWidth, spacingAfter: 5)
    }
    let fullEntryHeight = estimatedTextHeight(
      "Entry \(ordinal) - \(timestampFormatter.string(from: entry.capturedAt))",
      font: headingFont,
      width: contentWidth,
      spacingAfter: 6
    ) + photoBlockHeight + fields.reduce(CGFloat.zero) { partial, field in
      partial + estimatedTextHeight("\(field.label): \(field.value)", font: fieldFont, width: contentWidth, spacingAfter: field.spacingAfter)
    } + 12
    let usablePageHeight = footerTop - 48
    ensureSpace(fullEntryHeight <= usablePageHeight ? fullEntryHeight : minimum)

    drawText("Entry \(ordinal) - \(timestampFormatter.string(from: entry.capturedAt))", font: headingFont, color: evergreen, spacingAfter: 6)
    if let thumbnail, let photoSize {
      ensureSpace(photoSize.height + 8)
      let rect = CGRect(x: margin, y: y, width: photoSize.width, height: photoSize.height)
      thumbnail.draw(in: rect)
      y += photoSize.height + 7
      drawText("Photo included", font: .systemFont(ofSize: 9.5), color: secondary, spacingAfter: 5)
    } else {
      drawText("No photo attached", font: .systemFont(ofSize: 10, weight: .semibold), color: secondary, spacingAfter: 5)
    }

    for field in fields {
      drawField(field.label, field.value, spacingAfter: field.spacingAfter)
    }
    drawRule()
  }

  private func entryFields(_ entry: JournalExportEntry) -> [(label: String, value: String, spacingAfter: CGFloat)] {
    var fields: [(String, String, CGFloat)] = []
    if entry.photoState.hasExpectedPhoto {
      if let suggestion = entry.suggestedVisual {
        fields.append(contentsOf: [
          ("On-device suggestion — photo subject", displaySubject(suggestion.stoolPresence), 2),
          ("On-device suggestion — retake recommendation", displayRetake(
            suggestion.retakeReason,
            photoUsable: suggestion.retakeReason == nil ? true : false,
            unknown: "Not recorded"
          ), 2),
          ("On-device suggestion — Bristol type", stoolType(suggestion.bristolType), 2),
          ("On-device suggestion — form", displayForm(suggestion.form), 2),
          ("On-device suggestion — mixed form", display(suggestion.mixedForm), 2),
          ("On-device suggestion — apparent color", displayColor(suggestion.apparentColor), 2),
          ("On-device suggestion — possible red appearance", display(suggestion.redAppearance), 2),
        ])
        if suggestion.blackAppearance != nil {
          fields.append((
            "On-device suggestion — possible unusually black appearance",
            display(suggestion.blackAppearance),
            2
          ))
          fields.append((
            "On-device suggestion — possible tar-like appearance",
            display(suggestion.blackTarryAppearance),
            5
          ))
        } else {
          fields.append((
            "On-device suggestion — possible black/tar-like appearance",
            display(suggestion.blackTarryAppearance),
            5
          ))
        }
        if entry.confirmedStoolPresence != nil {
          fields.append((
            "Accepted value — photo subject",
            displaySubject(entry.confirmedStoolPresence),
            2
          ))
        }
        if entry.personConfirmedSubject != nil {
          fields.append((
            "Your answer — photo clearly showed the bowel movement",
            entry.personConfirmedSubject == true ? "Yes" : "No",
            2
          ))
        }
        fields.append(contentsOf: [
          ("Accepted value — retake recommendation", displayRetake(
            entry.initiallyAcceptedRetakeReason,
            photoUsable: entry.initiallyAcceptedPhotoUsable,
            unknown: "Not recorded"
          ), 2),
          ("Accepted value — photo subject", displaySubject(
            entry.initiallyAcceptedStoolPresence
          ), 2),
          ("Accepted value — Bristol type", stoolType(
            entry.initiallyAcceptedBristolType
          ), 2),
          ("Accepted value — form", displayForm(
            entry.initiallyAcceptedForm
          ), 2),
          ("Accepted value — mixed form", displayPerson(
            entry.initiallyAcceptedMixedForm
          ), 2),
          ("Accepted value — apparent color", displayColor(
            entry.initiallyAcceptedApparentColor
          ), 2),
          ("Accepted value — possible red/blood-like appearance", displayPerson(
            entry.initiallyAcceptedRed
          ), 2),
        ])
        if entry.fieldProvenance[.blackAppearance] != nil {
          fields.append((
            "Accepted value — possible unusually black appearance",
            displayPerson(entry.initiallyAcceptedBlackAppearance),
            2
          ))
          fields.append((
            "Accepted value — possible tar-like appearance",
            displayPerson(entry.initiallyAcceptedBlackTarry),
            2
          ))
        } else {
          fields.append((
            "Accepted value — possible black/tar-like appearance",
            displayPerson(entry.initiallyAcceptedBlackTarry),
            2
          ))
        }
        fields.append(contentsOf: [
          ("Final value — retake recommendation", displayRetake(
            entry.confirmedRetakeReason,
            photoUsable: entry.confirmedPhotoUsable,
            unknown: "Not recorded"
          ), 2),
          ("Final value — photo subject", displaySubject(entry.confirmedStoolPresence), 2),
          ("Final value — Bristol type", stoolType(entry.confirmedBristolType), 2),
          ("Final value — form", displayForm(entry.confirmedForm), 2),
          ("Final value — mixed form", displayPerson(entry.mixedForm), 2),
          ("Final value — apparent color", displayColor(entry.confirmedApparentColor), 2),
          ("Final value — possible red/blood-like appearance", displayPerson(entry.redBlood), 2),
        ])
        if entry.fieldProvenance[.blackAppearance] != nil {
          fields.append((
            "Final value — possible unusually black appearance",
            displayPerson(entry.blackAppearance),
            2
          ))
          fields.append((
            "Final value — possible tar-like appearance",
            displayPerson(entry.blackTarry),
            2
          ))
        } else {
          fields.append((
            "Final value — possible black/tar-like appearance",
            displayPerson(entry.blackTarry),
            2
          ))
        }
        fields.append((
          "Confirmation provenance",
          provenanceSummary(entry.fieldProvenance),
          7
        ))
      } else {
        fields.append(contentsOf: [
          ("Entry method", "Manual entry; attached photo was not analyzed or used to prefill fields", 5),
          ("Manual value — photo usability", entry.confirmedPhotoUsable == true
            ? "Usable"
            : entry.confirmedPhotoUsable == false ? "Not usable" : "Not recorded", 2),
          ("Manual value — retake recommendation", displayRetake(
            entry.confirmedRetakeReason,
            photoUsable: entry.confirmedPhotoUsable,
            unknown: "Not recorded"
          ), 2),
          ("Manual value — entry subject", displaySubject(entry.confirmedStoolPresence), 2),
          ("Manual value — Bristol type", stoolType(entry.confirmedBristolType), 2),
          ("Manual value — form", displayForm(entry.confirmedForm), 2),
          ("Manual value — mixed form", displayPerson(entry.mixedForm), 2),
          ("Manual value — apparent color", displayColor(entry.confirmedApparentColor), 2),
          ("Manual value — possible red/blood-like appearance", displayPerson(entry.redBlood), 2),
        ])
        if entry.fieldProvenance[.blackAppearance] != nil {
          fields.append((
            "Manual value — possible unusually black appearance",
            displayPerson(entry.blackAppearance),
            2
          ))
          fields.append((
            "Manual value — possible tar-like appearance",
            displayPerson(entry.blackTarry),
            2
          ))
        } else {
          fields.append((
            "Manual value — possible black/tar-like appearance",
            displayPerson(entry.blackTarry),
            2
          ))
        }
        fields.append((
          "Entry provenance",
          provenanceSummary(entry.fieldProvenance),
          7
        ))
      }
    }
    fields.append(contentsOf: [
      ("Stool type", entry.stoolForm.displayName, 2),
      ("Mixed form", display(entry.mixedForm), 2),
      ("Pain", entry.painScore.map { "\($0) out of 10" } ?? "Not recorded", 2),
      ("Urgency", entry.urgency?.displayName ?? "Not recorded", 2)
    ])
    if let type = entry.confirmedBristolType, (1...5).contains(type) {
      fields.append(("Straining or incomplete emptying", display(entry.strainingOrIncomplete), 2))
    } else if let type = entry.confirmedBristolType, (6...7).contains(type) {
      fields.append(("Leakage or accident", display(entry.leakageOrAccident), 2))
    }
    fields.append((
      "Possible red/blood-like appearance",
      displayPerson(entry.redBlood),
      2
    ))
    if entry.fieldProvenance[.blackAppearance] != nil {
      fields.append((
        "Possible unusually black appearance",
        displayPerson(entry.blackAppearance),
        2
      ))
      fields.append((
        "Possible tar-like appearance",
        displayPerson(entry.blackTarry),
        2
      ))
    } else {
      fields.append((
        "Possible black/tar-like appearance",
        displayPerson(entry.blackTarry),
        2
      ))
    }
    fields.append(contentsOf: [
      ("Marked for discussion", entry.isMarkedForDiscussion ? "Yes - selected by the user" : "No", 2),
      ("Note", entry.note?.isEmpty == false ? entry.note! : "Not recorded", 8)
    ])
    return fields
  }

  private func drawField(_ label: String, _ value: String, spacingAfter: CGFloat = 2) {
    drawText("\(label): \(value)", font: .systemFont(ofSize: 10.5), color: textColor, spacingAfter: spacingAfter)
  }

  private func display(_ answer: ClinicalTriState?) -> String { answer?.displayName ?? "Not recorded" }

  private func displayPerson(_ answer: ClinicalTriState?) -> String {
    answer?.displayName ?? "Not answered"
  }

  private func stoolType(_ type: Int?) -> String {
    ClinicalStoolForm(bristolType: type).displayName
  }

  private func displaySubject(_ subject: StoolPresence?) -> String {
    switch subject {
    case .stool: return "Bowel movement"
    case .nonStool: return "Different subject"
    case .uncertain: return "Not sure"
    case nil: return "Not recorded"
    }
  }

  private func displayForm(_ form: String?) -> String {
    guard let form else { return "Not recorded" }
    return form == "unable_to_assess"
      ? "Unable to tell"
      : form.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private func displayColor(_ color: String?) -> String {
    guard let color else { return "Not recorded" }
    if color == "unable_to_assess" { return "Unable to assess" }
    return color.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private func displayRetake(
    _ reason: PhotoRetakeReason?,
    photoUsable: Bool?,
    unknown: String
  ) -> String {
    if let reason { return reason.displayName }
    if photoUsable == true { return "No retake recommended" }
    return unknown
  }

  private func provenanceSummary(
    _ provenance: [ConfirmationField: FieldConfirmationProvenance]
  ) -> String {
    guard !provenance.isEmpty else { return "Legacy entry — field-level provenance was not recorded" }
    let labels: [ConfirmationField: String] = [
      .photoUsable: "photo usability",
      .retakeReason: "retake recommendation",
      .stoolPresence: "photo subject",
      .bristolType: "Bristol type",
      .form: "form",
      .mixedForm: "mixed form",
      .apparentColor: "apparent color",
      .redMaterial: "red appearance",
      .blackAppearance: "unusually black appearance",
      .blackTarry: "black/tar-like appearance",
    ]
    return ConfirmationField.allCases.compactMap { field in
      guard let value = provenance[field], let label = labels[field] else { return nil }
      return "\(label): \(value.displayName)"
    }.joined(separator: "; ")
  }

  private func drawSectionHeading(_ text: String) {
    ensureSpace(28)
    y += 5
    drawText(text, font: .systemFont(ofSize: 15, weight: .semibold), color: evergreen, spacingAfter: 6)
  }

  private func drawCallout(_ text: String, color: UIColor) {
    let start = y
    y += 5
    drawText(text, font: .systemFont(ofSize: 10.5, weight: .semibold), color: color, spacingAfter: 6, horizontalInset: 10)
    let height = y - start
    context.cgContext.setStrokeColor(color.cgColor)
    context.cgContext.setLineWidth(1)
    context.cgContext.stroke(CGRect(x: margin, y: start, width: contentWidth, height: height))
    y += 5
  }

  private func drawRule() {
    ensureSpace(12)
    context.cgContext.setStrokeColor(UIColor(white: 0.84, alpha: 1).cgColor)
    context.cgContext.setLineWidth(0.5)
    context.cgContext.move(to: CGPoint(x: margin, y: y + 4))
    context.cgContext.addLine(to: CGPoint(x: pageBounds.width - margin, y: y + 4))
    context.cgContext.strokePath()
    y += 12
  }

  private func beginPage() {
    if pageNumber > 0 { drawFooter() }
    context.beginPage()
    // Core Text position is mutable process state; normalize it at each page.
    context.cgContext.textMatrix = .identity
    context.cgContext.textPosition = .zero
    pageNumber += 1
    y = 48
    if pageNumber > 1 { drawRepeatedHeader() }
  }

  /// UIKit/Core Text can leak PDF text position across page boundaries on
  /// some OS releases. Rasterizing this small, metadata-free running header
  /// makes its placement deterministic while the report body stays searchable.
  private func drawRepeatedHeader() {
    let header = "GI Journal  ·  \(dayFormatter.string(from: snapshot.startOfFirstDay))–\(dayFormatter.string(from: snapshot.startAfterLastDay.addingTimeInterval(-1)))  ·  \(snapshot.scope.displayName)"
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    format.opaque = false
    let image = UIGraphicsImageRenderer(
      size: CGSize(width: contentWidth, height: repeatedHeaderHeight),
      format: format
    ).image { _ in
      (header as NSString).draw(
        in: CGRect(x: 0, y: 0, width: contentWidth, height: repeatedHeaderHeight),
        withAttributes: [
          .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
          .foregroundColor: evergreen
        ]
      )
    }
    image.draw(in: CGRect(x: margin, y: 32, width: contentWidth, height: repeatedHeaderHeight))
    context.cgContext.setStrokeColor(UIColor(white: 0.84, alpha: 1).cgColor)
    context.cgContext.setLineWidth(0.5)
    context.cgContext.move(to: CGPoint(x: margin, y: 59))
    context.cgContext.addLine(to: CGPoint(x: pageBounds.width - margin, y: 59))
    context.cgContext.strokePath()
    y = 70
  }

  private func drawFooter() {
    guard pageNumber > 0 else { return }
    let page = "Page \(pageNumber)"
    let font = UIFont.systemFont(ofSize: 8.5)
    let width = (page as NSString).size(withAttributes: [.font: font]).width
    drawCoreTextLine(
      page,
      font: font,
      color: secondary,
      x: pageBounds.width - margin - width,
      top: footerTop + 12
    )
  }

  /// Footer drawing uses a canonical PDF-space transform so page numbering is
  /// independent of any prior UIKit/Core Text position.
  private func drawCoreTextLine(_ text: String, font: UIFont, color: UIColor, x: CGFloat, top: CGFloat) {
    let graphics = context.cgContext
    graphics.saveGState()
    graphics.concatenate(graphics.ctm.inverted())
    graphics.textMatrix = .identity
    graphics.textPosition = CGPoint(x: x, y: pageBounds.height - top - font.ascender)
    let line = CTLineCreateWithAttributedString(NSAttributedString(
      string: text,
      attributes: [.font: font, .foregroundColor: color]
    ))
    CTLineDraw(line, graphics)
    graphics.restoreGState()
    graphics.textMatrix = .identity
    graphics.textPosition = .zero
  }

  private func withCleanTextState(_ draw: () -> Void) {
    context.cgContext.textMatrix = .identity
    context.cgContext.textPosition = .zero
    draw()
    // Core Text mutates the PDF context's text matrix/position, and those
    // values are not reliably restored by a Quartz graphics-state pop across
    // UIGraphicsPDFRenderer page boundaries. Normalize them after every draw.
    context.cgContext.textMatrix = .identity
    context.cgContext.textPosition = .zero
  }

  private func ensureSpace(_ height: CGFloat) {
    if y + height > footerTop { beginPage() }
  }

  private func drawText(
    _ text: String,
    font: UIFont,
    color: UIColor,
    spacingAfter: CGFloat,
    horizontalInset: CGFloat = 0
  ) {
    let width = contentWidth - horizontalInset * 2
    let lineHeight = ceil(font.lineHeight * 1.18)
    let paragraphs = text.components(separatedBy: .newlines)
    for (paragraphIndex, paragraph) in paragraphs.enumerated() {
      let lines = wrappedLines(paragraph, font: font, width: width)
      for line in lines.isEmpty ? [""] : lines {
        ensureSpace(lineHeight)
        withCleanTextState {
          (line as NSString).draw(
            in: CGRect(x: margin + horizontalInset, y: y, width: width, height: lineHeight),
            withAttributes: [.font: font, .foregroundColor: color]
          )
        }
        y += lineHeight
      }
      if paragraphIndex < paragraphs.count - 1 { y += lineHeight * 0.35 }
    }
    y += spacingAfter
  }

  private func estimatedTextHeight(_ text: String, font: UIFont, width: CGFloat, spacingAfter: CGFloat) -> CGFloat {
    let lineHeight = ceil(font.lineHeight * 1.18)
    let paragraphs = text.components(separatedBy: .newlines)
    let linesHeight = paragraphs.reduce(CGFloat.zero) { partial, paragraph in
      partial + CGFloat(max(wrappedLines(paragraph, font: font, width: width).count, 1)) * lineHeight
    }
    let paragraphSpacing = CGFloat(max(paragraphs.count - 1, 0)) * lineHeight * 0.35
    return linesHeight + paragraphSpacing + spacingAfter
  }

  private func wrappedLines(_ text: String, font: UIFont, width: CGFloat) -> [String] {
    guard !text.isEmpty else { return [] }
    let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    var lines: [String] = []
    var current = ""
    for word in words {
      let candidate = current.isEmpty ? word : "\(current) \(word)"
      if (candidate as NSString).size(withAttributes: [.font: font]).width <= width {
        current = candidate
      } else if current.isEmpty {
        // Very long unbroken user text is split at character boundaries.
        var fragment = ""
        for character in word {
          let proposed = fragment + String(character)
          if (proposed as NSString).size(withAttributes: [.font: font]).width > width, !fragment.isEmpty {
            lines.append(fragment)
            fragment = String(character)
          } else {
            fragment = proposed
          }
        }
        current = fragment
      } else {
        lines.append(current)
        current = word
      }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
  }

  private func fittedSize(for size: CGSize, maximumWidth: CGFloat, maximumHeight: CGFloat) -> CGSize {
    let scale = min(maximumWidth / max(size.width, 1), maximumHeight / max(size.height, 1), 1)
    return CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
  }

  private func makeFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
    formatter.dateFormat = format
    return formatter
  }
}

enum JournalPDFExporter {
  typealias Renderer = @Sendable (JournalExportSnapshot, URL) throws -> Data
  typealias ExportWriter = @MainActor (Data, String, JournalWriteGate) throws -> URL

  @MainActor static func createPDF(
    snapshot: JournalExportSnapshot,
    photoDirectory: URL,
    writeGate: JournalWriteGate? = nil,
    renderer: Renderer? = nil,
    exportWriter: ExportWriter? = nil
  ) async throws -> URL {
    // Capture synchronously before detached rendering. A later marker clear
    // cannot make this exact export operation current again.
    let capturedGate = writeGate ?? .app
    let render = renderer ?? { snapshot, photoDirectory in
      try JournalPDFRenderer().render(snapshot: snapshot, photoDirectory: photoDirectory)
    }
    let data = try await Task.detached(priority: .userInitiated) {
      try render(snapshot, photoDirectory)
    }.value
    // There is no suspension between this check and the main-actor writer.
    try capturedGate.requireWritable()
    if let exportWriter {
      return try exportWriter(data, snapshot.filename, capturedGate)
    }
    return try AppFolders.writeExport(
      data,
      filename: snapshot.filename,
      writeGate: capturedGate
    )
  }
}

@MainActor final class JournalPDFExportCoordinator: ObservableObject {
  @Published private(set) var isRendering = false
  @Published private(set) var previewURL: URL?
  @Published private(set) var errorMessage: String?
  private let writeGate: JournalWriteGate

  init(writeGate: JournalWriteGate? = nil) {
    self.writeGate = writeGate ?? .app
  }

  func create(snapshot: JournalExportSnapshot, photoDirectory: URL) async {
    guard !isRendering else { return }
    cleanupCurrentExport()
    isRendering = true
    errorMessage = nil
    do {
      previewURL = try await JournalPDFExporter.createPDF(
        snapshot: snapshot,
        photoDirectory: photoDirectory,
        writeGate: writeGate
      )
    } catch {
      errorMessage = error.localizedDescription
    }
    isRendering = false
  }

  func cancel() { cleanupCurrentExport() }
  func previewFailed() {
    cleanupCurrentExport()
    errorMessage = JournalPDFExportError.renderFailed.localizedDescription
  }
  func done() { cleanupCurrentExport() }
  func sharingCompleted() { cleanupCurrentExport() }
  func report(_ error: Error) {
    cleanupCurrentExport()
    errorMessage = error.localizedDescription
  }

  private func cleanupCurrentExport() {
    if let previewURL { try? AppFolders.removeExport(previewURL, writeGate: writeGate) }
    previewURL = nil
    isRendering = false
  }
}

struct JournalExportSheet: View {
  let entries: [EntryRecord]
  let completions: [DailyCompletionRecord]
  let treatmentEvents: [TreatmentEventRecord]
  let calendar: Calendar
  let timeZone: TimeZone
  let presetEndingDate: Date

  @Environment(\.dismiss) private var dismiss
  @StateObject private var coordinator = JournalPDFExportCoordinator()
  @State private var from: Date
  @State private var through: Date
  @State private var preset: JournalExportPreset = .fourteenDays
  @State private var scope: JournalExportScope = .allEntries
  @State private var helpRoute: GIJournalHelpRoute?

  init(
    entries: [EntryRecord],
    completions: [DailyCompletionRecord],
    treatmentEvents: [TreatmentEventRecord],
    today: Date = Date(),
    calendar: Calendar = .current,
    timeZone: TimeZone = .current
  ) {
    self.entries = entries
    self.completions = completions
    self.treatmentEvents = treatmentEvents
    self.calendar = calendar
    self.timeZone = timeZone
    presetEndingDate = today
    let range = JournalExportBuilder(calendar: calendar, timeZone: timeZone).defaultRange(today: today)
    _from = State(initialValue: range.from)
    _through = State(initialValue: range.through)
  }

  private var range: JournalExportRange { .init(from: from, through: through) }
  private var exportEntries: [JournalExportEntry] {
    entries.map {
      let photo: JournalPhotoState
      let hash: String?
      switch ($0.imageFilename, $0.imageSHA256, $0.imageUnavailable) {
      case (nil, nil, false):
        photo = .noPhoto
        hash = nil
      case let (filename?, expectedHash?, false):
        photo = .available(filename: filename)
        hash = expectedHash
      default:
        photo = .unavailable
        hash = $0.imageSHA256
      }
      return JournalExportEntry(
        id: $0.id,
        capturedAt: $0.capturedAt,
        confirmedBristolType: $0.effectiveConfirmedBristolType,
        markedForDiscussionAt: $0.markedForDiscussionAt,
        photoState: photo,
        photoSHA256: hash
      )
    }
  }
  private var builder: JournalExportBuilder { .init(calendar: calendar, timeZone: timeZone) }
  private var completionSnapshots: [DailyCompletionSnapshot] { completions.compactMap(\.snapshot) }
  private var validationError: JournalExportValidationError? {
    builder.validate(range: range, scope: scope, entries: exportEntries, completions: completionSnapshots)
  }
  private var matchCount: Int { (try? builder.matchingEntries(in: exportEntries, range: range, scope: scope).count) ?? 0 }
  private var noBowelMovementDayCount: Int {
    guard let boundaries = try? builder.boundaries(for: range) else { return 0 }
    return completionSnapshots.filter {
      let day = calendar.startOfDay(for: $0.day)
      return $0.answer == .noBowelMovement && day >= boundaries.start && day < boundaries.end
    }.count
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Date range") {
          Picker("Date range", selection: presetBinding) {
            ForEach(JournalExportPreset.allCases, id: \.self) { option in
              Text(option.displayName).tag(option)
            }
          }
          .pickerStyle(.segmented)
          if preset == .custom {
            DatePicker("From", selection: customFromBinding, displayedComponents: .date)
            DatePicker("Through", selection: customThroughBinding, displayedComponents: .date)
          } else {
            Text("\(from.formatted(date: .abbreviated, time: .omitted)) through \(through.formatted(date: .abbreviated, time: .omitted))")
              .font(.subheadline)
              .foregroundStyle(GIJournalTheme.secondaryText)
          }
        }
        Section("Entries to include") {
          Picker("Entries to include", selection: $scope) {
            Text("All entries").tag(JournalExportScope.allEntries)
            Text("Only entries marked for discussion").tag(JournalExportScope.markedForDiscussion)
          }
          .pickerStyle(.inline)
          Text("\(matchCount) entries will be included")
            .accessibilityLabel("\(matchCount) entries will be included")
          if scope == .allEntries, noBowelMovementDayCount > 0 {
            Text("\(noBowelMovementDayCount) no-bowel-movement day\(noBowelMovementDayCount == 1 ? "" : "s") will be included")
          }
          HStack(alignment: .firstTextBaseline) {
            Text("Every attached photo for the selected entries must verify and is included automatically. If any expected photo cannot be rendered, no PDF is created.")
            Spacer()
            GIJournalHelpButton(route: .pdfPhotos, routeToPresent: $helpRoute)
          }
          Text("This PDF may contain private health information. After you share it, GI Journal no longer controls that copy. A PDF cannot restore the journal.")
            .font(.footnote)
            .foregroundStyle(GIJournalTheme.secondaryText)
        }
        if let validationError {
          Section { Text(validationError.localizedDescription).foregroundStyle(.red) }
        }
        if let error = coordinator.errorMessage {
          Section { Text(error).foregroundStyle(.red) }
        }
        Section {
          Button {
            Task { await createPDF() }
          } label: {
            if coordinator.isRendering { ProgressView("Creating PDF").frame(maxWidth: .infinity) }
            else { Text("Create PDF").frame(maxWidth: .infinity) }
          }
          .disabled(validationError != nil || coordinator.isRendering)
        }
      }
      .navigationTitle("Export journal")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { coordinator.cancel(); dismiss() } } }
      .fullScreenCover(isPresented: Binding(
        get: { coordinator.previewURL != nil },
        set: { if !$0 { coordinator.done() } }
      )) {
        if let url = coordinator.previewURL { JournalPDFPreview(url: url, coordinator: coordinator) }
      }
      // Prevent interactive dismissal from bypassing lifecycle cleanup. The
      // explicit Cancel, Done and completed-share paths each remove the file.
      .interactiveDismissDisabled(coordinator.isRendering || coordinator.previewURL != nil)
      .sheet(item: $helpRoute) { GIJournalHelpSheet(route: $0) }
    }
  }

  private var presetBinding: Binding<JournalExportPreset> {
    Binding(
      get: { preset },
      set: { option in
        preset = option
        if let selectedRange = builder.range(for: option, endingOn: presetEndingDate) {
          from = selectedRange.from
          through = selectedRange.through
        }
      }
    )
  }

  private var customFromBinding: Binding<Date> {
    Binding(get: { from }, set: { from = $0; preset = .custom })
  }

  private var customThroughBinding: Binding<Date> {
    Binding(get: { through }, set: { through = $0; preset = .custom })
  }

  private func createPDF() async {
    guard validationError == nil else { return }
    do {
      let snapshot = try JournalExportSnapshotFactory.make(
            entries: entries,
            completions: completions,
            treatmentEvents: treatmentEvents,
            range: range,
            scope: scope,
            calendar: calendar,
            timeZone: timeZone
          )
      let photoDirectory = try AppFolders.images()
      await coordinator.create(snapshot: snapshot, photoDirectory: photoDirectory)
    } catch {
      coordinator.report(error)
    }
  }
}

private struct JournalPDFPreview: View {
  let url: URL
  @ObservedObject var coordinator: JournalPDFExportCoordinator
  @Environment(\.dismiss) private var dismiss
  @State private var showPrivacyConfirmation = false
  @State private var showShare = false

  var body: some View {
    NavigationStack {
      PDFDocumentView(url: url) {
        coordinator.previewFailed()
        dismiss()
      }
        .navigationTitle("PDF preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Done") { coordinator.done(); dismiss() } }
          ToolbarItem(placement: .primaryAction) { Button("Share", systemImage: "square.and.arrow.up") { showPrivacyConfirmation = true } }
        }
        .alert("Share private health information?", isPresented: $showPrivacyConfirmation) {
          Button("Cancel", role: .cancel) {}
          Button("Continue to Share") { showShare = true }
        } message: {
          Text("This PDF includes every attached photo for its selected entries and may contain private health information. After you share it, GI Journal no longer controls that copy. A PDF cannot restore the journal.")
        }
        .sheet(isPresented: $showShare) {
          ActivityShareView(items: [url]) { coordinator.sharingCompleted(); dismiss() }
        }
    }
  }
}

private struct PDFDocumentView: UIViewRepresentable {
  let url: URL
  let onFailure: () -> Void
  func makeUIView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    if let document = PDFDocument(url: url) {
      view.document = document
    } else {
      DispatchQueue.main.async(execute: onFailure)
    }
    return view
  }
  func updateUIView(_ uiView: PDFView, context: Context) {}
}

private struct ActivityShareView: UIViewControllerRepresentable {
  let items: [Any]
  let completion: () -> Void
  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    controller.completionWithItemsHandler = { _, _, _, _ in completion() }
    return controller
  }
  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
