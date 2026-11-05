resource "aws_iam_role" "prod_ec2" {
  name = "prod-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "prod_ec2_ssm" {
  role       = aws_iam_role.prod_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "prod_ec2" {
  name = "prod-ec2-profile"
  role = aws_iam_role.prod_ec2.name
}

resource "aws_iam_role_policy" "prod_ec2_app" {
  name = "prod-application-access"
  role = aws_iam_role.prod_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:BatchWriteItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.prod_sessions.arn,
          "${aws_dynamodb_table.prod_sessions.arn}/index/*",
          aws_dynamodb_table.prod_otp.arn,
          "${aws_dynamodb_table.prod_otp.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.prod_app.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.prod_app.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:SendMessageBatch"
        ]
        Resource = aws_sqs_queue.prod_processing.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.prod_app.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_db_instance.prod_mysql.master_user_secret[0].secret_arn
      },
      {
        Effect = "Allow"
        Action = ["ssm:GetParameter"]
        Resource = [
          local.jwt_secret_parameter_arn,
          local.jwt_refresh_secret_parameter_arn,
          local.release_sha_parameter_arn
        ]
      }
    ]
  })
}

resource "aws_ssm_parameter" "prod_release_sha" {
  name        = var.release_sha_parameter_name
  description = "Backend release deployed to the production API Auto Scaling group"
  type        = "String"
  value       = var.initial_release_sha

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Environment = "prod"
    Application = "BlessedBox API"
  }
}

resource "aws_cloudwatch_log_group" "prod_app" {
  name              = "/blessedbox/prod/application"
  retention_in_days = 365

  tags = {
    Environment = "prod"
  }
}

resource "aws_launch_template" "prod_app" {
  name                   = "prod-api"
  image_id               = var.app_ami_id
  instance_type          = var.app_instance_type
  update_default_version = true
  user_data = base64encode(templatefile("${path.module}/templates/prod-app-user-data.sh.tftpl", {
    app_dir                     = "/home/ubuntu/blessed-box/Blessed-Box-BackEnd"
    aws_region                  = var.aws_region
    db_secret_arn               = aws_db_instance.prod_mysql.master_user_secret[0].secret_arn
    db_host                     = aws_db_instance.prod_mysql.address
    db_name                     = aws_db_instance.prod_mysql.db_name
    release_sha_parameter_name  = aws_ssm_parameter.prod_release_sha.name
    dynamodb_sessions_table     = aws_dynamodb_table.prod_sessions.name
    dynamodb_otp_table          = aws_dynamodb_table.prod_otp.name
    ssm_jwt_secret_name         = var.jwt_secret_parameter_name
    ssm_jwt_refresh_secret_name = var.jwt_refresh_secret_parameter_name
    sqs_queue_url               = aws_sqs_queue.prod_processing.id
    s3_bucket                   = aws_s3_bucket.prod_app.bucket
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.prod_ec2.name
  }

  vpc_security_group_ids = [aws_security_group.prod_app.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      encrypted             = true
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "prod-api"
      Environment = "prod"
    }
  }
}

resource "aws_autoscaling_group" "prod_app" {
  name                      = "prod-api"
  min_size                  = var.asg_min_size
  desired_capacity          = var.asg_desired_capacity
  max_size                  = var.asg_max_size
  health_check_type         = "ELB"
  health_check_grace_period = 300
  vpc_zone_identifier       = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]
  target_group_arns         = [aws_lb_target_group.prod_app.arn]
  capacity_rebalance        = true
  depends_on = [
    aws_iam_role_policy.prod_ec2_app,
    aws_iam_role_policy_attachment.prod_ec2_ssm
  ]

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }

  launch_template {
    id      = aws_launch_template.prod_app.id
    version = aws_launch_template.prod_app.latest_version
  }

  tag {
    key                 = "Environment"
    value               = "prod"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "prod-api"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]

    precondition {
      condition = (
        var.asg_min_size <= var.asg_desired_capacity &&
        var.asg_desired_capacity <= var.asg_max_size
      )
      error_message = "Auto Scaling capacities must satisfy min_size <= desired_capacity <= max_size."
    }
  }
}

resource "aws_autoscaling_policy" "prod_app_cpu" {
  name                   = "prod-api-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.prod_app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50
  }
}
