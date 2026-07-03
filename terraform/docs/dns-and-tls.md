# DNS & TLS — Route 53, ACM, and the `enable_dns` / `enable_cloudfront` Flags

**Date:** 2026-07-03
**Environment:** `dev` (`ap-south-1`)
**Status:** Implemented

---

## Overview

Custom-domain routing and HTTPS for Starflix are controlled by two independent
feature flags in `environments/dev/terraform.tfvars`:

| Flag                | Controls                                                              |
|---------------------|----------------------------------------------------------------------|
| `enable_dns`        | The `dns` module (Route 53 hosted zone + both ACM certs) **and** whether the ALB gets an HTTPS listener. |
| `enable_cloudfront` | The `cloudfront` module (the CDN distribution).                      |

Because they are independent, there are four combinations. Three are fully
useful; one is a deliberate half-configuration (see the matrix below).

---

## Why two ACM certificates?

The `dns` module issues **two** certificates for the same names
(`starflix.com` + `*.starflix.com`):

| Consumer   | Service type | Cert region required          | Terraform resource                  |
|------------|--------------|-------------------------------|-------------------------------------|
| ALB        | Regional     | **ap-south-1** (matches the LB) | `aws_acm_certificate.alb`           |
| CloudFront | Global       | **us-east-1** (always)         | `aws_acm_certificate.cloudfront`    |

This is an **AWS constraint, not a design choice**:

- An **ALB is regional** — it physically lives in `ap-south-1`, and a regional
  load balancer requires its certificate in the **same region**.
- **CloudFront is global**, but its control plane is hard-coded to `us-east-1`.
  AWS therefore rejects any CloudFront certificate that is not in `us-east-1`:

  > The specified SSL certificate ... must be in the US East (N. Virginia) region.

To mint the us-east-1 cert without moving the rest of the stack, the environment
declares an **aliased provider** (`providers.tf`):

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  # ...
}
```

The `dns` module receives it via `configuration_aliases = [aws.us_east_1]`. The
us-east-1 provider exists **solely** for this certificate — VPC, ECS, ALB, S3,
and all Route 53 records stay in `ap-south-1`.

Both certs validate through the **same hosted zone**. ACM issues an identical
validation CNAME for a given domain regardless of the cert's region, so the
validation records are merged and deduped by record name — one Route 53 record
validates both certificates.

---

## Behaviour matrix

| `enable_dns` | `enable_cloudfront` | Hosted zone + certs | ALB                         | CloudFront            | Domain routed? | How you reach the app                |
|:------------:|:-------------------:|:-------------------:|-----------------------------|-----------------------|:--------------:|--------------------------------------|
| **off**      | **off**             | none                | HTTP :80 → app              | none                  | no             | `http://<alb-dns-name>`              |
| off          | on                  | none                | HTTP :80 → app              | default cert          | no             | `https://<xxxx.cloudfront.net>`      |
| on           | off                 | created             | HTTPS :443 (+80→443 redirect) | none                | **no** ⚠️      | ALB DNS name, but cert-name mismatch |
| on           | on                  | created             | HTTPS :443                  | custom cert + aliases | **yes**        | `https://starflix.com`               |

### 1. Both OFF — plain HTTP dev

- No `dns` module → no hosted zone, no certificates.
- ALB gets `acm_certificate_arn = null`, so the frontend HTTP listener forwards
  directly to the target group on port 80 (no HTTPS listener).
- No CloudFront, no alias records.

**Result:** the app runs over plain **HTTP** via the raw ALB DNS names. No custom
domain, no TLS, no registrar/delegation dependency. Cheapest, cleanest dev setup.

### 2. DNS OFF, CloudFront ON — CDN without a custom domain

- CloudFront gets `acm_certificate_arn = null`, which flips it to
  `cloudfront_default_certificate = true` with `aliases = []`.
- ALB stays HTTP-only.

**Result:** a working CloudFront distribution reachable at its
`https://dxxxx.cloudfront.net` domain (AWS default cert), fronting the ALB + S3
origins with real HTTPS. Useful for testing caching/behaviours cheaply.

### 3. DNS ON, CloudFront OFF — ⚠️ intentionally incomplete

- The `dns` module is created → hosted zone + **both** certs (the us-east-1
  CloudFront cert is built unconditionally, so here it is **validated but
  unused**).
- The ALB gets the ap-south-1 cert → HTTPS :443 listener, port 80 redirects to
  HTTPS.
- `create_dns_records = enable_dns && enable_cloudfront = false` → **no alias
  records**.

**Two consequences:**

1. The alias records target CloudFront by design, so with CloudFront off the
   **domain does not resolve to anything**. Hitting the ALB's own DNS name serves
   a cert issued for `starflix.com`, producing a **cert-name-mismatch warning**.
2. The us-east-1 CloudFront cert is created but has no consumer (harmless, but it
   still DNS-validates and thus still needs registrar delegation).

This is the one "valid but not useful" combination. If you want DNS + HTTPS on
the ALB *without* a CDN, add ALB-targeted alias records (they currently target
CloudFront only).

### 4. Both ON — full production topology

Hosted zone, both certs, HTTPS everywhere, and `starflix.com` / `www` / `api`
alias records (A + AAAA) pointing at the CloudFront distribution.

---

## Route 53 alias records

The apex/`www`/`api` alias records live in the **environment root**
(`main.tf`, `aws_route53_record.cloudfront_alias`), **not** in the `dns` module.
This avoids a dependency cycle:

```
dns (cert) ──▶ cloudfront (consumes cert) ──▶ dns (alias records)   ✗ cycle
```

CloudFront depends on the cert from the `dns` module, so the alias records — which
point at CloudFront — must be created **after** both modules exist. Keeping them
at the root breaks the cycle. They are gated on `local.create_dns_records`.

---

## Operational caveat — ACM validation needs registrar delegation

`aws_acm_certificate_validation` blocks until the validation CNAMEs resolve
**publicly**, which requires this zone's name servers (the `route53_name_servers`
output) to be delegated at your **domain registrar**.

On a brand-new domain, **delegate the NS records first**. Otherwise the first
`apply` waits up to the configured `60m` timeout and then fails. Steps for the
full (both-on) setup:

1. First `apply` may create the hosted zone; read `route53_name_servers`.
2. Set those NS records at the registrar for `starflix.com`.
3. `apply` again (or let the first one proceed) — ACM validation now succeeds.

---

## Domain delegation at your registrar

This step happens **outside Terraform**, in the control panel of wherever the
domain was purchased (GoDaddy / Namecheap / Squarespace-Google / etc.).

### The idea

When the domain was registered, the registrar became both the **registrar** and
the default **DNS host**. The Route 53 hosted zone that Terraform creates wants
to *become* the authoritative DNS host. You hand over control by pointing the
domain's **name server (NS) records** at Route 53 — done **once**.

After delegation, every record (the ACM validation CNAME and the
`apex` / `www` / `api` alias records) is managed by Terraform in Route 53.
**Do not create individual A/CNAME records at the registrar.**

### Step 1 — Get the 4 Route 53 name servers

```bash
cd terraform/environments/dev
terraform output route53_name_servers
```

Example output (also visible in Route 53 → Hosted zones → the zone's NS record):

```
ns-123.awsdns-45.com
ns-678.awsdns-90.net
ns-1011.awsdns-12.org
ns-1314.awsdns-15.co.uk
```

### Step 2 — Set them at the registrar

Log into the registrar, find the domain, and locate the **Nameservers** setting
(this is *different* from the "DNS records" / "Zone editor"). Switch from the
default nameservers to **custom nameservers** and enter all four values.

| Registrar                     | Where to look                                                                 |
|-------------------------------|-------------------------------------------------------------------------------|
| **GoDaddy**                   | Domain Portfolio → domain → **DNS** → **Nameservers** → "Change" → "I'll use my own nameservers" |
| **Namecheap**                 | Domain List → **Manage** → **Nameservers** → **Custom DNS** → add the 4 values |
| **Squarespace / Google Domains** | Domain settings → **Nameservers** → "Use custom nameservers"                |
| **Hostinger / others**        | Domain → **DNS / Nameservers** → Custom nameservers                            |
| **Cloudflare (registrar)**    | ⚠️ Forces Cloudflare's own nameservers — delegation to Route 53 generally not possible. See the alternative below. |

Details that trip people up:

- Enter **all four** name servers.
- **Drop the trailing dot** — Route 53 may show `ns-123.awsdns-45.com.`; most
  registrars want `ns-123.awsdns-45.com` (no dot).
- No **glue records** are needed (these aren't subdomains of the domain).

### Step 3 — Wait for propagation, then verify

Delegation usually takes a few minutes to ~1 hour (up to 48h worst case). Verify:

```bash
# Should return the 4 Route 53 nameservers
dig NS starflix.com +short

# Confirm the ACM validation CNAME is now resolvable
dig CNAME _<hash>.starflix.com +short
```

Once `dig NS` returns the AWS nameservers, ACM validation completes
automatically (typically within minutes).

### Alternative — keep DNS at the registrar (not recommended)

If you cannot delegate (e.g. Cloudflare Registrar) or choose not to, leave DNS at
the registrar and manually recreate records there:

- Copy the **ACM validation CNAME** (name + value) from the ACM console into the
  registrar's zone editor.
- Point `www` and `api` as **CNAME** → the CloudFront domain (`dxxxx.cloudfront.net`).
- The **apex** (`starflix.com`) cannot be a plain `CNAME`; you need registrar
  support for **ALIAS / ANAME / CNAME-flattening**, or the apex cannot point at
  CloudFront.

In this mode the Terraform-managed `aws_route53_record.cloudfront_alias`
resources do nothing (no hosted zone in use) and you manage DNS by hand.
**Delegating to Route 53 is the clean, fully-Terraform-managed option** and is
what this configuration assumes.

> ⚠️ If you ever **destroy and recreate** the Route 53 zone, it gets **new**
> name servers — repeat Steps 1–2 at the registrar. Avoid tearing down the `dns`
> module casually once delegated.

---

## Files involved

| File                                   | Role                                                        |
|----------------------------------------|-------------------------------------------------------------|
| `environments/dev/providers.tf`        | `aws.us_east_1` aliased provider                            |
| `environments/dev/locals.tf`           | `create_dns_records` gate + alias-record map                |
| `environments/dev/main.tf`             | `dns`/`cloudfront` module wiring + `cloudfront_alias` records |
| `modules/dns/versions.tf`              | `configuration_aliases = [aws.us_east_1]`                   |
| `modules/dns/main.tf`                  | Hosted zone, both ACM certs, merged validation records      |
| `modules/dns/outputs.tf`               | `acm_certificate_arn`, `cloudfront_acm_certificate_arn`     |
