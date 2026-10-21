resource "aws_lb" "prod_alb" {
  name               = "prod-api-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.prod_alb.id]
  subnets            = [aws_subnet.prod_public_a.id, aws_subnet.prod_public_b.id]

  tags = {
    Name        = "prod-api-alb"
    Environment = "prod"
  }
}

resource "aws_lb_target_group" "prod_app" {
  name        = "prod-api-targets"
  port        = 4000
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.prod_vpc.id

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200-399"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "prod-api-targets"
    Environment = "prod"
  }
}

resource "aws_lb_listener" "prod_http" {
  load_balancer_arn = aws_lb.prod_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "prod_https" {
  load_balancer_arn = aws_lb.prod_alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.alb_certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_app.arn
  }
}

resource "aws_wafv2_web_acl" "prod_api" {
  name        = "prod-api-waf"
  description = "Managed protections and per-IP rate limiting for the production API"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "prod-common-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "prod-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "prod-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "PerIpRateLimit"
    priority = 40

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "prod-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "prod-api-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "prod-api-waf"
    Environment = "prod"
  }
}

resource "aws_wafv2_web_acl_association" "prod_api" {
  resource_arn = aws_lb.prod_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.prod_api.arn
}
