#!/usr/bin/env bash
set -euo pipefail

# === ЦВЕТА ДЛЯ ВЫВОДА ===
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }

# === 1. ЗАГРУЗКА .env ===
if [ ! -f ".env" ]; then
    log_error "Файл .env не найден в корне проекта!"
    exit 1
fi
set -a
source .env
set +a
log_success "Переменные загружены из .env"

# === 2. ПАРАМЕТРЫ ИЗ .env С ДЕФОЛТАМИ ===
: "${SERVER_HOST:?SERVER_HOST не задан в .env}"
: "${SERVER_USER:=root}"
: "${SERVER_SSH_PORT:=22}"
: "${SERVER_PROJECT_PATH:=/opt/kprf-surgut.ru}"
: "${SERVICE_NAME:=kprf-app}"
: "${DUMP_FILENAME:=kprf_surgut.dump}"
: "${TEMP_DUMP_ON_SERVER:=/tmp/${DUMP_FILENAME}}"

SSH_CMD="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -p ${SERVER_SSH_PORT} ${SERVER_USER}@${SERVER_HOST}"
SCP_CMD="scp -o StrictHostKeyChecking=accept-new -P ${SERVER_SSH_PORT}"

# === 3. ПРОВЕРКА СОЕДИНЕНИЯ ===
log_info "Проверка соединения с ${SERVER_USER}@${SERVER_HOST}..."
if ! $SSH_CMD "echo '✅ SSH OK'" > /dev/null 2>&1; then
    log_error "Не удалось подключиться по SSH. Проверь IP, порт, ключи."
    exit 1
fi
log_success "SSH соединение установлено"

# === 4. GITHUB: КОММИТ И ПУШ ===
log_info "📦 Отправка кода в GitHub..."

# Определяем ветку
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Коммит (если есть изменения)
if ! git diff --quiet || ! git diff --cached --quiet; then
    git add .
    git commit -m "🚀 Deploy: $(date '+%Y-%m-%d %H:%M:%S')" || log_warn "Нет изменений для коммита"
fi

# Пуш
if ! git push origin "${CURRENT_BRANCH}" 2>/dev/null; then
    log_error "Ошибка пуша в GitHub. Проверь токен/ключи."
    exit 1
fi
log_success "Код отправлен в ветку ${CURRENT_BRANCH}"

# === 5. СОЗДАНИЕ ДАМПА БД (ЛОКАЛЬНО) ===
log_info "🗄 Создание дампа базы данных..."

# Извлекаем креды для локальной БД из DATABASE_URL
# Формат: postgresql://user:pass@host:port/dbname
if [[ "$DATABASE_URL" =~ postgresql://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+) ]]; then
    LOCAL_DB_USER="${BASH_REMATCH[1]}"
    LOCAL_DB_PASS="${BASH_REMATCH[2]}"
    LOCAL_DB_HOST="${BASH_REMATCH[3]}"
    LOCAL_DB_PORT="${BASH_REMATCH[4]}"
    LOCAL_DB_NAME="${BASH_REMATCH[5]}"
else
    log_error "Не удалось распарсить DATABASE_URL. Проверь формат."
    exit 1
fi

# Создаём дамп (с паролем через PGPASSWORD)
export PGPASSWORD="$LOCAL_DB_PASS"
if ! pg_dump -U "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -p "$LOCAL_DB_PORT" -F c -f "$DUMP_FILENAME" "$LOCAL_DB_NAME" 2>/dev/null; then
    log_error "Ошибка создания дампа БД"
    unset PGPASSWORD
    exit 1
fi
unset PGPASSWORD
log_success "Дамп создан: $DUMP_FILENAME"

# === 6. ПЕРЕДАЧА ФАЙЛОВ НА СЕРВЕР ===
log_info "📤 Передача файлов на сервер..."

# Передаём дамп и .env
$SCP_CMD "$DUMP_FILENAME" "${SERVER_USER}@${SERVER_HOST}:${TEMP_DUMP_ON_SERVER}" || {
    log_error "Не удалось передать дамп БД"
    exit 1
}
$SCP_CMD ".env" "${SERVER_USER}@${SERVER_HOST}:${SERVER_PROJECT_PATH}/.env.tmp" || {
    log_error "Не удалось передать .env"
    exit 1
}
log_success "Файлы переданы"

# === 7. ВЫПОЛНЕНИЕ НА СЕРВЕРЕ ===
log_info "🔧 Выполнение команд на сервере..."

$SSH_CMD << 'SERVER_SCRIPT'
set -euo pipefail

# Переменные (передаются из окружения скрипта)
PROJECT_PATH="${SERVER_PROJECT_PATH}"
SERVICE_NAME="${SERVICE_NAME}"
TEMP_DUMP="${TEMP_DUMP_ON_SERVER}"
DB_URL="${SERVER_DATABASE_URL}"

log() { echo -e "[SERVER] $1"; }

# 7.1 Остановка сервиса приложения (НЕ nginx/postgres!)
log "⏹ Остановка сервиса ${SERVICE_NAME}..."
sudo systemctl stop "${SERVICE_NAME}" || log "⚠️ Сервис ${SERVICE_NAME} не найден, пропускаем"

# 7.2 Бэкап старого кода
BACKUP_DIR="${PROJECT_PATH}/_backup_$(date +%Y%m%d_%H%M%S)"
if [ -d "${PROJECT_PATH}" ] && [ -n "$(ls -A ${PROJECT_PATH} 2>/dev/null | grep -v '_backup_')" ]; then
    log "📦 Архивация старого кода в ${BACKUP_DIR}..."
    mkdir -p "$(dirname "$BACKUP_DIR")"
    # Копируем всё, кроме папок бэкапов
    rsync -a --exclude='_backup_*' "${PROJECT_PATH}/" "${BACKUP_DIR}/" || {
        # Если rsync нет, используем cp
        cp -r "${PROJECT_PATH}" "${BACKUP_DIR}" || true
    }
    log "✅ Бэкап создан: ${BACKUP_DIR}"
fi

# 7.3 Очистка и клонирование кода (сохраняем .env.tmp)
log "🧹 Очистка директории проекта..."
mkdir -p "${PROJECT_PATH}"
find "${PROJECT_PATH}" -mindepth 1 -maxdepth 1 ! -name '.env.tmp' -exec rm -rf {} \; 2>/dev/null || true

log "📥 Клонирование репозитория..."
cd "${PROJECT_PATH}"
git clone --branch "${CURRENT_BRANCH}" "https://github.com/${GH_USER:-YOUR_GH_USER}/kprf.git" . 2>/dev/null || {
    # Если клон не удался, пробуем pull (если уже есть .git)
    [ -d ".git" ] && git pull origin "${CURRENT_BRANCH}" || {
        echo "❌ Ошибка клонирования. Проверь доступ к репозиторию."
        exit 1
    }
}

# 7.4 Перемещение .env на место
if [ -f ".env.tmp" ]; then
    mv ".env.tmp" ".env"
    chmod 600 ".env"
    log "✅ .env установлен"
fi

# 7.5 Виртуальное окружение и зависимости
if [ ! -d "venv" ]; then
    log "🐍 Создание виртуального окружения..."
    python3 -m venv venv
fi
log "📦 Установка зависимостей..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# 7.6 Восстановление БД
log "🗄 Восстановление базы данных..."
# Парсим SERVER_DATABASE_URL
if [[ "$DB_URL" =~ postgresql://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+) ]]; then
    SRV_DB_USER="${BASH_REMATCH[1]}"
    SRV_DB_PASS="${BASH_REMATCH[2]}"
    SRV_DB_HOST="${BASH_REMATCH[3]}"
    SRV_DB_PORT="${BASH_REMATCH[4]}"
    SRV_DB_NAME="${BASH_REMATCH[5]}"
else
    log "⚠️ Не удалось распарсить SERVER_DATABASE_URL, пропускаем восстановление БД"
    SRV_DB_NAME=""
fi

if [ -n "$SRV_DB_NAME" ] && [ -f "$TEMP_DUMP" ]; then
    export PGPASSWORD="$SRV_DB_PASS"
    # --clean удаляет объекты перед восстановлением, --if-exists защищает от ошибок
    pg_restore -U "$SRV_DB_USER" -h "$SRV_DB_HOST" -p "$SRV_DB_PORT" -d "$SRV_DB_NAME" \
        --clean --if-exists --no-owner --no-privileges "$TEMP_DUMP" 2>/dev/null || {
        log "⚠️ pg_restore вернул предупреждения (это нормально при первом развёртывании)"
    }
    unset PGPASSWORD
    rm -f "$TEMP_DUMP"
    log "✅ База данных восстановлена"
fi

# 7.7 Миграции Alembic
log "🔄 Применение миграций..."
flask db upgrade || log "⚠️ Миграции уже применены или требуют внимания"

# 7.8 Запуск сервиса
log "🚀 Запуск сервиса ${SERVICE_NAME}..."
sudo systemctl start "${SERVICE_NAME}"
sleep 3

# Проверка статуса
if sudo systemctl is-active --quiet "${SERVICE_NAME}"; then
    log "✅ Сервис ${SERVICE_NAME} запущен"
    sudo systemctl status "${SERVICE_NAME}" --no-pager -l
else
    log "❌ Сервис не запустился. Логи:"
    sudo journalctl -u "${SERVICE_NAME}" -n 20 --no-pager
    exit 1
fi

log "✅ Все шаги на сервере выполнены"
SERVER_SCRIPT

# === 8. ОЧИСТКА ЛОКАЛЬНО ===
rm -f "$DUMP_FILENAME"
log_success "Локальный дамп удалён"

# === 9. ФИНАЛ ===
echo ""
echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🎉 ДЕПЛОЙ ЗАВЕРШЁН УСПЕШНО!  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
echo ""
echo "🌐 Сайт: https://${DOMAIN:-your-domain.com}"
echo "🔐 Админка: /admin"
echo "📁 Бэкап кода на сервере: ${BACKUP_DIR:-N/A}"
echo ""
log_info "Если что-то пошло не так, восстанови код из бэкапа:"
echo "  ssh ${SERVER_USER}@${SERVER_HOST}"
echo "  sudo systemctl stop ${SERVICE_NAME}"
echo "  rm -rf ${SERVER_PROJECT_PATH}"
echo "  mv ${BACKUP_DIR} ${SERVER_PROJECT_PATH}"
echo "  sudo systemctl start ${SERVICE_NAME}"