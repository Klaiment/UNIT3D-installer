#!/bin/bash

# ========================================================
# Script d'installation automatique pour UNIT3D sur Ubuntu 20.04
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
APP_KEY=$(openssl rand -base64 32)

# Couleurs pour les messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# Début de l'installation
clear
echo "=================================================="
echo "     Installation automatique de UNIT3D"
echo "=================================================="
echo ""
echo "Ce script va installer UNIT3D sur votre serveur Ubuntu 20.04"
echo ""
read -p "Voulez-vous continuer? (o/n): " confirm
if [[ "$confirm" != "o" && "$confirm" != "O" ]]; then
    echo "Installation annulée"
    exit 0
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

# Ajout du PPA pour PHP 8.1
print_info "Ajout du dépôt PHP..."
add-apt-repository ppa:ondrej/php -y
apt update

# Installation de PHP et toutes les extensions requises
print_info "Installation de PHP et ses extensions..."
apt install -y php8.1 php8.1-cli php8.1-common php8.1-fpm php8.1-mysql \
    php8.1-zip php8.1-gd php8.1-mbstring php8.1-curl php8.1-xml php8.1-bcmath \
    php8.1-intl php8.1-readline php8.1-tokenizer php8.1-fileinfo php8.1-opcache

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

# Sécurisation de MariaDB (non-interactive)
print_info "Configuration de MariaDB..."
mysql -e "UPDATE mysql.user SET Password=PASSWORD('$DB_PASS') WHERE User='root'"
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

# Configuration du fichier .env
print_info "Configuration de l'environnement..."
sudo -u www-data cp .env.example .env
sudo -u www-data php artisan key:generate

# Mise à jour du fichier .env
sed -i "s|APP_URL=.*|APP_URL=$APP_URL|g" .env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=$DB_NAME|g" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USER|g" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|g" .env

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
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

# Activation de la configuration Nginx
ln -s /etc/nginx/sites-available/unit3d /etc/nginx/sites-enabled/
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

# Création d'un script de mise à jour
print_info "Création d'un script de mise à jour..."
cat > /usr/local/bin/update-unit3d << EOF
#!/bin/bash
cd /var/www/UNIT3D
sudo -u www-data git pull
sudo -u www-data composer install --no-dev --optimize-autoloader
sudo -u www-data php artisan migrate
sudo -u www-data php artisan cache:clear
sudo -u www-data php artisan view:clear
sudo -u www-data php artisan config:clear
echo "UNIT3D a été mis à jour avec succès!"
EOF
chmod +x /usr/local/bin/update-unit3d

# Installation terminée
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
echo "ou"
echo "cd /var/www/UNIT3D && php artisan git:update"
