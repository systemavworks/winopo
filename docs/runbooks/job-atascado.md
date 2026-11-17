# Runbook · Job atascado

## Síntoma

Un trabajo lleva más de 30 minutos en `en_curso`, o la cola crece y no baja.

## Diagnóstico

```sql
-- ¿Quién lo tiene y desde cuándo?
select id, tipo, estado, intentos, tomado_en, worker_id
from job
where estado in ('pendiente', 'en_curso')
order by creado_en
limit 20;
```

```sql
-- Worker muerto: lo tomó y no late desde hace 10 minutos
select id, tipo, tomado_en from job
where estado = 'en_curso' and latido_en < now() - interval '10 minutes';
```

## Resolución

1. Si el worker está vivo y el trabajo es lento de verdad (vídeo), esperar. Mirar los logs del worker.
2. Si el worker murió: `update job set estado='pendiente', tomado_en=null where id = <id>;` — el siguiente worker
   lo reclama. El `intentos` se incrementa; al llegar a 3 el job pasa a `fallido` y se avisa al preparador.
3. Si el trabajo se repite y siempre falla: mirar el error guardado. **No** reintentar en bucle: se marca `fallido`
   y se investiga.

## Prevención

- `latido_en` se actualiza cada 30 s mientras el trabajo corre.
- Un job que tarda más de lo previsto no se mata solo: se ve en el panel de admin.
- Ningún trabajo se borra a mano sin dejar nota en el registro de incidentes.
