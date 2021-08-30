#!/bin/sh

# Allow start with custom commands
if [ "$#" -ne 0 ] && command -v "$@" > /dev/null 2>&1; then
	"$@"
	exit 0
fi

set -e

# Check if $DATA_FOLDER is accessible and exit otherwise
if [ ! -e "${DATA_FOLDER:-/data}" ]; then
	echo "Directory '${DATA_FOLDER:-/data}' not found!" >&2
	echo "Please check if you mounted the vaultwarden volume with '--volumes-from=vaultwarden'" >&2
	exit 1
fi

# Check if $BACKUP_ROOT/archives is mounted and exit otherwise
if [ ! -e "${BACKUP_ROOT:-/backup}/archives" ]; then
	echo "Directory '${BACKUP_ROOT:-/backup}/archives' not found!" >&2
	echo "Please check if you mounted the volume with" \
		"'--volume=/tmp/archives:${BACKUP_ROOT:-/backup}/archives'" >&2
	exit 1
fi

/app/backup.sh

exit 0