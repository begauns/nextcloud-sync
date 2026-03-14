# Nextcloud Sync (nextcloudcmd) als Docker-Container

Minimaler Debian-Container, der mit `nextcloudcmd` ein lokales
Verzeichnis gegen eine Nextcloud-Instanz synchronisiert -- inkl.
Intervall-Sync, Exclude-/Unsynced-Listen und flexiblem UID/GID-Mapping
(Root + Rootless).

**Image:** `ghcr.io/begauns/nextcloud-sync:latest`

------------------------------------------------------------------------

## Image verwenden

### 1. Repository klonen (optional, aber bequem)

```bash
git clone https://github.com/begauns/nextcloud-sync.git
cd nextcloud-sync
```

### 2. Beispiel-Compose übernehmen und anpassen

```bash
cp docker-compose.example.yml docker-compose.yml
nano docker-compose.yml
```
- NC_URL, NC_USER, NC_PASS, NC_SOURCE_DIR anpassen
- Host-Pfade für `/media/nextcloud` und `/config` setzen
- Bei OMV/klassischem Docker: `USER_UID`/`USER_GID` setzen, kein `user:` im Service
- Bei rootless: `user:` setzen, `USER_UID`/`USER_GID` weglassen

### 3. Container starten

```bash
docker compose up -d
docker compose logs -f
```

------------------------------------------------------------------------

## Pflicht-Variablen (Sync-Parameter)

Diese Variablen sind für jeden Sync notwendig:

### NC_URL

Basis-URL deiner Nextcloud (ohne `/remote.php/dav/...`).
Beispiel: `https://cloud.example.com`

### NC_USER

Nextcloud-Benutzername, der für den Login verwendet wird.

### NC_PASS

Nextcloud-Passwort zu `NC_USER`.

### NC_SOURCE_DIR

Lokales Sync-Verzeichnis im Container.
Standard im Compose: `/media/nextcloud`, wird auf ein Host-Verzeichnis
gemountet.

Beispiel:

```yaml
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

Entspricht `--path`.
Setzt den entfernten Unterpfad, z.B. `/remote.php/dav/files/USER/Documents`.

### NC_NON_INTERACTIVE

`1` → `--non-interactive` aktiv (keine Prompts, liest ausschließlich ENV).
Alles andere = inaktiv.

### NC_SILENT

`false` → verbose Logs.
Jeder andere nicht-leere Wert → `--silent`.

### NC_TRUST_CERT

`false` → Standard-Zertifikatsprüfung.
Jeder andere nicht-leere Wert → `--trust` (unsichere Zertifikate akzeptieren).

### NC_HIDDEN

`false` → versteckte Dateien werden ignoriert.
Jeder andere nicht-leere Wert → `-h` (hidden files syncen).

### NC_EXCLUDE_FILE

Entspricht `--exclude <file>`.
Pfad zu einer Datei mit Exclude-Mustern (z.B. `/config/exclude.lst`).

### NC_UNSYNCED_FILE

Entspricht `--unsyncedfolders <file>`.
Pfad zu einer Datei mit Verzeichnissen, die **nicht** synchronisiert werden
sollen (Selective Sync).[web:185][web:262]

Format (eine Zeile pro Verzeichnis, relativ zum Nextcloud-Wurzelverzeichnis des Users, mit `/` am Ende):

```text
huge-archive/
old-backups/
downloads/
Photos/
```

**Wichtig:**

Die Ordner müssen auf dem Server tatsächlich existieren – falsche oder alte Einträge können zu `database is locked`‑Fehlern in der lokalen Sync-Datenbank führen.[web:172][web:176]

Änderungen an `unsynced.lst` wirken sich nur auf zukünftige Sync-Läufe aus; alte Einträge müssen ggf. durch Löschen der lokalen `.sync_*.db` komplett zurückgesetzt werden.

### NC_HTTPPROXY

Entspricht `--httpproxy http://user:pass@host:port`.

### NC_MAX_SYNC_RETRIES

Entspricht `--max-sync-retries <n>`.

Beispiel:

```yaml
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

**NC_INTERVAL**
Anzahl Sekunden zwischen zwei Sync-Durchläufen.
Beispiel: `300` (alle 5 Minuten).

**NC_EXIT**
`"false"` (oder leer) → Endlosschleife.
`"true"` → Container beendet sich nach einem Sync.

Beispiel:

```yaml
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

**USER_UID**
Ziel-UID, die Dateien im Sync-Ordner besitzen soll (Host-UID).

**USER_GID**
Ziel-GID (z.B. `users`).

Ablauf:

- `chown -R USER_UID:USER_GID /media/nextcloud`
- Im Container wird (falls nötig) ein User mit dieser UID/GID angelegt
- `nextcloudcmd` läuft als dieser User

Beispiel:

```yaml
environment:
  USER_UID: "1000"
  USER_GID: "1000"
```

**Wichtig:** In diesem Modus kein `user:` im Compose setzen, damit der Container als root starten kann.

------------------------------------------------------------------------

### 2. Rootless-Modus

Container läuft nicht als root (`id -u != 0`) -- z.B. rootless Docker oder Podman.

`entrypoint.sh`:

- führt **kein** `chown` aus
- legt **keine** Nutzer an
- startet `nextcloudcmd` direkt mit der vorhandenen UID

Voraussetzung:

Das gemountete Host-Verzeichnis muss bereits dem Engine-User gehören.

```bash
mkdir -p /pfad/zu/deinen/daten
chown -R $(id -u):$(id -g) /pfad/zu/deinen/daten
```

Im Compose kannst du optional `user:` setzen:

```yaml
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

```yaml
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

## Exclude- und Unsynced-Listen einrichten

Der Container bringt zwei Beispiel-Dateien im `config`-Ordner mit:

- `/config/exclude.lst` → für `NC_EXCLUDE_FILE` (`--exclude`)
- `/config/unsynced.lst` → für `NC_UNSYNCED_FILE` (`--unsyncedfolders`)[web:259][web:261]

### 1. Host-Verzeichnisse für Config mounten

Im `volumes`-Block der Compose-Datei:

```yaml
volumes:
  - /pfad/zu/deinen/daten:/media/nextcloud
  - /pfad/zu/nextcloud-sync/config:/config
```

Danach kannst du auf dem Host z.B. bearbeiten:

```bash
nano /pfad/zu/nextcloud-sync/config/exclude.lst
nano /pfad/zu/nextcloud-sync/config/unsynced.lst
```

### 2. exclude.lst (Datei-/Muster-basiert)

Die `exclude.lst` folgt der üblichen Nextcloud-Sync-Logik (`sync-exclude.lst`).[web:260][web:263]

Beispiele:

```text
*.tmp
*.bak
node_modules/
.cache/
```

- Zeilen mit `#` am Anfang sind Kommentare
- Ordner mit `/` am Ende werden rekursiv ausgeschlossen

### 3. unsynced.lst (verzeichnisbasiert, Selective Sync)

Die `unsynced.lst` steuert, welche Remote-Ordner komplett vom Sync ausgeschlossen werden.[web:185][web:262]

Beispiele:

```text
huge-archive/
old-backups/
downloads/
Photos/
```

**Hinweise zu Stabilität:**

- Nutze nur stabile, existierende Wurzelordner.
- Gelöschte oder umbenannte Ordner in `unsynced.lst` können im Zusammenspiel mit der lokalen Sync-Datenbank zu SQL error: `"database is locked"` führen.[web:172][web:176]

Wenn du die Liste stark änderst und merkwürdige `"database is locked"`‑Meldungen im Log siehst, kannst du den Client sauber zurücksetzen:

1. Container stoppen
2. Im gemounteten Datenordner die Sync-DB löschen:

```bash
rm -f /pfad/zu/deinen/daten/.sync_*.db
```

3. `unsynced.lst` prüfen/aufräumen
4. Container wieder starten

Danach macht `nextcloudcmd` einen frischen Sync-Lauf mit der neuen Selective-Sync-Konfiguration.

------------------------------------------------------------------------

## Kurz: Image + Nutzung

**Image:** `ghcr.io/begauns/nextcloud-sync:latest`

Nutzung:

1.  Repository klonen, Compose anpassen (Pfad, UID/GID, `NC_*`)  
2.  `docker compose up -d`  
3.  `docker compose logs -f` zum Überprüfen

