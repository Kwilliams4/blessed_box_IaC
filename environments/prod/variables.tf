variable "aws_region" {
  type        = string
  description = "AWS region for production resources"
  default     = "us-east-2"
}

variable "app_ami_id" {
  type        = string
  description = "AMI preconfigured with the Blessed Box API and CloudWatch Agent"

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.app_ami_id))
    error_message = "app_ami_id must be a valid EC2 AMI ID."
  }
}

variable "api_domain_name" {
  type        = string
  description = "Public API DNS name managed by the specified Route 53 hosted zone"
}

variable "route53_zone_id" {
  type        = string
  description = "Route 53 hosted zone ID for api_domain_name"
}

variable "alb_certificate_arn" {
  type        = string
  description = "ARN of an ACM certificate in aws_region covering api_domain_name"
}

variable "ses_sender_email" {
  type        = string
  description = "Verified SES sender address used by the notification Lambda"
}

variable "alarm_email" {
  type        = string
  description = "Email address subscribed to production CloudWatch alarm notifications"
}

variable "expiry_table_name" {
  type        = string
  description = "MySQL table processed by the scheduled expiry Lambda"
  default     = "access_codes"
}

variable "vpc_cidr" {
  type        = string
  description = "Production VPC CIDR; kept separate from the development VPC"
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(regex("/16$", var.vpc_cidr))
    error_message = "vpc_cidr must be an IPv4 /16 network to fit the production subnets."
  }
}

variable "app_instance_type" {
  type        = string
  description = "EC2 instance type used by the API Auto Scaling group"
  default     = "t3.small"
}

variable "db_instance_class" {
  type        = string
  description = "RDS MySQL instance class"
  default     = "db.t3.medium"
}

variable "asg_min_size" {
  type        = number
  description = "Minimum number of API instances"
  default     = 2

  validation {
    condition     = var.asg_min_size >= 2
    error_message = "Production must keep at least two API instances running."
  }
}

variable "asg_desired_capacity" {
  type        = number
  description = "Initial desired number of API instances"
  default     = 2

  validation {
    condition     = var.asg_desired_capacity >= 2
    error_message = "Production must start with at least two API instances."
  }
}

variable "asg_max_size" {
  type        = number
  description = "Maximum number of API instances"
  default     = 6

  validation {
    condition     = var.asg_max_size >= 2
    error_message = "asg_max_size must be at least two."
  }
}

variable "waf_rate_limit" {
  type        = number
  description = "Maximum requests per IP during the WAF evaluation window"
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100
    error_message = "waf_rate_limit must be at least 100."
  }
}
