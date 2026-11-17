# Consentimiento informado y renuncia al desistimiento · v1

> Texto de trabajo. Se muestra **antes** de la primera compra y se guarda la versión aceptada (`v1`) con fecha y
> usuario. Si el texto cambia, sube la versión; nadie queda cubierto por un texto que no leyó.

## Motivo

El servicio es contenido digital de acceso inmediato. El artículo 103.m) del Texto Refundido de la Ley General
 para la Defensa de los Consumidores y Usuarios excluye el derecho de desistimiento cuando el contenido digital se
 ha empezado a ejecutar con consentimiento expreso y con conocimiento de la pérdida del derecho.

Sin este consentimiento, la compra tendría 14 días de desistimiento aunque el opositor ya haya consumido el
 contenido.

## Texto que ve la persona

---

Al contratar, accedes de inmediato al contenido digital de WinOpo (temario, tests y correcciones).

Al marcar esta casilla declaras que:

1. Consientes que el servicio empiece **de inmediato**, sin esperar los 14 días naturales.
2. Sabes que, al empezar de inmediato, **pierdes el derecho de desistimiento** sobre la parte ya consumida.
3. Si desistes después, se te devolverá la parte proporcional del servicio **no** consumido, según lo explicado en
   las condiciones de contratación.

No marcarlo no impide comprar: en ese caso el contenido no se desbloquea hasta que pasen los 14 días.

[ ] He leído y acepto.

---

## Registro que hay que guardar

| Campo | Ejemplo |
|---|---|
| `user_id` | uuid |
| `version_texto` | `v1` |
| `aceptado_en` | ISO 8601 con zona |
| `ip` | dirección de la petición |
| `user_agent` | cadena recibida |
| `compra_id` | referencia de Stripe |

Sin este registro no se puede demostrar el consentimiento, y sin prueba el consentimiento no sirve.

## Pendiente

- [ ] Redacción final revisada.
- [ ] Decidir la política de devolución de la parte no consumida (importe, cálculo, plazo).
- [ ] Enlazar desde el checkout de Stripe, no solo desde la web.
