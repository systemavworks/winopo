import { Tarjeta } from '@/components/ui/Tarjeta'
import { exigirSesion } from '@/lib/api/sesion'

export const dynamic = 'force-dynamic'

export default async function PanelAdmin() {
  const sesion = await exigirSesion(['admin'])

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-xl font-semibold text-tinta">Administración de Winopo</h1>
        <p className="mt-1 text-sm text-slate-600">Sesión {sesion.usuarioId.slice(0, 8)}</p>
      </header>

      <div className="grid gap-4 sm:grid-cols-2">
        <Tarjeta titulo="Preparadores" pie="F1">Alta, suspensión y facturación de cada preparador.</Tarjeta>
        <Tarjeta titulo="Consumo de IA" pie="F3">Coste por corrección y por preparador, para no regalar margen.</Tarjeta>
      </div>
    </div>
  )
}
