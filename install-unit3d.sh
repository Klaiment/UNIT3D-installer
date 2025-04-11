#!/bin/bash

# ========================================================
# Script d'installation automatique pour UNIT3D sur Ubuntu 24.04
# Version: 4.0 - Installation robuste avec correction de tous les problèmes
# Date: 11 avril 2025
# ========================================================

# Vérification des privilèges root
if [[ $EUID -ne 0 ]]; then
   echo "Ce script doit être exécuté en tant que root"
   exit 1
fi

# Variables de configuration
DB_NAME="unit3d"
DB_USER="unit3d"
DB_PASS=$(openssl rand -base64 32)
APP_URL="http://localhost"

# Couleurs pour les messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonctions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ATTENTION]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERREUR]${NC} $1"
}

print_section() {
    echo -e "${BLUE}[SECTION]${NC} $1"
    echo "=================================================="
}

# Début de l'installation
clear
echo "=================================================="
echo "     Installation automatique de UNIT3D"
echo "=================================================="
echo ""
echo "Ce script va installer UNIT3D sur votre serveur Ubuntu 24.04"
echo "ATTENTION: Une phase de nettoyage va supprimer toutes les installations existantes"
echo ""
read -p "Voulez-vous continuer? (o/n): " confirm
if [[ "$confirm" != "o" && "$confirm" != "O" ]]; then
    echo "Installation annulée"
    exit 0
fi

# Phase de nettoyage complet
print_section "NETTOYAGE COMPLET DU SYSTÈME"
print_info "Suppression des installations précédentes..."

# Arrêt des services
print_info "Arrêt des services..."
systemctl stop nginx 2>/dev/null
systemctl stop php8.4-fpm 2>/dev/null
systemctl stop php8.3-fpm 2>/dev/null
systemctl stop php8.2-fpm 2>/dev/null
systemctl stop php8.1-fpm 2>/dev/null
systemctl stop mysql 2>/dev/null
systemctl stop mariadb 2>/dev/null
systemctl stop redis-server 2>/dev/null
systemctl stop meilisearch 2>/dev/null

# Suppression de la base de données UNIT3D
print_info "Suppression de la base de données..."
mysql -e "DROP DATABASE IF EXISTS unit3d" 2>/dev/null
mysql -e "DROP USER IF EXISTS 'unit3d'@'localhost'" 2>/dev/null
mysql -e "FLUSH PRIVILEGES" 2>/dev/null

# Suppression des fichiers d'installation précédents
print_info "Suppression des fichiers d'installation..."
rm -rf /var/www/UNIT3D
rm -f /etc/nginx/sites-available/unit3d
rm -f /etc/nginx/sites-enabled/unit3d
rm -f /usr/local/bin/update-unit3d
rm -f /etc/systemd/system/meilisearch.service

# Nettoyage du cache Composer
print_info "Nettoyage du cache Composer..."
rm -rf /root/.composer
rm -rf /var/www/.composer
rm -rf /home/*/.composer

print_info "Nettoyage terminé."

# Demander les informations nécessaires
read -p "Entrez le nom de domaine (sans http/https): " domain_name
read -p "Entrez l'adresse email pour l'administrateur: " admin_email
read -s -p "Entrez le mot de passe pour l'administrateur: " admin_password
echo ""
read -s -p "Confirmez le mot de passe: " admin_password_confirm
echo ""

if [[ "$admin_password" != "$admin_password_confirm" ]]; then
    print_error "Les mots de passe ne correspondent pas"
    exit 1
fi

APP_URL="http://$domain_name"

# Mise à jour du système
print_section "MISE À JOUR DU SYSTÈME"
print_info "Mise à jour des dépôts et du système..."
apt update && apt upgrade -y

# Installation des dépendances de base
print_info "Installation des dépendances de base..."
apt install -y software-properties-common curl git unzip wget gnupg2 lsb-release ca-certificates apt-transport-https

# Ajout du PPA pour PHP 8.4
print_section "INSTALLATION DE PHP 8.4"
print_info "Ajout du dépôt PHP pour obtenir PHP 8.4..."
add-apt-repository ppa:ondrej/php -y
apt update

# Installation de PHP 8.4 et toutes les extensions requises
print_info "Installation de PHP 8.4 et extensions requises..."
apt install -y php8.4 php8.4-fpm php8.4-cli php8.4-common php8.4-mysql \
    php8.4-zip php8.4-gd php8.4-mbstring php8.4-curl php8.4-xml php8.4-bcmath \
    php8.4-intl php8.4-readline php8.4-opcache php8.4-redis php8.4-igbinary

# Vérification de l'installation de PHP
PHP_VERSION=$(php -v | head -n 1)
print_info "PHP installé: $PHP_VERSION"

# Installation de Nginx
print_section "INSTALLATION DE NGINX"
print_info "Installation et configuration de Nginx..."
apt install -y nginx
systemctl enable nginx
systemctl start nginx

# Installation de MariaDB
print_section "INSTALLATION DE MARIADB"
print_info "Installation et configuration de MariaDB..."
apt install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb

# Sécurisation de MariaDB avec gestion des erreurs
print_info "Configuration de MariaDB..."

# Utilisation de sudo mysql pour éviter les problèmes d'authentification
sudo mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Vérification de l'accès à la base de données
if mysql -u $DB_USER -p$DB_PASS -e "USE $DB_NAME;" &> /dev/null; then
    print_info "Accès à la base de données vérifié avec succès."
else
    print_warning "Impossible d'accéder à la base de données avec l'utilisateur créé."
    print_info "Tentative de correction..."
    sudo mysql -e "DROP USER IF EXISTS '$DB_USER'@'localhost';"
    sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"

    if ! mysql -u $DB_USER -p$DB_PASS -e "USE $DB_NAME;" &> /dev/null; then
        print_error "Échec de la configuration de la base de données. Veuillez vérifier manuellement."
        exit 1
    fi
fi

# Installation de Redis
print_section "INSTALLATION DE REDIS"
print_info "Installation de Redis..."
apt install -y redis-server
systemctl enable redis-server
systemctl start redis-server

# Installation de MeiliSearch
print_section "INSTALLATION DE MEILISEARCH"
print_info "Installation de MeiliSearch..."
curl -L https://install.meilisearch.com | sh
mv ./meilisearch /usr/bin/

# Créer un service systemd pour MeiliSearch
cat > /etc/systemd/system/meilisearch.service << EOF
[Unit]
Description=MeiliSearch
After=systemd-user-sessions.service

[Service]
Type=simple
ExecStart=/usr/bin/meilisearch --http-addr 127.0.0.1:7700
Restart=always
Environment="MEILI_NO_ANALYTICS=true"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable meilisearch
systemctl start meilisearch

# Installation de Node.js et npm
print_section "INSTALLATION DE NODE.JS"
print_info "Installation de Node.js et npm..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Vérification des versions
print_info "Versions installées:"
php --version
node --version
npm --version

# Installation de Composer
print_section "INSTALLATION DE COMPOSER"
print_info "Installation de Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Installation de l'optimiseur d'images
print_info "Installation de l'optimiseur d'images..."
apt install -y jpegoptim optipng pngquant gifsicle webp

# Clonage du dépôt UNIT3D
print_section "INSTALLATION DE UNIT3D"
print_info "Téléchargement de UNIT3D..."
mkdir -p /var/www
cd /var/www
# Supprimer le répertoire s'il existe déjà
if [ -d "UNIT3D" ]; then
    rm -rf UNIT3D
fi
git clone https://github.com/HDInnovations/UNIT3D.git
cd UNIT3D

# Configurer Git pour accepter le répertoire comme sûr
git config --global --add safe.directory /var/www/UNIT3D

# Préparation des permissions pour Composer et npm
print_info "Configuration des permissions..."
mkdir -p /var/www/.composer
mkdir -p /var/www/.npm
chown -R www-data:www-data /var/www/UNIT3D
chown -R www-data:www-data /var/www/.composer
chown -R www-data:www-data /var/www/.npm
chmod -R 775 /var/www/UNIT3D
chmod -R 775 /var/www/.composer
chmod -R 775 /var/www/.npm

# Création manuelle du dossier vendor
mkdir -p /var/www/UNIT3D/vendor
chown -R www-data:www-data /var/www/UNIT3D/vendor
chmod -R 775 /var/www/UNIT3D/vendor

# Définir les variables d'environnement pour Composer et npm
export COMPOSER_HOME="/var/www/.composer"
export npm_config_cache="/var/www/.npm"

# Installation des dépendances avec Composer
print_info "Installation des dépendances PHP..."
cd /var/www/UNIT3D
sudo -u www-data composer install --no-dev --optimize-autoloader --no-interaction --ignore-platform-req=php

# Correction du fichier secure-headers.php
print_info "Correction du fichier secure-headers.php..."
if [ -f "config/secure-headers.php" ]; then
    sed -i "s/'url' => null/'url' => ''/" config/secure-headers.php
    sed -i "s/'url' => env('APP_URL', null)/'url' => env('APP_URL', '')/" config/secure-headers.php
fi

# Installation des dépendances Node.js
print_info "Installation des dépendances Node.js..."
cd /var/www/UNIT3D
sudo -u www-data npm install --no-audit

# Configuration du fichier .env
print_info "Configuration de l'environnement..."
cp .env.example .env
php artisan key:generate

# Mise à jour du fichier .env
sed -i "s|APP_URL=.*|APP_URL=$APP_URL|g" .env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=$DB_NAME|g" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USER|g" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|g" .env
sed -i "s|MAIL_FROM_ADDRESS=.*|MAIL_FROM_ADDRESS=$admin_email|g" .env
sed -i "s|REDIS_HOST=.*|REDIS_HOST=127.0.0.1|g" .env
sed -i "s|MEILISEARCH_HOST=.*|MEILISEARCH_HOST=http://127.0.0.1:7700|g" .env

# Configuration de Nginx
print_info "Configuration de Nginx..."
cat > /etc/nginx/sites-available/unit3d << EOF
server {
    listen 80;
    server_name $domain_name;
    root /var/www/UNIT3D/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size = 100M";
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    client_max_body_size 100M;
}
EOF

# Activation de la configuration Nginx
ln -s /etc/nginx/sites-available/unit3d /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

# Migrations et seeders avec gestion des erreurs
print_info "Finalisation de l'installation..."
cd /var/www/UNIT3D

# Vérifier à nouveau l'accès à la base de données avant les migrations
if ! mysql -u $DB_USER -p$DB_PASS -e "USE $DB_NAME;" &> /dev/null; then
    print_error "Problème d'accès à la base de données avant les migrations."
    print_info "Tentative de correction des permissions..."
    sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
fi

# Exécuter les migrations avec gestion des erreurs
sudo -u www-data php artisan migrate --seed --force || {
    print_error "Échec des migrations. Tentative de correction..."
    # Réinitialiser la base de données et réessayer
    sudo mysql -e "DROP DATABASE $DB_NAME;"
    sudo mysql -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
    sudo -u www-data php artisan migrate --seed --force || {
        print_error "Échec des migrations après tentative de correction. Veuillez vérifier les logs."
    }
}

sudo -u www-data php artisan storage:link

# Configuration des permissions
print_info "Configuration des permissions..."
chown -R www-data:www-data /var/www/UNIT3D
find /var/www/UNIT3D -type f -exec chmod 644 {} \;
find /var/www/UNIT3D -type d -exec chmod 755 {} \;
chmod -R 775 /var/www/UNIT3D/storage /var/www/UNIT3D/bootstrap/cache

# Création d'un script de mise à jour
print_info "Création d'un script de mise à jour..."
cat > /usr/local/bin/update-unit3d << EOF
#!/bin/bash
cd /var/www/UNIT3D
git pull
sudo -u www-data composer install --no-dev --optimize-autoloader --ignore-platform-req=php
cd /var/www/UNIT3D
sudo -u www-data php artisan migrate --force
sudo -u www-data php artisan cache:clear
sudo -u www-data php artisan view:clear
sudo -u www-data php artisan config:clear
echo "UNIT3D a été mis à jour avec succès!"
EOF
chmod +x /usr/local/bin/update-unit3d

# Installation terminée
print_section "INSTALLATION TERMINÉE"
print_info "Installation terminée avec succès!"
echo ""
echo "==================================================="
echo "      RÉSUMÉ DE L'INSTALLATION"
echo "==================================================="
echo "URL du site: $APP_URL"
echo "Base de données: $DB_NAME"
echo "Utilisateur DB: $DB_USER"
echo "Mot de passe DB: $DB_PASS"
echo ""
echo "Email admin: $admin_email"
echo ""
echo "Chemin d'installation: /var/www/UNIT3D"
echo "==================================================="
echo ""
print_warning "N'oubliez pas de configurer HTTPS pour votre site!"
print_warning "Vous pouvez utiliser Certbot pour obtenir un certificat SSL gratuit:"
echo "sudo apt install -y certbot python3-certbot-nginx"
echo "sudo certbot --nginx -d $domain_name"
echo ""
print_info "Pour mettre à jour UNIT3D à l'avenir, utilisez la commande:"
echo "sudo update-unit3d"
