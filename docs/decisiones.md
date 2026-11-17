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
