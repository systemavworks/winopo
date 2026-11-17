-- 0001_base · extensiones y contexto de tenant
-- F0
--
-- El rol de aplicación NO se crea aquí: se crea en infra/postgres/init.sql (local) y por
-- infraestructura en staging/producción. Una migración con CREATE ROLE ... PASSWORD acaba
-- metiendo credenciales en el repositorio.

create extension if not exists citext;
create extension if not exists pgcrypto;

-- Contexto de tenant por petición. Se fija con set_config(..., true) DENTRO de la transacción
-- de la petición; al cerrar la transacción se limpia solo.
create or replace function winopo_tenant() returns uuid
language sql stable as $$
  select nullif(current_setting('winopo.tenant_id', true), '')::uuid;
$$;

comment on function winopo_tenant() is
  'Tenant de la transacción en curso. Sin contexto devuelve NULL y RLS no deja ver ninguna fila.';
