# GitHub Token Permissions for CodeBuild Auto-Deployment

**Applies to:** `modules/codebuild` (source auth + push webhooks) in all environments.
**Secret:** `starflix/<env>/github-token` in AWS Secrets Manager.

CodeBuild uses a GitHub token to do three things:

1. **Clone the source repo** at build time (`git_clone_depth = 1`).
2. **Create and manage the push webhook** on the repo (`aws_codebuild_webhook`).
3. **Report build status** back to commits (optional but recommended).

The token must grant exactly the permissions those actions need — no more.

---

## Option 1 — Fine-grained Personal Access Token (recommended)

Fine-grained PATs are scoped to **specific repositories** and use granular
*repository permissions* instead of broad scopes. This is the least-privilege
choice.

### Create it

GitHub → **Settings → Developer settings → Personal access tokens →
Fine-grained tokens → Generate new token**.

- **Resource owner:** the account/org that owns `starflix`.
- **Repository access:** *Only select repositories* → choose the `starflix` repo.
- **Expiration:** set a calendar reminder to rotate before it lapses (a fine-grained
  token cannot be non-expiring beyond 1 year).

### Repository permissions to grant

| Permission | Access | Why CodeBuild needs it |
|---|---|---|
| **Contents** | **Read-only** | Clone/fetch the repository source for the build. |
| **Webhooks** | **Read and write** | Create, read, and delete the push webhook (`CreateWebhook`). Without this you get `does not have access` / webhook-creation `400`. |
| **Commit statuses** | **Read and write** | Post build success/failure back to the commit (needed if `report_build_status`/PR checks are used). Recommended. |
| **Metadata** | **Read-only** | Mandatory — GitHub auto-selects it; required for API access. |
| **Pull requests** | **Read** *(optional)* | Only if you add PR-event build triggers (`PULL_REQUEST_*`). Not needed for the current push-to-`main` deploy. |

> Minimum for the current setup (push-to-`main` → build → deploy):
> **Contents: Read**, **Webhooks: Read/write**, **Metadata: Read** (auto),
> plus **Commit statuses: Read/write** if you want build status on commits.

---

## Option 2 — Classic Personal Access Token

If you use a classic PAT instead, grant these **scopes**:

| Scope | Why |
|---|---|
| `repo` | Read repository contents (and commit statuses) for private repos. |
| `admin:repo_hook` | Create/manage the repository webhook. |

Classic tokens are broader (all repos the account can access), so prefer
fine-grained tokens where possible.

---

## Storing the token (Secrets Manager format)

CodeBuild's GitHub source auth via Secrets Manager requires the secret value to be
a **JSON document**, not a bare token string. The `secrets` module writes it in
this shape:

```json
{
  "ServerType": "GITHUB",
  "AuthType": "PERSONAL_ACCESS_TOKEN",
  "Token": "<your-token>"
}
```

Two ways to populate it:

**A. Terraform-managed (current dev)** — set the value via a gitignored var; the
module creates the secret version (value lands in encrypted state, see
`ARCHITECTURE.md` §7):

```hcl
# environments/<env>/terraform.tfvars  (gitignored)
github_token = "github_pat_xxxxxxxxxxxxxxxxxxxx"
```
```bash
terraform apply
```

Or without writing it to a file:

```bash
export TF_VAR_github_token='github_pat_xxxxxxxxxxxxxxxxxxxx'
terraform apply
```

**B. Out-of-band** — leave `github_token` empty and set the value directly (never
enters Terraform state). Note the required JSON wrapper:

```bash
aws secretsmanager put-secret-value \
  --secret-id "starflix/dev/github-token" \
  --secret-string '{"ServerType":"GITHUB","AuthType":"PERSONAL_ACCESS_TOKEN","Token":"github_pat_xxxx"}' \
  --region ap-south-1
```

The CodeBuild service role is granted `secretsmanager:GetSecretValue` on this
secret ARN (see `modules/iam`), which is required for both the source auth and the
webhook creation.

---

## Verifying it works

```bash
# 1. Secret has a value and is valid JSON with a Token
aws secretsmanager get-secret-value --secret-id starflix/dev/github-token \
  --region ap-south-1 --query SecretString --output text | python3 -m json.tool

# 2. Webhooks exist on both projects
aws codebuild batch-get-projects --names starflix-dev-frontend-build starflix-dev-backend-build \
  --region ap-south-1 --query 'projects[].{name:name,webhook:webhook.url}' --output table

# 3. A push to main to the relevant path triggers a build
aws codebuild list-builds-for-project --project-name starflix-dev-frontend-build \
  --region ap-south-1 --query 'ids[0]'
```

---

## Common failures & causes

| Error / symptom | Cause | Fix |
|---|---|---|
| `Project service role does not have access to retrieve secret ...` | CodeBuild role missing `secretsmanager:GetSecretValue` on the token secret | Grant it (already in `modules/iam`). |
| `Given secret ... was not found` / `secret value ... AWSCURRENT` | Secret container exists but has **no value** | Populate it (Option A or B above). |
| `Secret ... was not in the expected json format` | Value stored as a raw token instead of the JSON wrapper | Store the `{ServerType,AuthType,Token}` JSON. |
| Webhook `CreateWebhook` `400` (access) with a valid secret | Token lacks **Webhooks: Read/write** (fine-grained) or `admin:repo_hook` (classic) | Add the permission and re-store the token. |
| Build clones but can't read a private repo | Token lacks **Contents: Read** (fine-grained) or `repo` (classic) | Add the permission. |
| Build runs but no status shows on the commit/PR | Token lacks **Commit statuses: Read/write** | Add the permission (optional feature). |

---

## Rotation

1. Generate a new token with the same permissions.
2. Update the secret (Option A: change the tfvar + `terraform apply`; Option B:
   `put-secret-value`).
3. CodeBuild picks up the new value on the next build automatically (it reads
   `AWSCURRENT`). No project change needed.
4. Revoke the old token in GitHub.

---

*Related: `docs/frontend-backend-504-fix.md`, `ARCHITECTURE.md` §7 (secrets) and §9 (security).*
