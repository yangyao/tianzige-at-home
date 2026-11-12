package com.tianzige.tv.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

internal val apiJson = Json { ignoreUnknownKeys = true }

@Serializable
data class DayView(
    val date: String = "",
    @SerialName("is_today") val isToday: Boolean = false,
    @SerialName("days_ago") val daysAgo: Int = 0,
    val state: String = "empty",
    val note: String? = null,
    val images: List<ImageRef> = emptyList(),
    val subjects: List<SubjectGroup> = emptyList(),
    @SerialName("batch_ids") val batchIds: List<Long> = emptyList(),
)

@Serializable
data class ImageRef(val id: Long = 0, val url: String = "", val width: Int = 0, val height: Int = 0)

@Serializable
data class SubjectGroup(
    val subject: String = "",
    val items: List<HomeworkItem> = emptyList(),
    @SerialName("image_url") val imageUrl: String? = null,
)

@Serializable
data class HomeworkItem(val id: Long = 0, val content: String = "", val done: Boolean = false)

@Serializable
data class DayMark(
    val date: String,
    val has: Boolean = false,
    @SerialName("item_count") val itemCount: Int = 0,
)

@Serializable
data class DaysResponse(val days: List<DayMark> = emptyList())

@Serializable
data class HealthResponse(val ok: Boolean = false, val version: String? = null)

@Serializable
data class CachedDay(val day: DayView, val savedAt: String)
