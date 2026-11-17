package es.winopo.core.routes

import es.winopo.core.config.Settings
import es.winopo.core.db.Database
import es.winopo.core.repo.UserRepo
import es.winopo.core.security.SessionService
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationStopped
import io.ktor.server.routing.routing

/**
 * Punto único de registro. En F0 solo salud y autenticación; el resto de rutas se añaden con su fase
 * y con su prueba de aislamiento de tenant.
 */
fun Application.registrarRutas(ajustes: Settings) {
    val db = Database(ajustes)
    monitor.subscribe(ApplicationStopped) { db.close() }

    val usuarios = UserRepo(db)
    val sesiones = SessionService(db, ajustes.duracionSesionHoras)

    routing {
        healthRoutes()
        authRoutes(ajustes, usuarios, sesiones)
    }
}
