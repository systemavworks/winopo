package es.winopo.core.security

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * PBKDF2-HMAC-SHA256 con sal por usuario.
 *
 * Se elige PBKDF2 y no Argon2id en v0 porque es del JDK: no añade librería nativa y funciona en la imagen
 * Alpine sin sorpresas. Si más adelante se añade Argon2id, el formato guardado permite convivir con ambos
 * (`pbkdf2$...` frente a `argon2id$...`) y migrar al iniciar sesión.
 */
object Passwords {

    private const val ITERACIONES = 210_000
    private const val BYTES_SAL = 16
    private const val BYTES_CLAVE = 32
    private val aleatorio = SecureRandom()
    private val b64 = Base64.getEncoder().withoutPadding()
    private val b64d = Base64.getDecoder()

    fun hash(clave: String): String {
        val sal = ByteArray(BYTES_SAL).also(aleatorio::nextBytes)
        val derivada = derivar(clave, sal, ITERACIONES)
        return "pbkdf2\$$ITERACIONES\$${b64.encodeToString(sal)}\$${b64.encodeToString(derivada)}"
    }

    fun verifica(clave: String, guardado: String): Boolean {
        val partes = guardado.split('$')
        if (partes.size != 4 || partes[0] != "pbkdf2") return false
        val iteraciones = partes[1].toIntOrNull() ?: return false
        val sal = runCatching { b64d.decode(partes[2]) }.getOrNull() ?: return false
        val esperado = runCatching { b64d.decode(partes[3]) }.getOrNull() ?: return false
        val calculado = derivar(clave, sal, iteraciones)
        return MessageDigest.isEqual(esperado, calculado)
    }

    private fun derivar(clave: String, sal: ByteArray, iteraciones: Int): ByteArray {
        val spec = PBEKeySpec(clave.toCharArray(), sal, iteraciones, BYTES_CLAVE * 8)
        return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
    }
}
