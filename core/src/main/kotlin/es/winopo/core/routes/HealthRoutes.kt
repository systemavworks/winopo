package es.winopo.core.routes

import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import kotlinx.serialization.Serializable

@Serializable
data class EstadoServicio(val estado: String, val servicio: String)

fun Route.healthRoutes() {
    get("/healthz") {
        call.respond(EstadoServicio(estado = "ok", servicio = "winopo"))
    }
}
