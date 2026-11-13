import SwiftUI

/// 本周 7 天横条（docs/04-电视端UI.md §6：不做月历）。
/// 有作业的日子挂小红花圆点，圆点数据来自 /api/days，一次取一周。
/// 两端的 ‹ › 整周翻页；点某天切到那天。
struct DateStrip: View {
    @ObservedObject var vm: HomeViewModel
    @Environment(\.tz) private var tz

    var body: some View {
        let state = vm.state
        let days = DayLogic.weekDays(state.selectedDate)
        HStack(alignment: .center, spacing: tz.dp(14)) {
            Chevron(glyph: "‹", enabled: DayLogic.canGoBack(state.selectedDate, today: state.today)) {
                vm.selectDate(state.selectedDate.addingTimeInterval(-7 * 86_400))
            }
            ForEach(days, id: \.self) { date in
                DayCard(
                    date: date,
                    selected: date == state.selectedDate,
                    isToday: date == state.today,
                    hasWork: state.marks[DayLogic.format(date)]?.has == true
                )
                .frame(maxWidth: .infinity)
                .frame(height: tz.dp(104))
                .onTapGesture { vm.selectDate(date) }
            }
            Chevron(glyph: "›", enabled: DayLogic.canGoForward(state.selectedDate, today: state.today)) {
                vm.selectDate(state.selectedDate.addingTimeInterval(7 * 86_400))
            }
        }
        .frame(height: tz.dp(104))
    }
}

private struct Chevron: View {
    let glyph: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.tz) private var tz

    var body: some View {
        Text(glyph)
            .font(tz.h1)
            .foregroundStyle(color)
            .frame(width: tz.dp(40))
            .lineLimit(1)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .onHover { hovering = $0 }
    }

    private var color: Color {
        if hovering && enabled { return Tz.accent }
        if enabled { return Tz.textSecondary }
        return Tz.textDim.opacity(0.35)
    }
}

private struct DayCard: View {
    let date: Date
    let selected: Bool
    let isToday: Bool
    let hasWork: Bool
    @Environment(\.tz) private var tz

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: tz.dp(2)) {
                Text(weekday)
                    .font(tz.min)
                    .foregroundStyle(isToday ? Tz.textSecondary : Tz.textDim)
                    .lineLimit(1)
                Text(String(DayLogic.dayNumber(date)))
                    .font(tz.dateNumber)
                    .foregroundStyle(selected ? Tz.accent : Tz.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hasWork {
                Circle()
                    .fill(Tz.flower)
                    .frame(width: tz.dp(11), height: tz.dp(11))
                    .padding(.top, tz.dp(12))
                    .padding(.trailing, tz.dp(14))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: tz.dp(16))
                .fill(isToday ? Tz.bgRaised : Tz.bgSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: tz.dp(16))
                .strokeBorder(selected ? Tz.accent : Tz.line, lineWidth: selected ? 3 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: tz.dp(16)))
    }

    private var weekday: String {
        DayLogic.weekdayShort(date, locale: Texts.locale)
    }
}
