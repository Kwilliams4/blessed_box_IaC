# BlessedBox Infrastructure as Code (IaC)

## Overview

BlessedBox Infrastructure as Code (IaC) contains the cloud infrastructure definitions used to deploy and manage the BlessedBox platform on AWS.

The project follows Infrastructure as Code principles using Terraform, allowing environments to be provisioned, versioned, and maintained consistently across development, staging, and production.

## Architecture

The infrastructure is designed around AWS best practices, focusing on security, scalability, and maintainability.

### Core Components

- Amazon VPC
- Public and Private Subnets
- Internet Gateway
- NAT Gateway
- Security Groups
- Amazon EC2
- Amazon RDS (MySQL)
- Application Load Balancer (ALB)
- Amazon Route 53
- AWS Certificate Manager (ACM)
- Amazon SQS
- AWS Lambda
- Amazon SES
- Amazon CloudWatch

## Repository Structure

```text
.
├── environments/
│   ├── dev/
│   ├── staging/
│   └── prod/
│
├── modules/
│   ├── vpc/
│   ├── security-groups/
│   ├── ec2/
│   ├── rds/
│   ├── alb/
│   ├── route53/
│   ├── acm/
│   ├── sqs/
│   ├── lambda/
│   └── monitoring/
│
├── variables.tf
├── outputs.tf
├── providers.tf
├── backend.tf
└── README.md
```

## Features

### Networking

- Isolated VPC environment
- Public and private subnet architecture
- Internet Gateway for public resources
- NAT Gateway for outbound private subnet traffic
- Restricted security groups following least-privilege principles

### Compute

- EC2 instances hosting the BlessedBox backend
- Load balancing through Application Load Balancer
- Auto-scalable architecture ready for future growth

### Database

- Amazon RDS MySQL deployment
- Private subnet placement
- Controlled inbound access through security groups

### Messaging & Events

- Amazon SQS for asynchronous processing
- AWS Lambda for event-driven workloads
- Decoupled architecture between application services

### Authentication & Notifications

- OTP generation workflow
- Email delivery through Amazon SES
- Queue-based email processing for improved reliability

### Monitoring

- CloudWatch Logs
- CloudWatch Metrics
- CloudWatch Alarms
- Operational visibility and alerting

## Prerequisites

Before deploying, ensure the following tools are installed:

- Terraform >= 1.5
- AWS CLI
- AWS Account
- Git

Verify installations:

```bash
terraform version
aws --version
git --version
```

## Configuration

Configure AWS credentials:

```bash
aws configure
```

Required values:

```text
AWS Access Key ID
AWS Secret Access Key
AWS Region
```

## Deployment

Initialize Terraform:

```bash
terraform init
```

Review the execution plan:

```bash
terraform plan
```

Apply the infrastructure:

```bash
terraform apply
```

Destroy resources when needed:

```bash
terraform destroy
```

## Environment Management

Deploy a specific environment:

```bash
cd environments/dev

terraform init
terraform plan
terraform apply
```

Example environments:

- Development
- Staging
- Production

Each environment maintains its own variables and state configuration.

## Security

Security considerations implemented:

- Principle of least privilege
- Private database access
- Restricted inbound traffic
- HTTPS with ACM certificates
- Secure communication between services
- Environment-specific configurations

## CI/CD

Infrastructure changes can be automated through GitHub Actions.

Typical workflow:

1. Pull Request created
2. Terraform validation
3. Terraform plan generation
4. Review and approval
5. Terraform apply

## Project Context

BlessedBox is a platform designed to support Operation Christmas Child (OCC) box collection efforts by providing digital tracking, registration, and reporting capabilities.

This infrastructure supports backend services, database operations, OTP workflows, asynchronous processing, and monitoring across AWS services.

## Future Improvements

- Terraform remote state with S3 and DynamoDB
- Multi-environment pipelines
- Auto Scaling Groups
- ECS/Fargate migration
- AWS WAF integration
- Centralized logging strategy
- Disaster recovery architecture

## Author

Kenneth Williams

Computer Engineer | AWS Solutions Architect

## License

This project is licensed under the MIT License.
