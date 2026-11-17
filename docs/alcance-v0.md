# WinOpo · alcance v0

**Estado**: borrador de trabajo · **Fecha**: 17-nov-2026 · **Cliente**: 3 formadores · **Nicho**: oposiciones de
Maestro de Infantil y Primaria, Andalucía · **Dominio**: `winopo.es` (registrado 17-nov-2026)

> Producto separado de Billka: otro público, otros datos, otra marca, otro repositorio. No comparte base de datos
> ni despliegue.

## 1. Qué es

Una plataforma donde un **preparador** publica su temario, sus tests y sus supuestos, y sus **opositores** estudian,
se examinan y reciben corrección con criterios explícitos. La plataforma pone la herramienta; el preparador pone el
contenido y la autoridad pedagógica.

**Qué no es**, y conviene escribirlo antes de diseñar nada:

- No es una academia: no hay profesores propios en v1.
- No es un marketplace abierto: los preparadores los damos de alta nosotros, uno a uno.
- No sustituye al preparador: la IA **nunca** fija la clave de un test ni la nota final.
- No aloja libros de editorial: solo enlaces y material propio del preparador con cesión firmada.

## 2. Las dos caras, un solo dataset

| | Preparador | Opositor |
|---|---|---|
| Ve | Sus grupos, su temario, entregas, estadísticas por tema | Su temario, sus tests, sus notas, su progreso |
| Hace | Publica y versiona temario, corrige, programa tests | Estudia, hace tests, entrega supuestos |
| Nunca | Ve datos de otro preparador | Ve temario no publicado |

Son **dos shells de interfaz sobre un único backend y una única base de datos**. Dos rutas, dos menús, dos
permisos; ni dos productos ni dos bases. El error caro aquí es duplicar el modelo de datos «porque son públicos
distintos»: el dato es el mismo y cambia quién lo mira.

## 3. Aislamiento por preparador

Cada preparador es un **tenant**. Toda tabla con `tenant_id` lleva RLS forzado, como en Billka: sin contexto de
tenant no se ve una fila. Un preparador no puede, ni por error de código, leer el temario de otro.

El opositor pertenece a **un** preparador en v1 (relación 1:1). Cambiar de preparador es un alta nueva, no una
migración de historial.

## 4. Módulos y comercialización

Se venden por **módulo de oposición** y por **temporada** (septiembre–mayo), no por suscripción mensual continua:

| Nivel | Incluye |
|---|---|
| Base | Temario versionado, **PDF maquetado** y tests con clave fija |
| + IA | Supuestos corregidos por IA con rúbrica, nunca nota final |
| + Preparador | Corrección humana y tutoría |
| Curso completo | Todo lo anterior + vídeo |

Regla de precio: **el software no puede pasar del 10 % de lo que el preparador factura por alumno**. Si el
preparador cobra 60 €/mes por alumno, el módulo no puede costar 6 €/mes. Falta el dato real del preparador para
fijar tarifas (D9).

## 5. Reglas de IA (no negociables)

1. La IA **propone**; el humano **decide**. Ninguna clave de test la fija un modelo.
2. Toda corrección guarda `corregido_por`: `ia`, `preparador` o `validado`.
3. Toda corrección guarda `prompt_version` y `modelo`.
4. Todo material generado se etiqueta con la versión de temario de la que salió.
5. Un supuesto corregido por IA **no cuenta** para la nota si el preparador no lo valida.
6. El prompt de corrección publica su rúbrica: qué puntúa, cuánto y con qué tolerancia.

Sin 2, 3 y 4 el sistema no es auditable y el preparador no puede defender una nota ante un alumno.

## 6. Vídeo

Vídeo = **voz sintética + diapositivas**, no avatar. Cuesta céntimos por vídeo, se rehace en minutos cuando cambia
el tema y no envejece con la cara de nadie. Se guarda en R2 con la versión de temario y el hash del guion; si el
temario sube de versión, el vídeo queda marcado como desactualizado, no se borra.

La demo de 3 semanas **no incluye** vídeo ni corrección de supuestos por IA: son las dos piezas caras y las dos que
más ruido generan si el alumno aún no confía.

## 7. Propiedad intelectual y fuentes

| Material | Se puede | No se puede |
|---|---|---|
| Normativa oficial (BOE, BOJA) | Alojar y citar | — |
| Apuntes del preparador | Alojar **con cesión firmada** | Alojar sin contrato |
| Libros de editorial | Enlazar y citar | Alojar, escanear, resumir capítulo a capítulo |
| Tests de academia ajena | Nada | Copiar el enunciado |

El temario se versiona (`temario_version`) y cada tema cita su fuente. Una convocatoria nueva abre versión nueva;
no se sobrescribe la anterior, porque el opositor que repite necesita su histórico.

### 7.1 Maquetación: el trabajo que nadie quiere hacer

Observación de campo (17-nov-2026): muchos preparadores y opositores tienen **el contenido pendiente de maquetar**.
El material existe en Word, en escaneos o en fotos; lo que no existe es un documento que se pueda estudiar: portada,
índice paginado, numeración de epígrafes, tablas que no se salgan de la página.

WinOpo lo trata como parte del producto, no como un extra:

| Pieza | Decisión |
|---|---|
| Entrada | DOCX, Markdown o PDF con texto |
| Normalización | Markdown propio (`winopo-md`), sin formato propietario |
| Salida | PDF reproducible desde la versión del tema + hash de plantilla |
| Lo que se automatiza | Portada, índice, paginación, numeración, encabezados, avisos de calidad |
| Lo que no | Diseño libre, edición WYSIWYG, criterio editorial |

Regla: **la maquetación no inventa contenido**. Si un epígrafe no existe en el texto, no aparece en el PDF. Y el PDF
es un derivado: se regenera, nunca se edita a mano, porque un PDF editado a mano rompe la trazabilidad de la versión.

Complementa a §7 y no lo sustituye: maquetar no da derechos sobre el material. Sigue haciendo falta la cesión
firmada para alojarlo.

## 8. El diferencial: corrección con rúbrica explícita

Los competidores ya tienen tests con estadísticas. Lo que no hay, o casi no hay:

1. Corrección de supuestos con **rúbrica publicada** (puntos por apartado, tolerancias, penalizaciones).
2. Trazabilidad de quién corrigió: IA, preparador o validado.
3. Temario **versionado** con fuentes citadas y vídeo atado a la versión.
4. Las dos caras (preparador y opositor) sobre **el mismo dataset**, no dos herramientas pegadas con un Excel en
   medio.

Si el producto no hace 1 y 2, es otro simulador de tests y compite por precio. Eso hay que decidirlo antes de
escribir código, no después.

## 9. Legal y datos

| # | Tema | Estado |
|---|---|---|
| D2 | Acceso al módulo hasta 31-may | Pendiente |
| D3 | Renuncia al desistimiento (art. 103.m TRLGDCU) con clic en checkout | **Obligatorio antes de vender** |
| D4 | IVA 21 % o exención de enseñanza | Consultar asesor |
| D5 | Precio de renovación para quien repite | Pendiente |
| D7 | Responsable del tratamiento: ¿preparador o plataforma? | Pendiente |

D7 condiciona el contrato, el aviso legal y el encargado de tratamiento. Si el preparador es responsable, la
plataforma es encargada y necesita contrato de encargo (art. 28 RGPD). Si es al revés, la plataforma responde de
los datos de menores de los opositores. **No es un detalle de redacción.**

## 10. Decisiones abiertas

| # | Decisión | Estado |
|---|---|---|
| D1 | ¿El preparador puede ser alumno de otro preparador? | Recomendado: no en v1 |
| D6 | Nombre y dominio | **Cerrado**: `winopo.es` (17-nov-2026) |
| D8 | Vídeo: voz + diapositivas o avatar | Recomendado: voz + diapositivas |
| D9 | Precio por módulo | Bloqueado: falta el precio actual del preparador |
| D10 | ¿Se cobra el alta del preparador? | Recomendado: no; se cobra por alumno |

## 11. Competencia real

Decir «nadie hace esto» era falso. Hay competencia viva y con marca:

| Competidor | Qué hace | Qué no hace |
|---|---|---|
| Opogestión (`opogestion.com`, marca OEPM N-0458252) | Academia con temario, tests y producto «OPOGEST» | Rúbrica publicada ni trazabilidad de corrección |
| Aula del Opositor | Tests y estadísticas | Corrección de supuestos con rúbrica |
| Aula Preparadores | Herramienta B2B para preparadores | Cara de opositor integrada |
| `opotips.com`, `opositatest.com`, `opositarymas.com` | Tests y simuladores gratuitos | Nada de corrección |

Conclusión honesta: el hueco no son los tests. El hueco es **rúbrica explícita + trazabilidad + un único dataset
compartido entre las dos caras** (§8).

## 12. Nombre y dominio

Se comprobaron 28 candidatos con cinco pruebas: `dig NS` para `.es`, `whois` para `.com`, búsqueda del término
exacto, búsqueda de uso comercial y sentido en español.

**Descartados con motivo**:

- `opogest` — colisión directa con Opogestión (mismo sector, marca registrada).
- `apruebaopos`, `preparadocente`, `opositoraula`, `auladeopos`, `temariopo` — dominios libres, pero **nombre ya en
  uso** por otras academias. Un dominio libre no es un nombre libre.
- `aulateka` — `.com` ocupado y «aulateca.com» también.
- `opolink`, `opohub`, `tuopo`, `tuplaza`, `opored` — `.es` y `.com` ocupados.
- `opomatch`, `temauno` — `.com` ocupado.
- `sinbola` — libre en las dos, pero el sorteo por bolas no existe en Maestro de Infantil y Primaria y hay tres webs
  regalando el simulador.
- `metaplaza` — «Meta» es Meta Platforms.
- `elpreparador`, `detumano`, `aprobados` — genéricos, no registrables como marca.
- `nexopo`, `mentopo` — no se dictan.
- `plazapp`, `cazaplazas` — fricción al dictar.
- `oposí`, `opoguía`, `opocoach` — tilde imposible en dominio, ya ocupado, y «coach» no es el nombre del cliente.
- `oppositio` — `.com` en Sedo y, sobre todo, **`opositio.es` y `opositio.com` (una p) son de un tercero**: homófono
  exacto en el mismo TLD.

**Decidido: `winopo.es`** (win + opo). Riesgos asumidos por escrito:

1. El **`.com` no es nuestro**: está en BrandBucket a precio de marca y no se compra. Para vender a preparadores
   andaluces, el `.es` basta.
2. La **`w`** obliga a deletrear por teléfono. Mitigación de 4,95 €: `vinopo.es` está libre y recoge a quien
   escriba con `v`. Comprarla junto con el certificado.
3. Existen `winopo.pl` (vino de limón polaco) y un modelo de calzado de Kickers llamado WINOPO. Ninguno en clase 41,
   pero la búsqueda de marca saldrá contaminada.
4. **Bloqueante antes de invertir en logotipo o papelería**: búsqueda en OEPM (clase 41) y EUIPO.

Estado técnico: registrado en DonDominio con `ns1.dondominio.com` y `ns2.dondominio.com`. La delegación en el TLD
`.es` se publica en un plazo de minutos a 24 h; hasta entonces `dig NS winopo.es` devuelve vacío y no es un error de
configuración.

