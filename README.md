# Nextcloud Sync (nextcloudcmd) als Docker-Container

Minimaler Debian-Container, der mit `nextcloudcmd` ein lokales
Verzeichnis gegen eine Nextcloud-Instanz synchronisiert -- inkl.
Intervall-Sync, Exclude-/Unsynced-Listen und flexiblem UID/GID-Mapping
(Root + Rootless).

**Image:** `ghcr.io/begauns/nextcloud-sync:latest`

------------------------------------------------------------------------

## Image verwenden

1.  Datenverzeichnis auf dem Host anlegen, z.B.:

``` bash
mkdir -p /pfad/zu/deinen/daten
```

`docker-compose.example.yml` nach `docker-compose.yml` kopieren und
anpassen:

``` bash
cp docker-compose.example.yml docker-compose.yml
nano docker-compose.yml
```

Container starten:

``` bash
docker compose up -d
docker compose logs -f
```

------------------------------------------------------------------------

## Pflicht-Variablen (Sync-Parameter)

Diese Variablen sind für jeden Sync notwendig:

### NC_URL

Basis-URL deiner Nextcloud (ohne `/remote.php/dav/...`).\
Beispiel: `https://cloud.example.com`

### NC_USER

Nextcloud-Benutzername, der für den Login verwendet wird.

### NC_PASS

Nextcloud-Passwort zu `NC_USER`.

### NC_SOURCE_DIR

Lokales Sync-Verzeichnis im Container.\
Standard im Compose: `/media/nextcloud`, wird auf ein Host-Verzeichnis
gemountet.

Beispiel:

``` yaml
environment:
  NC_URL: "https://cloud.example.com"
  NC_USER: "your-nextcloud-user"
  NC_PASS: "your-nextcloud-password"
  NC_SOURCE_DIR: "/media/nextcloud"
```

------------------------------------------------------------------------

## Optionale CLI-Flags (nextcloudcmd)

Diese Variablen steuern 1:1 die CLI-Optionen von `nextcloudcmd`:

### NC_PATH

Entspricht `--path`.\
Setzt den entfernten Unterpfad, z.B.
`/remote.php/dav/files/USER/Documents`.

### NC_NON_INTERACTIVE

`1` → `--non-interactive` aktiv (keine Prompts, liest ausschließlich
ENV).\
Alles andere = inaktiv.

### NC_SILENT

`false` → verbose Logs.\
Jeder andere nicht-leere Wert → `--silent`.

### NC_TRUST_CERT

`false` → Standard-Zertifikatsprüfung.\
Jeder andere nicht-leere Wert → `--trust` (unsichere Zertifikate
akzeptieren).

### NC_HIDDEN

`false` → versteckte Dateien werden ignoriert.\
Jeder andere nicht-leere Wert → `-h` (hidden files syncen).

### NC_EXCLUDE_FILE

Entspricht `--exclude <file>`.\
Pfad zu einer Datei mit Exclude-Mustern (z.B. `/config/exclude.lst`).

### NC_UNSYNCED_FILE

Entspricht `--unsyncedfolders <file>`.\
Pfad zu einer Datei mit Verzeichnissen, die nicht synchronisiert werden
sollen.

### NC_HTTPPROXY

Entspricht `--httpproxy http://user:pass@host:port`.

### NC_MAX_SYNC_RETRIES

Entspricht `--max-sync-retries <n>`.

Beispiel:

``` yaml
environment:
  NC_PATH: ""
  NC_NON_INTERACTIVE: "1"
  NC_SILENT: "false"
  NC_TRUST_CERT: "false"
  NC_HIDDEN: "false"
  NC_MAX_SYNC_RETRIES: "5"
  NC_EXCLUDE_FILE: "/config/exclude.lst"
  NC_UNSYNCED_FILE: "/config/unsynced.lst"
  NC_HTTPPROXY: ""
```

------------------------------------------------------------------------

## CRON-Loop + User-Mapping

### Intervall-Sync (Cron-Loop)

**NC_INTERVAL**\
Anzahl Sekunden zwischen zwei Sync-Durchläufen.\
Beispiel: `300` (alle 5 Minuten).

**NC_EXIT**\
`"false"` (oder leer) → Endlosschleife.\
`"true"` → Container beendet sich nach einem Sync.

Beispiel:

``` yaml
environment:
  NC_INTERVAL: "300"
  NC_EXIT: "false"
```

------------------------------------------------------------------------

## USER-Mapping (Root + Rootless)

Der Container unterstützt zwei Modi:

### 1. Root-Modus (z.B. OMV / klassisches Docker)

Container-Prozess läuft als root (`id -u == 0`).

`entrypoint.sh` erwartet:

**USER_UID**\
Ziel-UID, die Dateien im Sync-Ordner besitzen soll (Host-UID).

**USER_GID**\
Ziel-GID (z.B. `users`).

Ablauf:

-   `chown -R USER_UID:USER_GID /media/nextcloud`
-   Im Container wird (falls nötig) ein User mit dieser UID/GID angelegt
-   `nextcloudcmd` läuft als dieser User

Beispiel:

``` yaml
environment:
  USER_UID: "1000"
  USER_GID: "1000"
```

**Wichtig:** In diesem Modus kein `user:` im Compose setzen, damit der
Container als root starten kann.

------------------------------------------------------------------------

### 2. Rootless-Modus

Container läuft nicht als root (`id -u != 0`) -- z.B. rootless Docker
oder Podman.

`entrypoint.sh`:

-   führt **kein** `chown` aus
-   legt **keine** Nutzer an
-   startet `nextcloudcmd` direkt mit der vorhandenen UID

Voraussetzung:

Das gemountete Host-Verzeichnis muss bereits dem Engine-User gehören.

``` bash
mkdir -p /pfad/zu/deinen/daten
chown -R $(id -u):$(id -g) /pfad/zu/deinen/daten
```

Im Compose kannst du optional `user:` setzen:

``` yaml
services:
  nextcloud-sync:
    image: ghcr.io/begauns/nextcloud-sync:latest
    user: "${UID}:${GID}"
    environment:
      NC_URL: "https://cloud.example.com"
      NC_USER: "your-nextcloud-user"
      NC_PASS: "your-nextcloud-password"
      NC_SOURCE_DIR: "/media/nextcloud"
      NC_INTERVAL: "300"
      NC_EXIT: "false"
      TZ: "Europe/Berlin"
    volumes:
      - /pfad/zu/deinen/daten:/media/nextcloud
      - ./config:/config:ro
```

`USER_UID` / `USER_GID` werden im Rootless-Modus ignoriert.

------------------------------------------------------------------------

## Beispiel: docker-compose.example.yml

``` yaml
services:
  nextcloud-sync:
    image: ghcr.io/begauns/nextcloud-sync:latest
    container_name: nextcloud-sync
    restart: always

    # Root-Modus (z.B. OMV):
    # - Kein "user:" setzen
    #
    # Rootless-Modus:
    # - Optional: user: "${UID}:${GID}"
    # - USER_UID/USER_GID weglassen oder ignoriert

    environment:
      # Pflicht-Parameter
      NC_URL: "https://cloud.example.com"
      NC_USER: "your-nextcloud-user"
      NC_PASS: "your-nextcloud-password"
      NC_SOURCE_DIR: "/media/nextcloud"

      # Nur im Root-Modus nötig
      USER_UID: "1000"
      USER_GID: "1000"

      # Optionale CLI-Flags
      NC_PATH: ""
      NC_NON_INTERACTIVE: "1"
      NC_SILENT: "false"
      NC_TRUST_CERT: "false"
      NC_HIDDEN: "false"
      NC_MAX_SYNC_RETRIES: "5"
      NC_EXCLUDE_FILE: "/config/exclude.lst"
      NC_UNSYNCED_FILE: "/config/unsynced.lst"
      NC_HTTPPROXY: ""

      # Cron-Loop
      NC_INTERVAL: "300"
      NC_EXIT: "false"
      TZ: "Europe/Berlin"

    volumes:
      - /pfad/zu/deinen/daten:/media/nextcloud
      - ./config:/config:ro
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
```

------------------------------------------------------------------------

## Kurz: Image + Nutzung

**Image:** `ghcr.io/begauns/nextcloud-sync:latest`

Nutzung:

1.  `docker-compose.example.yml` anpassen (Pfad, UID/GID, `NC_*`).
2.  `docker compose up -d`
3.  `docker compose logs -f` zum Überprüfen.
