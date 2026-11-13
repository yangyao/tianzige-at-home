import SwiftUI

/// 首屏：顶栏（标题 + 日期 + 状态角标 + 设置入口）、本周日期条、内容区。
/// 布局参数与 Android TV 端 HomeScreen.kt 一致，只是交互从遥控器换成鼠标。
struct HomeView: View {
    @ObservedObject var vm: HomeViewModel
    @Environment(\.tz) private var tz

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.top, tz.dp(48))
                .padding(.bottom, tz.dp(26))
            DateStrip(vm: vm)
                .padding(.bottom, tz.dp(30))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, tz.dp(48))
        }
        .padding(.horizontal, tz.dp(60))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tz.bgBase)
    }

    // ---------------------------------------------------------------- 顶栏

    private var topBar: some View {
        HStack(alignment: .center, spacing: tz.dp(28)) {
            Text(title)
                .font(tz.h1)
                .foregroundStyle(Tz.textPrimary)
                .lineLimit(1)
            Text(Texts.header(state.selectedDate))
                .font(tz.body)
                .foregroundStyle(Tz.textSecondary)
                .lineLimit(1)
            Spacer()
            if state.stale {
                chip(L10n.string("chip_cached"), color: Tz.warn)
            }
            if let updatedAt = state.updatedAt {
                chip(L10n.format("chip_updated", updatedAt), color: Tz.textSecondary)
            }
            settingsButton
        }
    }

    private var settingsButton: some View {
        Button {
            vm.openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: tz.dp(34), weight: .regular))
                .foregroundStyle(Tz.textSecondary)
        }
        .buttonStyle(.plain)
        .help(L10n.string("menu.settings"))
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(tz.min)
            .foregroundStyle(color)
            .padding(.horizontal, tz.dp(18))
            .padding(.vertical, tz.dp(8))
            .background(
                Capsule().fill(Tz.bgRaised)
                    .overlay(Capsule().strokeBorder(Tz.line, lineWidth: 1))
            )
    }

    // ---------------------------------------------------------------- 内容区

    @ViewBuilder
    private var content: some View {
        let day = state.day
        if day == nil && state.dayLoading {
            centerText(L10n.string("loading"), color: Tz.textDim, font: tz.body)
        } else if day == nil {
            ErrorPanel(state: state, onCheck: { vm.openSettings() })
        } else if let day {
            switch state.dayState() {
            case .empty:
                centerText(
                    L10n.string(state.selectedDate == state.today ? "empty_today" : "empty_day"),
                    color: Tz.textDim,
                    font: tz.display
                )
            case .pending:
                PendingPanel(day: day, baseUrl: state.serverUrl, vm: vm)
            case .ready:
                ReadyPanel(day: day, baseUrl: state.serverUrl, vm: vm)
            }
        }
    }

    private func centerText(_ text: String, color: Color, font: Font) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ---------------------------------------------------------------- 便捷取值

    private var state: HomeUiState { vm.state }

    private var title: String {
        let key = DayLogic.format(state.selectedDate)
        let serverDay = state.day.flatMap { $0.date == key ? $0 : nil }
        return Texts.dayTitle(
            state.selectedDate,
            isToday: state.selectedDate == state.today,
            daysAgo: serverDay?.daysAgo
        )
    }
}

/// 连不上：主文案说结论，副文案给出路（DESIGN.md §9）。
struct ErrorPanel: View {
    let state: HomeUiState
    let onCheck: () -> Void
    @Environment(\.tz) private var tz

    var body: some View {
        VStack(spacing: tz.dp(10)) {
            Text(L10n.string("error_title"))
                .font(tz.h1)
                .foregroundStyle(Tz.textPrimary)
            Text(state.fatalError.map(Texts.errorText) ?? L10n.string("error_panel_fallback"))
                .font(tz.body)
                .foregroundStyle(Tz.textSecondary)
            Text(state.serverUrl)
                .font(tz.caption)
                .foregroundStyle(Tz.textDim)
            Button(L10n.string("error_check")) { onCheck() }
                .font(tz.body)
                .buttonStyle(.plain)
                .foregroundStyle(Tz.accent)
                .padding(.top, tz.dp(22))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture { onCheck() }
    }
}
