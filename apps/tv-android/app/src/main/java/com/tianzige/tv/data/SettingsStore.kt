package com.tianzige.tv.data

import android.content.Context
import com.tianzige.tv.domain.DEFAULT_SERVER_URL
import com.tianzige.tv.domain.DayLogic

class SettingsStore(context: Context) {
    private val prefs = context.getSharedPreferences("tianzige-settings", Context.MODE_PRIVATE)
    fun serverUrl(): String = prefs.getString("server-url", null) ?: DEFAULT_SERVER_URL
    fun saveServerUrl(url: String) {
        prefs.edit().putString("server-url", DayLogic.normalizeServerUrl(url)).apply()
    }
}
