# README

## Prérequis

* **Docker** et **Docker Compose** installés sur votre machine.

## Démarrage du projet

1. Placez-vous dans le dossier **stack** :

```bash
cd stack
```

2. Lancez les services avec Docker Compose :

```bash
docker compose up -d
```

Cela démarre l’ensemble de la stack en arrière-plan (mode détaché).

## Accès aux services

### Grafana

* URL : `http://localhost:3000/login`
* Identifiants :

  * **Utilisateur** : `admin`
  * **Mot de passe** : `admin`

### InfluxDB

* URL : `http://localhost:8086/login`
* Identifiants :

  * **Utilisateur** : `admin`
  * **Mot de passe** : `adminadminadmin`

## Arrêter la stack

Pour arrêter les services :

```bash
docker compose down
```
