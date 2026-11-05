# Partial backend: the bucket and key come from env/<env>.backend.hcl at init time.
# Example: terraform init -reconfigure -backend-config=env/dev.backend.hcl
terraform {
  backend "s3" {}
}
