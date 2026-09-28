# 1. Route 53 Health Check untuk Region A
# Analogi: Seperti fitur IP SLA / Track Object di Cisco Router untuk ping IP ISP utama.
resource "aws_route53_health_check" "primary_health_check" {
  ip_address        = aws_instance.web_server.public_ip
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  request_interval  = 10 # Cek setiap 10 detik (Fast Interval untuk RTO minimal)
  failure_threshold = 1  # 1x gagal langsung dianggap DOWN (untuk kebutuhan lab RTO)

  tags = {
    Name = "Skripsi-HealthCheck-RegionA"
  }
}

# 2. CloudWatch Alarm yang terikat pada Health Check
# Saat Health Check bernilai 0 (Unhealthy), Alarm ini akan TRIGGER (ALARM State)
resource "aws_cloudwatch_metric_alarm" "health_check_alarm" {
  alarm_name          = "Skripsi-RegionA-Down-Alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 10
  statistic           = "Minimum"
  threshold           = 1 # Jika status < 1 (berarti 0 / Down)

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary_health_check.id
  }

  alarm_description = "Trigger failover ketika Region A down"
}