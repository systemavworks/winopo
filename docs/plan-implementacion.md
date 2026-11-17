# WinOpo · plan de implementación

**Estado**: borrador de trabajo · **Fecha**: 17-nov-2026 · **Objetivo**: plataforma operativa para 3 preparadores
antes de septiembre de 2027, empezando a vender módulos en la temporada 2027–2028.

Este documento decide **cómo se construye**. El qué está en [`alcance-v0.md`](alcance-v0.md): si los dos discrepan,
manda el alcance.

## 1. Principios

| # | Principio | Consecuencia práctica |
|---|---|---|
| 1 | **Un backend, dos caras** | Un servicio y una base. Preparador y opositor son permisos y rutas, no productos |
| 2 | **El dato manda** | Primero el esquema y las migraciones; la pantalla después |
| 3 | **Nada se sobrescribe** | Temario versionado, correcciones versionadas, vídeos marcados, no borrados |
| 4 | **La IA propone** | Ninguna clave ni nota final sin humano. Siempre `corregido_por` |
| 5 | **Multi-tenant fail-closed** | RLS forzado: sin contexto de tenant no se ve una fila |
| 6 | **Un test que no corre está en rojo** | `make test` falla si no ejecuta ningún test |
| 7 | **Céntimos, nunca floats** | Todo importe `*_cents` entero |
| 8 | **El vídeo es un derivado** | Se puede regenerar desde el guion y la versión del tema |

## 2. Stack

Mismo stack que Billka, a propósito: un solo lenguaje de backend, un solo patrón de despliegue y los mismos
utillajes que ya están probados en producción.

| Capa | Tecnología | Motivo |
|---|---|---|
| Backend | **Kotlin + Ktor** (JDK 21, Gradle) | Coherencia con Billka; corrutinas para IA y vídeo |
| Base de datos | **PostgreSQL 16** | RLS nativo, JSONB para rúbricas, `citext` para correos |
| Migraciones | **SQL a mano**, versionadas | El esquema es el contrato, no un subproducto del ORM |
| Frontend | **Next.js + TypeScript + Tailwind** | Dos shells sobre la misma API; SSR para el temario |
| Objetos | **Cloudflare R2** | Vídeo y PDF con coste de salida bajo |
| Colas | Tabla `job` + worker del propio `core` | Sin infraestructura nueva en v0 |
| IA | Proveedor externo tras una interfaz propia | Cambiar de modelo no debe tocar el dominio |
| TTS y vídeo | Servicio de voz + render de diapositivas | Céntimos por vídeo, regenerable |
| Pagos | Stripe (Checkout + webhooks) | IVA, facturas y SCA resueltos |
| Correo | Proveedor transaccional con SPF/DKIM/DMARC | Entregabilidad desde el día uno |
| Observabilidad | Logs estructurados + métricas de job | Un job atascado se ve, no se adivina |

Nada de microservicios, ni Kubernetes, ni colas gestionadas en v0: un servicio, un worker, una base y un bucket.

## 3. Despliegue

```
  web (Next.js)  ─┐
                  ├─ REST /v1 ─ core (Ktor) ─┬─ PostgreSQL 16 (RLS forzado)
  PWA opositor ───┘        │                 ├─ R2 (vídeo, PDF, adjuntos)
                           │                 └─ proveedor IA / TTS
                        worker (mismo binario, perfil worker)
```

- **Un servicio + un worker**. El worker reclama jobs de la tabla `job` con `FOR UPDATE SKIP LOCKED`.
- **Objetos fuera de Postgres**: en la base viven metadatos, hashes y punteros.
- **Secretos en `.env`**, nunca en el repositorio; `.env.example` documenta las claves.
- **Producción y staging separados**, con bases distintas y sin datos reales en staging.

## 4. Modelo de datos v0

| Tabla | Clave para qué | Notas |
|---|---|---|
| `tenant` | Un preparador = un tenant | `slug`, `nombre`, `estado` |
| `app_user` | Cuenta con login | Único por correo normalizado |
| `membership` | Qué usuario pertenece a qué tenant y con qué rol | `preparador`, `opositor`, `admin` |
| `temario` | Conjunto de temas de una oposición | Por tenant y convocatoria |
| `tema` | Unidad de estudio | Orden, título, estado |
| `tema_version` | Versión inmutable del contenido | `version`, `publicado_en`, `autor_id` |
| `tema_fuente` | Cita de cada versión | Norma, BOE/BOJA, URL, fecha |
| `pregunta` | Banco de preguntas | `tema_id`, `enunciado`, `clave` (fija) |
| `pregunta_opcion` | Opciones de la pregunta | `es_correcta` |
| `test` | Examen generado | `tema_ids`, `n_preguntas`, `publicado` |
| `test_intento` | Un alumno haciendo un test | `iniciado_en`, `cerrado_en`, `nota_cents` |
| `test_respuesta` | Respuesta por pregunta | Corregida contra clave, nunca contra IA |
| `supuesto` | Caso práctico | `enunciado`, `tema_id` |
| `rubrica` | Rúbrica versionada del supuesto | `version`, publicada |
| `rubrica_item` | Apartado puntuable | `puntos_cents`, tolerancia |
| `entrega` | Supuesto entregado por el opositor | Fichero o texto |
| `correccion` | Corrección de una entrega | **`corregido_por`**, `modelo`, `prompt_version` |
| `correccion_item` | Puntos por apartado | Trazable a `rubrica_item` |
| `video` | Derivado del tema | `tema_version_id`, `guion_sha256`, `estado` |
| `job` | Cola de trabajo | `tipo`, `estado`, `intentos`, `ultimo_error` |
| `consent` | Consentimientos y renuncia al desistimiento | Fecha, IP, texto versionado |
| `audit_log` | Quién hizo qué | Append-only |

Reglas transversales: toda tabla de contenido lleva `tenant_id` y RLS forzado; toda tabla con historial lleva
`creado_en` y `creado_por`; nada se borra, se marca.

## 5. Fases

Cada fase termina en algo **demostrable**, no en «código avanzado». Si el criterio de aceptación no se puede
enseñar en pantalla o en un test, la fase no está cerrada.

### F0 · Esqueleto, datos y acceso — 2 semanas

- Repositorio, `docker-compose`, `Makefile`, `.env.example`, CI.
- Migraciones `0001`–`0003`: `tenant`, `app_user`, `membership`, `audit_log`, RLS forzado.
- Login con sesión, dos roles, guardas por rol y por tenant.
- **Aceptación**: `make dev` levanta el stack desde cero; `make test` ejecuta tests reales (y falla si no hay
  ninguno); un opositor del tenant A recibe 404 con un recurso del tenant B.

### F1 · Temario versionado — 3 semanas

- Editor de temas y versiones; publicación; fuentes citadas por versión; subida de PDF a R2.
- Vista de opositor con la versión publicada y el histórico.
- **Aceptación**: el preparador publica el tema 5 v1, lo edita a v2 y el opositor ve v2; v1 sigue consultable y el
  vídeo (si existe) queda marcado como desactualizado.

### F2 · Tests y resultados — 3 semanas

- Banco de preguntas, generación de test por temas y número, intento con temporizador, corrección contra clave fija.
- Estadísticas por tema y por grupo; exportación CSV.
- **Aceptación**: test de 30 preguntas sobre 100, nota calculada en céntimos, desglose por tema, y un test con dos
  respuestas correctas configuradas **no** se guarda (validación en origen).

### F2.5 · Maquetación del temario — 2 semanas

Añadida el 17-nov-2026 a partir de una observación de campo: **la mayoría de preparadores tiene el contenido, no el
documento**. Word con estilos inconsistentes, escaneos, fotos de apuntes, numeración rota. El opositor estudia de un
PDF de 900 páginas sin índice útil. Es lo primero que se ve del curso, así que no es un detalle de acabado.

- Importar DOCX / Markdown / PDF con texto y normalizar a un Markdown propio (`winopo-md`): títulos, listas,
  tablas, imágenes y citas, nada más.
- Una plantilla por tenant: A4, márgenes, tipografía, encabezado con tema y versión, pie con «página x de y»,
  numeración de epígrafes automática, portada y contraportada.
- PDF con **WeasyPrint** (HTML+CSS → PDF) en un contenedor aparte `maquetador`. No LaTeX (dependencia enorme y
  frágil en ARM64) y **no** un editor WYSIWYG: un editor es otro producto y otro año de trabajo.
- **Avisos, no magia**: imágenes por debajo de 150 ppp, tablas que desbordan la caja, epígrafes sin numerar, enlaces
  muertos, texto sin título. El preparador ve qué le falta antes de publicar.
- Estado por versión: `sin_maquetar → maquetado → publicado`. El tema se puede leer en HTML sin maquetar; el PDF
  solo existe cuando está maquetado.
- El PDF es un **derivado** de `tema_version` + hash de plantilla. Nunca se edita a mano: si se edita, deja de ser
  reproducible y se pierde la trazabilidad de la que presumen las otras fases.

Fuera de alcance: diseño libre por preparador, corrección ortotipográfica con IA, plantillas múltiples.

- **Aceptación**: un DOCX de 40 páginas produce en menos de 2 minutos un PDF con portada, índice paginado y
  numeración correcta; y el listado de avisos detecta las 3 tablas desbordadas de un fichero de prueba.

Valor comercial: hoy la maquetación se cobra aparte (40–90 € por tema) o se hace a mano. Incluirla en el módulo Base
es un argumento concreto frente a Opogestión y crea dependencia sana: nadie migra un temario ya maquetado.

### F3 · Supuestos con rúbrica — 4 semanas

- Enunciado, rúbrica por apartados con puntos y tolerancias, entrega de texto o fichero.
- Corrección asistida por IA contra la rúbrica; validación humana; `corregido_por`, `modelo` y `prompt_version`.
- Comparativa IA vs preparador para medir desviación.
- **Aceptación**: dos correcciones de la misma entrega, con el mismo prompt y modelo, producen el mismo desglose; y
  toda corrección indica quién la cerró. Una entrega corregida solo por IA **no** suma a la nota final.

### F4 · Vídeo y demo — 3 semanas

- Guion desde el tema, TTS, render de diapositivas, subida a R2, reproductor con progreso.
- Modo demo de 3 semanas: temario completo, sin vídeo y sin corrección de supuestos por IA.
- **Aceptación**: un tema pasa a vídeo sin intervención manual; regenerar el vídeo de una versión no borra el
  anterior; la demo caduca sola.

### F5 · Cobro y alta de preparadores — 3 semanas

- Stripe Checkout, webhooks idempotentes, facturas, cupones de temporada.
- Checkout con **clic de renuncia al desistimiento** (art. 103.m TRLGDCU) guardado con fecha, IP y versión del texto.
- Alta guiada de los 3 preparadores; panel de admin mínimo.
- **Aceptación**: compra de prueba de un módulo, factura con IVA correcto, acceso concedido por webhook y no por
  retorno del navegador; consentimiento recuperable y auditable.

**Total: 20 semanas** de desarrollo (18 originales + 2 de maquetación). Con un solo desarrollador y sin imprevistos,
arrancar el 1-dic-2026 lleva a finales de abril de 2027, con margen hasta septiembre.

## 6. Entornos y CI

| Entorno | Para qué | Datos |
|---|---|---|
| Local | Desarrollo diario | Semilla sintética |
| Staging | Demo con el preparador | Sintéticos, nunca alumnos reales |
| Producción | Alumnos | Reales, con RGPD |

CI en cada push: `make build`, `make test`, `make test-db` (PostgreSQL efímero para esquema y RLS), validación de
migraciones y `make web-build`. **Rojo si no se ejecuta ningún test**, igual que en Billka.

## 7. Seguridad y RGPD

- Contraseñas con Argon2id; sesiones con cookie `HttpOnly`, `Secure`, `SameSite=Lax`.
- RLS forzado en todas las tablas de tenant; el contexto se fija por petición y se limpia al terminar.
- Datos de menores: los opositores pueden ser mayores de edad, pero el temario de Maestro toca datos sensibles por
  contexto. Minimizar: no pedir más que correo, nombre y progreso.
- Borrado: anonimizar el usuario y conservar métricas agregadas; las correcciones se conservan sin identidad.
- Exportación de datos del alumno en un clic (portabilidad).
- Registro de accesos a material protegido (`audit_log`).
- Copias: `pg_dump` diario a almacenamiento externo, retención 30 días, restauración probada una vez al trimestre.

## 8. IA: pipeline y versionado

```
entrega ─► construccion_prompt(rubrica, temario_version) ─► proveedor_ia ─► correccion_item[]
                    │                                              │
              prompt_version                                  modelo, tokens, coste_cents
```

Reglas de implementación:

1. **Interfaz propia** `CorrectorIA` con una sola operación; cambiar de proveedor es una clase nueva.
2. La rúbrica entra en el prompt **como dato estructurado**, no como texto libre: los puntos por apartado se suman
   en código, no se creen al modelo.
3. La respuesta del modelo se valida contra un JSON Schema; si no valida, el job falla y queda en `job.ultimo_error`.
4. Idempotencia por `entrega_id + rubrica_version + prompt_version + modelo`.
5. Coste por corrección registrado en céntimos; un supuesto no puede costar más que el margen del módulo.
6. **Ninguna clave de test pasa por la IA**, ni para generarla ni para corregirla.

## 9. Vídeo: pipeline

```
tema_version ─► guion (humano o IA, revisado) ─► TTS ─► diapositivas ─► render ─► R2 ─► video(estado)
```

- El guion es **texto versionado** y propiedad del preparador; el vídeo es un derivado reproducible.
- `video.guion_sha256` detecta si el guion cambió sin regenerar.
- Estados de primera clase: `pendiente`, `generando`, `listo`, `fallido`, `desactualizado`.
- Un fallo de render no bloquea el tema: se publica el texto y el vídeo va cuando va.

## 10. Pagos

- Stripe Checkout con `client_reference_id` = `membership_id`; el acceso se concede **por webhook**, nunca por el
  retorno del navegador.
- Webhooks idempotentes por `event.id` en tabla propia.
- Factura con IVA español; si el asesor confirma exención de enseñanza (D4), se configura la tasa y se documenta.
- Renuncia al desistimiento: casilla obligatoria, texto versionado, guardada con fecha e IP.
- Reembolsos: manuales en v0, con registro en `audit_log`.

## 11. Costes de operación (orden de magnitud)

| Concepto | Coste mensual estimado |
|---|---|
| Servidor (core + worker) | 15–40 € |
| PostgreSQL gestionado | 15–30 € |
| R2 (vídeo: 20 GB) | 2–5 € |
| Correo transaccional | 0–15 € |
| IA (500 correcciones/mes) | 20–60 € |
| TTS y render (20 vídeos/mes) | 10–30 € |
| **Total** | **~60–180 €/mes** |

Se sostiene con tres preparadores y pocos alumnos; el punto de equilibrio no exige cientos de clientes.

## 12. Riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| El preparador no cede los derechos de sus apuntes | Alto | Cláusula de cesión firmada **antes** de subir nada |
| Se aloja material de editorial | Alto | Solo enlaces; revisión manual del material subido |
| La IA corrige mal y el alumno reclama | Alto | Rúbrica explícita, validación humana, `corregido_por` |
| Confusión con `opositio` al dictar el dominio | Medio | Comprar `vinopo.es`; el logotipo siempre con la W visible |
| OEPM deniega o hay anterioridad en clase 41 | Medio | Búsqueda antes de invertir en marca; alternativa de nombre barata |
| Coste de IA descontrolado | Medio | Límite por alumno y por mes; coste en céntimos por corrección |
| Dependencia de un solo desarrollador | Alto | Documentación, migraciones a mano, tests que corren solos |

## 13. Definición de «hecho»

Una historia está hecha cuando: hay migración, hay test que la cubre, hay pantalla o endpoint demostrable, está
protegida por rol y por tenant, y está en el documento de alcance si cambió una regla de negocio.

## 14. Próximos pasos

1. Crear el esqueleto del repositorio (§15) y que `make dev` levante un «hola mundo» con dos roles.
2. Cerrar D9 (precio del preparador) y D7 (responsable del tratamiento): condicionan precios y contratos.
3. Búsqueda OEPM clase 41 y compra de `vinopo.es`.
4. Firma de cesión de derechos con el primer preparador.
5. Semilla con un temario real de 5 temas y 100 preguntas para probar F1–F2 con contenido de verdad.

## 15. Árbol del repositorio

```
winopo/
├── Makefile
├── README.md
├── .env.example
├── .gitignore
├── core/                        # Kotlin + Ktor
├── migrations/                  # SQL versionado, RLS incluido
├── contracts/                   # JSON Schema de la API y de la IA
├── infra/                       # docker-compose y despliegue
├── web/                         # Next.js: preparador + opositor
├── docs/                        # este plan y el alcance
└── tests/                       # pruebas de extremo a extremo
```

El detalle de cada carpeta está en [`esqueleto.md`](esqueleto.md).

