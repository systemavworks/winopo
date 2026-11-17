package es.winopo.core.db

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import es.winopo.core.config.Settings
import java.sql.Connection
import java.util.UUID

/**
 * Pool y transacciones con contexto de tenant.
 *
 * El contexto se fija con `set_config(..., true)` DENTRO de la transacción: al hacer commit o rollback
 * desaparece solo, así que una conexión devuelta al pool no arrastra el tenant de la petición anterior.
 * Ese es el fallo clásico de este patrón y aquí no ocurre.
 */
class Database(ajustes: Settings) : AutoCloseable {

    private val pool = HikariDataSource(
        HikariConfig().apply {
            jdbcUrl = UrlBaseDatos.normalizar(ajustes.databaseUrl)
            maximumPoolSize = 10
            minimumIdle = 2
            poolName = "winopo"
            connectionTimeout = 5_000
            transactionIsolation = "TRANSACTION_READ_COMMITTED"
        }
    )

    /** Valida una cookie: solo deja ver la sesión con ese hash. */
    fun <T> conSesion(tokenHash: String, bloque: (Connection) -> T): T =
        transaccion(mapOf("winopo.sesion_hash" to tokenHash), bloque)

    /** Tras verificar la contraseña: el usuario ve sus propias pertenencias, y nada más. */
    fun <T> conUsuario(userId: UUID, bloque: (Connection) -> T): T =
        transaccion(mapOf("winopo.user_id" to userId.toString()), bloque)

    /** Petición autenticada normal: el tenant manda. */
    fun <T> conTenant(tenantId: UUID, userId: UUID, bloque: (Connection) -> T): T =
        transaccion(
            mapOf("winopo.tenant_id" to tenantId.toString(), "winopo.user_id" to userId.toString()),
            bloque,
        )

    /** Sin contexto: tablas globales (login por correo). RLS deja 0 filas en todo lo demás. */
    fun <T> sinContexto(bloque: (Connection) -> T): T = transaccion(emptyMap(), bloque)

    private fun <T> transaccion(contexto: Map<String, String>, bloque: (Connection) -> T): T =
        pool.connection.use { conexion ->
            val autocommitOriginal = conexion.autoCommit
            conexion.autoCommit = false
            try {
                contexto.forEach { (clave, valor) ->
                    conexion.prepareStatement("select set_config(?, ?, true)").use { ps ->
                        ps.setString(1, clave)
                        ps.setString(2, valor)
                        ps.execute()
                    }
                }
                val resultado = bloque(conexion)
                conexion.commit()
                resultado
            } catch (e: Throwable) {
                conexion.rollback()
                throw e
            } finally {
                conexion.autoCommit = autocommitOriginal
            }
        }

    override fun close() = pool.close()
}

/**
 * El driver JDBC no acepta `postgresql://usuario:clave@host/bd`: quiere `jdbc:postgresql://host/bd?user=...`.
 * En los compose se escribe la forma corta (la que entiende todo el mundo) y aquí se traduce.
 */
object UrlBaseDatos {
    fun normalizar(crudo: String): String {
        if (crudo.startsWith("jdbc:")) return crudo
        if (!crudo.startsWith("postgresql://") && !crudo.startsWith("postgres://")) return crudo

        val uri = runCatching { java.net.URI(crudo) }.getOrNull() ?: return crudo
        val consulta = mutableListOf<String>()
        uri.rawQuery?.takeIf { it.isNotBlank() }?.let { consulta += it }

        val credenciales = uri.rawUserInfo?.split(':', limit = 2) ?: emptyList()
        if (credenciales.size == 2) {
            consulta += "user=" + java.net.URLEncoder.encode(decode(credenciales[0]), "UTF-8")
            consulta += "password=" + java.net.URLEncoder.encode(decode(credenciales[1]), "UTF-8")
        }

        val base = buildString {
            append("jdbc:postgresql://")
            append(uri.host ?: "localhost")
            if (uri.port > 0) append(':').append(uri.port)
            append(uri.path?.takeIf { it.isNotBlank() } ?: "/")
        }
        return if (consulta.isEmpty()) base else "$base?" + consulta.joinToString("&")
    }

    private fun decode(texto: String): String = java.net.URLDecoder.decode(texto, "UTF-8")
}
