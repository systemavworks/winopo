# WinOpo

Plataforma de preparación de oposiciones donde **un tenant es un preparador** y preparador y opositor son **roles** (`membership.rol`): el preparador publica su temario, sus tests y sus supuestos y corrige a su grupo; el opositor estudia, practica, ensaya el oral y recibe correcciones con **rúbrica explícita** y trazabilidad de quién corrigió. El opositor que prepara por su cuenta tiene un **espacio personal** de un solo miembro y puede vincularse después a un preparador sin perder su historial (D12 corregida). Se registra él solo, sin invitación (D16), y contrata su **plan por temporada: Básico, Pro o Máster** (D13). Se cobra a los dos: al opositor su plan y al preparador su cuota (D19); no hay comisión ni directorio.

> Código propietario. El repositorio es público para revisión; no se concede licencia de uso ni de redistribución.

## Estado

**F0 escrita y verificada en todo lo que se puede verificar en esta máquina**: 29 pruebas del core en verde (6
clases), `tsc --noEmit` limpio y `next build` correcto (7 rutas). Falta arrancar el stack completo con PostgreSQL
real y pasar el E2E. No hay ninguna funcionalidad de negocio todavía: temario, tests, supuestos y cobro están
planificados, no implementados. La hoja de ruta viva está en [`winopo_roadmap.html`](winopo_roadmap.html).

| Fase | Contenido | Estado |
|---|---|---|
| F0 | Esqueleto, esquema con RLS, login, dos roles, CI, landing | 29 tests, typecheck y build en verde; faltan stack real y E2E |
| F1 | Temario versionado | no empezada |
| F2 | Tests con clave fija | no empezada |
| F2.5 | Maquetación del temario (PDF reproducible) | nueva |
| F3 | Supuestos con rúbrica | no empezada |
| F3.5 | Tribunal simulado (oral, informe de conducta) | nueva |
| F4 | Vídeo y demo | no empezada |
| F5 | Cobro en dos circuitos, sin Connect: plan del opositor (Básico/Pro/Máster) y cuota del preparador | no empezada |
| F5.5 | Alta pública: `/registro` con correo verificado y espacio personal | nueva |
| F6 | Nexo opositor–preparador: perfil opt-in, solicitud de plaza, sin comisión | nueva |

## Estructura

```
core/        Backend Kotlin + Ktor (API /v1, worker de jobs)
migrations/  SQL versionado, RLS forzado
web/         Next.js + TypeScript (app.winopo.es)
landing/     HTML estático de winopo.es (sin build, sin JS; marca en landing/assets)
tools/       Utilidades de desarrollo (marca del landing, DNS de Cloudflare)
infra/       Compose local/staging/prod, Caddy
contracts/   Esquemas JSON compartidos
tests/e2e/   Playwright
docs/        Alcance, plan, decisiones, marca, legal, runbooks
```

## Documentación

| Documento | Para qué |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | cómo está montado: componentes, multi-tenant, sesión, contrato de API, qué no existe todavía |
| [`DEPLOY.md`](DEPLOY.md) | desplegar en el servidor: DNS, secretos, migraciones, rollback, copias |
| [`docs/runbooks/alta-servidor-winopo.md`](docs/runbooks/alta-servidor-winopo.md) | alta de la caja: endurecer, DNS, secretos, primer despliegue y despliegue desde GitHub |
| [`winopo_roadmap.html`](winopo_roadmap.html) | hoja de ruta viva por fases |
| [`docs/decisiones.md`](docs/decisiones.md) | D1–D24 y el porqué de cada una |
| [`docs/alcance-v0.md`](docs/alcance-v0.md) | qué se vende y qué no |

## Arrancar en local

Requiere Docker, JDK 17 o 21 y Node 20+.

```bash
cp .env.example .env        # rellena SESSION_SECRET: openssl rand -base64 48
make dev                    # PostgreSQL y Mailpit
make migrate                # esquema y políticas RLS
make seed                   # datos sinteticos
make up                     # core + worker + web en contenedores
make test                   # tests del core (falla si no ejecuta ninguno)
make web-build              # typecheck y build del frontend
make landing                # landing de winopo.es en http://localhost:4000
```

API en `http://localhost:8080`, web en `http://localhost:3000`.

## Decisiones que conviene leer antes de tocar código

- `docs/decisiones.md` — D1 a D24. Sin contexto de tenant no se ve una fila (RLS forzada); la sesión guarda el
  hash del token, no el token; la maquetación genera un PDF reproducible y nunca se edita a mano; hay **un tenant por
  preparador** y el opositor es un rol, con espacio personal si va por su cuenta (D12 corregida); tres ámbitos:
  `tenant`, `plataforma` y `admin` (D18); y se cobra a los dos lados sin comisión (D19).
- `docs/plan-implementacion.md` — fases, stack y criterios de aceptación.
- `docs/alcance-v0.md` — qué se vende, qué no, y qué material no se puede alojar.

## Seguridad

- Sin secretos en el repositorio: `.env` está ignorado y `.env.example` solo documenta nombres.
- El inventario identificable del servidor (IP, ID, hostname) vive en `privado/`, también ignorado.
- Vulnerabilidades: abre un aviso privado en el repositorio, no un issue público.
