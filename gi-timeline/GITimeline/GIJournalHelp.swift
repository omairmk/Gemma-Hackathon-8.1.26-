import SwiftUI

enum GIJournalHelpRoute: String, Identifiable {
  case stoolTypes
  case urgency
  case discussionMark
  case pdfPhotos
  case photoSuggestions
  case helpAbout

  var id: String { rawValue }

  var accessibilityLabel: String {
    switch self {
    case .stoolTypes: "About stool types"
    case .urgency: "About urgency"
    case .discussionMark: "About marked for discussion"
    case .pdfPhotos: "About photos included in a PDF"
    case .photoSuggestions:
      #if MANUAL_FALLBACK_RELEASE
      "How attached photos work"
      #else
      "How photo suggestions work"
      #endif
    case .helpAbout: "Help and About"
    }
  }

  var title: String {
    switch self {
    case .stoolTypes: "Choosing a stool type"
    case .urgency: "About urgency"
    case .discussionMark: "About discussion marks"
    case .pdfPhotos: "Photos in a PDF"
    case .photoSuggestions:
      #if MANUAL_FALLBACK_RELEASE
      "How attached photos work"
      #else
      "How photo suggestions work"
      #endif
    case .helpAbout: "Help & About"
    }
  }

  var body: String {
    switch self {
    case .stoolTypes:
      #if MANUAL_FALLBACK_RELEASE
      "The Bristol Stool Scale groups bowel movements by shape and consistency. Choose the type that looks closest overall. If more than one clearly different type appeared, choose the closest main type and answer the mixed-form question separately. Choose Unable to assess when you cannot tell."
      #else
      "The Bristol Stool Scale groups bowel movements by shape and consistency. Choose the type that looks closest overall. If more than one clearly different type appeared, choose the closest main type and answer the mixed-form question separately. A photo suggestion can be wrong and is not a diagnosis."
      #endif
    case .urgency:
      "Urgency means how difficult it was to delay reaching a toilet."
    case .discussionMark:
      "A discussion mark is a bookmark you add to help find an entry later or include it in a focused PDF. It is not added by AI and does not mean the entry is urgent or severe. An unmarked entry does not mean it is safe."
    case .pdfPhotos:
      "GI Journal adds a smaller copy of every attached photo for the selected entries to the PDF, not the original full-resolution file. If any expected attached photo cannot be verified, no PDF is created. Photos can be sensitive, and a PDF shared outside GI Journal is no longer controlled by the app."
    case .photoSuggestions:
      #if MANUAL_FALLBACK_RELEASE
      "An attached photo is stored locally with the manual entry and can be included in a PDF you create. This public version does not analyze the photo or use it to prefill fields. You enter or change every displayed value before saving. Red/blood-like and black/tar-like answers describe possible appearances only; GI Journal does not confirm blood, bleeding, physical stickiness, melena, diagnosis, urgency, cause, or treatment from a photo."
      #else
      "A photo suggestion is a starting point only. The prepared photo is processed locally by the on-device model and is never uploaded to the developer or model provider. The AI may suggest Yes, No, or Not sure for red/blood-like and black/tar-like appearance. You review or change every required value before one final confirmation and save. GI Journal does not diagnose a condition or confirm blood, bleeding, physical stickiness, melena, urgency, cause, or treatment from a photo."
      #endif
    case .helpAbout:
      #if MANUAL_FALLBACK_RELEASE
      "What GI Journal does\nGI Journal records observations you enter and review. It does not diagnose a condition or recommend treatment.\n\nHow attached photos work\nThe app-created photo copy stays on this iPhone with the manual entry. This public version does not analyze the photo or use it to prefill fields. An original selected from Apple Photos remains governed by that person's Photos and iCloud settings.\n\nSaved logs and restarts\nSaved logs are designed to remain in the app when you close and reopen GI Journal, restart and unlock this iPhone, or install an in-place app update.\n\nWhere journal data is stored\nGI Journal stores its app-created journal in its protected local container and does not upload it to the developer. It requests exclusion of the live journal from automatic device backup; iOS controls backup behavior. Deleting GI Journal, losing or resetting this iPhone, or a storage failure may permanently lose entries and photos.\n\nTaking a useful photo\nUse even light. Keep the whole bowel movement in frame. Avoid glare and shadow. Clean the lens and hold the phone steady.\n\nSharing a PDF\nThe entries you choose, no-bowel-movement days in the date range, and every attached photo for those entries are placed in a new PDF. If any expected photo cannot be verified, no PDF is created. Once shared, that copy is outside GI Journal’s control. A PDF cannot restore the journal."
      #else
      "What GI Journal does\nGI Journal records observations you review. It does not diagnose a condition or recommend treatment.\n\nHow photo suggestions work\nThe app-created photo copy stays on this iPhone and is processed locally by the on-device model. Suggestions can be wrong. The AI may suggest Yes, No, or Not sure for red/blood-like and black/tar-like appearance; every suggestion stays editable and unconfirmed until you review all displayed values and use one final confirmation to save. An original selected from Apple Photos remains governed by that person's Photos and iCloud settings.\n\nSaved logs and restarts\nSaved logs are designed to remain in the app when you close and reopen GI Journal, restart and unlock this iPhone, or install an in-place app update.\n\nWhere journal data is stored\nGI Journal stores its app-created journal in its protected local container and does not upload it to the developer. It requests exclusion of the live journal from automatic device backup; iOS controls backup behavior. Deleting GI Journal, losing or resetting this iPhone, or a storage failure may permanently lose entries and photos.\n\nTaking a useful photo\nUse even light. Keep the whole bowel movement in frame. Avoid glare and shadow. Clean the lens and hold the phone steady.\n\nSharing a PDF\nThe entries you choose, no-bowel-movement days in the date range, and every attached photo for those entries are placed in a new PDF. If any expected photo cannot be verified, no PDF is created. Once shared, that copy is outside GI Journal’s control. A PDF cannot restore the journal."
      #endif
    }
  }
}

struct GIJournalHelpSheet: View {
  let route: GIJournalHelpRoute
  @Environment(\.dismiss) private var dismiss
  @AccessibilityFocusState private var contentIsFocused: Bool

  var body: some View {
    NavigationStack {
      ScrollView {
        Text(route.body)
          .font(.body)
          .foregroundStyle(GIJournalTheme.text)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(GIJournalTheme.pageInset)
          .accessibilityLabel("\(route.title). \(route.body)")
          .accessibilityFocused($contentIsFocused)
      }
      .background(GIJournalTheme.canvas)
      .navigationTitle(route.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .onAppear {
      DispatchQueue.main.async { contentIsFocused = true }
    }
  }
}
