# EC2 primary + optionally Route 53 failover to stopped-then-started secondary.
# Route 53 HealthCheckStatus metrics exist in us-east-1.
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

variable "enable_eventbridge_dispatch" {
  description = "Enable automatic GitHub dispatch only after primary and secondary are verified"
  type        = bool
  default     = false
}

variable "github_pat" {
  description = "GitHub token authorized to dispatch events (stored sensitively in TF state)"
  type        = string
  sensitive   = true
}

variable "enable_dns_failover" {
  description = "Opt in to creating public Route 53 PRIMARY/SECONDARY failover records"
  type        = bool
  default     = false
}
variable "dr_hosted_zone_id" {
  type    = string
  default = ""
}
variable "dr_record_name" {
  type        = string
  description = "FQDN in your Route 53 public hosted zone, e.g., dr.lab.example.org"
  default     = ""
}
variable "secondary_eip" {
  type        = string
  description = "Output region_b_eip from Region-B Terraform"
  default     = ""
}
variable "health_check_interval" {
  type        = number
  description = "Route 53 interval in seconds (30 is lower cost than 10)"
  default     = 30
  validation {
    condition     = contains([10, 30], var.health_check_interval)
    error_message = "Choose 10 or 30 seconds."
  }
}

resource "aws_route53_health_check" "primary_health_check" {
  ip_address        = aws_eip.primary_static_ip.public_ip
  port              = 80
  type              = "HTTP"
  resource_path     = "/healthz"
  request_interval  = var.health_check_interval
  failure_threshold = 2
  tags              = { Name = "Skripsi-HealthCheck-RegionA-EC2" }
}

resource "aws_cloudwatch_metric_alarm" "health_check_alarm" {
  provider            = aws.virginia
  alarm_name          = "Skripsi-RegionA-Down-Alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "missing"
  dimensions = {
    HealthCheckId = aws_route53_health_check.primary_health_check.id
  }
  alarm_description = "Controlled failure of primary EC2 HTTP /healthz"
}

resource "aws_cloudwatch_event_connection" "github_connection" {
  provider           = aws.virginia
  name               = "skripsi-github-connection"
  authorization_type = "API_KEY"
  auth_parameters {
    api_key {
      key   = "Authorization"
      value = "Bearer ${var.github_pat}"
    }
  }
}

resource "aws_cloudwatch_event_api_destination" "github_api" {
  provider                         = aws.virginia
  name                             = "skripsi-github-destination"
  invocation_endpoint              = "https://api.github.com/repos/ZulPratama21/skripsi-aws-dr/dispatches"
  http_method                      = "POST"
  invocation_rate_limit_per_second = 1
  connection_arn                   = aws_cloudwatch_event_connection.github_connection.arn
}

resource "aws_cloudwatch_event_rule" "alarm_rule" {
  provider   = aws.virginia
  name       = "skripsi-alarm-rule"
  is_enabled = var.enable_eventbridge_dispatch
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.health_check_alarm.alarm_name]
      state     = { value = ["ALARM"] }
    }
  })
}

resource "aws_sqs_queue" "github_dispatch_dlq" {
  provider                  = aws.virginia
  name                      = "skripsi-dr-github-dispatch-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue_policy" "github_dispatch_dlq" {
  provider  = aws.virginia
  queue_url = aws_sqs_queue.github_dispatch_dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.github_dispatch_dlq.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.alarm_rule.arn } }
    }]
  })
}

resource "aws_iam_role" "eventbridge_role" {
  name = "skripsi-eventbridge-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_policy" {
  name = "skripsi-eventbridge-policy"
  role = aws_iam_role.eventbridge_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["events:InvokeApiDestination"]
      Resource = [aws_cloudwatch_event_api_destination.github_api.arn]
    }]
  })
}

resource "aws_cloudwatch_event_target" "github_target" {
  provider  = aws.virginia
  rule      = aws_cloudwatch_event_rule.alarm_rule.name
  target_id = "TriggerGitOpsPipeline"
  arn       = aws_cloudwatch_event_api_destination.github_api.arn
  role_arn  = aws_iam_role.eventbridge_role.arn
  input = jsonencode({
    event_type = "aws-cloudwatch-trigger"
    client_payload = {
      source = "aws-eventbridge"
      alarm  = aws_cloudwatch_metric_alarm.health_check_alarm.alarm_name
    }
  })
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 5
  }
  dead_letter_config {
    arn = aws_sqs_queue.github_dispatch_dlq.arn
  }
  http_target {
    header_parameters = {
      "Accept"               = "application/vnd.github+json"
      "X-GitHub-Api-Version" = "2022-11-28"
    }
  }
}

# Secondary health check is DOWN while EC2 Region B is stopped.
resource "aws_route53_health_check" "secondary_health_check" {
  count             = var.enable_dns_failover ? 1 : 0
  ip_address        = var.secondary_eip
  type              = "HTTP"
  port              = 80
  resource_path     = "/healthz"
  request_interval  = var.health_check_interval
  failure_threshold = 2
  tags              = { Name = "Skripsi-HealthCheck-RegionB-EC2" }
}

resource "aws_route53_record" "dr_primary" {
  count           = var.enable_dns_failover ? 1 : 0
  zone_id         = var.dr_hosted_zone_id
  name            = var.dr_record_name
  type            = "A"
  ttl             = 30
  records         = [aws_eip.primary_static_ip.public_ip]
  set_identifier  = "dr-primary-region-a"
  health_check_id = aws_route53_health_check.primary_health_check.id
  failover_routing_policy {
    type = "PRIMARY"
  }
  lifecycle {
    precondition {
      condition     = length(var.dr_hosted_zone_id) > 0 && length(var.dr_record_name) > 0 && length(var.secondary_eip) > 0
      error_message = "Set dr_hosted_zone_id, dr_record_name, secondary_eip before enabling DNS failover."
    }
  }
}

resource "aws_route53_record" "dr_secondary" {
  count           = var.enable_dns_failover ? 1 : 0
  zone_id         = var.dr_hosted_zone_id
  name            = var.dr_record_name
  type            = "A"
  ttl             = 30
  records         = [var.secondary_eip]
  set_identifier  = "dr-secondary-region-b"
  health_check_id = aws_route53_health_check.secondary_health_check[0].id
  failover_routing_policy {
    type = "SECONDARY"
  }
  depends_on = [aws_route53_record.dr_primary]
}

output "dr_validation_dns_name" {
  value = var.enable_dns_failover ? var.dr_record_name : "DNS failover disabled"
}

output "github_dispatch_dlq_url" {
  value = aws_sqs_queue.github_dispatch_dlq.id
}
