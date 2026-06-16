# Region the provider actually resolves to — used to assert the name suffix can't lie.
data "aws_region" "current" {}

locals {
  # Consistent, env- and region-suffixed name so resources are greppable and never
  # collide within an account. e.g. securityhub-forward-ops-prod-eu-west-2.
  name = "securityhub-forward-${var.environment}-${var.aws_region}"

  # Default pattern matches every imported Security Hub finding. Inspector findings
  # feed into Security Hub, so they ride along. Override via var.event_pattern to add
  # filtering later (e.g. severity) without a breaking change.
  default_event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
  })
  event_pattern = var.event_pattern != null ? var.event_pattern : local.default_event_pattern

  tags = {
    ENVIRONMENT = var.environment
    used_in     = "securityhub-forward"
  }
}

# Rule on this account's DEFAULT event bus, where Security Hub publishes its findings.
# The module deploys into the provider's region; var.aws_region is only a name suffix.
# Fail fast if they disagree, so resource names can't misreport where things live.
# lifecycle preconditions need Terraform >= 1.2, but consumers (e.g. acp-ops-resources)
# run 1.1.x, so we emulate the assertion here: when the regions match, count is 0 and
# nothing is created; when they disagree, count gets a string, which is an invalid value
# for count and aborts the plan — the diagnostic prints both region values.
resource "null_resource" "assert_region_matches_provider" {
  count = var.aws_region == data.aws_region.current.name ? 0 : "aws_region (\"${var.aws_region}\") must equal the provider region (\"${data.aws_region.current.name}\"); it only sets the name suffix, not where resources deploy."
}

resource "aws_cloudwatch_event_rule" "forward" {
  name          = local.name
  description   = "Forward Security Hub imported findings to the central ${coalesce(var.central_bus_name, "securityhub-ingest")} bus in the hub account"
  event_pattern = local.event_pattern
  tags          = local.tags
}

# Role EventBridge assumes to deliver to the central bus. Cross-account delivery needs
# BOTH this source-side role (PutEvents) AND the target bus resource policy in the hub
# account; missing either fails quietly.
resource "aws_iam_role" "forward" {
  name = local.name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "forward" {
  name = "${local.name}-put-events"
  role = aws_iam_role.forward.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = var.central_bus_arn
    }]
  })
}

# Target = the central bus ARN, delivered via the role above. Forwarded events keep
# their original source / detail-type / detail / account, so the hub pipeline rule
# still matches and its transformer's $.account carries the originating account ID.
resource "aws_cloudwatch_event_target" "forward" {
  rule     = aws_cloudwatch_event_rule.forward.name
  arn      = var.central_bus_arn
  role_arn = aws_iam_role.forward.arn

  # Ensure the PutEvents permission is created before the target is wired, so the rule
  # can't briefly fire into a role that isn't yet allowed to deliver (create-ordering).
  depends_on = [aws_iam_role_policy.forward]

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 4
  }

  dynamic "dead_letter_config" {
    for_each = var.enable_dlq ? [1] : []
    content {
      arn = aws_sqs_queue.dlq[0].arn
    }
  }
}

# Optional DLQ: failed cross-account PutEvents land here instead of disappearing.
resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name = "${local.name}-dlq"

  # Retry policy above only retries for 1h; keep the DLQ window wide (14 days = max)
  # so failed forwards persist long enough to investigate.
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = local.tags
}

resource "aws_sqs_queue_policy" "dlq" {
  count = var.enable_dlq ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeToSendFailedForwards"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.dlq[0].arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.forward.arn
        }
      }
    }]
  })
}
