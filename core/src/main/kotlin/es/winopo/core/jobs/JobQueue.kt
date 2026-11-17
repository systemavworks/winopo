package es.winopo.core.jobs

import es.winopo.core.config.Settings

internal data class Trabajo(val id: Long, val tipo: String)

/**
 * Cola en PostgreSQL. Sin Redis ni colas gestionadas en v0.
 *
 * `select ... for update skip locked limit 1` es lo que impide que dos workers procesen el mismo job.
 * Se implementa cuando exista la tabla `job` (migrations/0009_job.sql, F3).
 */
internal class JobQueue(@Suppress("UNUSED_PARAMETER") private val ajustes: Settings) {
    suspend fun reclamarSiguiente(): Trabajo? = null
}
