# Docker: compose plugin missing, then permission denied

## Symptom
- `make up` failed with `unknown shorthand flag: 'f' in -f` (the `docker compose -f ...` command).
- After that, it failed with `permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock`.
- `docker ps` failed, but `sudo docker ps` worked.

## Investigation
- `docker compose version` failed, so the Compose plugin was not installed (Docker had been installed without it).
- `sudo docker ps` worked and `docker ps` did not, so Docker itself was healthy and the problem was permissions.
- `groups` and the shell prompt (`ubuntu@...`) showed I was logged in as `ubuntu`, not as my laptop user.

## Root cause
1. Docker was installed without the Compose v2 plugin.
2. The `ubuntu` user was not in the `docker` group. I first added the wrong user (`mantra`, my laptop name) and, once I used the right one, the running shell still had the old group list. Group changes only apply to new sessions.

## Fix
```bash
sudo apt-get install -y docker-compose-v2      # adds the compose plugin
sudo usermod -aG docker ubuntu                 # the user I am actually logged in as
newgrp docker                                  # or log out and back in
docker ps
```

## Prevention
- Check the real username with `whoami` before running `usermod`.
- Add the user to the `docker` group in the server setup script, and verify with `docker ps` and `docker compose version`.
- Never use `sudo make up` as a workaround, because root-owned files cause new problems.

## What I learned
Linux group membership, why group changes need a new login session, and how to separate "Docker is broken" from "I lack permission".
