-- Datos sintéticos para local y CI. Nunca datos de alumnos reales.
-- Los hash de clave son de relleno: no permiten iniciar sesión. El login se prueba en los tests.

set winopo.tenant_id = '';

insert into tenant (id, slug, nombre)
values ('11111111-1111-1111-1111-111111111111', 'prepa-uno', 'Preparación Uno'),
       ('22222222-2222-2222-2222-222222222222', 'prepa-dos', 'Preparación Dos')
on conflict (slug) do nothing;

insert into app_user (id, correo, nombre, hash_clave)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'preparador@prepa-uno.test', 'Preparador Uno', 'x'),
       ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'opositor@prepa-uno.test', 'Opositor Uno', 'x'),
       ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'preparador@prepa-dos.test', 'Preparador Dos', 'x')
on conflict (correo) do nothing;

insert into membership (tenant_id, user_id, rol)
values ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'preparador'),
       ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'opositor'),
       ('22222222-2222-2222-2222-222222222222', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'preparador')
on conflict (tenant_id, user_id) do nothing;
