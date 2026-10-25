COMPOSE = docker compose --env-file infra/.env -f infra/docker-compose.yml

.PHONY: check build up up-detached down test smoke verify verify-all mobile-get mobile-test mobile-analyze mobile-apk mobile-check mobile-run

check:
	bash infra/scripts/check_env.sh

build: check
	$(COMPOSE) build

up: check
	$(COMPOSE) up --build

up-detached: check
	$(COMPOSE) up --build --detach --wait

down:
	$(COMPOSE) down

test: check
	docker build --target test -t ad-platform-ads-api-test services/ads-api
	$(COMPOSE) build auth-api analytics-api admin-panel ad-worker go-worker
	$(COMPOSE) run --rm --no-deps -e SECRET_KEY=test_secret_key_for_tests_32_chars -e DATABASE_URL=sqlite:////tmp/auth-test.db auth-api python -m pytest -q
	$(COMPOSE) run --rm --no-deps analytics-api python -m pytest -q
	$(COMPOSE) run --rm --no-deps admin-panel python manage.py test
	$(COMPOSE) run --rm --no-deps ad-worker python -m unittest discover -s tests -v
	$(COMPOSE) run --rm --no-deps go-worker go test ./...
	$(COMPOSE) run --rm --no-deps go-worker go vet ./...

smoke:
	bash infra/scripts/smoke_test.sh

verify: test up-detached smoke

verify-all: verify mobile-check

mobile-get:
	cd apps/mobile && flutter pub get

mobile-test:
	cd apps/mobile && flutter test

mobile-analyze:
	cd apps/mobile && flutter analyze

mobile-apk:
	cd apps/mobile && flutter build apk --debug

mobile-check: mobile-analyze mobile-test mobile-apk

mobile-run:
	cd apps/mobile && flutter run
