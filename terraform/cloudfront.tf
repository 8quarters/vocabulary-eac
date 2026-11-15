locals {
  s3_origin_id = "S3-UI-Origin"
  alb_origin_id = "EKS-ALB-Origin"
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for UI and EKS Backend API"
  default_root_object = "index.html"

  # ---------------------------------------------------------------------------
  # 1. S3 Origin (For Static UI Assets)
  # ---------------------------------------------------------------------------
  origin {
    domain_name              = "dictionary-2026"
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  # ---------------------------------------------------------------------------
  # 2. ALB Origin (For EKS Backend /api requests)
  # ---------------------------------------------------------------------------
  origin {
    domain_name = aws_alb.eks_alb.dns_name
    origin_id   = local.alb_origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "match-viewer" # or "https-only" if your ALB uses valid SSL certificates
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ---------------------------------------------------------------------------
  # Default Cache Behavior (UI Artifacts -> S3)
  # ---------------------------------------------------------------------------
  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    # Use CachingOptimized managed policy
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" 

    compress = true
  }

  # ---------------------------------------------------------------------------
  # Ordered Cache Behavior (/api/* -> EKS ALB Backend)
  # ---------------------------------------------------------------------------
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    target_origin_id = local.alb_origin_id

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]

    # Use CachingDisabled managed policy so dynamic API calls aren't cached
    cache_policy_id          = "4135ea2d-6df8-44a3-9cd3-4b5da47900b1"
    
    # Forward all headers, cookies, and query strings required by backend APIs
    origin_request_policy_id = "216adef6-5c7f-4794-b0ae-bb23c99b24f4" 
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# -----------------------------------------------------------------------------
# Origin Access Control (OAC) for secure S3 bucket access
# -----------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "s3-oac-dev"
  description                       = "OAC for UI S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
