# Verifying headscale

How to prove the headscale server this directory stands up actually works, **without any change to the quark
codebase**.

That independence is the point. quark's `pkg/util/remoteutil/remoteutil.go` hardcodes a `defaultControlURL`, but
the stock Tailscale client accepts `--login-server`, so a real node can join this tailnet before quark knows the
server exists. If you wait for the quark PR to test the infrastructure, a failure could be in either repo and you
will not know which.

Work outward. Each layer assumes the one before it passed, so stop at the first failure rather than reading on --
a symptom at layer 3 is usually a cause at layer 0.

## Layer 0 -- DNS and TLS

No VM access needed, and the most common place for this to be "broken" when nothing is wrong.

```bash
terraform -chdir=azure/autobutler output tailnet_dns_zone_nameservers
dig +short NS ts.autobutler.org
dig +short A quark.ts.autobutler.org
curl -sI https://quark.ts.autobutler.org | head -1
```

The `NS` lookup must return the Azure nameservers from that output. If it returns nothing, the one-time
delegation at Porkbun has not been done and nothing below can work -- see `bootstrap/README.md`.

**A TLS failure here on first boot is expected, not a bug.** certbot runs during VM provisioning, which happens
before the DNS record can possibly have propagated. The setup script treats that as a warning by design, so the
host serves plain HTTP and keeps going, and `headscale-certbot.timer` retries every 20 minutes until a
certificate exists. If it stays plain HTTP well after DNS resolves, read `journalctl -u headscale-certbot` on the
host rather than debugging headscale.

## Layer 1 -- headscale is serving

```bash
curl -s https://quark.ts.autobutler.org/key\?v=106
curl -s https://quark.ts.autobutler.org/health
```

`/key` returns the server's noise public key. Getting one back proves TLS, nginx, and the proxy to
`127.0.0.1:8080` all work -- the cheapest signal that the whole front end is healthy.

## Layer 2 -- the service on the box

```bash
ssh quark@quark.ts.autobutler.org
sudo systemctl status headscale
sudo journalctl -u headscale -n 50 --no-pager
```

The setup script's own output is worth reading when something is wrong, since it runs at boot and its failures do
not surface anywhere else:

```bash
sudo cat /var/log/azure/custom-script/handler.log
```

## Layer 3 -- a real node joins

This is the actual proof. Create a throwaway user and mint a short-lived key for it on the server:

```bash
sudo headscale users create verify-layer-3
sudo headscale users list                     # note the ID of verify-layer-3
sudo headscale preauthkeys create --user <id> --expiration 1h
```

> In v0.28.0 and v0.29.4 `--user` takes the numeric user ID, not the name. It has taken a name at other points, so check
> `headscale preauthkeys create --help` on the host after a version bump.

Then join from anywhere. A container is cleanest: nothing is installed on your machine, and the node is gone when
it exits.

```bash
docker run -it --rm --cap-add=NET_ADMIN --device /dev/net/tun tailscale/tailscale \
  tailscale up --login-server=https://quark.ts.autobutler.org --authkey=<key>
```

Back on the server:

```bash
sudo headscale nodes list
```

A node in that list means coordination, key exchange, and MagicDNS assignment all work. **That is headscale
working**, with zero quark code involved. Delete the node, then `sudo headscale users destroy --identifier <id>`.

## Layer 4 -- the provisioning service

This is quark's binary, not headscale, and it is a separate question. Nothing about it is set up by hand. The
endpoint takes no secret. Its one setting, the household HMAC key `PROVISIONING_HOUSEHOLD_KEY`, is generated on the
VM on first run, into `/var/lib/headscale/provisioning-household.key`, and never touches Terraform. The setup
script writes it into `/etc/quark/provisioning.env` and starts the service. There is no headscale API key: the
service mints keys through the local `headscale` CLI.

Check the service, then enroll from anywhere:

```bash
sudo systemctl status quark-provisioning
curl -X POST https://quark.ts.autobutler.org/provision \
  -H 'Content-Type: application/json' \
  -d '{"device_id":"smoke-test"}'
```

A `200` carries `auth_key`, `household` and `household_token`. Each first enrollment creates a new headscale user,
the household, so destroy the smoke-test one afterward on the VM:

```bash
sudo headscale users list                     # note the ID of the household the curl returned
sudo headscale users destroy --identifier <id>
```

A first enrollment is limited to five per hour per IP, so do not loop this. The old shared `quark` user may still
be listed: nodes enrolled before the households release live under it until they re-enroll. Leave it alone.

If layer 3 passes and layer 4 fails, the tailnet is fine and the problem is quark's service. See
`modules/headscale/README.md` for what it needs and where each value comes from.

## Layer 5 -- households are isolated

The policy is one grant: a node reaches the nodes of its own headscale user on `tcp:80` and nothing else. Confirm
headscale loaded it and runs 0.29.2 or later:

```bash
headscale version
sudo headscale policy get
```

Then prove it with two users. Mint a key for each (layer 3), then join three containers: two under `house-a`, one
under `house-b`. On the first `house-a` node, listen on 80 and on 8080:

```bash
sudo headscale users create house-a
sudo headscale users create house-b
docker exec -d <a1> nc -l -p 80
docker exec -d <a1> nc -l -p 8080
```

From the second `house-a` node, port 80 connects and 8080 times out. From the `house-b` node, 80 times out too.
Each listener takes one connection, so restart it between attempts:

```bash
docker exec <a2> sh -c 'nc -w 3 <a1-ip> 80 </dev/null && echo open'
docker exec <a2> sh -c 'nc -w 3 <a1-ip> 8080 </dev/null && echo open'
docker exec <b1> sh -c 'nc -w 3 <a1-ip> 80 </dev/null && echo open'
```

Delete the test nodes and users afterward. headscale will not delete a user that still has nodes, so delete the
nodes first.

## Known: UDP 3478 answers nothing

The NSG opens 3478 for STUN, but the headscale config sets `derp.server.enabled: false` and uses Tailscale's
public DERP map, so nothing on the host binds that port. A probe against it failing is not a fault.

The rule is inert as things stand. Removing it, or enabling the embedded DERP server so peers can relay through
this host instead of Tailscale's, is a real decision about how peer traffic should flow -- not a cleanup. Left
as-is deliberately until that decision is made.
