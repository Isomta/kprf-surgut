#!/usr/bin/env bash
set -euo pipefail

# === ЦВЕТА ===
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

# === 2. НАСТРОЙКИ ПУТЕЙ И ИМЕН ===
: "${SERVER_HOST:?SERVER_HOST не задан в .env}"
: "${SERVER_USER:=root}"
: "${SERVER_SSH_PORT:=22}"

# Имя репозитория на GitHub
GITHUB_REPO_NAME="kprf-surgut"
# Путь к папке на сервере (должна совпадать с названием папки в systemd/nginx)
SERVER_PROJECT_PATH="/opt/kprf-surgut.ru"

SERVICE_NAME="kprf-app"
DUMP_FILENAME="kprf_surgut.dump"
TEMP_DUMP_ON_SERVER="/tmp/${DUMP_FILENAME}"

# Определяем текущего пользователя GitHub
GH_USER=$(git config user.name)
if [ -z "$GH_USER" ]; then
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$REMOTE_URL" =~ github.com[:/]([^/]+)/ ]]; then
        GH_USER="${BASH_REMATCH[1]}"
    else
        read -r -p "📦 Введите ваш GitHub username: " GH_USER
    fi
fi

SSH_CMD="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -p ${SERVER_SSH_PORT} ${SERVER_USER}@${SERVER_HOST}"
SCP_CMD="scp -o StrictHostKeyChecking=accept-new -P ${SERVER_SSH_PORT}"

# === 3. ПРОВЕРКА СОЕДИНЕНИЯ ===
log_info "Проверка соединения с ${SERVER_USER}@${SERVER_HOST}..."
if ! $SSH_CMD "echo '✅ SSH OK'" > /dev/null 2>&1; then
    log_error "Не удалось подключиться по SSH."
    exit 1
fi

# === 4. GITHUB ===
log_info "📦 Отправка кода в GitHub..."
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

if ! git diff --quiet || ! git diff --cached --quiet; then
    git add .
    git commit -m "🚀 Deploy: $(date '+%Y-%m-%d %H:%M:%S')" || log_warn "Нет изменений"
fi

if ! git push origin "${CURRENT_BRANCH}" 2>/dev/null; then
    log_error "Ошибка пуша."
    exit 1
fi
log_success "Код отправлен в ${CURRENT_BRANCH}"

# === 5. ДАМП БД ===
log_info "🗄 Создание дампа базы данных..."
# Парсим DATABASE_URL (поддержка user:pass@host и user@host)
parse_db_url() {
    local url="$1"
    url="${url#postgresql://}"
    if [[ "$url" =~ ^([^@]+)@(.+)$ ]]; then
        local auth="${BASH_REMATCH[1]}"
        local rest="${BASH_REMATCH[2]}"
        if [[ "$auth" =~ ^([^:]+):(.+)$ ]]; then
            DB_USER="${BASH_REMATCH[1]}"; DB_PASS="${BASH_REMATCH[2]}"
        else
            DB_USER="$auth"; DB_PASS=""
        fi
        if [[ "$rest" =~ ^([^:]+):([0-9]+)/(.+)$ ]]; then
            DB_HOST="${BASH_REMATCH[1]}"; DB_PORT="${BASH_REMATCH[2]}"; DB_NAME="${BASH_REMATCH[3]}"
        fi
    fi
}
parse_db_url "$DATABASE_URL"

if [ -n "$DB_PASS" ]; then export PGPASSWORD="$DB_PASS"; fi
PG_OPTS="-U $DB_USER -h $DB_HOST -p $DB_PORT"
# Если локалхост, пробуем без -h (peer auth)
if [[ "$DB_HOST" == "127.0.0.1" || "$DB_HOST" == "localhost" ]]; then
    PG_OPTS="-U $DB_USER -p $DB_PORT"
fi

if ! pg_dump $PG_OPTS -F c -f "$DUMP_FILENAME" "$DB_NAME" 2>/dev/null; then
    log_error "Ошибка дампа."
    unset PGPASSWORD; exit 1
fi
unset PGPASSWORD
log_success "Дамп создан."

# === 6. ПЕРЕДАЧА ФАЙЛОВ ===
log_info "📤 Передача файлов на сервер..."

# 1. Создаем папку проекта, если её нет (ФИКС ОШИБКИ SCP)
$SSH_CMD "mkdir -p ${SERVER_PROJECT_PATH}"

# 2. Кидаем файлы
$SCP_CMD "$DUMP_FILENAME" "${SERVER_USER}@${SERVER_HOST}:${TEMP_DUMP_ON_SERVER}" || exit 1
$SCP_CMD ".env" "${SERVER_USER}@${SERVER_HOST}:${SERVER_PROJECT_PATH}/.env.tmp" || exit 1
log_success "Файлы переданы."

# === 7. СЕРВЕРНАЯ ЧАСТЬ ===
log_info "🔧 Выполнение на сервере..."

# Используем "DEPLOY_EOF" без кавычек, чтобы переменные ($SERVER_PROJECT_PATH) раскрылись
$SSH_CMD << DEPLOY_EOF
set -euo pipefail

PROJECT_PATH="${SERVER_PROJECT_PATH}"
SERVICE_NAME="${SERVICE_NAME}"
TEMP_DUMP="${TEMP_DUMP_ON_SERVER}"
DB_URL="${SERVER_DATABASE_URL}"
GH_USER="${GH_USER}"
REPO_NAME="${GITHUB_REPO_NAME}"
BRANCH="${CURRENT_BRANCH}"

log() { echo -e "[SERVER] \$1"; }

# 1. Остановка сервиса
log "⏹ Остановка \${SERVICE_NAME}..."
systemctl stop "\${SERVICE_NAME}" 2>/dev/null || true

# 2. Бэкап
BACKUP_DIR="\${PROJECT_PATH}/_backup_\$(date +%Y%m%d_%H%M%S)"
if [ -d "\${PROJECT_PATH}" ]; then
    log "📦 Бэкап в \${BACKUP_DIR}..."
    mkdir -p "\$(dirname "\$BACKUP_DIR")"
    # Копируем всё, кроме папок _backup
    rsync -a --exclude='_backup_*' "\${PROJECT_PATH}/" "\${BACKUP_DIR}/" 2>/dev/null || cp -r "\${PROJECT_PATH}" "\${BACKUP_DIR}"
fi

# 3. Очистка (оставляем .env.tmp)
log "🧹 Очистка..."
find "\${PROJECT_PATH}" -mindepth 1 -maxdepth 1 ! -name '.env.tmp' -exec rm -rf {} \; 2>/dev/null || true

# 4. Клонирование (ВНИМАНИЕ: репо kprf-surgut, папка kprf-surgut.ru)
log "📥 Клонирование \${REPO_NAME} -> \${PROJECT_PATH}..."
cd "\${PROJECT_PATH}"
# Клонируем репо в текущую папку (.)
git clone --branch "\${BRANCH}" https://github.com/\${GH_USER}/\${REPO_NAME}.git . 2>/dev/null || {
    # Если уже гит, делаем pull
    git pull origin "\${BRANCH}" || true
}

# 5. .env
if [ -f ".env.tmp" ]; then
    mv ".env.tmp" ".env"
    chmod 600 ".env"
    log "✅ .env установлен"
fi

# 6. Venv
if [ ! -d "venv" ]; then python3 -m venv venv; fi
source venv/bin/activate
pip install --upgrade pip -q
pip install -r requirements.txt -q

# 7. БД
log "🗄 Восстановление БД..."
parse_srv_db() {
    local url="\$1"
    url="\${url#postgresql://}"
    if [[ "\$url" =~ ^([^@]+)@(.+)\$ ]]; then
        local auth="\${BASH_REMATCH[1]}"; local rest="\${BASH_REMATCH[2]}"
        if [[ "\$auth" =~ ^([^:]+):(.+)\$ ]]; then SRV_USER="\${BASH_REMATCH[1]}"; SRV_PASS="\${BASH_REMATCH[2]}"
        else SRV_USER="\$auth"; SRV_PASS=""; fi
        if [[ "\$rest" =~ ^([^:]+):([0-9]+)/(.+)\$ ]]; then SRV_HOST="\${BASH_REMATCH[1]}"; SRV_PORT="\${BASH_REMATCH[2]}"; SRV_DB="\${BASH_REMATCH[3]}"; fi
    fi
}
parse_srv_db "\$DB_URL"

if [ -n "\$SRV_DB" ] && [ -f "\$TEMP_DUMP" ]; then
    if [ -n "\$SRV_PASS" ]; then export PGPASSWORD="\$SRV_PASS"; fi
    pg_restore -U "\$SRV_USER" -h "\$SRV_HOST" -p "\$SRV_PORT" -d "\$SRV_DB" --clean --if-exists --no-owner --no-privileges "\$TEMP_DUMP" 2>/dev/null || true
    unset PGPASSWORD
    rm -f "\$TEMP_DUMP"
    log "✅ БД восстановлена"
fi

# 8. Миграции
flask db upgrade || true

# 9. Запуск
log "🚀 Запуск \${SERVICE_NAME}..."
systemctl start "\${SERVICE_NAME}"
sleep 2
if systemctl is-active --quiet "\${SERVICE_NAME}"; then
    log "✅ Сервис запущен"
else
    log "❌ Ошибка запуска! Логи:"
    journalctl -u "\${SERVICE_NAME}" -n 20 --no-pager
    exit 1
fi
DEPLOY_EOF

# === 8. ФИНАЛ ===
rm -f "$DUMP_FILENAME"
log_success "Локальный дамп удалён."
echo -e "\n${GREEN}🎉 ДЕПЛОЙ ЗАВЕРШЁН!${NC}"
echo "🌐 https://${DOMAIN:-server-ip}"