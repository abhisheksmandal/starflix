# Enabling HTTPS with Cloudflare DNS

**Date:** 2026-07-06
**Environment:** `dev` (`ap-south-1`)
**Status:** Options — decision pending

---

## Overview

Starflix `dev` is currently served over **plain HTTP**:

| Service  | URL                                          |
|----------|----------------------------------------------|
| Frontend | `http://abhishek-frontend.1020dev.com`       |
| Backend  | `http://abhishek-backend.1020dev.com:4000`   |

Both hostnames are records in **Cloudflare DNS only** (grey cloud / DNS-only —
Cloudflare is not proxying traffic, just resolving names to the AWS ALBs).

This document explains what HTTPS requires, why the setup is on HTTP today, the
two problems that surface the moment the frontend goes HTTPS, and three concrete
options to choose from.

---

## What HTTPS actually requires

Three things must line up:

1. **A TLS certificate** for both hostnames, issued by a trusted CA.
2. **A TLS terminator** — something that decrypts HTTPS. This is either the
   **AWS ALB** or the **Cloudflare edge**.
3. **Domain-ownership validation** — to issue a cert, the CA requires a proof
   record in DNS. Because DNS lives in **Cloudflare**, that record is added in
   Cloudflare (not Route 53).

**Where the certificate is terminated (step 2) is the decision.** The three
options below differ only on that point.

---

## Why the setup is on HTTP today

The Terraform **already contains** a complete HTTPS path:

- An HTTPS listener on `:443` (`modules/alb/main.tf` — `aws_lb_listener.frontend_https`)
- An HTTP→HTTPS `301` redirect on `:80`
- A modern TLS policy (`ELBSecurityPolicy-TLS13-1-2-2021-06`)

It is gated behind a single flag, `enable_dns`, currently `false` in
`environments/dev/terraform.tfvars`:

```hcl
enable_https        = local.features.enable_dns
acm_certificate_arn = local.features.enable_dns ? module.dns[0].acm_certificate_arn : null
```

The problem: that same flag also switches on the **`dns` module**, which creates
a **Route 53 hosted zone** and an ACM cert validated **automatically via Route
53**. Our DNS is in Cloudflare, so we cannot simply flip `enable_dns = true` — it
would build a Route 53 zone we don't use.

**So the work is: obtain a certificate a Cloudflare-compatible way, then point
the ALB at it.**

> ⚠️ Do **not** set `enable_dns = true` for any of the options below. That flag
> is Route 53-specific. See [`dns-and-tls.md`](./dns-and-tls.md) for the Route 53
> design it drives.

---

## Two problems that appear the instant the frontend is HTTPS

Regardless of which option is chosen:

### 1. Mixed content (this is the one that breaks everything)

The frontend calls the backend at `http://abhishek-backend.1020dev.com:4000`,
baked into the build as `VITE_API_URL` (`environments/dev/main.tf` — the
`codebuild` module's `frontend_api_url`). An **HTTPS page cannot call an HTTP
endpoint** — browsers block it as mixed content.

**Therefore the backend must also become HTTPS, and the frontend must be
rebuilt** (a CodeBuild run) so the new `https://` API URL is baked in.

### 2. Port 4000

- Cloudflare's proxy (orange cloud) **cannot proxy port 4000** — only a fixed set
  of ports (80, 443, 8080, 8443, …). 4000 is not on the list.
- Some corporate / mobile networks block non-standard ports.

Moving the backend to standard **443** solves both. `https://…:4000` is possible
with Option A but discouraged.

---

## The options

### Option A — ACM certificate on the ALB (Cloudflare stays DNS-only) ✅ Recommended

```
Browser ──HTTPS──> Cloudflare (grey cloud, DNS only) ──HTTPS──> ALB (:443, ACM cert) ──> ECS
```

- Request a **free AWS ACM public certificate** for both hostnames.
- ACM emits DNS-validation CNAMEs → paste them into Cloudflare once → cert issues.
- Attach the cert to the ALB `:443` listener (the code already exists).
- TLS is fully under your control, end to end. Reuses almost all existing Terraform.

**Effort:** Low · **Cost:** $0 · **Cloudflare API token:** not needed
(2 records added by hand).

### Option B — Cloudflare proxy, Full (strict)

```
Browser ──HTTPS──> Cloudflare edge (orange cloud, CF cert) ──HTTPS──> ALB (:443, Origin cert) ──> ECS
```

- Enable Cloudflare's proxy (orange cloud); Cloudflare terminates TLS at its edge
  with a free edge certificate.
- Generate a **Cloudflare Origin certificate**, import it into ACM, attach to the
  ALB `:443` (so the Cloudflare→AWS hop is also encrypted = "strict").
- **Bonus:** hides origin IPs, adds DDoS protection and edge caching.
- **Forces** the backend onto 443 (Cloudflare will not proxy 4000).

**Effort:** Medium · **Cost:** $0 · Good if you want Cloudflare's edge protection.

### Option C — Cloudflare Flexible SSL ❌ Not recommended

```
Browser ──HTTPS──> Cloudflare edge ──HTTP (plaintext over public internet!)──> ALB (:80) ──> ECS
```

- Fastest to switch on, zero AWS cert work — but the Cloudflare→AWS leg travels
  the public internet **unencrypted**. It only *looks* secure, and is prone to
  redirect loops. Do not use for anything real.

### Backend sub-decision (applies to A and B)

| Choice | Result | Notes |
|--------|--------|-------|
| **Move backend to 443** (recommended) | `https://abhishek-backend.1020dev.com` | Clean, Cloudflare-proxyable, no port-blocking. |
| **Keep `:4000` over HTTPS** | `https://abhishek-backend.1020dev.com:4000` | Option A only. Uglier, not proxyable, some networks block it. |

---

## Comparison

| | A: ACM on ALB | B: Cloudflare proxy | C: Flexible |
|---|---|---|---|
| Security | Strong, end-to-end | Strongest (+ hides origin) | ❌ Insecure hop |
| Cost | $0 | $0 | $0 |
| Effort | Low | Medium | Lowest |
| Cloudflare API token | No | No | No |
| DDoS / origin hiding | No | Yes | Yes |
| Backend on 443 | Optional | Required | Required |
| Reuses existing Terraform | Yes | Partly | Barely |

**Recommendation: Option A + move the backend to 443.** Lowest effort, reuses the
existing HTTPS code, genuinely secure end-to-end, and Cloudflare's orange-cloud
proxy (Option B) can be layered on later without touching AWS.

---

## Implementation outline — Option A

> High-level; exact resources to be written when the option is confirmed.

1. **Request the ACM certificate** (in `ap-south-1`, the ALB's region), *without*
   the Route 53 `dns` module:

   ```hcl
   resource "aws_acm_certificate" "alb" {
     domain_name               = "abhishek-frontend.1020dev.com"
     subject_alternative_names = ["abhishek-backend.1020dev.com"]
     validation_method         = "DNS"
     lifecycle { create_before_destroy = true }
   }

   output "acm_validation_records" {
     value = { for o in aws_acm_certificate.alb.domain_validation_options :
       o.domain_name => { name = o.resource_record_name, value = o.resource_record_value } }
   }
   ```

2. **Add the validation CNAMEs to Cloudflare** (name + value from the output),
   as **DNS-only** records. ACM then validates and issues.

3. **Point the ALB module at the new cert** and enable HTTPS
   (`environments/dev/main.tf`), instead of `module.dns[0]`:

   ```hcl
   acm_certificate_arn = aws_acm_certificate.alb.arn
   enable_https        = true
   ```

   Gives the frontend `:80 → 301 → :443` and a real `:443` listener. The ALB
   security group already allows 443 inbound.

4. **Add a backend `:443` HTTPS listener.** The backend listener in
   `modules/alb/main.tf` (`aws_lb_listener.backend_http`) is HTTP-only on `:4000`
   with no HTTPS branch — add an HTTPS listener mirroring the frontend's, and
   move the backend off 4000.

5. **Update URLs and rebuild the frontend** in `terraform.tfvars`:

   ```hcl
   public_frontend_url = "https://abhishek-frontend.1020dev.com"
   public_backend_url  = "https://abhishek-backend.1020dev.com"   # no :4000
   ```

   `public_backend_url` is baked into the frontend build as `VITE_API_URL`, so a
   **CodeBuild frontend rebuild is required** after this change — otherwise the
   HTTPS frontend calls `http://…:4000` and the browser blocks it (mixed content).

---

## Gotchas checklist

- [ ] Do **not** set `enable_dns = true` (that is Route 53-specific).
- [ ] Backend must also be HTTPS, or the frontend's API calls are blocked as mixed content.
- [ ] Rebuild the frontend after changing `public_backend_url` (it's baked into the build).
- [ ] ACM cert for the ALB must be in **`ap-south-1`** (a regional LB needs a same-region cert).
- [ ] Cloudflare validation records must be **DNS-only** (grey cloud) — proxying them breaks ACM validation.

---

## Related docs

- [`dns-and-tls.md`](./dns-and-tls.md) — the Route 53 / ACM / `enable_dns` design (the path we are *not* using here).
- [`prerequisites.md`](./prerequisites.md) — environment prerequisites.
