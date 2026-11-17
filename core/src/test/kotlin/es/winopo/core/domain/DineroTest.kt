package es.winopo.core.domain

import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class DineroTest {

    @Test
    fun `suma y resta en centimos exactos`() {
        assertEquals(Centimos(300), Centimos(100) + Centimos(200))
        assertEquals(Centimos(100), Centimos(300) - Centimos(200))
    }

    @Test
    fun `no admite importes negativos`() {
        assertFailsWith<IllegalArgumentException> { Centimos(-1) }
    }

    /** Deliberado: restar de más es un error de programación, no un saldo negativo silencioso. */
    @Test
    fun `restar de mas falla en vez de devolver un negativo`() {
        assertFailsWith<IllegalArgumentException> { Centimos(100) - Centimos(200) }
    }

    @Test
    fun `porcentaje redondea al centimo`() {
        assertEquals(Centimos(210), Centimos(1000).porcentaje(21), "21 % de 10,00 EUR son 2,10 EUR")
        assertEquals(Centimos(1), Centimos(5).porcentaje(21), "0,0105 EUR redondea a 0,01 EUR")
        assertEquals(Centimos(0), Centimos(2).porcentaje(21), "0,0042 EUR redondea a 0,00 EUR")
        assertEquals(Centimos(4), Centimos(21).porcentaje(21), "0,0441 EUR redondea a 0,04 EUR")
    }

    @Test
    fun `se muestra con dos decimales en el locale del usuario`() {
        val esperado = String.format(Locale.getDefault(), "%.2f \u20ac", 29.90)
        assertEquals(esperado, Centimos(2990).toString())
    }
}
