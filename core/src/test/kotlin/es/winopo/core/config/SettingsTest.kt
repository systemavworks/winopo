package es.winopo.core.config

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class SettingsTest {

    private val minimo = mapOf(
        "DATABASE_URL" to "jdbc:postgresql://localhost:5432/winopo",
        "SESSION_SECRET" to "x".repeat(32),
    )

    @Test
    fun `sin DATABASE_URL no arranca`() {
        val error = assertFailsWith<IllegalStateException> { Settings.desdeEntorno(minimo - "DATABASE_URL") }
        assertEquals("Falta DATABASE_URL: sin base de datos no se arranca", error.message)
    }

    @Test
    fun `un secreto corto no arranca`() {
        assertFailsWith<IllegalArgumentException> {
            Settings.desdeEntorno(minimo + ("SESSION_SECRET" to "corto"))
        }
    }

    @Test
    fun `un perfil desconocido no arranca`() {
        assertFailsWith<IllegalStateException> {
            Settings.desdeEntorno(minimo + ("WINOPO_PROFILE" to "cron"))
        }
    }

    @Test
    fun `por defecto es api, local y 720 horas de sesion`() {
        val ajustes = Settings.desdeEntorno(minimo)
        assertEquals(Perfil.API, ajustes.perfil)
        assertEquals("local", ajustes.entorno)
        assertEquals(8080, ajustes.puerto)
        assertEquals(720L, ajustes.duracionSesionHoras)
    }

    @Test
    fun `un PORT que no es numero no arranca`() {
        assertFailsWith<IllegalStateException> { Settings.desdeEntorno(minimo + ("PORT" to "ocho")) }
    }
}
