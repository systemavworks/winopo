# Winopo · esqueleto del repositorio

**Estado**: F0 iniciada · **Fecha**: 17-nov-2026

Este documento dice **qué va en cada carpeta y qué no**. Si un archivo no encaja en ninguna de estas
responsabilidades, o sobra o falta una carpeta; se decide aquí antes de escribir código.

## 1. Árbol

```
winopo/
├── Makefile                     comandos: dev, migrate, test, tree, web-dev
├── README.md                    qué es y cómo se arranca
├── .env.example                 todas las claves, ningún valor real
├── .gitignore
│
├── docs/
│   ├── alcance-v0.md            el qué: producto, módulos, legal, dominio
│   ├── plan-implementacion.md   el cómo: stack, datos, fases, riesgos
│   ├── plan-implementacion.html misma cosa, para leer e imprimir
│   └── esqueleto.md             este documento
│
├── migrations/                  SQL a mano, numerado, nunca editado tras aplicarse
│   ├── 0001_init.sql            tenant, app_user, membership, audit_log + RLS
│   ├── 0002_temario.sql         (reservado F1)
│   └── 0003_examen_supuestos.sql (reservado F2–F3)
│
├── contracts/                   JSON Schema: lo que el sistema no puede saltarse
│   ├── correccion-ia.schema.json
│   └── README.md
│
├── core/                        Kotlin + Ktor · API y worker en el mismo binario
│   ├── build.gradle.kts
│   ├── settings.gradle.kts
│   ├── Dockerfile
│   └── src/
│       ├── main/kotlin/es/winopo/
│       │   ├── Application.kt          arranque: HTTP o worker
│       │   ├── auth/                   sesión, roles, guardas
│       │   ├── tenant/                 contexto y RLS por petición
│       │   ├── temario/                temas y versiones
│       │   ├── examen/                 preguntas, tests, intentos
│       │   ├── supuesto/               rúbricas y corrección
│       │   ├── video/                  guion, TTS y estados del vídeo
│       │   ├── pago/                   Stripe y webhooks
│       │   ├── job/                    cola y worker
│       │   └── comun/                  dinero, errores, reloj
│       └── test/kotlin/es/winopo/      tests que corren de verdad
│
├── infra/docker/docker-compose.yml   PostgreSQL 16 + core + worker
│
├── web/                         Next.js: dos caras, una app
│   ├── package.json
│   ├── next.config.js
│   ├── tailwind.config.ts
│   ├── postcss.config.js
│   ├── tsconfig.json
│   └── src/app/
│       ├── layout.tsx           cabecera común con los dos accesos
│       ├── page.tsx             portada: elegir cara
│       ├── preparador/          shell del preparador
│       ├── opositor/            shell del opositor
│       └── api/                 proxy al core (sin lógica de negocio)
│
└── tests/e2e/                   flujos completos contra el stack levantado
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
