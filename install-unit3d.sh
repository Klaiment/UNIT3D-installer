#!/bin/bash

# ========================================================
# Script d'installation automatique pour UNIT3D sur Ubuntu 24.04
# Version: 2.0 - Avec support Docker
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

check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "La commande $1 n'est pas disponible."
        return 1
    fi
    return 0
}

# Début de l'installation
clear
echo "=================================================="
echo "     Installation automatique de UNIT3D"
echo "=================================================="
echo ""
echo "Ce script propose deux méthodes d'installation :"
echo "1) Installation native sur Ubuntu 24.04"
echo "2) Installation via Docker (recommandé)"
echo ""
read -p "Choisissez la méthode d'installation (1/2): " install_method

if [[ "$install_method" != "1" && "$install_method" != "2" ]]; then
    print_error "Choix invalide. Installation annulée."
    exit 1
fi

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
print_info "Mise à jour du système..."
apt update && apt upgrade -y

# Installation des dépendances de base
print_info "Installation des dépendances de base..."
apt install -y software-properties-common curl git unzip

# Installation native
if [[ "$install_method" == "1" ]]; then
    print_section "INSTALLATION NATIVE"
    
    # Ajout du PPA pour PHP 8.4
    print_info "Ajout du dépôt PHP pour obtenir PHP 8.4..."
    add-apt-repository ppa:ondrej/php -y
    apt update

    # Vérification de la disponibilité de PHP 8.4
    if ! apt-cache show php8.4 &> /dev/null; then
        print_error "PHP 8.4 n'est pas disponible dans les dépôts. Veuillez vérifier le PPA ou utiliser l'installation Docker."
        exit 1
    fi

    # Installation de PHP 8.4 et toutes les extensions requises
    print_info "Installation de PHP 8.4 et extensions requises..."
    apt install -y php8.4 php8.4-cli php8.4-common php8.4-fpm php8.4-mysql \
        php8.4-zip php8.4-gd php8.4-mbstring php8.4-curl php8.4-xml php8.4-bcmath \
        php8.4-intl php8.4-readline php8.4-tokenizer php8.4-fileinfo php8.4-opcache \
        php8.4-dom php8.4-json php8.4-libxml php8.4-redis

    # Installation de Nginx
    print_info "Installation de Nginx..."
    apt install -y nginx
    systemctl enable nginx
    systemctl start nginx

    # Installation de MariaDB
    print_info "Installation de MariaDB..."
    apt install -y mariadb-server
    systemctl enable mariadb
    systemctl start mariadb

    # Sécurisation de MariaDB
    print_info "Configuration de MariaDB..."
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password"
    mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$DB_PASS')"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
    mysql -e "DELETE FROM mysql.user WHERE User=''"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
    mysql -e "FLUSH PRIVILEGES"

    # Création de la base de données et de l'utilisateur
    print_info "Création de la base de données..."
    mysql -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
    mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS'"
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'"
    mysql -e "FLUSH PRIVILEGES"

    # Installation de Redis
    print_info "Installation de Redis..."
    apt install -y redis-server
    systemctl enable redis-server
    systemctl start redis-server

    # Installation de MeiliSearch
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

    systemctl enable meilisearch
    systemctl start meilisearch

    # Installation de Node.js et npm
    print_info "Installation de Node.js et npm..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
    
    # Vérification des versions
    print_info "Versions installées:"
    php --version
    node --version
    npm --version
    
    # Installation de Composer
    print_info "Installation de Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # Clonage du dépôt UNIT3D
    print_info "Téléchargement de UNIT3D..."
    cd /var/www
    git clone https://github.com/HDInnovations/UNIT3D.git
    chown -R www-data:www-data UNIT3D
    cd UNIT3D

    # Installation des dépendances avec Composer
    print_info "Installation des dépendances PHP..."
    sudo -u www-data composer install --no-dev --optimize-autoloader

    # En cas d'échec, proposer d'ignorer les exigences de plateforme
    if [ $? -ne 0 ]; then
        print_warning "L'installation standard des dépendances a échoué."
        read -p "Voulez-vous essayer avec --ignore-platform-req=php? (o/n): " ignore_platform
        if [[ "$ignore_platform" == "o" || "$ignore_platform" == "O" ]]; then
            sudo -u www-data composer install --no-dev --optimize-autoloader --ignore-platform-req=php
        else
            print_error "Installation des dépendances échouée. Veuillez vérifier les exigences de PHP."
            exit 1
        fi
    fi

    # Installation des dépendances Node.js
    print_info "Installation des dépendances Node.js..."
    npm install
    npm run build

    # Configuration du fichier .env
    print_info "Configuration de l'environnement..."
    sudo -u www-data cp .env.example .env
    sudo -u www-data php artisan key:generate

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

    # Migrations et seeders
    print_info "Finalisation de l'installation..."
    cd /var/www/UNIT3D
    sudo -u www-data php artisan migrate --seed
    sudo -u www-data php artisan storage:link

    # Configuration des permissions
    print_info "Configuration des permissions..."
    chown -R www-data:www-data /var/www/UNIT3D
    find /var/www/UNIT3D -type f -exec chmod 644 {} \;
    find /var/www/UNIT3D -type d -exec chmod 755 {} \;
    chmod -R 775 /var/www/UNIT3D/storage /var/www/UNIT3D/bootstrap/cache

    # Installation de l'optimiseur d'images
    print_info "Installation de l'optimiseur d'images..."
    apt install -y jpegoptim optipng pngquant gifsicle webp

    # Création d'un script de mise à jour
    print_info "Création d'un script de mise à jour..."
    cat > /usr/local/bin/update-unit3d << EOF
#!/bin/bash
cd /var/www/UNIT3D
sudo -u www-data git pull
sudo -u www-data composer install --no-dev --optimize-autoloader
npm install
npm run build
sudo -u www-data php artisan migrate
sudo -u www-data php artisan cache:clear
sudo -u www-data php artisan view:clear
sudo -u www-data php artisan config:clear
echo "UNIT3D a été mis à jour avec succès!"
EOF
    chmod +x /usr/local/bin/update-unit3d

    # Résumé de l'installation
    DB_ROOT_PASS=$DB_PASS
    INSTALL_TYPE="Installation native"

# Installation Docker
else
    print_section "INSTALLATION DOCKER"
    
    # Vérification de Docker
    if ! check_command docker; then
        print_info "Installation de Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        usermod -aG docker $USER
    fi

    # Vérification de Docker Compose
    if ! check_command docker-compose; then
        print_info "Installation de Docker Compose..."
        apt install -y docker-compose-plugin
    fi

    # Clonage du dépôt UNIT3D
    print_info "Téléchargement de UNIT3D..."
    mkdir -p /var/www
    cd /var/www
    git clone https://github.com/HDInnovations/UNIT3D.git
    cd UNIT3D

    # Configuration du fichier .env
    print_info "Configuration de l'environnement..."
    cp .env.example .env

    # Génération d'un ID utilisateur et groupe pour Sail
    WWWUSER=$(id -u)
    WWWGROUP=$(id -g)

    # Mise à jour du fichier .env
    sed -i "s|APP_URL=.*|APP_URL=$APP_URL|g" .env
    sed -i "s|DB_DATABASE=.*|DB_DATABASE=$DB_NAME|g" .env
    sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USER|g" .env
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|g" .env
    sed -i "s|MAIL_FROM_ADDRESS=.*|MAIL_FROM_ADDRESS=$admin_email|g" .env
    
    # Ajout des variables d'environnement pour Docker
    echo "WWWUSER=$WWWUSER" >> .env
    echo "WWWGROUP=$WWWGROUP" >> .env
    echo "SERVER_NAME=$domain_name" >> .env
    echo "SSL_DOMAIN=$domain_name" >> .env
    
    # Installation de Composer localement
    print_info "Installation de Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    
    # Installation des dépendances avec Composer
    print_info "Installation des dépendances PHP..."
    composer install
    
    # Démarrage des conteneurs Docker
    print_info "Démarrage des conteneurs Docker..."
    docker-compose up -d
    
    # Attendre que les conteneurs soient prêts
    print_info "Attente du démarrage des conteneurs..."
    sleep 10
    
    # Exécution des migrations et seeders
    print_info "Finalisation de l'installation..."
    docker-compose exec laravel.test php artisan key:generate
    docker-compose exec laravel.test php artisan migrate --seed
    docker-compose exec laravel.test php artisan storage:link
    
    # Installation des dépendances Node.js et compilation des assets
    print_info "Compilation des assets frontend..."
    docker-compose exec laravel.test npm install
    docker-compose exec laravel.test npm run build
    
    # Création d'un script de mise à jour
    print_info "Création d'un script de mise à jour..."
    cat > /usr/local/bin/update-unit3d-docker << EOF
#!/bin/bash
cd /var/www/UNIT3D
git pull
docker-compose exec laravel.test composer install --no-dev --optimize-autoloader
docker-compose exec laravel.test npm install
docker-compose exec laravel.test npm run build
docker-compose exec laravel.test php artisan migrate
docker-compose exec laravel.test php artisan cache:clear
docker-compose exec laravel.test php artisan view:clear
docker-compose exec laravel.test php artisan config:clear
echo "UNIT3D a été mis à jour avec succès!"
EOF
    chmod +x /usr/local/bin/update-unit3d-docker
    
    # Résumé de l'installation
    DB_ROOT_PASS=$DB_PASS
    INSTALL_TYPE="Installation Docker"
fi

# Installation terminée
print_info "Installation terminée avec succès!"
echo ""
echo "==================================================="
echo "      RÉSUMÉ DE L'INSTALLATION"
echo "==================================================="
echo "Type d'installation: $INSTALL_TYPE"
echo "URL du site: $APP_URL"
echo "Base de données: $DB_NAME"
echo "Utilisateur DB: $DB_USER"
echo "Mot de passe DB: $DB_PASS"
if [[ "$install_method" == "1" ]]; then
    echo "Mot de passe root DB: $DB_ROOT_PASS"
fi
echo ""
echo "Email admin: $admin_email"
echo ""
echo "Chemin d'installation: /var/www/UNIT3D"
echo "==================================================="
echo ""

if [[ "$install_method" == "1" ]]; then
    print_warning "N'oubliez pas de configurer HTTPS pour votre site!"
    print_warning "Vous pouvez utiliser Certbot pour obtenir un certificat SSL gratuit:"
    echo "sudo apt install -y certbot python3-certbot-nginx"
    echo "sudo certbot --nginx -d $domain_name"
    echo ""
    print_info "Pour mettre à jour UNIT3D à l'avenir, utilisez la commande:"
    echo "sudo update-unit3d"
else
    print_info "Pour mettre à jour UNIT3D à l'avenir, utilisez la commande:"
    echo "sudo update-unit3d-docker"
fi

print_info "Pour accéder à votre site, visitez: $APP_URL"
