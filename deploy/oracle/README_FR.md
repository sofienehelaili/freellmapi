# FreeLLMAPI sur une instance Oracle Cloud Always Free ARM64 existante

> Statut au 7 novembre 2026 : **préparation terminée, installation bloquée par manque d'espace**. Le contrôle distant sur le runner `oracle-free-arm64` a constaté environ **254 Mio libres sur un système de fichiers racine de 45 Gio**, tandis que Docker et huit conteneurs d'autres projets sont en cours d'exécution. Aucune donnée n'a été supprimée.

## Architecture et limitations

- Projet source : `sofienehelaili/freellmapi`
- Cible : machine Oracle **existante**, Ubuntu ARM64/Ampere A1, accessible via le runner GitHub privé du dépôt `sofienehelaili/helaili-visco-homog`
- Déploiement : image officielle `ghcr.io/tashfeenahmed/freellmapi:latest` avec Docker Compose
- Projet Compose indépendant : `helaili-freellmapi`
- Accès HTTP : **127.0.0.1:3001 seulement**, pas de nouvelle règle VCN/pare-feu, aucun port Internet ouvert
- Données : volume Docker local persistant dans le disque existant, clé de chiffrement privée dans `deploy/oracle/.env` (ignorée par Git)
- Aucun provisionnement OCI, aucun nouveau volume OCI, aucune ressource payante
- Les tarifs et l'éligibilité effective Always Free du compte OCI restent à confirmer dans la console OCI

## Procédure de déploiement préparée

1. Maintenir les conteneurs existants actifs et réaliser un audit de stockage.
2. Libérer **au moins 3 Gio** sur `/`, uniquement après accord sur les fichiers à supprimer.
3. Dans le dépôt **privé** `sofienehelaili/helaili-visco-homog`, branche `deploy/freellmapi-oci`, créer ou modifier le fichier `cloud/oracle/freellmapi.deploy.trigger`.
4. Le workflow `.github/workflows/oci-freellmapi-deploy.yml` vérifiera l'espace libre, clonera cette branche `setup/oracle-free-arm64` à la révision épinglée et exécutera `deploy/oracle/install.sh`.
5. Vérifier l'issue du workflow et une réponse HTTP 200 sur `http://127.0.0.1:3001/api/ping` **depuis l'instance**.
6. Dans le tableau de bord FreeLLMAPI, ajouter les clés fournisseurs volontairement, **jamais dans GitHub**.

Aucune action programmée ne déclenche la procédure d'installation toute seule. Aucun nettoyage ni désinstallation automatique des autres projets.

## Commandes manuelles depuis la VM (après libération de disque)

```bash
git clone --depth 1 --branch setup/oracle-free-arm64 https://github.com/sofienehelaili/freellmapi.git ~/apps/freellmapi-oci
cd ~/apps/freellmapi-oci
git checkout --detach 232bef2ee200e8ebfab2c6ef9603aa0e5139617e
bash deploy/oracle/install.sh
```

## Accès privé depuis un PC distant

Une fois le serveur opérationnel, créer un tunnel SSH sécurisé depuis son PC (avec sa propre clé SSH). La connexion est uniquement possible avec les paramètres SSH de l'utilisateur et une adresse publique valide.

```bash
ssh -i /chemin/vers/cle-privee -N -L 3001:127.0.0.1:3001 ubuntu@ADRESSE_IP_ORACLE
```

Ouvrir ensuite `http://127.0.0.1:3001` sur le PC. Ne jamais exposer le port 3001 publiquement pour éviter de publier les interfaces administratives et clés API.

## Diagnostics non destructifs

```bash
df -h /
sudo docker system df
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'
ss -ltn | grep ':3001' || true
```

Référence officielle : [installation FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi/blob/main/docs/en/install/01-install.md).
