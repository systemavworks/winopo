package es.winopo.core.ia

/**
 * Interfaz propia sobre el proveedor de IA: UNA operación. Cambiar de proveedor es una clase nueva
 * en `ia/proveedor/`, no un cambio en el dominio.
 *
 * Reglas (docs/alcance-v0.md §5): la IA propone, el humano decide; ninguna clave de test pasa por aquí;
 * toda corrección guarda modelo y prompt_version.
 */
interface CorrectorIA {
    fun corregir(peticion: PeticionCorreccion): PropuestaCorreccion
}

data class PeticionCorreccion(
    val entregaTexto: String,
    val enunciado: String,
    val rubrica: List<ItemRubrica>,
    val promptVersion: String,
    val modelo: String,
)

data class ItemRubrica(
    val codigo: String,
    val descripcion: String,
    val puntosMaximosCents: Long,
)

/** Lo que devuelve el modelo: puntos por apartado. Nunca una nota final. */
data class PropuestaCorreccion(
    val items: List<ItemCorregido>,
    val observaciones: String,
    val modelo: String,
    val promptVersion: String,
    val costeCents: Long,
) {
    init {
        require(items.isNotEmpty()) { "Una corrección sin apartados no es una corrección" }
    }
}

data class ItemCorregido(
    val codigo: String,
    val puntosCents: Long,
    val justificacion: String,
)

/** Quién cierra la corrección. Sin este dato, la corrección no cuenta para nota. */
enum class CorregidoPor { IA, PREPARADOR, VALIDADO }
