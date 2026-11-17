import { Boton } from '@/components/ui/Boton'
import { Tarjeta } from '@/components/ui/Tarjeta'

export default function Portada() {
  return (
    <div className="space-y-12">
      <section className="space-y-5">
        <p className="text-xs font-semibold uppercase tracking-wider text-acento">Oposiciones · opositor y preparador</p>
        <h1 className="max-w-2xl text-3xl font-semibold leading-tight text-tinta sm:text-4xl">
          Estudiar una oposición no debería depender de cómo esté maquetado tu temario.
        </h1>
        <p className="max-w-2xl text-base leading-relaxed text-slate-600">
          Temario y apuntes maquetados, tests corregidos al instante, supuestos con rúbrica y tribunal simulado.
          Con preparador o por tu cuenta: la IA propone la corrección, una persona la valida y la nota final nunca
          la pone un modelo.
        </p>
        <div className="flex flex-wrap gap-3">
          <Boton href="/login">Acceder</Boton>
          <Boton href="/login" variante="secundario">Soy opositor</Boton>
          <Boton href="/login" variante="secundario">Soy preparador</Boton>
        </div>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Tarjeta titulo="Temario" pie="Un PDF, un tema, una versión">
          Tus apuntes o los de tu preparador, maquetados y versionados. Se sabe qué temario estudió cada opositor y cuándo.
        </Tarjeta>
        <Tarjeta titulo="Tests" pie="Corrección inmediata, sin esperar al martes">
          Preguntas tipo test con explicación de cada fallo. El opositor ve qué estudiar hoy, no la nota dentro de una semana.
        </Tarjeta>
        <Tarjeta titulo="Supuestos" pie="Rúbrica por apartados y nota trazable">
          Corrección por apartados con justificación. Queda registrado qué modelo, qué versión del prompt y quién validó.
        </Tarjeta>
        <Tarjeta titulo="Tribunal simulado" pie="El oral, ensayado antes del día">
          Expones el tema, te repreguntan y recibes un informe de tiempos, estructura y puntos flojos. Es una
          simulación, no una nota oficial.
        </Tarjeta>
      </section>

      <section className="rounded-xl border border-slate-200 bg-white p-6">
        <h2 className="text-base font-semibold text-tinta">Sin promesas que no podamos cumplir</h2>
        <ul className="mt-3 space-y-2 text-sm text-slate-600">
          <li>· No aprobamos exámenes: preparamos.</li>
          <li>· No hay nota automática: hay propuesta de corrección y validación humana.</li>
          <li>· El tribunal simulado no emite nota oficial: es un ensayo, y así se etiqueta.</li>
          <li>· Tus datos no se venden ni se usan para entrenar modelos.</li>
        </ul>
      </section>
    </div>
  )
}
