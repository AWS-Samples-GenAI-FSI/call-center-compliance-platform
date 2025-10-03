terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "allowed_ip" {
  description = "IP address allowed to access the application (CIDR format)"
  type        = string
  default     = "136.57.32.30/32"
}

variable "deploy_ecs" {
  description = "Whether to deploy ECS service"
  type        = bool
  default     = true
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# VPC
resource "aws_vpc" "anycompany_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "anycompany-vpc-${var.environment}"
  }
}

# Subnets
resource "aws_subnet" "anycompany_public_subnet_1" {
  vpc_id                  = aws_vpc.anycompany_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "anycompany-public-subnet-1-${var.environment}"
  }
}

resource "aws_subnet" "anycompany_private_subnet_1" {
  vpc_id            = aws_vpc.anycompany_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "anycompany-private-subnet-1-${var.environment}"
  }
}

resource "aws_subnet" "anycompany_public_subnet_2" {
  vpc_id                  = aws_vpc.anycompany_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "anycompany-public-subnet-2-${var.environment}"
  }
}

resource "aws_subnet" "anycompany_private_subnet_2" {
  vpc_id            = aws_vpc.anycompany_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "anycompany-private-subnet-2-${var.environment}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "anycompany_igw" {
  vpc_id = aws_vpc.anycompany_vpc.id

  tags = {
    Name = "anycompany-igw-${var.environment}"
  }
}

# Route Table
resource "aws_route_table" "anycompany_public_rt" {
  vpc_id = aws_vpc.anycompany_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.anycompany_igw.id
  }

  tags = {
    Name = "anycompany-public-rt-${var.environment}"
  }
}

resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id      = aws_subnet.anycompany_public_subnet_1.id
  route_table_id = aws_route_table.anycompany_public_rt.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id      = aws_subnet.anycompany_public_subnet_2.id
  route_table_id = aws_route_table.anycompany_public_rt.id
}

# SQS Queues
resource "aws_sqs_queue" "anycompany_processing_dlq" {
  name                      = "anycompany-processing-dlq-${var.environment}"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "anycompany_processing_queue" {
  name                       = "anycompany-processing-queue-${var.environment}"
  visibility_timeout_seconds = 960
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.anycompany_processing_dlq.arn
    maxReceiveCount     = 3
  })
}

# S3 Buckets
resource "aws_s3_bucket" "anycompany_input_bucket" {
  bucket        = "anycompany-input-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "anycompany_input_bucket_versioning" {
  bucket = aws_s3_bucket.anycompany_input_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "anycompany_input_bucket_encryption" {
  bucket = aws_s3_bucket.anycompany_input_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "anycompany_input_bucket_pab" {
  bucket = aws_s3_bucket.anycompany_input_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "anycompany_input_bucket_cors" {
  bucket = aws_s3_bucket.anycompany_input_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket" "anycompany_transcribe_output_bucket" {
  bucket        = "anycompany-transcribe-output-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "anycompany_transcribe_output_bucket_versioning" {
  bucket = aws_s3_bucket.anycompany_transcribe_output_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "anycompany_transcribe_output_bucket_encryption" {
  bucket = aws_s3_bucket.anycompany_transcribe_output_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "anycompany_transcribe_output_bucket_pab" {
  bucket = aws_s3_bucket.anycompany_transcribe_output_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "anycompany_comprehend_output_bucket" {
  bucket        = "anycompany-comprehend-output-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "anycompany_comprehend_output_bucket_versioning" {
  bucket = aws_s3_bucket.anycompany_comprehend_output_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "anycompany_comprehend_output_bucket_encryption" {
  bucket = aws_s3_bucket.anycompany_comprehend_output_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "anycompany_comprehend_output_bucket_pab" {
  bucket = aws_s3_bucket.anycompany_comprehend_output_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "anycompany_source_bucket" {
  bucket        = "anycompany-source-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "anycompany_source_bucket_versioning" {
  bucket = aws_s3_bucket.anycompany_source_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "anycompany_source_bucket_encryption" {
  bucket = aws_s3_bucket.anycompany_source_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "anycompany_source_bucket_pab" {
  bucket = aws_s3_bucket.anycompany_source_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB Tables
resource "aws_dynamodb_table" "anycompany_calls_table" {
  name           = "anycompany-calls-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "call_id"

  attribute {
    name = "call_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name        = "anycompany-calls-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_dynamodb_table" "anycompany_rules_table" {
  name           = "anycompany-rules-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "rule_id"

  attribute {
    name = "rule_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "anycompany-rules-${var.environment}"
    Environment = var.environment
  }
}

# Security Groups
resource "aws_security_group" "anycompany_alb_sg" {
  name_prefix = "anycompany-alb-sg-"
  description = "Security group for ALB - Restricted to authorized IP only"
  vpc_id      = aws_vpc.anycompany_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
    description = "HTTP access restricted to authorized IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "anycompany-alb-sg-${var.environment}"
  }
}

resource "aws_security_group" "anycompany_container_sg" {
  name_prefix = "anycompany-container-sg-"
  description = "Security group for containers"
  vpc_id      = aws_vpc.anycompany_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.anycompany_alb_sg.id]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for AWS API calls"
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for package downloads"
  }

  tags = {
    Name = "anycompany-container-sg-${var.environment}"
  }
}

resource "aws_security_group" "anycompany_vpc_endpoint_sg" {
  name_prefix = "anycompany-vpc-endpoint-sg-"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.anycompany_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = {
    Name = "anycompany-vpc-endpoint-sg-${var.environment}"
  }
}

# VPC Endpoints
resource "aws_vpc_endpoint" "anycompany_ecr_endpoint" {
  vpc_id              = aws_vpc.anycompany_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.anycompany_private_subnet_1.id, aws_subnet.anycompany_private_subnet_2.id]
  security_group_ids  = [aws_security_group.anycompany_vpc_endpoint_sg.id]
}

resource "aws_vpc_endpoint" "anycompany_ecr_api_endpoint" {
  vpc_id              = aws_vpc.anycompany_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.anycompany_private_subnet_1.id, aws_subnet.anycompany_private_subnet_2.id]
  security_group_ids  = [aws_security_group.anycompany_vpc_endpoint_sg.id]
}

resource "aws_vpc_endpoint" "anycompany_s3_endpoint" {
  vpc_id            = aws_vpc.anycompany_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.anycompany_public_rt.id]
}

