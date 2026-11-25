import SwiftUI

/// Klavyenin hemen üstündeki hızlı tuş çubuğu.
struct AccessoryBar: View {
    @EnvironmentObject private var connection: ConnectionManager

    private enum Action {
        case key(String)
        case combo([String])
    }

    private let items: [(label: String, icon: String?, action: Action)] = [
        ("Esc", nil, .key("esc")),
        ("Tab", nil, .key("tab")),
        ("Win", "squareshape.split.2x2", .key("win")),
        ("Alt+F4", nil, .combo(["alt", "f4"])),
        ("", "arrow.left", .key("left")),
        ("", "arrow.up", .key("up")),
        ("", "arrow.down", .key("down")),
        ("", "arrow.right", .key("right")),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    Button {
                        switch item.action {
                        case .key(let name): connection.key(name)
                        case .combo(let keys): connection.combo(keys)
                        }
                        Haptics.key()
                    } label: {
                        Group {
                            if let icon = item.icon, item.label.isEmpty {
                                Image(systemName: icon)
                            } else if let icon = item.icon {
                                Label(item.label, systemImage: icon).labelStyle(.titleAndIcon)
                            } else {
                                Text(item.label)
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.11))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 44)
        .background(Color(white: 0.07))
    }
}
