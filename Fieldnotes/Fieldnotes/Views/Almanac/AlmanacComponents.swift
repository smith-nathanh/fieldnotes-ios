import SwiftUI

// MARK: - Layout constants

enum AlmanacLayout {
    /// Screen horizontal padding (§3).
    static let screenPadding: CGFloat = 26
}

// MARK: - Screen background

extension View {
    func almanacBackground() -> some View {
        background(Color.paper.ignoresSafeArea())
    }
}

// MARK: - Eyebrow

/// Mono uppercase section label, tracked. Rust by default (§7).
struct Eyebrow: View {
    let text: String
    var color: Color = .rust
    var size: CGFloat = 11

    init(_ text: String, color: Color = .rust, size: CGFloat = 11) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(.mono(size, .medium))
            .tracking(.tracking(0.20, at: size))
            .foregroundStyle(color)
    }
}

// MARK: - Double rule (signature motif, §3)

struct DoubleRule: View {
    var body: some View {
        VStack(spacing: 1) {
            Rectangle().fill(Color.ink).frame(height: 1)
            Rectangle().fill(Color.ink).frame(height: 1)
        }
    }
}

// MARK: - Masthead

/// Double rule → optional mono eyebrow → serif title → optional italic subtitle.
struct Masthead: View {
    var eyebrow: String?
    var title: String
    var subtitle: String?
    var titleSize: CGFloat = 40
    var titleWeight: Font.Weight = .bold

    init(
        title: String,
        eyebrow: String? = nil,
        subtitle: String? = nil,
        titleSize: CGFloat = 40,
        titleWeight: Font.Weight = .bold
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.titleSize = titleSize
        self.titleWeight = titleWeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DoubleRule()
                .padding(.bottom, 2)
            if let eyebrow {
                Eyebrow(eyebrow)
            }
            Text(title)
                .font(.serif(titleSize, titleWeight))
                .tracking(-0.5)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.serifItalic(18))
                    .foregroundStyle(Color.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Plate badge (§4)

/// 44×44 (default) bordered plate holding a mono index like `01`.
struct PlateBadge: View {
    let index: String
    var size: CGFloat = 44

    var body: some View {
        Text(index)
            .font(.mono(size * 0.27, .medium))
            .foregroundStyle(Color.rust)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.paperCard))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ink, lineWidth: 1.5))
    }
}

// MARK: - Rank chip (match-rank rows, §4)

/// Fully round rank chip; fill by rank (#1 rust, #2 olive, #3 tan).
struct RankChip: View {
    let rank: Int
    var size: CGFloat = 30

    private var fill: Color {
        switch rank {
        case 1: return .rust
        case 2: return .olive
        case 3: return .tan
        default: return .paperCard
        }
    }

    private var numeral: Color {
        rank == 3 ? .ink : .paper
    }

    var body: some View {
        Text("\(rank)")
            .font(.serif(size * 0.5, .semibold))
            .foregroundStyle(numeral)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
    }
}

// MARK: - Metric block (big serif numeral + mono label)

struct MetricBlock: View {
    var title: String
    var value: String
    var valueColor: Color = .ink

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.serif(26, .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title.uppercased())
                .font(.mono(10, .regular))
                .tracking(.tracking(0.08, at: 10))
                .foregroundStyle(Color.monoLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Metric chip ("99% best", "21 detections")

struct MetricChip: View {
    var value: String
    var label: String
    var valueColor: Color = .rust

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.serif(22, .semibold))
                .foregroundStyle(valueColor)
            Text(label.uppercased())
                .font(.mono(10, .regular))
                .tracking(.tracking(0.08, at: 10))
                .foregroundStyle(Color.monoLabel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.paperCard))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ink, lineWidth: 1))
    }
}

// MARK: - Similarity / confidence chip (§4)

/// Big number on an ink chip with a mono unit label.
struct SimilarityChip: View {
    var value: String
    var unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(value)
                .font(.serif(26))
                .foregroundStyle(Color.paper)
            Text(unit.uppercased())
                .font(.mono(11, .regular))
                .tracking(.tracking(0.08, at: 11))
                .foregroundStyle(Color.chipUnit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.ink))
    }
}

// MARK: - Small mono tag chip (`new`, `recent`, category)

struct TagChip: View {
    var text: String
    var textColor: Color = .ink
    var fill: Color = .paperCard
    var borderColor: Color? = .ink

    var body: some View {
        Text(text.uppercased())
            .font(.mono(10, .medium))
            .tracking(.tracking(0.08, at: 10))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .overlay {
                if let borderColor {
                    RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1)
                }
            }
    }
}

// MARK: - Buttons

/// Full-width rust primary button (§4).
struct AlmanacButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.serif(19, .semibold))
            .foregroundStyle(Color.buttonInk)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.rust))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Bordered secondary button — transparent fill, ink border, ink text.
struct AlmanacSecondaryButton: ButtonStyle {
    var disabled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.serif(19, .semibold))
            .foregroundStyle(disabled ? Color.inkFaint : Color.ink)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(disabled ? Color.lineWarm : Color.ink, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Segmented control (pill chips, §4)

struct AlmanacSegmentedControl<Value: Hashable>: View {
    var options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.value) { option in
                let active = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title.uppercased())
                        .font(.mono(11, .medium))
                        .tracking(.tracking(0.10, at: 11))
                        .foregroundStyle(active ? Color.paper : Color.segInactive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if active {
                                Capsule().fill(Color.ink)
                            } else {
                                Capsule().stroke(Color.lineWarm, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Section (rust eyebrow + optional trailing + content)

struct AlmanacSection<Trailing: View, Content: View>: View {
    var title: String
    var trailing: Trailing
    var content: Content

    init(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(title)
                Spacer()
                trailing
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ledger row (flat hairline-divided list row)

/// A flat printed-ledger row: leading mono label, serif detail, trailing value.
struct LedgerRow: View {
    var label: String
    var detail: String
    var value: String
    var valueColor: Color = .rust
    var labelWidth: CGFloat = 34

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(.mono(11, .medium))
                .tracking(.tracking(0.08, at: 11))
                .foregroundStyle(Color.rust)
                .frame(width: labelWidth, alignment: .leading)
            Text(detail)
                .font(.serif(18))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(value)
                .font(.serif(19, .semibold))
                .foregroundStyle(valueColor)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }
}

// MARK: - Empty state

struct AlmanacEmpty: View {
    var title: String
    var message: String?

    init(_ title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.serif(20, .semibold))
                .foregroundStyle(Color.inkSoft)
            if let message {
                Text(message)
                    .font(.mono(11, .regular))
                    .tracking(.tracking(0.06, at: 11))
                    .foregroundStyle(Color.monoLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
