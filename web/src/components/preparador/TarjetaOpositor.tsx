import type { Opositor } from '@/lib/api/tipos'

export function TarjetaOpositor({ opositor }: { opositor: Opositor }) {
  return (
    <li className="flex items-center justify-between rounded-lg border border-slate-200 bg-white px-4 py-3">
      <div>
        <p className="text-sm font-medium text-tinta">{opositor.nombre}</p>
        <p className="text-xs text-slate-500">{opositor.correo}</p>
      </div>
      <span
        className={
          opositor.activo
            ? 'rounded-full bg-green-50 px-2 py-1 text-xs text-green-700'
            : 'rounded-full bg-slate-100 px-2 py-1 text-xs text-slate-500'
        }
      >
        {opositor.activo ? 'activo' : 'inactivo'}
      </span>
    </li>
  )
}
