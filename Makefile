.PHONY: up down build check

up:
	docker-compose -f infra/docker-compose.yml up --build

down:
	docker-compose -f infra/docker-compose.yml down

build:
	docker-compose -f infra/docker-compose.yml build

check:
	bash infra/scripts/check_env.sh