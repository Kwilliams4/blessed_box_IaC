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

- An Ubuntu application AMI in the selected region with the API installed at
  `/home/ubuntu/blessed-box/Blessed-Box-BackEnd`, plus Git, Node.js, Python 3,
  and the SSM Agent. The production bootstrap clones the public backend
  repository at the release SHA stored in SSM, installs its dependencies,
  and replaces the pre-baked application directory. If AWS CLI is missing,
  EC2 user data installs it from the Ubuntu package repository. The API must
  expose `/health`; Terraform installs and enables `blessedbox-api.service`,
  runs it on port 4000, and refreshes its runtime configuration every
  15 minutes. If the AMI already starts this same `app.js` entry through PM2,
  bootstrap removes that matching PM2 process before handing startup to
  systemd.
  The backend must read `DYNAMODB_SESSIONS_TABLE` and `DYNAMODB_OTP_TABLE`
  when selecting its DynamoDB tables; production sets these to its `prod-*`
  tables rather than granting the EC2 role access to development tables.
  Configure the CloudWatch Agent to collect
  `/var/log/blessedbox/application.log` into `/blessedbox/prod/application`.
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

The certificate ARN, API name, AMI ID, initial backend release SHA, SES sender,
and alarm email are required Terraform inputs. Set them in an untracked
`environments/prod/terraform.tfvars` file (Terraform variable files are ignored
by Git). Do not put database passwords or JWT secrets in that file. RDS
generates and manages its master password in Secrets Manager; the EC2 role and
expiry Lambda can read only that RDS secret. The app's JWT signing keys are
SSM `SecureString` parameters. From the repository root, create them if they do
not already exist:

```hcl
aws_region          = "us-east-2"
app_ami_id          = "ami-REPLACE_WITH_PRODUCTION_AMI"
initial_release_sha = "40_CHARACTER_BACKEND_COMMIT_SHA"
api_domain_name     = "api.example.org"
alb_certificate_arn = "arn:aws:acm:us-east-2:ACCOUNT_ID:certificate/CERTIFICATE_ID"
ses_sender_email    = "noreply@example.org"
alarm_email         = "oncall@example.org"
```

```powershell
.\environments\prod\prepare-secrets.ps1 -Region us-east-2
```

The helper generates random JWT values only for missing parameters and never
overwrites existing ones. If you override the JWT parameter-name Terraform
variables, pass the same names to this helper. The EC2 bootstrap retrieves the
initial release SHA from `/blessedbox/prod/app/RELEASE_SHA`, checks out that
exact commit, installs its dependencies, then retrieves the RDS secret and JWT
parameters, writes `.env` in the application root with mode `0600`, and starts
the API only after configuration is available. Ensure `.env` is ignored by the
backend repository and never committed. Terraform seeds the release parameter
from `initial_release_sha` on first creation and ignores subsequent value drift
so Terraform does not overwrite releases published by GitHub Actions.

For each production release, the backend workflow should publish the triggering
commit SHA and use an Auto Scaling instance refresh as the deployment. Do not
deploy with a separate per-instance `git pull`/restart step: replacement
instances fetch the SHA from Parameter Store during bootstrap, and the refresh
rolls the whole group with the configured healthy-capacity and warmup settings.
For example, after configuring AWS credentials:

```bash
aws ssm put-parameter \
  --name /blessedbox/prod/app/RELEASE_SHA \
  --type String \
  --value "$GITHUB_SHA" \
  --overwrite

REFRESH_ID=$(aws autoscaling start-instance-refresh \
  --auto-scaling-group-name prod-api \
  --query InstanceRefreshId \
  --output text)

while true; do
  STATUS=$(aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name prod-api \
    --instance-refresh-ids "$REFRESH_ID" \
    --query "InstanceRefreshes[0].Status" \
    --output text)
  case "$STATUS" in
    Successful) break ;;
    Pending|InProgress|Baking|Cancelling|RollbackInProgress) sleep 15 ;;
    *)
      echo "Production instance refresh ended with status: $STATUS" >&2
      exit 1
      ;;
  esac
done
```

The workflow must use the `github_actions_prod_role_arn` output from the
`github-actions` Terraform configuration. That dedicated role trusts only the
backend repository's `main` branch, can publish the release parameter, and can
start and monitor the instance refresh. Do not use the development role for
production deployments. If an AWS-managed RDS password rotation changes the
secret, the instance timer refreshes the environment file and restarts the
service. Protect the local Terraform state and AWS access as usual.

After applying, create a CNAME record at the DNS provider for `api_domain_name`
that points to Terraform's `alb_dns_name` output. Add ACM's DNS-validation
CNAME as a separate record; it does not replace the API CNAME.

```bash
cd environments/prod
npm ci --prefix ../dev/expiry_lambda
terraform init
terraform validate
terraform plan
terraform apply
```

The default production CIDR is `10.1.0.0/16` so it does not overlap the
development VPC. Production uses two NAT gateways and a Multi-AZ database, so
review the AWS cost estimate in the plan before applying. RDS and DynamoDB
deletion protection and Terraform destroy guards are enabled. S3 buckets have
versioning enabled and cannot be force-destroyed. RDS creates a final snapshot
on deletion. This configuration also uses a local Terraform state unless a
remote backend is configured separately.

After applying, verify the HTTPS API and database health:

```powershell
$ApiUrl = terraform -chdir=environments/prod output -raw api_url
Invoke-RestMethod "$ApiUrl/health"
```

The health endpoint must return HTTP 200. Also confirm both EC2 targets are
healthy behind the ALB, then exercise the application's normal upload and
notification workflows to verify its scoped S3 and SQS access. Do not send an
ad-hoc message to the production queue; it triggers the notification Lambda.

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
  `AWS-StartPortForwardingSessionToRemoteHost` document. These permissions are
  not granted to a developer's machine by this Terraform.
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
MySQL Workbench) to `127.0.0.1:3306`. Use the username `bb_prod_admin` and the
password stored as `TF_VAR_db_master_password` in the local `.env` file. Treat
the master credentials as privileged, do not paste them into logs or commit
them, and close the tunnel with `Ctrl+C` when finished. The forwarded local
port is available only while the SSM session is running.

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
