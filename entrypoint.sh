#!/bin/bash
set -e

LOG_DATE_FORMAT="%m-%d %H:%M:%S"

log() {
  echo "$(date +"${LOG_DATE_FORMAT}") $*"
}

########################################
# Config-Defaults initialisieren
########################################
init_config_defaults() {
  if [ -d /config ]; then
    if [ ! -f /config/exclude.lst ] && [ -f /defaults-config/exclude.lst ]; then
      log "[ info entrypoint ]: initializing /config/exclude.lst from image defaults"
      cp /defaults-config/exclude.lst /config/exclude.lst
    fi
    if [ ! -f /config/unsynced.lst ] && [ -f /defaults-config/unsynced.lst ]; then
      log "[ info entrypoint ]: initializing /config/unsynced.lst from image defaults"
      cp /defaults-config/unsynced.lst /config/unsynced.lst
    fi

    # Besitzer & Rechte nur setzen, wenn wir root sind
    if [ "$(id -u)" = "0" ]; then
      # Verzeichnis selbst
      chown root:users /config || \
        log "[ warn entrypoint ]: chown /config to root:users failed"
      chmod 750 /config || \
        log "[ warn entrypoint ]: chmod /config failed"

      # Dateien, falls vorhanden
      if [ -f /config/exclude.lst ]; then
        chown root:users /config/exclude.lst || \
          log "[ warn entrypoint ]: chown /config/exclude.lst failed"
        chmod 640 /config/exclude.lst || \
          log "[ warn entrypoint ]: chmod /config/exclude.lst failed"
      fi
      if [ -f /config/unsynced.lst ]; then
        chown root:users /config/unsynced.lst || \
          log "[ warn entrypoint ]: chown /config/unsynced.lst failed"
        chmod 640 /config/unsynced.lst || \
          log "[ warn entrypoint ]: chmod /config/unsynced.lst failed"
      fi
    fi
  else
    log "[ warn entrypoint ]: /config directory not found (no config volume mounted?)"
  fi
}

cleanup_unsynced_list() {
  # Platzhalter: hier könntest du später problematische unsynced-Einträge bereinigen
  :
}

init_config_defaults

export TZ=${TZ:-Europe/Berlin}
log "[ info entrypoint ]: Using timezone: ${TZ}"
log "[ info entrypoint ]: Running as UID: $(id -u), GID: $(id -g)"

########################################
# Rootless-Modus
########################################
if [ "$(id -u)" != "0" ]; then
  log "[ info entrypoint ]: detected rootless mode (no UID 0) – running directly as current user"

  run_sync_rootless() {
      ARGS=()

      [ -n "${NC_PATH}" ]                 && ARGS+=(--path "${NC_PATH}")
      [ -n "${NC_USER}" ]                 && ARGS+=(--user "${NC_USER}")
      [ -n "${NC_PASS}" ]                 && ARGS+=(--password "${NC_PASS}")
      [ "${NC_NON_INTERACTIVE}" = "1" ]   && ARGS+=(--non-interactive)
      [[ "${NC_SILENT}" != "false" && "${NC_SILENT}" != "" ]] && ARGS+=(--silent)
      [[ "${NC_TRUST_CERT}" != "false" && "${NC_TRUST_CERT}" != "" ]] && ARGS+=(--trust)
      [ -n "${NC_HTTPPROXY}" ]            && ARGS+=(--httpproxy "${NC_HTTPPROXY}")
      [ -n "${NC_EXCLUDE_FILE}" ]         && ARGS+=(--exclude "${NC_EXCLUDE_FILE}")
      [ -n "${NC_UNSYNCED_FILE}" ]        && ARGS+=(--unsyncedfolders "${NC_UNSYNCED_FILE}")
      [ -n "${NC_MAX_SYNC_RETRIES}" ]     && ARGS+=(--max-sync-retries "${NC_MAX_SYNC_RETRIES}")
      [[ "${NC_HIDDEN}" != "false" && "${NC_HIDDEN}" != "" ]] && ARGS+=(-h)

      if [ -z "${NC_SOURCE_DIR}" ] || [ -z "${NC_URL}" ]; then
          log "[ error entrypoint ]: NC_SOURCE_DIR und NC_URL müssen gesetzt sein."
          exit 1
      fi

      log "[ info entrypoint ]: [rootless] Syncing ${NC_SOURCE_DIR} → ${NC_URL} ..."
      nextcloudcmd "${ARGS[@]}" "${NC_SOURCE_DIR}" "${NC_URL}"

      cleanup_unsynced_list
  }

  INTERVAL=${NC_INTERVAL:-300}
  while true; do
      run_sync_rootless
      [ "${NC_EXIT}" = "true" ] && exit 0
      log "[ info entrypoint ]: waiting ${INTERVAL}s before next sync..."
      sleep "${INTERVAL}"
  done
fi

########################################
# Root-Modus
########################################

# USER_UID / USER_GID müssen in Root-Modus gesetzt sein
if [ -z "${USER_UID}" ] || [ -z "${USER_GID}" ]; then
  log "[ error entrypoint ]: running as root – USER_UID und USER_GID müssen gesetzt sein!"
  exit 1
fi

TARGET_UID=${USER_UID}
TARGET_GID=${USER_GID}

# Rechte auf Sync-Ordner setzen
if [ -d /media/nextcloud ]; then
  log "[ info entrypoint ]: [root] chown /media/nextcloud to ${TARGET_UID}:${TARGET_GID} ..."
  chown -R "${TARGET_UID}:${TARGET_GID}" /media/nextcloud || \
    log "[ warn entrypoint ]: [root] chown /media/nextcloud failed"
else
  log "[ warn entrypoint ]: /media/nextcloud does not exist"
fi

# User mit dieser UID/GID im Container sicherstellen
EXISTING_USER_NAME="$(getent passwd "${TARGET_UID}" | cut -d: -f1 || true)"
if [ -n "${EXISTING_USER_NAME}" ]; then
  RUN_AS_USER="${EXISTING_USER_NAME}"
  log "[ info entrypoint ]: [root] using existing user ${RUN_AS_USER} for UID ${TARGET_UID}"
else
  RUN_AS_USER="ncsync"
  log "[ info entrypoint ]: [root] creating user ${RUN_AS_USER} (${TARGET_UID}:${TARGET_GID})"
  groupadd -g "${TARGET_GID}" ncsync 2>/dev/null || true
  useradd -u "${TARGET_UID}" -g "${TARGET_GID}" -M -s /usr/sbin/nologin "${RUN_AS_USER}" 2>/dev/null || true
fi

run_sync_root() {
    ARGS=()

    [ -n "${NC_PATH}" ]                 && ARGS+=(--path "${NC_PATH}")
    [ -n "${NC_USER}" ]                 && ARGS+=(--user "${NC_USER}")
    [ -n "${NC_PASS}" ]                 && ARGS+=(--password "${NC_PASS}")
    [ "${NC_NON_INTERACTIVE}" = "1" ]   && ARGS+=(--non-interactive)
    [[ "${NC_SILENT}" != "false" && "${NC_SILENT}" != "" ]] && ARGS+=(--silent)
    [[ "${NC_TRUST_CERT}" != "false" && "${NC_TRUST_CERT}" != "" ]] && ARGS+=(--trust)
    [ -n "${NC_HTTPPROXY}" ]            && ARGS+=(--httpproxy "${NC_HTTPPROXY}")
    [ -n "${NC_EXCLUDE_FILE}" ]         && ARGS+=(--exclude "${NC_EXCLUDE_FILE}")
    [ -n "${NC_UNSYNCED_FILE}" ]        && ARGS+=(--unsyncedfolders "${NC_UNSYNCED_FILE}")
    [ -n "${NC_MAX_SYNC_RETRIES}" ]     && ARGS+=(--max-sync-retries "${NC_MAX_SYNC_RETRIES}")
    [[ "${NC_HIDDEN}" != "false" && "${NC_HIDDEN}" != "" ]] && ARGS+=(-h)

    if [ -z "${NC_SOURCE_DIR}" ] || [ -z "${NC_URL}" ]; then
        log "[ error entrypoint ]: NC_SOURCE_DIR und NC_URL müssen gesetzt sein."
        exit 1
    fi

    log "[ info entrypoint ]: [root] Syncing ${NC_SOURCE_DIR} → ${NC_URL} as ${RUN_AS_USER} (${TARGET_UID}:${TARGET_GID}) ..."

    CMD="nextcloudcmd"
    for arg in "${ARGS[@]}"; do
      CMD+=" $(printf '%q' "${arg}")"
    done
    CMD+=" $(printf '%q' "${NC_SOURCE_DIR}") $(printf '%q' "${NC_URL}")"

    log "[ debug entrypoint ]: running as ${RUN_AS_USER}: ${CMD}"
    su -s /bin/bash "${RUN_AS_USER}" -c "${CMD}"

    cleanup_unsynced_list
}

INTERVAL=${NC_INTERVAL:-300}
while true; do
    run_sync_root
    [ "${NC_EXIT}" = "true" ] && exit 0
    log "[ info entrypoint ]: [root] waiting ${INTERVAL}s before next sync..."
    sleep "${INTERVAL}"
done
