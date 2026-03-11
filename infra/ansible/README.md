# Ansible Инфраструктура для Ad Platform

Этот каталог содержит Ansible плейбуки и роли для развертывания и управления инфраструктурой Ad Platform.

## Сравнение с Docker Compose

### Docker Compose (infra/docker-compose.yml)
**Назначение**: Локальная разработка и тестирование
- **Простота**: Быстрый запуск всех сервисов одной командой `docker-compose up`
- **Локальное окружение**: Все сервисы работают на одном хосте
- **Автоматизация**: Автоматическое создание сетей, volumes и зависимостей
- **Health checks**: Встроенные проверки работоспособности сервисов
- **Мониторинг**: Prometheus и Grafana для локального мониторинга

### Ansible (infra/ansible/)
**Назначение**: Продуктивное развертывание и управление инфраструктурой
- **Масштабируемость**: Развертывание на нескольких хостах
- **Гибкость**: Разделение сервисов по разным серверам
- **Безопасность**: SSH-доступ, управление секретами через Vault
- **Производительность**: Оптимизация под нагрузку
- **Резервное копирование**: Автоматическое резервное копирование данных
- **Мониторинг**: Расширенный стек мониторинга с алертами

## Обзор

Ansible настройка предоставляет автоматическое развертывание для:
- **Общая инфраструктура**: Docker, сетевые настройки, безопасность
- **Сервисы баз данных**: MySQL, Tarantool, ClickHouse, RabbitMQ
- **Сервисы приложений**: Auth API, Ads API, Analytics API, Admin Panel, Worker Go, Worker Python
- **Мониторинг**: Prometheus, Grafana, AlertManager

## Структура каталогов

```
infra/ansible/
├── inventory/              # Инвентаризация для разных окружений
│   ├── production.yml      # Хосты production окружения
│   ├── staging.yml         # Хосты staging окружения
│   └── development.yml     # Хосты development окружения
├── group_vars/             # Переменные для групп
│   ├── all.yml            # Глобальные переменные для всех окружений
│   ├── production.yml     # Переменные для production
│   ├── staging.yml        # Переменные для staging
│   └── development.yml    # Переменные для development
├── host_vars/             # Переменные для конкретных хостов
├── roles/                 # Ansible роли
│   ├── common/           # Общая системная конфигурация
│   ├── database/         # Развертывание сервисов баз данных
│   ├── application/      # Развертывание сервисов приложений
│   └── monitoring/       # Развертывание стека мониторинга
├── templates/            # Шаблоны Jinja2
├── playbook.yml          # Основной плейбук развертывания
├── requirements.yml      # Требования к коллекциям Ansible
└── README.md            # Этот файл
```

## Предварительные требования

### Системные требования
- Ansible 2.10 или новее
- Python 3.8 или новее
- SSH доступ к целевым хостам
- Docker и Docker Compose на целевых хостах

### Установка коллекций Ansible
```bash
ansible-galaxy install -r requirements.yml
```

## Конфигурация окружения

### Development окружение
- Развертывание на одном хосте
- Локальный Docker registry
- Включен режим отладки
- Минимальные лимиты ресурсов

### Staging окружение
- Многохостовое развертывание
- Staging registry
- Конфигурация, похожая на production
- Уменьшенные лимиты ресурсов

### Production окружение
- Многохостовое развертывание
- Production registry
- Конфигурация высокой доступности
- Полное выделение ресурсов

## Использование

### 1. Установка зависимостей
```bash
cd infra/ansible
ansible-galaxy install -r requirements.yml
```

### 2. Настройка инвентаризации
Отредактируйте соответствующий файл инвентаризации в `inventory/`:
- `production.yml` - Хосты production
- `staging.yml` - Хосты staging
- `development.yml` - Хосты development

### 3. Настройка переменных
Отредактируйте переменные групп в `group_vars/`:
- `all.yml` - Глобальная конфигурация
- `production.yml` - Настройки для production
- `staging.yml` - Настройки для staging
- `development.yml` - Настройки для development

### 4. Запуск плейбука

#### Развертывание в Development
```bash
ansible-playbook -i inventory/development.yml playbook.yml
```

#### Развертывание в Staging
```bash
ansible-playbook -i inventory/staging.yml playbook.yml
```

#### Развертывание в Production
```bash
ansible-playbook -i inventory/production.yml playbook.yml
```

#### Развертывание конкретной роли
```bash
ansible-playbook -i inventory/production.yml playbook.yml --tags "database"
```

### 5. Проверка развертывания
```bash
# Проверка запущенных контейнеров
ansible production -m shell -a "docker ps"

# Проверка работоспособности приложения
ansible production -m uri -a "url=http://localhost:8080/health"
```

## Роли

### Common роль
Настраивает общие системные параметры:
- Установка и конфигурация Docker
- Настройка брандмауэра
- Управление SSH ключами
- Установка пакетов
- Конфигурация часового пояса

### Database роль
Развертывает и настраивает сервисы баз данных:
- MySQL с пользовательской конфигурацией
- Tarantool для кэширования
- ClickHouse для аналитики
- RabbitMQ для обмена сообщениями
- Инициализация и миграции баз данных

### Application роль
Развертывает сервисы приложений:
- Сервис Auth API
- Сервис Ads API
- Сервис Analytics API
- Сервис Admin Panel
- Worker Go для обработки задач
- Worker Python для фоновых операций
- Nginx reverse proxy
- Управление SSL сертификатами
- Автоматическое масштабирование сервисов

### Monitoring роль
Развертывает стек мониторинга:
- Prometheus для сбора метрик
- Grafana для визуализации
- AlertManager для оповещений
- Node Exporter для системных метрик
- Пользовательские дашборды и алерты
- Автоматическое резервное копирование метрик
- Система оповещения через email и Slack
- Мониторинг производительности баз данных

## Переменные

### Переменные окружения
- `environment`: Название окружения (production/staging/development)
- `project_name`: Название проекта
- `project_version`: Версия проекта
- `app_version`: Версия приложения

### Переменные базы данных
- `database_host`: Имя хоста сервера базы данных
- `database_port`: Порт базы данных
- `database_name`: Название базы данных
- `database_user`: Пользователь базы данных
- `database_password`: Пароль базы данных

### Переменные приложения
- `auth_api_port`: Порт Auth API
- `ads_api_port`: Порт Ads API
- `analytics_api_port`: Порт Analytics API
- `admin_panel_port`: Порт Admin Panel
- `worker_go_port`: Порт Worker Go
- `worker_py_port`: Порт Worker Python
- `nginx_port`: Порт Nginx reverse proxy
- `debug`: Флаг режима отладки
- `ssl_enabled`: Включение SSL/TLS
- `ssl_cert_path`: Путь к SSL сертификату
- `ssl_key_path`: Путь к SSL ключу

### Переменные мониторинга
- `prometheus_port`: Порт Prometheus
- `grafana_port`: Порт Grafana
- `grafana_admin_user`: Администратор Grafana
- `grafana_admin_password`: Пароль администратора Grafana

## Безопасность

### Интеграция Vault
Используйте Ansible Vault для хранения конфиденциальных данных:
```bash
# Создание vault файла
ansible-vault create group_vars/vault.yml

# Редактирование vault файла
ansible-vault edit group_vars/vault.yml

# Запуск плейбука с vault
ansible-playbook -i inventory/production.yml playbook.yml --ask-vault-pass
```

### Управление SSH ключами
Настройка SSH ключей для безопасного доступа:
```yaml
# В файле инвентаризации
ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

## Мониторинг и логирование

### Мониторинг приложений
- Проверка работоспособности всех сервисов
- Сбор метрик производительности
- Мониторинг частоты ошибок
- Отслеживание времени отклика

### Мониторинг инфраструктуры
- Использование CPU и памяти
- Мониторинг свободного места на диске
- Анализ сетевого трафика
- Доступность сервисов

### Логирование
- Централизованный сбор логов
- Конфигурация ротации логов
- Поддержка структурированного логирования
- Политики хранения логов

## Устранение неполадок

### Распространенные проблемы

#### Конфликты Docker сетей
```bash
# Удаление конфликтующих сетей
docker network prune
```

#### Проблемы с правами доступа
```bash
# Обеспечение правильных прав
ansible production -m file -a "path=/opt/ad-platform mode=0755 owner=deploy"
```

#### Ошибки проверки работоспособности сервисов
```bash
# Проверка логов сервиса
ansible production -m shell -a "docker logs <container_name>"
```

#### Проблемы с подключением к базе данных
```bash
# Проверка доступности базы данных
ansible production -m shell -a "docker exec mysql-container mysql -u root -p -e 'SHOW DATABASES;'"
```

#### Ошибки Worker сервисов
```bash
# Проверка логов Worker Go
ansible production -m shell -a "docker logs worker-go-container"

# Проверка логов Worker Python
ansible production -m shell -a "docker logs worker-py-container"
```

#### Проблемы с Nginx reverse proxy
```bash
# Проверка конфигурации Nginx
ansible production -m shell -a "docker exec nginx-container nginx -t"

# Проверка доступности сервисов через Nginx
ansible production -m shell -a "curl -I http://localhost/api/health"
```

#### Проблемы с SSL сертификатами
```bash
# Проверка SSL сертификата
ansible production -m shell -a "openssl x509 -in /path/to/cert.pem -text -noout"

# Проверка цепочки сертификатов
ansible production -m shell -a "openssl verify /path/to/cert.pem"
```

#### Проблемы с мониторингом
```bash
# Проверка доступности Prometheus
ansible monitoring -m shell -a "curl -I http://localhost:9090"

# Проверка доступности Grafana
ansible monitoring -m shell -a "curl -I http://localhost:3000"

# Проверка доступности AlertManager
ansible monitoring -m shell -a "curl -I http://localhost:9093"
```

### Режим отладки
Включите режим отладки для подробного вывода:
```bash
ansible-playbook -i inventory/production.yml playbook.yml -vvv
```

### Диагностика проблем
```bash
# Проверка состояния всех контейнеров
ansible production -m shell -a "docker ps -a"

# Проверка использования ресурсов
ansible production -m shell -a "docker stats"

# Проверка системных логов
ansible production -m shell -a "journalctl -u docker.service -f"

# Проверка сетевых соединений
ansible production -m shell -a "netstat -tulpn | grep docker"
```

## Обслуживание

### Обновления
```bash
# Обновление приложения
ansible-playbook -i inventory/production.yml playbook.yml --extra-vars "app_version=1.1.0"

# Обновление базы данных
ansible-playbook -i inventory/production.yml playbook.yml --tags "database"
```

### Резервное копирование
```bash
# Запуск резервного копирования вручную
ansible production -m shell -a "/opt/ad-platform/scripts/backup.sh"

# Резервное копирование баз данных
ansible production -m shell -a "/opt/ad-platform/scripts/backup_database.sh"

# Резервное копирование конфигурации
ansible production -m shell -a "/opt/ad-platform/scripts/backup_config.sh"

# Резервное копирование метрик мониторинга
ansible monitoring -m shell -a "/opt/ad-platform/scripts/backup_metrics.sh"
```

### Мониторинг
```bash
# Проверка статуса мониторинга
ansible monitoring -m shell -a "docker ps | grep -E '(prometheus|grafana)'"
```

## Лучшие практики

1. **Контроль версий**: Храните все файлы Ansible в системе контроля версий
2. **Изоляция окружений**: Используйте отдельные инвентаризации для каждого окружения
3. **Управление секретами**: Используйте Ansible Vault для хранения конфиденциальных данных
4. **Тестирование**: Тестируйте плейбуки в development перед production
5. **Документация**: Поддерживайте документацию в актуальном состоянии
6. **Мониторинг**: Осуществляйте мониторинг как инфраструктуры, так и приложений
7. **Безопасность**: Регулярно обновляйте и патчите системы
8. **Резервное копирование**: Настройте регулярное резервное копирование всех компонентов
9. **Масштабирование**: Планируйте горизонтальное масштабирование сервисов
10. **Производительность**: Оптимизируйте конфигурацию сервисов для высокой нагрузки

## Поддержка

По вопросам и проблемам:
1. Проверьте раздел устранения неполадок
2. Просмотрите логи Ansible с флагом `-vvv`
3. Проверьте конфигурацию инвентаризации и переменных
4. Проверьте логи Docker контейнеров
5. Мониторьте ресурсы системы и сетевое соединение
