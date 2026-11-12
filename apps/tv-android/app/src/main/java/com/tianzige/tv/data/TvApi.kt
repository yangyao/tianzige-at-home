package com.tianzige.tv.data

import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.decodeFromString
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.time.LocalDate
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class TvApi {
    private val client = OkHttpClient.Builder()
        .connectTimeout(6, TimeUnit.SECONDS)
        .callTimeout(15, TimeUnit.SECONDS)
        .build()

    suspend fun getDay(base: String, date: LocalDate): DayView =
        apiJson.decodeFromString(get(base, "api/day", mapOf("date" to date.toString())))

    suspend fun getDays(base: String, from: LocalDate, to: LocalDate): List<DayMark> =
        apiJson.decodeFromString<DaysResponse>(
            get(base, "api/days", mapOf("from" to from.toString(), "to" to to.toString()))
        ).days

    suspend fun health(base: String): HealthResponse {
        val result = apiJson.decodeFromString<HealthResponse>(get(base, "api/health"))
        if (!result.ok) throw IOException("家里的服务暂时不可用")
        return result
    }

    private suspend fun get(base: String, path: String, query: Map<String, String> = emptyMap()): String {
        val url = base.trimEnd('/').toHttpUrl().newBuilder().addPathSegments(path)
        query.forEach { (key, value) -> url.addQueryParameter(key, value) }
        val call = client.newCall(Request.Builder().url(url.build()).build())
        return suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(e)
                }
                override fun onResponse(call: Call, response: Response) {
                    try {
                        val text = response.use {
                            if (!it.isSuccessful) throw IOException("家里的服务暂时不可用（${it.code}）")
                            it.body?.string() ?: throw IOException("家里的服务没有返回内容")
                        }
                        if (continuation.isActive) continuation.resume(text)
                    } catch (e: Exception) {
                        if (continuation.isActive) continuation.resumeWithException(e)
                    }
                }
            })
        }
    }
}
