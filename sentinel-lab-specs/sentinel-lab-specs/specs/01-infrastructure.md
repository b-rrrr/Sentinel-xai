# Spec 01 — Infrastructure (`infra`)

Read `00-ARCHITECTURE.md` §7 (trust boundaries) and §8 (hardware tiers) before starting. This spec covers Phases 0 and 1 of `BUILD_ORDER.md`.

## Goal

Stand up a 3-node k3s cluster on real hardware, with namespaces, RBAC, MetalLB, Traefik, and storage — nothing application-specific yet.

## Allowed paths

`infra/**`, `inventory/nodes.yaml`. Nothing else.

## Phase 0 — Node inventory & cluster bring-up

1. On each of the 3 physical machines, run and record real output (do not estimate):
   ```bash
   free -h; lscpu | grep -E "Model name|CPU\(s\)"; lsblk; ip -br a
   ```
2. Write the results into `inventory/nodes.yaml`:
   ```yaml
   nodes:
     - name: <hostname you choose>
       hardware: "<actual CPU model>"
       ram_gb: <real number>
       disk_gb: <real number>
       tier: <1|2|3, per ARCHITECTURE.md §8 rule — most RAM+disk = tier 1>
       static_ip: <reserved IP>
   ```
3. Reformat the Pentium laptop to Ubuntu Server LTS (same OS as the Xeons — do not mix distros across nodes, it complicates every later automation step).
4. Static IP + hostname + `/etc/hosts` entries on all 3 nodes, SSH key auth only, swap disabled, per standard Ubuntu Server headless hardening (update, disable password SSH, disable swap, NTP on).
5. Install k3s: the tier-1 node as `server` (control-plane), the other two as `agent`, joined via the node token. Disable the bundled `traefik` and `servicelb` at server install time (`--disable traefik --disable servicelb`) — Traefik and MetalLB are installed deliberately in Phase 1, not left as k3s defaults.

### Phase 0 acceptance tests

- [ ] `inventory/nodes.yaml` exists with real (not placeholder) values for all 3 nodes.
- [ ] `kubectl get nodes -o wide` shows all 3 nodes `Ready`.
- [ ] SSH password auth confirmed disabled on all 3 nodes (`sshd -T | grep passwordauthentication` returns `no`).

## Phase 1 — Networking, storage, namespaces, RBAC

1. Install MetalLB with a small reserved IP pool (outside the DHCP range) — see `00-ARCHITECTURE.md` §7 for why this must stay off any WAN-facing interface.
2. Install Traefik via Helm with `service.type=LoadBalancer` so it gets a MetalLB IP.
3. Storage: use k3s's built-in `local-path-provisioner` for v1. Do not install Longhorn/Ceph in this phase — that's an explicit later ADR decision if replication is actually needed, not a default.
4. Create namespaces exactly as named in `00-ARCHITECTURE.md` §9: `demo-app`, `telemetry`, `knowledge-base`, `classifier`, `fusion`, `dashboard`, `attack-sim`, `policy`, `data-layer`.
5. Apply a default-deny `NetworkPolicy` to `demo-app` and `attack-sim` namespaces (ingress and egress), then explicitly allow only: `demo-app` ingress from Traefik namespace; `attack-sim` egress to `demo-app` namespace only. **No namespace gets default internet egress.**
6. Create one ServiceAccount + Role per module namespace, scoped only to that namespace (no ClusterRole, no cluster-admin, ever — see `AGENT_INSTRUCTIONS.md`).

### Phase 1 acceptance tests

- [ ] `kubectl get svc -n traefik-system` shows an `EXTERNAL-IP` assigned by MetalLB (not `<pending>`).
- [ ] `kubectl get networkpolicy -n demo-app` shows a default-deny policy plus the explicit allow rule.
- [ ] A test pod deployed in `demo-app` cannot reach `8.8.8.8` (egress genuinely blocked) but can reach the Traefik ingress.
- [ ] `kubectl auth can-i --as=system:serviceaccount:demo-app:default create clusterroles` returns `no`.

## Do not

- Do not expose the Traefik LoadBalancer IP, k3s API server, or any node's SSH port to the router's WAN interface.
- Do not give any namespace's default ServiceAccount cluster-admin "to save time" — this is checked explicitly in acceptance tests above.
- Do not install a CNI swap (e.g., Cilium) in this phase without an ADR — Flannel + NetworkPolicy is the default; only revisit if a later phase genuinely needs L7 policy that Flannel can't express.
