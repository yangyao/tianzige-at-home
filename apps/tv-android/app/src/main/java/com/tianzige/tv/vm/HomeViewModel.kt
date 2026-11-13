package com.tianzige.tv.vm

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.tianzige.tv.data.CacheStore
import com.tianzige.tv.data.DayMark
import com.tianzige.tv.data.DayView
import com.tianzige.tv.data.SettingsStore
import com.tianzige.tv.data.TvApi
import com.tianzige.tv.domain.DEFAULT_SERVER_URL
import com.tianzige.tv.domain.DayLogic
import com.tianzige.tv.domain.DayState
import com.tianzige.tv.domain.ErrorKind
import com.tianzige.tv.domain.ErrorText
import com.tianzige.tv.domain.SettingsNotice
import com.tianzige.tv.domain.SettingsPad
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate

data class HomeUiState(
    val serverUrl: String = DEFAULT_SERVER_URL,
    val today: LocalDate = LocalDate.now(),
    val selectedDate: LocalDate = LocalDate.now(),
    val day: DayView? = null,
    val dayLoading: Boolean = true,
    /** date(YYYY-MM-DD) -> 有作业标记，日期条圆点用 */
    val marks: Map<String, DayMark> = emptyMap(),
    /** 最近一次成功同步的 HH:mm */
    val updatedAt: String? = null,
    /** true = 当前画面来自缓存（网络没通） */
    val stale: Boolean = false,
    /** 完全没有缓存又连不上时才有值 */
    val fatalError: ErrorKind? = null,
    val subjectIndex: Int = 0,
    val imageIndex: Int = 0,
    val fullscreen: Boolean = false,
    val fullscreenUrl: String? = null,
    val showSettings: Boolean = false,
    val settingsDraft: String = "",
    val settingsNotice: SettingsNotice? = null,
    val settingsRow: Int = 0,
    val settingsCol: Int = 0,
    val exitConfirm: Boolean = false,
    /** 0 = 继续看，1 = 退出 */
    val exitChoice: Int = 0,
    val exitRequested: Boolean = false,
) {
    fun dayState(): DayState = day?.let { DayLogic.effectiveState(it) } ?: DayState.EMPTY
}

/**
 * 唯一的状态持有者。
 * 两条硬规则（协议 §5.3）：
 *  1. 先渲染缓存，再后台刷新；
 *  2. 刷新失败时保留旧数据，只把标题角标改成「上次更新」，不要清屏。
 */
class HomeViewModel(app: Application) : AndroidViewModel(app) {

    private val settings = SettingsStore(app)
    private val cache = CacheStore(app)
    private val api = TvApi()

    private val _state = MutableStateFlow(
        HomeUiState(
            serverUrl = settings.serverUrl(),
            today = LocalDate.now(),
            selectedDate = LocalDate.now(),
        )
    )
    val state: StateFlow<HomeUiState> = _state.asStateFlow()

    private val dayMemory = mutableMapOf<String, DayView>()
    private val markMemory = mutableMapOf<String, DayMark>()

    private var dayJob: Job? = null
    private var marksJob: Job? = null
    private var lastFetchAt = 0L
    private var hasEverLoaded = false
    private var autoSettingsShown = false
    private var userNavigated = false

    init {
        restoreCache()
        fetchDay(target = _state.value.today, jumpToDate = !userNavigated)
        ensureMarks(_state.value.today)
    }

    // ---------------------------------------------------------------- 缓存

    private fun restoreCache() {
        val cached = cache.readDay() ?: return
        val date = DayLogic.parseDate(cached.day.date) ?: return
        dayMemory[DayLogic.format(date)] = cached.day
        hasEverLoaded = true
        cache.readMarks()?.days?.forEach { markMemory[it.date] = it }
        _state.update {
            it.copy(
                day = cached.day,
                selectedDate = date,
                updatedAt = DayLogic.timeLabel(cached.savedAt),
                stale = true,
                dayLoading = true,
                marks = markMemory.toMap(),
            )
        }
    }

    // ---------------------------------------------------------------- 网络

    private fun fetchDay(target: LocalDate, jumpToDate: Boolean) {
        dayJob?.cancel()
        dayJob = viewModelScope.launch {
            lastFetchAt = System.currentTimeMillis()
            val baseUrl = _state.value.serverUrl
            try {
                val day = api.getDay(baseUrl, target)
                dayMemory[DayLogic.format(target)] = day
                hasEverLoaded = true
                cache.writeDay(day)
                _state.update { s ->
                    val jump = jumpToDate && !userNavigated
                    s.copy(
                        day = day,
                        selectedDate = if (jump) target else s.selectedDate,
                        dayLoading = false,
                        stale = false,
                        updatedAt = DayLogic.nowLabel(),
                        fatalError = null,
                        subjectIndex = if (jump) 0 else s.subjectIndex,
                        imageIndex = if (jump) 0 else s.imageIndex,
                    )
                }
                ensureMarks(target, force = true)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                onDayFailure(target, e)
            }
        }
    }

    private fun onDayFailure(target: LocalDate, error: Exception) {
        val key = DayLogic.format(target)
        val memory = dayMemory[key]
        if (memory != null) {
            _state.update {
                it.copy(day = memory, dayLoading = false, stale = true, fatalError = null)
            }
            return
        }
        val fileCache = cache.readDay()?.takeIf { it.day.date == key }
        if (fileCache != null) {
            dayMemory[key] = fileCache.day
            _state.update {
                it.copy(
                    day = fileCache.day,
                    dayLoading = false,
                    stale = true,
                    fatalError = null,
                    updatedAt = DayLogic.timeLabel(fileCache.savedAt) ?: it.updatedAt,
                )
            }
            return
        }
        _state.update {
            it.copy(day = null, dayLoading = false, stale = false, fatalError = ErrorText.kindOf(error))
        }
        if (!hasEverLoaded && !autoSettingsShown) {
            autoSettingsShown = true
            openSettings(notice = SettingsNotice.Unreachable)
        }
    }

    /** 日期条圆点：一次取一周（/api/days 会返回区间内每一天）。 */
    private fun ensureMarks(date: LocalDate, force: Boolean = false) {
        val week = DayLogic.weekDays(date)
        val covered = week.all { markMemory.containsKey(DayLogic.format(it)) }
        if (covered && !force) {
            _state.update { it.copy(marks = markMemory.toMap()) }
            return
        }
        marksJob?.cancel()
        marksJob = viewModelScope.launch {
            val baseUrl = _state.value.serverUrl
            try {
                val marks = api.getDays(baseUrl, week.first(), week.last())
                marks.forEach { markMemory[it.date] = it }
                cache.writeMarks(markMemory.values.toList())
                _state.update { it.copy(marks = markMemory.toMap()) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // 圆点缺失不影响主流程，静默失败（协议 §5.1：图优先）
            }
        }
    }

    // ---------------------------------------------------------------- 日期与科目

    fun selectDate(date: LocalDate) {
        val clamped = DayLogic.clampSelectable(date, _state.value.today)
        if (clamped == _state.value.selectedDate) return
        userNavigated = true
        val cached = dayMemory[DayLogic.format(clamped)]
        _state.update {
            it.copy(
                selectedDate = clamped,
                day = cached,
                dayLoading = cached == null,
                stale = false,
                fatalError = null,
                subjectIndex = 0,
                imageIndex = 0,
                fullscreen = false,
                fullscreenUrl = null,
            )
        }
        fetchDay(target = clamped, jumpToDate = false)
        ensureMarks(clamped)
    }

    fun moveDay(delta: Int) {
        val now = _state.value
        selectDate(DayLogic.shiftDate(now.selectedDate, delta, now.today))
    }

    /** ↑↓：ready 换科目，pending 换图（docs/04-电视端UI.md §2）。 */
    fun selectImage(index: Int) {
        _state.update { it.copy(imageIndex = DayLogic.clampIndex(index, it.day?.images?.size ?: 0)) }
    }

    fun selectSubject(index: Int) {
        _state.update { it.copy(subjectIndex = DayLogic.clampIndex(index, it.day?.subjects?.size ?: 0)) }
    }

    fun stepItem(delta: Int) {
        val now = _state.value
        val day = now.day ?: return
        when (DayLogic.effectiveState(day)) {
            DayState.READY -> _state.update {
                it.copy(subjectIndex = DayLogic.clampIndex(it.subjectIndex + delta, day.subjects.size))
            }
            DayState.PENDING -> _state.update {
                it.copy(imageIndex = DayLogic.clampIndex(it.imageIndex + delta, day.images.size))
            }
            DayState.EMPTY -> Unit
        }
    }

    // ---------------------------------------------------------------- 全屏

    fun openFullscreen() {
        val now = _state.value
        val day = now.day ?: return
        val path = day.images.getOrNull(DayLogic.clampIndex(now.imageIndex, day.images.size))?.url
            ?: return
        val url = DayLogic.absoluteUrl(now.serverUrl, path)
        _state.update { it.copy(fullscreen = true, fullscreenUrl = url) }
    }

    fun closeFullscreen() {
        _state.update { it.copy(fullscreen = false, fullscreenUrl = null) }
    }

    // ---------------------------------------------------------------- 返回键

    fun onBack() {
        val now = _state.value
        when {
            now.fullscreen -> closeFullscreen()
            now.showSettings -> closeSettings()
            now.exitConfirm -> _state.update { it.copy(exitConfirm = false) }
            else -> _state.update { it.copy(exitConfirm = true, exitChoice = 0) }
        }
    }

    fun moveExitChoice(delta: Int) {
        _state.update { it.copy(exitChoice = (it.exitChoice + delta).coerceIn(0, 1)) }
    }

    fun confirmExit() {
        if (_state.value.exitChoice == 1) {
            _state.update { it.copy(exitRequested = true, exitConfirm = false) }
        } else {
            _state.update { it.copy(exitConfirm = false) }
        }
    }

    // ---------------------------------------------------------------- 设置屏

    fun openSettings(notice: SettingsNotice? = null) {
        _state.update {
            it.copy(
                showSettings = true,
                settingsDraft = it.serverUrl,
                settingsNotice = notice,
                settingsRow = 0,
                settingsCol = 0,
            )
        }
    }

    fun closeSettings() {
        _state.update { it.copy(showSettings = false, settingsNotice = null) }
    }

    fun settingsMove(dRow: Int, dCol: Int) {
        _state.update {
            val (row, col) = SettingsPad.move(it.settingsRow, it.settingsCol, dRow, dCol)
            it.copy(settingsRow = row, settingsCol = col)
        }
    }

    fun settingsActivate() {
        val now = _state.value
        if (SettingsPad.isInputRow(now.settingsRow)) {
            val key = SettingsPad.keyLabel(now.settingsRow, now.settingsCol)
            _state.update {
                it.copy(
                    settingsDraft = SettingsPad.append(it.settingsDraft, key),
                    settingsNotice = null,
                )
            }
            return
        }
        when (now.settingsCol) {
            0 -> saveSettings()
            1 -> testConnection()
            2 -> _state.update {
                it.copy(settingsDraft = "", settingsNotice = null)
            }
        }
    }

    private fun saveSettings() {
        val raw = _state.value.settingsDraft
        if (!DayLogic.isPlausibleServerUrl(raw)) {
            _state.update {
                it.copy(settingsNotice = SettingsNotice.BadAddress)
            }
            return
        }
        val url = DayLogic.normalizeServerUrl(raw)
        settings.saveServerUrl(url)
        dayJob?.cancel()
        marksJob?.cancel()
        dayMemory.clear()
        markMemory.clear()
        userNavigated = false
        val today = _state.value.today
        _state.update {
            it.copy(
                serverUrl = url,
                marks = emptyMap(),
                showSettings = false,
                settingsNotice = null,
                day = null,
                dayLoading = true,
                stale = false,
                fatalError = null,
                updatedAt = null,
                selectedDate = today,
                subjectIndex = 0,
                imageIndex = 0,
                fullscreen = false,
                fullscreenUrl = null,
            )
        }
        fetchDay(target = today, jumpToDate = true)
        ensureMarks(today)
    }

    private fun testConnection() {
        val raw = _state.value.settingsDraft
        if (!DayLogic.isPlausibleServerUrl(raw)) {
            _state.update {
                it.copy(settingsNotice = SettingsNotice.BadAddress)
            }
            return
        }
        val url = DayLogic.normalizeServerUrl(raw)
        _state.update {
            it.copy(settingsNotice = SettingsNotice.Testing)
        }
        viewModelScope.launch {
            val notice = try {
                val health = api.health(url)
                SettingsNotice.Connected(health.version)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                SettingsNotice.Failed(ErrorText.kindOf(e))
            }
            _state.update { it.copy(settingsNotice = notice) }
        }
    }

    // ---------------------------------------------------------------- 回到前台

    /** 电视常年不关机，回到前台顺手刷一次（30 秒内不重复请求）。 */
    fun onResume() = refreshIfNeeded()

    fun refreshIfNeeded(backgroundPoll: Boolean = false) {
        if (_state.value.showSettings) return
        val interval = if (!backgroundPoll) 30_000L else if (_state.value.dayState() == DayState.PENDING) 4_000L else 300_000L
        if (System.currentTimeMillis() - lastFetchAt < interval) return
        val today = LocalDate.now()
        _state.update { it.copy(today = today, selectedDate = if (it.selectedDate == it.today) today else it.selectedDate) }
        fetchDay(target = _state.value.selectedDate, jumpToDate = false)
        ensureMarks(_state.value.selectedDate)
    }
}
