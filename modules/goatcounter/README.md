# `goatcounter` module

Stands up a self-hosted [GoatCounter](https://www.goatcounter.com) server on a single Azure VM. It counts page views
for the org's static sites without cookies, and every count stays on our own infrastructure instead of going to
goatcounter.com.

|             | autobutler                                                                      |
| ----------- | ------------------------------------------------------------------------------- |
| Dashboard   | `https://goatcounter.cloud.autobutler.org/`                                     |
| Beacon      | `https://goatcounter.cloud.autobutler.org/count`                                |
| Admin login | `admin@autobutler.org`, password in `/etc/goatcounter/admin-password` on the VM |
| Backups     | `https://stautobutlergoatcounter.blob.core.windows.net/backups`                 |
| VM          | `goatcounter` in resource group `goatcounter`                                   |

## What the module produces

- An Arm Ubuntu 24.04 VM (`Standard_B2pts_v2`, the headscale host's size), with a system-assigned managed identity
  and Entra ID SSH (`AADSSHLoginForLinux`).
- A static public IP, a network security group that opens 22, 80 and 443 only, and an alias A record
  `goatcounter.cloud.autobutler.org` in the `cloud` zone.
- A setup script, run through the CustomScript extension, that installs GoatCounter, creates the site, and runs
  it under systemd. A changed script re-runs in place, so a version bump never replaces the VM.
- A private storage account with shared keys off and a `backups` container, a lifecycle rule that deletes
  backups after 90 days, and Storage Blob Data Contributor on that container for the VM's identity.

## How GoatCounter runs

The setup script downloads the official release binary, `goatcounter-<version>-linux-arm64.gz` from
[the release page](https://github.com/arp242/goatcounter/releases). GoatCounter publishes no checksum file, so the
SHA-256 of that asset is pinned in `azure/autobutler/variables.tf` next to the version. The script refuses a
download that does not match.

It runs as the unprivileged `goatcounter` user, with `CAP_NET_BIND_SERVICE` for ports 80 and 443:

```text
goatcounter serve -db sqlite+/var/lib/goatcounter/db.sqlite3 \
  -listen :443 -tls tls,rdr,acme:/var/lib/goatcounter/acme-secrets -automigrate
```

These are the production flags from GoatCounter's README and `goatcounter help listen` at v2.7.0. GoatCounter
serves TLS itself, redirects port 80 to 443, and gets its certificate from Let's Encrypt. There is no reverse
proxy. The ACME client asks for a certificate only for a host that is a site in the database. It asks on the first
HTTPS request for that host, and it answers the HTTP-01 challenge on port 80. That is why port 80 stays open.

The database is SQLite on the VM's OS disk, not on Azure Files: SQLite's locking does not hold over SMB. Because
the disk holds the data, the VM has `prevent_destroy`, as the headscale VM does.

## The admin password

Terraform never sees the password. It would land in state and in the planfile artifact if it did. The setup
script creates the site before GoatCounter first starts:

```text
goatcounter db create site -createdb -db sqlite+/var/lib/goatcounter/db.sqlite3 \
  -vhost goatcounter.cloud.autobutler.org -user.email admin@autobutler.org -user.password <generated>
```

The password is `openssl rand -base64 24`, generated on the VM and written to `/etc/goatcounter/admin-password`,
which is owned by root with mode 0600. The script generates it only when the site does not exist yet, so a re-run
never changes it. Creating the site up front also closes GoatCounter's first-run web wizard, which would otherwise
let whoever reached the server first create the site.

If you change the password on the dashboard, the file goes stale. Update or delete it by hand. GoatCounter has no
SMTP configured, so a "forgot password" email is written to the service's journal instead of being sent.

## Bringing it up

### Prerequisite: the `cloud` delegation

The NS records for `cloud` must exist at Porkbun, or `goatcounter.cloud.autobutler.org` doesn't resolve and Let's
Encrypt cannot issue. The `ONE-TIME MANUAL STEP` comment on the `cloud` zone in
[`azure/autobutler/dns.tf`](../../azure/autobutler/dns.tf) describes it. If `schmeide.cloud.autobutler.org`
already works, the delegation is done.

### 1. Read the password

SSH in with Entra ID. You need the Virtual Machine Administrator Login role on the VM for `sudo`:

```bash
az ssh vm --resource-group goatcounter --name goatcounter
sudo cat /etc/goatcounter/admin-password
```

Then log in at `https://goatcounter.cloud.autobutler.org/` as `admin@autobutler.org`. The first HTTPS request may take a
few seconds while the certificate is issued.

### 2. Point the sites at it

Both sites send `navigator.sendBeacon("https://goatcounter.cloud.autobutler.org/count?p=<host><path>&r=<referrer>")`.
GoatCounter's `/count` accepts the POST that `sendBeacon` makes. Change the host in each site's page view code
from `autobutler.goatcounter.com` to `goatcounter.cloud.autobutler.org`. Counts on goatcounter.com are not moved over.
To keep them, export them there and import them with `goatcounter import` on the VM.

## Backups

`goatcounter-backup.timer` runs `/usr/local/sbin/goatcounter-backup` once a day, within an hour after midnight UTC.
It is `Persistent`, so a run missed while the VM was off happens at the next boot. The script:

1. Copies the live database with `sqlite3 .backup`, which is consistent while GoatCounter keeps writing.
2. Runs `PRAGMA integrity_check` on the copy, and uploads nothing if it fails.
3. Gzips it and uploads it as a new blob, `db-<UTC timestamp>.sqlite3.gz`, with a single Put Blob call.

It authenticates with the VM's managed identity: an IMDS token for `storage.azure.com`, passed to curl through a
0600 header file. The account has shared keys off, so there is no key anywhere. The lifecycle rule deletes a
backup after `backup_retention_days`, 90 by default, and soft delete keeps a deleted blob recoverable for 7 days.

The role assignment can take a few minutes to take effect after the first apply. The setup script leaves the first
backup to the timer for that reason. To run one now and check it:

```bash
sudo systemctl start goatcounter-backup.service
journalctl -u goatcounter-backup -n 20
```

A version bump also leaves a local copy, `/var/lib/goatcounter/db.sqlite3.goatcounter-<old version>.bak`, taken
before `-automigrate` runs the new version's migrations.

### Restore

```bash
# On your machine: download a backup with your own Entra ID login. You need Storage Blob Data Reader or above on
# the account; terraform grants only the VM.
az storage blob download --auth-mode login --account-name stautobutlergoatcounter \
  --container-name backups --name db-<timestamp>.sqlite3.gz --file db.sqlite3.gz

# On the VM, after copying the file there:
sudo systemctl stop goatcounter
gunzip db.sqlite3.gz
sudo rm -f /var/lib/goatcounter/db.sqlite3-wal /var/lib/goatcounter/db.sqlite3-shm
sudo install -m 0640 -o goatcounter -g goatcounter db.sqlite3 /var/lib/goatcounter/db.sqlite3
sudo systemctl start goatcounter
```

On a replacement VM the setup script has already created an empty site and a new password by the time you can log
in. Restore over it the same way. The restored database keeps its own admin user and password hash, so the password
is the one from before, and `/etc/goatcounter/admin-password` on the new VM no longer matches. Delete that file.

## Upgrading

Change `goatcounter_version` and `goatcounter_sha256` in `azure/autobutler/variables.tf` together and merge. Get
the checksum from the release asset:

```bash
curl -fsSL https://github.com/arp242/goatcounter/releases/download/<version>/goatcounter-<version>-linux-arm64.gz \
  | sha256sum
```

Renovate does not track the version. It would bump the version without the checksum, and that apply would fail on
the VM. Read the release notes in GoatCounter's `CHANGELOG.md` before moving a major version.

## Cost

At eastus list prices, about $11.50 a month:

| Item                                     | Monthly |
| ---------------------------------------- | ------- |
| VM, `Standard_B2pts_v2`                  | $6.13   |
| Standard static public IP                | $3.65   |
| OS disk, Standard HDD, 30 GiB (S4 tier)  | $1.54   |
| Backups, Cool LRS, a few MiB a day       | < $0.10 |
| DNS record, in the existing `cloud` zone | < $0.05 |

Outbound traffic is the beacon's empty responses and the dashboard, well inside the free egress allowance.

## Operating notes

- `journalctl -u goatcounter` shows the server's log, including ACME issuance and migrations.
- `/var/log/azure/custom-script/handler.log` and the extension status show the setup script's last run.
- `/usr/local/lib/goatcounter/` holds every installed version, and `/usr/local/bin/goatcounter` is a symlink to
  the current one. To roll back by hand, repoint the symlink, restore the `.bak` copy, and restart. Then set the
  old version in terraform, or the next apply moves forward again.
- GoatCounter rate-limits `/count` to 4 requests a second per IP address by default, which is far above what a person
  browsing either site sends.
