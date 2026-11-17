package es.winopo.core.plugins

import es.winopo.core.config.Settings
import io.ktor.server.application.Application

fun Application.configurarPlugins(ajustes: Settings) {
    configurarObservabilidad()
    configurarSerializacion()
    configurarErrores()
}
