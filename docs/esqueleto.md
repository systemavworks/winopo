# Winopo · esqueleto del repositorio

**Estado**: F0 escrita · 29 pruebas del core en verde, `tsc --noEmit` limpio · **Fecha**: 17-nov-2026

Este documento dice **qué va en cada carpeta y qué no**. Si un archivo no encaja en ninguna de estas
responsabilidades, o sobra o falta una carpeta; se decide aquí antes de escribir código.

## 1. Árbol

```
winopo/
├── .github/
│   └── workflows/
│       └── ci.yml
├── contracts/
│   ├── api/
│   │   ├── error.schema.json
│   │   └── openapi.yaml
│   ├── ia/
│   │   ├── correccion.schema.json
│   │   └── guion.schema.json
│   └── README.md
├── core/
│   ├── .kotlin/
│   │   └── sessions/
│   │       └── … (0 archivos)
│   ├── gradle/
│   │   ├── wrapper/
│   │   │   └── … (2 archivos)
│   │   └── libs.versions.toml
│   ├── src/
│   │   ├── main/
│   │   │   └── … (20 archivos)
│   │   └── test/
│   │       └── … (6 archivos)
│   ├── build.gradle.kts
│   ├── Dockerfile
│   ├── gradle.properties
│   ├── gradlew
│   ├── gradlew.bat
│   └── settings.gradle.kts
├── docs/
│   ├── legal/
│   │   ├── consent/
│   │   │   └── … (1 archivos)
│   │   ├── cesion-derechos.md
│   │   └── rgpd.md
│   ├── marca/
│   │   ├── winopo_logo.jpeg
│   │   └── winopo_logo_es.jpeg
│   ├── runbooks/
│   │   ├── backup-restauracion.md
│   │   └── job-atascado.md
│   ├── alcance-v0.md
│   ├── decisiones.md
│   ├── esqueleto.md
│   ├── infra-servidor.md
│   ├── marca.md
│   ├── plan-implementacion.html
│   └── plan-implementacion.md
├── infra/
│   ├── caddy/
│   │   └── Caddyfile
│   ├── postgres/
│   │   └── init.sql
│   ├── scripts/
│   │   ├── backup.sh
│   │   ├── deploy.sh
│   │   └── restore-test.sh
│   ├── seed/
│   │   ├── demo-staging.sql
│   │   └── sintetica.sql
│   ├── docker-compose.prod.yml
│   ├── docker-compose.staging.yml
│   ├── docker-compose.yml
│   └── README.md
├── migrations/
│   ├── 0001_base.sql
│   ├── 0002_identidad.sql
│   ├── 0003_audit_log.sql
│   ├── 0004_archivo.sql
│   ├── 0005_temario.sql
│   ├── 0006_tema_version.sql
│   ├── 0007_pregunta.sql
│   ├── 0008_test.sql
│   ├── 0009_job.sql
│   ├── 0010_supuesto.sql
│   ├── 0011_correccion.sql
│   ├── 0012_video.sql
│   ├── 0013_consent.sql
│   ├── 0014_billing.sql
│   └── README.md
├── tests/
│   └── e2e/
│       ├── f0-acceso.spec.ts
│       ├── f1-temario.spec.ts
│       ├── f2-tests.spec.ts
│       ├── f3-supuestos.spec.ts
│       ├── f4-video.spec.ts
│       ├── f5-pagos.spec.ts
│       ├── package.json
│       ├── playwright.config.ts
│       └── README.md
├── web/
│   ├── public/
│   │   ├── icons/
│   │   │   └── … (1 archivos)
│   │   ├── manifest.webmanifest
│   │   └── robots.txt
│   ├── src/
│   │   ├── app/
│   │   │   └── … (9 archivos)
│   │   ├── components/
│   │   │   └── … (4 archivos)
│   │   └── lib/
│   │       └── … (3 archivos)
│   ├── .env.local.example
│   ├── Dockerfile
│   ├── next.config.ts
│   ├── package-lock.json
│   ├── package.json
│   ├── postcss.config.mjs
│   ├── tailwind.config.ts
│   ├── tsconfig.json
│   └── tsconfig.tsbuildinfo
├── .editorconfig
├── .env.example
├── .gitignore
├── Makefile
├── README.md
├── winopo_logo.jpeg
├── winopo_logo_es.jpeg
└── winopo_roadmap.html
```

## 2. Responsabilidades, con lo que NO va dentro

| Carpeta | Sí | No |
|---|---|---|
| `migrations/` | DDL, RLS, triggers, índices | Datos de semilla, lógica de negocio |
| `contracts/` | JSON Schema versionados | Ejemplos de prueba inventados |
| `core/temario` | Versiones, publicación, fuentes | Render de PDF, CSS del temario |
| `core/examen` | Banco de preguntas, intentos, nota | Corrección por IA |
| `core/supuesto` | Rúbrica, propuesta de IA, validación humana | Llamada HTTP directa al proveedor |
| `core/pago` | Checkout, webhook idempotente, factura | Precios hardcodeados por cliente |
| `web/` | Presentación, formularios, llamadas a la API | Consultas SQL, reglas de negocio |
| `tests/e2e` | Flujos de usuario contra el stack | Tests unitarios (esos viven en `core`) |

## 3. Las tres fronteras del sistema

1. **Tenant**: el contexto se fija en la petición y la base lo aplica con RLS. El código no "recuerda" filtrar.
2. **IA**: sólo se habla con ella a través de `CorrectorIA`, y su respuesta se valida contra
   `contracts/correccion-ia.schema.json`.
3. **Objetos**: los ficheros viven en R2; en Postgres sólo metadatos y hashes.
