variable "central_bus_arn" {
  description = "ARN of the central EventBridge bus in the hub account (hod-ops-prod) that Security Hub findings are forwarded to. This is the target of the forwarding rule and the only resource the PutEvents role is granted."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:events:[a-z0-9-]+:[0-9]{12}:event-bus/.+$", var.central_bus_arn))
    error_message = "central_bus_arn must be a full EventBridge event-bus ARN, e.g. arn:aws:events:eu-west-2:546151634857:event-bus/securityhub-ingest."
  }
}

variable "central_bus_name" {
  description = "Name of the central bus. Optional; used only in resource descriptions for readability."
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name, used as a resource-name suffix (e.g. ops-prod, prod, notprod, test). Keeps names consistent and greppable across accounts."
  type        = string
}

variable "aws_region" {
  description = "AWS region, used as a resource-name suffix. Forwarding is eu-west-2 only by design; findings raised in other regions are not forwarded."
  type        = string
}

variable "enable_dlq" {
  description = "Create an SQS dead-letter queue on the forwarding rule so failed cross-account PutEvents are observable rather than silently dropped."
  type        = bool
  default     = true
}

variable "event_pattern" {
  description = "Override the EventBridge event pattern (a JSON string). When null, the module matches Security Hub imported findings (source aws.securityhub, detail-type 'Security Hub Findings - Imported'). Use this to add filtering later without a breaking change."
  type        = string
  default     = null
}
