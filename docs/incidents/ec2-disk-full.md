# EC2: no space left on device

## Symptom
- `make up` failed while building images with `no space left on device` (while writing into `/var/lib/containerd`).
- `health-check.sh` reported `FAIL: disk 100% (limit 80%)`.

## Investigation
```bash
df -hT /
lsblk
sudo du -xh / --max-depth=2 2>/dev/null | sort -h | tail -15
docker system df
```
The root volume was almost full, and the biggest users were Docker and containerd image layers.

## Root cause
The root EBS volume was too small for the OS plus Docker images and build cache (the Python and boto3 layers are large).

## Fix
(Edit this section to match exactly what you did.)
1. Freed space: `docker system prune -af`, `docker builder prune -af`, `sudo apt-get clean`, `sudo journalctl --vacuum-size=100M`.
2. Attached an extra 20 GB EBS volume in the same Availability Zone, formatted it (`mkfs.ext4`), mounted it at `/mnt/data`, and added a UUID entry with `nofail` to `/etc/fstab`.
3. Moved Docker and containerd data to `/mnt/data` and bind-mounted them back to `/var/lib/docker` and `/var/lib/containerd`.
4. Ran `make up` and `make test` again, then re-ran the health check.

## Prevention
- Size the volume in Terraform from the start (at least 20 GB for a Docker host).
- The health-check cron alerts at 80% disk usage, which warns before it reaches 100%.
- Prune old images regularly, and monitor disk with Prometheus Node Exporter later.

## What I learned
How to read `df`, `du` and `lsblk`, how EBS volumes attach, how `/etc/fstab` works, and that a health check catches a problem before the application fails.
