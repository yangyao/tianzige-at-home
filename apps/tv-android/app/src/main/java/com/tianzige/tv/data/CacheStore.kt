package com.tianzige.tv.data

import android.content.Context
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import java.time.OffsetDateTime
import java.time.ZoneOffset

// Namespace by server address so changing NAS never displays the previous server's data.
class CacheStore(context: Context) {
    private val settings = SettingsStore(context)
    private val prefs = context.getSharedPreferences("tianzige-cache", Context.MODE_PRIVATE)
    private fun key(kind: String) = settings.serverUrl() + "|" + kind
    fun readDay(): CachedDay? = runCatching {
        apiJson.decodeFromString<CachedDay>(prefs.getString(key("day"), null) ?: return null)
    }.getOrNull()
    fun readMarks(): DaysResponse? = runCatching {
        apiJson.decodeFromString<DaysResponse>(prefs.getString(key("marks"), null) ?: return null)
    }.getOrNull()
    fun writeDay(day: DayView) {
        val value = CachedDay(day, OffsetDateTime.now(ZoneOffset.ofHours(8)).toString())
        prefs.edit().putString(key("day"), apiJson.encodeToString(value)).apply()
    }
    fun writeMarks(days: List<DayMark>) {
        prefs.edit().putString(key("marks"), apiJson.encodeToString(DaysResponse(days))).apply()
    }
}
