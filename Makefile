.RECIPEPREFIX = >
.DEFAULT_GOAL := help
.PHONY: help dev up down logs psql migrate seed build test test-db web-dev web-build landing e2e tree clean

COMPOSE := docker compose $(if $(wildcard .env),--env-file .env,) -p winopo -f infra/docker-compose.yml

# Si hay JDK 21 se compila a 21; si no, a 17 (el bytecode 17 corre en el runtime 21 de la imagen).
JVM_OBJETIVO := $(shell ls /usr/lib/jvm 2>/dev/null | grep -q '21' && echo 21 || echo 17)
GRADLE := cd core && ./gradlew -PjvmTarget=$(JVM_OBJETIVO)

help:
> @echo "WinOpo · comandos"
> @echo ""
> @echo "  make dev        Levanta PostgreSQL y Mailpit"
> @echo "  make up         Stack completo: db + core + worker + web"
> @echo "  make down       Para el stack"
> @echo "  make logs       Logs del stack"
> @echo "  make migrate    Aplica migrations/*.sql en orden"
> @echo "  make seed       Carga infra/seed/sintetica.sql (datos falsos)"
> @echo "  make psql       Abre psql contra la base de datos"
> @echo "  make build      Compila el backend (Kotlin, JVM $(JVM_OBJETIVO))"
> @echo "  make test       Tests JVM; ROJO si no se ejecuta ninguno"
> @echo "  make test-db    Esquema y RLS contra el PostgreSQL del stack"
> @echo "  make web-dev    Next.js en modo desarrollo"
> @echo "  make web-build  Build de produccion del frontend"
> @echo "  make landing    Sirve el landing de winopo.es en http://localhost:4000"
> @echo "  make e2e        Pruebas de extremo a extremo (Playwright)"
> @echo "  make tree       Arbol resumido"
> @echo "  make clean      Borra artefactos"

dev:
> @test -f .env || cp .env.example .env
> $(COMPOSE) up -d db mailpit
> @echo "PostgreSQL en 5432 y Mailpit en 8025. Siguiente: make migrate && make seed"

up:
> @test -f .env || cp .env.example .env
> $(COMPOSE) --profile app up -d --build
> @echo "App en http://localhost:3000 (web) y http://localhost:8080 (API)"

down:
> $(COMPOSE) --profile app down

logs:
> $(COMPOSE) --profile app logs -f --tail=100

migrate:
> @for f in migrations/*.sql; do \
>   echo "-> $$f"; \
>   $(COMPOSE) exec -T db psql -U $${POSTGRES_USER:-winopo} -d $${POSTGRES_DB:-winopo} -v ON_ERROR_STOP=1 < $$f || exit 1; \
> done
> @echo "Migraciones aplicadas."

seed:
> $(COMPOSE) exec -T db psql -U $${POSTGRES_USER:-winopo} -d $${POSTGRES_DB:-winopo} -v ON_ERROR_STOP=1 < infra/seed/sintetica.sql
> @echo "Datos sinteticos cargados."

psql:
> $(COMPOSE) exec db psql -U $${POSTGRES_USER:-winopo} -d $${POSTGRES_DB:-winopo}

build:
> $(GRADLE) build -x test

test:
> $(GRADLE) test

test-db:
> @echo "Esquema y RLS: se rehace el esquema public y se aplican las migraciones"
> $(COMPOSE) exec -T db psql -U $${POSTGRES_USER:-winopo} -d $${POSTGRES_DB:-winopo} -v ON_ERROR_STOP=1 \
>   -c 'drop schema if exists public cascade' -c 'create schema public'
> $(COMPOSE) exec -T db psql -U $${POSTGRES_USER:-winopo} -d $${POSTGRES_DB:-winopo} -v ON_ERROR_STOP=1 \
>   < infra/postgres/init.sql
> @$(MAKE) migrate
> @for f in tests/db/*.sql; do \
>   echo "-> $$f"; \
>   $(COMPOSE) exec -T db psql -U $${POSTGRES_USER:-winopo} -d $${POSTGRES_DB:-winopo} -v ON_ERROR_STOP=1 < $$f || exit 1; \
> done
> @echo "Esquema y RLS: OK."

web-dev:
> cd web && npm run dev

web-build:
> cd web && npm run build

# El landing es HTML estático: se sirve con cualquier servidor. En producción lo sirve Caddy.
landing:
> @echo "Landing en http://localhost:4000 (Ctrl+C para parar)"
> cd landing && python3 -m http.server 4000

e2e:
> cd tests/e2e && npx playwright test

tree:
> @find . -type f \
>   -not -path './node_modules/*' -not -path './.git/*' -not -path './core/build/*' \
>   -not -path './core/.gradle/*' -not -path './web/.next/*' -not -path './web/node_modules/*' \
>   | sed 's|^\./||' | sort

clean:
> rm -rf core/build web/.next web/out
