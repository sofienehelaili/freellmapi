# Installation de FreeLLMAPI sur Windows (configuration locale)

Ce guide concerne le fork [sofienehelaili/freellmapi](https://github.com/sofienehelaili/freellmapi). Le code est heberge sur GitHub; **le service ne fonctionne pas sur GitHub lui-meme**. Il doit tourner sur un PC ou sur un serveur allume.

## Prerequis

- Windows 10/11 avec PowerShell et Git;
- Docker Desktop installe, demarre et configure pour les conteneurs Linux;
- une connexion Internet pour recuperer l'image Docker;
- des cles API de fournisseurs de modeles, ajoutees ulterieurement dans l'interface locale.

Aucun abonnement cloud payant n'est provisionne par cette procedure. Attention, certains fournisseurs de modeles peuvent facturer les requetes selon les cles et offres choisies.

## Installation sur le PC

Ouvrir PowerShell et executer:

```powershell
git clone https://github.com/sofienehelaili/freellmapi.git
cd freellmapi
git fetch origin setup/windows-local-install
git switch --track origin/setup/windows-local-install
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\install-windows-local.ps1
```

La procedure :

1. verifie Docker Desktop et Docker Compose;
2. cree `.env` avec une cle de chiffrement aleatoire 256 bits si absent, sans ecraser une configuration existante;
3. telecharge l'image Docker officielle `ghcr.io/tashfeenahmed/freellmapi:latest`;
4. demarre uniquement le service `freellmapi` sur `127.0.0.1:3001`;
5. teste `/api/ping` et affiche les informations de diagnostic en cas d'echec.

Une fois la verification reussie, ouvrir **http://127.0.0.1:3001** puis ajouter ses propres cles de fournisseurs depuis la page Keys. Recuperer ensuite la cle API unifiee.

## Diagnostics et maintenance

Depuis le dossier `freellmapi` :

```powershell
docker compose ps
docker compose logs --tail=100 freellmapi
```

Pour arreter le service sans supprimer la base:

```powershell
docker compose down
```

Pour mettre a jour l'image, sans modifier le fichier `.env` et sans supprimer les volumes:

```powershell
docker compose pull freellmapi
docker compose up -d --no-build freellmapi
```

**Ne pas executer** `docker compose down -v` si vous souhaitez conserver votre base de donnees et vos cles.

## Securite et limites

- `.env` est ignore par Git. Ne jamais ajouter ce fichier, des tokens ou des cles API aux commits.
- Le script force une exposition exclusivement locale sur `127.0.0.1:3001`. Il n'ouvre pas de port public.
- Conserver une sauvegarde coherente du volume Docker et de la cle de chiffrement `.env`. Sans la meme cle, les secrets stockes ne pourront pas etre dechiffres.
- GitHub Actions, Pages ou le fork GitHub **ne constituent pas** un hebergement permanent pour cette application Node.js/SQLite.
- Cette installation n'a pas ete executee ni testee sur le PC de destination. L'utilisateur doit lancer la commande sur un ordinateur avec Docker Desktop demarre.
- Pour une installation Windows sans Docker, utiliser l'installateur de bureau de la [derniere version publiee par l'auteur](https://github.com/tashfeenahmed/freellmapi/releases/latest).

## Documentation source

[Guide officiel d'installation et de deploiement](https://github.com/tashfeenahmed/freellmapi/blob/main/docs/en/install/01-install.md).
