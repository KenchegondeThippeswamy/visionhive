#!/usr/bin/env bash
# Delete old log files. DRY RUN by default. Add --apply to really delete.
# Usage: ./log-cleanup.sh /var/log/myapp 14        (preview)
#        ./log-cleanup.sh /var/log/myapp 14 --apply
set -euo pipefail

DIR=${1:?Usage: $0 <directory> <days> [--apply]}
DAYS=${2:?Usage: $0 <directory> <days> [--apply]}
APPLY=${3:-}

[[ -d "$DIR" ]] || { echo "Not a directory: $DIR"; exit 1; }
[[ "$DIR" != "/" && "$DIR" != "/var" && "$DIR" != "/var/log" ]] || { echo "Refusing to clean $DIR"; exit 1; }

echo "Files older than $DAYS days in $DIR (*.log, *.gz):"
find "$DIR" -type f \( -name '*.log' -o -name '*.gz' \) -mtime +"$DAYS" -print

if [[ "$APPLY" == "--apply" ]]; then
  find "$DIR" -type f \( -name '*.log' -o -name '*.gz' \) -mtime +"$DAYS" -delete
  echo "Deleted."
else
  echo "(dry run) nothing deleted. Re-run with --apply to delete."
fi
