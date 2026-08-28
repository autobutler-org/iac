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
dig +short A network.quark.ts.autobutler.org
curl -sI https://network.quark.ts.autobutler.org | head -1
```

The `NS` lookup must return the Azure nameservers from that output. If it returns nothing, the one-time
delegation at Porkbun has not been done and nothing below can work -- see `bootstrap/README.md`.

**A TLS failure here on first boot is expected, not a bug.** certbot runs during VM provisioning, which happens
before the DNS record can possibly have propagated. The setup script treats that as a warning by design, so the
host serves plain HTTP and keeps going. Re-run certbot per `modules/headscale/README.md` rather than debugging
headscale.

## Layer 1 -- headscale is serving

```bash
curl -s https://network.quark.ts.autobutler.org/key\?v=106
curl -s https://network.quark.ts.autobutler.org/health
```

`/key` returns the server's noise public key. Getting one back proves TLS, nginx, and the proxy to
`127.0.0.1:8080` all work -- the cheapest signal that the whole front end is healthy.

## Layer 2 -- the service on the box

```bash
ssh quark@network.quark.ts.autobutler.org
sudo systemctl status headscale
sudo journalctl -u headscale -n 50 --no-pager
```

The setup script's own output is worth reading when something is wrong, since it runs at boot and its failures do
not surface anywhere else:

```bash
sudo cat /var/log/azure/custom-script/handler.log
```

## Layer 3 -- a real node joins

This is the actual proof. Create a user and a short-lived key on the server:

```bash
sudo headscale users create quark
sudo headscale preauthkeys create --user quark --expiration 1h
```

> The `--user` flag has changed across headscale releases -- it has taken a name and an ID at different points.
> Check `headscale preauthkeys create --help` on the host rather than trusting this line.

Then join from anywhere. A container is cleanest: nothing is installed on your machine, and the node is gone when
it exits.

```bash
docker run -it --rm --cap-add=NET_ADMIN --device /dev/net/tun tailscale/tailscale \
  tailscale up --login-server=https://network.quark.ts.autobutler.org --authkey=<key>
```

Back on the server:

```bash
sudo headscale nodes list
```

A node in that list means coordination, key exchange, and MagicDNS assignment all work. **That is headscale
working**, with zero quark code involved.

## Layer 4 -- the provisioning service

This is quark's binary, not headscale, and it is a separate question. It will not start at all until both
secrets exist -- `cmd/provisioning/main.go` calls `log.Fatal` on each:

```bash
sudo systemctl status quark-provisioning
curl -s -X POST http://network.quark.ts.autobutler.org:8081/provision \
  -H "X-Provisioning-Secret: <secret>" -d '{}'
```

If layer 3 passes and layer 4 fails, the tailnet is fine and the problem is quark's service. See
`modules/headscale/README.md` for the two variables it needs.

## Known: UDP 3478 answers nothing

The NSG opens 3478 for STUN, but the headscale config sets `derp.server.enabled: false` and uses Tailscale's
public DERP map, so nothing on the host binds that port. A probe against it failing is not a fault.

The rule is inert as things stand. Removing it, or enabling the embedded DERP server so peers can relay through
this host instead of Tailscale's, is a real decision about how peer traffic should flow -- not a cleanup. Left
as-is deliberately until that decision is made.
