-- 0016_bolsa_ensayo · bolsa de evaluadores y ensayo de tribunal
-- F3.5 · pendiente de aplicar (antes 0015_bolsa_ensayo; se desplaza por 0015_especialidad_tarifa)
--
-- La especialidad es una FK al catálogo de 0015: nace ya con especialidad_id y no hace
-- falta un ALTER. Los importes del ensayo son una copia de la tarifa vigente el día de la
-- compra, en céntimos netos. Subir tarifas no reescribe liquidaciones devengadas.
--
-- `tenant_id` es el espacio del ALUMNO (su tenant propio en B2C, el del preparador en la
-- plaza B2B). El evaluador ciego vive en otro tenant y por eso hay una política cruzada.

-- ───────────── Helpers de sesión ─────────────
-- Deberían vivir en 0002_identidad, pero una migración aplicada no se edita (README).

create or replace function winopo_membership() returns uuid
language sql stable as $$
  select nullif(current_setting('winopo.membership_id', true), '')::uuid;
$$;

comment on function winopo_membership() is
  'Membership de la petición en curso. Sin contexto devuelve NULL.';

create or replace function winopo_es_staff() returns boolean
language sql stable as $$
  select exists (
    select 1
      from membership m
     where m.id = winopo_membership()
       and m.rol = 'admin'
       and m.estado = 'activo'
  );
$$;

comment on function winopo_es_staff() is
  'True si la membership de la petición es admin activo. Lee membership bajo RLS: no abre nada.';

-- ───────────── Bolsa de evaluadores ─────────────

create table bolsa_evaluador (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references tenant(id) on delete restrict,
  membership_id   uuid not null references membership(id) on delete cascade,  -- D12: nunca user_id
  especialidad_id uuid not null references especialidad(id) on delete restrict,
  estado          text not null default 'activo'
                  check (estado in ('activo', 'pausado', 'retirado')),
  max_mes         integer not null default 20 check (max_mes > 0),
  acepta_rubrica  boolean not null default false,
  creado_en       timestamptz not null default now(),
  unique (tenant_id, membership_id, especialidad_id)
);

create index on bolsa_evaluador (especialidad_id, estado);

comment on column bolsa_evaluador.max_mes is
  'Tope de carga. Más de 20 ensayos al mes convierte el acta en plantilla.';

-- La membership tiene que ser del mismo tenant y ser de preparador. Sin esto, una fila
-- mal escrita deja a un opositor en la bolsa de evaluadores.
create or replace function bolsa_membership_valida() returns trigger
language plpgsql as $$
declare
  v_tenant uuid;
  v_rol    text;
begin
  select m.tenant_id, m.rol into v_tenant, v_rol
    from membership m
   where m.id = new.membership_id;

  if v_tenant is distinct from new.tenant_id or v_rol <> 'preparador' then
    raise exception
      'bolsa_evaluador: la membership % no es de preparador del tenant %',
      new.membership_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger bolsa_membership_valida before insert or update on bolsa_evaluador
  for each row execute function bolsa_membership_valida();

-- ───────────── Ensayo de tribunal ─────────────

create table ensayo_tribunal (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references tenant(id) on delete restrict,
  alumno_membership_id    uuid not null references membership(id) on delete restrict,
  evaluador_membership_id uuid references membership(id) on delete restrict,  -- null si 'solicitado'
  especialidad_id         uuid not null references especialidad(id) on delete restrict,
  tipo                    text not null check (tipo in ('supuesto_escrito', 'oral', 'simulacro')),
  modalidad               text not null check (modalidad in ('propio', 'ciego')),
  origen                  text not null check (origen in ('plan', 'compra')),
  -- Copia de la tarifa vigente el día de la compra. Congelada por trigger.
  tarifa_id               uuid not null references tarifa(id) on delete restrict,
  cobrado_neto_cents      integer not null check (cobrado_neto_cents >= 0),  -- 0 si viene del plan
  pago_evaluador_cents    integer check (pago_evaluador_cents >= 0),
  stripe_ref              text unique,                    -- una referencia, un ensayo
  estado                  text not null default 'solicitado'
                          check (estado in ('solicitado', 'asignado', 'celebrado', 'informado',
                                            'reclamado', 'cerrado', 'liquidado', 'cancelado')),
  programado_para         timestamptz not null,
  informado_at            timestamptz,
  cerrado_at              timestamptz,
  cancelado_at            timestamptz,
  rubrica                 jsonb,
  acta_pdf                text,
  audio_ref               text,                            -- se borra según retención (F3.5)
  creado_en               timestamptz not null default now(),
  check ((modalidad = 'ciego') = (pago_evaluador_cents is not null)),
  -- El plan no cobra; una compra cobra y siempre deja referencia de Stripe. Fail-closed:
  -- una compra sin cobro ni referencia no es un caso válido, es un descuento que nadie firmó.
  check (
    (origen = 'plan'   and cobrado_neto_cents = 0 and stripe_ref is null)
    or
    (origen = 'compra' and cobrado_neto_cents > 0 and stripe_ref is not null)
  ),
  -- Asignado o posterior necesita evaluador; 'solicitado' y 'cancelado' no.
  check (estado in ('solicitado', 'cancelado') or evaluador_membership_id is not null),
  check (estado <> 'cancelado' or cancelado_at is not null)
);

create index on ensayo_tribunal (tenant_id, estado);
create index on ensayo_tribunal (evaluador_membership_id, estado);
create index on ensayo_tribunal (especialidad_id, estado);

-- Índice parcial: el barrido de cierre solo mira lo que puede cerrar.
create index ensayo_pendiente_cierre on ensayo_tribunal (informado_at)
  where estado = 'informado';

comment on column ensayo_tribunal.tenant_id is
  'Espacio del alumno. En la plaza B2B es el tenant del preparador; en B2C, el del opositor.';
comment on column ensayo_tribunal.audio_ref is
  'Referencia al audio del oral. Se borra con la retención de F3.5, no con el ensayo.';

-- El alumno tiene que ser del tenant del ensayo. Solo en INSERT: en UPDATE el evaluador
-- ciego no ve la membership del alumno (otro tenant, RLS), así que la comprobación no se
-- puede repetir por fila. Que alumno y tenant no cambien lo garantiza ensayo_campos_por_rol.
create or replace function ensayo_alumno_valido() returns trigger
language plpgsql as $$
declare
  v_tenant uuid;
begin
  select m.tenant_id into v_tenant from membership m where m.id = new.alumno_membership_id;

  if v_tenant is distinct from new.tenant_id then
    raise exception
      'ensayo_tribunal: la membership % no pertenece al tenant %',
      new.alumno_membership_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger ensayo_alumno_valido before insert on ensayo_tribunal
  for each row execute function ensayo_alumno_valido();

-- Los importes no cambian después de insertar: un cambio de tarifa no reescribe lo que ya
-- se cobró ni lo que ya se debe al evaluador.
create or replace function ensayo_importes_congelados() returns trigger
language plpgsql as $$
begin
  if (new.tarifa_id, new.cobrado_neto_cents, new.pago_evaluador_cents)
     is distinct from
     (old.tarifa_id, old.cobrado_neto_cents, old.pago_evaluador_cents) then
    raise exception 'ensayo_tribunal: los importes se congelan al comprar';
  end if;
  return new;
end;
$$;

create trigger ensayo_importes_congelados before update on ensayo_tribunal
  for each row execute function ensayo_importes_congelados();

-- RLS no distingue columnas. El evaluador puede informar (estado, rúbrica, acta, audio),
-- pero no cambiar al alumno ni la fecha; el alumno solo puede mover el estado (reclamar).
-- Se compara el jsonb sin las columnas permitidas, así una columna nueva queda protegida
-- por defecto en vez de olvidada.
create or replace function ensayo_campos_por_rol() returns trigger
language plpgsql as $$
declare
  v_actor uuid := winopo_membership();
begin
  -- Invariante para todos, incluido el operador: el ensayo no cambia de dueño ni de tenant.
  if (new.tenant_id, new.alumno_membership_id)
     is distinct from (old.tenant_id, old.alumno_membership_id) then
    raise exception 'ensayo_tribunal: el alumno y su tenant no cambian';
  end if;

  if winopo_es_staff() then
    return new;   -- el staff mueve el ciclo de vida; los importes los frena el otro trigger
  end if;

  if old.evaluador_membership_id = v_actor then
    if (to_jsonb(new) - 'estado' - 'informado_at' - 'rubrica' - 'acta_pdf' - 'audio_ref')
       is distinct from
       (to_jsonb(old) - 'estado' - 'informado_at' - 'rubrica' - 'acta_pdf' - 'audio_ref') then
      raise exception 'ensayo_tribunal: el evaluador solo informa el ensayo';
    end if;
  elsif old.alumno_membership_id = v_actor then
    if (to_jsonb(new) - 'estado') is distinct from (to_jsonb(old) - 'estado') then
      raise exception 'ensayo_tribunal: el alumno solo cambia el estado';
    end if;
  end if;
  return new;
end;
$$;

create trigger ensayo_campos_por_rol before update on ensayo_tribunal
  for each row execute function ensayo_campos_por_rol();

-- ───────────── RLS ─────────────

alter table bolsa_evaluador  enable row level security;
alter table bolsa_evaluador  force  row level security;
alter table ensayo_tribunal  enable row level security;
alter table ensayo_tribunal  force  row level security;

-- Bolsa: el evaluador ve y mantiene su alta; el staff del tenant, las de su espacio.
create policy bolsa_propia on bolsa_evaluador
  for select using (
    tenant_id = winopo_tenant()
    and (membership_id = winopo_membership() or winopo_es_staff())
  );

create policy bolsa_alta_propia on bolsa_evaluador
  for insert with check (
    tenant_id = winopo_tenant()
    and membership_id = winopo_membership()
  );

create policy bolsa_actualiza_propia on bolsa_evaluador
  for update using (
    tenant_id = winopo_tenant()
    and (membership_id = winopo_membership() or winopo_es_staff())
  ) with check (
    tenant_id = winopo_tenant()
    and (membership_id = winopo_membership() or winopo_es_staff())
  );

-- Ensayo: alumno, staff y evaluador asignado. Ninguna política consulta la otra tabla:
-- el diseño anterior encadenaba bolsa → ensayo → bolsa y entraba en recursión infinita.
create policy ensayo_alumno_ve on ensayo_tribunal
  for select using (
    tenant_id = winopo_tenant()
    and alumno_membership_id = winopo_membership()
  );

create policy ensayo_staff_ve on ensayo_tribunal
  for select using (
    tenant_id = winopo_tenant()
    and winopo_es_staff()
  );

-- ÚNICA excepción al aislamiento por tenant de todo el proyecto, y es deliberada: el
-- evaluador ciego vive en otro tenant (si no, no sería ciego) y tiene que ver el ensayo
-- que se le ha asignado. Solo ese: la condición es su membership, no el tenant.
-- No quitar "por parecer un error": sin esta rama el ensayo ciego no se puede evaluar.
create policy ensayo_evaluador_asignado on ensayo_tribunal
  for select using (evaluador_membership_id = winopo_membership());

create policy ensayo_alta_alumno on ensayo_tribunal
  for insert with check (
    tenant_id = winopo_tenant()
    and alumno_membership_id = winopo_membership()
    and estado = 'solicitado'
  );

-- WITH CHECK explícito: en UPDATE, si falta, PostgreSQL reutiliza el USING y el evaluador
-- no podría pasar a 'informado' (la fila nueva ya no cumple estado in ('asignado','celebrado')).
create policy ensayo_evaluador_actualiza on ensayo_tribunal
  for update using (
    evaluador_membership_id = winopo_membership()
    and estado in ('asignado', 'celebrado')
  ) with check (
    evaluador_membership_id = winopo_membership()
    and estado in ('asignado', 'celebrado', 'informado')
  );

create policy ensayo_alumno_reclama on ensayo_tribunal
  for update using (
    tenant_id = winopo_tenant()
    and alumno_membership_id = winopo_membership()
    and estado = 'informado'
  ) with check (
    alumno_membership_id = winopo_membership()
    and estado = 'reclamado'
  );

-- Cierre por silencio a 72 h. NO es una política: en UPDATE, PostgreSQL aplica además las
-- políticas de SELECT, así que una política de UPDATE sin identidad no vería ninguna fila, y
-- darle una de SELECT equivalente abriría a la app la lectura de rúbricas de todos los
-- tenants. El barrido va por función: cierra y devuelve cuántos cerró, sin exponer filas.
create or replace function cerrar_ensayos_vencidos() returns integer
language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_previo text := current_setting('winopo.membership_id', true);
  v_n      integer;
begin
  -- El trigger que limita columnas compara con la membership de la sesión: el barrido no
  -- tiene rol, así que se le quita el contexto y se le devuelve tal cual al terminar.
  perform set_config('winopo.membership_id', '', true);

  update ensayo_tribunal
     set estado = 'cerrado', cerrado_at = now()
   where estado = 'informado'
     and informado_at < now() - interval '72 hours';

  get diagnostics v_n = row_count;

  perform set_config('winopo.membership_id', coalesce(v_previo, ''), true);
  return v_n;
end;
$$;

comment on function cerrar_ensayos_vencidos() is
  'Cierra los ensayos informados hace más de 72 h. Idempotente; devuelve cuántos cerró.';

revoke all on function cerrar_ensayos_vencidos() from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'winopo_app') then
    execute 'grant execute on function cerrar_ensayos_vencidos() to winopo_app';
  end if;
end;
$$;

create policy ensayo_staff_actualiza on ensayo_tribunal
  for update using (
    tenant_id = winopo_tenant()
    and winopo_es_staff()
  ) with check (
    tenant_id = winopo_tenant()
    and winopo_es_staff()
  );

-- ───────────── Recuento de la bolsa: lectura cruzada, solo agregado ─────────────
-- El checkout necesita saber cuántos evaluadores activos hay en una especialidad, y esos
-- evaluadores viven en otros tenants. En vez de abrir un SELECT cruzado sobre filas ajenas
-- (que expondría quién está en la bolsa), se expone un recuento. SECURITY DEFINER, sin SQL
-- dinámico y sin devolver identidades.
create or replace function evaluadores_activos(p_especialidad uuid) returns integer
language sql stable security definer
set search_path = public, pg_temp as $$
  select count(*)::integer
    from bolsa_evaluador b
   where b.especialidad_id = p_especialidad
     and b.estado = 'activo';
$$;

comment on function evaluadores_activos(uuid) is
  'Evaluadores activos por especialidad. La única lectura cruzada que devuelve un agregado: un número, no identidades.';

revoke all on function evaluadores_activos(uuid) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'winopo_app') then
    execute 'grant execute on function evaluadores_activos(uuid) to winopo_app';
  end if;
end;
$$;




