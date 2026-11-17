'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'
import { Boton } from '@/components/ui/Boton'
import type { Rol } from '@/lib/api/tipos'

const destino: Record<Rol, string> = {
  preparador: '/preparador',
  opositor: '/opositor',
  admin: '/admin',
}

export default function Login() {
  const router = useRouter()
  const [correo, setCorreo] = useState('')
  const [clave, setClave] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  async function enviar(evento: React.FormEvent) {
    evento.preventDefault()
    setError(null)
    setEnviando(true)
    try {
      const respuesta = await fetch('/api/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ correo, clave }),
      })
      const datos = await respuesta.json()
      if (!respuesta.ok) {
        setError(datos.error ?? 'No se ha podido entrar')
        return
      }
      router.push(destino[datos.rol as Rol] ?? '/')
      router.refresh()
    } catch {
      setError('No hay conexión con el servidor')
    } finally {
      setEnviando(false)
    }
  }

  return (
    <div className="mx-auto max-w-sm">
      <h1 className="text-xl font-semibold text-tinta">Acceder</h1>
      <p className="mt-1 text-sm text-slate-600">Con la cuenta que te dio tu preparador.</p>

      <form onSubmit={enviar} className="mt-6 space-y-4">
        <label className="block text-sm">
          <span className="text-slate-700">Correo</span>
          <input
            type="email"
            required
            autoComplete="email"
            value={correo}
            onChange={(e) => setCorreo(e.target.value)}
            className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-acento focus:outline-none"
          />
        </label>
        <label className="block text-sm">
          <span className="text-slate-700">Contraseña</span>
          <input
            type="password"
            required
            autoComplete="current-password"
            value={clave}
            onChange={(e) => setClave(e.target.value)}
            className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-acento focus:outline-none"
          />
        </label>

        {error ? (
          <p role="alert" className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
            {error}
          </p>
        ) : null}

        <Boton tipo="submit" deshabilitado={enviando}>
          {enviando ? 'Entrando…' : 'Entrar'}
        </Boton>
      </form>
    </div>
  )
}
