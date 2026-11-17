-- 0003_audit_log · registro append-only
-- F0

create table audit_log (
  id         bigserial primary key,
  tenant_id  uuid references tenant(id) on delete restrict,
  actor_id   uuid references app_user(id) on delete set null,
  accion     text not null,
  entidad    text not null,
  entidad_id text,
  datos      jsonb not null default '{}'::jsonb,
  creado_en  timestamptz not null default now()
);

create index on audit_log (tenant_id, creado_en desc);

alter table audit_log enable row level security;
alter table audit_log force  row level security;

create policy audit_por_tenant on audit_log
  using (tenant_id = winopo_tenant());

-- Inmutable por trigger, no por convención de código.
create or replace function audit_log_inmutable() returns trigger
language plpgsql as $$
begin
  raise exception 'audit_log es append-only';
end;
$$;

create trigger audit_log_no_update before update or delete on audit_log
  for each row execute function audit_log_inmutable();
