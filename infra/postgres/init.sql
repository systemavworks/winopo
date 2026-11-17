-- Solo LOCAL. En staging y producción el rol se crea por infraestructura.
-- El rol de aplicación no puede saltarse la RLS: sin BYPASSRLS no hay atajo.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'winopo_app') then
    create role winopo_app login password 'winopo_app' nosuperuser nocreatedb nocreaterole noinherit;
  end if;
end
$$;

grant connect on database winopo to winopo_app;
grant usage on schema public to winopo_app;
alter default privileges in schema public grant select, insert, update, delete on tables to winopo_app;
alter default privileges in schema public grant usage, select on sequences to winopo_app;
