resource "aws_iam_role" "prod_notification_lambda" {
  name = "prod-notification-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "prod_notification_lambda_logs" {
  role       = aws_iam_role.prod_notification_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "prod_notification_lambda" {
  name = "prod-notification-lambda-access"
  role = aws_iam_role.prod_notification_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.prod_processing.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ses:FromAddress" = var.ses_sender_email
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "prod_notification_lambda" {
  name              = "/aws/lambda/prod-sqs-message-processor"
  retention_in_days = 365

  tags = {
    Environment = "prod"
  }
}

resource "aws_lambda_function" "prod_notification" {
  filename         = data.archive_file.prod_notification_lambda.output_path
  source_code_hash = data.archive_file.prod_notification_lambda.output_base64sha256
  function_name    = "prod-sqs-message-processor"
  role             = aws_iam_role.prod_notification_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  timeout          = 30

  environment {
    variables = {
      SENDER_EMAIL = var.ses_sender_email
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.prod_notification_lambda_logs,
    aws_iam_role_policy.prod_notification_lambda,
    aws_cloudwatch_log_group.prod_notification_lambda
  ]

  tags = {
    Name        = "prod-sqs-message-processor"
    Environment = "prod"
  }
}

resource "aws_lambda_event_source_mapping" "prod_notification" {
  event_source_arn = aws_sqs_queue.prod_processing.arn
  function_name    = aws_lambda_function.prod_notification.arn
  batch_size       = 10
  enabled          = true
}

resource "aws_iam_role" "prod_expiry_lambda" {
  name = "prod-expiry-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "prod_expiry_lambda_logs" {
  role       = aws_iam_role.prod_expiry_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "prod_expiry_lambda_vpc" {
  role       = aws_iam_role.prod_expiry_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "prod_expiry_lambda_secret" {
  name = "prod-expiry-lambda-secret-access"
  role = aws_iam_role.prod_expiry_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
      Resource = aws_db_instance.prod_mysql.master_user_secret[0].secret_arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "prod_expiry_lambda" {
  name              = "/aws/lambda/prod-update-expiration"
  retention_in_days = 365

  tags = {
    Environment = "prod"
  }
}

resource "aws_lambda_function" "prod_expiry" {
  filename         = data.archive_file.prod_expiry_lambda.output_path
  source_code_hash = data.archive_file.prod_expiry_lambda.output_base64sha256
  function_name    = "prod-update-expiration"
  role             = aws_iam_role.prod_expiry_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  timeout          = 60

  vpc_config {
    subnet_ids         = [aws_subnet.prod_private_a.id, aws_subnet.prod_private_b.id]
    security_group_ids = [aws_security_group.prod_expiry_lambda.id]
  }

  environment {
    variables = {
      DB_SECRET_ARN = aws_db_instance.prod_mysql.master_user_secret[0].secret_arn
      DB_HOST       = aws_db_instance.prod_mysql.address
      DB_PORT       = tostring(aws_db_instance.prod_mysql.port)
      DB_NAME       = aws_db_instance.prod_mysql.db_name
      EXPIRY_TABLE  = var.expiry_table_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.prod_expiry_lambda_logs,
    aws_iam_role_policy_attachment.prod_expiry_lambda_vpc,
    aws_iam_role_policy.prod_expiry_lambda_secret,
    aws_cloudwatch_log_group.prod_expiry_lambda,
    aws_vpc_endpoint.prod_secretsmanager
  ]

  tags = {
    Name        = "prod-update-expiration"
    Environment = "prod"
  }
}

resource "aws_iam_role" "prod_scheduler" {
  name = "prod-expiry-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "prod_scheduler" {
  name = "prod-expiry-scheduler-invoke"
  role = aws_iam_role.prod_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.prod_expiry.arn
    }]
  })
}

resource "aws_scheduler_schedule" "prod_expiry" {
  name                         = "prod-expiry-every-15-minutes"
  description                  = "Runs the production access-code expiry task"
  schedule_expression          = "rate(15 minutes)"
  schedule_expression_timezone = "UTC"
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.prod_expiry.arn
    role_arn = aws_iam_role.prod_scheduler.arn
    input    = jsonencode({})
  }

  depends_on = [aws_iam_role_policy.prod_scheduler]
}

resource "aws_lambda_permission" "prod_expiry_scheduler" {
  statement_id  = "AllowProductionSchedulerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.prod_expiry.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.prod_expiry.arn
}
