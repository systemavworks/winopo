import { TarjetaOpositor } from '@/components/preparador/TarjetaOpositor'
import { Tarjeta } from '@/components/ui/Tarjeta'
import { exigirSesion } from '@/lib/api/sesion'
import type { Opositor } from '@/lib/api/tipos'

export const dynamic = 'force-dynamic'

export default async function PanelPreparador() {
  const sesion = await exigirSesion(['preparador', 'admin'])

  // F0: el endpoint de opositores llega en F1. Se pinta el estado vacío real, no datos de mentira.
  const opositores: Opositor[] = []

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-xl font-semibold text-tinta">Panel del preparador</h1>
        <p className="mt-1 text-sm text-slate-600">
          Cuenta {sesion.usuarioId.slice(0, 8)} · {opositores.length} opositores activos
        </p>
      </header>

      <Tarjeta titulo="Opositores" pie="Alta de opositores: F1">
        {opositores.length === 0 ? (
          <p>Todavía no hay opositores. Cuando los des de alta aparecerán aquí, con su progreso.</p>
        ) : (
          <ul className="space-y-2">
            {opositores.map((opositor) => (
              <TarjetaOpositor key={opositor.id} opositor={opositor} />
            ))}
          </ul>
        )}
      </Tarjeta>

      <div className="grid gap-4 sm:grid-cols-2">
        <Tarjeta titulo="Correcciones pendientes" pie="F3">
          Las entregas corregidas por la IA esperan tu validación. La nota no cuenta hasta que la firmas.
        </Tarjeta>
        <Tarjeta titulo="Temario" pie="F2">
          Sube el temario una vez y asígnalo. Cada opositor ve la versión que le toca.
        </Tarjeta>
      </div>
    </div>
  )
}
