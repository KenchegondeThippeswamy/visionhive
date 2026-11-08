resource "aws_efs_file_system" "this" {
  creation_token   = "${var.name}-models"
  encrypted        = true
  kms_key_id       = var.kms_key_arn
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  # Files not used for 30 days move to the cheaper Infrequent Access class,
  # and move back to standard storage when they are read again.
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = { Name = "${var.name}-models" }
}

resource "aws_efs_mount_target" "this" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [var.security_group_id]
}

resource "aws_efs_backup_policy" "this" {
  count          = var.backup_enabled ? 1 : 0
  file_system_id = aws_efs_file_system.this.id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_access_point" "models" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/models"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = { Name = "${var.name}-models" }
}
