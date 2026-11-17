# Winopo

Plataforma de preparación de oposiciones: el preparador publica su temario, sus tests y sus supuestos; sus opositores estudian, practican y reciben correcciones con **rúbrica explícita** y trazabilidad de quién corrigió.

> Código propietario. El repositorio es público para revisión; no se concede licencia de uso ni de redistribución.

## Estado

**F0 escrita, verificación pendiente.** No hay ninguna funcionalidad de negocio todavía: temario, tests, supuestos
 y cobro están planificados, no implementados. La hoja de ruta viva está en [`winopo_roadmap.html`](winopo_roadmap.html).

| Fase | Contenido | Estado |
|---|---|---|
| F0 | Esqueleto, esquema con RLS, login, dos roles, CI | escrito, sin verificar |
| F1 | Temario versionado | no empezada |
| F2 | Tests con clave fija | no empezada |
| F2.5 | Maquetación del temario (PDF reproducible) | nueva |
| F3 | Supuestos con rúbrica | no empezada |
| F4 | Vídeo y demo | no empezada |
| F5 | Cobro y alta de preparadores | no empezada |

## Estructura

```
core/        Backend Kotlin + Ktor (API /v1, worker de jobs)
migrations/  SQL versionado, RLS forzado
web/         Next.js + TypeScript + Tailwind
infra/       Compose local/staging/prod, Caddy
contracts/   Esquemas JSON compartidos
tests/e2e/   Playwright
docs/        Alcance, plan, decisiones, marca, legal, runbooks
```

## Arrancar en local

Requiere Docker, JDK 17 o 21 y Node 20+.

```bash
cp .env.example .env        # rellena SESSION_SECRET: openssl rand -base64 48
make dev                    # base de datos + core + web
make migrate                # esquema y políticas RLS
make seed                   # datos sinteticos
make test                   # tests del core (falla si no ejecuta ninguno)
make web-build              # typecheck y build del frontend
```

API en `http://localhost:8080`, web en `http://localhost:3000`.

## Decisiones que conviene leer antes de tocar código

- `docs/decisiones.md` — D1 a D11. Sin contexto de tenant no se ve una fila (RLS forzada); la sesión guarda el
  hash del token, no el token; la maquetación genera un PDF reproducible y nunca se edita a mano.
- `docs/plan-implementacion.md` — fases, stack y criterios de aceptación.
- `docs/alcance-v0.md` — qué se vende, qué no, y qué material no se puede alojar.

## Seguridad

- Sin secretos en el repositorio: `.env` está ignorado y `.env.example` solo documenta nombres.
- El inventario identificable del servidor (IP, ID, hostname) vive en `privado/`, también ignorado.
- Vulnerabilidades: abre un aviso privado en el repositorio, no un issue público.
