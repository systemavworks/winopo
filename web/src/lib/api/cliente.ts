import type { ErrorApi } from './tipos'

const BASE = process.env.WINOPO_API_URL ?? 'http://localhost:8080'

export class ErrorPeticion extends Error {
  constructor(mensaje: string, readonly estado: number, readonly codigo?: string) {
    super(mensaje)
    this.name = 'ErrorPeticion'
  }
}

/**
 * Cliente único. En el servidor reenvía la cookie de sesión; en el navegador usa `credentials: 'include'`.
 * No hay token en localStorage: la sesión es una cookie httpOnly y JavaScript no la ve.
 */
export async function peticion<T>(
  ruta: string,
  opciones: RequestInit & { cookie?: string } = {},
): Promise<T> {
  const { cookie, headers, ...resto } = opciones
  const respuesta = await fetch(`${BASE}${ruta}`, {
    ...resto,
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
      ...(cookie ? { cookie } : {}),
      ...headers,
    },
    cache: 'no-store',
  })

  if (respuesta.status === 204) return undefined as T

  if (!respuesta.ok) {
    const cuerpo = (await respuesta.json().catch(() => ({ error: respuesta.statusText }))) as ErrorApi
    throw new ErrorPeticion(cuerpo.error, respuesta.status, cuerpo.codigo)
  }

  return (await respuesta.json()) as T
}
