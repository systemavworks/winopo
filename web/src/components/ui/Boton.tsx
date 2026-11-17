import Link from 'next/link'
import type { ReactNode } from 'react'

const base =
  'inline-flex items-center justify-center rounded-lg px-4 py-2 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-acento disabled:opacity-50'

const variantes = {
  principal: 'bg-acento text-white hover:bg-blue-700',
  secundario: 'border border-slate-300 bg-white text-tinta hover:border-acento hover:text-acento',
} as const

export function Boton({
  children,
  variante = 'principal',
  tipo = 'button',
  deshabilitado = false,
  href,
}: {
  children: ReactNode
  variante?: keyof typeof variantes
  tipo?: 'button' | 'submit'
  deshabilitado?: boolean
  href?: string
}) {
  const clases = `${base} ${variantes[variante]}`
  if (href) return <Link href={href} className={clases}>{children}</Link>
  return (
    <button type={tipo} disabled={deshabilitado} className={clases}>
      {children}
    </button>
  )
}
