# Changelog

All notable changes to this module are documented here. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
