# Blank Frontend During Rolling Deploys — Root Cause & Fix

**Date:** 2026-07-09
**Environment:** all (`dev` / `recovery`, `ap-south-1`)
**Status:** Fix committed (`9012bf4`) — requires `terraform apply` + a frontend rebuild to take effect

---

## Symptom

While an ECS deployment was rolling out (new frontend tasks provisioning,
old ones draining), the frontend would intermittently go **blank white** —
not a 502/503 error page, just an empty `<div id="root">` with nothing
rendered. It self-resolved once the rollout finished, but recurred on every
deploy for some fraction of requests.

---

## Root Cause — SPA version skew across ALB targets

`deployment_maximum_percent = 200` / `deployment_minimum_healthy_percent = 50`
(`modules/ecs-service/main.tf`) deliberately keeps old and new frontend tasks
registered in the ALB target group **at the same time** while new tasks warm
up and pass health checks. The frontend target group
(`modules/alb/main.tf`) had no `stickiness` configured, so the ALB
round-robins every individual request — including `index.html` and its
follow-up asset requests — across whichever targets are currently healthy,
old or new, independently per request.

Vite fingerprints build output (`assets/index-<hash>.js`), so an old task and
a new task serve **different filenames**. A single page load could:

1. Get `index.html` from the **new** task (referencing `index-B2f9.js`), then
2. Have the browser's script request round-robin to the **old** task, which
   only has `index-A1c3.js` on disk → `404` on the module script.

React never mounts if its entry script 404s, leaving the root `<div>` empty —
the blank page.

```
Browser ──▶ ALB (no stickiness) ──▶ old task   (index.html: index-A1c3.js)
        └─▶ ALB (no stickiness) ──▶ new task   (GET /assets/index-B2f9.js) ✗ 404
```

A related but separate failure mode: `nginx.conf.template` set no
`Cache-Control` headers, so a browser tab left open across a deploy could
hold a **stale cached `index.html`** referencing bundle hashes that no
longer exist on *any* task once the old ones fully drain — same blank-page
symptom, but persisting until a hard refresh instead of just during the
rollout window.

---

## Fix

### 1. ALB session stickiness (`terraform/modules/alb/main.tf`)

Pin a browser to one task for the life of its session so its `index.html`
and asset requests can't be split across app versions:

```hcl
resource "aws_lb_target_group" "frontend" {
  # ...
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }
}
```

### 2. Cache headers (`frontend/nginx.conf.template`)

```nginx
# Content-hashed by Vite, safe to cache forever.
location /assets/ {
    add_header Cache-Control "public, max-age=31536000, immutable";
    try_files $uri =404;
}

location / {
    # Never serve a stale index.html referencing bundle hashes that no
    # longer exist on any task after a deploy finishes.
    add_header Cache-Control "no-cache";
    try_files $uri $uri/ /index.html;
}
```

`no-cache` (not `no-store`) lets the browser still revalidate via
conditional GET (nginx sends `ETag`/`Last-Modified` by default), so repeat
loads stay fast but never serve HTML without checking the server first.

---

## Changes Applied

| File | Change |
|------|--------|
| `terraform/modules/alb/main.tf` | Added `stickiness` block (`lb_cookie`, 1h duration) to the frontend target group. |
| `frontend/nginx.conf.template` | Added `/assets/` location with long-lived immutable caching; `no-cache` on the `/` (index.html) location. |

---

## Deploy / Apply Steps

1. Apply Terraform in each environment to create the ALB stickiness policy:
   ```bash
   cd terraform/environments/dev       # and/or recovery
   terraform apply
   ```
2. The `nginx.conf.template` change ships on the **next frontend CodeBuild
   run** (push to `main` touching `frontend/`, or trigger the CodeBuild
   project manually) — it's baked into the Docker image, not something
   `terraform apply` alone picks up.

---

## Verification

- During a rollout, repeatedly hard-refresh the frontend URL from the same
  browser and confirm no blank page / no 404s in devtools Network tab for
  `/assets/*.js`.
- Confirm the sticky cookie is set: `curl -sD - -o /dev/null http://<frontend-alb-dns>/ | grep -i set-cookie` should show an `AWSALB`/`AWSALBCORS` cookie once stickiness is applied.
- Confirm cache headers: `curl -sD - -o /dev/null http://<frontend-alb-dns>/ | grep -i cache-control` → `no-cache`; same request against `/assets/<hashed>.js` → `public, max-age=31536000, immutable`.

---

## Follow-ups / Known Limitations

- Stickiness only bounds the window to one browser session (1h cookie) —
  it doesn't fully eliminate skew for a session that spans a deploy that
  takes longer than the rollout to converge, but that's a far smaller
  window than "any request, any time during rollout."
- The dead `location /api/` proxy block in `nginx.conf.template` (see
  [`frontend-backend-504-fix.md`](frontend-backend-504-fix.md)) is unrelated
  to this fix and still just harmless dead config.
