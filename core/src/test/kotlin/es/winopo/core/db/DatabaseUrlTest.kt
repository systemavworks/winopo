package es.winopo.core.db

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * `DATABASE_URL` se escribe en los compose como URL corta (la que entiende cualquiera) y el driver JDBC
 * quiere otra forma. Si esto se rompe, el core no arranca y el error que sale no dice por qué.
 */
class DatabaseUrlTest {

    @Test
    fun `una url jdbc se deja como esta`() {
        val url = "jdbc:postgresql://db:5432/winopo?user=winopo&password=cambiame"
        assertEquals(url, UrlBaseDatos.normalizar(url))
    }

    @Test
    fun `la forma corta se convierte en jdbc con credenciales en la consulta`() {
        assertEquals(
            "jdbc:postgresql://db:5432/winopo?user=winopo&password=cambiame",
            UrlBaseDatos.normalizar("postgresql://winopo:cambiame@db:5432/winopo"),
        )
    }

    @Test
    fun `postgres como esquema tambien se traduce`() {
        assertEquals(
            "jdbc:postgresql://localhost:5432/winopo?user=u&password=p",
            UrlBaseDatos.normalizar("postgres://u:p@localhost:5432/winopo"),
        )
    }

    @Test
    fun `sin puerto no se inventa uno y se conserva el valor por defecto del driver`() {
        assertEquals(
            "jdbc:postgresql://localhost/winopo?user=u&password=p",
            UrlBaseDatos.normalizar("postgresql://u:p@localhost/winopo"),
        )
    }

    @Test
    fun `las credenciales con caracteres reservados se escapan`() {
        val traducida = UrlBaseDatos.normalizar("postgresql://winopo:p%40s%3Aw0rd@db:5432/winopo")
        assertEquals(
            "jdbc:postgresql://db:5432/winopo?user=winopo&password=p%40s%3Aw0rd",
            traducida,
        )
    }

    @Test
    fun `una url con parametros propios conserva los parametros y anade credenciales`() {
        assertEquals(
            "jdbc:postgresql://db:5432/winopo?sslmode=require&user=u&password=p",
            UrlBaseDatos.normalizar("postgresql://u:p@db:5432/winopo?sslmode=require"),
        )
    }

    @Test
    fun `sin usuario ni clave no se anade consulta vacia`() {
        assertEquals(
            "jdbc:postgresql://db:5432/winopo",
            UrlBaseDatos.normalizar("postgresql://db:5432/winopo"),
        )
    }

    @Test
    fun `algo que no es una url de base de datos no se toca`() {
        assertEquals("", UrlBaseDatos.normalizar(""))
        assertEquals("no-es-una-url", UrlBaseDatos.normalizar("no-es-una-url"))
    }
}
