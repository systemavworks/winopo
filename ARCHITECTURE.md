# Arquitectura de WinOpo

> Documento de referencia del sistema en v0. Describe **lo que hay**, no lo que nos gustaría.
> Cuando algo no existe todavía, está en la sección [Lo que no está](#10-lo-que-no-está).
> Última revisión: F0 cerrado (esqueleto + identidad), fase F2.5 añadida al plan.

## 1. Resumen en una frase

WinOpo es un SaaS **multi-tenant donde el tenant es el preparador** y preparador y opositor son **roles**
(`membership.rol`), donde el opositor estudia temario maquetado, hace tests corregidos automáticamente, resuelve
supuestos prácticos, ensaya la exposición ante un tribunal y ve su progreso; el preparador publica, corrige y
responde ante sus opositores. El opositor que prepara por su cuenta tiene un **espacio personal** de un solo miembro
y puede vincularse a un preparador después sin perder su historial (D12 corregida, D18).

Tres decisiones mandan sobre todas las demás:

1. **Un solo backend y un solo binario**, con dos perfiles (`api` y `worker`).
2. **Aislamiento por base de datos (RLS), no por código**: si una consulta olvida el filtro, PostgreSQL
   devuelve cero filas. El fallo es cerrado.
3. **Sin servicios de moda que no aporten**: ni Redis, ni Kafka, ni microservicios, ni ORM.

## 2. Vista de componentes

```
                 Internet
                    │
             ┌──────▼───────┐
             │  Cloudflare  │
             ├──────┬───────┤
 winopo.es ──┤      │       │
 (Worker)    ▼      ▼       │
        landing/   │  túnel │
       (assets)    │        │
 app.winopo.es ────┴────────┘
                    │
               ┌────▼─────┐
               │  Caddy   │  enrutado por dominio y cabeceras
               └──┬────┬──┘
                  │    │
      /v1/* , /healthz  │ todo lo demás
                  │    │
          ┌───────▼──┐ ┌─▼────────┐
          │  core    │ │  web     │  Next.js 15 (App Router), standalone
          │  (Ktor)  │ │  Node 22 │
          └───┬──┬───┘ └────┬─────┘
              │  │          │  fetch interno a WINOPO_API_URL
              │  └──────────┴──────────────► vuelve a /v1 de core
              │
      ┌───────▼────────┐        ┌──────────────┐
      │  PostgreSQL 16 │◄───────│   worker     │  mismo binario, perfil worker
      │  RLS forzada   │        │  (cola job)  │
      └────────────────┘        └──────────────┘
```

| Componente | Tecnología | Responsabilidad | No hace |
|---|---|---|---|
| Worker `winopo` | Cloudflare Workers + assets estáticos | sirve `landing/` en `winopo.es` y `www.winopo.es` | lógica de negocio |
| `caddy` | Caddy 2 | enrutado por dominio, cabeceras, TLS en caja dedicada; entrada del túnel | lógica de negocio |
| `core` | Kotlin + Ktor + Netty | API HTTP `/v1`, sesiones, RBAC, acceso a datos | renderizar HTML |
| `worker` | mismo binario, `WINOPO_PROFILE=worker` | cola de trabajos (maquetación, extracción, corrección) | atender HTTP |
| `web` | Next.js 15 / React 19 | interfaz de preparador, opositor y admin | hablar con PostgreSQL |
| `db` | PostgreSQL 16 | datos, aislamiento (RLS), cola de trabajos | exponerse al exterior |
| `landing` | HTML estático | página pública de `winopo.es`, servida por el Worker de Cloudflare | formularios con servidor propio |

**Por qué un solo binario con dos perfiles:** el worker comparte modelos, repositorios y configuración
con la API. Separarlos duplicaría el SQL y las reglas de tenant. La imagen es la misma; lo único que
cambia es `WINOPO_PROFILE` (`core/src/main/kotlin/es/winopo/core/Main.kt`).

**Por qué no hay Redis:** la cola vive en PostgreSQL con `select ... for update skip locked limit 1`
(`migrations/0009_job.sql`, F3). Para el volumen previsto (decenas de trabajos al día, no miles por
segundo) es un servicio menos que operar, copiar y asegurar.

## 3. Dos dominios, dos responsabilidades

| Dominio | Qué sirve | Quién lo edita |
|---|---|---|
| `winopo.es` + `www` | landing comercial estático (`landing/`), en un Worker de Cloudflare | marketing / HTML |
| `app.winopo.es` | la plataforma (login, panel del preparador, panel del opositor) | `web/` |
| `app.winopo.es/v1/*` | la API, consumida por la propia web y por clientes futuros | `core/` |
| `staging.winopo.es` | copia con datos sintéticos | nadie: es para probar |

El apex (`winopo.es`) sirve el landing y **no** la aplicación. Motivos: el landing cambia sin recompilar
Next, se publica sin tocar el servidor y una caída del backend no deja la web comercial en blanco.
`landing/_redirects` manda `/login`, `/app*` y `/v1*` del apex a `app.winopo.es`.

El landing **no depende de la caja**: `wrangler.jsonc` declara `landing/` como assets y `winopo.es` +
`www.winopo.es` como `custom_domain`, y lo publica `tools/deploy-landing.sh` o el workflow «landing» en
cada push. Cambiar el landing = cambiar un HTML y hacer push; no hay build. Las cabeceras que antes ponía
Caddy viven en `landing/_headers`. Como red de seguridad, `infra/caddy/Caddyfile` sigue sirviendo el mismo
`landing/` montado en `/srv/landing` si algún día se detacha el custom domain. Los recursos de marca
(`landing/assets/`) se generan con `tools/marca/generar_marca.py` a partir del logo original: ahí no se
edita a mano. El emblema se sirve sobre una pastilla crema porque el azul de la marca desaparece en
modo oscuro, y el logo con el nombre completo no se usa en la cabecera: es un lockup vertical que a
68 px de alto no se lee.

## 4. El recorrido de una petición autenticada

1. El navegador pide `GET https://app.winopo.es/preparador` con la cookie `winopo_sesion`.
2. Caddy termina TLS y reenvía a `web:3000`.
3. El servidor de Next llama a `core` (`GET /v1/auth/sesion`, reenviando la cookie).
4. `core` lee la cookie, calcula su SHA-256 y abre una transacción con contexto `winopo.sesion_hash`
   (`Database.conSesion`). La política `sesion_por_token` deja ver **esa única fila** de `sesion`.
5. Con el `user_id` y el `tenant_id` de la sesión, `core` comprueba el rol **contra la tabla
   `membership` en cada petición**, no contra la cookie. Si al opositor se le da de baja, su cookie
   deja de valer al instante.
6. El resto de consultas de la petición usan `Database.conTenant(tenantId, userId)`: las políticas
   `*_por_tenant` filtran por `winopo_tenant()`.
7. Al cerrar la transacción, `set_config(..., true)` se limpia solo; la conexión vuelve al pool sin
   memoria del tenant anterior.

**El punto 7 es el fallo clásico de este patrón** (fijar el tenant con `SET` de sesión y devolver la
conexión al pool con el contexto pegado). Aquí el contexto es local a la transacción, así que no puede
filtrarse entre peticiones (`core/src/main/kotlin/es/winopo/core/db/Database.kt`).

## 5. Multi-tenant: cómo se aísla de verdad

### Modelo

```
tenant (preparador)  1 ──── n  membership  n ──── 1  app_user
   │                              │
   │                              └── rol: preparador | opositor | admin
   └── id = winopo.tenant_id en cada transacción
```

- Un `app_user` es global (una persona, un correo, una contraseña).
- `membership` une persona y preparador con un rol. Una persona puede ser opositor en un preparador
  y preparador en otro.
- **v1: un opositor tiene como mucho una `membership` activa de rol opositor** en un tenant de preparador (D1); su
  espacio personal no cuenta como pertenencia. Si el login encuentra varias, responde `409 varias_pertenencias` en
  lugar de adivinar.
- **Ámbito de plataforma** (D18): identidad de usuario, perfil público opt-in, solicitudes de plaza y cuotas viven en
  tablas propias, fuera del `tenant_id` del negocio. Ahí no hay datos de alumnos.

### Los cuatro contextos de acceso

| Método | Contexto fijado | Para qué | Quién puede llamarlo |
|---|---|---|---|
| `Database.sinContexto` | ninguno | tablas globales (buscar correo en login) | solo login y tareas de sistema |
| `Database.conUsuario` | `winopo.user_id` | leer **mis** pertenencias tras verificar contraseña | login |
| `Database.conSesion` | `winopo.sesion_hash` | validar la cookie antes de conocer el tenant | middleware de sesión |
| `Database.conTenant` | `winopo.tenant_id` + `winopo.user_id` | todo lo demás | rutas autenticadas |

Ninguna ruta de datos usa `sinContexto`. Si alguien lo hiciera, la RLS devolvería cero filas: el
sistema falla cerrado, no abierto.

### Políticas (`migrations/0002_identidad.sql`, combinadas con OR)

| Política | Tabla | Regla |
|---|---|---|
| `tenant_por_contexto` | `tenant` | `id = winopo_tenant()` |
| `membership_por_tenant` | `membership` | `tenant_id = winopo_tenant()` |
| `membership_propia` | `membership` | `user_id = winopo.user_id` (resuelve el login) |
| `sesion_por_tenant` | `sesion` | `tenant_id = winopo_tenant()` |
| `sesion_por_token` | `sesion` | `token_hash = winopo.sesion_hash` (resuelve la cookie) |

`force row level security` está activado: ni el dueño de la tabla se salta las políticas. El rol de
aplicación se crea **sin** `BYPASSRLS` (`infra/postgres/init.sql`, y en producción por infraestructura).

### Regla para las migraciones nuevas

**La RLS de una tabla va en la misma migración que crea la tabla.** Si se separa, se olvida; y una tabla
sin política en un esquema con RLS forzada no es "abierta": es inaccesible hasta que alguien añade un
`using (true)` para "que funcione". Ver `migrations/README.md`.

## 6. Identidad y sesión

- **Contraseñas:** PBKDF2-HMAC-SHA256, 200 000 iteraciones, sal por usuario, formato
  `pbkdf2_sha256$<iteraciones>$<sal>$<hash>` (D10). Comparación en tiempo constante.
  No se usa Argon2id para no añadir dependencias nativas; PBKDF2 es aceptado por OWASP.
- **Sesiones de servidor:** token aleatorio de 32 bytes (base64url) en cookie `HttpOnly`, `SameSite=Lax`
  y `Secure` fuera de local. En la base solo se guarda el **SHA-256** del token. Duración por defecto
  720 h (`SESSION_HOURS`).
- **Rol:** nunca se guarda en la cookie. Se resuelve contra `membership` en cada petición
  (`SessionService.valida`). Revocar acceso = `estado = 'baja'`; efecto inmediato.
- **Logout:** borra la fila de `sesion` y vacía la cookie. Un token robado deja de servir.
- **Autorización:** `SesionAutenticada?.exigir(vararg roles)` (`security/Guards.kt`) lanza `SinSesion`
  (401) o `SinPermiso` (403); `StatusPages` los convierte al formato único de error.

## 7. Contrato de la API

- Prefijo `/v1`. Cambio incompatible = `/v2`; `/v1` no se rompe.
- Errores: **una sola forma** para toda la API (`contracts/api/error.schema.json`):

```json
{ "error": "credenciales incorrectas", "codigo": "credenciales" }
```

`codigo` es máquina-legible y estable; `error` es texto para humanos. Si no hay código específico,
el campo se omite.

- **Un 404 cross-tenant es indistinguible de un 404 real**: no se revela la existencia de recursos de
  otro preparador (`StatusPages`).
- Rutas existentes en F0: `GET /healthz`, `POST /v1/auth/login`, `GET /v1/auth/sesion`,
  `POST /v1/auth/logout`.

| Código | `codigo` | Cuándo |
|---|---|---|
| 400 | `peticion_invalida` | JSON malformado o campos que no validan |
| 401 | `credenciales` | correo o contraseña incorrectos |
| 401 | `sin_sesion` | falta cookie válida |
| 403 | `sin_permiso` | sesión válida, rol insuficiente |
| 403 | `sin_pertenencia` | usuario sin preparador asignado |
| 404 | `no_encontrado` | recurso inexistente **o de otro tenant** |
| 409 | `varias_pertenencias` | opositor en más de un preparador (v1 no lo soporta) |
| 500 | `error_interno` | fallo no controlado (se registra con traza; no se devuelve al cliente) |

## 8. Frontend

- Next.js 15 (App Router) + React 19, TypeScript estricto, sin framework de UI.
- Grupos de rutas por rol: `(public)` portada y login, `(preparador)`, `(opositor)`, `(admin)`.
- **La web no habla con PostgreSQL.** Todo pasa por `/v1`.
- El rol se comprueba en el servidor (componente de servidor o route handler), no en el cliente:
  ocultar un botón no es autorizar.
- `web/src/lib/api/` centraliza el acceso a la API (`cliente.ts`, `sesion.ts`, `tipos.ts`).
- Build `standalone`, usuario sin privilegios, healthcheck propio en el Dockerfile.

## 9. Servicios externos y su frontera

| Servicio | Para qué | Frontera |
|---|---|---|
| Cloudflare R2 (S3) | PDFs, vídeos, escaneos de temario | nunca se sirve el binario directo: URLs firmadas de corta duración |
| IA (corrección asistida) | corregir supuestos prácticos | interfaz propia (`CorrectorIA`); el proveedor se cambia sin tocar el dominio; **no** se envían datos personales del opositor, solo el texto del supuesto |
| Stripe | cobros en dos circuitos, ninguno Connect: el preparador (B2B, cuota por temporada y tramos de alumnos) y los planes del opositor (B2C: Básico, Pro y Máster, D13); el opositor vinculado no paga dos veces el mismo material |
| WeasyPrint (`maquetador`) | generar PDF desde HTML | contenedor aparte: sus dependencias nativas no contaminan la imagen de `core` (D11) |

Regla general: **ningún servicio externo recibe identificadores internos** (ni `tenant_id` ni `user_id`);
lo que sale es el mínimo necesario para la operación.

## 10. Lo que no está

Enumerado para que nadie asuma que existe:

| Elemento | Estado real |
|---|---|
| Tablas de temario, tests, supuestos, vídeo, consentimiento, facturación | migraciones `0004`–`0014` son **stubs de 4 líneas con el número reservado**; las tablas no existen |
| Cola `job` | `JobQueue.reclamarSiguiente()` devuelve `null` a propósito: el worker late cada 2 s y no finge trabajo |
| Handlers del worker (maquetación, extracción, corrección) | no existen |
| `CorrectorIA` | interfaz definida, sin implementación de proveedor |
| Tribunal simulado (voz, transcripción, informe) | especificado en `docs/alcance-v0.md` §8.1 y D15; sin código, sin tabla y sin migración |
| Material derivado (esquemas, PPTX, línea de tiempo) | especificado en §7.2 del alcance; depende de que exista F2.5 |
| Subida a R2 | no implementada |
| Stripe | no implementado |
| `next build` | **en verde** (17-nov-2026): compila, 7 rutas, tipos válidos |
| E2E (Playwright) | specs escritos; `f0` real, `f1`–`f5` en `fixme` |
| Rate limiting, verificación de correo, recuperación de contraseña | no existen (F0 no los necesita; F3 sí) |
| Observabilidad (métricas, trazas) | solo logs a stdout vía SLF4J |

## 11. Reglas de código que no se negocian

1. **SQL a mano, sin ORM.** Lo que se ejecuta es lo que se lee en el repositorio.
2. **Toda ruta de datos pasa por `conTenant`.** Sin excepciones, sin "solo esta vez".
3. **Toda fase nueva trae su prueba de aislamiento**: un usuario del tenant A no puede leer ni modificar
   datos del tenant B. Si esa prueba no existe, la fase no está terminada.
4. **Una migración aplicada no se edita.** Se corrige con la siguiente.
5. **Credenciales fuera del repositorio.** `.env` está en `.gitignore`; en el servidor, permisos `600`.
6. **Nada de datos reales en desarrollo ni en staging.** Semilla sintética (`infra/seed/sintetica.sql`).
7. **El contenido del preparador es suyo.** La licencia es de uso, no cesión de propiedad, y está
   prohibido usar sus temarios para entrenar modelos (ver `docs/legal/cesion-derechos.md`).

## 12. Decisiones relacionadas

`docs/decisiones.md` es la fuente de verdad. Las que afectan a esta arquitectura:
D1 (una vinculación activa por opositor), D12 (un tenant por preparador; preparador y opositor son roles), D3 (Kotlin/Ktor),
D4 (Next.js), D6 (RLS en la base), D7 (responsable del tratamiento, pendiente), D9 (precio, pendiente),
D10 (PBKDF2), D11 (WeasyPrint en contenedor aparte), D13 (planes Básico/Pro/Máster del opositor),
D15 (tribunal simulado con audio grabado).

- Despliegue: [`DEPLOY.md`](DEPLOY.md)
- Plan y fases: [`winopo_roadmap.html`](winopo_roadmap.html)
- Árbol de ficheros: [`docs/esqueleto.md`](docs/esqueleto.md)
- Alcance funcional: [`docs/alcance-v0.md`](docs/alcance-v0.md)

