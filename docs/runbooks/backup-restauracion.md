# Runbook · Copia y restauración

## Copia diaria

```bash
BACKUP_DESTINO=s3:... infra/scripts/backup.sh
```

- `pg_dump -Fc` (formato custom, restaurable por tabla).
- Cifrado en destino. Nunca en el mismo disco que la base.
- Retención: 30 días.

## Restauración (probar una vez al mes, no el día del incidente)

```bash
infra/scripts/restore-test.sh backups/winopo-YYYY-MM-DD.dump
```

El script crea una base temporal `winopo_restore_test`, restaura, cuenta filas en `tenant`, `app_user` y `membership`,
 y compara con el origen. Si los números no cuadran, **falla**. Después borra la base temporal.

## Restauración real

1. Avisar y parar `core` y `worker`
   (`docker compose --env-file .env -f infra/docker-compose.prod.yml stop core worker`). Así nadie escribe a mitad.
2. `createdb winopo_nuevo` y `pg_restore -d winopo_nuevo`.
3. Renombrar bases (`alter database ... rename to ...`).
4. Arrancar `core`; comprobar `/healthz` y un login real.
5. Anotar en el registro de incidentes: hora, copia usada, filas restauradas.

## Qué se pierde y qué no

- Se pierde todo lo posterior a la copia. Por eso la copia es diaria y no semanal.
- El vídeo vive en R2: no entra en el `pg_dump`. Sus metadatos sí; si R2 y la base se desincronizan, el registro
  apunta a un objeto que ya no existe. El worker lo detecta y marca la entrega como `video_perdido`.
