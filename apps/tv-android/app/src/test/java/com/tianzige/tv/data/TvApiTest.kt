package com.tianzige.tv.data

import java.net.ServerSocket
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.net.InetSocketAddress
import java.time.LocalDate

class TvApiTest {
    private fun withServer(json: String, test: (String, () -> String) -> Unit) {
        val server = ServerSocket()
        server.bind(InetSocketAddress("127.0.0.1", 0))
        val requested = AtomicReference("")
        val worker = thread(isDaemon = true) {
            server.accept().use { socket ->
                socket.soTimeout = 5000
                val input = socket.getInputStream().bufferedReader()
                requested.set(input.readLine().split(" ")[1])
                while (!input.readLine().isNullOrEmpty()) { }
                val bytes = json.toByteArray(Charsets.UTF_8)
                val headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n"
                socket.getOutputStream().apply {
                    write(headers.toByteArray(Charsets.US_ASCII))
                    write(bytes)
                    flush()
                }
            }
        }
        try { test("http://127.0.0.1:${server.localPort}", { requested.get() }) }
        finally { server.close(); worker.join(5000) }
    }

    @Test fun readsRealServerFieldNamesAndNullableValues() {
        withServer("""
            {"date":"2026-11-12","is_today":true,"days_ago":0,"state":"ready","note":null,
             "images":[{"id":1,"url":"/img/2026-11-12/1.png","width":80,"height":40}],
             "subjects":[{"subject":"数学","image_url":null,"items":[{"id":2,"content":"练习册 P18","done":false,"done_at":null}]}],
             "batch_ids":[4],"future_field":"ignored"}
        """.trimIndent()) { base, path ->
            val day = runBlocking { TvApi().getDay(base, LocalDate.of(2026, 11, 12)) }
            assertEquals("/api/day?date=2026-11-12", path())
            assertTrue(day.isToday)
            assertNull(day.note)
            assertNull(day.subjects.first().imageUrl)
            assertEquals("练习册 P18", day.subjects.first().items.first().content)
            assertEquals(4L, day.batchIds.first())
        }
    }

    @Test fun daysRequestUsesTheServerRangeParameters() {
        withServer("""{"days":[{"date":"2026-11-12","has":true,"item_count":3}]}""") { base, path ->
            val days = runBlocking { TvApi().getDays(base, LocalDate.of(2026,11,9), LocalDate.of(2026,11,15)) }
            assertEquals("/api/days?from=2026-11-09&to=2026-11-15", path())
            assertTrue(days.single().has)
            assertEquals(3, days.single().itemCount)
        }
    }

    @Test fun unhealthyServerIsNotReportedAsConnected() {
        withServer("""{"ok":false,"db":"error"}""") { base, _ ->
            try {
                runBlocking { TvApi().health(base) }
                fail("Expected an unhealthy server to fail the connection test")
            } catch (_: IOException) { }
        }
    }
}
