# Plan controle : extension du boot volume OCI de 50 a 100 Go, sans depense

Date de preparation : 7 novembre 2026.

**STATUT : PREPARE, NON EXECUTE. LE QUOTA RESTANT N'A PAS PU ETRE CERTIFIE.**

## Elements verifies sur l'instance Oracle existante

- Region de l'instance : `eu-marseille-1`.
- Region d'origine de la location : **`eu-marseille-1`, confirmee par `IdentityClient.list_region_subscriptions`** via identite d'instance.
- Instance : `VM.Standard.A1.Flex`, architecture ARM64.
- Disque systeme Linux `/dev/sda` : **50 010 783 744 octets**, environ 50 Go provisionnes.
- Racine `/dev/sda1` : ext4, environ 45 Gio utilises, seulement ~254 Mio disponibles.
- Partition EFI `/dev/sda15` : debute au secteur 2048 ; partition racine `/dev/sda1` : debute au secteur 206848. L'EFI se trouve **avant** la racine; aucune partition situee apres la racine dans le diagnostic.
- Outils `growpart` et `resize2fs` presents.
- Aucun redimensionnement OCI, aucune nouvelle ressource, aucune suppression, aucune extension Linux effectues.

## Ce qui reste IMPERATIVEMENT a verifier

Oracle Always Free offre **200 Go de stockage de boot volumes + block volumes au total, dans la region d'origine**, pas 200 Go par VM. Une extension de 50 vers 100 Go ajoute environ 50 Go a l'usage provisionne.

Les requetes de quota et d'inventaire faites depuis l'instance via son principal OCI ont retourne HTTP 404 pour `limits`, `compute boot-volume-attachment` et `bv`. Ceci ne permet PAS de conclure sur le volume restant : une politique IAM insuffisante peut masquer des ressources.

La condition arithmetique theorique est :

`total actuel de stockage Boot + Block Volume dans toute la location et la region d'origine + 50 Go <= 200 Go`.

Il faut aussi verifier que tous les volumes sont eligibles Always Free, que l'operation dans la console OCI n'annonce aucun cout, et que la sauvegarde est possible **sans frais**. Oracle inclut jusqu'a cinq sauvegardes de volume Always Free; ne pas en creer davantage sans verifier la facturation.

## Etape 1 : audit complet depuis Oracle Cloud Shell

Ouvrir Oracle Cloud Console, choisir `eu-marseille-1`, puis ouvrir **Cloud Shell**, avec l'utilisateur autorise a consulter la liste des volumes de la location.

```bash
curl -fL https://raw.githubusercontent.com/sofienehelaili/freellmapi/setup/oracle-free-arm64/deploy/oracle/audit_always_free_quota.py -o audit_always_free_quota.py
# Inspecter le fichier avant execution
less audit_always_free_quota.py
python3 audit_always_free_quota.py
```

Le script est en lecture seule. Il utilise l'OCI CLI pre-authentifie du Cloud Shell et n'affiche ni OCID ni secret. Il tente de lire les regions, domaines de disponibilite, limites, compartiments visibles et volumes provisionnes. Les compartiments caches par IAM peuvent rendre le total **incomplet** : ne pas conclure sur les seuls volumes visibles si cette visibilite n'est pas totale.

Si le fichier de configuration Cloud Shell ne permet pas de lire l'OCID de la location, definir localement `TENANCY_OCID` avant l'execution, **sans l'ajouter a GitHub**.

## Etape 2 : confirmation du volume cible, sauvegarde et absence de cout

1. Dans la console OCI : Compute > Instances > instance A1 en fonctionnement > **Boot Volume**. Verifier **taille OCI exacte 50 Go**, OCID du volume et etat AVAILABLE.
2. Dans Storage > Block Volumes et Boot Volumes : inspecter tous les compartiments accessibles. Verifier qu'au moins 50 Go du quota Always Free restent libres.
3. Verifier dans la rubrique de facturation et dans le formulaire de modification de volume que la future taille **100 Go** reste eligible Always Free et ne cree **aucune facturation**.
4. Sauvegarder les donnees irremplacables et verifier le quota des cinq sauvegardes Always Free avant une eventuelle sauvegarde du boot volume. Une sauvegarde n'est pas automatiquement gratuite si le quota est deja utilise.
5. L'extension d'un boot volume est ascendante : on ne peut pas simplement reduire ensuite de 100 a 50 Go. Ne pas proceder sur une base incomplete.

## Etape 3 : modification OCI (NE PAS EXECUTER avant validation)

Dans Oracle Console, sur **le boot volume de l'instance verifiee**, choisir Edit / Modifier puis fixer `Volume size = 100 GB`.

La commande OCI equivalente ci-dessous est DONNEE COMME REFERENCE UNIQUEMENT, sans identifiant ni execution :

```bash
# NE PAS EXECUTER sans confirmation de la gratuité, sauvegarde et OCID exact
# oci bv boot-volume update --boot-volume-id "<OCID_DU_BOOT_VOLUME>" --size-in-gbs 100 --region eu-marseille-1
```

Attendre que le volume atteigne l'etat AVAILABLE et que la machine detecte le nouveau disque, sans debrancher ni supprimer de volume.

## Etape 4 : extension Linux (uniquement une fois les 100 Go presents)

Sur la VM via SSH / workflow prive, lancer d'abord le **dry-run** :

```bash
bash deploy/oracle/check_boot_resize_readiness.sh
```

Le script verifie l'architecture, `/dev/sda1`, le systeme ext4, la taille du disque et le fait que l'EFI soit avant la racine. Il execute seulement `growpart -N` et n'apporte aucun changement.

Apres validation explicite par un operateur qualifie, et seulement si les hypotheses precedentess sont confirmees :

```bash
sudo growpart /dev/sda 1
sudo resize2fs /dev/sda1
lsblk -f
df -h /
```

Ces deux premieres commandes **modifient le partitionnement et le systeme de fichiers**. Elles ne sont pas executees par le kit de preparation.

## Etape 5 : controles de sortie

- Racine ext4 montee sans erreur; `df -h /` montre l'espace supplementaire (~93 Gio de disque pour 100 Go decimaux, moins les partitions/metadonnees).
- Les huit conteneurs existants restent disponibles; tests des ports locaux existants.
- Pas de nouvelle instance ni volume OCI; pas de transfert hors de l'offre Always Free.
- Installation FreeLLMAPI seulement apres verification et si au moins 3 Gio sont disponibles.

## Sources Oracle

- [Always Free Resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Online Resizing a Block or Boot Volume](https://docs.oracle.com/en-us/iaas/Content/Block/Tasks/update-online-resize-block-boot-volume.htm)
- [Cloud Shell](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cloudshellintro.htm)
