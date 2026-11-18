-- 0015_especialidad_tarifa · catálogo de especialidades y matriz de tarifas
-- F3.5 (bolsa) y F5 (checkout) · pendiente de aplicar
--
-- Ámbito plataforma: estas tablas NO llevan tenant_id. Las lee winopo_app y solo las
-- escribe el operador. Importes en céntimos enteros y NETOS de IVA (principio 7): el IVA
-- se calcula en el checkout, no se guarda.
--
-- Sin precios cargados: una fila de `tarifa` entra cuando hay fuente (tres tarifas reales
-- de preparadores con fecha). `fuente` es NOT NULL a propósito.

-- btree_gist aporta el operador de igualdad para text en GiST y permite la EXCLUDE de abajo.
create extension if not exists btree_gist;

-- ───────────── Catálogo de especialidades ─────────────
-- El grupo (A1/A2/C1/C2) vive aquí y solo aquí. Hoy la especialidad es texto libre en la
-- bolsa y en el ensayo, así que "Administrativo" y "administrativo C1" no casarían entre
-- tenants; con catálogo, la tarifa se resuelve por join y el grupo no se duplica.

create table especialidad (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  nombre     text not null check (length(btrim(nombre)) > 0),
  grupo      text not null check (grupo in ('A1', 'A2', 'C1', 'C2')),
  activa     boolean not null default true,
  creado_en  timestamptz not null default now()
);

comment on table especialidad is
  'Catálogo de plataforma. Única fuente del grupo (A1/A2/C1/C2) con el que se tarifica.';

-- ───────────── Matriz de tarifas ─────────────
-- tipo × grupo × modalidad. El pago al evaluador solo existe en la modalidad ciega:
-- en 'propio' evalúa el preparador del alumno y WinOpo no paga ensayo (D17).

create table tarifa (
  id                    uuid primary key default gen_random_uuid(),
  tipo                  text not null check (tipo in ('supuesto_escrito', 'oral', 'simulacro')),
  grupo                 text not null check (grupo in ('A1', 'A2', 'C1', 'C2')),
  modalidad             text not null check (modalidad in ('propio', 'ciego')),
  precio_neto_cents     integer not null check (precio_neto_cents >= 0),
  pago_evaluador_cents  integer check (pago_evaluador_cents >= 0),
  vigente_desde         date not null,
  vigente_hasta         date,                                    -- null = abierta
  fuente                text not null check (length(btrim(fuente)) > 0),
  creado_en             timestamptz not null default now(),
  check (vigente_hasta is null or vigente_hasta > vigente_desde),
  check ((modalidad = 'ciego') = (pago_evaluador_cents is not null)),
  -- El pago no puede superar el precio: es aritmética, no la regla de negocio del 25 %.
  check (pago_evaluador_cents is null or pago_evaluador_cents <= precio_neto_cents),
  -- Una sola tarifa vigente por (tipo, grupo, modalidad) en cada fecha: si alguien intenta
  -- abrir una nueva sin cerrar la anterior, el solape lo rechaza la base, no el código.
  exclude using gist (
    tipo with =,
    grupo with =,
    modalidad with =,
    daterange(vigente_desde, vigente_hasta, '[)') with &&
  )
);

comment on table tarifa is
  'Matriz tipo × grupo × modalidad. Sin fuente no hay tarifa; sin tarifa no se vende (fail-closed).';
comment on column tarifa.pago_evaluador_cents is
  'Solo modalidad ciego. En propio evalúa el preparador del alumno y no hay pago de ensayo.';

-- Una tarifa no se edita ni se borra: se cierra (vigente_hasta) y se abre otra. Un cambio
-- de precio no puede reescribir lo que ya se vendió.
create or replace function tarifa_inmutable() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'tarifa: no se borra, se cierra con vigente_hasta';
  end if;
  if (new.tipo, new.grupo, new.modalidad, new.precio_neto_cents,
      new.pago_evaluador_cents, new.vigente_desde, new.fuente, new.creado_en)
     is distinct from
     (old.tipo, old.grupo, old.modalidad, old.precio_neto_cents,
      old.pago_evaluador_cents, old.vigente_desde, old.fuente, old.creado_en) then
    raise exception 'tarifa: solo se puede cerrar (vigente_hasta)';
  end if;
  return new;
end;
$$;

create trigger tarifa_inmutable before update or delete on tarifa
  for each row execute function tarifa_inmutable();

-- Fail-closed: si no devuelve filas, el checkout no vende el ensayo. Devolver una fila
-- "por defecto" convertiría un catálogo incompleto en un precio inventado.
create or replace function tarifa_vigente(
  p_tipo          text,
  p_especialidad  uuid,
  p_modalidad     text,
  p_fecha         date default current_date
) returns setof tarifa
language sql stable as $$
  select t.*
    from tarifa t
    join especialidad e on e.grupo = t.grupo
   where e.id = p_especialidad
     and t.tipo = p_tipo
     and t.modalidad = p_modalidad
     and t.vigente_desde <= p_fecha
     and (t.vigente_hasta is null or t.vigente_hasta > p_fecha)
$$;

comment on function tarifa_vigente(text, uuid, text, date) is
  'Tarifa aplicable a una fecha. Cero filas = no se vende.';

-- ───────────── RLS ─────────────
-- Lectura para la app, escritura solo del operador (D3).

alter table especialidad enable row level security;
alter table especialidad force  row level security;
alter table tarifa       enable row level security;
alter table tarifa       force  row level security;

create policy especialidad_lectura on especialidad
  for select using (true);

create policy tarifa_lectura on tarifa
  for select using (true);

-- Sin política de escritura, FORCE RLS ya bloquea INSERT/UPDATE/DELETE a winopo_app.
-- El REVOKE es defensa en profundidad: infra/postgres/init.sql concede DML por defecto
-- sobre toda tabla nueva, así que el permiso existe aunque la política lo niegue.
--
-- Consecuencia asumida (igual que en 0002: nadie crea tenants desde la app): el catálogo
-- lo mantiene el operador, que aplica migraciones como superusuario. Si algún día las
-- migraciones se aplican con un rol dueño y sin superusuario, FORCE RLS también lo frenará
-- a él y hará falta una política explícita para ese rol.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'winopo_app') then
    revoke insert, update, delete on especialidad, tarifa from winopo_app;
  end if;
end;
$$;
