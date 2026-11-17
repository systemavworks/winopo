import { TarjetaSupuesto } from '@/components/opositor/TarjetaSupuesto'
import { Tarjeta } from '@/components/ui/Tarjeta'
import { exigirSesion } from '@/lib/api/sesion'
import type { Supuesto } from '@/lib/api/tipos'

export const dynamic = 'force-dynamic'

export default async function PanelOpositor() {
  const sesion = await exigirSesion(['opositor'])

  // F0: sin endpoints todavía. Se muestra el estado vacío, sin inventar supuestos.
  const supuestos: Supuesto[] = []

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-xl font-semibold text-tinta">Mi preparación</h1>
        <p className="mt-1 text-sm text-slate-600">Sesión iniciada en el preparador {sesion.tenantId?.slice(0, 8)}</p>
      </header>

      <div className="grid gap-4 sm:grid-cols-2">
        <Tarjeta titulo="Tests pendientes" pie="Corrección inmediata">
          Aquí aparecerán los tests que te asigne tu preparador.
        </Tarjeta>
        <Tarjeta titulo="Mi progreso" pie="Por tema y por tipo de ejercicio">
          Cuando haya entregas, verás qué temas flojos repasar primero.
        </Tarjeta>
      </div>

      <Tarjeta titulo="Supuestos prácticos" pie="Corrección por rúbrica, revisada por tu preparador">
        {supuestos.length === 0 ? (
          <p>No tienes supuestos asignados todavía.</p>
        ) : (
          <ul className="space-y-2">
            {supuestos.map((supuesto) => (
              <TarjetaSupuesto key={supuesto.id} supuesto={supuesto} />
            ))}
          </ul>
        )}
      </Tarjeta>
    </div>
  )
}
