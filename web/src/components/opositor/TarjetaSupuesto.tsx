import type { Supuesto } from '@/lib/api/tipos'

export function TarjetaSupuesto({ supuesto }: { supuesto: Supuesto }) {
  return (
    <li className="rounded-lg border border-slate-200 bg-white px-4 py-3">
      <div className="flex items-baseline justify-between gap-3">
        <p className="text-sm font-medium text-tinta">{supuesto.titulo}</p>
        <p className="shrink-0 text-xs text-slate-500">{supuesto.minutos} min</p>
      </div>
      <p className="mt-1 line-clamp-2 text-xs text-slate-600">{supuesto.enunciado}</p>
    </li>
  )
}
