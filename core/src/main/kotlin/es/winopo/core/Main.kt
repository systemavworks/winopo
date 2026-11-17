package es.winopo.core

import es.winopo.core.config.Perfil
import es.winopo.core.config.Settings
import es.winopo.core.jobs.WorkerLoop
import es.winopo.core.plugins.configurarPlugins
import es.winopo.core.routes.registrarRutas
import io.ktor.server.application.Application
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import kotlinx.coroutines.runBlocking

/**
 * Un binario, dos perfiles. WINOPO_PROFILE decide si arranca la API o el worker.
 * La misma imagen sirve para los dos contenedores.
 */
fun main() {
    val ajustes = Settings.desdeEntorno()
    when (ajustes.perfil) {
        Perfil.WORKER -> runBlocking { WorkerLoop(ajustes).arrancar() }
        Perfil.API -> embeddedServer(Netty, port = ajustes.puerto, host = "0.0.0.0") {
            modulo(ajustes)
        }.start(wait = true)
    }
}

fun Application.modulo(ajustes: Settings) {
    configurarPlugins(ajustes)
    registrarRutas(ajustes)
}
