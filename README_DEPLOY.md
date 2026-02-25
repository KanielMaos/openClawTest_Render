# Déploiement OpenClaw sur VPS Ubuntu 22.04

## Pré-requis
- VM publique (≥4 vCPU, ≥8 Go RAM, ≥80 Go SSD) avec Ubuntu 22.04 LTS et IP statique.
- Nom de domaine pointant vers l’IP.
- Clé SSH publique disponible localement.

## 1. Connexion root
```bash
ssh root@IP
```

## 2. Hardening + dépendances
Définissez les variables puis exécutez le script.
```bash
export ADMIN_USER=openc
export ADMIN_SSH_KEY="ssh-ed25519 AAAA... votre_cle_publique"
export DOMAIN=votre-domaine.tld
export ADMIN_EMAIL=you@example.com
export SSH_PORT=22   # optionnel
sudo bash scripts/install.sh
```
Ce script :
- crée l’utilisateur non-root sudoer, désactive le login root + password;
- active UFW (ports 22/80/443), installe Fail2ban;
- installe Docker + Compose, Node 20.x, Python 3.11, Nginx, Certbot;
- crée 2 Go de swap;
- configure Nginx + Let’s Encrypt si `DOMAIN` + `ADMIN_EMAIL` fournis.

## 3. Déployer OpenClaw
Copiez ce dépôt sur le serveur (scp ou git clone), puis:
```bash
ssh -p $SSH_PORT ${ADMIN_USER}@${DOMAIN}
cd /path/to/OPENCLOW
sudo bash scripts/deploy_openclaw.sh
```
Ensuite éditez `/opt/openclaw/.env` avec vos clés API (OpenAI/Claude, etc.) puis relancez:
```bash
cd /opt/openclaw
sudo docker compose up -d
```

## 4. TLS
Si Certbot n’a pas pu obtenir le certificat (DNS non prêt), relancez quand le domaine pointe vers l’IP:
```bash
sudo certbot --nginx -d $DOMAIN -m $ADMIN_EMAIL --agree-tos --non-interactive
sudo systemctl reload nginx
```

## 5. Monitoring
Netdata est lancé via `docker-compose.yml` (port 19999). Restreignez l’accès avec votre pare-feu ou un tunnel SSH:
```bash
ssh -L 19999:localhost:19999 -p $SSH_PORT ${ADMIN_USER}@${DOMAIN}
# puis naviguez http://localhost:19999
```

## 6. Sauvegardes
Un cron `/etc/cron.d/openclaw-backup` exécute chaque nuit:
```bash
/usr/local/bin/openclaw-backup.sh
```
Les archives sont dans `/var/backups/openclaw/`. Branchez un stockage distant via `rclone` si souhaité (voir commentaire dans le script).

## 7. Logs & redémarrage
- Journaux applicatifs: `docker compose logs -f openclaw`
- Journaux Nginx: `/var/log/nginx/`
- Politique de redémarrage `restart: always` (crash -> relance).

## 8. Mise à jour
```bash
cd /opt/openclaw
git pull
sudo docker compose build --pull
sudo docker compose up -d
```

## 9. Scalabilité
- Prévu pour un futur load balancer (Nginx/HAProxy en frontal). L’application écoute en HTTP interne sur 3000.
- Déplacez la persistance (`./data`) vers un disque ou un bucket réseau partagé pour un cluster.
- Base PostgreSQL externe : renseignez la chaîne de connexion dans `.env` puis exposez la DB via un VPC ou une IP privée.

## 10. Tests rapides
```bash
curl -I https://$DOMAIN
curl http://localhost:3000/health    # depuis le serveur
```

## Déploiement sur Render.com (option PaaS)
1) Forkez ce repo et connectez-le à Render.  
2) Dans Render, "New + Blueprint" puis fournissez `render.yaml`.  
3) Ajoutez vos variables d’environnement dans le dashboard Render (OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.).  
4) Render créera un disque persistant 10 Go monté sur `/var/lib/openclaw`.  
5) Build & deploy se font automatiquement; l’app écoute sur le port fourni par Render (`$PORT`).  
6) Ajoutez un custom domain dans Render si souhaité, TLS est géré par Render.
