# README (MECHA MSPR) — Stack + Démo

## 1) Prérequis

* **Docker Desktop** installé + lancé
* **Docker Compose** (inclus avec Docker Desktop)
* **PowerShell** (Windows) pour exécuter `run_demo.ps1`

> Si Docker Desktop n’est pas démarré, `docker compose` ne pourra pas lancer la stack.

---

## 2) Démarrage rapide (recommandé)

Le plus simple pour remettre le projet “dans l’état démo” (données + KPI + télémétrie) :

```powershell
cd stack
.\run_demo.ps1
```

Ce script :

* démarre la stack (`docker compose up -d`)
* charge les **événements Postgres** (Phase 6.2)
* (re)crée les **vues KPI** (Phase 7)
* injecte de la **télémétrie dans InfluxDB via MQTT → Telegraf** (pour que Grafana n’affiche pas “0 series”)
* lance des **smoke tests** (Postgres + Influx)

✅ Après ça, Grafana doit afficher des données immédiatement.

---

## 3) Accès aux services

### Grafana (Dashboards)

* URL : `http://localhost:3000`
* Identifiants :

  * **User** : `admin`
  * **Password** : `admin`

### InfluxDB (télémétrie)

* URL : `http://localhost:8086`
* Identifiants :

  * **User** : `admin`
  * **Password** : `adminadminadmin`
* Organisation : `mecha`
* Bucket : `telemetry`

### PostgreSQL (événements)

* Host : `localhost`
* Port : `5432`
* DB : `mecha`
* User : `mecha`
* Password : `mecha`

---

## 4) Commandes utiles (selon ton besoin)

### A) Reprendre le projet (sans perdre les données)

Si tu as simplement arrêté la stack, tu peux relancer sans tout regénérer :

```powershell
cd stack
docker compose up -d
```

💡 Si tu veux revenir en “état démo” complet (avec données garanties), fais plutôt :

```powershell
.\run_demo.ps1
```

### B) Pause / reprise (meilleure pratique)

Pour mettre en pause sans rien effacer :

```powershell
docker compose stop
```

Puis pour reprendre :

```powershell
docker compose start
```

### C) Stop normal (garde les données)

```powershell
docker compose down
```

> Les volumes (données Postgres/Influx/Grafana) sont conservés.

### D) Reset complet (efface TOUT, puis reconstruit)

À utiliser uniquement si on a modifié les scripts d’init ou si on veut repartir propre :

```powershell
.\run_demo.ps1 -ResetVolumes
```

Ou manuellement :

```powershell
docker compose down -v
docker compose up -d
.\run_demo.ps1
```

> ⚠️ `down -v` supprime les volumes → données effacées → sans `run_demo.ps1`, Grafana affichera “0 series”.

---

## 5) Vérifications rapides (si quelque chose semble vide)

### Vérif Postgres (events)

```powershell
docker compose exec -T postgres psql -U mecha -d mecha -c "SELECT COUNT(*) FROM production_events;"
```

### Vérif Influx (télémétrie)

```powershell
$q = @'
from(bucket:"telemetry")
  |> range(start: -6h)
  |> filter(fn:(r)=> r._measurement == "telemetry" and r._field == "power_kw")
  |> limit(n: 5)
'@
$q | docker compose exec -T influxdb influx query --org mecha --token mecha-super-token -
```

Si Influx renvoie 0 lignes → relancer `.\run_demo.ps1` (ou vérifier Telegraf/MQTT).

---

## 6) Notes importantes (évite les pièges)

* **Si tu fais `docker compose down -v`**, tu effaces les données → il faut relancer `.\run_demo.ps1` pour recharger events + KPI + télémétrie.
* Le KPI “énergie” (kWh/jour) dépend des points `power_kw` dans Influx.
  `run_demo.ps1` injecte de la télémétrie pour éviter le “0 series returned”.