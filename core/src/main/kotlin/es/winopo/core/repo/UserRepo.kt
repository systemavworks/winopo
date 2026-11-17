package es.winopo.core.repo

import es.winopo.core.db.Database
import java.util.UUID

/** SQL a mano. Sin ORM: lo que se ejecuta es lo que se lee aquí. */
class UserRepo(private val db: Database) {

    data class Credenciales(val id: UUID, val nombre: String, val hashClave: String)
    data class Pertenencia(val membershipId: UUID, val tenantId: UUID, val rol: String)

    /** Sin contexto de tenant: solo busca por correo en la tabla global. */
    fun porCorreo(correo: String): Credenciales? = db.sinContexto { c ->
        c.prepareStatement("select id, nombre, hash_clave from app_user where correo = ? and anonimizado_en is null")
            .use { ps ->
                ps.setString(1, correo)
                ps.executeQuery().use { rs ->
                    if (rs.next()) Credenciales(rs.getObject(1, UUID::class.java), rs.getString(2), rs.getString(3))
                    else null
                }
            }
    }

    /** Con `winopo.user_id` fijado, la política deja ver solo sus pertenencias. */
    fun pertenencias(userId: UUID): List<Pertenencia> = db.conUsuario(userId) { c ->
        c.prepareStatement(
            "select id, tenant_id, rol from membership where user_id = ? and estado = 'activo' order by creado_en"
        ).use { ps ->
            ps.setObject(1, userId)
            ps.executeQuery().use { rs ->
                buildList {
                    while (rs.next()) {
                        add(Pertenencia(rs.getObject(1, UUID::class.java), rs.getObject(2, UUID::class.java), rs.getString(3)))
                    }
                }
            }
        }
    }
}
