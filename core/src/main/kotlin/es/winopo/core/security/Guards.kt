package es.winopo.core.security

/** Sin sesión válida. Se responde 401. */
class SinSesion : RuntimeException("sesión requerida")

/** Sesión válida pero sin el rol. Se responde 403. */
class SinPermiso(rolRequerido: String) : RuntimeException("requiere rol $rolRequerido")

/**
 * Regla: ninguna ruta de datos se registra sin pasar por aquí. Sin sesión no hay tenant,
 * y sin tenant la RLS devuelve cero filas: el fallo es cerrado, no abierto.
 */
fun SesionAutenticada?.exigir(vararg roles: String): SesionAutenticada {
    val sesion = this ?: throw SinSesion()
    if (roles.isNotEmpty() && sesion.rol !in roles) throw SinPermiso(roles.joinToString("/"))
    return sesion
}
