package es.winopo.core.routes

import kotlinx.serialization.Serializable

/** Contrato: contracts/api/error.schema.json */
@Serializable
data class ErrorApi(
    val error: String,
    val codigo: String? = null,
)
