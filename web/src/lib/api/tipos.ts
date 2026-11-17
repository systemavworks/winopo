// Tipos espejo de contracts/. Si cambia el contrato, cambia este archivo en el mismo commit.

export type Rol = 'preparador' | 'opositor' | 'admin'

export interface Sesion {
  usuarioId: string
  tenantId: string | null
  rol: Rol
}

export interface ErrorApi {
  error: string
  codigo?: string
}

export interface Supuesto {
  id: string
  titulo: string
  enunciado: string
  minutos: number
  puntosMaximosCents: number
}

export interface Opositor {
  id: string
  nombre: string
  correo: string
  activo: boolean
}
