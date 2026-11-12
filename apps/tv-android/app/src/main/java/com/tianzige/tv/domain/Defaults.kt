package com.tianzige.tv.domain

/** 服务端默认地址（docs/05-协议.md §8）。 */
const val DEFAULT_SERVER_URL = "http://nas.local:8080"

/** 日期条允许回看 / 前看的天数，避免遥控器一路按到 2029 年。 */
const val MAX_DAYS_BACK = 56
const val MAX_DAYS_FORWARD = 6
