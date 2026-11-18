-- Pruebas de esquema de 0015_especialidad_tarifa.
-- Se ejecutan sobre una base recién migrada (make test-db). No son idempotentes: el
-- objetivo es que el esquema falle antes de que falle el checkout.

create or replace function test_ok(p_ok boolean, p_que text) returns void
language plpgsql as $$
begin
  if p_ok is not true then
    raise exception 'FALLO: %', p_que;
  end if;
  raise notice 'ok · %', p_que;
end;
$$;

create or replace function test_falla(p_sql text, p_estado text, p_que text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate = p_estado then
      raise notice 'ok · %', p_que;
      return;
    end if;
    raise exception 'FALLO: % (esperaba %, llegó %: %)', p_que, p_estado, sqlstate, sqlerrm;
  end;
  raise exception 'FALLO: % (no falló)', p_que;
end;
$$;

-- ───────────── Datos de prueba ─────────────

insert into especialidad (id, slug, nombre, grupo) values
  ('00000000-0000-0000-0000-0000000000e1', 'administrativo-c1', 'Administrativo C1', 'C1'),
  ('00000000-0000-0000-0000-0000000000e2', 'administrativo-c2', 'Administrativo C2', 'C2');

insert into tarifa (tipo, grupo, modalidad, precio_neto_cents, pago_evaluador_cents,
                    vigente_desde, fuente)
values ('supuesto_escrito', 'C1', 'propio', 6198, null, '2026-09-01',
        'prueba · tarifa sintética');

insert into tarifa (tipo, grupo, modalidad, precio_neto_cents, pago_evaluador_cents,
                    vigente_desde, fuente)
values ('oral', 'C2', 'ciego', 12397, 3000, '2026-09-01', 'prueba · ciego sintético');

-- ───────────── Resolución de la tarifa ─────────────

select test_ok(
  (select count(*) from tarifa_vigente('supuesto_escrito',
     '00000000-0000-0000-0000-0000000000e1', 'propio', '2026-10-01')) = 1,
  'la tarifa se resuelve por el grupo de la especialidad');

select test_ok(
  (select count(*) from tarifa_vigente('supuesto_escrito',
     '00000000-0000-0000-0000-0000000000e2', 'propio', '2026-10-01')) = 0,
  'un grupo sin tarifa devuelve cero filas (fail-closed)');

select test_ok(
  (select count(*) from tarifa_vigente('oral',
     '00000000-0000-0000-0000-0000000000e1', 'propio', '2026-10-01')) = 0,
  'un tipo sin tarifa devuelve cero filas (fail-closed)');

select test_ok(
  (select count(*) from tarifa_vigente('supuesto_escrito',
     '00000000-0000-0000-0000-0000000000e1', 'propio', '2026-08-31')) = 0,
  'antes de vigente_desde no hay tarifa');

-- ───────────── Reglas del esquema ─────────────

select test_falla(
  $sql$insert into tarifa (tipo, grupo, modalidad, precio_neto_cents, vigente_desde, fuente)
       values ('supuesto_escrito', 'C1', 'propio', 9000, '2026-10-01', 'prueba')$sql$,
  '23P01', 'abrir una tarifa que solapa la vigente falla');

select test_falla(
  $sql$update tarifa set precio_neto_cents = 9000
        where tipo = 'supuesto_escrito' and grupo = 'C1' and modalidad = 'propio'$sql$,
  'P0001', 'editar el precio de una tarifa falla');

select test_falla(
  $sql$delete from tarifa
        where tipo = 'supuesto_escrito' and grupo = 'C1' and modalidad = 'propio'$sql$,
  'P0001', 'borrar una tarifa falla');

select test_falla(
  $sql$insert into tarifa (tipo, grupo, modalidad, precio_neto_cents, vigente_desde, fuente)
       values ('oral', 'C1', 'ciego', 12397, '2026-09-01', 'prueba')$sql$,
  '23514', 'un ensayo ciego sin pago al evaluador falla');

select test_falla(
  $sql$insert into tarifa (tipo, grupo, modalidad, precio_neto_cents, pago_evaluador_cents,
                           vigente_desde, fuente)
       values ('oral', 'C1', 'propio', 12397, 3000, '2026-09-01', 'prueba')$sql$,
  '23514', 'un pago al evaluador en modalidad propio falla');

select test_falla(
  $sql$insert into tarifa (tipo, grupo, modalidad, precio_neto_cents, vigente_desde, fuente)
       values ('simulacro', 'C1', 'propio', 9000, '2026-09-01', '')$sql$,
  '23514', 'una tarifa sin fuente falla');

-- ───────────── Regla de negocio: el evaluador no se lleva más del 25 % ─────────────
-- No está en el DDL porque la cifra sigue sin firmar; se comprueba aquí para que el día
-- que alguien meta una tarifa con un pago desproporcionado salte el test y no la caja.

select test_ok(
  not exists (
    select 1 from tarifa
     where pago_evaluador_cents is not null
       and pago_evaluador_cents * 4 > precio_neto_cents
  ),
  'ningún pago al evaluador supera el 25 % del precio neto');

-- ───────────── Cierre y reapertura ─────────────

update tarifa set vigente_hasta = '2026-11-01'
 where tipo = 'supuesto_escrito' and grupo = 'C1' and modalidad = 'propio';

select test_ok(
  (select count(*) from tarifa_vigente('supuesto_escrito',
     '00000000-0000-0000-0000-0000000000e1', 'propio', '2026-11-01')) = 0,
  'el día de cierre la tarifa ya no está vigente');

select test_ok(
  (select count(*) from tarifa_vigente('supuesto_escrito',
     '00000000-0000-0000-0000-0000000000e1', 'propio', '2026-10-31')) = 1,
  'el día anterior al cierre sigue vigente');

insert into tarifa (tipo, grupo, modalidad, precio_neto_cents, vigente_desde, fuente)
values ('supuesto_escrito', 'C1', 'propio', 9000, '2026-11-01', 'prueba · tarifa nueva');

select test_ok(
  (select precio_neto_cents from tarifa_vigente('supuesto_escrito',
     '00000000-0000-0000-0000-0000000000e1', 'propio', '2026-11-01')) = 9000,
  'tras cerrar se puede abrir otra y el checkout ve la nueva');

-- ───────────── RLS: lee, no escribe ─────────────

set role winopo_app;

select test_ok((select count(*) from tarifa) >= 1, 'winopo_app lee el catálogo de tarifas');
select test_ok((select count(*) from especialidad) >= 1, 'winopo_app lee el catálogo de especialidades');

select test_falla(
  $sql$insert into especialidad (slug, nombre, grupo)
       values ('otra-c1', 'Otra C1', 'C1')$sql$,
  '42501', 'winopo_app no escribe especialidades');

select test_falla(
  $sql$insert into tarifa (tipo, grupo, modalidad, precio_neto_cents, vigente_desde, fuente)
       values ('oral', 'C2', 'propio', 9000, '2026-09-01', 'prueba')$sql$,
  '42501', 'winopo_app no escribe tarifas');

select test_falla(
  $sql$update tarifa set vigente_hasta = '2026-12-01'$sql$,
  '42501', 'winopo_app no cierra tarifas');

reset role;

