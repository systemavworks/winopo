package es.winopo.core.security

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class GuardsTest {

    private fun sesion(rol: String) =
        SesionAutenticada(UUID.randomUUID(), UUID.randomUUID(), rol, "hash")

    @Test
    fun `sin sesion no se pasa`() {
        assertFailsWith<SinSesion> { (null as SesionAutenticada?).exigir("preparador") }
    }

    @Test
    fun `con rol distinto no se pasa`() {
        val error = assertFailsWith<SinPermiso> { sesion("opositor").exigir("preparador")
        }
        assertEquals("requiere rol preparador", error.message)
    }

    @Test
    fun `con el rol exigido se pasa`() {
        val original = sesion("preparador")
        assertEquals(original, original.exigir("preparador", "admin"))
    }

    @Test
    fun `sin roles exigidos basta con tener sesion`() {
        val original = sesion("opositor")
        assertEquals(original, original.exigir())
    }
}
