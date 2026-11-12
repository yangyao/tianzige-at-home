package com.tianzige.tv.domain

import kotlinx.serialization.SerializationException
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * 异常 → 给孩子家长看的一句中文。不拼技术词。
 * 文案原则见 DESIGN.md §9：主文案说结论，副文案给出路。
 */
object ErrorText {

    fun describe(t: Throwable): String = when (t) {
        is SocketTimeoutException -> "连接超时"
        is UnknownHostException -> "找不到这个地址"
        is ConnectException -> "连不上服务端"
        is SerializationException -> "返回的数据看不懂"
        is IllegalArgumentException -> "地址格式不对"
        is IOException -> "网络不通"
        else -> t.message?.takeIf { it.isNotBlank() } ?: "出错了"
    }
}
