package es.winopo.core.routes

import es.winopo.core.config.Settings
import es.winopo.core.repo.UserRepo
import es.winopo.core.security.Passwords
import es.winopo.core.security.SessionService
import es.winopo.core.security.SesionAutenticada
import io.ktor.http.Cookie
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import kotlinx.serialization.Serializable

private const val COOKIE = "winopo_sesion"

@Serializable
data class PeticionLogin(val correo: String, val clave: String)

@Serializable
data class RespuestaSesion(val usuarioId: String, val tenantId: String?, val rol: String)

fun Route.authRoutes(ajustes: Settings, usuarios: UserRepo, sesiones: SessionService) {

    route("/v1/auth") {
        post("/login") {
            val peticion = call.receive<PeticionLogin>()
            val credenciales = usuarios.porCorreo(peticion.correo.trim())
                ?: return@post call.respond(HttpStatusCode.Unauthorized, ErrorApi("credenciales incorrectas", "credenciales"))

            if (!Passwords.verifica(peticion.clave, credenciales.hashClave)) {
                return@post call.respond(HttpStatusCode.Unauthorized, ErrorApi("credenciales incorrectas", "credenciales"))
            }

            val pertenencias = usuarios.pertenencias(credenciales.id)
            if (pertenencias.isEmpty()) {
                return@post call.respond(HttpStatusCode.Forbidden, ErrorApi("sin preparador asignado", "sin_pertenencia"))
            }
            if (pertenencias.size > 1) {
                // v1: un opositor pertenece a un solo preparador (D1). Si hay varias, se decide en el alta.
                return@post call.respond(HttpStatusCode.Conflict, ErrorApi("pertenece a varios preparadores", "varias_pertenencias"))
            }

            val pertenencia = pertenencias.single()
            val token = sesiones.crear(
                userId = credenciales.id,
                tenantId = pertenencia.tenantId,
                ip = call.request.local.remoteHost,
                userAgent = call.request.headers["User-Agent"],
            )

            call.response.cookies.append(
                Cookie(
                    name = COOKIE,
                    value = token,
                    httpOnly = true,
                    secure = ajustes.entorno != "local",
                    path = "/",
                    maxAge = (ajustes.duracionSesionHoras * 3600).toInt(),
                    extensions = mapOf("SameSite" to "Lax"),
                )
            )
            call.respond(RespuestaSesion(credenciales.id.toString(), pertenencia.tenantId.toString(), pertenencia.rol))
        }

        get("/sesion") {
            val sesion = call.sesionActual(sesiones)
                ?: return@get call.respond(HttpStatusCode.Unauthorized, ErrorApi("sin sesión", "sin_sesion"))
            call.respond(RespuestaSesion(sesion.usuarioId.toString(), sesion.tenantId?.toString(), sesion.rol))
        }

        post("/logout") {
            call.request.cookies[COOKIE]?.let(sesiones::revoca)
            call.response.cookies.append(Cookie(name = COOKIE, value = "", path = "/", maxAge = 0))
            call.respond(HttpStatusCode.NoContent)
        }
    }
}

internal fun ApplicationCall.sesionActual(sesiones: SessionService): SesionAutenticada? =
    request.cookies[COOKIE]?.let(sesiones::valida)

