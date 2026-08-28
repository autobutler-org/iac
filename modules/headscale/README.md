# `headscale` module

Stands up a [headscale](https://github.com/juanfont/headscale) control server — a
self-hosted Tailscale coordination server — plus quark's provisioning service, on a single
Azure VM.

This file is the contract between the infrastructure and the quark codebase. If you are
here to make quark talk to a server this module built, everything you need is below.

## What the module produces

| | quark instance |
| --- | --- |
| Control server (`server_url`) | `https://network.quark.ts.autobutler.org` |
| MagicDNS base (`base_domain`) | `headscale.quark.ts.autobutler.org` |
| Provisioning API | `http://<control server>:8081` |
| Azure fallback FQDN | `quark-headscale.eastus.cloudapp.azure.com` |

The control server and the MagicDNS base are deliberately **siblings** — neither contains
the other. A node named the same as the control server would otherwise shadow it in
MagicDNS, and the symptom is nodes intermittently failing to reach the coordinator rather
than anything that names DNS as the cause.

`base_domain` is resolved only inside the tailnet. It has no public DNS record and must not
be given one.

## Ports

| Port | Proto | Purpose |
| --- | --- | --- |
| 22 | TCP | SSH (also Entra ID login, via the `AADSSHLoginForLinux` extension) |
| 80 | TCP | ACME HTTP-01 challenge, redirects to 443 once a certificate exists |
| 443 | TCP | headscale, behind nginx |
| 3478 | UDP | STUN, for NAT traversal |
| 8081 | TCP | quark provisioning service |

headscale's gRPC (50443) is **not** exposed. It listens on `127.0.0.1:50443`, so a public
rule would grant nothing; reach it over SSH if you need remote CLI admin.

## What quark has to change

`pkg/util/remoteutil/remoteutil.go` currently hardcodes a domain that is not ours:

```go
const defaultControlURL = "https://network.quark.org"   // quark.org is not our domain
```

`quark.org` resolves to `52.20.84.62`, which belongs to someone else — rename fallout of
the same kind `updateutil.go` already documents. It needs to become:

```go
const defaultControlURL = "https://network.quark.ts.autobutler.org"
```

`QUARK_HEADSCALE_URL` already overrides this at runtime, so a build can be pointed at a
different tailnet without a code change. The constant is the default, not the only path.

## What the provisioning service needs

`cmd/provisioning/main.go` reads five environment variables. The systemd unit this module
installs sets the first two; **the two required ones it cannot set**, because neither value
can exist before the host is running:

| Variable | Set by | Required |
| --- | --- | --- |
| `HEADSCALE_URL` | the unit (`http://127.0.0.1:8080`) | no, has a default |
| `PORT` | the unit (`8081`) | ignored — `main.go` hardcodes `:8081` |
| `HEADSCALE_API_KEY` | **you, post-boot** | yes — `log.Fatal` without it |
| `PROVISIONING_SECRET` | **you, post-boot** | yes — `log.Fatal` without it |
| `PROVISIONING_KEY_EXPIRY_HOURS` | optional | no |

Both required variables go in `${config_dir}/provisioning.env`, which the unit loads with
`EnvironmentFile=-` so a missing file is not fatal at boot.

> **This is the step that catches people.** The setup script's own post-deploy notes, and
> the README this module was ported from, mention only `HEADSCALE_API_KEY`. Set just that
> one and the service still exits immediately on `PROVISIONING_SECRET`, with a message that
> reads like a fresh problem rather than an incomplete instruction. Set both.

## Bringing a server up

1. **Apply.** Terraform creates the VM, the DNS alias record, and runs the setup script.

2. **Delegate the zone** — one time, ever, and only for a new zone. Take the
   `tailnet_dns_zone_nameservers` output and create matching `NS` records for the delegated
   label at Porkbun, where `autobutler.org` is served. Until this exists the zone answers
   for nobody and certbot cannot issue.

3. **Re-run certbot** if the first boot beat DNS to it. Certificate failure at boot is
   non-fatal by design — the host serves plain HTTP and keeps going, because the
   alternative is a VM that fails provisioning over a DNS record that could not have
   existed yet:

   ```bash
   sudo certbot --nginx -d network.quark.ts.autobutler.org \
     --non-interactive --agree-tos -m admin@autobutler.org --redirect
   ```

4. **Create the API key and the shared secret**, then start the service:

   ```bash
   sudo headscale apikeys create --expiration 9999d      # copy the output
   sudo tee /etc/quark/provisioning.env >/dev/null <<'ENV'
   HEADSCALE_API_KEY=<the key from above>
   PROVISIONING_SECRET=<a long random string>
   ENV
   sudo chmod 600 /etc/quark/provisioning.env
   sudo systemctl restart quark-provisioning
   sudo systemctl status quark-provisioning
   ```

   The API key cannot be generated before headscale first runs, which is why this is a
   post-boot step and not something the module can do.

5. **Create the tailnet user** headscale registers nodes under:

   ```bash
   sudo headscale users create quark
   ```

## Enrolling a node

Clients call the provisioning service, which mints a headscale pre-auth key on their behalf
so the headscale API key never leaves the server:

```http
POST http://network.quark.ts.autobutler.org:8081/provision
X-Provisioning-Secret: <PROVISIONING_SECRET>
```

The shared secret is what authorises that call, so it is a real credential: it is the only
thing between a caller and a valid tailnet enrolment key. It belongs in quark's secret
handling, never in a committed config.

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
