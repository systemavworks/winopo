import { NextResponse } from 'next/server'

const BASE = process.env.WINOPO_API_URL ?? 'http://localhost:8080'

/**
 * El navegador nunca habla con el core: habla con Next, que reenvía y propaga la cookie httpOnly.
 * Así no hay CORS, no hay clave en el bundle y la cookie sigue siendo del dominio de la web.
 */
export async function POST(peticion: Request) {
  const cuerpo = await peticion.text()

  const respuesta = await fetch(`${BASE}/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: cuerpo,
    cache: 'no-store',
  })

  const datos = await respuesta.text()
  const saliente = new NextResponse(datos, {
    status: respuesta.status,
    headers: { 'Content-Type': 'application/json' },
  })

  for (const cookie of respuesta.headers.getSetCookie()) {
    saliente.headers.append('set-cookie', cookie)
  }

  return saliente
}
