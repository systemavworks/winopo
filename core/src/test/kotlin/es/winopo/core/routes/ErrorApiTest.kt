package es.winopo.core.routes

import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals

class ErrorApiTest {

    @Test
    fun `el error respeta el contrato error schema json`() {
        val json = Json { explicitNulls = false }
        assertEquals("""{"error":"no encontrado","codigo":"no_encontrado"}""", json.encodeToString(ErrorApi.serializer(), ErrorApi("no encontrado", "no_encontrado")))
    }

    @Test
    fun `sin codigo el campo desaparece, no se envia null`() {
        val json = Json { explicitNulls = false }
        assertEquals("""{"error":"error interno"}""", json.encodeToString(ErrorApi.serializer(), ErrorApi("error interno")))
    }
}
