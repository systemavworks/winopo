# Contratos

El contrato manda. API e IA se validan contra estos esquemas; si algo no valida, falla y se ve.

| Archivo | Quién lo cumple | Cuándo se valida |
|---|---|---|
| `api/openapi.yaml` | Frontend y clientes | En CI; de aquí se generan los tipos de `web/src/lib/api/tipos.ts` |
| `api/error.schema.json` | Toda respuesta 4xx/5xx | En los tests de rutas |
| `ia/correccion.schema.json` | Respuesta del proveedor de IA | Antes de guardar `correccion_item` |
| `ia/guion.schema.json` | Guion generado por IA | Antes de pasar a TTS |

Regla: un JSON inválido **no se arregla a mano**; el job falla y queda en `job.ultimo_error`.
