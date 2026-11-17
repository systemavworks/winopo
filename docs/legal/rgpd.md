# RGPD · notas de trabajo

> **Esto no es asesoramiento jurídico.** Es la lista de lo que hay que tener resuelto y quién lo firma.

## 1. Papeles y quién es quién

| Concepto | Quién |
|---|---|
| Responsable del tratamiento | **Pendiente (D7)** |
| Encargado del tratamiento | Winopo (alojamiento, IA, vídeo) si el responsable es el preparador |
| Subencargados | Hetzner (servidor), Cloudflare R2 (vídeo), proveedor de IA, Stripe (pagos) |

Mientras D7 no esté cerrado, la política de privacidad **no se publica**.

## 2. Qué datos se tratan

- **Identificación**: nombre, correo, contraseña (hash PBKDF2; nunca en claro).
- **Actividad**: tests, respuestas, entregas, correcciones, notas.
- **Contenido del opositor**: textos de supuestos. Pueden incluir datos personales por descuido.
- **Vídeo**: solo si el preparador lo activa y con consentimiento explícito y separado.
- **Pago**: gestionado por Stripe. Winopo no almacena números de tarjeta.

## 3. Base jurídica

- Ejecución de contrato: cuenta, temario, correcciones.
- Consentimiento explícito: vídeo del opositor, comunicaciones comerciales.
- Interés legítimo: seguridad, prevención de fraude, registros de auditoría.

## 4. Plazos

| Dato | Plazo |
|---|---|
| Cuenta activa | Mientras dure la relación |
| Entregas y correcciones | Mientras dure la relación + 3 años (posible reclamación) |
| Vídeo | 90 días desde la corrección, o antes si se pide |
| Logs técnicos | 90 días |
| Registro de auditoría | 3 años (integridad, no contenido sensible) |

## 5. Derechos

Acceso, rectificación, supresión, oposición, portabilidad y limitación. Canal: correo de privacidad publicado en la
 web. Plazo de respuesta: un mes.

**Supresión real, no lógica**: al borrar una cuenta se anonimiza `app_user` y se borran entregas y vídeos. Queda el
 `audit_log` sin datos personales.

## 6. IA

- Se envía al proveedor **solo el texto de la entrega y el enunciado**. Nunca el correo ni el nombre.
- No se usa para entrenar modelos (verificar en el contrato del proveedor y dejarlo por escrito).
- Se registra modelo y `prompt_version` en cada corrección.
- El opositor debe saber, antes de entregar, que su texto se envía a un tercero.

## 7. Lista de comprobación antes de abrir al público

- [ ] D7 decidido y política de privacidad revisada.
- [ ] Contrato de encargo de tratamiento con cada preparador.
- [ ] Registro de actividades de tratamiento (art. 30).
- [ ] Consentimiento de vídeo separado del resto.
- [ ] Procedimiento de brecha de seguridad (72 h) escrito en `docs/runbooks/`.
- [ ] Backup cifrado y restauración probada.
