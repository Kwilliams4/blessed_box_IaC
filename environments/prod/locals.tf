data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  public_a_cidr      = cidrsubnet(var.vpc_cidr, 8, 1)
  public_b_cidr      = cidrsubnet(var.vpc_cidr, 8, 2)
  private_a_cidr     = cidrsubnet(var.vpc_cidr, 8, 11)
  private_b_cidr     = cidrsubnet(var.vpc_cidr, 8, 12)
  cloudtrail_name    = "prod-cloudtrail"
  cloudtrail_bucket  = "blessedbox-prod-cloudtrail-${data.aws_caller_identity.current.account_id}"
  cloudtrail_arn     = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
}

data "archive_file" "prod_notification_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../dev/temp"
  output_path = "${path.module}/../../build/prod-lambda.zip"
}

data "archive_file" "prod_expiry_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../dev/expiry_lambda"
  output_path = "${path.module}/../../build/prod-expiry-lambda.zip"
}
