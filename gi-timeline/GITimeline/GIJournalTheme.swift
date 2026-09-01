import SwiftUI
import UIKit

/// Semantic, adaptive presentation tokens for the patient-facing GI Journal UI.
/// Keep literal colors here so clinical views never need to make their own color
/// decisions.
enum GIJournalTheme {
  static let canvas = Color(adaptiveLight: 0xF7F6F1, dark: 0x0E1512)
  static let surface = Color(adaptiveLight: 0xFFFFFF, dark: 0x17201C)
  static let tintedSurface = Color(adaptiveLight: 0xE8F3EC, dark: 0x1D2B25)
  static let primary = Color(adaptiveLight: 0x146B54, dark: 0x6DD39B)
  static let primaryPressed = Color(adaptiveLight: 0x0E4F3E, dark: 0x6DD39B)
  static let text = Color(adaptiveLight: 0x17221D, dark: 0xF4F7F5)
  static let secondaryText = Color(adaptiveLight: 0x53615A, dark: 0xBBC8C1)
  static let border = Color(adaptiveLight: 0xD7E1DB, dark: 0x36463E)
  static let suggested = Color(adaptiveLight: 0x245E45, dark: 0x8BD7AE)
  static let discussion = Color(adaptiveLight: 0xA65D00, dark: 0xFFB65C)
  static let discussionSurface = Color(adaptiveLight: 0xFFF4E5, dark: 0x3A2A17)
  static let safety = Color(adaptiveLight: 0xB42318, dark: 0xFF8A80)
  static let safetySurface = Color(adaptiveLight: 0xFDECEA, dark: 0x3B1D1B)

  static let cornerRadius: CGFloat = 16
  static let pageInset: CGFloat = 20
  static let cardPadding: CGFloat = 16
}

private extension Color {
  init(adaptiveLight: UInt, dark: UInt) {
    self.init(uiColor: UIColor { traits in
      UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : adaptiveLight)
    })
  }
}

private extension UIColor {
  convenience init(rgb: UInt) {
    self.init(
      red: CGFloat((rgb >> 16) & 0xFF) / 255,
      green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255,
      alpha: 1
    )
  }
}

struct GIJournalCard: ViewModifier {
  var padding: CGFloat = GIJournalTheme.cardPadding

  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background(GIJournalTheme.surface, in: RoundedRectangle(cornerRadius: GIJournalTheme.cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: GIJournalTheme.cornerRadius, style: .continuous)
          .stroke(GIJournalTheme.border, lineWidth: 1)
      }
  }
}

extension View {
  func giJournalCard(padding: CGFloat = GIJournalTheme.cardPadding) -> some View {
    modifier(GIJournalCard(padding: padding))
  }
}

struct GIJournalPrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(isEnabled ? GIJournalTheme.surface : GIJournalTheme.secondaryText)
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.horizontal, 12)
      .background(
        isEnabled
          ? (configuration.isPressed ? GIJournalTheme.primaryPressed : GIJournalTheme.primary)
          : GIJournalTheme.tintedSurface,
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        if !isEnabled {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(GIJournalTheme.border, lineWidth: 1)
        }
      }
  }
}

struct GIJournalSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(GIJournalTheme.primary)
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.horizontal, 12)
      .background(GIJournalTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(GIJournalTheme.primary.opacity(configuration.isPressed ? 0.85 : 0.65), lineWidth: 1)
      }
  }
}

struct GIJournalBadge: View {
  let title: String
  var symbol: String? = nil
  var foreground = GIJournalTheme.suggested
  var background = GIJournalTheme.tintedSurface

  var body: some View {
    Label {
      Text(title)
    } icon: {
      if let symbol { Image(systemName: symbol) }
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(foreground)
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .background(background, in: Capsule())
    .accessibilityElement(children: .combine)
  }
}

struct GIJournalHelpButton: View {
  let route: GIJournalHelpRoute
  @Binding var routeToPresent: GIJournalHelpRoute?
  @State private var openedThisSheet = false
  @AccessibilityFocusState private var isAccessibilityFocused: Bool

  var body: some View {
    Button {
      openedThisSheet = true
      routeToPresent = route
    } label: {
      Image(systemName: "questionmark.circle")
        .font(.title3)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(GIJournalTheme.primary)
    .accessibilityLabel(route.accessibilityLabel)
    .accessibilityHint("Opens help")
    .accessibilityFocused($isAccessibilityFocused)
    .onChange(of: routeToPresent?.id) { _, newRouteID in
      guard newRouteID == nil, openedThisSheet else { return }
      openedThisSheet = false
      isAccessibilityFocused = true
    }
  }
}
