#!/usr/bin/env bash
# Adds the Phase 5 settings to env/dev.tfvars, env/qa.tfvars and env/prod.tfvars.
# Safe to run twice: a file that already has the settings is skipped.
set -euo pipefail
cd "$(dirname "$0")/../terraform/env"

add() {
  local f="$1.tfvars"
  if grep -q '^enable_rds' "$f"; then
    echo "skip   $f (already updated)"
    return
  fi
  printf '\n%s\n' "$2" >> "$f"
  echo "added  $f"
}

add dev 'enable_rds               = true
enable_efs               = true
enable_bastion           = true
db_instance_class        = "db.t4g.micro"
db_allocated_storage     = 20
db_multi_az              = false
db_backup_retention_days = 1
db_deletion_protection   = false
db_skip_final_snapshot   = true
efs_backup_enabled       = false'

add qa 'enable_rds               = true
enable_efs               = true
enable_bastion           = false
db_instance_class        = "db.t4g.micro"
db_allocated_storage     = 20
db_multi_az              = false
db_backup_retention_days = 3
db_deletion_protection   = false
db_skip_final_snapshot   = true
efs_backup_enabled       = false'

add prod 'enable_rds               = true
enable_efs               = true
enable_bastion           = false
db_instance_class        = "db.t4g.small"
db_allocated_storage     = 20
db_multi_az              = true
db_backup_retention_days = 7
db_deletion_protection   = true
db_skip_final_snapshot   = false
efs_backup_enabled       = true'
