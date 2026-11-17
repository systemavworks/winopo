package es.winopo.core.security

import es.winopo.core.db.Database
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.OffsetDateTime
import java.util.Base64
import java.util.UUID

/**
 * Sesiones de servidor. En la base solo vive el SHA-256 del token; el token en claro solo está en la cookie.
 * El rol se resuelve contra `membership`, nunca se guarda en la cookie: si se revoca el acceso, deja de valer.
 */
class SessionService(private val db: Database, private val horas: Long) {

    private val aleatorio = SecureRandom()

    fun crear(userId: UUID, tenantId: UUID?, ip: String?, userAgent: String?): String {
        val token = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(ByteArray(32).also(aleatorio::nextBytes))
        val hash = hashDe(token)
        db.conUsuario(userId) { c ->
            c.prepareStatement(
                "insert into sesion (token_hash, user_id, tenant_id, ip, user_agent, expira_en) " +
                    "values (?, ?, ?, ?::inet, ?, ?)"
            ).use { ps ->
                ps.setString(1, hash)
                ps.setObject(2, userId)
                ps.setObject(3, tenantId)
                ps.setString(4, ip)
                ps.setString(5, userAgent)
                ps.setObject(6, OffsetDateTime.now().plusHours(horas))
                ps.executeUpdate()
            }
        }
        return token
    }

    fun valida(token: String): SesionAutenticada? {
        val hash = hashDe(token)

        val base = db.conSesion(hash) { c ->
            c.prepareStatement(
                "select user_id, tenant_id from sesion where token_hash = ? and expira_en > now()"
            ).use { ps ->
                ps.setString(1, hash)
                ps.executeQuery().use { rs ->
                    if (rs.next()) rs.getObject(1, UUID::class.java) to rs.getObject(2, UUID::class.java)
                    else null
                }
            }
        } ?: return null

        val (usuarioId, tenantId) = base
        val rol = db.conUsuario(usuarioId) { c ->
            c.prepareStatement(
                "select rol from membership where user_id = ? and tenant_id = ? and estado = 'activo'"
            ).use { ps ->
                ps.setObject(1, usuarioId)
                ps.setObject(2, tenantId)
                ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else null }
            }
        } ?: return null

        return SesionAutenticada(usuarioId, tenantId, rol, hash)
    }

    fun revoca(token: String) {
        val hash = hashDe(token)
        db.conSesion(hash) { c ->
            c.prepareStatement("delete from sesion where token_hash = ?").use { ps ->
                ps.setString(1, hash)
                ps.executeUpdate()
            }
        }
    }

    private fun hashDe(token: String): String =
        MessageDigest.getInstance("SHA-256").digest(token.toByteArray())
            .joinToString("") { "%02x".format(it) }
}
