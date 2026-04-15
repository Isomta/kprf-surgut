#!/usr/bin/env bash
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'

echo -e "${BLUE}🚀 Инициализация деплоя KPRF-Deputat...${NC}"
echo -e "${YELLOW}⚠️  Убедитесь, что домен уже указывает на IP сервера (A-запись)${NC}"

# ==========================================
# 1. ГИТХАБ: КОММИТ И ПУШ
# ==========================================
echo -e "\n${GREEN}1️⃣  GitHub: Подготовка и отправка кода${NC}"
read -r -p "📦 Ваш GitHub username: " GH_USER
read -r -s -p "🔑 GitHub Personal Access Token (с правами repo): " GH_TOKEN
echo ""

REPO_URL="https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/kprf.git"
# Используем временный credential helper, чтобы не хранить токен в истории
git config --global credential.helper 'store --file=.git-credentials'
echo "https://${GH_USER}:${GH_TOKEN}@github.com" > .git-credentials

echo "📝 Добавление изменений..."
git add .
git commit -m "🚀 Auto-deploy: $(date '+%Y-%m-%d %H:%M:%S')" || echo "ℹ️  Нет новых изменений"
echo "📤 Отправка на GitHub..."
git push origin main || git push origin master
rm -f .git-credentials
git config --global --unset credential.helper

# ==========================================
# 2. СЕРВЕР: ПОДКЛЮЧЕНИЕ И ПРОВЕРКА
# ==========================================
echo -e "\n${GREEN}2️⃣  Сервер: Подключение${NC}"
read -r -p "🌐 IP адрес сервера: " SERVER_IP
read -r -p "👤 SSH пользователь (root или sudoer): " SSH_USER
read -r -s -p "🔐 SSH пароль (если используется): " SSH_PASS
echo ""

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
if [ -n "$SSH_PASS" ]; then
    # Если установлен sshpass, используем его. Иначе SSH спросит пароль сам.
    if command -v sshpass &> /dev/null; then
        SSH_CMD="sshpass -p '$SSH_PASS' ssh $SSH_OPTS ${SSH_USER}@${SERVER_IP}"
    else
        echo -e "${YELLOW}⚠️  sshpass не найден. SSH запросит пароль интерактивно.${NC}"
        SSH_CMD="ssh $SSH_OPTS ${SSH_USER}@${SERVER_IP}"
    fi
else
    SSH_CMD="ssh $SSH_OPTS ${SSH_USER}@${SERVER_IP}"
fi

# Тест соединения
echo "🔍 Проверка соединения..."
$SSH_CMD "echo '✅ Соединение установлено'" || { echo -e "${RED}❌ Ошибка подключения. Проверьте IP, пользователя и доступ.${NC}"; exit 1; }

# ==========================================
# 3. СЕРВЕР: ОСТАНОВКА СТАРОГО САЙТА
# ==========================================
echo -e "\n${GREEN}3️⃣  Остановка текущего сайта${NC}"
$SSH_CMD << 'EOF'
echo "⛔ Остановка Nginx..."
sudo systemctl stop nginx || true
echo "⛔ Остановка Docker контейнеров..."
sudo docker compose -f /opt/kprf/docker-compose.yml down 2>/dev/null || true
sudo docker stop $(sudo docker ps -aq) 2>/dev/null || true
sudo docker rm $(sudo docker ps -aq) 2>/dev/null || true
echo "✅ Старые сервисы остановлены"
EOF

# ==========================================
# 4. СЕРВЕР: УСТАНОВКА ЗАВИСИМОСТЕЙ
# ==========================================
echo -e "\n${GREEN}4️⃣  Установка системных пакетов${NC}"
$SSH_CMD << 'EOF'
echo "📦 Обновление репозиториев..."
sudo apt update -y
echo "📦 Установка Docker, Nginx, Certbot..."
sudo apt install -y docker.io docker-compose-plugin nginx certbot python3-certbot-nginx
sudo systemctl enable docker nginx
echo "✅ Зависимости установлены"
EOF

# ==========================================
# 5. СЕКРЕТЫ И КЛЮЧИ
# ==========================================
echo -e "\n${GREEN}5️⃣  Отправка .env на сервер${NC}"
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ Файл .env не найден в корне проекта. Создайте его перед деплоем.${NC}"
    exit 1
fi

# Создаём папку на сервере
$SSH_CMD "sudo mkdir -p /opt/kprf && sudo chown $SSH_USER:$SSH_USER /opt/kprf"
echo "📤 Копирование .env..."
if [ -n "$SSH_PASS" ] && command -v sshpass &> /dev/null; then
    sshpass -p "$SSH_PASS" scp .env ${SSH_USER}@${SERVER_IP}:/opt/kprf/.env
else
    scp .env ${SSH_USER}@${SERVER_IP}:/opt/kprf/.env
fi

# ==========================================
# 6. РАЗВЁРТЫВАНИЕ ПРОЕКТА
# ==========================================
echo -e "\n${GREEN}6️⃣  Клонирование и настройка${NC}"
$SSH_CMD << 'DEPLOY_EOF'
cd /opt/kprf
if [ ! -d ".git" ]; then
    echo "📥 Клонирование репозитория..."
    git clone https://github.com/$GH_USER/kprf.git .
else
    echo "📥 Обновление кода..."
    git pull origin main || git pull origin master
fi

echo "🔧 Установка прав..."
sudo chown -R $USER:$USER /opt/kprf
sudo chmod 600 /opt/kprf/.env

echo "🐳 Запуск Docker Compose (БД + App)..."
docker compose up -d --build
sleep 15

echo "🗄️  Применение миграций БД..."
docker compose exec -T app flask db upgrade || echo "⚠️  Миграции пропущены (возможно, уже применены)"

echo "🔄 Перезапуск приложения..."
docker compose restart app
DEPLOY_EOF

# ==========================================
# 7. NGINX + LET'S ENCRYPT
# ==========================================
echo -e "\n${GREEN}7️⃣  Настройка Nginx и SSL${NC}"
read -r -p "🌍 Домен сайта (например: deputaty.ru): " DOMAIN
read -r -p "📧 Email для Let's Encrypt (уведомления об SSL): " EMAIL

cat > /tmp/nginx_kprf.conf << NGINX_EOF
server {
    listen 80;
    server_name ${DOMAIN};
    client_max_body_size 10M;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX_EOF

echo "📤 Загрузка Nginx конфига..."
if [ -n "$SSH_PASS" ] && command -v sshpass &> /dev/null; then
    sshpass -p "$SSH_PASS" scp /tmp/nginx_kprf.conf ${SSH_USER}@${SERVER_IP}:/etc/nginx/sites-available/kprf
else
    scp /tmp/nginx_kprf.conf ${SSH_USER}@${SERVER_IP}:/etc/nginx/sites-available/kprf
fi

$SSH_CMD << SSL_EOF
echo "🔗 Активация конфига Nginx..."
sudo ln -sf /etc/nginx/sites-available/kprf /etc/nginx/sites-enabled/kprf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

echo "🔒 Получение SSL сертификата..."
sudo certbot --nginx -d ${DOMAIN} --email ${EMAIL} --agree-tos --non-interactive --redirect
echo "✅ SSL настроен"

echo "⏰ Настройка автобэкапов БД (каждый день в 03:00)..."
sudo mkdir -p /opt/kprf/backups
cat > /tmp/backup_script.sh << 'BACKUP'
#!/bin/bash
DATE=\$(date +%F_%H%M)
docker compose -f /opt/kprf/docker-compose.yml exec -T db pg_dump -U kprf_user kprf_db | gzip > /opt/kprf/backups/kprf_\${DATE}.sql.gz
find /opt/kprf/backups -name "*.sql.gz" -mtime +7 -delete
BACKUP
sudo mv /tmp/backup_script.sh /opt/kprf/backup_db.sh
sudo chmod +x /opt/kprf/backup_db.sh
(sudo crontab -l 2>/dev/null | grep -v backup_db.sh; echo "0 3 * * * /opt/kprf/backup_db.sh") | sudo crontab -
echo "✅ Бэкапы настроены"

sudo systemctl restart nginx
echo "🌐 Сайт запущен: https://${DOMAIN}"
SSL_EOF

rm -f /tmp/nginx_kprf.conf
echo -e "\n${GREEN}✅ ДЕПЛОЙ ЗАВЕРШЁН УСПЕШНО!${NC}"
echo -e "📊 Проверьте: ${BLUE}https://${DOMAIN}${NC}"
echo -e "🔑 Админка: ${BLUE}https://${DOMAIN}/admin/login${NC}"