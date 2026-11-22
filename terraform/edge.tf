data "aws_ec2_managed_prefix_list" "cloudfront_origin" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# The origin verification value is stored in Terraform state. Protect state
# as a secret and avoid exposing it through outputs or CI logs.
resource "random_password" "origin_header" {
  length  = 32
  special = false
}

# The Free flat-rate CloudFront plan cannot use a private VPC origin. The ALB
# is public, but its listener accepts only CloudFront traffic with the secret.
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.1"

  name                       = "${substr(local.name, 0, 24)}-api-alb"
  load_balancer_type         = "application"
  internal                   = false
  enable_deletion_protection = false
  vpc_id                     = module.vpc.vpc_id
  subnets                    = module.vpc.public_subnets

  # Application pods receive traffic on port 8080.
  security_group_ingress_rules = {
    cloudfront_http = {
      description    = "HTTP from CloudFront origin-facing servers"
      from_port      = "80"
      to_port        = "80"
      ip_protocol    = "tcp"
      prefix_list_id = data.aws_ec2_managed_prefix_list.cloudfront_origin.id
    }
  }

  security_group_egress_rules = {
    application = {
      description = "HTTP to application targets in the VPC"
      from_port   = "8080"
      to_port     = "8080"
      ip_protocol = "tcp"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      fixed_response = {
        content_type = "text/plain"
        message_body = "Forbidden"
        status_code  = "403"
      }
      rules = {
        cloudfront_only = {
          priority = 100
          actions = [{
            forward = {
              target_group_key = "api"
            }
          }]
          conditions = [{
            http_header = {
              http_header_name = "X-Origin-Verify"
              values           = [random_password.origin_header.result]
            }
          }]
        }
      }
    }
  }

  # The AWS Load Balancer Controller TargetGroupBinding in
  # load_balancer_controller.tf registers backend pod IPs. Terraform owns
  # this ALB and target group.
  target_groups = {
    api = {
      name              = "${substr(local.name, 0, 25)}-api-tg"
      protocol          = "HTTP"
      port              = 8080
      target_type       = "ip"
      create_attachment = false
      health_check = {
        enabled = true
        path    = "/actuator/health/readiness"
        matcher = "200"
      }
    }
  }

  tags = local.common_tags
}

# The bucket starts empty. Upload the compiled UI after applying Terraform.
resource "aws_s3_bucket" "ui" {
  bucket_prefix = "${substr(local.name, 0, 33)}-ui-"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "ui" {
  bucket                  = aws_s3_bucket.ui.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "ui" {
  bucket = aws_s3_bucket.ui.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ui" {
  bucket = aws_s3_bucket.ui.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "ui" {
  bucket = aws_s3_bucket.ui.id

  versioning_configuration {
    status = "Enabled"
  }
}

# A CloudFront-scope web ACL is required for the $0/month Free plan.
#resource "aws_wafv2_web_acl" "cloudfront" {
#  provider = aws.us_east_1
#
#  name  = "${local.name}-cloudfront"
#  scope = "CLOUDFRONT"
#
#  default_action {
#    allow {}
#  }
#
#  visibility_config {
#    cloudwatch_metrics_enabled = false
#    metric_name                = "${local.name}-cloudfront"
#    sampled_requests_enabled   = false
#  }
#
#  tags = local.common_tags
#}

module "cdn" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "6.7.1"

  # Wait for the public ALB and its origin-verification listener rule.
  depends_on = [module.alb]

  comment             = "${local.name} frontend and API"
  enabled             = true
  default_root_object = "index.html"
  wait_for_deployment = true
  #web_acl_id          = aws_wafv2_web_acl.cloudfront.arn

  origin_access_control = {
    s3 = {
      description      = "CloudFront access to ${local.name} UI"
      origin_type      = "s3"
      signing_behavior = "always"
      signing_protocol = "sigv4"
    }
  }

  origin = {
    ui = {
      domain_name               = aws_s3_bucket.ui.bucket_regional_domain_name
      origin_access_control_key = "s3"
    }
    api = {
      domain_name = module.alb.dns_name
      custom_header = {
        X-Origin-Verify = random_password.origin_header.result
      }
      custom_origin_config = {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "http-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  default_cache_behavior = {
    target_origin_id       = "ui"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
    compress               = true
  }

  ordered_cache_behavior = [
    {
      path_pattern             = "/api/*"
      target_origin_id         = "api"
      viewer_protocol_policy   = "redirect-to-https"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader
      compress                 = true
    }
  ]

  viewer_certificate = {
    cloudfront_default_certificate = true
  }

  tags = local.common_tags
}

#resource "aws_pricingplanmanager_subscription" "cloudfront_free" {
#  provider = aws.us_east_1
#
#  plan_family = "CloudFront"
#  plan_tier   = "FREE"
#  resource_arns = [
#    module.cdn.cloudfront_distribution_arn,
#    aws_wafv2_web_acl.cloudfront.arn,
#  ]
#}

data "aws_iam_policy_document" "ui_cloudfront" {
  statement {
    sid     = "AllowCloudFrontRead"
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.ui.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cdn.cloudfront_distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "ui" {
  bucket = aws_s3_bucket.ui.id
  policy = data.aws_iam_policy_document.ui_cloudfront.json

  depends_on = [aws_s3_bucket_public_access_block.ui]
}
