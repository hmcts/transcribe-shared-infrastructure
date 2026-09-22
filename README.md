# transcribe-shared-infrastructure

Product-level Azure infrastructure for the **transcribe** product, deployed by
the HMCTS CNP common pipeline (`withInfraPipeline`). Terraform lives at the
repository root, and each long-lived environment has its own branch kept in
step with `master`.

This is the middle of the three CNP infrastructure tiers:

| Tier | Owner | Where |
|---|---|---|
| Platform | PlatOps (`cnp-core-infrastructure`) | Resource group, VNet, AKS. Service teams do not provision networking. |
| **Product** | **this repo** | **Key Vault, Application Insights, storage — anything shared by more than one component.** |
| Component | `transcribe-api/infrastructure` | Resources belonging to exactly one component, e.g. its Postgres server. |

## What this builds

- Resource group `transcribe-shared-infrastructure-<env>`
- Key Vault **`transcribe-<env>`** — the name is load-bearing, see below
- Application Insights, plus the `AppInsightsConnectionString` secret
- Storage account with `audio` and `transcriptions` containers, plus the
  `azure-storage-account-name` secret

## The Key Vault name is load-bearing

Both component charts declare `keyVaults: { transcribe: ... }`. The HMCTS base
chart expands that to `"<key>-<global.environment>"`, so the vault **must** be
named `transcribe-<env>`. Renaming it here silently breaks every component
deployment: the CSI driver cannot find the vault, the volume never mounts, and
pods stay unready with no obvious error in the application logs.

## Secrets that must be seeded by hand

The chart's `keyVaults` block names every secret it wants mounted. **If any one
of them is missing from the vault, the Secrets Store CSI driver fails the mount
and the pod never starts** — so seeding these is a hard precondition for the
first deploy, not a follow-up.

Terraform creates these:

| Secret | Created by |
|---|---|
| `AppInsightsConnectionString` | this repo |
| `azure-storage-account-name` | this repo |
| `database-connection-string` | `transcribe-api/infrastructure` |

These have to be seeded manually, because they are credentials for systems
outside this product's Terraform:

| Secret | Notes |
|---|---|
| `entra-client-id` | MoJ Entra (e-judiciary) app registration |
| `entra-tenant-id` | " |
| `entra-client-secret` | " |
| `azure-speech-key` | See "Azure Speech" below |
| `azure-speech-endpoint` | " |
| `azure-openai-api-key` | |
| `azure-openai-endpoint` | |
| `gov-notify-api-key` | GOV.UK Notify |
| `jwt-secret-key` | Any high-entropy string |
| `webhook-secret-encryption-key` | Must be a valid Fernet key: 32 random bytes, url-safe base64. Generate with `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`. A plain random string will fail at decrypt time, not at startup. |

Seed one with:

```bash
az keyvault secret set --vault-name transcribe-aat --name gov-notify-api-key --value '<value>'
```

## Azure Speech is not provisioned here

`azurerm_cognitive_account` does not appear on any CNP Terraform whitelist —
neither `terraform-infra-approvals/global.json` nor any per-repo file. The
pipeline halts on unapproved resources, so Speech **cannot** be created from
this repo as things stand. Two ways forward:

1. Raise a PR against `hmcts/cnp-jenkins-config` adding
   `terraform-infra-approvals/transcribe-shared-infrastructure.json` with
   `azurerm_cognitive_account`, for `@hmcts/production-apps-approvals`.
2. Until then, point `azure-speech-key` and `azure-speech-endpoint` at the
   existing Speech resource and seed them by hand as above.

## Deploying

The pipeline runs Terraform per environment; `env`, `product` and
`subscription` are injected as `-var` at runtime and must never be set in the
`.tfvars` files.
