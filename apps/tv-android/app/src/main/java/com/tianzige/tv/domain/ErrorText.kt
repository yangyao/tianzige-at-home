package com.tianzige.tv.domain

import kotlinx.serialization.SerializationException
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * 异常 → 一个语义化的错误种类。文案在 UI 层按当前语言查 R.string，
 * 这样 domain / ViewModel 里不会再出现面向用户的字符串。
 * 文案原则见 DESIGN.md §9：主文案说结论，副文案给出路。
 */
enum class ErrorKind { TIMEOUT, HOST_NOT_FOUND, CONNECT_FAILED, BAD_DATA, BAD_ADDRESS, NETWORK, UNKNOWN }

object ErrorText {

    fun kindOf(t: Throwable): ErrorKind = when (t) {
        is SocketTimeoutException -> ErrorKind.TIMEOUT
        is UnknownHostException -> ErrorKind.HOST_NOT_FOUND
        is ConnectException -> ErrorKind.CONNECT_FAILED
        is SerializationException -> ErrorKind.BAD_DATA
        is IllegalArgumentException -> ErrorKind.BAD_ADDRESS
        is IOException -> ErrorKind.NETWORK
        else -> ErrorKind.UNKNOWN
    }
}

/** 设置屏的提示条。同样只携带语义和参数，具体文案由 UI 翻译。 */
sealed interface SettingsNotice {
    /** 首次启动连不上，自动弹出的那句「检查地址」。 */
    data object Unreachable : SettingsNotice
    data object BadAddress : SettingsNotice
    data object Testing : SettingsNotice
    data class Connected(val version: String?) : SettingsNotice
    data class Failed(val kind: ErrorKind) : SettingsNotice
}
