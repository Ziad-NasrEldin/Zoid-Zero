import AppKit
import SwiftUI

enum Sumi {
  static let ink = dynamic(light: .init(white: 0.05, alpha: 1), dark: .init(white: 0.94, alpha: 1))
  static let paper = dynamic(light: .white, dark: .init(white: 0.06, alpha: 1))
  static let softPaper = dynamic(
    light: .init(white: 0.98, alpha: 1), dark: .init(white: 0.11, alpha: 1))
  static let rule = dynamic(light: .init(white: 0.58, alpha: 1), dark: .init(white: 0.42, alpha: 1))
  static let muted = dynamic(
    light: .init(white: 0.33, alpha: 1), dark: .init(white: 0.72, alpha: 1))
  static let seal = dynamic(
    light: .init(srgbRed: 194 / 255, green: 58 / 255, blue: 46 / 255, alpha: 1),
    dark: .init(srgbRed: 224 / 255, green: 96 / 255, blue: 81 / 255, alpha: 1)
  )
  static let sealWash = dynamic(
    light: .init(srgbRed: 245 / 255, green: 229 / 255, blue: 227 / 255, alpha: 1),
    dark: .init(srgbRed: 61 / 255, green: 27 / 255, blue: 24 / 255, alpha: 1)
  )

  static func display(_ size: CGFloat) -> Font {
    .system(size: size, weight: .regular, design: .serif)
  }

  static func body(_ size: CGFloat = 14) -> Font {
    .system(size: size, weight: .regular, design: .serif)
  }

  private static func dynamic(light: NSColor, dark: NSColor) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
      })
  }
}

struct InkButtonStyle: ButtonStyle {
  let accent: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold, design: .serif))
      .foregroundStyle(accent ? Color.white : Sumi.ink)
      .padding(.horizontal, 18)
      .frame(height: 38)
      .background(accent ? Sumi.seal : Sumi.softPaper)
      .overlay(Rectangle().stroke(accent ? Sumi.seal : Sumi.rule, lineWidth: 1))
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct InkFieldLabel: View {
  let text: String

  var body: some View {
    Text(text.uppercased())
      .font(.system(size: 10, weight: .semibold, design: .serif))
      .tracking(1.6)
      .foregroundStyle(Sumi.muted)
  }
}
