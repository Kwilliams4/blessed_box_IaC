resource "aws_s3_bucket" "prod_app" {
  bucket_prefix = "blessedbox-prod-app-"

  tags = {
    Name        = "blessedbox-prod-app"
    Environment = "prod"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "prod_app" {
  bucket                  = aws_s3_bucket.prod_app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "prod_app" {
  bucket = aws_s3_bucket.prod_app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "prod_app" {
  bucket = aws_s3_bucket.prod_app.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "prod_sessions" {
  name                        = "prod-app-sessions"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "userId"
  deletion_protection_enabled = true

  attribute {
    name = "userId"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToLive"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "prod-dynamodb-sessions"
    Environment = "prod"
  }
}

resource "aws_dynamodb_table" "prod_otp" {
  name                        = "prod-app-otp"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "userId"
  deletion_protection_enabled = true

  attribute {
    name = "userId"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToLive"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "prod-dynamodb-otp"
    Environment = "prod"
  }
}
