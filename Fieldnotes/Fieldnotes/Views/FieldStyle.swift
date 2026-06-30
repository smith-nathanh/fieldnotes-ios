import SwiftUI

enum FieldStyle {
    static let paper = Color(red: 0.985, green: 0.980, blue: 0.958)
    static let paperRaised = Color(red: 1.000, green: 0.996, blue: 0.982)
    static let paperRecessed = Color(red: 0.938, green: 0.930, blue: 0.900)
    static let ink = Color(red: 0.105, green: 0.090, blue: 0.070)
    static let inkMuted = Color(red: 0.525, green: 0.485, blue: 0.415)
    static let inkFaint = Color(red: 0.650, green: 0.610, blue: 0.535)
    static let rule = Color.black.opacity(0.095)
    static let moss = Color(red: 0.260, green: 0.330, blue: 0.220)
    static let leaf = Color(red: 0.195, green: 0.500, blue: 0.300)
    static let clay = Color(red: 0.680, green: 0.365, blue: 0.160)
    static let sky = Color(red: 0.255, green: 0.420, blue: 0.560)

    static func confidenceColor(_ confidence: Float?) -> Color {
        guard let confidence else {
            return inkFaint
        }
        if confidence >= 0.85 {
            return leaf
        }
        if confidence >= 0.70 {
            return clay
        }
        return inkFaint
    }
}

struct FieldPageHeader: View {
    var title: String
    var subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(FieldStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if let subtitle {
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .tracking(0.4)
                    .foregroundStyle(FieldStyle.inkFaint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

struct FieldSectionLabel: View {
    var title: String
    var systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }
            Text(title)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.4)
        }
        .foregroundStyle(FieldStyle.inkMuted)
    }
}

struct FieldPill: View {
    var text: String
    var systemImage: String?
    var color: Color

    init(_ text: String, systemImage: String? = nil, color: Color = FieldStyle.moss) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.10), in: Capsule())
    }
}

struct FieldMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .foregroundStyle(FieldStyle.ink)
            Text(title)
                .font(.caption2.weight(.medium))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(FieldStyle.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FieldPanelModifier: ViewModifier {
    var inset: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(inset)
            .background(FieldStyle.paperRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FieldStyle.rule)
            }
            .shadow(color: .black.opacity(0.035), radius: 12, x: 0, y: 7)
    }
}

extension View {
    func fieldPanel(inset: CGFloat = 16) -> some View {
        modifier(FieldPanelModifier(inset: inset))
    }

    func fieldPageBackground() -> some View {
        background(FieldStyle.paper.ignoresSafeArea())
    }
}
