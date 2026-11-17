import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { ErrorPeticion, peticion } from './cliente'
import type { Rol, Sesion } from './tipos'

/**
 * Sesión resuelta en el servidor. Next reenvía la cookie al core, que es el único que la valida.
 * Si no hay sesión, no se pinta la página: se redirige a /login. No hay "cargando" que oculte un fallo.
 */
export async function sesionActual(): Promise<Sesion | null> {
  const almacen = await cookies()
  const cookie = almacen.toString()
  if (!cookie.includes('winopo_sesion')) return null

  try {
    return await peticion<Sesion>('/v1/auth/sesion', { cookie })
  } catch (error) {
    if (error instanceof ErrorPeticion && error.estado === 401) return null
    throw error
  }
}

export async function exigirSesion(roles: Rol[]): Promise<Sesion> {
  const sesion = await sesionActual()
  if (!sesion) redirect('/login')
  if (!roles.includes(sesion.rol)) redirect(rutaDe(sesion.rol))
  return sesion
}

export function rutaDe(rol: Rol): string {
  return rol === 'preparador' ? '/preparador' : rol === 'admin' ? '/admin' : '/opositor'
}
