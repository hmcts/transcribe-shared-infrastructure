# transcribe-shared-infrastructure

Product-level (shared) Terraform for the HMCTS Transcribe product on the
[Cloud Native Platform](https://hmcts.github.io/cloud-native-platform/).

Target architecture: https://tools.hmcts.net/confluence/pages/viewpage.action?pageId=2004000371

> **Scaffold only.** No Terraform has been written yet. Two questions gate it:
> whether `transcribe` is an acceptable CNP `product` name, and whether Azure
> Speech is on the CNP approved-resource whitelist (the pipeline halts on
> anything unapproved). Both are with PlatOps.

## Scope — what belongs here, and what does not

CNP has three infrastructure tiers. This repository is the middle one.

| Tier | Owner | Where |
|---|---|---|
| Platform-level | PlatOps | Their repos, e.g. `cnp-core-infrastructure` (resource group, VNet, AKS). We raise PRs to add product values via path-to-live. |
| **Product-level (shared)** | **Us** | **This repo, Terraform at the root** |
| Component-level | Us | Each component repo's `/infrastructure` |

Only two resources genuinely belong here, because both are read by more than
one component and so cannot live in either:

- **Key Vault** (`hmcts-transcribe-kv-{env}`) — CNP's secret injection assumes a
  product vault; every component reads it via the chart's `keyVaults` block.
- **Azure Speech account** (`hmcts-transcribe-ai-{env}`) — used by the backend
  for batch and fast transcription, and to mint the tokens the browser uses for
  real-time streaming. Quota, model config and cost argue for one account.

Plus product-level Application Insights and alert rules.

**Networking is NOT ours.** PlatOms owns the resource group and VNet, so there
is no VNet here. `pcq-shared-infrastructure` is the model to copy —
`key-vault.tf`, `storage-account.tf`, `application-insights.tf`, `alerts.tf`,
and no networking. `darts-shared-infrastructure` does hold networking, but darts
is a heritage VM migration rather than a normal AKS product.

## Conventions

- Terraform files at the repository **root**.
- `{env}.tfvars` for per-environment values.
- Jenkins injects `env`, `product` and `subscription` — never set them in tfvars.
- Secrets never in Terraform or Git; retrieve from Key Vault.
- `.terraform-version` (hyphenated) is the real filename, despite the published
  docs prose saying `.terraformversion`.
- Infrastructure repos carry per-environment branches synced from the default
  branch (`syncBranchesWithMaster`).

## Related repositories

| Repository | Purpose |
|---|---|
| [transcribe-api](https://github.com/hmcts/transcribe-api) | The single backend. Component-scoped Terraform in its own `/infrastructure`. |
| [transcribe-web](https://github.com/hmcts/transcribe-web) | The merged frontend. Expected to need no bespoke Azure resources. |
