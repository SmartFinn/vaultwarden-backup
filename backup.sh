#!/bin/sh

set -ex

# Use the value of the corresponding environment variable, or the
# default if none exists.
: "${DATA_FOLDER:=/data}"
: "${ATTACHMENTS_FOLDER:=${DATA_FOLDER}/attachments}"
: "${DATABASE_URL:=${DATA_FOLDER}/db.sqlite3}"
: "${CONFIG_FILE:=${DATA_FOLDER}/config.json}"
: "${RSA_KEY_FILENAME:=${DATA_FOLDER}/rsa_key}"
: "${SENDS_FOLDER:=${DATA_FOLDER}/sends}"

: "${BACKUP_ROOT:=/backup}"

BACKUP_DIR_NAME="vaultwarden-$(date '+%Y%m%d-%H%M')"
BACKUP_DIR_PATH="${BACKUP_ROOT}/${BACKUP_DIR_NAME}"
BACKUP_FILE_DIR="archives"
BACKUP_FILE_NAME="${BACKUP_DIR_NAME}.tar.gz"
BACKUP_FILE_PATH="${BACKUP_ROOT}/${BACKUP_FILE_DIR}/${BACKUP_FILE_NAME}"

cd "${DATA_FOLDER}"
mkdir -p "${BACKUP_DIR_PATH}"

# Back up the database using the Online Backup API (https://www.sqlite.org/backup.html)
# as implemented in the SQLite CLI. However, if a call to sqlite3_backup_step() returns
# one of the transient errors SQLITE_BUSY or SQLITE_LOCKED, the CLI doesn't retry the
# backup step; instead, it simply stops the backup and returns an error. This is unlikely,
# but to minimize the possibility of a failed backup, implement a retry mechanism here.
max_tries=10
tries=0

case "${DATABASE_URL}" in
mysql://*|postgresql://*)
    echo "WARNING: Backup MySQL and PostgreSQL DB is not supported." \
        "Backup without database dump will be incomplete!" >&2
    ;;
*)
    until sqlite3 "file:${DATABASE_URL}?mode=ro" ".backup '${BACKUP_DIR_PATH}/${DATABASE_URL##*/}'"; do
        tries=$((tries+1))
        if [ "$tries" -ge "$max_tries" ]; then
            echo "Aborting after ${max_tries} failed backup attempts..." >&2
            exit 1
        fi
        echo "Backup failed. Retry #${tries}..." >&2
        rm -f "${BACKUP_DIR_PATH}/${DATABASE_URL##*/}"
        sleep 1
    done
    ;;
esac


for i in \
    "$ATTACHMENTS_FOLDER" \
    "$CONFIG_FILE" \
    "$RSA_KEY_FILENAME.der" \
    "$RSA_KEY_FILENAME.pem" \
    "$RSA_KEY_FILENAME.pub.der" \
    "$RSA_KEY_FILENAME.pub.pem" \
    "$SENDS_FOLDER"
do
    if [ -e "${DATA_FOLDER}/$i" ]; then
        cp -a "$DATA_FOLDER/$i" "${BACKUP_DIR_PATH}"
    fi
done

tar -caf "${BACKUP_FILE_PATH}" -C "${BACKUP_ROOT}" "${BACKUP_DIR_NAME}"
rm -rf "${BACKUP_DIR_PATH}"

if [ -n "${GPG_PASSPHRASE}" ]; then
    # https://gnupg.org/documentation/manuals/gnupg/GPG-Esoteric-Options.html
    # Note: Add `--pinentry-mode loopback` if using GnuPG 2.1.
    printf '%s' "${GPG_PASSPHRASE}" |
        gpg -c --cipher-algo "${GPG_CIPHER_ALGO:-AES128}" --batch --passphrase-fd 0 "${BACKUP_FILE_PATH}"

    if [ -s "${BACKUP_FILE_PATH}.gpg" ]; then
        rm "${BACKUP_FILE_PATH}"
    fi
fi

# Purge old local backups
if [ "${DELETE_BACKUP_AFTER}" -gt 0 ]; then
    find "${BACKUP_ROOT}/${BACKUP_FILE_DIR}" \
        -name 'vaultwarden-*.tar.*' \
        -mtime "+${DELETE_BACKUP_AFTER}" -delete
fi

# Override owner and group for archives if one of the variable is set
if [ "$(id -u)" -eq 0 ] && {
        [ -n "$OVERRIDE_UID" ] || [ -n "$OVERRIDE_GID" ]
    }
then
    chown -R "${OVERRIDE_UID}:${OVERRIDE_GID}" "${BACKUP_ROOT}/${BACKUP_FILE_DIR}"
fi