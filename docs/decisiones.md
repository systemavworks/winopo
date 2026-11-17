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

> **Revisada el 17-nov-2026 (ver D12).** El opositor deja de «pertenecer» a un preparador: es un **tenant propio**.
> Lo que se limita a uno es la **vinculación activa**, no la identidad. El motivo del cambio no es técnico: un
> opositor que prepara por su cuenta también es cliente, y con el modelo anterior no tenía dónde existir.

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

## D9 · Precio del preparador por opositor

**Pendiente**: tarifa por opositor activo y qué incluye (correcciones IA, almacenamiento de vídeo). Sin esto no se
 puede cerrar la página de precios ni el modelo de Stripe.

## D10 · PBKDF2 del JDK en vez de Argon2id

El servidor de destino es ARM64. Argon2id exige un artefacto nativo; si el binario no coincide con la
 arquitectura, el arranque falla en producción y no en local. PBKDF2-HMAC-SHA256 con 210 000 iteraciones
 viene en el JDK, no necesita compilación y es verificable en cualquier máquina.

Se revisa si en algun momento se pasa a x86 o si el coste de PBKDF2 se vuelve un problema de latencia.
 Mientras tanto, un artefacto nativo menos es un despliegue menos que se rompe.

## D11 · Maquetación con WeasyPrint en un contenedor aparte

El PDF del temario se genera desde HTML + CSS con WeasyPrint, en un contenedor propio (`maquetador`), no dentro
 del core. Motivos: (1) el mismo lenguaje de estilos que la web, una sola plantilla; (2) LaTeX en ARM64 arrastra
 cientos de megabytes; (3) aislar Python evita que el core dependa de librerías del sistema.

El PDF es un derivado reproducible de `tema_version` + hash de plantilla. No se edita a mano.

---

## D12 · Dos tipos de tenant: preparador y opositor

**Decidido** (17-nov-2026): el `tenant` tiene un tipo, `preparador` u `opositor`. Todo usuario tiene su propio
espacio. La relación entre ambos es una **vinculación opcional** (`vinculacion`), con como mucho una activa por
opositor en v1.

**Por qué**: el opositor que prepara por su cuenta es un cliente completo, no un usuario a la espera de que alguien
lo dé de alta. Sube sus apuntes, maqueta, hace tests, entrega supuestos y ensaya el oral. Si el modelo lo obliga a
depender de un preparador, ese cliente no puede pagar ni existir, y el producto se queda con la mitad del mercado.

**Cómo se mantiene el aislamiento**: `tenant_id` sigue en todas las tablas y la RLS no se relaja. Lo único que
cambia es que el contexto de tenant puede ser de tipo `opositor`. Las tres lecturas cruzadas permitidas están
enumeradas en `docs/alcance-v0.md` §3.

**Descartado**: un único tipo de tenant con un rol «opositor autónomo» dentro del espacio de un preparador ficticio
(el «tenant cero»). Es un parche que contamina todos los informes y acaba en fugas cuando alguien filtra por tipo.

**Consecuencia de producto**: dos escalas de precio (§4 del alcance) y dos circuitos de cobro (D13).

---

## D13 · El opositor paga su propio plan: Básico, Pro y Master

**Decidido** (17-nov-2026): el opositor contrata un plan propio por temporada, no un pago por uso ni una
suscripción mensual. Tres niveles, y cada uno desbloquea módulos completos:

| Plan | Qué desbloquea |
|---|---|
| **Básico** | Temario y apuntes propios maquetados en PDF, tests con corrección explicada, guías y plan de estudio |
| **Pro** | Todo lo del Básico + supuestos con rúbrica, corrección asistida por IA y **tribunal simulado** |
| **Master** | Todo lo del Pro + vídeo y animaciones de repaso, simulacro completo y tope de ensayos ampliado |

Los nombres son provisionales («Básico / Pro / Master» se cambia en una tarde); la escalera de tres niveles y lo
que desbloquea cada uno, no.

**Lo que no se vende**: la vinculación con un preparador **no es un módulo de pago**. Está disponible en los tres
planes, porque el material que aporta el preparador ya lo paga él. Si su preparador cubre un módulo, el opositor no
lo paga dos veces: su plan se queda en lo que el preparador no da.

**Tope de uso por plan**: cada nivel lleva un máximo de correcciones y de ensayos de oral por temporada. La IA y el
tribunal son las dos piezas con coste variable; sin tope, el plan Master se vende a pérdida. Las cifras se cierran
con D9.

**Por qué no se puede improvisar**: facturación a consumidor final exige datos fiscales, derecho de desistimiento
(art. 103.m TRLGDCU) y soporte de reclamaciones. No es «el mismo Stripe con otro precio».

---

## D16 · Registro abierto para el opositor; alta guiada para el preparador

**Decidido** (17-nov-2026): el opositor se registra solo, con su correo y verificación, y el sistema le crea su
tenant `opositor` con su `membership`. Sin invitación, sin lista de espera y sin tener que pedir acceso.

**Qué implica técnicamente**: una ruta `/registro` que **hoy no existe** (solo hay `/login`), verificación de correo
obligatoria, creación de `tenant` + `membership` en la misma transacción, y límite de intentos más captcha, porque
cada cuenta nueva puede gastar dinero en IA desde el primer minuto.

**El preparador no**: entra por alta guiada. Son tres, firman la cesión de derechos antes de subir nada y alguien
revisa lo que publican. Abrir el alta a cualquiera convierte el catálogo en un vertedero de material copiado y nos
pone a responder por él.

---

## D14 · Venta de material dentro de la plataforma

**Decidido** (17-nov-2026): **fuera de v1**. El material se produce y se exporta; no hay escaparate ni cobro entre
usuarios.

**La confusión que conviene cortar**: D13 (planes Básico/Pro/Master) resuelve cómo **compra** el opositor, no cómo
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
