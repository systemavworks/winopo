package es.winopo.core.security

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class PasswordsTest {

    @Test
    fun `una clave correcta verifica`() {
        val guardado = Passwords.hash("correcta-horse-battery")
        assertTrue(Passwords.verifica("correcta-horse-battery", guardado))
    }

    @Test
    fun `una clave incorrecta no verifica`() {
        val guardado = Passwords.hash("correcta-horse-battery")
        assertFalse(Passwords.verifica("correcta-horse-batterY", guardado))
    }

    @Test
    fun `la misma clave produce hashes distintos`() {
        assertNotEquals(Passwords.hash("misma"), Passwords.hash("misma"))
    }

    @Test
    fun `el formato guardado lleva algoritmo, iteraciones y sal`() {
        val partes = Passwords.hash("x").split('$')
        assertTrue(partes.size == 4 && partes[0] == "pbkdf2", "formato inesperado: $partes")
        assertTrue(partes[1].toInt() >= 100_000, "pocas iteraciones: ${partes[1]}")
    }

    @Test
    fun `un hash corrupto no lanza excepcion`() {
        assertFalse(Passwords.verifica("x", "basura"))
        assertFalse(Passwords.verifica("x", "pbkdf2" + '$' + "no-numero" + '$' + "aa" + '$' + "bb"))
        assertFalse(Passwords.verifica("x", ""))
    }
}
