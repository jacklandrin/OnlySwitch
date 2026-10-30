import SwiftUI

/// A station logo, falling back to a tinted radio glyph when there is none or it fails to load.
struct RadioStationArtwork: View {
    let name: String
    let url: URL?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            placeholder
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(size * 0.08)
                            .frame(width: size, height: size)
                            .background(.background)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.24))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(.primary.opacity(0.08))
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: "radio")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    /// A stable color per station name so the list stays recognizable without logos.
    private var tint: Color {
        let palette: [Color] = [.orange, .pink, .purple, .indigo, .blue, .teal, .green, .red]
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[seed % palette.count]
    }
}

/// Liquid Glass on macOS 26, material with a hairline elsewhere.
struct RadioSurface<S: Shape>: ViewModifier {
    let shape: S
    var interactive = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.stroke(.primary.opacity(0.08)) }
        }
    }
}

extension View {
    func radioSurface<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        modifier(RadioSurface(shape: shape, interactive: interactive))
    }
}

/// A rounded search field used by both station lists.
struct RadioSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button(RadioStrings.text("Radio Cancel"), systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .radioSurface(.capsule)
    }
}

/// The transient confirmation shown at the bottom of the page.
struct RadioMessageBanner: View {
    let message: RadioMessage

    var body: some View {
        Label {
            Text(message.text)
                .lineLimit(2)
        } icon: {
            Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(message.isError ? .orange : .green)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .radioSurface(.capsule)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension RadioBrowserStation {
    /// The regional-indicator flag for the station's country, if it has a valid code.
    var flag: String? { Self.flag(countryCode) }

    static func flag(_ countryCode: String) -> String? {
        let code = countryCode.uppercased()
        guard code.count == 2, code.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return nil }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }))
    }

    var detail: String {
        var parts: [String] = []
        if !country.isEmpty { parts.append([flag, country].compactMap { $0 }.joined(separator: " ")) }
        if !tags.isEmpty { parts.append(tags.prefix(3).joined(separator: ", ")) }
        if bitrate > 0 { parts.append("\(codec.isEmpty ? "" : codec + " ")\(bitrate) kbps") } else if !codec.isEmpty { parts.append(codec) }
        return parts.joined(separator: " · ")
    }
}
