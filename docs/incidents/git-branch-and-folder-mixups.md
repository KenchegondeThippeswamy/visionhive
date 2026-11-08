# Git: branch name conflict, nested folders, and an untracked dev branch

## Symptom
1. `git checkout -b feature/phase3-scripts` failed with `cannot lock ref ... 'refs/heads/feature' exists`.
2. Files appeared as `scripts/scripts/*.sh` and `visionhive-phase4/terraform/...` instead of `scripts/*.sh` and `terraform/...`.
3. On the server, `git checkout dev` worked but `git pull` said `There is no tracking information for the current branch`, and the scripts were missing.

## Investigation
- `git branch` showed a stray branch named `feature`.
- `git show --stat HEAD` showed the nested paths.
- `git log origin/dev` had the scripts, while the local `dev` was still at the old commit.

## Root cause
1. Branch names behave like file paths: a branch `feature` blocks `feature/anything`.
2. I copied or unzipped a folder inside another folder, one level too deep.
3. I created a local `dev` with `git branch dev` (from `main`) instead of tracking `origin/dev`.

## Fix
```bash
git branch -d feature                                   # remove the blocking branch
git mv scripts/scripts/*.sh scripts/ && rmdir scripts/scripts
git branch --set-upstream-to=origin/dev dev && git pull
```
For the nested Terraform folder I moved the files up with `rsync -a visionhive-phase4/ ./`, verified `terraform plan` still said `No changes`, and then removed the old folder.

## Prevention
- Use `feature/<name>` consistently and never create a plain `feature` branch.
- Run `ls` and `git status --short` after every copy or unzip.
- Create tracking branches with `git checkout dev` (when `origin/dev` exists) or `git switch -c dev --track origin/dev`.

## What I learned
How Git stores branch names, how upstream tracking works, and how to check a commit with `git show --stat`.
