# acp-tf-securityhub-forwarder

Terraform module that forwards an account's **AWS Security Hub findings** cross-account to a central
**EventBridge** bus, where the ACP Security Hub → Splunk Cloud pipeline drains them into Splunk.

This module needs no org-management privileges: each account forwards its own findings.

## What it does

```
(this account)                                    (hub account: hod-ops-prod, eu-west-2)
Security Hub finding
      │ AWS publishes automatically
      ▼
Default event bus ─▶ rule (this module) ─▶ central "securityhub-ingest" bus ─▶ existing
                         │ via IAM role (PutEvents)                              Splunk pipeline
                         └─▶ SQS DLQ (failed forwards)
```

Security Hub publishes every imported finding (Inspector findings included — they feed into Security
Hub) onto the account's **default** event bus. This module puts a rule on that bus and forwards
matching events to the **central bus ARN** you pass in. Delivery is serverless — no Lambda.

Forwarded events keep their original `source`, `detail-type`, `detail` and `account`, so the hub's
existing pipeline rule (`source aws.securityhub`, detail-type `Security Hub Findings - Imported`)
still matches, and its input transformer's `$.account` carries the **originating** account ID.

### Cross-account needs BOTH sides

Cross-account EventBridge delivery requires **two** things; missing either fails quietly:

1. **Source side (this module):** an IAM role EventBridge assumes, with `events:PutEvents` on the
   central bus. Created here.
2. **Target side (hub account):** a resource policy on the central bus allowing `events:PutEvents`
   from these accounts. **Not** created here — it lives in the hub repo (`acp-ops-resources`),
   scoped with `aws:PrincipalOrgID`. See [Hub-side resources](#hub-side-resources-not-in-this-module).

## Usage

### Member account

```hcl
module "securityhub_forwarder" {
  source          = "git::https://github.com/UKHomeOffice/acp-tf-securityhub-forwarder?ref=v1.0.0"
  central_bus_arn = "arn:aws:events:eu-west-2:546151634857:event-bus/securityhub-ingest"
  environment     = var.environment
  aws_region      = var.aws_region
}
```

Add this in the repo's **main eu-west-2 Terraform directory** (the one whose default, unaliased
provider resolves to eu-west-2 — `default/terraform/` in ops/notprod/prod, `terraform/` in
test/ci/bx). The module declares **no** provider of its own and inherits the caller's default
provider. If a repo's default provider is not eu-west-2, pass `providers = { aws = aws.eu-west-2 }`.

### Hub account (hod-ops-prod) — same-account self-forward

The hub forwards its own default bus into the ingest bus too, so its findings survive the pipeline
being repointed off the default bus. Same module, pointed at the bus it sits beside:

```hcl
module "securityhub_forwarder" {
  source          = "git::https://github.com/UKHomeOffice/acp-tf-securityhub-forwarder?ref=v1.0.0"
  central_bus_arn = aws_cloudwatch_event_bus.securityhub_ingest.arn
  environment     = var.environment
  aws_region      = var.aws_region
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `central_bus_arn` | string | — (required) | ARN of the central EventBridge bus in the hub account. Target of the rule and the only resource PutEvents is granted on. |
| `central_bus_name` | string | `null` | Optional; used only in resource descriptions. |
| `environment` | string | — (required) | Resource-name suffix (e.g. `ops-prod`, `prod`, `notprod`, `test`). |
| `aws_region` | string | — (required) | Resource-name suffix. eu-west-2 only by design. |
| `enable_dlq` | bool | `true` | Create an SQS DLQ on the forwarding rule so failed forwards are observable. |
| `event_pattern` | string | `null` | Override the event pattern (JSON string). When null, matches Security Hub imported findings. The hook for adding filtering later without a breaking change. |

## Outputs

| Name | Description |
|---|---|
| `rule_arn` | ARN of the forwarding rule. |
| `rule_name` | Rule name (for CloudWatch `AWS/Events` metrics). |
| `role_arn` | ARN of the role EventBridge assumes to PutEvents. |
| `dlq_arn` | DLQ ARN, or `null` when `enable_dlq = false`. |
| `dlq_url` | DLQ URL, or `null` when `enable_dlq = false`. |

## Resources created

All named `securityhub-forward-${environment}-${aws_region}`:

- `aws_cloudwatch_event_rule.forward` — on the default bus, matching imported Security Hub findings.
- `aws_iam_role.forward` + `aws_iam_role_policy.forward` — assumable by `events.amazonaws.com`,
  least-privilege `events:PutEvents` on `central_bus_arn` only.
- `aws_cloudwatch_event_target.forward` — target = `central_bus_arn`, with retry policy + optional DLQ.
- `aws_sqs_queue.dlq` + `aws_sqs_queue_policy.dlq` — when `enable_dlq` (default), SSE on, 14-day
  retention, `sqs:SendMessage` scoped to this rule.

## Hub-side resources (NOT in this module)

These live in `acp-ops-resources` (`default/terraform/`), not here, because they are singletons in the
hub account:

- The custom **`securityhub-ingest`** bus (`aws_cloudwatch_event_bus`).
- Its **resource policy** (`aws_cloudwatch_event_bus_policy`): `events:PutEvents` on that bus only,
  `Condition StringEquals aws:PrincipalOrgID = <org-id>`.
- **Repointing** the existing Splunk pipeline rule onto the ingest bus
  (`event_bus_name = aws_cloudwatch_event_bus.securityhub_ingest.name`).

**Bus policy scope — why `aws:PrincipalOrgID`:** it grants only `events:PutEvents` on one bus
(minimal blast radius), gives zero-touch onboarding of future org accounts, and needs no
management-account access to enumerate OU paths (the Org ID is readable from any member via
`aws organizations describe-organization`). Tightening to `aws:PrincipalOrgPaths` (the ACP OU) is a
non-breaking change if the OU path becomes available.

## Rollout runbook

Tag-pinned and staged so it's reversible (re-pin to roll back). Per-repo: add the module call, commit,
push a feature branch, open an MR (CI runs `terraform plan`), review, merge (CI runs `terraform
apply`), then run the acceptance test below before advancing.

**Order (lowest risk first):** stand up the hub bus + self-forward + pipeline repoint →
`acp-test-resources` (hod-dsp-testing) → `acp-notprod-resources` (hod-dsp-dev) + `acp-bx-resources`
(dsab-acp-np) → `acp-ci-resources` (hod-ci) + `acp-ecr-resources` (acp-ecr) + `acp-vpn-resources`
(hod-vpn) → `acp-prod-resources` (hod-dsp-prod) last.

### Per-account acceptance test (gate before the next account)

1. Merge the MR → CI applies the module.
2. Inject a synthetic finding with a **unique Id** via `aws securityhub batch-import-findings`.
   Do **not** use `aws events put-events` with `source aws.securityhub` — EventBridge rejects the
   `aws.` prefix with `NotAuthorizedForSourceException`.
3. Confirm the hub pipeline rule fired: CloudWatch `AWS/Events` `Invocations > 0` on
   `securityhub-splunk-ops-prod-eu-west-2`.
4. Confirm **both** DLQs stay at 0 — this module's forwarding DLQ and the Splunk pipeline DLQ.
5. Search Splunk: `index=es_hocs_acp-security-hub_prod "<your-unique-id>" earliest=-15m`.

## Assumptions & limitations

- **eu-west-2 only.** No cross-region forwarding; findings raised in other regions are not delivered.
- **No filtering yet.** All imported findings are forwarded; the Splunk team filters downstream. Add
  filtering later via `event_pattern` without a breaking change.
- **Forward-looking.** EventBridge forwards new/updated findings; pre-existing findings are not
  replayed.
