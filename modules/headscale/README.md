# `headscale` module

Stands up a [headscale](https://github.com/juanfont/headscale) control server — a
self-hosted Tailscale coordination server — plus quark's provisioning service, on a single
Azure VM.

This file is the contract between the infrastructure and the quark codebase. If you are
here to make quark talk to a server this module built, everything you need is below.

## What the module produces

|                               | quark instance                              |
| ----------------------------- | ------------------------------------------- |
| Control server (`server_url`) | `https://quark.ts.autobutler.org`           |
| MagicDNS base (`base_domain`) | `headscale.quark.ts.autobutler.org`         |
| Provisioning API              | `https://quark.ts.autobutler.org/provision` |
| Azure fallback FQDN           | `quark-headscale.eastus.cloudapp.azure.com` |

The control server and the MagicDNS base are deliberately **siblings** — neither contains
the other. A node named the same as the control server would otherwise shadow it in
MagicDNS, and the symptom is nodes intermittently failing to reach the coordinator rather
than anything that names DNS as the cause.

`base_domain` is resolved only inside the tailnet. It has no public DNS record and must not
be given one.

## Ports

| Port | Proto | Purpose                                                            |
| ---- | ----- | ------------------------------------------------------------------ |
| 22   | TCP   | SSH (also Entra ID login, via the `AADSSHLoginForLinux` extension) |
| 80   | TCP   | ACME HTTP-01 challenge, redirects to 443 once a certificate exists |
| 443  | TCP   | headscale, behind nginx                                            |
| 3478 | UDP   | STUN, for NAT traversal                                            |

headscale's gRPC (50443) is **not** exposed. It listens on `127.0.0.1:50443`, so a public
rule would grant nothing; reach it over SSH if you need remote CLI admin.

The provisioning service is not exposed either. It listens on `127.0.0.1:8081`, and nginx
proxies `https://<control server>/provision` to it, so the shared secret only ever crosses
the internet inside TLS.

## ACL policy

headscale loads `/etc/headscale/policy.hujson`, which the setup script writes as one grant:

```json
{
  "grants": [
    { "src": ["autogroup:member"], "dst": ["autogroup:self"], "ip": ["tcp:80"] }
  ]
}
```

A headscale user is a household: one per Quark, with the owner's phones enrolled under the
same user (autobutler-org/quark#2320). The grant lets every node reach the other nodes of its
own user on `tcp:80`, Quark's HTTP port, and nothing else. Households cannot see each other,
and adding a household or a device never edits the policy or reloads headscale.

- **Needs headscale 0.29.2 or later.** Grants arrived in 0.29.0, and 0.29.2 fixed the
  reconnect storm an `autogroup:self` policy could set off (juanfont/headscale#3358).
- **A Quark is never tagged.** Tagged nodes are excluded from `autogroup:self`, and a tag
  as the source of an `autogroup:self` grant fails to load.
- **No ICMP.** `ping` between nodes fails. That is the policy, not a broken tailnet.
- **Phones never listen.** The grant covers a phone's port 80 too, and it stays harmless
  only because nothing listens there.

Checked against v0.29.4 before it shipped: `headscale policy check` accepts it, and the
compiled filter for a node lists only its own user's addresses as sources, on TCP port 80.
`azure/autobutler/VERIFYING-HEADSCALE.md` (layer 5) is how to prove it on the live server.

## The household key

`PROVISIONING_HOUSEHOLD_KEY` is the HMAC key the provisioning service signs household
tokens with (autobutler-org/quark#2358). It is **never in Terraform, state, a planfile or
CI**. The setup script generates it on the VM the first time it runs
(`openssl rand -base64 48`), into `/var/lib/headscale/provisioning-household.key`, mode
`600`, owner `headscale`. On every run it copies the file into `provisioning.env`, with
tracing off.

The key lives and dies with the headscale database. Every household token a Quark holds was
signed with it, and every household it names is a user in that database, so the two
are only useful together. The script never replaces an existing key, and the pre-upgrade
backup copies it alongside `db.sqlite`.

**Losing the key, or replacing it, means every Quark must re-enroll** (Disable, then
Enable): their tokens no longer verify. To restore a VM, restore the key together with the
database. There is no rotation procedure, on purpose.

## No node expiry

The config sets no `node.expiry`, so the default, `0`, applies: headscale sets no expiry of
its own, and a node registered with a pre-auth key gets whatever expiry the client asks for.
tsnet asks for none, so Quark and phone nodes never expire. An expiry would log a Quark out
of the tailnet with nobody at the device to log it back in. Do not add one.

## What quark has to change

`pkg/util/remoteutil/remoteutil.go` currently hardcodes a domain that is not ours:

```go
const defaultControlURL = "https://quark.org"   // quark.org is not our domain
```

`quark.org` resolves to `52.20.84.62`, which belongs to someone else — rename fallout of
the same kind `updateutil.go` already documents. It needs to become:

```go
const defaultControlURL = "https://quark.ts.autobutler.org"
```

`QUARK_HEADSCALE_URL` already overrides this at runtime, so a build can be pointed at a
different tailnet without a code change. The constant is the default, not the only path.

## What the provisioning service needs

Nothing by hand. The unit sets the plain configuration, and the setup script writes the two
secrets (one from Terraform, one from the key file described above) into
`${config_dir}/provisioning.env` (`/etc/quark/provisioning.env`), mode `600`, owner
`headscale`.

| Variable                        | Set by                                                  | Required                     |
| ------------------------------- | ------------------------------------------------------- | ---------------------------- |
| `PROVISIONING_LISTEN_ADDR`      | the unit (`127.0.0.1:8081`)                             | no, defaults to `:8081`      |
| `HEADSCALE_USER`                | the unit (`quark`)                                      | no, defaults to `quark`      |
| `PROVISIONING_SECRET`           | the setup script, from `var.provisioning_secret`        | yes — `log.Fatal` without it |
| `PROVISIONING_HOUSEHOLD_KEY`    | the setup script, from the key file on the VM           | ignored by the pinned binary |
| `PROVISIONING_KEY_EXPIRY_HOURS` | not set                                                 | no                           |

There is no headscale API key. The service mints pre-auth keys by running the local
`headscale` CLI (autobutler-org/quark#1877), which reaches headscale over its unix socket:

- **Socket.** The config sets neither `unix_socket` nor `unix_socket_permission`, so
  headscale's defaults apply: `/var/run/headscale/headscale.sock`, mode `0770`. It
  sits in `/run/headscale`, the `RuntimeDirectory` of the packaged `headscale.service`,
  which is `0750` and owned by `headscale`. The provisioning unit runs as `User=headscale`,
  which is what grants it access.
- **No remote CLI.** Neither `cli.address` nor `HEADSCALE_CLI_ADDRESS` is set anywhere. Set
  either and the CLI switches to remote gRPC, which demands an API key.
- **Binary.** The `.deb` installs `/usr/bin/headscale`, which is on systemd's default `PATH`,
  so the unit does not set `HEADSCALE_BIN`.

`PROVISIONING_LISTEN_ADDR` and `HEADSCALE_USER` need autobutler-org/quark#1876, and the
CLI-based minting needs #1877. The binary built from `v0.37.0` still requires
`HEADSCALE_API_KEY`, so it exits with `log.Fatal` and `systemd` keeps restarting it. That is
expected: it could not mint keys against 0.28 anyway. Bump `provisioning_repo_ref` to a
release that includes both changes.

## The shared secret

> **Not confidential.** This value shows up in plan artifacts and in state, and quark
> publishes it anyway (autobutler-org/quark#1879). Anything that must stay confidential
> belongs in a data source, such as Key Vault, not in a `TF_VAR`.

`PROVISIONING_SECRET` authorizes `POST /provision`, so it is the only thing between a
caller and a valid tailnet enrollment key. quark's release build stamps the same value into
the client, and both sides read it from one place:

1. **GitHub.** The organization Actions secret `QUARK_PROVISIONING_SECRET`, shared with this
   repository and autobutler-org/quark.
2. **CI.** `plan.yml` sets it as `TF_VAR_quark_headscale_provisioning_secret` on the Plan
   step only.
3. **Terraform.** The root variable `quark_headscale_provisioning_secret` feeds this
   module's `provisioning_secret`. Both are `sensitive`, and the module rejects anything
   shorter than 32 characters or outside the base64, base64url and hex alphabets, since
   the value lands unquoted in a systemd `EnvironmentFile`.
4. **The extension.** `templatefile` renders the value, base64-encoded, into the setup
   script, and the script travels in the CustomScript extension's `protected_settings`.
   That attribute is sensitive in the provider schema, so a plan shows it as
   `(sensitive value)`, and ARM never returns it. The extension takes `script` or
   `commandToExecute` but not both, so passing the secret as an environment variable
   would mean inlining the whole script into `commandToExecute`.
5. **The VM.** The script decodes the value with tracing off, since the extension reports
   the tail of stderr to ARM, and writes it to `/etc/quark/provisioning.env`. Then it
   restarts `quark-provisioning`.

`PROVISIONING_SECRET` goes away once the provisioning pin moves to a binary that no longer
reads it (autobutler-org/quark#1879). The binary pinned today exits without it.

**Rotating the secret:**

1. Update the `QUARK_PROVISIONING_SECRET` org secret.
2. Re-run apply: push to `main` or dispatch `apply.yml`. The new value changes
   `protected_settings`, which updates the extension in place. ARM gives it a new
   sequence number, and the handler re-runs the script, which rewrites the env file and
   restarts the service.
3. Cut a quark release, so the client carries the new value.

Until step 3 ships, released clients send the old value and get refused. That re-run is
the whole setup script, not just the secret step. It rebuilds the binary and restarts
headscale, which briefly interrupts the control plane without touching the database.

**Where the value ends up.** State holds the extension's `protected_settings`, the
rendered script with the secret in it. State is the `azure/autobutler.tfstate` blob in the
`tfstate` container of the `stautobutlertfstate` storage account, in the `autobutler`
subscription (see `azure/autobutler/backend.tf`). Reading it takes Entra ID RBAC on the
account. The planfile artifact CI uploads carries the variable and a copy of state too.

A local `make plan` needs the variable exported. Any valid value works for a plan. Anything
other than the real value shows the `cloud-init` extension changing, and a local plan is
never applied.

## Bringing a server up

1. **Apply.** Terraform creates the VM and the DNS alias record, then runs the setup script.
   The script installs headscale and nginx, and it tries for a certificate. It builds and
   starts the provisioning service with its secret in place, and it creates the `quark`
   tailnet user if that user does not exist yet.

2. **Delegate the zone.** This is the one manual step, done once for a new zone. Take the
   `tailnet_dns_zone_nameservers` output and create matching `NS` records for the delegated
   label at Porkbun, where `autobutler.org` is served. Until this exists, the zone answers
   for nobody and certbot cannot issue.

That is all. A certificate failure at boot is non-fatal by design: the host serves plain
HTTP and keeps going, so that a DNS record that could not exist yet does not fail the VM's
provisioning. `headscale-certbot.timer` retries every 20 minutes until a certificate
exists. Once one does, the service is skipped, and renewal is the certbot package's own
`certbot.timer`. To check on it:

```bash
systemctl list-timers headscale-certbot.timer
journalctl -u headscale-certbot
```

## Enrolling a node

Clients call the provisioning service, which mints a headscale pre-auth key on their behalf:

```http
POST https://quark.ts.autobutler.org/provision
X-Provisioning-Secret: <PROVISIONING_SECRET>
Content-Type: application/json

{"device_id": "<stable per-device id>"}
```

## Operating notes

- **Changing the setup script does not replace the VM.** It is delivered by the
  `CustomScript` extension, not `custom_data`, so terraform updates the extension and
  re-runs it in place. That is deliberate: headscale keeps its state in sqlite at
  `/var/lib/headscale/db.sqlite` on the OS disk, and a VM replacement would take every node
  registration in the tailnet with it.
- **The script is not idempotent in the strict sense** — it re-clones, rebuilds, and
  rewrites config on every run. It is safe to re-run; it is not free.
- **The VM is Arm64** (`Standard_B2pts_v2`). `var.vm_architecture` drives the image SKU and
  both downloads together, so the size cannot drift from what the script fetches.
- **Memory is the constraint, not CPU.** 1 GiB, and the script compiles the Go binary on
  the host. If that starts OOMing, `Standard_B2pls_v2` (4 GiB) is the next step.
