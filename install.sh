#!/bin/bash

# Script d'installation YouTube Shorts API pour VPS avec n8n
# Port 5001 pour éviter conflit avec n8n (généralement sur 5678)

set -e

echo "========================================"
echo "🎥 YouTube Shorts API - Installation VPS"
echo "========================================"
echo "✅ Compatible avec n8n existant"
echo "📍 Port utilisé : 5001"
echo "========================================"

# Variables
API_KEY="sk_prod_2025_youtube_shorts_secure_key_xyz789"
SERVER_IP=$(curl -s ifconfig.me)
APP_PORT=5001
APP_USER="youtube"
APP_DIR="/home/$APP_USER/youtube-shorts-api"

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}📍 IP serveur: $SERVER_IP${NC}"
echo -e "${YELLOW}📍 Port API: $APP_PORT${NC}"
echo ""

# Vérifier si root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ce script doit être exécuté en root"
    echo "Utilisez: sudo bash install.sh"
    exit 1
fi

# Fonction de vérification
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $1${NC}"
    else
        echo "❌ Erreur: $1"
        exit 1
    fi
}

# Vérifier si n8n est installé
if systemctl is-active --quiet n8n; then
    echo -e "${GREEN}✅ n8n détecté et actif${NC}"
    N8N_PORT=$(ss -tlnp | grep n8n | awk '{print $4}' | cut -d':' -f2 | head -1)
    echo -e "${YELLOW}📍 n8n utilise le port: ${N8N_PORT:-5678}${NC}"
fi

# Installation des dépendances système
echo -e "${YELLOW}📦 Installation des dépendances...${NC}"
apt update -qq
apt install -y python3 python3-pip python3-venv ffmpeg git curl > /dev/null 2>&1
check_status "Installation dépendances"

# Vérifier FFmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "❌ FFmpeg non installé!"
    exit 1
fi

# Créer utilisateur si nécessaire
if ! id -u $APP_USER > /dev/null 2>&1; then
    echo -e "${YELLOW}👤 Création utilisateur $APP_USER...${NC}"
    adduser $APP_USER --gecos "" --disabled-password > /dev/null 2>&1
    echo "$APP_USER:YtApi2025!" | chpasswd
    check_status "Création utilisateur"
else
    echo -e "${GREEN}✅ Utilisateur $APP_USER existe${NC}"
fi

# Créer structure
echo -e "${YELLOW}📁 Création des dossiers...${NC}"
mkdir -p $APP_DIR
mkdir -p $APP_DIR/temp
chown -R $APP_USER:$APP_USER $APP_DIR
check_status "Création dossiers"

# Copier les fichiers
echo -e "${YELLOW}📄 Copie des fichiers...${NC}"
cp server.py $APP_DIR/
cp requirements.txt $APP_DIR/
cp .env.example $APP_DIR/.env
chown -R $APP_USER:$APP_USER $APP_DIR
check_status "Copie fichiers"

# Configurer .env
echo -e "${YELLOW}🔑 Configuration .env...${NC}"
sed -i "s|your-secure-api-key-here|$API_KEY|g" $APP_DIR/.env
sed -i "s|PORT=.*|PORT=$APP_PORT|g" $APP_DIR/.env
sed -i "s|BASE_URL=.*|BASE_URL=http://$SERVER_IP:$APP_PORT|g" $APP_DIR/.env
sed -i "s|TEMP_DIR=.*|TEMP_DIR=$APP_DIR/temp|g" $APP_DIR/.env
check_status "Configuration .env"

# Installation Python en tant qu'utilisateur
echo -e "${YELLOW}🐍 Installation environnement Python...${NC}"
sudo -u $APP_USER bash << EOF
cd $APP_DIR
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt > /dev/null 2>&1
# Mise à jour yt-dlp
pip install --upgrade yt-dlp > /dev/null 2>&1
EOF
check_status "Installation Python"

# Service systemd
echo -e "${YELLOW}🚀 Configuration service systemd...${NC}"
cat > /etc/systemd/system/youtube-shorts-api.service << EOF
[Unit]
Description=YouTube Shorts API
After=network.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/gunicorn --bind 0.0.0.0:$APP_PORT --workers 2 --timeout 120 server:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable youtube-shorts-api > /dev/null 2>&1
systemctl start youtube-shorts-api
check_status "Service systemd"

# Nginx configuration (si installé)
if command -v nginx &> /dev/null; then
    echo -e "${YELLOW}🔒 Configuration Nginx...${NC}"
    cat > /etc/nginx/sites-available/youtube-api << EOF
server {
    listen 8080;
    server_name $SERVER_IP;

    client_max_body_size 500M;
    proxy_read_timeout 300s;

    location /youtube-api/ {
        rewrite ^/youtube-api/(.*)\$ /\$1 break;
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/youtube-api /etc/nginx/sites-enabled/
    nginx -t > /dev/null 2>&1 && systemctl reload nginx
    echo -e "${GREEN}✅ Nginx configuré sur le port 8080${NC}"
fi

# Ouvrir les ports firewall
if command -v ufw &> /dev/null; then
    echo -e "${YELLOW}🔥 Configuration firewall...${NC}"
    ufw allow $APP_PORT/tcp > /dev/null 2>&1
    ufw allow 8080/tcp > /dev/null 2>&1
    check_status "Configuration firewall"
fi

# Test de l'API
echo -e "${YELLOW}🧪 Test de l'API...${NC}"
sleep 5

if curl -s -f -X POST http://localhost:$APP_PORT/test \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" > /dev/null; then
    echo -e "${GREEN}✅ API fonctionnelle !${NC}"
else
    echo "❌ L'API ne répond pas"
    echo "Vérifiez les logs : journalctl -u youtube-shorts-api -f"
fi

# Résumé
echo ""
echo "========================================"
echo -e "${GREEN}✅ Installation terminée !${NC}"
echo "========================================"
echo ""
echo -e "📡 ${GREEN}Accès Direct :${NC}"
echo -e "   URL : http://$SERVER_IP:$APP_PORT"
echo ""
if command -v nginx &> /dev/null; then
    echo -e "📡 ${GREEN}Accès via Nginx :${NC}"
    echo -e "   URL : http://$SERVER_IP:8080/youtube-api/"
fi
echo ""
echo -e "🔑 ${GREEN}API Key :${NC}"
echo -e "   $API_KEY"
echo ""
echo -e "📝 ${GREEN}Configuration n8n :${NC}"
echo -e "   URL : http://$SERVER_IP:$APP_PORT/download"
echo -e "   Header : X-API-Key"
echo -e "   Body : {\"video_url\": \"{{ \$json.url }}\"}"
echo ""
echo -e "🔧 ${GREEN}Commandes utiles :${NC}"
echo "   systemctl status youtube-shorts-api"
echo "   systemctl restart youtube-shorts-api"
echo "   journalctl -u youtube-shorts-api -f"
echo "   cd $APP_DIR"
echo ""
echo -e "⚠️  ${YELLOW}IMPORTANT :${NC}"
echo "   1. Changez l'API_KEY dans $APP_DIR/.env"
echo "   2. Redémarrez : systemctl restart youtube-shorts-api"
echo ""
echo "========================================"
