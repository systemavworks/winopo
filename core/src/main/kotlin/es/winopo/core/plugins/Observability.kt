package es.winopo.core.plugins

import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.calllogging.CallLogging
import org.slf4j.event.Level

fun Application.configurarObservabilidad() {
    install(CallLogging) {
        level = Level.INFO
        filter { llamada -> !llamada.request.local.uri.startsWith("/healthz") }
    }
}
