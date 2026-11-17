package es.winopo.core.jobs

import es.winopo.core.config.Settings
import kotlinx.coroutines.delay
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("es.winopo.core.worker")

/**
 * Bucle del worker. Reclama trabajos con `FOR UPDATE SKIP LOCKED` para que dos workers no
 * se lleven el mismo. En F0 no hay tabla `job` todavía (llega en 0009): el bucle late y no finge trabajo.
 */
class WorkerLoop(private val ajustes: Settings) {

    suspend fun arrancar() {
        log.info("worker arrancado (entorno={})", ajustes.entorno)
        Runtime.getRuntime().addShutdownHook(Thread { log.info("worker detenido") })

        while (true) {
            val trabajo = JobQueue(ajustes).reclamarSiguiente()
            if (trabajo == null) delay(2_000) else ejecutar(trabajo)
        }
    }

    private fun ejecutar(trabajo: Trabajo) {
        log.info("trabajo {} de tipo {}: handler pendiente de su fase", trabajo.id, trabajo.tipo)
    }
}
