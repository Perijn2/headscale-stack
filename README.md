# headscale-stack

Self-hosted Tailscale control plane for a Raspberry Pi: **headscale** +
**Headplane** (Tailscale-style admin UI) + **Caddy** (automatic TLS), as a
modular Docker Compose project.

## Compose layout

The stack is split into small modules aggregated by the root `compose.yaml`
via the `include:` directive (Docker Compose v2.20+):

| File                    | Service    | Role                                                        |
| ----------------------- | ---------- | ----------------------------------------------------------- |
| `compose.yaml`          | —          | aggregator + shared `controlplane` network                   |
| `compose/headscale.yaml`| headscale  | coordination control plane (only thing that speaks Tailscale)|
| `compose/headplane.yaml`| headplane  | Tailscale-style admin UI + coordination proxy                |
| `compose/caddy.yaml`    | caddy      | TLS terminator + router (only published web ports)           |
| `compose/backup.yaml`   | backup     | opt-in snapshot loop (`--profile backup`)                    |

**Path rule:** inside an included module, relative paths resolve against that
*module's* directory — hence `../config/...` and `../data/...` everywhere.

## Repo layout

```
config/                  tracked, declarative, human-edited
  headscale/config.yaml      control plane settings
  headscale/policy.hujson    ACLs
  headplane/headplane.yaml.example   template (real file is generated, ignored)
  caddy/Caddyfile              TLS + routing
data/                    IGNORED — runtime state (sqlite, keys, certs)
backups/                 IGNORED — snapshot tarballs
compose/                 the service modules above
.env.example             copy to .env on the Pi; all interpolation lives here
```

Reinstall story: `git clone` + copy `.env` + `./install.sh` → `scripts/restore.sh`
for the data.

## Quick start (Raspberry Pi, 64-bit OS)

```sh
git clone <this-repo> && cd headscale-server
cp .env.example .env        # set DOMAIN, TLS_EMAIL
./install.sh                # checks arch/docker, generates secrets, composes up
docker compose --profile backup up -d   # optional: enable nightly snapshots
```

Then point an A record at the Pi, open `https://<DOMAIN>`, and add devices
with a preauth key.
