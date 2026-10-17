# 📦 Applications Architecture

This directory houses application-layer definitions, serverless edge functions, and integration bridge manifests for the homelab infrastructure.

---

## 🏛️ Architecture Boundary

In accordance with repository separation of concerns:

1. **Docker Compose Stacks:**
   - Multi-container application workloads (e.g., DNS filtering, monitoring hubs, workflow automation, LLM gateways) are maintained in external dedicated service repositories (e.g., `homelab-services`).
   - This keeps infrastructure provisioning and day-to-day application compose updates decoupled.
2. **Serverless Edge Code (Cloudflare Workers):**
   - Cloudflare Workers, edge routes, and lightweight serverless functions deployed alongside Cloudflare DNS/WAF infrastructure reside in this directory (`apps/`).
3. **Bridge Manifests:**
   - Any declarative bridges connecting OpenTofu outputs to service inputs are documented or templated here.

---

## 🛠️ Tooling & Quality Gates

Edge scripts and TypeScript/JavaScript functions in `apps/` are linted via **Oxlint** (`mise run check:general`) and formatted via **Oxfmt** as enforced by Lefthook pre-commit hooks.
