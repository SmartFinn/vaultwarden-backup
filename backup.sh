#!/bin/sh

set -ex

# Use the value of the corresponding environment variable, or the
# default if none exists.
: "${DATA_FOLDER:=/data}"
: "${ATTACHMENTS_FOLDER:=${DATA_FOLDER}/attachments}"
: "${DATABASE_URL:=${DATA_FOLDER}/db.sqlite3}}"
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
until sqlite3 "file:${DATABASE_URL}?mode=ro" ".backup '${BACKUP_DIR_PATH}/${DATABASE_URL##*/}'"; do
    tries=$((tries+1))
    if [ "$tries" -ge "$max_tries" ]; then
        echo "Aborting after ${max_tries} failed backup attempts..."
        exit 1
    fi
    echo "Backup failed. Retry #${tries}..."
    rm -f "${BACKUP_DIR_PATH}/${DATABASE_URL##*/}"
    sleep 1
done

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
md5sum "${BACKUP_FILE_PATH}"
sha1sum "${BACKUP_FILE_PATH}"

if [ -n "${GPG_PASSPHRASE}" ]; then
    # https://gnupg.org/documentation/manuals/gnupg/GPG-Esoteric-Options.html
    # Note: Add `--pinentry-mode loopback` if using GnuPG 2.1.
    printf '%s' "${GPG_PASSPHRASE}" |
        gpg -c --cipher-algo "${GPG_CIPHER_ALGO:-AES128}" --batch --passphrase-fd 0 "${BACKUP_FILE_PATH}"
    BACKUP_FILE_NAME="$BACKUP_FILE_NAME.gpg"
    BACKUP_FILE_PATH="$BACKUP_FILE_PATH.gpg"
    md5sum "${BACKUP_FILE_PATH}"
    sha1sum "${BACKUP_FILE_PATH}"
fi
