provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

# 1. Variabel Placeholder (Kita isi nanti saat simulasi dijalankan)
variable "eks_lb_fqdn" {
  description = "URL Load Balancer EKS Region A (tanpa http://)"
  type        = string
  default     = "a60600f6c9a034d98a0d1716f5e182b4-1823949781.ap-southeast-1.elb.amazonaws.com" 
}

variable "github_pat" {
  description = "GitHub Personal Access Token (PAT)"
  type        = string
  sensitive   = true
}

# 2. Route 53 Health Check (Memantau Load Balancer EKS)
resource "aws_route53_health_check" "primary_health_check" {
  fqdn        = var.eks_lb_fqdn
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  request_interval  = 10 # Interval cepat untuk percepatan RTO
  failure_threshold = 1  # 1x gagal = DOWN

  tags = {
    Name = "Skripsi-HealthCheck-RegionA"
  }
}

# 3. CloudWatch Alarm (Mendeteksi kegagalan Health Check)
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

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary_health_check.id
  }
  alarm_description = "Sinyal simulasi outage Region A"
}

# 4. Koneksi EventBridge ke GitHub (Membawa Token PAT)
resource "aws_cloudwatch_event_connection" "github_connection" {
  provider            = aws.virginia
  name               = "skripsi-github-connection"
  description        = "Koneksi aman ke GitHub Actions API"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "Authorization"
      value = "Bearer ${var.github_pat}"
    }
  }
}

# 5. Target Endpoint GitHub Repo Dispatch
resource "aws_cloudwatch_event_api_destination" "github_api" {
  provider                         = aws.virginia
  name                             = "skripsi-github-destination"
  description                      = "Webhook ke repositori skripsi-aws-dr"
  invocation_endpoint              = "https://api.github.com/repos/ZulPratama21/skripsi-aws-dr/dispatches"
  http_method                      = "POST"
  connection_arn                   = aws_cloudwatch_event_connection.github_connection.arn
}

# 6. EventBridge Rule (Pemicu saat Alarm berbunyi)
resource "aws_cloudwatch_event_rule" "alarm_rule" {
  provider    = aws.virginia
  name        = "skripsi-alarm-rule"
  description = "Memicu webhook saat Region A berstatus ALARM"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.health_check_alarm.alarm_name]
      state     = { value = ["ALARM"] }
    }
  })
}

# 7. Eksekutor EventBridge (Mengirim Payload 'aws-cloudwatch-trigger')
resource "aws_cloudwatch_event_target" "github_target" {
  provider  = aws.virginia
  rule      = aws_cloudwatch_event_rule.alarm_rule.name
  target_id = "TriggerGitOpsPipeline"
  arn       = aws_cloudwatch_event_api_destination.github_api.arn
  role_arn  = aws_iam_role.eventbridge_role.arn

  input = jsonencode({ event_type = "aws-cloudwatch-trigger" })
}

# 8. Izin IAM agar EventBridge bisa mengirim HTTP POST
resource "aws_iam_role" "eventbridge_role" {
  name = "skripsi-eventbridge-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "events.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "eventbridge_policy" {
  name = "skripsi-eventbridge-policy"
  role = aws_iam_role.eventbridge_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["events:InvokeApiDestination"], Resource = [aws_cloudwatch_event_api_destination.github_api.arn] }]
  })
}