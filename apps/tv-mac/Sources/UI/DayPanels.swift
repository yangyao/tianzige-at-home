import AppKit
import SwiftUI

/// pending：原图网格（每行 3 张）；ready：左图右清单（52 / 48，与电视端一致）。
/// 点图进全屏阅读——黑板字小，全屏才是主要阅读方式（docs/04-电视端UI.md §7）。
struct PendingPanel: View {
    let day: DayView
    let baseUrl: String
    @ObservedObject var vm: HomeViewModel
    @Environment(\.tz) private var tz

    var body: some View {
        let rows = day.images.chunked(into: 3)
        VStack(spacing: tz.dp(24)) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: tz.dp(24)) {
                    ForEach(rows[rowIndex].indices, id: \.self) { columnIndex in
                        let index = rowIndex * 3 + columnIndex
                        PhotoCard(
                            url: DayLogic.absoluteUrl(baseUrl, rows[rowIndex][columnIndex].url),
                            onOpen: {
                                vm.selectImage(index)
                                vm.openFullscreen()
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ReadyPanel: View {
    let day: DayView
    let baseUrl: String
    @ObservedObject var vm: HomeViewModel
    @Environment(\.tz) private var tz

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: tz.dp(40)) {
                VStack(spacing: tz.dp(16)) {
                    ForEach(day.images.indices, id: \.self) { index in
                        PhotoCard(
                            url: DayLogic.absoluteUrl(baseUrl, day.images[index].url),
                            onOpen: {
                                vm.selectImage(index)
                                vm.openFullscreen()
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: geo.size.width * 0.52, alignment: .top)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: tz.dp(28)) {
                        ForEach(day.subjects.indices, id: \.self) { groupIndex in
                            let group = day.subjects[groupIndex]
                            VStack(alignment: .leading, spacing: tz.dp(12)) {
                                Text(Texts.subject(group.subject))
                                    .font(tz.body)
                                    .foregroundStyle(Tz.accent)
                                ForEach(group.items.indices, id: \.self) { itemIndex in
                                    Text(group.items[itemIndex].content)
                                        .font(tz.item)
                                        .lineSpacing(tz.itemLineSpacing)
                                        .foregroundStyle(Tz.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.bottom, tz.dp(20))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// 一张作业原图：圆角卡片 + 1px 描边，悬停变小手，点开全屏。
struct PhotoCard: View {
    let url: String?
    let onOpen: () -> Void
    @State private var hovering = false
    @Environment(\.tz) private var tz

    var body: some View {
        ZStack {
            Tz.bgSurface
            if let url, let imageUrl = URL(string: url) {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(tz.dp(5))
                    default:
                        Tz.bgSurface
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: tz.dp(20)))
        .overlay(
            RoundedRectangle(cornerRadius: tz.dp(20))
                .strokeBorder(hovering ? Tz.accent : Tz.line, lineWidth: hovering ? 3 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: tz.dp(20)))
        .onTapGesture { onOpen() }
        .onHover { inside in
            hovering = inside
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityLabel(L10n.string("cd_homework_photo"))
    }
}

extension Array {
    /// Kotlin `chunked(3)` 的对等实现：图片网格每行放 3 张。
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
