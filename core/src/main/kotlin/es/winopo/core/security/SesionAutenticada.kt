package es.winopo.core.security

import java.util.UUID

/** Lo que una petición autenticada tiene derecho a saber de sí misma. */
data class SesionAutenticada(
    val usuarioId: UUID,
    val tenantId: UUID?,
    val rol: String,
    val tokenHash: String,
)
