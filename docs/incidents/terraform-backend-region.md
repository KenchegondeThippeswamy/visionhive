# Terraform init: 301 error, region mismatch

## Symptom
`terraform init -reconfigure -backend-config=env/qa.backend.hcl` failed with:
`Failed to get existing workspaces ... StatusCode: 301 ... requested bucket from "ap-south-1", actual location "ap-southeast-2"`.

## Investigation
- The state bucket had been created in `ap-southeast-2` (Sydney).
- `grep -n region env/*.backend.hcl` showed `qa.backend.hcl` and `prod.backend.hcl` still had `ap-south-1`. Only dev had been changed.
- The plan after the failed init still ran, because I typed the two commands on separate lines.

## Root cause
Each environment has its own backend file with its own `region` line, and I changed the region in only one of them. S3 answers with a redirect (301) when the bucket is in another region. The plan ran against the previously initialised dev state because the failed `init` did not stop the next command.

## Fix
```bash
sed -i 's/ap-south-1/ap-southeast-2/g' env/qa.backend.hcl env/prod.backend.hcl
grep -rn "ap-south-1" .      # must print nothing
terraform init -reconfigure -backend-config=env/qa.backend.hcl && terraform plan -var-file=env/qa.tfvars
```

## Prevention
- Make the region a single value where possible, and check with `grep -rn "region" terraform/` after any change.
- Chain commands with `&&` (or use `set -e` in scripts), so a failed init stops everything.
- Use the `tf.sh` wrapper for all runs.

## What I learned
Backend configuration is separate from provider configuration, how S3 reports a wrong region, and why command chaining matters.
