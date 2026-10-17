# `schmeide-control` module

Stands up a [schmeide](https://github.com/autobutler-org/schmeide) control node on a single
Azure VM. The node runs `schmeide control`, which serves the GitHub App's webhook through
Caddy and runs the NATS server that runners pull jobs from.

|             | autobutler                                      |
| ----------- | ----------------------------------------------- |
| Webhook URL | `https://schmeide.cloud.autobutler.org/webhook` |
| NATS URL    | `tls://schmeide.cloud.autobutler.org:4222`      |
| Key Vault   | `kv-schmeide-control`                           |

## Bringing a node up

Terraform never holds a secret value, so a person does the steps below once, after the
first apply.

### Prerequisite: the `cloud` delegation

The NS records for `cloud` must exist at Porkbun. Without them,
`schmeide.cloud.autobutler.org` doesn't resolve, Caddy can't get a certificate, and NATS has
no certificate to serve. That step is described once, in the `ONE-TIME MANUAL STEP` comment
on the `cloud` zone in [`azure/autobutler/dns.tf`](../../azure/autobutler/dns.tf). If quark
already serves on `quark.cloud.autobutler.org`, the delegation is done.

### 1. Set the Key Vault secrets

Grant yourself secret access on the vault. The VM's own access policy is managed by
terraform, and a policy added by hand is left alone:

```bash
az keyvault set-policy --name kv-schmeide-control \
  --object-id "$(az ad signed-in-user show --query id -o tsv)" \
  --secret-permissions get list set
```

Then set the three secrets:

```bash
# The schmeide GitHub App's webhook secret. Step 2 sets the same value on the App.
az keyvault secret set --vault-name kv-schmeide-control --name webhook-secret \
  --value '<webhook secret>'

# The App's private key, the whole PEM as GitHub downloaded it.
az keyvault secret set --vault-name kv-schmeide-control --name github-app-private-key \
  --file ./schmeide.private-key.pem

# One '<steward login>:<token>' entry per steward, comma-separated, no spaces.
az keyvault secret set --vault-name kv-schmeide-control --name runner-tokens \
  --value 'octocat:a-token-for-octocat,hubot:a-token-for-hubot'
```

Until all three exist, `schmeide-control.service` on the VM fails and retries every 10
seconds. Every start reads the vault again, so the service comes up on its own once the last
secret is set. To watch it:

```bash
journalctl -u schmeide-control -f
```

### 2. Point the GitHub App at the webhook

In the schmeide App's settings (**autobutler-org** → **Settings** → **Developer settings** →
**GitHub Apps** → **schmeide** → **General**), under **Webhook**:

- **Active**: checked.
- **Webhook URL**: the `schmeide_control_webhook_url` output,
  `https://schmeide.cloud.autobutler.org/webhook`.
- **Webhook secret**: the same value as the `webhook-secret` secret. If the two differ,
  every delivery fails its signature check.

### 3. Point runners at NATS

Each runner connects with its steward's login and that steward's token from
`runner-tokens`. The NATS URL is the `schmeide_control_nats_url` output. Put the token in
the environment, so it stays out of the process list:

```bash
export SCHMEIDE_NATS_TOKEN='a-token-for-octocat'
schmeide runner --steward octocat --nats-url tls://schmeide.cloud.autobutler.org:4222
```

## On the VM

| Path                                    | What                                                      |
| --------------------------------------- | --------------------------------------------------------- |
| `/srv/schmeide/data`                    | The JetStream store, on the data disk, mounted at `/data` |
| `/srv/schmeide/caddy`                   | Caddy's certificates, on the data disk                    |
| `/etc/schmeide/control.env`             | Non-secret settings, rewritten by the setup script        |
| `/run/schmeide/`                        | Secrets fetched at each start, held in memory only        |
| `/usr/local/bin/schmeide-fetch-secrets` | The `ExecStartPre` that reads the vault                   |

The VM is disposable. Replacing it attaches the same data disk, and a new VM mounts it
without formatting it.
