# How the Frontend Is Served — Local vs. `dev`

**Status:** Reference

Two different setups answer "how is the frontend served," depending on where
you're running it. Both use the **same image** (`frontend/Dockerfile`: Vite
build → static files served by nginx), but the surrounding infrastructure and
how `/api` calls are routed differ.

---

## Local (`docker compose up`)

```
Browser ──► nginx :80 (container) ──┬─► "/"      static SPA (dist/), SPA fallback
                                     └─► "/api/*" proxy_pass to backend (same Docker network)
```

- `frontend/Dockerfile` builds the Vite app, then copies `dist/` into an
  `nginx:1.27-alpine` image alongside `nginx.conf.template`.
- nginx serves static files on `/` (`try_files $uri $uri/ /index.html` for
  SPA routing) and reverse-proxies `/api/` to `${BACKEND_URL}` — the backend
  container's service name on the shared `starflix-net` Docker bridge network.
- The browser only ever talks to nginx; nginx does the cross-container hop.

## `dev` environment (Terraform-provisioned)

```
Browser ──HTTP──► ALB (frontend) :80  ──► ECS task (nginx + static SPA)
Browser ──HTTP──► ALB (backend)  :4000 ──► ECS task (Express API)   [direct, CORS-allowed]
```

Same nginx image, but:

- **Runs as an ECS service** (`ecs_service_frontend`, EC2 launch type) instead
  of a `docker compose` container, sitting behind its own public
  Application Load Balancer (`aws_lb.frontend`).
- **No CDN/DNS layer in dev** — `terraform.tfvars` sets `enable_dns = false`
  and `enable_cloudfront = false`, so the `cloudfront` and `dns` modules
  aren't created (`count = 0`). Traffic hits the frontend ALB's raw DNS name
  over plain HTTP; there's no Route 53 record or TLS termination yet.
- **The nginx `/api/` proxy is bypassed.** The frontend container's ECS task
  still gets a `BACKEND_URL` env var and the nginx config still has the
  `location /api/` block, but neither is used by the SPA in dev. Instead,
  `VITE_API_URL` is baked into the Vite build at CI time
  (`modules/codebuild/main.tf`) pointing at the **public backend ALB URL**,
  so the browser calls the backend directly rather than hairpinning through
  nginx inside the VPC. This was a deliberate fix, not the original design —
  see [`frontend-backend-504-fix.md`](frontend-backend-504-fix.md) for the
  root cause (an internet-facing ALB can't be reached via NAT hairpin from a
  private-subnet nginx).
- **Deploys via CodeBuild**, not a manual `docker compose up --build`: a push
  to `main` touching `frontend/` triggers a webhook → CodeBuild builds the
  image (with `VITE_API_URL` baked in) → pushes to ECR → forces a new ECS
  deployment.

## Where this fits in the bigger picture

- Full target architecture (with CloudFront + custom domain, for stage/prod)
  and the current dev snapshot: [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
  (§0 and §10).
- `enable_dns` / `enable_cloudfront` flag behavior: [`dns-and-tls.md`](dns-and-tls.md).
- Root cause for why dev bypasses the nginx `/api` proxy: [`frontend-backend-504-fix.md`](frontend-backend-504-fix.md).
