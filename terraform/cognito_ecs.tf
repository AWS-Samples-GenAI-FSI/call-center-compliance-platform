# Cognito User Pool
resource "aws_cognito_user_pool" "anycompany_cognito_user_pool" {
  name = "anycompany-compliance-users-${var.environment}"

  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  schema {
    attribute_data_type = "String"
    name               = "email"
    required           = true
    mutable            = true
  }

  schema {
    attribute_data_type = "String"
    name               = "given_name"
    required           = true
    mutable            = true
  }

  schema {
    attribute_data_type = "String"
    name               = "family_name"
    required           = true
    mutable            = true
  }

  tags = {
    Environment = var.environment
    Application = "AnyCompanyCompliance"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "anycompany_cognito_user_pool_client" {
  name         = "anycompany-compliance-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.anycompany_cognito_user_pool.id

  generate_secret = true
  explicit_auth_flows = [
    "ADMIN_NO_SRP_AUTH",
    "USER_PASSWORD_AUTH"
  ]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 8
  id_token_validity      = 8
  refresh_token_validity = 30

  callback_urls = ["https://${aws_lb.anycompany_alb.dns_name}/oauth2/idpresponse"]
  logout_urls   = ["https://${aws_lb.anycompany_alb.dns_name}/"]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  allowed_oauth_flows_user_pool_client = true
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "anycompany_cognito_user_pool_domain" {
  domain       = "anycompany-auth-${var.environment}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.anycompany_cognito_user_pool.id
}

# ECR Repository
resource "aws_ecr_repository" "anycompany_ecr_repository" {
  name                 = "anycompany-ui-${var.environment}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "anycompany_ecs_cluster" {
  name = "anycompany-cluster-${var.environment}"

  tags = {
    Name        = "anycompany-cluster-${var.environment}"
    Environment = var.environment
  }
}

# ECS Task Role
resource "aws_iam_role" "anycompany_task_role" {
  name = "anycompany-task-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_role_policy" {
  role       = aws_iam_role.anycompany_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecr_access_policy" {
  name = "ECRAccessPolicy"
  role = aws_iam_role.anycompany_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "anycompany_log_group" {
  name              = "/ecs/anycompany-ui-${var.environment}"
  retention_in_days = 7
}

# ECS Task Definition
resource "aws_ecs_task_definition" "anycompany_task_definition" {
  family                   = "anycompany-ui-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.anycompany_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "anycompany-ui"
      image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${aws_ecr_repository.anycompany_ecr_repository.name}:latest"
      
      portMappings = [
        {
          containerPort = 80
        }
      ]

      environment = [
        {
          name  = "API_ENDPOINT"
          value = "https://${aws_api_gateway_rest_api.anycompany_rest_api.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
        },
        {
          name  = "FORCE_UPDATE"
          value = "${var.environment}-${data.aws_caller_identity.current.account_id}"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.anycompany_log_group.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "anycompany-ui"
        }
      }
    }
  ])
}

# Application Load Balancer
resource "aws_lb" "anycompany_alb" {
  name               = "anycompany-compliance"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.anycompany_alb_sg.id]
  subnets            = [aws_subnet.anycompany_public_subnet_1.id, aws_subnet.anycompany_public_subnet_2.id]

  tags = {
    Name        = "anycompany-compliance"
    Environment = var.environment
  }
}

# Target Group
resource "aws_lb_target_group" "anycompany_target_group" {
  name        = "anycompany-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.anycompany_vpc.id
  target_type = "ip"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "anycompany-tg-${var.environment}"
    Environment = var.environment
  }
}

# ALB Listener
resource "aws_lb_listener" "anycompany_alb_listener" {
  load_balancer_arn = aws_lb.anycompany_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.anycompany_target_group.arn
  }
}

# ECS Service
resource "aws_ecs_service" "anycompany_ecs_service" {
  name            = "anycompany-ui-${var.environment}"
  cluster         = aws_ecs_cluster.anycompany_ecs_cluster.id
  task_definition = aws_ecs_task_definition.anycompany_task_definition.arn
  
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.anycompany_target_group.arn
    container_name   = "anycompany-ui"
    container_port   = 80
  }

  network_configuration {
    security_groups  = [aws_security_group.anycompany_container_sg.id]
    subnets          = [aws_subnet.anycompany_public_subnet_1.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_lb_listener.anycompany_alb_listener,
    null_resource.build_and_deploy_container
  ]
}