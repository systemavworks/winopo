package es.winopo.core.config

enum class Perfil { API, WORKER }

/**
 * Configuración leída del entorno. Falla al arrancar si falta algo: un arranque a medias
 * que descubre la falta de una clave a la tercera petición es peor que no arrancar.
 */
data class Settings(
    val perfil: Perfil,
    val entorno: String,
    val puerto: Int,
    val databaseUrl: String,
    val secretoSesion: String,
    val duracionSesionHoras: Long,
) {
    companion object {
        fun desdeEntorno(env: Map<String, String> = System.getenv()): Settings {
            val perfil = when (val crudo = env["WINOPO_PROFILE"] ?: "api") {
                "api" -> Perfil.API
                "worker" -> Perfil.WORKER
                else -> error("WINOPO_PROFILE inválido: '$crudo' (api | worker)")
            }

            val databaseUrl = env["DATABASE_URL"]
                ?: error("Falta DATABASE_URL: sin base de datos no se arranca")

            val secreto = env["SESSION_SECRET"].orEmpty()
            require(secreto.length >= 32) { "SESSION_SECRET debe tener al menos 32 caracteres" }

            return Settings(
                perfil = perfil,
                entorno = env["APP_ENV"] ?: "local",
                puerto = (env["PORT"] ?: "8080").toIntOrNull()
                    ?: error("PORT no es un número"),
                databaseUrl = databaseUrl,
                secretoSesion = secreto,
                duracionSesionHoras = (env["SESSION_HOURS"] ?: "720").toLong(),
            )
        }
    }
}
