import type { ReactNode } from 'react'

export function Tarjeta({
  titulo,
  children,
  pie,
}: {
  titulo: string
  children: ReactNode
  pie?: ReactNode
}) {
  return (
    <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
      <h2 className="text-base font-semibold text-tinta">{titulo}</h2>
      <div className="mt-3 text-sm leading-relaxed text-slate-600">{children}</div>
      {pie ? <div className="mt-4 border-t border-slate-100 pt-3 text-xs text-slate-500">{pie}</div> : null}
    </section>
  )
}
