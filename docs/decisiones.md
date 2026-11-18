# Decisiones

Un registro corto. Cada decisión dice **qué se decidió**, **por qué** y **qué se descartó**. Si una decisión
 cambia, se añade otra entrada; no se reescribe la historia.

---

## D1 · Un opositor, un preparador

**Decidido**: en v0 cada opositor pertenece a un único preparador (un tenant).

**Por qué**: simplifica el modelo de permisos, la facturación y el soporte. El opositor que cambia de preparador
se da de baja y se da de alta.

**Descartado**: pertenencia múltiple. Multiplica los casos límite (¿de quién es la corrección?, ¿quién paga?) sin
 resolver un problema que hoy nadie tiene.

> **Revisada el 17-nov-2026 (ver D12).** El opositor deja de «pertenecer» a un preparador: si va por su cuenta tiene
> un **espacio personal** de un solo miembro, y al vincularse es una `membership` de rol `opositor` dentro del tenant
> del preparador. Lo que se limita a uno es la **vinculación activa**, no la identidad. El motivo del cambio no es
> técnico: un opositor que prepara por su cuenta también es cliente, y con el modelo anterior no tenía dónde existir.

---

## D2 · RLS forzada, no opcional

**Decidido**: todas las tablas de negocio llevan `tenant_id` y política RLS con `FORCE ROW LEVEL SECURITY`. El rol
 de la aplicación **no** tiene `BYPASSRLS`.

**Por qué**: si un `where` se olvida en una consulta, la base sigue sin devolver datos de otro preparador. El
 aislamiento no depende de la disciplina del programador.

**Descartado**: filtrar solo en la capa de aplicación. Un `where tenant_id = ?` olvidado es una fuga silenciosa.

---

## D3 · El rol `winopo_app` se crea fuera de las migraciones

**Decidido**: `CREATE ROLE ... PASSWORD` vive en `infra/postgres/init.sql` (local) y en el aprovisionamiento de
 cada entorno. Las migraciones solo hacen `GRANT`.

**Por qué**: una contraseña escrita en `migrations/` acaba en el historial de git para siempre y hay que rotarla en
 todos los entornos a la vez.

**Descartado**: crear el rol en `0001_base.sql` con una clave por defecto.

---

## D4 · La sesión guarda el hash, no el token

**Decidido**: la tabla `sesion` almacena `token_hash` (SHA-256). El token en claro solo existe en la cookie.

**Por qué**: un volcado de la base (o un backup filtrado) no permite suplantar a nadie.

**Descartado**: guardar el token tal cual, "porque es una tabla interna".

---

## D5 · Dos políticas de arranque en `membership` y `sesion`

**Decidido**: además de la política por tenant, existen `membership_propia` (por `winopo.user_id`) y
 `sesion_por_token` (por `winopo.sesion_hash`).

**Por qué**: en el login todavía no se sabe a qué tenant pertenece quien llama. Sin estas dos políticas, el sistema
 no podría leer ni sus propias pertenencias ni validar una cookie: la RLS, bien puesta, lo bloquea todo.

**Descartado**: un rol de servicio con `BYPASSRLS` solo para el login. Sería un agujero permanente para resolver un
 caso puntual.

---

## D6 · `winopo.es` como dominio

**Decidido**: marca y dominio `winopo.es`; identidad visual pendiente en `docs/marca.md`.

**Pendiente**: comprobar que `vinopo.es` no se compra por error (typo habitual) y confirmar la delegación de DNS.

---

## D7 · Responsable del tratamiento

**Pendiente de decisión legal**: quién figura como responsable del tratamiento en la política de privacidad
 (¿el preparador, WinOpo, o corresponsables?). Afecta al texto RGPD y al contrato de encargo de tratamiento.
 Ver `docs/legal/rgpd.md`.

---

## D8 · Auditoría append-only por trigger

**Decidido**: `audit_log` rechaza `UPDATE` y `DELETE` con un trigger, no por convención.

**Por qué**: un registro de auditoría que se puede editar no es un registro de auditoría.

---

## D9 · Precio anclado a lo que el opositor ya paga

**Dato de mercado** (17-nov-2026): un preparador de oposiciones de Primaria cobra entre **95 y 200 €/mes** por
alumno; en preparaciones individuales con corrección exhaustiva, programación a medida y simulacros de defensa
sube a **300–400 €/mes**. Materiales aparte: 90–150 € por partes, ~300 € el paquete completo.

**Los dos datos son el mismo**: 150–200 €/mes × 9–10 meses de temporada = **1.350–2.000 €** por opositor y
temporada. La cifra de 1.500–2.000 € que dio el cliente para Audición y Lenguaje en Andalucía encaja con la
horquilla general: no es una excepción, es el mercado.

**Cómo se ancla el precio** (sustituye al «10 % de la facturación mensual», que estaba mal calculado):

1. **Opositor**: el plan completo no debe pasar del **15 %** de lo que ya paga por prepararse. Sobre 1.750 € por
temporada, el techo son ~260 €.
2. **Preparador**: la adhesión no debe pasar del **10 %** de lo que factura. Con 10 opositores a 1.750 €
   (17.500 € por temporada), el techo son 1.750 €; con 30 opositores (3.000–4.500 €/mes brutos, ~35.000 €), el
techo pasa de 3.500 €.
3. **Tribunal del Máster**: cada ensayo es una hora de preparador. El Máster tiene que cubrir esa hora con margen;
   si no, se vende a pérdida aunque el plan parezca caro.

**Propuesta, pendiente de su OK** (no se publica en el landing hasta que la firme):

| Plan | Precio/temporada | % de 1.750 € | Qué cubre el coste variable |
|---|---|---|---|
| Básico | 90 € | 5 % | Resúmenes y tests con IA |
| Pro | 160 € | 9 % | + maquetación (casi sin coste variable) |
| Máster | 250 € | 14 % | + 3–4 ensayos de tribunal a 25–30 €/hora |
| Adhesión preparador | 600 € | — | <4 % de 17.500 €; sube con tramos de alumnos |

**Y el precio de la maquetación, que es el escalón de Pro** (17-nov-2026):

| Trabajo encargado por fuera | Tarifa | Ejemplo real |
|---|---|---|
| Texto corrido, 200 páginas | 0,70–1,20 €/página | 140–240 € |
| Temario didáctico con tablas y esquemas | **1,30–3,00 €/página** | 260–600 € / 200 págs |
| Diseño editorial complejo | 3,50–6,00 €/página | 700–1.200 € / 200 págs |
| Portada y cubierta | 100–200 € aparte | — |
| Plantilla maestra sola | 150–400 € | — |
| Programación didáctica (60 págs) | precio cerrado | 150–250 € |

Un temario real de oposición (500–700 páginas) se va a **650–2.100 €** maquetado por fuera, y hay que repetirlo cada
convocatoria. Nuestro **Pro cuesta 160 €** e incluye el temario entero, regenerable al cambiar la convocatoria.

**El argumento comercial completo**: material suelto a 90–150 € por partes y ~300 € el paquete; maquetación a
650–2.100 € el temario. El plan Pro, que hace las dos cosas, cuesta 160 €. El ahorro no es marginal: es de varias
veces el precio del plan, y ahí está la conversión de Básico a Pro.

Fuentes: OpositaTest, CEN, El Aula de Javier, PreparaOposiciones, Milanuncios (Sevilla), CGTA Educación, Blauverd
Impressors, Maquetación de libros, Maquetadores.org, Regladetres.

---

## D10 · PBKDF2 del JDK en vez de Argon2id

El servidor de destino es ARM64. Argon2id exige un artefacto nativo; si el binario no coincide con la
 arquitectura, el arranque falla en producción y no en local. PBKDF2-HMAC-SHA256 con 210 000 iteraciones
 viene en el JDK, no necesita compilación y es verificable en cualquier máquina.

Se revisa si en algun momento se pasa a x86 o si el coste de PBKDF2 se vuelve un problema de latencia.
 Mientras tanto, un artefacto nativo menos es un despliegue menos que se rompe.

---

## D11 · Maquetación con WeasyPrint en un contenedor aparte

El PDF del temario se genera desde HTML + CSS con WeasyPrint, en un contenedor propio (`maquetador`), no dentro
 del core. Motivos: (1) el mismo lenguaje de estilos que la web, una sola plantilla; (2) LaTeX en ARM64 arrastra
 cientos de megabytes; (3) aislar Python evita que el core dependa de librerías del sistema.

El PDF es un derivado reproducible de `tema_version` + hash de plantilla. No se edita a mano.

---

## D12 · Un tenant por preparador; preparador y opositor son roles

**Decidido** (17-nov-2026, corregido el mismo día): el `tenant` es **uno por preparador** —su temario, sus alumnos,
su frontera RLS—. Preparador y opositor son **roles** (`membership.rol`) dentro de él, no dos tipos de espacio en
paralelo. La relación entre un opositor y un preparador es, literalmente, **una `membership` de rol `opositor` activa**
en el tenant de ese preparador: no hay tabla de vinculación aparte.

**Por qué**: el opositor que prepara por su cuenta es un cliente completo, no un usuario a la espera de que alguien
lo dé de alta. Sube sus apuntes, maqueta, hace tests, entrega supuestos y ensaya el oral. Para que exista sin romper
el aislamiento, es dueño de un **espacio personal** de un solo miembro (`tenant.tipo = 'personal'`), y ahí vive su
material; en cuanto se vincula, trabaja **dentro del tenant del preparador** con su `membership` y cambia de contexto
como cualquier usuario. Nunca lee cross-tenant.

**Cómo se mantiene el aislamiento**: `tenant_id` sigue en todas las tablas del negocio y la RLS no se relaja. Lo que
cambia es que el contexto puede ser el espacio personal del opositor. Toda lectura que cruce tenants vive en el
ámbito `plataforma`, con tablas propias y sin datos de alumnos (D18).

**Descartado**: (a) **dos tipos de tenant en paralelo** (`preparador` / `opositor`): obligaría al opositor a leer el
temario del preparador en cada petición, rompe el fail-closed y tumba el test de aceptación de F0 (404 cross-tenant);
(b) el «tenant cero», un preparador ficticio con los opositores autónomos dentro: contamina todos los informes y
acaba en fugas cuando alguien filtra por tipo.

**Consecuencia de producto**: un plan del opositor y una cuota del preparador; ninguna comisión (D13, D19).

> **Nota de corrección (17-nov-2026):** la primera versión de D12 decía «dos tipos de tenant» y una tabla
> `vinculacion`. Era un error de diseño. Esta nota se queda para que no se reintroduzca.

---

## D13 · Todo es de pago, y el opositor escala por plan

**Decidido** (17-nov-2026, corregido el mismo día): **no hay plan gratuito**, y esto no es un marketplace.
Los planes son una escalera de producto: lo que sube de nivel es lo que la plataforma hace con el material del
opositor.

| | Temario + tests | Resúmenes IA | Maquetación | Corrección IA | Corrección humana |
|---|---|---|---|---|---|
| **Básico** | Sí | Sí | — | — | — |
| **Pro** | Sí | Sí | Sí (cuota de páginas/mes) | — | — |
| **Máster** | Sí | Sí | Sí (cuota mayor) | Sí (límite/mes) | Del preparador |

El Máster no repite la maquetación: lo que añade de verdad es **corrección**, primero de la IA y después humana. La
maquetación es el escalón de Pro, y es lo que hace que alguien suba de nivel.

**A quién se le cobra**: a los dos, y por cosas distintas (D19). Al preparador, la herramienta con la que produce; al
opositor, el acceso a lo que consume. El material que produce el preparador no se le factura otra vez al alumno.

**El tribunal del Máster no es IA**: lo hace un preparador adherido, que escucha, repregunta y firma el informe. Por
eso el Máster no se puede vender sin límite: cada ensayo consume horas de una persona. El plan lleva un número
cerrado de ensayos por temporada y WinOpo **paga al preparador** por cada uno.

**La única relación entre los dos lados**: el opositor puede contratar **clases particulares** con un preparador
adherido a WinOpo (D17). No hay catálogo de material, ni comisión, ni valoraciones, ni carrito.

**Quién paga a quién**:

| Concepto | Quién paga |
|---|---|
| Plan del opositor | El opositor, a WinOpo |
| Adhesión del preparador | El preparador, a WinOpo |
| Ensayos de tribunal del Máster | Van en el plan del opositor; WinOpo liquida al preparador |
| Clase particular | La paga el opositor al preparador, fuera de la plataforma |

**Descartado**: el nivel gratuito —quien no paga consume IA, almacenamiento y tribunal humano sin ingresos— y el
modelo de dos lados con comisión por transacción.

---

## D14 · Venta de material dentro de la plataforma

**Decidido** (17-nov-2026): **fuera de v1**. El material se produce y se exporta; no hay escaparate ni cobro entre
usuarios.

**La confusión que conviene cortar**: D13 (planes Básico/Pro/Máster) resuelve cómo **compra** el opositor, no cómo
**vende**. Que alguien pague un plan no lo convierte en vendedor dentro de la plataforma.

**Por qué fuera**: vender entre usuarios exige comisión, facturación al comprador, resolución de disputas y
responsabilidad sobre material ajeno — posiblemente copiado de una editorial—. Es la diferencia entre un producto
que se puede lanzar en F2.5 y un marketplace que necesita equipo legal.

**Revisable**: si el material de los opositores acaba siendo un atractivo real, se reabre con comisión y contrato
propio, no de tapadillo.

---

## D15 · Tribunal simulado con audio grabado

**Recomendado**: ensayo con audio grabado + transcripción + evaluación, no conversación en tiempo real.

**Por qué**: es más barato (una subida, una transcripción, una evaluación), más auditable (queda el audio y el
informe con `modelo` y `prompt_version`) y más justo con quien tiene mala conexión. El tiempo real se reserva para
cuando haya preparadores que quieran tutelar el oral en directo, que es otro producto.

**Límite no negociable**: el informe **no es una nota oficial** y se etiqueta como simulación. Puntúa conducta
(estructura, tiempo, claridad) y no capacidad de la persona.

---

## D16 · Registro abierto para el opositor; alta guiada para el preparador

**Decidido** (17-nov-2026): el opositor se registra solo, con su correo y verificación, y el sistema le crea su
**espacio personal** (`tenant.tipo = 'personal'`, un solo miembro) y su `membership` en la misma transacción. Sin
invitación, sin lista de espera y sin tener que pedir acceso, pero **sin plan no se abre ningún módulo** (D13).

**Qué implica técnicamente**: una ruta `/registro` que **hoy no existe** (solo hay `/login`), verificación de correo
obligatoria, creación de `tenant` + `membership` en la misma transacción, y límite de intentos más captcha, porque
cada cuenta nueva puede gastar dinero en IA desde el primer minuto.

**El preparador no**: entra por alta guiada. Son tres, firman la cesión de derechos antes de subir nada y alguien
revisa lo que publican. Abrir el alta a cualquiera convierte el catálogo en un vertedero de material copiado y nos
pone a responder por él.

---

## D17 · Preparador adherido y clases particulares, sin marketplace

**Decidido** (17-nov-2026): el preparador que quiera dar clase a opositores de WinOpo **se adhiere**. La adhesión es
lo que WinOpo cobra al preparador; a cambio aparece en el listado y puede recibir solicitudes de clase particular.

**Lo que es**: una conexión. El opositor ve quién da su materia, pide clase y se entiende con él.

**Lo que no es**: un marketplace. Sin cobro dentro, sin comisión por clase, sin valoraciones públicas, sin carrito y
sin devoluciones gestionadas por nosotros.

**Por qué**: cobrar por cuenta ajena exige KYC, facturación por tercero, IVA de otro, disputas y responsabilidad
sobre una clase que no damos. Eso es otro producto y otro equipo legal. Aquí WinOpo cobra por su herramienta, no
por el trabajo del preparador.

**Excepción, y es la única**: el tribunal del plan Máster. Ahí el preparador actúa **para WinOpo**, no para el
opositor, y WinOpo le liquida el ensayo. Es un coste del plan, no una venta.

**Revisable**: si algún día se quiere cobrar la clase dentro, se reabre esta decisión con contrato y asesoría. No se
hace de tapadillo.

---

## D18 · Tres ámbitos de datos, no dos tenants

**Decidido** (17-nov-2026): el aislamiento sigue siendo el `tenant` del preparador —RLS forzada, fail-closed y 404
cross-tenant como test de aceptación de F0—. Preparador y opositor son **roles**, no tipos de tenant (D12).

| Ámbito | Contiene | Quién lee | Regla |
|---|---|---|---|
| `tenant` | Temario, tests, entregas, correcciones, progreso | Los miembros de ese tenant | RLS forzada: sin contexto, cero filas |
| `plataforma` | Catálogo de preparadores adheridos, identidad de usuario, solicitudes de plaza, cuotas | Cualquiera, si el perfil es opt-in, o el propio usuario | Tablas propias y políticas explícitas; **nunca** datos de alumnos |
| `admin` | Censo completo, soporte, auditoría | WinOpo | Rol de plataforma, con `audit_log` |

**Lo que el preparador ve de un opositor**: su membership en **su** tenant. Nunca el censo global. El censo entero
es ámbito `admin`, y se consulta con motivo.

**Por qué tablas propias y no relajar la RLS**: una política del tipo «si el recurso es público, deja pasar» acaba
aplicándose a algo que no era público. El ámbito de plataforma no comparte tabla con el de negocio.

---

## D19 · A quién se cobra: a los dos, por cosas distintas

**Decidido** (17-nov-2026): WinOpo cobra **al preparador y al opositor**, y esto sigue sin ser un marketplace de
pagos.

| Quién | Por qué paga | Cómo |
|---|---|---|
| **Preparador** | Herramienta profesional: temas ya maquetados y versionados, corrección con IA, vídeo IA para sus alumnos, bibliografía vigilada, estadísticas y tribunal | Cuota por temporada, por tramos de alumnos |
| **Opositor** | Su plan: temario propio, resúmenes, tests, maquetación, corrección IA y tribunal | Básico / Pro / Máster por temporada (D13) |

**Dos modalidades para el alumno de un preparador**, y las dos acaban en WinOpo:

1. El alumno paga su plan, con el registro abierto de D16.
2. El preparador **compra plazas** para sus alumnos y las incluye en su precio. Mismo `client_reference_id =
   membership_id` que ya tiene F5, sin Stripe Connect.

**Por qué no es doble cobro**: al preparador se le cobra la herramienta con la que produce; al alumno, el acceso a lo
que consume. Lo que produce el preparador no se le factura otra vez al alumno (D13).

**Descartado**: Stripe Connect, comisión por transacción y WinOpo como *merchant of record* del trabajo ajeno. Eso
trae KYC, payouts, IVA de otro y disputas, y es otro producto.

**Cómo se sostiene sin cobrar por contacto**: la cuota es mensual por tramos, no por lead. Cobrar la presentación
sería el incentivo máximo para que preparador y opositor se fuguen a WhatsApp.

---

## D20 · Resúmenes: un derivado cacheado por versión del tema

**Decidido** (17-nov-2026): el resumen se genera **una vez por `tema_version`**, se cachea por
`tema_version + prompt_version + modelo`, lo **revisa y publica el preparador** y lo consumen todos sus alumnos.
Coste marginal ≈ 0.

**Si se genera por alumno** en el plan Básico, el margen se va en tokens y el mismo tema se resume veinte veces
igual. El resumen es un derivado del temario, no un servicio personalizado.

**Para el opositor libre** se genera sobre **su** material y se etiqueta «generado por IA, no verificado»: no hay
preparador que lo firme y no puede presentarse como material revisado.

**Consecuencia comercial**: el resumen no es palanca de precio, porque cuesta casi nada. Las palancas son la
maquetación (Pro) y la corrección (Máster).

---

## D21 · El nexo termina en una membership, sin chat

**Decidido** (17-nov-2026): el descubrimiento es `perfil público opt-in → solicitud de plaza con mensaje corto → el
preparador acepta → membership en su tenant`. A partir de ahí todo es el producto que ya existe: temario versionado,
tests y correcciones auditables.

- **Sin chat en v0**: moderación, abuso, RGPD y notificaciones son otro producto. Solicitud con mensaje corto y
  datos de contacto ocultos hasta que el preparador acepta.
- Todo el recorrido queda en `audit_log`.
- **D1 sigue vivo**: descubrir es libre, comprometerse es uno. Cambiar de preparador es cerrar una vinculación y
  abrir otra; el historial del opositor no se migra.
- **Fase F6**, no antes: con tres preparadores y pocos alumnos el nexo no tiene liquidez. Primero tienen que traer a
  sus alumnos y haber temarios que enseñar.

**Anti-fuga, y es deliberado**: no se cobra por contacto; se cobra por la herramienta y por la permanencia (temario
ya maquetado y versionado, histórico de correcciones defendible, bibliografía vigilada). Eso no se lo lleva nadie a
WhatsApp. Un preparador con muchas solicitudes y pocas memberships es una **señal comercial** —llamada—, no
policial —bloqueo—.

---

## D22 · Maquetación a escala: cola de render y cuota de páginas

**Problema** (17-nov-2026): con tres preparadores, WeasyPrint a demanda cabe en 4 GB. Con opositores maquetando su
propio temario, no: el mismo servidor atiende N renders concurrentes de 500–700 páginas y el proceso se lleva la
memoria por delante.

**Decidido**:

1. El render va a **cola con un trabajador aparte**, nunca dentro de la petición web.
2. Cada plan lleva **cuota de páginas al mes** (Pro y Máster). Sin cuota, alguien maqueta gratis lo que no paga y
   tumba el servicio de los demás.
3. Límite de concurrencia explícito; si la cola crece, se avisa al usuario con la posición, no se deja la petición
   colgada.

**Pendiente de medir**: memoria real por render de 700 páginas en el servidor de destino. Si no cabe, la salida es
un trabajador separado con su propio límite —no «subir el servidor y esperar»—.

---

## D23 · Bibliografía vigilada: se vende aviso, no garantía

**Decidido** (17-nov-2026): un job revisa BOE y BOJA y marca el `tema_fuente` cuya norma ha cambiado, y la versión
del tema pasa a *fuente desactualizada*. El preparador ve el aviso y decide si toca el tema.

**Qué se vende**: el **aviso**. No se promete que el temario esté siempre actualizado: si se promete actualización y
falla un cambio de norma, el problema legal es de WinOpo y de nadie más.

**Por qué es el mejor argumento anti-fuga**: es lo más difícil de copiar a mano cada convocatoria y lo que un
preparador solo no puede mantener con 25 temas y tres boletines.

---

## D24 · La bolsa de ensayos y la matriz de tarifas

**Decidido** (18-nov-2026): el tribunal simulado del plan Máster se escribe en tres migraciones —
`0015_especialidad_tarifa`, `0016_bolsa_ensayo` y `0017_liquidacion_evaluador` —, cada una con su prueba ejecutable en
`tests/db/` y ejecutadas contra un PostgreSQL limpio por `make test-db`. La especialidad deja de ser texto libre: es una
fila del catálogo de plataforma `especialidad`, única fuente del grupo (A1/A2/C1/C2), y el precio sale de una matriz
`tipo × grupo × modalidad` en `tarifa`. Cinco tablas, doce políticas y dos funciones `SECURITY DEFINER`.

**Fail-closed**: sin tarifa vigente no se vende. `fuente` es `NOT NULL`, así que una tarifa sin documentación (tres
tarifas reales de preparadores, con fecha) no entra; `tarifa_vigente()` devuelve cero filas antes que inventarse un
precio. Una tarifa tampoco se edita ni se borra: se cierra con `vigente_hasta` y se abre otra.

**Una sola tarifa vigente por producto**: `exclude using gist (tipo with =, grupo with =, modalidad with =,
daterange(vigente_desde, vigente_hasta, '[)') with &&)`. Dos precios solapados son un error de la base, no del código
que los inserta; `btree_gist` entra en 0015 justo por eso.

**Los importes se congelan al comprar**: `ensayo_tribunal` copia `tarifa_id`, `cobrado_neto_cents` y
`pago_evaluador_cents`, y un trigger impide que cambien después. Subir una tarifa no reescribe lo que ya se cobró ni lo
que ya se debe al evaluador. Todo en céntimos enteros y **netos de IVA**: el IVA se calcula en el checkout, no se
guarda. El plan no cobra (`origen = 'plan'` con `cobrado_neto_cents = 0`); una compra siempre deja `stripe_ref`.

**La excepción al aislamiento, y por qué se sostiene**: D18 exige que toda lectura cruzada viva en el ámbito
`plataforma`, con tablas propias y sin datos de alumnos. El ensayo ciego no puede cumplirlo: el evaluador tiene que
leer una fila de negocio de otro espacio o no hay tribunal. `ensayo_tribunal` es la única tabla del negocio con una
política que no filtra por `winopo_tenant()` sino por `evaluador_membership_id = winopo_membership()`: ve los ensayos
que lleva asignados, ni uno más, y su política de escritura no le deja salir de `asignado`, `celebrado` e `informado`.
La migración lo dice dentro del propio `create policy` para que nadie lo «arregle».

**Nada de `SECURITY DEFINER` para asignar evaluador.** Con `FORCE ROW LEVEL SECURITY` una función no ve más filas que
quien la llama, así que asignar es política del staff (`winopo_es_staff()`) y el evaluador solo mueve lo que ya lleva.
Las dos funciones que sí son `SECURITY DEFINER` no exponen filas: `cerrar_ensayos_vencidos()` devuelve cuántos cerró y
`evaluadores_activos(uuid)` un entero.

**Por qué el cierre a 72 h es función y no política.** En PostgreSQL, un `UPDATE` aplica además las políticas de
`SELECT`: una política de `UPDATE` sin identidad de sesión no vería ninguna fila, y darle una de `SELECT` equivalente
abriría a la aplicación las rúbricas de todos los tenants. El barrido va por función `SECURITY DEFINER` con
`search_path` fijo, se le quita y se le devuelve el contexto de sesión, y no devuelve ninguna fila.

**`WITH CHECK` explícito en toda política de escritura.** Si falta, PostgreSQL reutiliza el `USING` sobre la fila nueva
y transiciones legítimas — el evaluador pasando a `informado` — fallan sin decir por qué.

**Pendiente, y no se resuelve escribiendo SQL**:

- el tope del 25 % del neto del ensayo choca con la tarifa de 30 € que maneja el estudio de precios (ronda el 30 %);
  mientras no se firme cuál de las dos cifras manda, el tope no está en el esquema y lo vigila `tests/db/0015_tarifa.sql`;
- quién cobra en `modalidad = 'propio'`: hoy `pago_evaluador_cents` es `NULL` porque evalúa el preparador del alumno;
- la retención y el IVA del pago al evaluador: `0017_liquidacion_evaluador` queda como especificación hasta que el
  gestor conteste;
- con qué rol corre el job de liquidación: bajo `FORCE RLS` un proceso sin identidad de sesión no ve ninguna fila, el
  mismo problema que el cierre a 72 h.

**Asumido**: el catálogo (`especialidad`, `tarifa`) lo escribe el operador aplicando migraciones como superusuario;
`winopo_app` solo lee, y el `REVOKE` de 0015 es defensa en profundidad sobre el `GRANT` por defecto de
`infra/postgres/init.sql`. Es la misma consecuencia de D3 y de `0002_identidad`: nadie crea tenants desde la aplicación.

**Descartado**: la especialidad como texto libre —dos espacios escribiendo «Administrativo C1» y «administrativo c1» no
casan con la tarifa—, el pago al evaluador por Stripe (es un proveedor: necesita factura con retención, no un payout) y
un rol de servicio con `BYPASSRLS` para el barrido o la liquidación.

