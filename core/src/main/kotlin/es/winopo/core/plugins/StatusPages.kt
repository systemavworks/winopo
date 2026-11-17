package es.winopo.core.plugins

import es.winopo.core.routes.ErrorApi
import es.winopo.core.security.SinPermiso
import es.winopo.core.security.SinSesion
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.BadRequestException
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.response.respond
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("es.winopo.core.errores")

/**
 * Una sola forma de error para toda la API. El 404 cross-tenant es indistinguible de un 404 real:
 * no se filtra la existencia de recursos de otro preparador.
 */
fun Application.configurarErrores() {
    install(StatusPages) {
        exception<BadRequestException> { call, causa ->
            call.respond(HttpStatusCode.BadRequest, ErrorApi(causa.message ?: "petición inválida", "peticion_invalida"))
        }
        exception<SinSesion> { call, _ ->
            call.respond(HttpStatusCode.Unauthorized, ErrorApi("sesión requerida", "sin_sesion"))
        }
        exception<SinPermiso> { call, causa ->
            call.respond(HttpStatusCode.Forbidden, ErrorApi(causa.message ?: "sin permiso", "sin_permiso"))
        }
        exception<Throwable> { call, causa ->
            log.error("error no controlado", causa)
            call.respond(HttpStatusCode.InternalServerError, ErrorApi("error interno", "error_interno"))
        }
        status(HttpStatusCode.NotFound) { call, estado ->
            call.respond(estado, ErrorApi("no encontrado", "no_encontrado"))
        }
    }
}
