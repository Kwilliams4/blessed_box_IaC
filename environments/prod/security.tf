resource "aws_security_group" "prod_alb" {
  name        = "prod-alb"
  description = "Public HTTP and HTTPS access to the production ALB"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "prod-alb"
    Environment = "prod"
  }
}

resource "aws_security_group" "prod_app" {
  name        = "prod-app"
  description = "API instances accept traffic only from the production ALB"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    description     = "API from ALB"
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [aws_security_group.prod_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "prod-app"
    Environment = "prod"
  }
}

resource "aws_security_group" "prod_db" {
  name        = "prod-db"
  description = "MySQL access only from production application and expiry Lambda"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    description     = "MySQL from API instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.prod_app.id]
  }

  ingress {
    description     = "MySQL from expiry Lambda"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.prod_expiry_lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "prod-db"
    Environment = "prod"
  }
}

resource "aws_security_group" "prod_expiry_lambda" {
  name        = "prod-expiry-lambda"
  description = "Expiry Lambda egress to RDS"
  vpc_id      = aws_vpc.prod_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "prod-expiry-lambda"
    Environment = "prod"
  }
}
