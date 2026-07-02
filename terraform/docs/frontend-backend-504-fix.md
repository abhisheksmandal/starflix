# Frontend 504 — Root Cause & Fix (Browser-Direct Backend Calls)

**Date:** 2026-07-02
**Environment:** `dev` (`ap-south-1`, account `882282737240`)
**Status:** Resolved

---

## Symptom

Loading the frontend URL returned **HTTP 504 Gateway Timeout** for any content
that required the API. The page shell loaded, but featured/category data never
appeared.

```
http://starflix-dev-alb-frontend-241601509.ap-south-1.elb.amazonaws.com
```

### Isolating the failing hop

| Request                                             | Result                |
|-----------------------------------------------------|-----------------------|
| Backend ALB directly (from the public internet)     | `HTTP 200` (~0.05s)   |
| Frontend ALB `GET /` (static SPA shell)             | `HTTP 200` (~0.05s)   |
| Frontend ALB `GET /api/...` (nginx-proxied)         | hangs ~40s → **504**  |

So the backend was healthy and the frontend was serving static assets. Only the
**nginx `/api` proxy hop** timed out.

---

## Root Cause — internet-facing ALB hairpin from a private subnet

The frontend served the SPA and proxied `/api/*` to the backend via nginx:

```nginx
location /api/ {
    proxy_pass ${BACKEND_URL};   # http://<backend-alb-dns>:4000
}
```

The network layout:

- The frontend runs in an ECS container on an **EC2 instance in a private
  subnet** (`10.0.12.128`, no public IP).
- The backend ALB is **internet-facing** (`internal = false`, placed in the
  public subnets).
- An internet-facing ALB's DNS name **always resolves to public IPs** — even
  from inside the VPC (e.g. `3.7.237.212`, `35.154.8.174`).

When nginx tried to reach those public IPs, the traffic had to leave the private
subnet through the **NAT gateway**, hairpin out to the internet, and come back to
an ALB whose nodes live in the *same VPC*. AWS does not route this reliably, so
the TCP connection never completed → nginx timed out → 504.

This is why it worked from a laptop on the real internet but not from nginx
inside the VPC.

```
Browser ──▶ Frontend ALB ──▶ nginx (private subnet)
                                 │  proxy_pass http://backend-alb:4000
                                 ▼
                          NAT ▶ IGW ▶ (backend ALB public IP)  ✗ hairpin hangs
```

---

## Fix — Option A: the browser calls the backend directly

Instead of nginx proxying API calls from inside the VPC, the **public backend
URL is baked into the SPA at build time** (`VITE_API_URL`). API calls then
originate from the **user's browser on the public internet**, which can reach the
internet-facing backend ALB normally — there is no in-VPC hairpin at all.

```
Browser ──▶ Frontend ALB ──▶ static SPA
Browser ──▶ Backend ALB :4000  (direct, public → public)  ✓
```

Both ALBs stay **public**, which also keeps the backend ready to be consumed as a
standalone CMS API by other clients in the future.

### How the SPA picks up the URL

`frontend/src/api/client.js`:

```js
const BASE_URL = import.meta.env.VITE_API_URL || "";
// empty  -> relative "/api/..."  (old nginx-proxy behavior)
// set    -> "http://<backend-alb>:4000/api/..."  (browser-direct)
```

`VITE_API_URL` is a **Vite build-time** variable — it must be present when
`npm run build` runs, and gets compiled into the static JS bundle.

---

## Changes Applied

| File | Change |
|------|--------|
| `frontend/buildspec.yml` | Pass `--build-arg VITE_API_URL="$VITE_API_URL"` to `docker build`. |
| `terraform/modules/codebuild/variables.tf` | New `frontend_api_url` variable. |
| `terraform/modules/codebuild/main.tf` | Inject `VITE_API_URL` as a build env var on the frontend CodeBuild project. |
| `terraform/environments/dev/main.tf` | Set `frontend_api_url = "http://${module.alb.backend_alb_dns_name}:${var.backend_port}"`. |

The `frontend/Dockerfile` already accepted the build arg:

```dockerfile
ARG VITE_API_URL=""
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build
```

### CORS

Because the browser now makes a **cross-origin** request (frontend ALB origin →
backend ALB origin), the backend must allow it. This was already wired:

- Backend CORS (`backend/src/index.js`): `origin: process.env.FRONTEND_URL`, `methods: ["GET"]`.
- The backend ECS task sets `FRONTEND_URL = http://<frontend-alb-dns>`, which
  matches the browser origin exactly.
- The SPA only issues `GET` requests, which the CORS policy permits.

---

## Deploy / Apply Steps

1. Apply Terraform to set the new CodeBuild env var:
   ```bash
   cd terraform/environments/dev
   terraform apply
   ```
2. Commit & push to `main`. The CodeBuild webhook rebuilds the frontend image
   with `VITE_API_URL` baked in and force-deploys the ECS service.

---

## Verification

```bash
FE="starflix-dev-alb-frontend-241601509.ap-south-1.elb.amazonaws.com"
BE="starflix-dev-alb-backend-189641992.ap-south-1.elb.amazonaws.com"

# 1. Backend URL is compiled into the SPA bundle
JS=$(curl -s "http://$FE/" | grep -oE '/assets/[^"]+\.js' | head -1)
curl -s "http://$FE$JS" | grep -oE "http://starflix-dev-alb-backend[^\"']*" | head -1
# -> http://starflix-dev-alb-backend-189641992.ap-south-1.elb.amazonaws.com:4000

# 2. CORS allows the frontend origin
curl -s -D - -o /dev/null -H "Origin: http://$FE" \
  "http://$BE:4000/api/content/featured" | grep -i access-control-allow-origin
# -> Access-Control-Allow-Origin: http://starflix-dev-alb-frontend-...
```

Both checks passed and the frontend loads content correctly.

---

## Follow-ups / Known Limitations

- **Dead nginx config:** the `location /api/` proxy block in
  `frontend/nginx.conf.template` and the `BACKEND_URL` env on the frontend task
  are now unused (harmless). They can be removed for cleanliness.
- **HTTPS / mixed content:** everything currently runs over HTTP, so it works.
  When the frontend is served over HTTPS, browsers will **block** HTTP calls to
  the backend. At that point:
  - Add an ACM cert + `443` listener to the **backend** ALB.
  - Update `frontend_api_url` to `https://...` and rebuild the frontend.
- **ALB IP churn:** not relevant anymore for the frontend (the browser resolves
  the backend DNS itself), but keep in mind internet-facing ALB IPs are dynamic.

---

## Alternatives Considered (not chosen)

| Option | Why not chosen |
|--------|----------------|
| Make backend ALB internal | Backend must stay public (future CMS API). |
| Second internal ALB for backend | Extra ALB cost/complexity; browser-direct is simpler. |
| Move ECS instances to public subnets | Exposes compute; weakens the private-subnet posture. |
| Service discovery (Service Connect / Cloud Map) | Requires `bridge`→`awsvpc` migration; larger change. |
