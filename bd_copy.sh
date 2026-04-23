#!/bin/bash

# Скрипт копирования БД с сервера на локальную машину
# Использование: ./bd_copy.sh

set -e  # Прерывать при ошибке

# Загрузка переменных из .env
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "❌ Файл .env не найден!"
    exit 1
fi

# Функция парсинга DATABASE_URL
parse_db_url() {
    local url=$1
    local prefix="postgresql://"
    local without_prefix=${url#$prefix}
    local user_pass=$(echo $without_prefix | cut -d'@' -f1)
    local host_port_db=$(echo $without_prefix | cut -d'@' -f2)
    
    local user=$(echo $user_pass | cut -d':' -f1)
    local password=$(echo $user_pass | cut -d':' -f2)
    local host=$(echo $host_port_db | cut -d':' -f1)
    local port_db=$(echo $host_port_db | cut -d':' -f2)
    local port=$(echo $port_db | cut -d'/' -f1)
    local database=$(echo $port_db | cut -d'/' -f2)
    
    echo "$user|$password|$host|$port|$database"
}

# Парсим серверную БД
SERVER_PARAMS=$(parse_db_url "$SERVER_DATABASE_URL")
SERVER_DB_USER=$(echo $SERVER_PARAMS | cut -d'|' -f1)
SERVER_DB_PASS=$(echo $SERVER_PARAMS | cut -d'|' -f2)
SERVER_DB_HOST=$(echo $SERVER_PARAMS | cut -d'|' -f3)
SERVER_DB_PORT=$(echo $SERVER_PARAMS | cut -d'|' -f4)
SERVER_DB_NAME=$(echo $SERVER_PARAMS | cut -d'|' -f5)

# Парсим локальную БД
LOCAL_PARAMS=$(parse_db_url "$LOCAL_DATABASE_URL")
LOCAL_DB_USER=$(echo $LOCAL_PARAMS | cut -d'|' -f1)
LOCAL_DB_PASS=$(echo $LOCAL_PARAMS | cut -d'|' -f2)
LOCAL_DB_HOST=$(echo $LOCAL_PARAMS | cut -d'|' -f3)
LOCAL_DB_PORT=$(echo $LOCAL_PARAMS | cut -d'|' -f4)
LOCAL_DB_NAME=$(echo $LOCAL_PARAMS | cut -d'|' -f5)

# Определяем суперпользователя PostgreSQL на локальной машине
if psql -U postgres -d postgres -c "SELECT 1" &>/dev/null; then
    PG_SUPERUSER="postgres"
elif psql -U $USER -d postgres -c "SELECT 1" &>/dev/null; then
    PG_SUPERUSER="$USER"
else
    PG_SUPERUSER=""
fi

if [ -z "$PG_SUPERUSER" ]; then
    echo "❌ Не удалось определить суперпользователя PostgreSQL"
    exit 1
fi

echo ""
echo "=== КОПИРОВАНИЕ БАЗЫ ДАННЫХ С СЕРВЕРА ==="
echo "Источник: $SERVER_DB_NAME на сервере $SERVER_HOST"
echo "Приемник: $LOCAL_DB_NAME локально"
echo "Пользователь БД: $LOCAL_DB_USER"
echo "Суперпользователь PG: $PG_SUPERUSER"
echo ""

# 1. Создаем пользователя если нет
echo "1. Проверка пользователя $LOCAL_DB_USER..."
if ! psql -U "$PG_SUPERUSER" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$LOCAL_DB_USER'" | grep -q 1; then
    psql -U "$PG_SUPERUSER" -d postgres -c "CREATE USER $LOCAL_DB_USER WITH PASSWORD '$LOCAL_DB_PASS';"
    echo "   ✅ Пользователь создан"
else
    echo "   ✅ Пользователь уже существует"
fi

# 2. Удаляем старую БД если есть
echo "2. Подготовка локальной БД..."
# Закрываем все соединения
psql -U "$PG_SUPERUSER" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$LOCAL_DB_NAME';" 2>/dev/null || true
# Удаляем БД
psql -U "$PG_SUPERUSER" -d postgres -c "DROP DATABASE IF EXISTS $LOCAL_DB_NAME;" 2>/dev/null || true
# Создаем новую БД
psql -U "$PG_SUPERUSER" -d postgres -c "CREATE DATABASE $LOCAL_DB_NAME OWNER $LOCAL_DB_USER;"
psql -U "$PG_SUPERUSER" -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE $LOCAL_DB_NAME TO $LOCAL_DB_USER;"
echo "   ✅ База данных создана"

# 3. Создаем дамп на сервере
echo "3. Создание дампа на сервере..."
ssh -p ${SERVER_SSH_PORT:-22} $SERVER_USER@$SERVER_HOST << EOF
    export PGPASSWORD='$SERVER_DB_PASS'
    pg_dump -h $SERVER_DB_HOST -p $SERVER_DB_PORT -U $SERVER_DB_USER \
            -Fc -f $TEMP_DUMP_ON_SERVER $SERVER_DB_NAME 2>/dev/null
    if [ \$? -eq 0 ]; then
        echo "   ✅ Дамп создан: \$(du -h $TEMP_DUMP_ON_SERVER | cut -f1)"
    else
        echo "   ❌ Ошибка создания дампа"
        exit 1
    fi
EOF

if [ $? -ne 0 ]; then
    echo "❌ Ошибка при создании дампа на сервере"
    exit 1
fi

# 4. Копируем дамп
echo "4. Копирование дампа..."
scp -P ${SERVER_SSH_PORT:-22} $SERVER_USER@$SERVER_HOST:$TEMP_DUMP_ON_SERVER /tmp/$SERVER_DB_NAME.dump 2>/dev/null
if [ $? -eq 0 ]; then
    echo "   ✅ Дамп скопирован"
else
    echo "   ❌ Ошибка копирования"
    exit 1
fi

# 5. Очищаем сервер
echo "5. Очистка сервера..."
ssh -p ${SERVER_SSH_PORT:-22} $SERVER_USER@$SERVER_HOST "rm -f $TEMP_DUMP_ON_SERVER" 2>/dev/null
echo "   ✅ Временные файлы удалены"

# 6. Восстанавливаем БД
echo "6. Восстановление БД из дампа..."
pg_restore -U "$PG_SUPERUSER" -d $LOCAL_DB_NAME --no-owner --clean /tmp/$SERVER_DB_NAME.dump 2>/dev/null
if [ $? -eq 0 ]; then
    echo "   ✅ База данных восстановлена"
else
    echo "   ⚠️  Восстановление с предупреждениями"
fi

# 7. Назначаем ВСЕ права пользователю kprf_db
echo "7. Настройка полных прав для пользователя $LOCAL_DB_USER..."

# Создаем SQL скрипт для назначения прав
cat > /tmp/grant_privileges.sql << EOF
-- Назначаем права на схемы
GRANT ALL ON SCHEMA public TO $LOCAL_DB_USER;
ALTER SCHEMA public OWNER TO $LOCAL_DB_USER;

-- Назначаем владельца и права на все таблицы
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE format('ALTER TABLE public.%I OWNER TO $LOCAL_DB_USER', r.tablename);
        EXECUTE format('GRANT ALL PRIVILEGES ON public.%I TO $LOCAL_DB_USER', r.tablename);
    END LOOP;
END \$\$;

-- Назначаем права на все последовательности
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT sequencename FROM pg_sequences WHERE schemaname = 'public') LOOP
        EXECUTE format('GRANT ALL PRIVILEGES ON public.%I TO $LOCAL_DB_USER', r.sequencename);
    END LOOP;
END \$\$;

-- Назначаем права на все функции
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace) LOOP
        EXECUTE format('GRANT ALL PRIVILEGES ON FUNCTION %I() TO $LOCAL_DB_USER', r.proname);
    END LOOP;
END \$\$;

-- Делаем пользователя владельцем БД
ALTER DATABASE $LOCAL_DB_NAME OWNER TO $LOCAL_DB_USER;

-- Настраиваем права по умолчанию для новых объектов
ALTER DEFAULT PRIVILEGES FOR USER $PG_SUPERUSER IN SCHEMA public 
    GRANT ALL ON TABLES TO $LOCAL_DB_USER;
    
ALTER DEFAULT PRIVILEGES FOR USER $PG_SUPERUSER IN SCHEMA public 
    GRANT ALL ON SEQUENCES TO $LOCAL_DB_USER;
    
ALTER DEFAULT PRIVILEGES FOR USER $PG_SUPERUSER IN SCHEMA public 
    GRANT ALL ON FUNCTIONS TO $LOCAL_DB_USER;
EOF

# Выполняем скрипт
psql -U "$PG_SUPERUSER" -d $LOCAL_DB_NAME -f /tmp/grant_privileges.sql 2>/dev/null

if [ $? -eq 0 ]; then
    echo "   ✅ Права успешно настроены"
else
    echo "   ⚠️  Некоторые права не настроены, но БД должна работать"
fi

# 8. Проверяем подключение и права
echo "8. Проверка подключения и прав..."

# Проверяем чтение таблицы topics
if PGPASSWORD="$LOCAL_DB_PASS" psql -h $LOCAL_DB_HOST -U $LOCAL_DB_USER -d $LOCAL_DB_NAME -c "SELECT COUNT(*) FROM topics;" 2>/dev/null | grep -q '[0-9]'; then
    TOPICS_COUNT=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h $LOCAL_DB_HOST -U $LOCAL_DB_USER -d $LOCAL_DB_NAME -tAc "SELECT COUNT(*) FROM topics;")
    echo "   ✅ Доступ к таблице topics: $TOPICS_COUNT записей"
else
    echo "   ❌ Нет доступа к таблице topics"
fi

# Проверяем чтение таблицы address_boundaries
if PGPASSWORD="$LOCAL_DB_PASS" psql -h $LOCAL_DB_HOST -U $LOCAL_DB_USER -d $LOCAL_DB_NAME -c "SELECT COUNT(*) FROM address_boundaries;" 2>/dev/null | grep -q '[0-9]'; then
    BOUNDARIES_COUNT=$(PGPASSWORD="$LOCAL_DB_PASS" psql -h $LOCAL_DB_HOST -U $LOCAL_DB_USER -d $LOCAL_DB_NAME -tAc "SELECT COUNT(*) FROM address_boundaries;")
    echo "   ✅ Доступ к таблице address_boundaries: $BOUNDARIES_COUNT записей"
else
    echo "   ❌ Нет доступа к таблице address_boundaries"
fi

# 9. Показываем статистику
echo "9. Статистика БД:"
TABLE_COUNT=$(psql -U "$PG_SUPERUSER" -d $LOCAL_DB_NAME -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null)
echo "   📊 Всего таблиц: $TABLE_COUNT"

# Показываем владельца таблиц
OWNER=$(psql -U "$PG_SUPERUSER" -d $LOCAL_DB_NAME -tAc "SELECT tableowner FROM pg_tables WHERE tablename='topics' LIMIT 1" 2>/dev/null)
echo "   👤 Владелец таблиц: $OWNER"

# 10. Очищаем временные файлы
rm -f /tmp/$SERVER_DB_NAME.dump
rm -f /tmp/grant_privileges.sql

echo ""
echo "✅ ГОТОВО! База данных скопирована и настроена"
echo ""
echo "=== ДЛЯ ЗАПУСКА ПРИЛОЖЕНИЯ ==="
echo "Убедитесь, что в .env файле (или экспортирована переменная):"
echo "   DATABASE_URL=$LOCAL_DATABASE_URL"
echo ""
echo "Или выполните:"
echo "   export DATABASE_URL=\"$LOCAL_DATABASE_URL\""
echo ""
echo "Затем перезапустите приложение"