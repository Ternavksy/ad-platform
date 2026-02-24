# Ad Platform — Go + Python
 
Проект демонстрирует backend-разработку с использованием **Go**, **Python**, **микросервисной архитектуры**.

---

## 🧱 Архитектура проекта

Проект организован как **моно-репозиторий с микросервисами**.


---

## 🔹 Роли сервисов

### `auth-api` (FastAPI, Python)
**OLTP Core сервиса** — владелец схемы данных и ACID-консистентности.

Отвечает за:
- пользователей и роли
- балансы
- кампании, объявления, креативы
- финансовые транзакции
- миграции БД (Alembic)

### `ads-api` (Go)
HTTP API для рекламного кабинета:
- CRUD для Campaign / Ad / Creative
- работа с MySQL через `sqlx`
- бизнес-логика
- подготовка событий (в будущем)

❗️ Не владеет схемой БД и не делает миграции.

---

## 🧩 Реализовано на текущий момент

### Auth API
- Регистрация пользователей
- Логин
- JWT-аутентификация
- Роли пользователей
- FastAPI AutoDocs (`/docs`)
- SQLAlchemy + Alembic

### OLTP схема БД
Созданы таблицы:
- `users`
- `balances`
- `transactions`
- `campaigns`
- `ads`
- `creatives`

Все таблицы:
- создаются через Alembic
- имеют FK
- соответствуют ACID-подходу

### Ads API (Go)

На данный момент:
- подключение к MySQL через `sqlx`
- store-слой для Campaign (`Create`, `GetByID`)
- подготовлена архитектура: handler → service → store


---

## 🚀 Локальный запуск

### 1. Проверка окружения
```bash ```
make check

### 2. Запуск всех сервисов
make up

Будут подняты:

- MySQL

- RabbitMQ

- Redis

- Tarantool

- ClickHouse

- auth-api

- ads-api

- analytics-api

- admin-panel

## 🔍 Проверка сервисов

### Auth API
Swagger UI: http://localhost:8000/docs
Health check: curl http://localhost:8000/health

### Ads API
Health check: curl http://localhost:8080/health


- **HTTP-эндпоинты:** добавлены CRUD-операции `GET`, `POST`, `PUT`, `DELETE` для соответствующих ресурсов (Campaigns, Ads, Creative) в `ads-api`.

- **Мониторинг:** добавлена интеграция с Prometheus и Grafana. Prometheus доступен по http://localhost:9090, Grafana — http://localhost:3000 (админ: `admin1!` / `admin1!`).

- **Метрики приложений:** в `ads-api` и `auth-api` добавлен endpoint `/metrics` в Prometheus-формате. Prometheus собирает их по таргетам в `infra/prometheus/prometheus.yml`.

**Проверка метрик и экспортёров**

- Ads API метрики: `curl http://localhost:8080/metrics`
- Auth API метрики: `curl http://localhost:8000/metrics`
- mysqld_exporter: `curl http://localhost:9104/metrics`
- node_exporter: `curl http://localhost:9100/metrics`

Чтобы `mysqld_exporter` корректно собирал метрики, создайте в MySQL отдельного пользователя `metrics` и дайте минимальные права:

```bash
docker-compose exec mysql mysql -u root -prootpassword -e "\
CREATE USER IF NOT EXISTS 'metrics'@'%' IDENTIFIED BY 'metrics_password'; \
GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'metrics'@'%'; \
FLUSH PRIVILEGES;"
```

В `infra/docker-compose.yml` `mysqld_exporter` использует DSN `metrics:metrics_password@tcp(mysql:3306)/`.


## 🛠️ Используемые технологии

### Backend

- Go 1.21+

- Gin

- sqlx

- Python 3.11

- FastAPI

- SQLAlchemy

- Alembic

- Django

### Infrastructure

- Docker

- Docker Compose

- MySQL 8

- RabbitMQ

- Redis

- Tarantool

- ClickHouse

- Prometheus

- Grafana