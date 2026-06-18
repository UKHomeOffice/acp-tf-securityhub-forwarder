# Changelog

All notable changes to this module are documented here. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.2] - 2026-06-18

### Fixed

- Removed the `retry_policy` block from `aws_cloudwatch_event_target.forward`. EventBridge rejects a
  retry policy when the target is an event bus (`ValidationException: Retry policy is not supported for
  Event bus targets`), and this module's target is always an event bus, so every `terraform apply`
  failed at the target. `terraform plan` could not catch it — the constraint is enforced server-side at
  apply time. Bus-to-bus delivery now relies on EventBridge's default managed retry (~24h); the optional
  DLQ is unchanged and still captures undelivered forwards (DLQs *are* supported for event-bus targets).

## [1.1.1] - 2026-06-16

### Fixed

- Variable `validation` error messages (`central_bus_arn`, `event_pattern`) now start with a capital
  letter and end with a period, as Terraform 1.1.x requires. They previously started with the lowercase
  variable name, which failed `terraform init` on consumers running Terraform 1.1.x (e.g.
  `terraform-toolset:v1.1.7`). Newer Terraform dropped that check, so it wasn't caught locally.

## [1.1.0] - 2026-06-16

### Changed

- Lowered `required_version` back to `>= 1.0` so the module runs on the Terraform that
  consumers actually use. `acp-ops-resources` (the first consumer) runs
  `terraform-toolset:v1.1.7`; the `>= 1.2` pin added in 1.0.1 would have failed `terraform init`.
- Re-implemented the region assertion without a `lifecycle` precondition (a 1.2-only feature):
  a `null_resource` now emulates it via a count type-coercion that aborts the plan, printing both
  region values, when `var.aws_region` disagrees with the provider's actual region. Same guarantee,
  Terraform 1.0+ compatible.

### Added

- `hashicorp/null` provider requirement (`>= 3.0`), used solely for the region-assertion resource.

## [1.0.1] - 2026-06-10

### Changed

- The forwarding target now `depends_on` the IAM `events:PutEvents` policy, so the rule can't be
  wired before the role is permitted to deliver (removes a create-ordering race).
- Bumped `required_version` to `>= 1.2` (needed for the precondition below).

### Added

- Precondition asserting `var.aws_region` equals the provider's actual region, so the resource-name
  suffix can't drift from where resources really deploy.
- Validation that `event_pattern` is valid JSON (or null).

## [1.0.0] - 2026-06-10

### Added

- Initial release. Forwards AWS Security Hub imported findings from an account's default EventBridge
  bus to a central cross-account bus, reusing the existing ACP Security Hub → Splunk Cloud pipeline.
- `aws_cloudwatch_event_rule` on the default bus (overridable `event_pattern`, defaults to
  `source aws.securityhub` / detail-type `Security Hub Findings - Imported`).
- IAM role assumable by `events.amazonaws.com` with least-privilege `events:PutEvents` on the central
  bus only.
- EventBridge target = central bus ARN, with retry policy and an optional SQS DLQ (`enable_dlq`,
  default `true`).
- Consistent, env- and region-suffixed resource names (`securityhub-forward-${environment}-${aws_region}`).
