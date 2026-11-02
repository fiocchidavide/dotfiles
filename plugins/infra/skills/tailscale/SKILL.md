---
name: tailscale
description: >-
  Inspect and change Davide's tailnet with the tailscale CLI and the Tailscale
  API: devices, Tailscale Services, serve config, the ACL policy, DNS. Use when
  a task touches Tailscale, such as a service that isn't reachable, adding a
  service, reviewing or editing the policy, or finding a device.
---

# Tailscale

There is no official MCP server for administering a tailnet, so this skill
uses the `tailscale` CLI and the REST API directly.

## Where the facts are

Read the handbook's `areas/homelab.md` (section Tailscale) first: the tailnet
name, how services are published, and the 1Password reference of the API
token. How the apps VM publishes its services is `homelab-apps/serve.sh` and
that repo's README.

## Read: do it freely

On this Mac:

```sh
tailscale status                    # peers, online state, exit nodes
tailscale status --json | jq '.Peer[] | {HostName, Online, TailscaleIPs}'
tailscale ping <host>               # direct or relayed, latency
tailscale serve status              # what this Mac shares (x serve)
tailscale whois <ip>                # which node and user an IP is
tailscale netcheck                  # NAT, DERP latency
```

The same commands run on a host over SSH (`ssh pve tailscale status`).

Through the API (`https://api.tailscale.com/api/v2`, tailnet `-` means the
token's own). Read the token into a variable and pass the header on stdin, so
it appears in no argv or environment, and never print it:

```sh
tok=$(op read "<reference from areas/homelab.md>")
ts_api() { printf 'Authorization: Bearer %s\n' "$tok" | curl -fsS -H @- "https://api.tailscale.com/api/v2/$1" "${@:2}"; }
ts_api tailnet/-/devices | jq '.devices[] | {hostname, lastSeen, tags}'
ts_api tailnet/-/acl -H 'Accept: application/hujson'     # the policy file
ts_api tailnet/-/dns/nameservers
```

## Change: ask first

Anything that changes the tailnet (policy, device authorization, tags, keys,
DNS, a host's `tailscale serve`) needs Davide's go-ahead, and so does any
change on a host (conventions). For the policy:

1. Fetch it as HuJSON and keep the `ETag` header (`-D -`).
2. Edit a copy in the scratchpad and show Davide the diff.
3. Validate: `ts_api tailnet/-/acl/validate -X POST -H 'Content-Type: application/hujson' --data-binary @policy.hujson`.
4. Write with `-X POST -H 'If-Match: "<etag>"'`, so a concurrent edit isn't
   overwritten.

A new Tailscale Service also needs the steps in `areas/homelab.md`
(`autoApprovers`, `serve.sh`).
