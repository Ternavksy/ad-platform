# Ad Platform — Go + Python
 
Backend архитектура рекламной платформы production-уровня, реализованная на **Go** и **Python**, с **микросервисами**, **event-driven коммуникацией**, **OLTP/OLAP разделением**, **асинхронными воркерами** и **масштабируемой инфраструктурой**.

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
- ACID-транзакции для всех финансовых операций

**В сервисе:**
- Регистрация пользователей
- Логин
- JWT-аутентификация
- Роли пользователей
- FastAPI AutoDocs (`/docs`)
- SQLAlchemy + Alembic
- OLTP схема БД с таблицами: `users`, `balances`, `transactions`, `campaigns`, `ads`, `creatives`
- Все таблицы создаются через Alembic, имеют FK и соответствуют ACID-подходу

### `ads-api` (Go)
HTTP API для рекламного кабинета:
- CRUD для Campaign / Ad / Creative
- работа с MySQL через `sqlx`
- бизнес-логика
- подготовка событий (в будущем)

❗️ Не владеет схемой БД и не делает миграции.

**В сервисе:**
- подключение к MySQL через `sqlx`
- store-слой для Campaign (`Create`, `GetByID`)
- подготовлена архитектура: handler → service → store
- HTTP-эндпоинты: добавлены CRUD-операции `GET`, `POST`, `PUT`, `DELETE` для соответствующих ресурсов (Campaigns, Ads, Creative)

### `analytics-api` (FastAPI, Python)
**OLAP сервис аналитики** — работа с ClickHouse для хранения и анализа рекламной статистики.

Отвечает за:
- Хранение статистики по кампаниям, объявлениям и креативам
- Аналитические запросы и агрегацию данных
- Интеграцию с RabbitMQ для потоковой загрузки данных
- Предоставление REST API для доступа к аналитике

**В сервисе:**
- Интеграция с ClickHouse
- Созданные таблицы: `ads_stats`, `campaign_stats`, `creative_stats`
- REST API для получения аналитики с фильтрацией по датам, кампаниям, объявлениям и креативам
- Поддержка OLAP-запросов для глубокого анализа рекламной эффективности

---

## ⚒️ Конфигурация через .env
Проект использует переменные окружения.
В папке infra:
```bash
cp env.example .env
```

В .env необходимо задать:
- MYSQL_ROOT_PASSWORD
- MYSQL_PASSWORD
- SECRET_KEY
- GF_SECURITY_ADMIN_PASSWORD

.env не коммитится в git (добавлен в .gitignore).

---

## 🚀 Локальный запуск

### 1. Проверка окружения
```bash
make check
```

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

## 🏎️ 🚀 🔥 Развертывание в production с Ansible

Ansible использует шаблоны Jinja2 для генерации конфигурационных файлов на основе переменных.

### 1. Установка зависимостей
```bash
cd infra/ansible
ansible-galaxy install -r requirements.yml
```

### 2. Настройка инвентаризации
Отредактируйте файл `inventory/production.yml` с указанием IP-адресов ваших серверов.

### 3. Настройка переменных
Отредактируйте `group_vars/production.yml` с конфигурацией для production окружения.

### 4. Запуск плейбука
```bash
ansible-playbook -i inventory/production.yml playbook.yml
```

### 5. Проверка развертывания
```bash
# Проверка запущенных контейнеров
ansible production -m shell -a "docker ps"

# Проверка работоспособности приложения
ansible production -m uri -a "url=http://localhost:8080/health"
```

### Особенности production развертывания

**Масштабируемость**: Ansible позволяет развертывать сервисы на нескольких хостах:
- Базы данных на отдельных серверах
- Приложения на разных серверах
- Мониторинг на выделенном сервере

**Безопасность**: 
- SSH-доступ к серверам
- Управление секретами через Ansible Vault
- Настройка брандмауэра
- SSL/TLS сертификаты

**Производительность**:
- Оптимизация под нагрузку
- Автоматическое масштабирование
- Выделение ресурсов под каждый сервис

**Мониторинг**:
- Prometheus для сбора метрик
- Grafana для визуализации
- AlertManager для оповещений
- Автоматическое резервное копирование

**Резервное копирование**:
- Автоматическое резервное копирование баз данных
- Резервное копирование конфигурации
- Резервное копирование метрик мониторинга


## 📊 ClickHouse

**🎯 Оптимизированные таблицы**
- `ads_stats` - детальная статистика по объявлениям
- `campaign_stats` - агрегированная статистика по кампаниям  
- `creative_stats` - аналитика по креативам
- MergeTree движок для эффективного хранения и индексации

**📈 Масштабируемая аналитика рекламы**
- Хранение и анализ статистики по кампаниям, объявлениям и креативам
- Быстрое получение метрик: показы, клики, стоимость, CTR
- Поддержка временных рядов для анализа эффективности рекламы

### Практическое использование:

**1. Создание базы данных и таблиц:**
```bash
# Создание базы данных analytics
curl -s -X POST 'http://localhost:8123/' -d "CREATE DATABASE IF NOT EXISTS analytics"

# Создание таблиц для хранения рекламной статистики
curl -s -X POST 'http://localhost:8123/' -d "
CREATE TABLE IF NOT EXISTS analytics.ads_stats (
    date Date,
    campaign_id UInt64,
    ad_id UInt64,
    creative_id UInt64,
    impressions UInt64,
    clicks UInt64,
    cost Float64,
    timestamp DateTime
) ENGINE = MergeTree()
ORDER BY (date, campaign_id, ad_id)
"
```

**2. Загрузка и анализ данных:**
- Таблицы оптимизированы для хранения миллионов записей о показах, кликах и расходах
- MergeTree движок обеспечивает быструю вставку и эффективные агрегационные запросы

**3. Интеграция с микросервисами:**
- analytics-api предоставляет REST API для доступа к данным ClickHouse
- Поддержка фильтрации по датам, кампаниям, объявлениям и креативам
- Интеграция с RabbitMQ для потоковой загрузки данных в реальном времени

## 🚀 Tarantool

**🎯 Высокопроизводительное хранилище для кэширования и очередей**
- Используется для кэширования данных и управления очередями задач
- Поддержка Lua-скриптов для сложной логики обработки данных
- Высокая производительность для операций чтения/записи в реальном времени

**📈 Интеграция с микросервисами**
- `ads-api` использует Tarantool для кэширования данных через `internal/store/tarantool.go`
- Lua-скрипты для сложных операций с данными и управления очередями
- Обеспечивает низкую задержку для критически важных операций

### Практическое использование:

**1. Инициализация Tarantool:**
```bash
infra/scripts/init_tarantool.lua
```

**2. Интеграция с Go-сервисами:**
- `services/ads-api/internal/store/tarantool.go` - реализация хранилища на Go
- Поддержка Lua-скриптов для сложной логики обработки данных
- Кэширование часто используемых данных для ускорения ответов

**3. Lua-скрипты для бизнес-логики:**
- Сложные операции с данными, которые требуют атомарности
- Используется для кэширования данных и реализации rate limiting
- Реализация кастомной логики обработки данных

## 🐰 RabbitMQ

**🎯 Асинхронная обработка событий и сообщений**
- Используется для асинхронной обработки событий рекламной платформы
- Обеспечивает надежную доставку сообщений между микросервисами
- Поддержка различных типов обменников (exchanges) и очередей

**📈 Архитектура сообщений**
- **Обменник**: `ad_events` (topic type) для маршрутизации событий
- **Очереди**: `ad_worker_queue` для обработки событий воркерами
- **Routing keys**: `ad.created`, `ad.updated` для разделения типов событий

**🔧 Интеграция с микросервисами**

### Go-сервисы (`ads-api`)
- **RabbitMQService**: `services/ads-api/internal/service/rabbitmq.go`
- **Публикация событий**: Автоматическая отправка сообщений при создании/обновлении объявлений
- **Интеграция**: Встроена в `AdService` для асинхронной обработки
- **Безопасность**: Ошибки публикации не прерывают основные операции

### Python-сервисы
- **auth-api**: `services/auth-api/app/core/rabbitmq.py` - базовый сервис для подключения
- **analytics-api**: `services/analytics-api/app/core/rabbitmq.py` - асинхронный consumer для аналитики
- **Воркеры**: `services/workers/worker-py/worker.py` и `services/workers/worker-go/main.go` - обработка сообщений

### Практическое использование:

**1. Запуск RabbitMQ:**
```bash
# RabbitMQ доступен на порту 5672 (AMQP) и 15672 (Web UI)
# Web UI: http://localhost:15672 (логин: guest, пароль: guest)
```

**2. Публикация событий из Go:**
```go
// Автоматическая публикация при создании объявления
if s.rabbitmq != nil {
    if err := s.rabbitmq.PublishAdCreated(ctx, fmt.Sprintf("%d", ad.ID)); err != nil {
        // Логируем ошибку, но не прерываем операцию
    }
}
```

**3. Обработка сообщений в воркерах:**
```go
// Go воркер обрабатывает сообщения из очереди
func (w *AdEventWorker) processMessage(d amqp091.Delivery) {
    var data map[string]interface{}
    json.Unmarshal(d.Body, &data)
    
    eventType := data["type"].(string)
    switch eventType {
    case "ad_created":
        w.handleAdCreated(data)
    case "ad_updated":
        w.handleAdUpdated(data)
    }
}
```

**4. Асинхронная аналитика:**
- analytics-api потребляет сообщения для сбора статистики
- Реализована асинхронная обработка через asyncio
- Сообщения обрабатываются в фоновом режиме без блокировки основного API

**5. Безопасность и отказоустойчивость:**
- Все сервисы имеют graceful shutdown при остановке
- Обработка ошибок подключения к RabbitMQ
- Автоматическое восстановление соединений
- Подтверждение обработки сообщений (ACK/NACK)

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

- Python 3.12

- FastAPI

- SQLAlchemy

- Alembic

- Django

- Lua

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

- Jinja2 - шаблонизатор, используемый для генерации конфигурационных файлов в Ansible

## ✅ CI/CD и тесты

- В репозиторий добавлен workflow GitHub Actions (`.github/workflows/ci.yml`) для автоматического запуска сборки и тестов при `push`/`pull_request`.
- CI запускает:
	- Go-тесты для `services/ads-api` (используется SQLite/CGO для in-memory тестов).
	- Python-тесты для `services/auth-api` и `services/analytics-api` (Python 3.12).
- Локальные тесты также добавлены в кодовую базу:
	- `services/auth-api/tests` — безопасность и интеграционные проверки (in-memory DB override).
	- `services/analytics-api/tests` — health/metrics checks.
	- `services/ads-api/internal/model/tests` и `services/ads-api/internal/service/tests` — проверка моделей и service-логики с in-memory sqlite.
- CI устанавливает необходимые системные зависимости (gcc, sqlite dev) и включает `CGO_ENABLED` для корректной работы `github.com/mattn/go-sqlite3`.


## 🔒 ACID-транзакции

Проект реализует полную поддержку ACID-транзакций для всех финансовых операций:

### Атомарность (Atomicity)
- Все операции выполняются в рамках единой транзакции
- При ошибках происходит автоматический rollback
- Гарантировано, что либо все изменения применяются, либо ни одно

### Согласованность (Consistency)
- Используются внешние ключи для поддержания целостности данных
- Транзакции ссылаются на созданные объявления и креативы
- Соблюдение бизнес-правил на уровне базы данных

### Изолированность (Isolation)
- Используется `SELECT ... FOR UPDATE` для предотвращения гонок
- Блокировка строк во время финансовых операций
- Защита от одновременного изменения балансов

### Долговечность (Durability)
- Все изменения фиксируются в базе данных
- Транзакции сохраняются даже при сбоях системы
- Гарантированное сохранение финансовой истории

### Реализация
- **Python (auth-api)**: SQLAlchemy транзакции с `with_for_update()`
- **Go (ads-api)**: sqlx транзакции с defer rollback/commit
- **Связь сущностей**: `transaction_id` в таблицах `ads` и `creatives`
- **API endpoints**: `/billing/deposit`, `/billing/withdraw`, `/billing/charge-for-ad`, `/billing/charge-for-creative`
- **Тестирование**: Все транзакции протестированы на корректность и изолированность

## 🔑 Шифрование и безопасность

Проект реализует современные методы шифрования и защиты данных:

### Хэширование паролей
- **Алгоритм**: bcrypt
- **Безопасность**: Защита от атак по словарю и rainbow-таблицам
- **Реализация**: `hash_password()` и `verify_password()` функции в `app/core/security.py`

### JWT-аутентификация
- **Алгоритм**: HS256 (HMAC с SHA-256)
- **Секретный ключ**: Конфигурируется через переменную окружения `SECRET_KEY`
- **Срок действия**: 30 минут (настраивается через `ACCESS_TOKEN_EXPIRE_MINUTES`)
- **Реализация**: `create_access_token()` функция в `app/core/security.py`

### Защита данных
- **ENV-переменные**: Все чувствительные данные хранятся в `.env` файле
- **Git-игнорирование**: `.env` файл добавлен в `.gitignore`
- **Production**: Рекомендуется использовать секреты Kubernetes/Docker Swarm
- **Валидация**: Все входные данные проходят валидацию через Pydantic модели
