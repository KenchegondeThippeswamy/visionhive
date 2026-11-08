# Terraform: plan showed 27 resources to destroy

## Symptom
`terraform plan -var-file=env/qa.tfvars` ended with `Plan: 31 to add, 1 to change, 27 to destroy`, and many resources were marked `must be replaced`, for example `cidr_block = "10.10.0.0/16" -> "10.20.0.0/16" # forces replacement`.

## Investigation
- The resource names changed from `visionhive-dev-...` to `visionhive-qa-...` and the CIDR from 10.10 to 10.20, which are the dev and qa values.
- `grep '"key"' .terraform/terraform.tfstate` showed `visionhive/dev/terraform.tfstate`.

## Root cause
The backend was still initialised for the dev state, but I ran `plan` with the qa variables. Terraform compared dev's real resources with qa's settings and planned to replace everything. Nothing was applied, so no resource was lost.

## Fix
Switch the backend first, then plan, with `&&` so a failed init stops the command:
```bash
terraform init -reconfigure -backend-config=env/qa.backend.hcl && terraform plan -var-file=env/qa.tfvars
```
The correct qa plan was `32 to add, 0 to change, 0 to destroy`. Dev stayed untouched (`No changes`).

## Prevention
- The state file (`init -backend-config=...`) and the variables (`-var-file=...`) must always be for the same environment.
- A wrapper script, `scripts/tf.sh <env> <action>`, runs both together.
- Always read the number of destroys first, and never apply a plan that destroys more than expected.
- Check the active state with `grep '"key"' .terraform/terraform.tfstate`.

## What I learned
How plans are calculated from code, state and real infrastructure, what `forces replacement` means, and that `plan` is safe to run and a good place to catch mistakes.
