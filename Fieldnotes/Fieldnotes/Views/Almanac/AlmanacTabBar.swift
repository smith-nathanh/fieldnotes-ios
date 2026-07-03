import SwiftUI

enum AlmanacTab: String, CaseIterable, Identifiable {
    case listen
    case photo
    case log
    case stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listen: return "Listen"
        case .photo: return "Photo"
        case .log: return "Log"
        case .stats: return "Stats"
        }
    }
}

/// Single rounded ink bar with four evenly-spaced mono labels (§4). No shadow.
struct AlmanacTabBar: View {
    @Binding var selection: AlmanacTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AlmanacTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.title.uppercased())
                        .font(.mono(11, .medium))
                        .tracking(.tracking(0.10, at: 11))
                        .foregroundStyle(selection == tab ? Color.rustSoft : Color.tan)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 22)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
        .padding(.horizontal, AlmanacLayout.screenPadding)
    }
}

/// Bottom padding reserved on each screen's scroll content so it clears the
/// floating tab bar.
extension CGFloat {
    static let tabBarClearance: CGFloat = 96
}
