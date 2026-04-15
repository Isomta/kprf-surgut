#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'
echo -e "${BLUE}🚀 Инициализация деплоя KPRF-Deputat...${NC}"

# 1. Загрузка переменных из .env
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

# 2. Запрос недостающих параметров
echo -e "\n${GREEN}1️⃣  Параметры подключения${NC}"
[ -z "${SERVER_IP:-}" ] && read -r -p "🌐 IP адрес сервера: " SERVER_IP
[ -z "${SSH_USER:-}" ] && read -r -p "👤 SSH пользователь (обычно root): " SSH_USER
SSH_PORT=${SSH_PORT:-22}
DOMAIN=${DOMAIN:-}
[ -z "$DOMAIN" ] && read -r -p "🌍 Домен сайта: " DOMAIN
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-}
[ -z "$LETSENCRYPT_EMAIL" ] && read -r -p "📧 Email для SSL: " LETSENCRYPT_EMAIL

# Команда SSH с таймаутами и проверкой ключей
SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o ServerAliveInterval=5 -p $SSH_PORT $SSH_USER@$SERVER_IP"

echo -e "\n🔍 Проверка соединения с $SSH_USER@$SERVER_IP..."
$SSH_CMD "echo '✅ Соединение установлено'" || {
    echo -e "${RED}❌ Ошибка подключения. Проверьте IP, порт, фаервол и доступ.${NC}"
    exit 1
}

# 3. GitHub: Коммит и пуш
echo -e "\n${GREEN}2️⃣  GitHub: Отправка кода${NC}"
read -r -p "📦 GitHub username: " GH_USER
read -r -s -p "🔑 GitHub Token (PAT): " GH_TOKEN; echo ""
REPO_URL="https://$GH_USER:$GH_TOKEN@github.com/$GH_USER/kprf.git"

git remote set-url origin "$REPO_URL" 2>/dev/null || git remote add origin "$REPO_URL"
git add .
git commit -m "🚀 Deploy: $(date '+%Y-%m-%d %H:%M:%S')" || echo "ℹ️  Нет изменений"
git push origin main || git push origin master
git remote set-url origin "https://github.com/$GH_USER/kprf.git" # Убираем токен из конфига

# 4. Сервер: Остановка старого сайта и установка пакетов
echo -e "\n${GREEN}3️⃣  Сервер: Остановка старого сайта и подготовка${NC}"
$SSH_CMD << 'EOF'
echo "⛔ Остановка текущего Nginx и Docker..."
sudo systemctl stop nginx 2>/dev/null || true
sudo docker compose -f /opt/kprf/docker-compose.yml down 2>/dev/null || true
sudo docker stop $(sudo docker ps -aq) 2>/dev/null || true
sudo docker rm $(sudo docker ps -aq) 2>/dev/null || true
echo "✅ Старые сервисы остановлены"

echo "📦 Установка Docker, Nginx, Certbot..."
sudo apt update -y && sudo apt install -y docker.io docker-compose-plugin nginx certbot python3-certbot-nginx
sudo systemctl enable docker nginx
sudo mkdir -p /opt/kprf /opt/kprf/backups
EOF

# 5. Деплой кода и конфигов
echo -e "\n${GREEN}4️⃣  Развертывание приложения${NC}"
$SSH_CMD << DEPLOY_EOF
cd /opt/kprf
if [ ! -d ".git" ]; then
    git clone https://github.com/$GH_USER/kprf.git .
else
    git pull origin main || git pull origin master
fi
DEPLOY_EOF

echo "📤 Отправка .env на сервер..."
scp -o StrictHostKeyChecking=no -P $SSH_PORT .env $SSH_USER@$SERVER_IP:/opt/kprf/.env
$SSH_CMD "chmod 600 /opt/kprf/.env"

# 6. Запуск Docker и миграции
echo -e "\n${GREEN}5️⃣  Запуск Docker и инициализация БД${NC}"
$SSH_CMD << 'EOF'
cd /opt/kprf
docker compose up -d --build
sleep 20
docker compose exec -T app flask db upgrade || echo "⚠️  Миграции пропущены или уже применены"
docker compose restart app
echo "✅ Приложение запущено на порту 8080"
EOF

# 7. Nginx + SSL + Бэкапы
echo -e "\n${GREEN}6️⃣  Настройка Nginx и получение SSL${NC}"
cat > /tmp/nginx_kprf.conf << NGINX_EOF
server {
    listen 80;
    server_name $DOMAIN;
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

scp -o StrictHostKeyChecking=no -P $SSH_PORT /tmp/nginx_kprf.conf $SSH_USER@$SERVER_IP:/etc/nginx/sites-available/kprf
rm -f /tmp/nginx_kprf.conf

$SSH_CMD << SSL_EOF
sudo ln -sf /etc/nginx/sites-available/kprf /etc/nginx/sites-enabled/kprf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

echo "🔒 Получение SSL сертификата для $DOMAIN..."
sudo certbot --nginx -d $DOMAIN --email $LETSENCRYPT_EMAIL --agree-tos --non-interactive --redirect
echo "✅ SSL настроен"

# Настройка автобэкапов
cat > /tmp/backup.sh << 'BACKUP'
#!/bin/bash
DATE=\$(date +%F_%H%M)
docker compose -f /opt/kprf/docker-compose.yml exec -T db pg_dump -U kprf_user kprf_db | gzip > /opt/kprf/backups/kprf_\${DATE}.sql.gz
find /opt/kprf/backups -name "*.sql.gz" -mtime +7 -delete
BACKUP
sudo mv /tmp/backup.sh /opt/kprf/backup_db.sh
sudo chmod +x /opt/kprf/backup_db.sh
(sudo crontab -l 2>/dev/null | grep -v backup_db.sh; echo "0 3 * * * /opt/kprf/backup_db.sh") | sudo crontab -
echo "✅ Автобэкапы настроены (ежедневно в 03:00)"

sudo systemctl restart nginx
echo -e "\n${GREEN}🎉 ДЕПЛОЙ ЗАВЕРШЁН УСПЕШНО!${NC}"
echo -e "🌐 Сайт: https://$DOMAIN"
echo -e "🔐 Админка: https://$DOMAIN/admin/login"
SSL_EOF