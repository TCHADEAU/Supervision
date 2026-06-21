# Guide d'installation des outils de supervision
### Société Tchadienne des Eaux (STE)

Document interne — Service informatique / SIG
Serveurs x86 Linux — Installation, configuration et maintenance d'une stack de supervision complète en environnement d'entreprise.

Stack : Ubuntu Server 22.04 LTS · Zabbix 6.4 · Grafana · Netdata · LibreNMS · ClamAV · Graylog · Docker Compose.

---

## 1. Introduction et concepts de base

### 1.1 Qu'est-ce que la supervision du SI ?

La supervision du Système d'Information consiste à surveiller en permanence l'ensemble des composants informatiques :

| Domaine | Éléments surveillés |
|---|---|
| Serveurs | CPU, RAM, disque, température |
| Réseau | Switches, routeurs, bande passante |
| Sécurité | Virus, intrusions, logs suspects |
| Services | Web, mail, base de données, DNS |
| Sauvegardes | État, durée, succès/échec |

### 1.2 Stack de supervision utilisée

| Outil | Rôle |
|---|---|
| **Zabbix** | Supervision serveurs, réseau, services |
| **Grafana** | Tableaux de bord visuels et graphiques |
| **LibreNMS** | Supervision réseau dédiée (SNMP) |
| **ClamAV** | Antivirus open source |
| **Graylog** | Centralisation et analyse des logs |
| **Netdata** | Monitoring temps réel léger |

### 1.3 Schéma global de l'architecture

```
                    ┌─────────────────────┐
                    │   SERVEUR CENTRAL   │
                    │   DE SUPERVISION    │
                    │                     │
                    │  ┌───────────────┐  │
                    │  │    Zabbix     │  │
                    │  │    Grafana    │  │
                    │  │    Graylog    │  │
                    │  │    LibreNMS   │  │
                    │  └───────────────┘  │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
    ┌─────────▼──────┐ ┌───────▼──────┐ ┌──────▼───────┐
    │  SERVEURS      │ │   RÉSEAU     │ │   POSTES     │
    │  Linux/Windows │ │  Switches    │ │   Agents     │
    │  Agents Zabbix │ │  Routeurs    │ │   ClamAV     │
    │  ClamAV        │ │  SNMP actif  │ │              │
    └────────────────┘ └──────────────┘ └──────────────┘
```

---

## 2. Architecture de supervision recommandée

### 2.1 Serveur de supervision dédié

| Composant | Minimum | Recommandé |
|---|---|---|
| OS | Ubuntu Server 22.04 LTS | Ubuntu Server 22.04 LTS |
| CPU | 4 cœurs | 8 cœurs |
| RAM | 8 Go | 16 Go |
| Disque | 200 Go SSD | 500 Go SSD |
| Réseau | 1 Gbps | 1 Gbps |
| IP | Fixe | Fixe |

### 2.2 Plan d'adressage recommandé

```
192.168.1.200  → Serveur de supervision
192.168.1.201  → Serveur Web
192.168.1.202  → Serveur de fichiers
192.168.1.203  → Serveur de base de données
192.168.1.1    → Routeur/Pare-feu
192.168.1.2    → Switch principal
```

---

## 3. Préparation des serveurs

### 3.1 Configuration initiale

```bash
# Connexion SSH
ssh admin@192.168.1.200

# Mise à jour du système
sudo apt update && sudo apt upgrade -y

# Installation des outils de base
sudo apt install -y \
    curl wget git vim htop net-tools nmap unzip \
    gnupg software-properties-common \
    apt-transport-https ca-certificates lsb-release

# Configuration du nom d'hôte
sudo hostnamectl set-hostname supervision-central

# Fuseau horaire
sudo timedatectl set-timezone Europe/Paris
sudo timedatectl set-ntp true
```

### 3.2 Configuration du pare-feu

```bash
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH
sudo ufw allow 22/tcp

# Zabbix
sudo ufw allow 10050/tcp   # Agent
sudo ufw allow 10051/tcp   # Serveur

# Interfaces web
sudo ufw allow 80/tcp      # HTTP / Zabbix
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 3000/tcp    # Grafana
sudo ufw allow 9000/tcp    # Graylog
sudo ufw allow 8080/tcp    # LibreNMS
sudo ufw allow 19999/tcp   # Netdata

# SNMP
sudo ufw allow 161/udp
sudo ufw allow 162/udp

sudo ufw status verbose
```

### 3.3 Installation de Docker

```bash
# Installation automatique
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Ajouter l'utilisateur au groupe docker
sudo usermod -aG docker $USER

# Docker Compose
sudo apt install docker-compose-plugin -y

# Démarrage automatique
sudo systemctl enable docker
sudo systemctl start docker

# Vérification
docker --version
docker compose version
docker run hello-world
```

---

## 4. Zabbix — Supervision serveurs et réseau

### 4.1 Installation du serveur Zabbix

```bash
# Ajouter le dépôt Zabbix 6.4
wget https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu22.04_all.deb
sudo dpkg -i zabbix-release_6.4-1+ubuntu22.04_all.deb
sudo apt update

# Installer Zabbix Server + Frontend + Agent
sudo apt install -y \
    zabbix-server-mysql \
    zabbix-frontend-php \
    zabbix-apache-conf \
    zabbix-sql-scripts \
    zabbix-agent

# Installer MySQL
sudo apt install -y mysql-server
sudo mysql_secure_installation
```

### 4.2 Configuration de la base de données

```sql
-- Dans MySQL
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'MotDePasseZabbix123!';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EXIT;
```

```bash
# Importer le schéma
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | \
    mysql --default-character-set=utf8mb4 -u zabbix -p zabbix
```

### 4.3 Configuration de Zabbix Server

```bash
sudo nano /etc/zabbix/zabbix_server.conf
```

```ini
DBHost=localhost
DBName=zabbix
DBUser=zabbix
DBPassword=MotDePasseZabbix123!

# Performances (recommandé)
StartPollers=10
StartPingers=5
CacheSize=128M
HistoryCacheSize=64M
TrendCacheSize=32M
```

```bash
# Fuseau horaire PHP
sudo nano /etc/zabbix/apache.conf
# php_value date.timezone Europe/Paris

# Démarrage des services
sudo systemctl restart zabbix-server zabbix-agent apache2
sudo systemctl enable zabbix-server zabbix-agent apache2
```

### 4.4 Configuration initiale via l'interface web

```
URL : http://192.168.1.200/zabbix
Login par défaut : Admin / zabbix
Changer le mot de passe immédiatement !
```

Assistant de configuration :

1. Vérification des prérequis → tout doit être vert.
2. Connexion DB : MySQL / localhost / 3306 / zabbix.
3. Détails serveur : localhost / 10051 / « Supervision Entreprise ».
4. Fuseau horaire : Europe/Paris.

### 4.5 Installation de l'agent sur les serveurs supervisés

```bash
# À exécuter sur CHAQUE serveur à superviser

wget https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu22.04_all.deb
sudo dpkg -i zabbix-release_6.4-1+ubuntu22.04_all.deb
sudo apt update
sudo apt install zabbix-agent -y

# Configuration de l'agent
sudo nano /etc/zabbix/zabbix_agentd.conf
```

```ini
Server=192.168.1.200
ServerActive=192.168.1.200
Hostname=NOM-DU-SERVEUR
```

```bash
sudo systemctl enable --now zabbix-agent
sudo ufw allow 10050/tcp
```

### 4.6 Templates recommandés

| Type de serveur | Template Zabbix |
|---|---|
| Linux | Linux by Zabbix agent |
| Windows | Windows by Zabbix agent |
| Apache | Apache by Zabbix agent |
| MySQL/MariaDB | MySQL by Zabbix agent |
| Nginx | Nginx by Zabbix agent |
| Docker | Docker by Zabbix agent |
| Switch SNMP | Network Generic Device by SNMP |
| Cisco | Cisco IOS by SNMP |

### 4.7 Configuration des alertes email

```
Administration → Médias → Email
→ Serveur SMTP : smtp.entreprise.fr
→ Port : 587
→ Email expéditeur : zabbix@entreprise.fr

Administration → Utilisateurs → Admin → Médias
→ Type : Email
→ Adresse : admin@entreprise.fr
→ Événements : Problème, Résolu

Configuration → Actions → Trigger actions
→ Sévérité >= Haute → Envoyer message à Admin
```

---

## 5. Grafana — Tableaux de bord visuels

### 5.1 Installation

```bash
# Ajouter le dépôt Grafana
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | \
    gpg --dearmor | \
    sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] \
    https://apt.grafana.com stable main" | \
    sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt update
sudo apt install grafana -y

sudo systemctl enable --now grafana-server
```

```
URL : http://192.168.1.200:3000
Login par défaut : admin / admin
Changer le mot de passe à la première connexion !
```

### 5.2 Connexion à Zabbix

```bash
# Installer le plugin Zabbix
sudo grafana-cli plugins install alexanderzobnin-zabbix-app
sudo systemctl restart grafana-server
```

```
Configuration → Plugins → Zabbix → Activer

Configuration → Data Sources → Add data source → Zabbix
→ URL : http://localhost/zabbix/api_jsonrpc.php
→ Utilisateur : Admin
→ Mot de passe : [votre mot de passe Zabbix]
→ Save & Test → "Data source is working"
```

### 5.3 Dashboards recommandés

| ID | Nom |
|---|---|
| 7039 | Zabbix Server Dashboard |
| 9276 | Linux Host Overview |
| 10048 | Network Overview |
| 13407 | System Overview |

```
Dashboards → Import → Coller l'ID → Sélectionner la source Zabbix → Import
```

---

## 6. Netdata — Supervision temps réel

### 6.1 Installation

```bash
# À installer sur CHAQUE serveur supervisé

wget -O /tmp/netdata-kickstart.sh https://my-netdata.io/kickstart.sh
sudo sh /tmp/netdata-kickstart.sh --stable-channel

sudo systemctl enable --now netdata
```

### 6.2 Configuration

```bash
sudo nano /etc/netdata/netdata.conf
```

```ini
[global]
    hostname = NOM-DU-SERVEUR
    history = 3600

[web]
    bind to = 0.0.0.0
    default port = 19999
```

```
Accès local : http://IP-DU-SERVEUR:19999
```

### 6.3 Centralisation avec Netdata Cloud

```bash
# Créer un compte sur https://app.netdata.cloud
# Récupérer le token depuis Administration → Nodes → Connect Nodes

sudo netdata-claim.sh \
    -token=VOTRE_TOKEN \
    -rooms=VOTRE_ROOM_ID \
    -url=https://app.netdata.cloud
```

---

## 7. LibreNMS — Supervision réseau dédiée

### 7.1 Déploiement avec Docker

```bash
mkdir -p /opt/librenms && cd /opt/librenms
nano docker-compose.yml
```

```yaml
version: "3.8"

services:
  db:
    image: mariadb:10.5
    container_name: librenms_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword123
      MYSQL_DATABASE: librenms
      MYSQL_USER: librenms
      MYSQL_PASSWORD: librenmspassword123
    volumes:
      - db_data:/var/lib/mysql

  redis:
    image: redis:6-alpine
    container_name: librenms_redis
    restart: always

  librenms:
    image: librenms/librenms:latest
    container_name: librenms_app
    restart: always
    ports:
      - "8080:8000"
    environment:
      DB_HOST: db
      DB_NAME: librenms
      DB_USER: librenms
      DB_PASSWORD: librenmspassword123
      REDIS_HOST: redis
      TZ: Europe/Paris
    volumes:
      - librenms_data:/data
    depends_on:
      - db
      - redis

  dispatcher:
    image: librenms/librenms:latest
    container_name: librenms_dispatcher
    restart: always
    environment:
      DB_HOST: db
      DB_NAME: librenms
      DB_USER: librenms
      DB_PASSWORD: librenmspassword123
      REDIS_HOST: redis
      DISPATCHER_NODE_ID: dispatcher1
      SIDECAR_DISPATCHER: 1
      TZ: Europe/Paris
    volumes:
      - librenms_data:/data
    depends_on:
      - librenms

volumes:
  db_data:
  librenms_data:
```

```bash
docker compose up -d
docker compose ps
```

```
URL : http://192.168.1.200:8080
```

### 7.2 Configuration SNMP sur les équipements

```bash
# Sur Linux
sudo apt install snmpd snmp -y
sudo nano /etc/snmp/snmpd.conf
```

```ini
agentAddress udp:161
rocommunity public 192.168.1.200
sysLocation "Salle Serveur"
sysContact "admin@entreprise.fr"
```

```bash
sudo systemctl enable --now snmpd
```

```
# Sur Cisco
snmp-server community public RO
snmp-server host 192.168.1.200 version 2c public
```

### 7.3 Ajouter des équipements

```
Devices → Add Device
→ Hostname/IP : 192.168.1.1
→ SNMP Version : v2c
→ Community : public
→ Add Device

# Découverte automatique
Settings → Discovery → Network Discovery
→ Plage : 192.168.1.0/24
```

---

## 8. Antivirus — ClamAV et protection

### 8.1 Installation

```bash
# À installer sur CHAQUE serveur

sudo apt install clamav clamav-daemon clamav-freshclam -y

# Mise à jour des signatures
sudo systemctl stop clamav-freshclam
sudo freshclam
sudo systemctl enable --now clamav-freshclam
sudo systemctl enable --now clamav-daemon

clamscan --version
```

### 8.2 Configuration

```bash
sudo nano /etc/clamav/clamd.conf
```

```ini
LogFile /var/log/clamav/clamav.log
LogTime yes
LogVerbose yes
MaxFileSize 100M
MaxScanSize 400M
MaxFiles 15000
DetectPUA yes
ScanArchive yes
ScanHTML yes
ScanOLE2 yes
ScanPDF yes
```

### 8.3 Script de scan automatique

```bash
sudo nano /usr/local/bin/scan_antivirus.sh
```

```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/clamav/scan_$DATE.log"
EMAIL_ADMIN="admin@entreprise.fr"

echo "========================================"  | tee $LOG_FILE
echo "SCAN ANTIVIRUS - $(date)"                  | tee -a $LOG_FILE
echo "Serveur : $(hostname)"                     | tee -a $LOG_FILE
echo "========================================"  | tee -a $LOG_FILE

# Mise à jour des signatures
echo "[1/3] Mise à jour des signatures..." | tee -a $LOG_FILE
freshclam >> $LOG_FILE 2>&1

# Scan des répertoires critiques
echo "[2/3] Scan en cours..." | tee -a $LOG_FILE
clamscan \
    --recursive \
    --infected \
    --log=$LOG_FILE \
    --exclude-dir=/proc \
    --exclude-dir=/sys \
    --exclude-dir=/dev \
    /home /var/www /tmp /var/tmp /opt

# Analyse des résultats
INFECTED=$(grep "Infected files:" $LOG_FILE | awk '{print $3}')
echo "[3/3] Fichiers infectés : $INFECTED" | tee -a $LOG_FILE

# Alerte si virus détecté
if [ "$INFECTED" -gt "0" ]; then
    echo "ALERTE VIRUS DÉTECTÉ sur $(hostname) !" | tee -a $LOG_FILE

    # Email d'alerte
    mail -s "ALERTE VIRUS - $(hostname)" $EMAIL_ADMIN < $LOG_FILE

    # Alerte Zabbix
    zabbix_sender -z 192.168.1.200 -s "$(hostname)" \
        -k "clamav.infected" -o "$INFECTED"
fi

echo "Scan terminé : $(date)" | tee -a $LOG_FILE
```

```bash
sudo chmod +x /usr/local/bin/scan_antivirus.sh

# Planification cron
sudo crontab -e
# 0 2 * * * /usr/local/bin/scan_antivirus.sh
# 0 */4 * * * freshclam --quiet
```

### 8.4 Intégration dans Zabbix

```bash
sudo nano /etc/zabbix/scripts/check_clamav.sh
```

```bash
#!/bin/bash
LAST_SCAN=$(ls -t /var/log/clamav/scan_*.log 2>/dev/null | head -1)
[ -z "$LAST_SCAN" ] && echo "0" && exit 0
INFECTED=$(grep "Infected files:" $LAST_SCAN | awk '{print $3}')
echo "${INFECTED:-0}"
```

```bash
sudo chmod +x /etc/zabbix/scripts/check_clamav.sh

# Ajouter dans zabbix_agentd.conf
sudo nano /etc/zabbix/zabbix_agentd.conf
# UserParameter=clamav.infected,/etc/zabbix/scripts/check_clamav.sh
# UserParameter=clamav.db.version,sigtool --info /var/lib/clamav/main.cvd | grep Version | awk '{print $2}'

sudo systemctl restart zabbix-agent
```

### 8.5 Mise en quarantaine automatique

```bash
sudo nano /usr/local/bin/quarantaine_virus.sh
```

```bash
#!/bin/bash
QUARANTINE_DIR="/var/quarantine"
mkdir -p $QUARANTINE_DIR && chmod 700 $QUARANTINE_DIR

clamscan \
    --recursive \
    --move=$QUARANTINE_DIR \
    --log=/var/log/clamav/quarantine_$(date +%Y%m%d).log \
    /home /var/www /tmp

echo "Quarantaine effectuée : $QUARANTINE_DIR"
ls -la $QUARANTINE_DIR
```

```bash
sudo chmod +x /usr/local/bin/quarantaine_virus.sh
```

---

## 9. Graylog — Centralisation des logs

### 9.1 Déploiement avec Docker

```bash
# Générer les secrets nécessaires
pwgen -N 1 -s 96                                          # → GRAYLOG_PASSWORD_SECRET
echo -n "VotreMotDePasseAdmin" | sha256sum | cut -d" " -f1  # → ROOT_PASSWORD_SHA2

mkdir -p /opt/graylog && cd /opt/graylog
nano docker-compose.yml
```

```yaml
version: "3.8"

services:
  mongodb:
    image: mongo:6.0
    container_name: graylog_mongo
    restart: always
    volumes:
      - mongo_data:/data/db

  opensearch:
    image: opensearchproject/opensearch:2.4.0
    container_name: graylog_opensearch
    restart: always
    environment:
      - "OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g"
      - "bootstrap.memory_lock=true"
      - "discovery.type=single-node"
      - "action.auto_create_index=false"
      - "plugins.security.disabled=true"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - opensearch_data:/usr/share/opensearch/data

  graylog:
    image: graylog/graylog:5.1
    container_name: graylog_app
    restart: always
    depends_on:
      - mongodb
      - opensearch
    ports:
      - "9000:9000"         # Interface web
      - "1514:1514"         # Syslog TCP
      - "1514:1514/udp"     # Syslog UDP
      - "12201:12201"       # GELF TCP
      - "12201:12201/udp"   # GELF UDP
    environment:
      GRAYLOG_PASSWORD_SECRET: "VotreSecretGenere96Caracteres"
      GRAYLOG_ROOT_PASSWORD_SHA2: "HashSHA256DuMotDePasse"
      GRAYLOG_HTTP_EXTERNAL_URI: "http://192.168.1.200:9000/"
      GRAYLOG_MONGODB_URI: "mongodb://mongodb/graylog"
      GRAYLOG_ELASTICSEARCH_HOSTS: "http://opensearch:9200"
      TZ: Europe/Paris
    volumes:
      - graylog_data:/usr/share/graylog/data

volumes:
  mongo_data:
  opensearch_data:
  graylog_data:
```

```bash
docker compose up -d
docker compose logs -f graylog
```

```
URL : http://192.168.1.200:9000
Login : admin / VotreMotDePasseAdmin
```

### 9.2 Configuration des inputs

```
System → Inputs → Launch new input

Input Syslog UDP :
→ Type : Syslog UDP
→ Titre : "Syslog Serveurs"
→ Port : 1514

Input GELF :
→ Type : GELF UDP
→ Titre : "GELF Applications"
→ Port : 12201
```

### 9.3 Envoi des logs depuis les serveurs

```bash
# Sur chaque serveur à superviser
sudo apt install rsyslog -y
sudo nano /etc/rsyslog.d/99-graylog.conf
```

```
*.* @192.168.1.200:1514;RSYSLOG_SyslogProtocol23Format
```

```bash
sudo systemctl restart rsyslog
```

### 9.4 Alertes recommandées dans Graylog

| Alerte | Filtre | Condition |
|---|---|---|
| Brute force SSH | `"Failed password"` | > 5 en 5 min |
| Erreurs critiques | `level:0 OR level:1 OR level:2` | Immédiat |
| Connexion root | `"session opened for user root"` | Immédiat |
| Service en échec | `"systemd" AND "failed"` | Immédiat |

---

## 10. Alertes et notifications

### 10.1 Configuration email (Postfix)

```bash
sudo apt install postfix mailutils -y
sudo nano /etc/postfix/main.cf
```

```ini
myhostname = supervision.entreprise.fr
relayhost = [smtp.entreprise.fr]:587
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_security_level = encrypt
```

```bash
sudo nano /etc/postfix/sasl_passwd
# [smtp.entreprise.fr]:587 utilisateur@entreprise.fr:motdepasse

sudo postmap /etc/postfix/sasl_passwd
sudo chmod 600 /etc/postfix/sasl_passwd
sudo systemctl restart postfix

# Test
echo "Test supervision" | mail -s "Test alerte" admin@entreprise.fr
```

### 10.2 Alertes Telegram

```bash
sudo nano /usr/local/bin/alerte_telegram.sh
```

```bash
#!/bin/bash
TOKEN="VOTRE_TOKEN_BOT"
CHAT_ID="VOTRE_CHAT_ID"

curl -s -X POST \
    "https://api.telegram.org/bot$TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="ALERTE SUPERVISION
Serveur : $(hostname)
Date : $(date)
Message : $1" \
    -d parse_mode="HTML"
```

```bash
sudo chmod +x /usr/local/bin/alerte_telegram.sh

# Test
/usr/local/bin/alerte_telegram.sh "Test de notification"
```

> **Astuce.** Créer un bot Telegram : ouvrir `@BotFather` → `/newbot` → récupérer le TOKEN. Récupérer votre Chat ID via `@userinfobot`.

### 10.3 Seuils d'alerte recommandés

| Métrique | Attention | Critique | Urgence |
|---|---|---|---|
| CPU | > 70 % | > 85 % | > 95 % |
| RAM | > 75 % | > 90 % | > 95 % |
| Disque | > 70 % | > 85 % | > 95 % |
| Charge système | > nb_cpu | > 2× nb_cpu | > 4× nb_cpu |
| Ping | > 100 ms | > 500 ms | Timeout |
| Perte paquets | > 1 % | > 5 % | > 20 % |
| Bande passante | > 70 % | > 85 % | > 95 % |
| Virus détectés | 1 | 5 | 10+ |
| Erreurs SSH | > 5/5 min | > 20/5 min | > 50/5 min |

---

## 11. Tableaux de bord et rapports

### 11.1 Dashboard Grafana — Vue d'ensemble SI

| Panneau | Métrique Zabbix |
|---|---|
| État des serveurs | `Hosts → Status` |
| CPU moyen | `Items → system.cpu.util` |
| RAM utilisée | `Items → vm.memory.utilization` |
| Espace disque | `Items → vfs.fs.size[/,pused]` |
| Trafic réseau | `Items → net.if.in/out` |
| Dernières alertes | `Triggers → Recent problems` |

### 11.2 Script de rapport hebdomadaire

```bash
sudo nano /usr/local/bin/rapport_hebdomadaire.sh
```

```bash
#!/bin/bash
RAPPORT="/tmp/rapport_$(date +%Y%m%d).txt"
EMAIL="direction@entreprise.fr"

cat > $RAPPORT << EOF
========================================
RAPPORT DE SUPERVISION HEBDOMADAIRE
Période : $(date -d '7 days ago' +%d/%m/%Y) - $(date +%d/%m/%Y)
Généré le : $(date)
========================================

1. ESPACE DISQUE
$(df -h | grep -v tmpfs)

2. CHARGE SYSTÈME
$(uptime)

3. MISES À JOUR DISPONIBLES
$(apt list --upgradable 2>/dev/null | wc -l) mises à jour disponibles

4. DERNIERS SCANS ANTIVIRUS
$(grep "Infected files:" /var/log/clamav/scan_*.log 2>/dev/null | tail -7)

5. TENTATIVES DE CONNEXION SUSPECTES
$(grep "Failed password" /var/log/auth.log 2>/dev/null | wc -l) tentatives échouées

6. SERVICES EN ERREUR
$(systemctl --failed --no-legend 2>/dev/null)

========================================
Pour plus de détails : http://192.168.1.200:3000
========================================
EOF

mail -s "Rapport Supervision - $(date +%d/%m/%Y)" $EMAIL < $RAPPORT
echo "Rapport envoyé à $EMAIL"
```

```bash
sudo chmod +x /usr/local/bin/rapport_hebdomadaire.sh
# Planifier : 0 8 * * 1 /usr/local/bin/rapport_hebdomadaire.sh
```

---

## 12. Maintenance et bonnes pratiques

### 12.1 Script de vérification quotidienne

```bash
sudo nano /usr/local/bin/check_supervision.sh
```

```bash
#!/bin/bash
echo "=== VÉRIFICATION SUPERVISION - $(date) ==="

check_service() {
    if systemctl is-active --quiet $1; then
        echo "OK    $1"
    else
        echo "ARRÊT $1 → Tentative de redémarrage..."
        systemctl start $1
    fi
}

echo "--- Services locaux ---"
for svc in zabbix-server zabbix-agent apache2 grafana-server \
           clamav-daemon clamav-freshclam rsyslog; do
    check_service $svc
done

echo "--- Conteneurs Docker ---"
for container in librenms_app graylog_app; do
    if docker ps | grep -q $container; then
        echo "OK    $container"
    else
        echo "ARRÊT $container"
        cd /opt/$(echo $container | cut -d_ -f1) && docker compose up -d
    fi
done

echo "--- Espace disque ---"
df -h | grep -v tmpfs | awk 'NR>1 {
    gsub(/%/,"",$5)
    if ($5 > 85) print "ATTENTION " $0
    else print "OK    " $0
}'

echo "--- Connectivité réseau ---"
for host in 192.168.1.1 8.8.8.8; do
    ping -c 1 -W 2 $host &>/dev/null \
        && echo "OK    $host accessible" \
        || echo "KO    $host INACCESSIBLE"
done

echo "=== Vérification terminée ==="
```

```bash
sudo chmod +x /usr/local/bin/check_supervision.sh
# Planifier : 0 7 * * * /usr/local/bin/check_supervision.sh
```

### 12.2 Sauvegarde des configurations

```bash
sudo nano /usr/local/bin/backup_supervision.sh
```

```bash
#!/bin/bash
BACKUP_DIR="/backup/supervision/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Zabbix
cp -r /etc/zabbix/ $BACKUP_DIR/zabbix/
mysqldump -u zabbix -pMotDePasseZabbix123! zabbix | \
    gzip > $BACKUP_DIR/zabbix_db.sql.gz

# Grafana
cp -r /etc/grafana/ $BACKUP_DIR/grafana/
cp -r /var/lib/grafana/ $BACKUP_DIR/grafana_data/

# ClamAV
cp -r /etc/clamav/ $BACKUP_DIR/clamav/

# Docker Compose
cp /opt/librenms/docker-compose.yml $BACKUP_DIR/librenms-compose.yml
cp /opt/graylog/docker-compose.yml $BACKUP_DIR/graylog-compose.yml

# Compression finale
tar -czf /backup/supervision_$(date +%Y%m%d).tar.gz $BACKUP_DIR/
rm -rf $BACKUP_DIR

echo "Sauvegarde : /backup/supervision_$(date +%Y%m%d).tar.gz"
```

```bash
sudo chmod +x /usr/local/bin/backup_supervision.sh
# Planifier : 0 3 * * 0 /usr/local/bin/backup_supervision.sh
```

### 12.3 Checklist de maintenance mensuelle

- [ ] Mettre à jour Zabbix : `sudo apt update && sudo apt upgrade zabbix-server`
- [ ] Mettre à jour les conteneurs Docker : `docker compose pull && docker compose up -d`
- [ ] Vérifier les signatures ClamAV : `sigtool --info /var/lib/clamav/main.cvd`
- [ ] Contrôler l'espace disque des logs : `du -sh /var/log/ /var/lib/mysql/`
- [ ] Réviser les alertes Zabbix (faux positifs, seuils)
- [ ] Vérifier les rapports de scan antivirus
- [ ] Tester les notifications (déclencher une alerte test)
- [ ] Réviser les accès utilisateurs (supprimer les comptes inactifs)
- [ ] Vérifier et tester les sauvegardes
- [ ] Documenter les incidents du mois

---

## Annexe A — Récapitulatif des accès

| Outil | URL | Login par défaut |
|---|---|---|
| Zabbix | `http://IP/zabbix` | `Admin` / `zabbix` |
| Grafana | `http://IP:3000` | `admin` / `admin` |
| LibreNMS | `http://IP:8080` | `admin` / `admin` |
| Graylog | `http://IP:9000` | `admin` / `[défini]` |
| Netdata | `http://IP:19999` | Pas d'authentification |

> **Important.** Changer TOUS les mots de passe par défaut immédiatement.

## Annexe B — Ports utilisés

| Port | Proto | Usage |
|---|---|---|
| 80 | TCP | Zabbix Web |
| 3000 | TCP | Grafana |
| 8080 | TCP | LibreNMS |
| 9000 | TCP | Graylog Web |
| 19999 | TCP | Netdata |
| 10050 | TCP | Zabbix Agent |
| 10051 | TCP | Zabbix Server |
| 161 | UDP | SNMP |
| 162 | UDP | SNMP Traps |
| 1514 | TCP/UDP | Syslog → Graylog |
| 12201 | TCP/UDP | GELF → Graylog |

## Annexe C — Commandes de diagnostic rapide

```bash
# État général du serveur
htop                                          # CPU/RAM temps réel
df -h                                         # Espace disque
free -h                                       # Mémoire
uptime                                        # Charge système

# Services de supervision
sudo systemctl status zabbix-server
sudo systemctl status grafana-server
sudo systemctl status clamav-daemon
docker ps                                     # Conteneurs actifs

# Logs en temps réel
sudo journalctl -f
sudo tail -f /var/log/zabbix/zabbix_server.log
sudo tail -f /var/log/clamav/clamav.log

# Réseau
ss -tulpn                                     # Ports ouverts
ip addr show                                  # Interfaces réseau
ping -c 4 192.168.1.1                         # Test connectivité

# Antivirus
sudo clamscan -r /home --infected             # Scan rapide

# Sécurité
sudo grep "Failed password" /var/log/auth.log | tail -20
sudo grep "Invalid user" /var/log/auth.log | tail -20
```

## Annexe D — Ressources utiles

| Ressource | URL |
|---|---|
| Zabbix Documentation | https://www.zabbix.com/documentation |
| Grafana Documentation | https://grafana.com/docs |
| LibreNMS Documentation | https://docs.librenms.org |
| ClamAV Documentation | https://docs.clamav.net |
| Graylog Documentation | https://docs.graylog.org |
| Netdata Documentation | https://learn.netdata.cloud |
| Docker Documentation | https://docs.docker.com |

---

## Notes importantes pour les débutants

> **Commencer petit.** Installer d'abord Zabbix + Grafana, puis ajouter les autres outils progressivement.

> **Tester en lab.** Valider la configuration sur une VM avant la production.

> **Documenter.** Noter chaque modification effectuée.

> **Sauvegarder.** Toujours sauvegarder avant une modification.

> **Surveiller les alertes.** Une supervision non surveillée ne sert à rien.

---

*Document interne — Société Tchadienne des Eaux. Supervision du Système d'Information Linux x86. Diffusion restreinte.*
*Version 1.0 — basé sur la stack Zabbix / Grafana / LibreNMS / ClamAV / Graylog / Netdata.*
