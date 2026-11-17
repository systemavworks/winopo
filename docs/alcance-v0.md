# WinOpo · alcance v0

**Estado**: borrador de trabajo · **Fecha**: 17-nov-2026 · **Cliente**: 3 formadores · **Nicho**: oposiciones de
Maestro de Infantil y Primaria, Andalucía · **Dominio**: `winopo.es` (registrado 17-nov-2026)

> Producto separado de Billka: otro público, otros datos, otra marca, otro repositorio. No comparte base de datos
> ni despliegue.

## 1. Qué es

Una plataforma donde un **preparador** publica su temario, sus tests y sus supuestos, y sus **opositores** estudian,
se examinan y reciben corrección con criterios explícitos. La plataforma pone la herramienta; el preparador pone el
contenido y la autoridad pedagógica.

Y donde un **opositor sin preparador** hace lo mismo por su cuenta: sube sus apuntes, maqueta su temario, se hace
tests, entrega supuestos y ensaya la exposición oral. No es un modo degradado de la plataforma: es un espacio propio
con su propio plan (D12). Si más adelante se vincula a un preparador, conserva su historial.

**Qué no es**, y conviene escribirlo antes de diseñar nada:

- No es una academia: no hay profesores propios en v1.
- No es un marketplace abierto: los preparadores los damos de alta nosotros, uno a uno.
- No sustituye al preparador: la IA **nunca** fija la clave de un test ni la nota final.
- No aloja libros de editorial: solo enlaces y material propio del preparador con cesión firmada.

## 2. Dos espacios, un mismo dataset

La unidad de aislamiento es el **espacio** (`tenant`), y hay dos tipos:

| | Espacio preparador | Espacio opositor |
|---|---|---|
| Quién | Un preparador y los opositores vinculados | Un opositor que prepara por su cuenta |
| Ve | Sus grupos, su temario, entregas, estadísticas por tema | Su temario, sus tests, sus correcciones, su progreso |
| Hace | Publica y versiona temario, corrige, programa tests, da accesos | Estudia, sube apuntes, maqueta, hace tests, entrega supuestos, ensaya el oral |
| Nunca | Ve datos de otro preparador | Ve temario no publicado ni datos de otro opositor |

Son **dos shells de interfaz sobre un único backend y una única base de datos**. Dos rutas, dos menús, dos
permisos; ni dos productos ni dos bases. El error caro aquí es duplicar el modelo de datos «porque son públicos
distintos»: el dato es el mismo y cambia quién lo mira.

### 2.1 Vinculación entre espacios

El opositor **no** pertenece al preparador: tiene su propio tenant. Lo que existe es una vinculación opcional.

```
tenant(tipo = preparador | opositor)
vinculacion(tenant_opositor_id, tenant_preparador_id, estado, desde, hasta)
```

- Como mucho **una vinculación activa** por opositor en v1 (se mantiene el espíritu de D1, sin que el opositor
  deje de ser espacio propio).
- Al vincularse, el opositor recibe el material **publicado** del preparador y sus tests programados; el
  preparador ve el progreso de estudio de ese opositor.
- Al desvincularse, la fila se cierra (`hasta`) y el opositor conserva su temario propio, su historial y sus
  correcciones. No se borra nada suyo para «devolverlo» a un estado anterior.
- El alta del preparador sigue siendo manual: el material publicado tiene que tener responsable identificado.

## 3. Aislamiento por espacio

Toda tabla con `tenant_id` lleva RLS forzado, como en Billka: sin contexto de tenant no se ve una fila. Un
preparador no puede, ni por error de código, leer el temario de otro; y un opositor no puede leer los apuntes de
otro opositor.

Hay **tres** lecturas cruzadas permitidas, y solo tres:

1. `vinculacion` — el preparador ve el progreso de estudio del opositor vinculado (temas, tests, notas,
   correcciones). No ve su material privado ni nada fuera de la plataforma.
2. `material_publicado` — lo que el preparador publica lo ven sus vinculados. Un opositor no vinculado no ve nada,
   ni por enlace directo: el permiso se comprueba en el servidor.
3. `directorio` — la ficha pública del preparador (materia, plazas, contacto). Es dato profesional, no dato
   personal del opositor.

El opositor puede vivir toda la vida de la plataforma sin vincularse a nadie. Si se vincula y luego cambia de
preparador, se cierra una vinculación y se abre otra: el historial es suyo y no se migra al preparador.

## 4. Planes y comercialización

Se vende por **temporada** (septiembre–mayo), nunca por suscripción mensual continua, y con dos escalas, una por
espacio. Para no confundir tres cosas en la misma reunión: **bloque** es una parte del temario (una materia), **plan**
es lo que se contrata y **módulo** es lo que un plan desbloquea.

**Espacio preparador**

| Nivel | Incluye |
|---|---|
| Base | Temario versionado, **PDF maquetado** y tests con clave fija |
| + IA | Supuestos corregidos por IA con rúbrica, nunca nota final |
| + Preparador | Corrección humana y tutoría |
| Curso completo | Todo lo anterior + vídeo |

**Espacio opositor — plan propio (D13)**

| Plan | Incluye | Coste variable |
|---|---|---|
| Básico | Temario y apuntes propios maquetados en PDF, tests con corrección explicada, guías y plan de estudio | Casi nulo |
| Pro | + supuestos con rúbrica, corrección asistida por IA validable y tribunal simulado | IA + transcripción |
| Master | + vídeo y animaciones de repaso, simulacro completo y tope de ensayos ampliado | IA + vídeo |

Los nombres («Básico / Pro / Master») son provisionales; la escalera de tres niveles y lo que desbloquea cada uno,
no. La **vinculación con un preparador no está a la venta**: se incluye en los tres planes, porque el material que
aporta ya lo paga él.

Tres reglas de precio:

1. **Preparador**: el software no puede pasar del 10 % de lo que factura por alumno. Si cobra 60 €/mes por alumno,
   el módulo no puede costar 6 €/mes.
2. **Opositor**: el plan Básico tiene que salir más barato que **mandar maquetar el temario por fuera** (hoy se
   cobran 40–90 € por tema, §7.1). Si no sale más barato, no hay razón para contratarlo.
3. **Ningún plan con IA sin tope**: Pro y Master llevan un máximo de correcciones y de ensayos de oral por
   temporada. La IA y el tribunal son las dos piezas con coste variable; sin tope, se venden a pérdida.

Falta el dato real del preparador para fijar tarifas (D9). Cobrar al opositor exige Stripe con cliente final
persona física (D13), que es un circuito distinto del cobro a una academia.

### 4.1 Cómo entra cada uno

| | Opositor | Preparador |
|---|---|---|
| **Alta** | **Registro abierto** (D16): correo verificado y tenant propio creado en la misma transacción | Alta guiada: cesión de derechos firmada y revisión del material |
| **Paga** | Su plan, por temporada | Por alumno cubierto, según D9 |
| **Vinculación** | Opcional: enlace o código del preparador, y no depende de él para entrar | Ve a los opositores vinculados, no al resto |

El registro abierto obliga a límite de intentos y captcha: cada cuenta nueva puede empezar a gastar IA el primer
día, y el que abusa no paga.

## 5. Reglas de IA (no negociables)

1. La IA **propone**; el humano **decide**. Ninguna clave de test la fija un modelo.
2. Toda corrección guarda `corregido_por`: `ia`, `preparador` o `validado`.
3. Toda corrección guarda `prompt_version` y `modelo`.
4. Todo material generado se etiqueta con la versión de temario de la que salió.
5. Un supuesto corregido por IA **no cuenta** para la nota si el preparador no lo valida.
6. El prompt de corrección publica su rúbrica: qué puntúa, cuánto y con qué tolerancia.
7. El **tribunal simulado no emite nota oficial**: devuelve un informe orientativo, siempre etiquetado como
   simulación, con `modelo` y `prompt_version`.
8. Si se graba voz, hay consentimiento explícito, se dice cuánto se conserva y se puede borrar. El audio **no** se
   usa para entrenar modelos.

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

### 7.2 Del temario al material de estudio

El mismo contenido produce más de un entregable, y no es un adorno: es lo que hoy se encarga y se paga por fuera.

| Entregable | Cómo se genera | Quién lo usa |
|---|---|---|
| PDF maquetado | WeasyPrint sobre la versión del tema | Estudio e impresión |
| Esquema / mapa del tema | Epígrafes y relaciones extraídos del propio texto | Repaso rápido |
| Línea de tiempo | Fechas detectadas en el tema, revisadas por una persona | Historia, normativa |
| Presentación (PPTX) | Diapositivas desde epígrafes y tablas | Clase del preparador y material vendible |
| Animación / vídeo de repaso | Voz sintética + diapositivas (§6) | Repaso y venta de material |
| Test de autoevaluación | Preguntas del banco asociadas al tema | Estudio activo |

Límite explícito: **se deriva del texto, no se inventa**. Si el tema no trae fechas, no hay línea de tiempo; si no
hay epígrafes, no hay esquema. Todo entregable lleva la versión del tema de la que salió, para poder rehacerlo
cuando cambie la convocatoria.

Quien produce y vende material (hay un mercado real: se cobra por tema maquetado) encuentra aquí la parte que hoy
hace a mano en Word y Canva. Producirlo y exportarlo entra en el producto; **venderlo dentro** de la plataforma
está en estudio (D14).

## 8. El diferencial: corrección con rúbrica explícita

Los competidores ya tienen tests con estadísticas. Lo que no hay, o casi no hay:

1. Corrección de supuestos con **rúbrica publicada** (puntos por apartado, tolerancias, penalizaciones).
2. Trazabilidad de quién corrigió: IA, preparador o validado.
3. Temario **versionado** con fuentes citadas y vídeo atado a la versión.
4. Los dos espacios (preparador y opositor) sobre **el mismo dataset**, no dos productos con un Excel en medio.
5. **Tribunal simulado**: exponer en voz alta, con repreguntas y un informe que dice en qué se cae, sin inventarse
   una nota oficial.

Si el producto no hace 1, 2 y 5, es otro simulador de tests y compite por precio. Eso hay que decidirlo antes de
escribir código, no después.

### 8.1 Tribunal simulado

El ejercicio oral se prepara leyendo, y se pierde por no haberlo dicho en voz alta nunca. WinOpo ofrece un ensayo:

| Pieza | Regla |
|---|---|
| Entrada | El opositor elige tema y duración; opcionalmente sube su guion |
| Desarrollo | Expone hablando; el tribunal artificial interrumpe, pide aclaraciones y repregunta |
| Salida | Informe: tiempo por bloque, estructura, muletillas, preguntas que no supo responder |
| Lo que no es | Nota oficial, sustituto del preparador ni grabación publicada |
| Datos | Consentimiento de grabación, plazo de conservación explícito y borrado a petición (§5, regla 8) |

Coste: es voz + transcripción + evaluación. Se cobra dentro del módulo + IA, nunca por minuto suelto: un opositor
que ensaya diez veces no puede quedarse con la sensación de estar echando monedas.

Riesgo asumido: evaluar un oral es más subjetivo que corregir un test, y el informe puede desanimar a quien mejora
despacio. Por eso el informe puntúa **conducta** (estructura, tiempo, claridad) y no «capacidad» de la persona, y
siempre termina con qué hacer en el siguiente ensayo.

## 9. Legal y datos

| # | Tema | Estado |
|---|---|---|
| L1 | Acceso al módulo hasta 31-may | Pendiente |
| L2 | Renuncia al desistimiento (art. 103.m TRLGDCU) con clic en checkout | **Obligatorio antes de vender** |
| L3 | IVA 21 % o exención de enseñanza | Consultar asesor |
| L4 | Precio de renovación para quien repite | Pendiente |
| D7 | Responsable del tratamiento: ¿preparador o plataforma? | Pendiente |

Los códigos `L*` son trámites legales y se numeran aparte a propósito: antes usaban `D2`–`D5`, que ya estaban
ocupados por decisiones técnicas en `docs/decisiones.md`, y nadie sabía de qué se hablaba en una reunión.

D7 condiciona el contrato, el aviso legal y el encargado de tratamiento. Si el preparador es responsable, la
plataforma es encargada y necesita contrato de encargo (art. 28 RGPD). Si es al revés, la plataforma responde de
los datos de menores de los opositores. **No es un detalle de redacción.**

## 10. Decisiones abiertas

| # | Decisión | Estado |
|---|---|---|
| D1 | ¿El preparador puede ser alumno de otro preparador? | Recomendado: no en v1 (ver D12: el opositor ya es espacio propio) |
| D6 | Nombre y dominio | **Cerrado**: `winopo.es` (17-nov-2026) |
| D8 | Vídeo: voz + diapositivas o avatar | Recomendado: voz + diapositivas |
| D9 | Precio por módulo y por plan | Bloqueado: falta el precio actual del preparador |
| D10 | ¿Se cobra el alta del preparador? | Recomendado: no; se cobra por alumno |
| D12 | ¿El opositor sin preparador tiene espacio propio? | **Cerrado**: sí, tenant `opositor` con vinculación opcional (17-nov-2026) |
| D13 | ¿Cómo paga el opositor? | **Cerrado**: plan propio por temporada con tres niveles: Básico, Pro y Master (17-nov-2026) |
| D14 | ¿Se vende material dentro de la plataforma? | **Cerrado**: fuera de v1; pagar un plan no convierte al opositor en vendedor (17-nov-2026) |
| D15 | Tribunal simulado: ¿voz en directo o audio grabado? | Recomendado: audio grabado + transcripción (más barato y auditable) |
| D16 | ¿Cómo entra cada uno? | **Cerrado**: registro abierto para el opositor, alta guiada para el preparador (17-nov-2026) |

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

