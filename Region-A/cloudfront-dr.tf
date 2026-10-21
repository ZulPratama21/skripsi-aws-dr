# AWS Disaster Recovery laboratory - EC2-only with CloudFront origin failover.
# Place this file in Region-A/ alongside the existing main.tf and failover.tf.
# CloudFront is a global service; no hosted zone or custom domain is required.

variable "region_b_elastic_ip" {
  description = "Static Elastic IP for the stopped-standby EC2 instance in Tokyo"
  type        = string
  default     = "35.73.68.202"
}

locals {
  # CloudFront custom origins require DNS names, not raw IPv4 addresses.
  # Both EC2 origins use Elastic IPs so their public hostnames remain stable.
  region_a_origin_dns = aws_eip.primary_static_ip.public_dns
  region_b_origin_dns = "ec2-${replace(var.region_b_elastic_ip, ".", "-")}.ap-northeast-1.compute.amazonaws.com"
}

resource "aws_cloudfront_distribution" "dr_failover" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "EC2-only DR experiment: Singapore primary, Tokyo secondary"
  default_root_object = "index.html"
  price_class         = "PriceClass_200"

  origin {
    domain_name         = local.region_a_origin_dns
    origin_id           = "region-a-primary"
    connection_attempts = 1
    connection_timeout  = 3

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 5
    }
  }

  origin {
    domain_name         = local.region_b_origin_dns
    origin_id           = "region-b-secondary"
    connection_attempts = 1
    connection_timeout  = 3

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 5
    }
  }

  origin_group {
    origin_id = "dr-origin-group"

    failover_criteria {
      status_codes = [500, 502, 503, 504]
    }

    # Terraform preserves member order: primary first, secondary second.
    member {
      origin_id = "region-a-primary"
    }
    member {
      origin_id = "region-b-secondary"
    }
  }

  default_cache_behavior {
    target_origin_id       = "dr-origin-group"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false

    # AWS-managed CachingDisabled: all object TTLs are zero.
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  }

  # Error caching is distinct from ordinary object caching.
  dynamic "custom_error_response" {
    for_each = toset([500, 502, 503, 504])
    content {
      error_code            = custom_error_response.value
      error_caching_min_ttl = 0
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name    = "Skripsi-EC2-DR-CloudFront"
    Project = "Skripsi-AWS-DR"
  }
}

output "cloudfront_dr_domain" {
  description = "AWS-provided hostname for the CloudFront DR distribution"
  value       = aws_cloudfront_distribution.dr_failover.domain_name
}

output "cloudfront_dr_url" {
  description = "Single HTTPS endpoint for the manual versus automatic DR experiment"
  value       = "https://${aws_cloudfront_distribution.dr_failover.domain_name}"
}
