
# ---------------------------------------------------------------------------------------------------------------------
# 1. NETWORK & SECURITY (VPC, Subnets, Security Group)
# ---------------------------------------------------------------------------------------------------------------------
variable "my_ip" {
  type        = string
  sensitive   = true
  description = "Tu IP pública para acceso administrativo"
}
variable "dev_ip" {
  type        = string
  sensitive   = true
  description = "IP pública para acceso de desarrollo"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Contraseña para la base de datos RDS"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "dev_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "dev-vpc"
    Environment = "dev"
  }
}

resource "aws_internet_gateway" "dev_igw" {
  vpc_id = aws_vpc.dev_vpc.id

  tags = {
    Name = "dev-igw"
  }
}

resource "aws_subnet" "dev_public_1" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "dev-public-subnet-1"
  }
}

resource "aws_subnet" "dev_public_2" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "dev-public-subnet-2"
  }
}

resource "aws_route_table" "dev_public_rt" {
  vpc_id = aws_vpc.dev_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev_igw.id
  }

  tags = {
    Name = "dev-public-route-table"
  }
}

resource "aws_route_table_association" "pub_1" {
  subnet_id      = aws_subnet.dev_public_1.id
  route_table_id = aws_route_table.dev_public_rt.id
}

resource "aws_route_table_association" "pub_2" {
  subnet_id      = aws_subnet.dev_public_2.id
  route_table_id = aws_route_table.dev_public_rt.id
}

resource "aws_security_group" "dev_restricted_sg" {
  name        = "dev-restricted-access"
  description = "Permite trafico entrante solo desde la IP de desarrollo"
  vpc_id      = aws_vpc.dev_vpc.id


  # Acceso MySQL a la base de datos RDS
  ingress {
    description = "MySQL desde mi IP"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.my_ip, var.dev_ip]
  }
  ingress {
    description     = "Node.js desde EC2 hacia MySQL"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  # Salida libre a internet para actualizaciones de paquetes
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "dev-restricted-sg"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# 2. COMPUTE (EC2 Instance)
# ---------------------------------------------------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "image-id"
    values = ["ami-099b38cf081b2de98"]
  }
}

resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-ssm-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

# Inline policy granting minimal write permissions to DynamoDB and send permissions to SQS
resource "aws_iam_role_policy" "ec2_app_policy" {
  name = "ec2-app-dynamo-sqs-policy"
  role = aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.dev_sessions.arn,
          aws_dynamodb_table.dev_otp.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:SendMessageBatch"
        ]
        Resource = aws_sqs_queue.dev_queue.arn
      }
    ]
  })
}

resource "aws_security_group" "ec2_sg" {
  name        = "mi-app-ec2-sg"
  description = "Security Group para la instancia EC2 de Node.js"
  vpc_id      = aws_vpc.dev_vpc.id


  ingress {
    description = "Acceso a la aplicacion Node.js"
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip, var.dev_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_instance" "dev_ec2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro" # Capa gratuita / Bajo costo para dev
  subnet_id              = aws_subnet.dev_public_1.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  root_block_device {
    volume_size = 20 # Suficiente para entornos de desarrollo comunes
    volume_type = "gp3"
  }

  tags = {
    Name        = "dev-ec2-instance"
    Environment = "dev"
  }
  lifecycle {
    # Debe estar en false para que Terraform te permita destruir la infraestructura
    prevent_destroy = false
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# 3. STORAGE & DATABASES (S3, RDS MySQL, DynamoDB)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "dev_bucket" {
  bucket_prefix = "dev-app-storage-" # Genera un nombre único automáticamente
  force_destroy = true               # Permite borrar el bucket en dev incluso si tiene archivos

  tags = {
    Name        = "dev-s3-bucket"
    Environment = "dev"
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "dev-rds-subnet-group"
  subnet_ids = [aws_subnet.dev_public_1.id, aws_subnet.dev_public_2.id]

  tags = {
    Name = "dev-rds-subnet-group"
  }
}

resource "aws_db_instance" "dev_mysql" {
  identifier            = "dev-mysql-db"
  allocated_storage     = 20
  max_allocated_storage = 50 # Auto-scaling de almacenamiento básico para pruebas
  engine                = "mysql"
  engine_version        = "8.0"
  instance_class        = "db.t3.micro" # Capa gratuita / Dev
  snapshot_identifier   = "blessed-box-7-agosto-2026"
  # db_name                   = "blessedbox_dev"
  username                  = "admin"
  password                  = var.db_password # Cambiar mediante variables secretas en entornos reales
  db_subnet_group_name      = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.dev_restricted_sg.id]
  publicly_accessible       = true # Requerido si te conectas directo desde tu PC, mitigado por el SG restrictivo
  skip_final_snapshot       = true # Evita retenciones costosas al destruir el entorno de pruebas
  final_snapshot_identifier = "rds-blessed-box-dev-snapshot"

  tags = {
    Name        = "dev-mysql-rds"
    Environment = "dev"
  }
  lifecycle {
    ignore_changes = [
      username,
      password,
      db_name
    ]
  }
}

resource "aws_dynamodb_table" "dev_sessions" {
  name         = "dev-app-sessions"
  billing_mode = "PAY_PER_REQUEST" # Costo cero si no se usa (On-Demand)
  hash_key     = "SessionId"

  attribute {
    name = "SessionId"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToLive"
    enabled        = true
  }

  tags = {
    Name        = "dev-dynamodb-sessions"
    Environment = "dev"
  }
}
resource "aws_dynamodb_table" "dev_otp" {
  name         = "dev-app-otp"
  billing_mode = "PAY_PER_REQUEST" # Costo cero si no se usa (On-Demand)
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToLive"
    enabled        = true
  }

  tags = {
    Name        = "dev-dynamodb-otp"
    Environment = "dev"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# 4. MESSAGING (SNS & SQS)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sns_topic" "dev_topic" {
  name = "dev-notifications-topic"
}

resource "aws_sqs_queue" "dev_queue" {
  name                       = "dev-processing-queue"
  message_retention_seconds  = 86400 # 1 día de retención es óptimo para dev
  max_message_size           = 262144
  visibility_timeout_seconds = 90
}

resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.dev_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.dev_queue.arn
}

resource "aws_sqs_queue_policy" "dev_queue_policy" {
  queue_url = aws_sqs_queue.dev_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.dev_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.dev_topic.arn
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# 5. SERVERLESS & API GATEWAY (Lambda & API Gateway HTTP)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "lambda_exec_role" {
  name = "dev-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_sqs_policy" {
  name        = "lambda-sqs-permissions"
  description = "Allows Lambda to poll messages from SQS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.dev_queue.arn
      },
      # NUEVO: Permiso para enviar correos con SES
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*" # SES requiere "*" para acciones de envío, controlado por la identidad del remitente
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }

    ]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_sqs_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_sqs_policy.arn
}
# Terraform busca tu código suelto en temp/ y crea el ZIP automáticamente
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/temp"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "dev_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "sqs_message_processor-dev"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  environment {
    variables = {
      SENDER_EMAIL = "blessedbox789@gmail.com" # Este correo DEBE estar verificado en AWS SES
    }
  }
}
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.dev_queue.arn
  function_name    = aws_lambda_function.dev_lambda.arn
  batch_size       = 10 # Number of records sent per invocation
  enabled          = true
}

resource "aws_apigatewayv2_api" "dev_api" {
  name          = "dev-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "api_lambda_integration" {
  api_id           = aws_apigatewayv2_api.dev_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.dev_lambda.invoke_arn
}

resource "aws_apigatewayv2_route" "api_route" {
  api_id    = aws_apigatewayv2_api.dev_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.api_lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "dev_stage" {
  api_id      = aws_apigatewayv2_api.dev_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dev_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.dev_api.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------------------------------------------------
# OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "ec2_public_ip" {
  value       = aws_instance.dev_ec2.public_ip
  description = "IP publica de tu instancia EC2"
}

output "rds_endpoint" {
  value       = aws_db_instance.dev_mysql.endpoint
  description = "Dirección de conexión para tu base de datos MySQL"
}

output "api_gateway_url" {
  value       = aws_apigatewayv2_api.dev_api.api_endpoint
  description = "URL publica base de tu API Gateway"
}

output "sqs_queue_url" {
  value       = aws_sqs_queue.dev_queue.id
  description = "URL de la cola SQS para pruebas de mensajería"
}
