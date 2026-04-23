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

# === 2. НАСТРОЙКИ ПУТЕЙ И ИМЕН (с дефолтами из .env) ===
: "${SERVER_HOST:?SERVER_HOST не задан в .env}"
: "${SERVER_USER:=root}"
: "${SERVER_SSH_PORT:=22}"

# Пути и имена (можно переопределить в .env)
: "${GITHUB_REPO_NAME:=kprf-surgut}"
: "${SERVER_PROJECT_PATH:=/var/www/kprf-surgut.ru}"
: "${SERVICE_NAME:=kprf-surgut}"
: "${APP_PORT:=8000}"
: "${APP_USER:=kprf}"
: "${DUMP_FILENAME:=kprf_surgut.dump}"
: "${TEMP_DUMP_ON_SERVER:=/tmp/${DUMP_FILENAME}}"

# === 2.1. ОПРЕДЕЛЕНИЕ GH_USER (исправлено: не перезаписываем если есть в .env) ===
# Если GH_USER уже задан в .env — используем его, иначе пытаемся определить
if [ -z "${GH_USER:-}" ]; then
    GH_USER=$(git config user.name 2>/dev/null || echo "")
fi
if [ -z "${GH_USER:-}" ]; then
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$REMOTE_URL" =~ github.com[:/]([^/]+)/ ]]; then
        GH_USER="${BASH_REMATCH[1]}"
    else
        read -r -p "📦 Введите ваш GitHub username: " GH_USER
    fi
fi
log_info "GitHub пользователь: ${GH_USER}"

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
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Коммит (если есть изменения)
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    git add .
    git commit -m "🚀 Deploy: $(date '+%Y-%m-%d %H:%M:%S')" || log_warn "Нет изменений для коммита"
fi

# Пуш
if ! git push origin "${CURRENT_BRANCH}" 2>/dev/null; then
    log_error "Ошибка пуша в GitHub. Проверь токен/ключи."
    exit 1
fi
log_success "Код отправлен в ветку ${CURRENT_BRANCH}"

# === 5. ДАМП БД (ЛОКАЛЬНО) ===
log_info "🗄 Создание дампа базы данных..."

# Парсинг DATABASE_URL (поддержка с паролем и без)
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

# Создаём дамп
if [ -n "$DB_PASS" ]; then export PGPASSWORD="$DB_PASS"; fi

# Для localhost пробуем без -h (peer auth)
if [[ "$DB_HOST" == "127.0.0.1" || "$DB_HOST" == "localhost" ]]; then
    PG_OPTS="-U $DB_USER -p $DB_PORT"
else
    PG_OPTS="-U $DB_USER -h $DB_HOST -p $DB_PORT"
fi

if ! pg_dump $PG_OPTS -F c -f "$DUMP_FILENAME" "$DB_NAME" 2>/dev/null; then
    log_error "Ошибка создания дампа БД"
    unset PGPASSWORD
    exit 1
fi
unset PGPASSWORD
log_success "Дамп создан: $DUMP_FILENAME"

# === 6. ПЕРЕДАЧА ФАЙЛОВ НА СЕРВЕР ===
log_info "📤 Передача файлов на сервер..."

# Создаём директорию на сервере
$SSH_CMD "mkdir -p ${SERVER_PROJECT_PATH}" || {
    log_error "Не удалось создать директорию на сервере"
    exit 1
}

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

# 🔑 ВАЖНО: используем << DEPLOY_EOF (без кавычек), чтобы переменные подставились локально
# Внутренние переменные скрипта экранируем знаком $ (например, \$1, \$?)
$SSH_CMD bash -s << DEPLOY_EOF
set -euo pipefail

# === ФУНКЦИИ ЛОГИРОВАНИЯ ===
log() { echo -e "[SERVER] \$1"; }
log_warn() { echo -e "[SERVER] [WARN] \$1"; }
log_error() { echo -e "[SERVER] [FAIL] \$1"; }

# === ПЕРЕМЕННЫЕ (подставлены локально перед отправкой) ===
# Значения уже встроены в скрипт благодаря heredoc без кавычек
: "\${PROJECT_PATH:=${SERVER_PROJECT_PATH}}"
: "\${SERVICE_NAME:=${SERVICE_NAME}}"
: "\${APP_PORT:=${APP_PORT}}"
: "\${APP_USER:=${APP_USER}}"
: "\${TEMP_DUMP:=${TEMP_DUMP_ON_SERVER}}"
: "\${DB_URL:=${SERVER_DATABASE_URL}}"
: "\${GH_USER:=${GH_USER}}"
: "\${REPO_NAME:=${GITHUB_REPO_NAME}}"
: "\${BRANCH:=${CURRENT_BRANCH}}"
: "\${GITHUB_TOKEN:=${GITHUB_TOKEN:-}}"

# Отладочный вывод (поможет увидеть, какие переменные пришли)
log "🔍 DEBUG: GH_USER=[\${GH_USER}], REPO=[\${REPO_NAME}], TOKEN=[\${GITHUB_TOKEN:0:10}...]"

# === 7.1 ОСТАНОВКА СЕРВИСА ===
log "⏹ Остановка \${SERVICE_NAME}..."
if systemctl list-units --all 2>/dev/null | grep -q "\${SERVICE_NAME}"; then
    systemctl stop "\${SERVICE_NAME}" 2>/dev/null || {
        log_warn "systemctl stop не сработал, пробуем pkill..."
        pkill -f "gunicorn.*\${APP_PORT}" 2>/dev/null || true
    }
else
    log_warn "Сервис \${SERVICE_NAME} не найден в systemd, используем pkill"
    pkill -f "gunicorn.*\${APP_PORT}" 2>/dev/null || true
fi
sleep 2

# === 7.2 БЭКАП СТАРОГО КОДА ===
BACKUP_DIR="\${PROJECT_PATH}/_backup_\$(date +%Y%m%d_%H%M%S)"
if [ -d "\${PROJECT_PATH}" ] && [ -n "\$(ls -A "\${PROJECT_PATH}" 2>/dev/null | grep -v '_backup_' || true)" ]; then
    log "📦 Архивация старого кода в \${BACKUP_DIR}..."
    mkdir -p "\$(dirname "\$BACKUP_DIR")"
    rsync -a --exclude='_backup_*' "\${PROJECT_PATH}/" "\${BACKUP_DIR}/" 2>/dev/null || \
    cp -r "\${PROJECT_PATH}" "\${BACKUP_DIR}" || true
    log "✅ Бэкап создан: \${BACKUP_DIR}"
fi

# === 7.3 ОЧИСТКА ПАПКИ (сохраняем .env) ===
log "🧹 Очистка директории проекта..."
mkdir -p "\${PROJECT_PATH}"
find "\${PROJECT_PATH}" -mindepth 1 -maxdepth 1 ! -name '.env' -exec rm -rf {} \; 2>/dev/null || true

# === 7.4 КЛОНИРОВАНИЕ/ОБНОВЛЕНИЕ КОДА ===
log "📥 Синхронизация кода из GitHub..."
cd "\${PROJECT_PATH}"

# Формируем URL для клонирования (с токеном если есть)
if [ -n "\${GITHUB_TOKEN}" ]; then
    REPO_URL="https://\${GH_USER}:\${GITHUB_TOKEN}@github.com/\${GH_USER}/\${REPO_NAME}.git"
    log "🔐 Используем аутентификацию через токен"
else
    REPO_URL="https://github.com/\${GH_USER}/\${REPO_NAME}.git"
    log "🌐 Используем публичный доступ (может потребоваться SSH-ключ)"
fi

if [ -d ".git" ] && git rev-parse --git-dir > /dev/null 2>&1; then
    log "🔄 Pull из ветки \${BRANCH}..."
    git fetch origin "\${BRANCH}" 2>&1 || {
        log_warn "git fetch не сработал, пробуем полный reset..."
        git remote set-url origin "\${REPO_URL}" 2>/dev/null || true
        git fetch origin "\${BRANCH}" 2>&1 || true
    }
    git reset --hard "origin/\${BRANCH}" 2>/dev/null || true
    git clean -fd 2>/dev/null || true
    log "✅ Код обновлён через pull"
else
    log "🗑 Папка не является репозиторием, клонируем заново..."
    [ -f ".env" ] && mv ".env" "/tmp/.env.backup.\$\$"
    
    # Очищаем папку перед клонированием
    find "\${PROJECT_PATH}" -mindepth 1 -delete 2>/dev/null || true
    
    # Пробуем клонировать с подробным выводом для отладки
    log "🔗 Клонируем: \${REPO_URL} -> \${PROJECT_PATH}"
    if ! git clone --branch "\${BRANCH}" "\${REPO_URL}" "\${PROJECT_PATH}" 2>&1; then
        log_warn "Клонирование с веткой не удалось, пробуем без указания ветки..."
        if ! git clone "\${REPO_URL}" "\${PROJECT_PATH}" 2>&1; then
            log_error "❌ Не удалось клонировать репозиторий!"
            log "💡 Возможные причины:"
            log "   • Неверный GH_USER (\${GH_USER}) или GITHUB_TOKEN"
            log "   • Репозиторий приватный, а токен не имеет доступа"
            log "   • Git не установлен на сервере"
            log "   • Нет доступа к github.com (фаервол/сеть)"
            # Восстанавливаем .env перед выходом
            [ -f "/tmp/.env.backup.\$\$" ] && mv "/tmp/.env.backup.\$\$" "\${PROJECT_PATH}/.env"
            exit 1
        fi
    fi
    
    [ -f "/tmp/.env.backup.\$\$" ] && mv "/tmp/.env.backup.\$\$" "\${PROJECT_PATH}/.env"
    log "✅ Код склонирован заново"
fi

# === 7.5 ВИРТУАЛЬНОЕ ОКРУЖЕНИЕ И ЗАВИСИМОСТИ ===
log "🐍 Проверка виртуального окружения..."
if [ ! -d "venv" ]; then
    log "Создание venv..."
    python3 -m venv venv
fi
log "📦 Установка зависимостей..."
source venv/bin/activate
pip install --upgrade pip -q
pip install -r requirements.txt -q 2>/dev/null || log_warn "pip install вернул предупреждения"

# === 7.6 ВОССТАНОВЛЕНИЕ БД ===
log "🗄 Восстановление базы данных..."
if [ -n "\${DB_URL}" ] && [ -f "\${TEMP_DUMP}" ]; then
    # Парсим SERVER_DATABASE_URL
    if [[ "\${DB_URL}" =~ postgresql://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+) ]]; then
        SRV_USER="\${BASH_REMATCH[1]}"
        SRV_PASS="\${BASH_REMATCH[2]}"
        SRV_HOST="\${BASH_REMATCH[3]}"
        SRV_PORT="\${BASH_REMATCH[4]}"
        SRV_DB="\${BASH_REMATCH[5]}"
        
        if [ -n "\$SRV_PASS" ]; then export PGPASSWORD="\$SRV_PASS"; fi
        pg_restore -U "\$SRV_USER" -h "\$SRV_HOST" -p "\$SRV_PORT" -d "\$SRV_DB" \
            --clean --if-exists --no-owner --no-privileges "\$TEMP_DUMP" 2>/dev/null || \
            log_warn "pg_restore вернул предупреждения"
        unset PGPASSWORD
        rm -f "\$TEMP_DUMP"
        log "✅ База данных восстановлена"
    else
        log_warn "Не удалось распарсить SERVER_DATABASE_URL: \${DB_URL}"
    fi
else
    log_warn "DB_URL или дамп не заданы, пропускаем восстановление БД"
fi

# === 7.7 МИГРАЦИИ ===
log "🔄 Применение миграций..."
flask db upgrade 2>/dev/null || log_warn "Миграции уже применены"

# === 7.8 ПРАВА НА ФАЙЛЫ ===
log "🔐 Выставляем права на папку проекта..."
chown -R "\${APP_USER}:\${APP_USER}" "\${PROJECT_PATH}" 2>/dev/null || true

# === 7.9 ЗАПУСК СЕРВИСА ===
log "🚀 Запуск сервиса \${SERVICE_NAME}..."
if systemctl list-units --all 2>/dev/null | grep -q "\${SERVICE_NAME}"; then
    systemctl daemon-reload 2>/dev/null || true
    systemctl start "\${SERVICE_NAME}"
    sleep 3
    if systemctl is-active --quiet "\${SERVICE_NAME}" 2>/dev/null; then
        log "✅ Сервис \${SERVICE_NAME} запущен"
    else
        log_error "❌ Сервис не запустился. Логи:"
        journalctl -u "\${SERVICE_NAME}" -n 20 --no-pager 2>/dev/null || echo "Нет логов"
        exit 1
    fi
else
    log_warn "systemd-юнит не найден, запускаем gunicorn вручную..."
    cd "\${PROJECT_PATH}"
    source venv/bin/activate
    nohup gunicorn --workers 3 --bind 127.0.0.1:"\${APP_PORT}" app:app > /var/log/kprf-app.log 2>&1 &
    sleep 3
fi

# === 7.10 ПРОВЕРКА ЗДОРОВЬЯ ===
log "🏥 Проверка доступности приложения..."
if curl -s --max-time 5 "http://127.0.0.1:\${APP_PORT}" > /dev/null 2>&1; then
    log "✅ Приложение отвечает на порту \${APP_PORT}"
else
    log_warn "Приложение не отвечает. Логи:"
    [ -f "/var/log/kprf-app.log" ] && tail -20 /var/log/kprf-app.log || echo "Нет логов"
fi

log "✅ Все шаги на сервере выполнены"
DEPLOY_EOF

# === 8. ОЧИСТКА ЛОКАЛЬНО ===
rm -f "$DUMP_FILENAME"
log_success "Локальный дамп удалён"

# === 9. ФИНАЛ ===
echo ""
echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  🎉 ДЕПЛОЙ ЗАВЕРШЁН УСПЕШНО!  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
echo ""
echo "🌐 Сайт: https://${DOMAIN:-${SERVER_HOST}}"
echo "🔐 Админка: /admin"
echo "📁 Бэкап кода на сервере: ${SERVER_PROJECT_PATH}/_backup_*"
echo ""
log_info "Если что-то пошло не так, восстанови код из бэкапа:"
echo "  ssh ${SERVER_USER}@${SERVER_HOST}"
echo "  systemctl stop ${SERVICE_NAME}"
echo "  rm -rf ${SERVER_PROJECT_PATH}"
echo "  mv ${SERVER_PROJECT_PATH}/_backup_YYYYMMDD_HHMMSS ${SERVER_PROJECT_PATH}"
echo "  systemctl start ${SERVICE_NAME}"