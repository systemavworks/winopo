-- Pruebas de esquema de 0016_bolsa_ensayo.
-- Cubren lo que el diseño anterior no cubría: la transición a 'informado', el cierre por
-- silencio bajo FORCE RLS, el evaluador ciego cross-tenant y el recuento de la bolsa.

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

-- ───────────── Datos de prueba: tres tenants ─────────────
-- A preparador, B opositor (alumno), C preparador que entra en la bolsa como evaluador.

insert into tenant (id, slug, nombre) values
  ('00000000-0000-0000-0000-0000000000a0', 'prepa-a', 'Preparador A'),
  ('00000000-0000-0000-0000-0000000000b0', 'opo-b',    'Opositor B'),
  ('00000000-0000-0000-0000-0000000000c0', 'prepa-c',  'Evaluador C');

insert into app_user (id, correo, nombre, hash_clave) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@ejemplo.test', 'Preparador A', 'x'),
  ('00000000-0000-0000-0000-0000000000b1', 'b@ejemplo.test', 'Opositor B',   'x'),
  ('00000000-0000-0000-0000-0000000000c1', 'c@ejemplo.test', 'Evaluador C',  'x');

insert into membership (id, tenant_id, user_id, rol) values
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0',
   '00000000-0000-0000-0000-0000000000a1', 'preparador'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b0',
   '00000000-0000-0000-0000-0000000000b1', 'opositor'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000c0',
   '00000000-0000-0000-0000-0000000000c1', 'preparador');

insert into especialidad (id, slug, nombre, grupo) values
  ('00000000-0000-0000-0000-0000000000d1', 'gestion-a2', 'Gestión A2', 'A2');

insert into tarifa (tipo, grupo, modalidad, precio_neto_cents, pago_evaluador_cents,
                    vigente_desde, fuente)
values
  ('supuesto_escrito', 'A2', 'ciego',  9917, 2400, '2026-09-01', 'prueba · ciego'),
  ('supuesto_escrito', 'A2', 'propio', 6198, null, '2026-09-01', 'prueba · propio');

-- ───────────── Validaciones de alta ─────────────

select test_falla(
  $sql$insert into bolsa_evaluador (tenant_id, membership_id, especialidad_id)
       values ('00000000-0000-0000-0000-0000000000b0',
               '00000000-0000-0000-0000-0000000000b2',
               '00000000-0000-0000-0000-0000000000d1')$sql$,
  'P0001', 'un opositor no entra en la bolsa de evaluadores');

select test_falla(
  $sql$insert into bolsa_evaluador (tenant_id, membership_id, especialidad_id)
       values ('00000000-0000-0000-0000-0000000000b0',
               '00000000-0000-0000-0000-0000000000c2',
               '00000000-0000-0000-0000-0000000000d1')$sql$,
  'P0001', 'una membership de otro tenant no entra en la bolsa');

insert into bolsa_evaluador (tenant_id, membership_id, especialidad_id)
values ('00000000-0000-0000-0000-0000000000c0',
        '00000000-0000-0000-0000-0000000000c2',
        '00000000-0000-0000-0000-0000000000d1');

select test_ok(true, 'el preparador evaluador entra en la bolsa');

-- ───────────── Ensayos ─────────────

select test_falla(
  $sql$insert into ensayo_tribunal (tenant_id, alumno_membership_id, especialidad_id, tipo,
         modalidad, origen, tarifa_id, cobrado_neto_cents, programado_para)
       values ('00000000-0000-0000-0000-0000000000b0',
               '00000000-0000-0000-0000-0000000000a2',
               '00000000-0000-0000-0000-0000000000d1',
               'supuesto_escrito', 'propio', 'plan',
               (select id from tarifa where grupo = 'A2' and modalidad = 'propio'),
               0, now())$sql$,
  'P0001', 'un alumno de otro tenant no puede tener ensayo en este espacio');

select test_falla(
  $sql$insert into ensayo_tribunal (tenant_id, alumno_membership_id, especialidad_id, tipo,
         modalidad, origen, tarifa_id, cobrado_neto_cents, stripe_ref, estado, programado_para)
       values ('00000000-0000-0000-0000-0000000000b0',
               '00000000-0000-0000-0000-0000000000b2',
               '00000000-0000-0000-0000-0000000000d1',
               'supuesto_escrito', 'ciego', 'compra',
               (select id from tarifa where grupo = 'A2' and modalidad = 'ciego'),
               9917, 'pi_sin_fecha', 'cancelado', now())$sql$,
  '23514', 'un ensayo cancelado sin fecha de cancelación falla');

-- f1: ciego comprado, asignado al evaluador del tenant C.
insert into ensayo_tribunal (id, tenant_id, alumno_membership_id, evaluador_membership_id,
  especialidad_id, tipo, modalidad, origen, tarifa_id, cobrado_neto_cents,
  pago_evaluador_cents, stripe_ref, estado, programado_para)
values ('00000000-0000-0000-0000-0000000000f1',
  '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b2',
  '00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000d1',
  'supuesto_escrito', 'ciego', 'compra',
  (select id from tarifa where grupo = 'A2' and modalidad = 'ciego'),
  9917, 2400, 'pi_prueba_f1', 'asignado', now() + interval '3 days');

-- f2: propio del plan, ya informado hace 80 h: el candidato del cierre por silencio.
insert into ensayo_tribunal (id, tenant_id, alumno_membership_id, evaluador_membership_id,
  especialidad_id, tipo, modalidad, origen, tarifa_id, cobrado_neto_cents, estado,
  programado_para, informado_at)
values ('00000000-0000-0000-0000-0000000000f2',
  '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b2',
  '00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000d1',
  'supuesto_escrito', 'propio', 'plan',
  (select id from tarifa where grupo = 'A2' and modalidad = 'propio'),
  0, 'informado', now() - interval '10 days', now() - interval '80 hours');

-- f3: solicitado, sin evaluador todavía.
insert into ensayo_tribunal (id, tenant_id, alumno_membership_id, especialidad_id, tipo,
  modalidad, origen, tarifa_id, cobrado_neto_cents, estado, programado_para)
values ('00000000-0000-0000-0000-0000000000f3',
  '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b2',
  '00000000-0000-0000-0000-0000000000d1', 'supuesto_escrito', 'propio', 'plan',
  (select id from tarifa where grupo = 'A2' and modalidad = 'propio'),
  0, 'solicitado', now() + interval '7 days');

select test_ok(true, 'los tres ensayos de prueba se insertan');

select test_falla(
  $sql$update ensayo_tribunal set estado = 'asignado'
        where id = '00000000-0000-0000-0000-0000000000f3'$sql$,
  '23514', 'no se asigna un ensayo sin evaluador');

select test_falla(
  $sql$update ensayo_tribunal set cobrado_neto_cents = 1
        where id = '00000000-0000-0000-0000-0000000000f1'$sql$,
  'P0001', 'los importes del ensayo se congelan');

select test_falla(
  $sql$update ensayo_tribunal
           set alumno_membership_id = '00000000-0000-0000-0000-0000000000a2'
         where id = '00000000-0000-0000-0000-0000000000f1'$sql$,
  'P0001', 'el ensayo no cambia de alumno');

-- f4: informado hace un instante. Sirve para comprobar que el cierre por silencio no se
-- adelanta: 72 h son 72 h.
insert into ensayo_tribunal (id, tenant_id, alumno_membership_id, evaluador_membership_id,
  especialidad_id, tipo, modalidad, origen, tarifa_id, cobrado_neto_cents, estado,
  programado_para, informado_at)
values ('00000000-0000-0000-0000-0000000000f4',
  '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b2',
  '00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000d1',
  'supuesto_escrito', 'propio', 'plan',
  (select id from tarifa where grupo = 'A2' and modalidad = 'propio'),
  0, 'informado', now() - interval '9 days', now());

-- ───────────── Evaluador ciego: la única lectura cruzada ─────────────

set role winopo_app;
select set_config('winopo.tenant_id', '00000000-0000-0000-0000-0000000000c0', false);
select set_config('winopo.membership_id', '00000000-0000-0000-0000-0000000000c2', false);

select test_ok(
  (select count(*) from ensayo_tribunal
    where id = '00000000-0000-0000-0000-0000000000f1') = 1,
  'el evaluador ciego ve el ensayo que se le asignó aunque sea de otro tenant');

select test_ok(
  (select count(*) from ensayo_tribunal
    where id = '00000000-0000-0000-0000-0000000000f3') = 0,
  'el evaluador no ve ensayos que no le han asignado');

select test_ok((select count(*) from bolsa_evaluador) = 1, 'el evaluador ve su alta en la bolsa');

select test_ok(
  evaluadores_activos('00000000-0000-0000-0000-0000000000d1') = 1,
  'el recuento de la bolsa atraviesa tenants y solo devuelve un número');

select test_falla(
  $sql$update ensayo_tribunal set programado_para = now()
        where id = '00000000-0000-0000-0000-0000000000f1'$sql$,
  'P0001', 'el evaluador no mueve la fecha del ensayo');

update ensayo_tribunal set estado = 'informado', informado_at = now()
 where id = '00000000-0000-0000-0000-0000000000f1';

select test_ok(
  (select estado from ensayo_tribunal
    where id = '00000000-0000-0000-0000-0000000000f1') = 'informado',
  'el evaluador pasa a informado: USING y WITH CHECK separados');

-- ───────────── Alumno ─────────────

select set_config('winopo.tenant_id', '00000000-0000-0000-0000-0000000000b0', false);
select set_config('winopo.membership_id', '00000000-0000-0000-0000-0000000000b2', false);

select test_ok((select count(*) from ensayo_tribunal) = 4, 'el alumno ve sus cuatro ensayos');
select test_ok((select count(*) from bolsa_evaluador) = 0, 'el alumno no ve la bolsa de otros tenants');

select test_falla(
  $sql$update ensayo_tribunal set rubrica = '{}'::jsonb
        where id = '00000000-0000-0000-0000-0000000000f1'$sql$,
  'P0001', 'el alumno no escribe la rúbrica');

update ensayo_tribunal set estado = 'reclamado'
 where id = '00000000-0000-0000-0000-0000000000f1';

select test_ok(
  (select estado from ensayo_tribunal
    where id = '00000000-0000-0000-0000-0000000000f1') = 'reclamado',
  'el alumno reclama el informe');

-- ───────────── Cierre por silencio: sin membership, sin staff ─────────────

select set_config('winopo.tenant_id', '', false);
select set_config('winopo.membership_id', '', false);

with cerrados as (
  update ensayo_tribunal set estado = 'cerrado', cerrado_at = now()
   where id = '00000000-0000-0000-0000-0000000000f2'
  returning 1
)
select test_ok((select count(*) from cerrados) = 0,
  'la app no cierra ensayos por su cuenta: no hay política de UPDATE para eso');

select test_ok(cerrar_ensayos_vencidos() = 1,
  'el barrido cierra el informe de hace más de 72 h');

select test_ok(cerrar_ensayos_vencidos() = 0,
  'el barrido es idempotente: la segunda pasada no cierra nada más');

with borrados as (
  delete from ensayo_tribunal where id = '00000000-0000-0000-0000-0000000000f1'
  returning 1
)
select test_ok((select count(*) from borrados) = 0,
  'ninguna política permite borrar un ensayo');

reset role;

select test_ok(
  (select estado from ensayo_tribunal
    where id = '00000000-0000-0000-0000-0000000000f2') = 'cerrado',
  'el cierre por silencio quedó escrito');

select test_ok(
  (select estado from ensayo_tribunal
    where id = '00000000-0000-0000-0000-0000000000f4') = 'informado',
  'el barrido no se adelanta: el informe de hace un minuto sigue abierto');


