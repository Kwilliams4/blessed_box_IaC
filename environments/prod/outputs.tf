output "api_url" {
  description = "Public HTTPS URL for the production API"
  value       = "https://${var.api_domain_name}"
}

output "alb_dns_name" {
  description = "ALB DNS name registered in Route 53"
  value       = aws_lb.prod_alb.dns_name
}

output "autoscaling_group_name" {
  description = "Production API Auto Scaling group"
  value       = aws_autoscaling_group.prod_app.name
}

output "rds_endpoint" {
  description = "Private MySQL endpoint"
  value       = aws_db_instance.prod_mysql.endpoint
}

output "sqs_queue_url" {
  description = "Production notification processing queue URL"
  value       = aws_sqs_queue.prod_processing.id
}

output "sqs_dead_letter_queue_url" {
  description = "Production notification dead-letter queue URL"
  value       = aws_sqs_queue.prod_dlq.id
}

output "s3_bucket_name" {
  description = "Production object storage bucket"
  value       = aws_s3_bucket.prod_app.bucket
}

output "dynamodb_sessions_table" {
  description = "DynamoDB sessions table"
  value       = aws_dynamodb_table.prod_sessions.name
}

output "dynamodb_otp_table" {
  description = "DynamoDB OTP table"
  value       = aws_dynamodb_table.prod_otp.name
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL protecting the public ALB"
  value       = aws_wafv2_web_acl.prod_api.arn
}
