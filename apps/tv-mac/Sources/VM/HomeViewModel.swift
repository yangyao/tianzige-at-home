import Foundation
import Combine

/// 一次性快照整个界面状态。VM 是唯一的状态持有者。
/// 两条硬规则（协议 §5.3）：
///  1. 先渲染缓存，再后台刷新；
///  2. 刷新失败时保留旧数据，只把角标改成「上次更新」，不要清屏。
struct HomeUiState {
    var serverUrl: String = DEFAULT_SERVER_URL
    var today: Date = DayLogic.startOfDay(Date())
    var selectedDate: Date = DayLogic.startOfDay(Date())
    var day: DayView?
    var dayLoading = true
    /// date(YYYY-MM-DD) -> 有作业标记，日期条圆点用
    var marks: [String: DayMark] = [:]
    /// 最近一次成功同步的 HH:mm
    var updatedAt: String?
    /// true = 当前画面来自缓存（网络没通）
    var stale = false
    /// 完全没有缓存又连不上时才有值
    var fatalError: ErrorKind?
    var subjectIndex = 0
    var imageIndex = 0
    var fullscreen = false
    var fullscreenUrl: String?
    var showSettings = false
    var settingsDraft = ""
    var settingsNotice: SettingsNotice?

    func dayState() -> DayState {
        day.map { DayLogic.effectiveState($0) } ?? .empty
    }
}

@MainActor
final class HomeViewModel: ObservableObject {

    @Published private(set) var state: HomeUiState

    private let settings: SettingsStore
    private let cache: CacheStore
    private let api = TvApi()

    private var dayMemory: [String: DayView] = [:]
    private var markMemory: [String: DayMark] = [:]

    private var dayTask: Task<Void, Never>?
    private var marksTask: Task<Void, Never>?
    private var lastFetchAt: TimeInterval = 0
    private var hasEverLoaded = false
    private var autoSettingsShown = false
    private var userNavigated = false

    init(settings: SettingsStore = SettingsStore(), cache: CacheStore? = nil) {
        self.settings = settings
        self.cache = cache ?? CacheStore(settings: settings)
        state = HomeUiState(
            serverUrl: settings.serverUrl(),
            today: DayLogic.startOfDay(Date()),
            selectedDate: DayLogic.startOfDay(Date())
        )
        restoreCache()
        fetchDay(target: state.today, jumpToDate: !userNavigated)
        ensureMarks(state.today, force: false)
    }

    // ---------------------------------------------------------------- 缓存

    private func restoreCache() {
        guard let cached = cache.readDay(),
              let date = DayLogic.parseDate(cached.day.date) else { return }
        dayMemory[DayLogic.format(date)] = cached.day
        hasEverLoaded = true
        cache.readMarks()?.forEach { markMemory[$0.date] = $0 }
        state.day = cached.day
        state.selectedDate = date
        state.updatedAt = DayLogic.timeLabel(cached.savedAt)
        state.stale = true
        state.dayLoading = true
        state.marks = markMemory
    }

    // ---------------------------------------------------------------- 网络

    private func fetchDay(target: Date, jumpToDate: Bool) {
        dayTask?.cancel()
        lastFetchAt = Date().timeIntervalSince1970
        let baseUrl = state.serverUrl
        dayTask = Task { [weak self] in
            guard let self else { return }
            do {
                let day = try await self.api.getDay(base: baseUrl, date: target)
                self.dayMemory[DayLogic.format(target)] = day
                self.hasEverLoaded = true
                self.cache.writeDay(day)
                let jump = jumpToDate && !self.userNavigated
                var s = self.state
                s.day = day
                if jump {
                    s.selectedDate = target
                    s.subjectIndex = 0
                    s.imageIndex = 0
                }
                s.dayLoading = false
                s.stale = false
                s.updatedAt = DayLogic.nowLabel()
                s.fatalError = nil
                self.state = s
                self.ensureMarks(target, force: true)
            } catch {
                // 用户主动取消 / 换了日期，别当成错误处理
                if error is CancellationError || Task.isCancelled { return }
                if (error as? URLError)?.code == .cancelled { return }
                self.onDayFailure(target: target, error: error)
            }
        }
    }

    private func onDayFailure(target: Date, error: Error) {
        let key = DayLogic.format(target)
        // 1. 内存里刚拉过的那份
        if let memory = dayMemory[key] {
            state.day = memory
            state.dayLoading = false
            state.stale = true
            state.fatalError = nil
            return
        }
        // 2. 磁盘缓存里那份（哪怕不是今天存的）
        if let fileCache = cache.readDay(), fileCache.day.date == key {
            dayMemory[key] = fileCache.day
            state.day = fileCache.day
            state.dayLoading = false
            state.stale = true
            state.fatalError = nil
            if state.updatedAt == nil {
                state.updatedAt = DayLogic.timeLabel(fileCache.savedAt)
            }
            return
        }
        // 3. 彻底没戏：只在这种情况才清屏、报错、自动弹设置
        state.day = nil
        state.dayLoading = false
        state.stale = false
        state.fatalError = ErrorKind.kind(of: error)
        if !hasEverLoaded && !autoSettingsShown {
            autoSettingsShown = true
            openSettings(notice: .unreachable)
        }
    }

    /// 日期条圆点：一次取一周（/api/days 会返回区间内每一天）。
    private func ensureMarks(_ date: Date, force: Bool) {
        let week = DayLogic.weekDays(date)
        if !force && week.allSatisfy({ markMemory[DayLogic.format($0)] != nil }) {
            state.marks = markMemory
            return
        }
        marksTask?.cancel()
        let baseUrl = state.serverUrl
        marksTask = Task { [weak self] in
            guard let self else { return }
            do {
                let marks = try await self.api.getDays(base: baseUrl, from: week[0], to: week[6])
                marks.forEach { self.markMemory[$0.date] = $0 }
                self.cache.writeMarks(Array(self.markMemory.values))
                self.state.marks = self.markMemory
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                // 圆点缺失不影响主流程，静默失败（协议 §5.1：图优先）
            }
        }
    }

    // ---------------------------------------------------------------- 日期与科目

    func selectDate(_ date: Date) {
        let clamped = DayLogic.clampSelectable(date, today: state.today)
        if clamped == state.selectedDate { return }
        userNavigated = true
        let cached = dayMemory[DayLogic.format(clamped)]
        state.selectedDate = clamped
        state.day = cached
        state.dayLoading = cached == nil
        state.stale = false
        state.fatalError = nil
        state.subjectIndex = 0
        state.imageIndex = 0
        if state.fullscreen { closeFullscreen() }
        fetchDay(target: clamped, jumpToDate: false)
        ensureMarks(clamped, force: false)
    }

    /// ready 换科目，pending 换图（docs/04-电视端UI.md §2）。Mac 上就是点哪张看哪张。
    func selectImage(_ index: Int) {
        state.imageIndex = DayLogic.clampIndex(index, state.day?.images.count ?? 0)
    }

    func openFullscreen() {
        guard let day = state.day, !day.images.isEmpty else { return }
        let path = day.images[DayLogic.clampIndex(state.imageIndex, day.images.count)].url
        guard !path.isEmpty else { return }
        state.fullscreen = true
        state.fullscreenUrl = DayLogic.absoluteUrl(state.serverUrl, path)
    }

    func closeFullscreen() {
        state.fullscreen = false
        state.fullscreenUrl = nil
    }

    // ---------------------------------------------------------------- 设置屏

    func openSettings(notice: SettingsNotice? = nil) {
        state.showSettings = true
        state.settingsDraft = state.serverUrl
        state.settingsNotice = notice
    }

    func closeSettings() {
        state.showSettings = false
        state.settingsNotice = nil
    }

    func saveSettings(draft: String) {
        guard DayLogic.isPlausibleServerUrl(draft) else {
            state.settingsNotice = .badAddress
            return
        }
        let url = DayLogic.normalizeServerUrl(draft)
        settings.saveServerUrl(url)
        dayTask?.cancel()
        marksTask?.cancel()
        dayMemory.removeAll()
        markMemory.removeAll()
        userNavigated = false
        let today = state.today
        state = HomeUiState(
            serverUrl: url,
            today: today,
            selectedDate: today
        )
        state.dayLoading = true
        fetchDay(target: today, jumpToDate: true)
        ensureMarks(today, force: false)
    }

    func testConnection(draft: String) {
        guard DayLogic.isPlausibleServerUrl(draft) else {
            state.settingsNotice = .badAddress
            return
        }
        let url = DayLogic.normalizeServerUrl(draft)
        state.settingsNotice = .testing
        Task { [weak self] in
            guard let self else { return }
            let notice: SettingsNotice
            do {
                let health = try await self.api.health(base: url)
                notice = .connected(version: health.version)
            } catch {
                notice = .failed(ErrorKind.kind(of: error))
            }
            self.state.settingsNotice = notice
        }
    }

    // ---------------------------------------------------------------- 刷新节律

    /// 回到前台顺手刷一次（30 秒内不重复请求）。
    func refreshIfBecameActive() {
        refreshIfNeeded(backgroundPoll: false)
    }

    /// 挂个 4 秒定时器走这里：pending 时 4 秒一刷（等识别结果），
    /// 其余 5 分钟一刷；设置面板开着时不动。
    func refreshIfNeeded(backgroundPoll: Bool) {
        if state.showSettings { return }
        let interval: TimeInterval = backgroundPoll
            ? (state.dayState() == .pending ? 4 : 300)
            : 30
        if Date().timeIntervalSince1970 - lastFetchAt < interval { return }
        let now = DayLogic.startOfDay(Date())
        let wasOnToday = state.selectedDate == state.today
        state.today = now
        if wasOnToday { state.selectedDate = now }
        fetchDay(target: state.selectedDate, jumpToDate: false)
        ensureMarks(state.selectedDate, force: false)
    }
}
