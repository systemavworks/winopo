-- 0002_identidad · tenant, usuario, pertenencia y sesión
-- F0

create table tenant (
  id        uuid primary key default gen_random_uuid(),
  slug      citext not null unique,
  nombre    text   not null,
  estado    text   not null default 'activo' check (estado in ('activo', 'suspendido', 'baja')),
  creado_en timestamptz not null default now()
);

create table app_user (
  id                  uuid primary key default gen_random_uuid(),
  correo              citext not null unique,
  nombre              text   not null,
  hash_clave          text   not null,
  email_verificado_en timestamptz,
  creado_en           timestamptz not null default now(),
  anonimizado_en      timestamptz
);

create table membership (
  id        uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenant(id) on delete restrict,
  user_id   uuid not null references app_user(id) on delete cascade,
  rol       text not null check (rol in ('preparador', 'opositor', 'admin')),
  estado    text not null default 'activo' check (estado in ('activo', 'invitado', 'baja')),
  creado_en timestamptz not null default now(),
  unique (tenant_id, user_id)
);

create index on membership (user_id);

-- Sesión: se guarda el HASH del token, nunca el token.
create table sesion (
  id         uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  user_id    uuid not null references app_user(id) on delete cascade,
  tenant_id  uuid references tenant(id) on delete cascade,
  ip         inet,
  user_agent text,
  creado_en  timestamptz not null default now(),
  expira_en  timestamptz not null
);

create index on sesion (user_id);

-- RLS forzado: el dueño de la tabla también queda sujeto a las políticas.
alter table tenant     enable row level security;
alter table tenant     force  row level security;
alter table membership enable row level security;
alter table membership force  row level security;
alter table sesion     enable row level security;
alter table sesion     force  row level security;

create policy tenant_por_contexto on tenant
  using (id = winopo_tenant());

create policy membership_por_tenant on membership
  using (tenant_id = winopo_tenant());

create policy sesion_por_tenant on sesion
  using (tenant_id = winopo_tenant());

-- Dos problemas reales de arranque, resueltos aquí y no en el código:
--
-- 1. En el login todavía no hay tenant, pero hay que saber a cuáles pertenece el usuario.
--    Con `winopo.user_id` fijado tras verificar la contraseña, el usuario ve SUS memberships.
--    Las políticas se combinan con OR: esta no abre nada de otros usuarios.
create policy membership_propia on membership
  using (user_id = nullif(current_setting('winopo.user_id', true), '')::uuid);

-- 2. Para validar una cookie hay que leer `sesion` antes de conocer el tenant.
--    Se fija el HASH de la cookie y la política deja ver exactamente esa fila. Nada más.
create policy sesion_por_token on sesion
  using (token_hash = nullif(current_setting('winopo.sesion_hash', true), ''));

comment on policy sesion_por_token on sesion is
  'Permite validar la cookie sin conocer el tenant. El token en claro no se guarda nunca.';
