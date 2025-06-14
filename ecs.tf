resource "aws_ecs_cluster" "this" {
  count = var.create_cluster ? 1 : 0
  name  = var.cluster_name
  tags  = var.tags

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = var.cluster_name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.id
  container_definitions    = jsonencode(local.container)
  execution_role_arn       = aws_iam_role.this.arn
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  tags                     = var.tags
}

resource "aws_ecs_service" "this" {
  name                              = var.id
  cluster                           = var.create_cluster ? aws_ecs_cluster.this[0].id : data.aws_ecs_cluster.this[0].id
  task_definition                   = aws_ecs_task_definition.this.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  propagate_tags                    = "SERVICE"
  health_check_grace_period_seconds = 600
  depends_on                        = [aws_lb_listener_rule.this]
  tags                              = var.tags

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = local.container[0].name
    container_port   = local.container[0].portMappings[0].containerPort
  }

  network_configuration {
    security_groups = [aws_security_group.ecs.id]
    subnets         = tolist(var.private_subnet_ids)
  }
}

data "aws_region" "this" {}

locals {
  container = [
    {
      name        = "metabase"
      image       = var.image
      essential   = true
      environment = concat(local.environment, var.environment)

      portMappings = [
        {
          containerPort = 3000
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.this.name
          awslogs-stream-prefix = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:3000/api/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ]

  environment = [
    {
      name  = "MB_JETTY_HOST"
      value = "0.0.0.0"
    },
    {
      name  = "JAVA_TIMEZONE"
      value = var.java_timezone
    },
    {
      name  = "MB_DB_TYPE"
      value = "postgres"
    },
    {
      name  = "MB_DB_DBNAME"
      value = var.db_dbname
    },
    {
      name  = "MB_DB_PORT"
      value = var.db_port
    },
    {
      name  = "MB_DB_USER"
      value = var.db_user
    },
    {
      name  = "MB_DB_HOST"
      value = var.db_host
    },
    {
      name  = "MB_DB_PASS"
      value = var.db_pass
    }
  ]
}

resource "aws_iam_role" "this" {
  name_prefix        = var.id
  assume_role_policy = data.aws_iam_policy_document.ecs.json
  tags               = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "ecs" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.this.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
  role       = aws_iam_role.this.name
}

resource "aws_lb_target_group" "this" {
  name        = var.id
  port        = local.container[0].portMappings[0].containerPort
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  tags        = var.tags

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/api/health"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }
}

resource "aws_lb_listener_rule" "this" {
  listener_arn = aws_lb_listener.https.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    host_header {
      values = [var.domain]
    }
  }
}

resource "aws_route53_record" "this" {
  name    = var.domain
  type    = "A"
  zone_id = var.zone_id

  alias {
    name                   = var.alb_dns_name != "" ? var.alb_dns_name : aws_lb.this[0].dns_name
    zone_id                = var.alb_zone_id != "" ? var.alb_zone_id : aws_lb.this[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = var.id
  retention_in_days = var.log_retention
  tags              = var.tags
}
