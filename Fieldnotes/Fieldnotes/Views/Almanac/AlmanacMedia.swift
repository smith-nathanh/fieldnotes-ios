import SwiftUI

// MARK: - Category tag (§4)

/// Paper fill, ink border, mono uppercase. Overlaid on photo frames.
struct CategoryTag: View {
    var text: String

    var body: some View {
        TagChip(text: text, textColor: .ink, fill: .paper, borderColor: .ink)
    }
}

// MARK: - Diagonal hatch placeholder

struct DiagonalHatch: Shape {
    var spacing: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.height))
            x += spacing
        }
        return path
    }
}

struct HatchPlaceholder: View {
    var text: String = "[ your capture ]"

    var body: some View {
        ZStack {
            Color.paperCardAlt
            DiagonalHatch()
                .stroke(Color.ink.opacity(0.12), lineWidth: 1)
            Text(text)
                .font(.mono(11, .regular))
                .tracking(.tracking(0.08, at: 11))
                .foregroundStyle(Color.inkSoft)
        }
    }
}

// MARK: - Photo frame (§4)

/// Radius 16, 1.5 pt ink border, optional category tag overlaid bottom-left.
struct PhotoFrame<Content: View>: View {
    var categoryTag: String?
    @ViewBuilder var content: () -> Content

    init(categoryTag: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.categoryTag = categoryTag
        self.content = content
    }

    var body: some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.ink, lineWidth: 1.5)
            )
            .overlay(alignment: .bottomLeading) {
                if let categoryTag {
                    CategoryTag(text: categoryTag)
                        .padding(10)
                }
            }
    }
}

// MARK: - Match-rank row (§4)

struct MatchRankRow: View {
    var rank: Int
    var name: String
    var scientificName: String
    var score: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RankChip(rank: rank)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.serif(18, .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Text(scientificName)
                    .font(.serifItalic(13))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(score)
                .font(.serif(19, .semibold))
                .foregroundStyle(rank == 1 ? Color.ink : Color.inkSoft)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }
}

// MARK: - Sonogram / waveform (§4)

/// Row of thin vertical rust bars. Static heights for detail views.
struct Sonogram: View {
    var heights: [CGFloat]
    var color: Color = .rust
    var barWidth: CGFloat = 4
    var gap: CGFloat = 3

    var body: some View {
        HStack(alignment: .center, spacing: gap) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: barWidth, height: height)
            }
        }
    }

    /// Deterministic pseudo-random bar heights (~10–64) for stable static art.
    static func sample(count: Int = 34, seed: UInt64 = 0x9E4A26) -> [CGFloat] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double((state >> 33) & 0x7FFFFF) / Double(0x7FFFFF)
            return 10 + CGFloat(unit) * 54
        }
    }
}

// MARK: - Play control (§4)

struct PlayCircle: View {
    var isPlaying: Bool = false
    var size: CGFloat = 48
    var isEnabled: Bool = true

    var body: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(Color.paper)
            .frame(width: size, height: size)
            .background(Circle().fill(isEnabled ? Color.rust : Color.tan))
    }
}
