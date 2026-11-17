import { Boton } from '@/components/ui/Boton'
import { Tarjeta } from '@/components/ui/Tarjeta'

export default function Portada() {
  return (
    <div className="space-y-12">
      <section className="space-y-5">
        <p className="text-xs font-semibold uppercase tracking-wider text-acento">Oposiciones · corrección con rúbrica</p>
        <h1 className="max-w-2xl text-3xl font-semibold leading-tight text-tinta sm:text-4xl">
          Tu preparador corrige como siempre. WinOpo le quita el trabajo repetitivo.
        </h1>
        <p className="max-w-2xl text-base leading-relaxed text-slate-600">
          Temario, tests corregidos al instante y supuestos prácticos con rúbrica. La IA propone una corrección;
          tu preparador la revisa y firma. La nota final siempre la pone una persona.
        </p>
        <div className="flex flex-wrap gap-3">
          <Boton href="/login">Acceder</Boton>
          <Boton href="/login" variante="secundario">Soy preparador</Boton>
        </div>
      </section>

      <section className="grid gap-4 sm:grid-cols-3">
        <Tarjeta titulo="Tests" pie="Corrección inmediata, sin esperar al martes">
          Preguntas tipo test con explicación de cada fallo. El opositor ve qué estudiar hoy, no la nota dentro de una semana.
        </Tarjeta>
        <Tarjeta titulo="Supuestos" pie="Rúbrica por apartados y nota trazable">
          Corrección por apartados con justificación. Queda registrado qué modelo, qué versión del prompt y quién validó.
        </Tarjeta>
        <Tarjeta titulo="Temario" pie="Un PDF, un tema, una versión">
          Material del preparador, versionado. Se sabe qué temario estudió cada opositor y cuándo.
        </Tarjeta>
      </section>

      <section className="rounded-xl border border-slate-200 bg-white p-6">
        <h2 className="text-base font-semibold text-tinta">Sin promesas que no podamos cumplir</h2>
        <ul className="mt-3 space-y-2 text-sm text-slate-600">
          <li>· No aprobamos exámenes: preparamos.</li>
          <li>· No hay nota automática: hay propuesta de corrección y validación humana.</li>
          <li>· Tus datos no se venden ni se usan para entrenar modelos.</li>
        </ul>
      </section>
    </div>
  )
}
