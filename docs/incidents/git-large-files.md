# Git push rejected: file exceeds GitHub's 100 MB limit

## Symptom
`git push` failed with `GH001: Large files detected`:
`terraform/bootstrap/.terraform/providers/.../terraform-provider-aws_v6.72.0_x5 is 768.58 MB`.

## Investigation
- The commit output listed `.terraform/providers/...` and `terraform.tfstate` among the created files.
- `.gitignore` had no Terraform rules at that point.

## Root cause
`terraform init` downloads the AWS provider plugin (about 768 MB) into a `.terraform/` folder. I ran `git add -A` without ignoring it, so the plugin and the state file were committed.

## Fix
```bash
git reset HEAD~1                                   # undo the local commit, keep the files
printf '\n**/.terraform/\n*.tfstate\n*.tfstate.*\n*.plan\ncrash.log\n' >> .gitignore
git rm -r --cached --ignore-unmatch terraform/bootstrap/.terraform terraform/bootstrap/terraform.tfstate
git add -A && git commit -m "feat: terraform base"
git log --all --name-only --format= | grep terraform-provider-aws || echo "history clean"
git push -u origin feature-phase4
```
I backed up `bootstrap/terraform.tfstate` to S3 (`backups/`) and to a local folder before removing it from Git.

## Prevention
- Add the Terraform rules to `.gitignore` on day one.
- Run `git status --short` and read it before every commit.
- Commit `.terraform.lock.hcl` (small, pins versions), but never `.terraform/`, `*.tfstate` or `*.plan`.
- The push was rejected before any data was stored on GitHub, so nothing was exposed.

## What I learned
What Terraform creates locally, why state files hold sensitive data and do not belong in Git, and how to undo a commit safely.
