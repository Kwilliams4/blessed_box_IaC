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

### Production environment

The production Terraform configuration in `environments/prod` implements the
two-AZ architecture from the Blessed Box production diagram: public ALB subnets,
private application and RDS subnets, one NAT gateway per AZ, EC2 Auto Scaling,
WAF, Route 53, Multi-AZ MySQL, DynamoDB, encrypted S3, SQS with a DLQ, SES
notification processing, scheduled expiry processing, CloudWatch alarms/logs,
and a multi-region CloudTrail. Terraform resources are split across files by
concern; all `.tf` files in the directory are part of the same environment and
state.

Before planning production, prepare:

- An application AMI in the selected region with the API installed, listening
  on port 4000, exposing `/health`, the SSM Agent installed, and the CloudWatch
  Agent configured to send application logs to `/blessedbox/prod/application`.
  Configure the application to use the production table, queue, bucket, and
  RDS secret outputs rather than development resources.
- An ACM certificate in the selected region for the API name. DNS validation
  and the API record must be configured at the DNS provider (for example,
  Namecheap).
- A verified SES sender identity with production sending enabled, plus an email
  address for alarm notifications. Confirm the SNS email subscription after
  the first apply.
- AWS credentials authorized to create the listed services and IAM roles.
- Terraform >= 1.5, AWS CLI, and Node.js 22 (for packaging the scheduled
  Lambda).
- Node.js dependencies for the scheduled expiry Lambda:
  `npm ci --prefix ../dev/expiry_lambda`.

The certificate ARN, API name, AMI ID, SES sender, and alarm email are required
Terraform inputs. Set them in an untracked
`environments/prod/terraform.tfvars` file (Terraform variable files are ignored
by Git). Do not commit passwords or credentials; RDS generates and manages its
master password in Secrets Manager.

```hcl
app_ami_id         = "ami-REPLACE_WITH_PRODUCTION_AMI"
api_domain_name    = "api.example.org"
alb_certificate_arn = "arn:aws:acm:us-east-2:ACCOUNT_ID:certificate/CERTIFICATE_ID"
ses_sender_email   = "noreply@example.org"
alarm_email        = "oncall@example.org"
```

After applying, create a CNAME record at the DNS provider for `api_domain_name`
that points to Terraform's `alb_dns_name` output. Add ACM's DNS-validation
CNAME as a separate record; it does not replace the API CNAME.

```bash
cd environments/prod
npm ci --prefix ../dev/expiry_lambda
terraform init
terraform validate
terraform plan
```

The default production CIDR is `10.1.0.0/16` so it does not overlap the
development VPC. Production uses two NAT gateways and a Multi-AZ database, so
review the AWS cost estimate in the plan before applying. RDS, DynamoDB, and
the production buckets have deletion protection; this configuration also uses
a local Terraform state unless a remote backend is configured separately.

#### Emergency MySQL access from a local machine

Production RDS stays private (`publicly_accessible = false`). For emergency
access, open an AWS Systems Manager port-forwarding session through a running
production application instance; do not add your IP to the database security
group or expose port 3306 to the internet.

Requirements:

- AWS CLI v2 configured for the production account and region.
- Session Manager plugin installed locally.
- An operator identity authorized to describe EC2/RDS instances, start and end
  SSM sessions to the tagged production instances using the
  `AWS-StartPortForwardingSessionToRemoteHost` document, and read the RDS
  master secret in Secrets Manager. Grant these permissions only to designated
  operators; they are not granted to a developer's machine by this Terraform.
- The selected EC2 instance must be online in Systems Manager. Its AMI needs
  the SSM Agent, and the instance profile in this configuration already
  includes `AmazonSSMManagedInstanceCore`.

In PowerShell, from the repository root, find the private database endpoint
and one healthy-enough running application instance:

```powershell
$Region = "us-east-2"
$DbHost = aws rds describe-db-instances `
  --region $Region `
  --db-instance-identifier blessedbox-prod-mysql `
  --query "DBInstances[0].Endpoint.Address" `
  --output text

$InstanceId = aws ec2 describe-instances `
  --region $Region `
  --filters "Name=tag:Name,Values=prod-api" "Name=tag:Environment,Values=prod" "Name=instance-state-name,Values=running" `
  --query "Reservations[].Instances[].InstanceId | [0]" `
  --output text

if (-not $DbHost -or $DbHost -eq "None") { throw "Could not find the production RDS endpoint." }
if (-not $InstanceId -or $InstanceId -eq "None") { throw "No running production EC2 instance was found." }
```

Start the tunnel and leave this terminal open:

```powershell
aws ssm start-session `
  --region $Region `
  --target $InstanceId `
  --document-name AWS-StartPortForwardingSessionToRemoteHost `
  --parameters "host=$DbHost,portNumber=3306,localPortNumber=3306"
```

While the session is active, connect your MySQL client (for example,
MySQL Workbench) to `127.0.0.1:3306`. Retrieve the RDS-managed credentials
only when needed:

```powershell
Set-Location .\environments\prod
$SecretArn = terraform output -raw db_credentials_secret_arn
$SecretJson = aws secretsmanager get-secret-value `
  --region $Region `
  --secret-id $SecretArn `
  --query SecretString `
  --output text
$DbCredentials = $SecretJson | ConvertFrom-Json
$DbCredentials.username
```

Use the displayed username and the password in `$DbCredentials` in your client;
in the MySQL command-line client, use `mysql --host 127.0.0.1 --port 3306
--user $($DbCredentials.username) --password` and enter the password at its
prompt. Treat the master credentials as privileged, do not paste them into
logs or commit them, and close the tunnel with `Ctrl+C` when finished. The
forwarded local port is available only while the SSM session is running.

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
