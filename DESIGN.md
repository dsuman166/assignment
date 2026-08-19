# DESIGN.md

## 1. Why I built it this way

**Kind, provisioned with Terraform**
I went with Kind because it runs real, unmodified Kubernetes inside Docker — not a stripped-down variant like K3s. It's fast to spin up and tear down, which matters when you're iterating locally, but it still behaves like a real cluster, so what I learn here carries over to something like AKS later.

I used Terraform to create the cluster instead of just running `kind create cluster` by hand. The reasoning is simple: if the cluster config lives in a file, it's repeatable and I'm not relying on memory or shell history to rebuild it. It's also the same workflow (`terraform apply`) I'd use against Azure later — just a different provider.

**Flask + Postgres**
A small Flask app is enough to prove a real two-tier setup — a stateless service talking to a stateful database — without the app itself getting in the way of the Kubernetes/Docker parts, which are the actual point of the assignment. Postgres is a normal, boring, well-understood database, so anything I learn about PVCs, backups, or scaling here maps directly onto a real project.

**ConfigMap vs Secret**
Non-sensitive settings (DB host, DB name, a greeting string) go in a ConfigMap. The DB password goes in a Secret. It's the standard split, and it keeps the one sensitive value separate so it's obvious what needs tighter access control later — even though, worth being honest about, a raw Kubernetes Secret is just base64, not encryption. More on that in the trade-offs section.

**metrics-server, not a full Prometheus stack**
metrics-server is one lightweight Deployment and it's all you need for `kubectl top nodes/pods` to work. A full Prometheus + Grafana setup would mean extra persistent volumes, scrape configs, and dashboards — overkill for a single-node demo cluster. I also used k9s as a terminal UI to actually watch pods/deployments/PVCs live, since it needs zero setup beyond a kubeconfig.

## 2. Taking this from local to production (AKS)

| Local (this repo) | Production (AKS) |
|---|---|
| One node running everything | Multiple node pools across Availability Zones, managed HA control plane |
| Postgres running as a pod with a local PVC | Managed Azure Database for PostgreSQL (HA + backups handled for you, and it's no longer a single point of failure inside the cluster) |
| NodePort | LoadBalancer or an Ingress controller with TLS in front |
| Secret committed in the repo | Azure Key Vault + Secrets Store CSI Driver — no plaintext secrets anywhere in Git |
| metrics-server only | Real observability: Azure Monitor, Prometheus/Grafana, log aggregation, alerting |
| Terraform + Kind provider | Same Terraform workflow, just the `azurerm` provider instead |
| `kubectl apply` by hand | GitOps (Argo CD/Flux) applying changes automatically from Git |
| One web replica | HorizontalPodAutoscaler, PodDisruptionBudget, cluster autoscaler |
| CI builds and tests | CI pushes to Azure Container Registry, CD promotes through dev → staging → prod with approvals |

The big shift is pulling the database out of the cluster entirely. Locally, everything — including Postgres — lives inside Kind. In production, the database becomes a managed service with its own failover and backups, and the cluster is left to focus on stateless things that are easy to scale horizontally.

## 3. The single point of failure

The obvious one here: it's all running on one node. If that machine or Docker itself goes down, the API server and every pod — web and database — go down with it. There's nowhere else for anything to reschedule to.

It gets worse with Postgres specifically: it's a single pod on a single PVC that can only be mounted by one pod at a time. If that pod dies, Kubernetes has to fully stop it before anything can take its place, so there's a real gap in availability — and if the volume itself gets corrupted, there's no replica and no backup to fall back on.

Locally, I'm just accepting this — a single-node cluster is what the assignment asked for, and going further (backups, replicas) would add complexity for very little benefit at this scale. If I wanted a cheap partial fix even locally, I'd cron a `pg_dump` to somewhere outside the cluster so at least data loss is bounded.

In production the fix is straightforward: move Postgres to Azure Database for PostgreSQL with zone-redundant HA and automated backups, and run AKS across at least 3 Availability Zones so no single VM or zone failure takes the cluster down. Spread the web replicas across nodes/zones with anti-affinity and a PodDisruptionBudget so a node drain doesn't take out all of them at once.

## 4. What I traded off to keep this local and simple

- **The Secret is committed to the repo.** In any real project this would get rejected outright — even a fake local-only password shouldn't be in git, it's a bad habit to normalize. I did it here purely so the manifests apply with zero extra setup.
- **metrics-server runs with `--kubelet-insecure-tls`.** Only needed because Kind's kubelets use self-signed certs. On a real cluster this flag would be an actual security hole.
- **Postgres storage is just Kind's default hostPath-backed StorageClass.** Fine for a demo, not something you'd trust with real data or real I/O needs.
- **One Postgres replica, one node overall.** No redundancy anywhere, on purpose — the whole point was to keep this runnable on a laptop or a free CI runner without needing a real cloud account.
- **No Prometheus/Grafana.** metrics-server gives point-in-time numbers but nothing historical, no alerting. Left out deliberately — the operational cost (extra volumes, scrape configs, dashboards) wasn't worth it for a single-node setup.
- **Postgres runs as a Deployment, not a StatefulSet.** Technically a StatefulSet is the "correct" primitive for a database, but with exactly one replica and `strategy: Recreate`, a Deployment behaves the same and is less to explain. Would switch to a StatefulSet immediately if I ever went to more than one Postgres replica.

## 5. A couple of real bugs I hit along the way

Two things broke during setup that are worth mentioning, because they're good examples of security settings colliding with how the app actually runs:

**gunicorn crash-looping under `readOnlyRootFilesystem: true`.** I'd locked the web container's filesystem read-only as a hardening measure, but gunicorn needs to write a small temp file per worker on startup. With nowhere writable, it crashed immediately every time. The fix wasn't to loosen the read-only setting — it was to mount a small `emptyDir` volume at `/tmp` specifically, so gunicorn gets the one writable path it needs and nothing else changes.

**metrics-server wouldn't go ready.** The patch I used to make metrics-server work with Kind's self-signed kubelet certs also changed its listening port without me realizing the container's declared port (used by the readiness/liveness probes) still expected the original one. First attempt had the server listening on one port while the probes checked another — pod ran, but never went "ready." Fixed by explicitly setting `--secure-port` to match the port Kubernetes was actually probing.

Both are decent illustrations of the same lesson: changing a config value doesn't mean you're done — you have to actually watch the pod come up and check it against what's really happening, not just assume the change did what you intended.
