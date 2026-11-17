import { NextResponse } from 'next/server'

const BASE = process.env.WINOPO_API_URL ?? 'http://localhost:8080'

export async function POST() {
  await fetch(`${BASE}/v1/auth/logout`, { method: 'POST', cache: 'no-store' })
  const saliente = NextResponse.json({ ok: true })
  saliente.cookies.set('winopo_sesion', '', { path: '/', maxAge: 0 })
  return saliente
}
