package es.winopo.core.domain

/** Importes en céntimos, enteros. Nunca coma flotante. */
@JvmInline
value class Centimos(val valor: Long) {
    init {
        require(valor >= 0) { "Un importe no puede ser negativo: $valor" }
    }

    operator fun plus(otro: Centimos) = Centimos(valor + otro.valor)
    operator fun minus(otro: Centimos) = Centimos(valor - otro.valor)

    /** Porcentaje con redondeo al céntimo. */
    fun porcentaje(pct: Int): Centimos = Centimos((valor * pct + 50) / 100)

    override fun toString(): String = "%.2f €".format(valor / 100.0)
}
