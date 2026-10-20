resource "aws_s3_bucket_policy" "prod_app_tls" {
  bucket = aws_s3_bucket.prod_app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.prod_app.arn,
        "${aws_s3_bucket.prod_app.arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}

resource "aws_s3_bucket" "prod_cloudtrail" {
  bucket = local.cloudtrail_bucket

  tags = {
    Name        = "blessedbox-prod-cloudtrail"
    Environment = "prod"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "prod_cloudtrail" {
  bucket                  = aws_s3_bucket.prod_cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "prod_cloudtrail" {
  bucket = aws_s3_bucket.prod_cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "prod_cloudtrail" {
  bucket = aws_s3_bucket.prod_cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "prod_cloudtrail" {
  bucket = aws_s3_bucket.prod_cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudTrailBucketAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.prod_cloudtrail.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.cloudtrail_arn
          }
        }
      },
      {
        Sid       = "AllowCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.prod_cloudtrail.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.cloudtrail_arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.prod_cloudtrail.arn,
          "${aws_s3_bucket.prod_cloudtrail.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "prod_cloudtrail" {
  name              = "/aws/cloudtrail/prod"
  retention_in_days = 365

  tags = {
    Environment = "prod"
  }
}

resource "aws_iam_role" "prod_cloudtrail" {
  name = "prod-cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "cloudtrail.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "prod_cloudtrail" {
  name = "prod-cloudtrail-cloudwatch-logs"
  role = aws_iam_role.prod_cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.prod_cloudtrail.arn}:log-stream:*"
    }]
  })
}

resource "aws_cloudtrail" "prod" {
  name                          = local.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.prod_cloudtrail.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.prod_cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.prod_cloudtrail.arn

  depends_on = [
    aws_s3_bucket_policy.prod_cloudtrail,
    aws_iam_role_policy.prod_cloudtrail
  ]

  tags = {
    Name        = "prod-cloudtrail"
    Environment = "prod"
  }
}

resource "aws_sns_topic" "prod_alarms" {
  name = "prod-cloudwatch-alarms"

  tags = {
    Name        = "prod-cloudwatch-alarms"
    Environment = "prod"
  }
}

resource "aws_sns_topic_subscription" "prod_alarm_email" {
  topic_arn = aws_sns_topic.prod_alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "prod_unhealthy_hosts" {
  alarm_name          = "prod-alb-unhealthy-hosts"
  alarm_description   = "One or more production API targets are unhealthy"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.prod_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.prod_app.arn_suffix
  }

  alarm_actions = [aws_sns_topic.prod_alarms.arn]
  ok_actions    = [aws_sns_topic.prod_alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "prod_rds_cpu" {
  alarm_name          = "prod-rds-high-cpu"
  alarm_description   = "Production RDS CPU utilization is above 80 percent"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.prod_mysql.identifier
  }

  alarm_actions = [aws_sns_topic.prod_alarms.arn]
}
