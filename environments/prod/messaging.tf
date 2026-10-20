resource "aws_sqs_queue" "prod_dlq" {
  name                      = "prod-processing-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = {
    Name        = "prod-processing-dlq"
    Environment = "prod"
  }
}

resource "aws_sqs_queue" "prod_processing" {
  name                       = "prod-processing-queue"
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 180
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.prod_dlq.arn
    maxReceiveCount     = 5
  })

  tags = {
    Name        = "prod-processing-queue"
    Environment = "prod"
  }
}
