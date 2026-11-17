# Migraciones

- Convenio: `NNNN_descripcion.sql`, numeración correlativa, sin huecos.
- **Una migración aplicada no se edita nunca.** Se corrige con la siguiente.
- La RLS de una tabla va **en la misma migración** que crea la tabla. Si se separa, se olvida.
- El rol de aplicación no se crea aquí (§ `infra/postgres/init.sql`): credenciales fuera del repositorio.
- Se aplican en orden con `make migrate`; `ON_ERROR_STOP=1` hace que el primer error detenga el proceso.
