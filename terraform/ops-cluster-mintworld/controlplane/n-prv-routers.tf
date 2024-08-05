resource "tailscale_tailnet_key" "tailscale_auth_key" {
  reusable      = true
  ephemeral     = true
  preauthorized = true
  expiry        = 604800 // 7 days, an ideal time to rotate the AMI
  description   = "Auto-Generated Auth Key Subnet Router"
  tags          = ["tag:mintworld"]
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "fCCECSExecutionRole"
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

  tags = merge(
    var.stack_tags,
    {
      Role = local.aws_tag__role_tailscale
    }
  )
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "fCCECSTaskRole"
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

  tags = merge(
    var.stack_tags,
    {
      Role = local.aws_tag__role_tailscale
    }
  )
}

resource "aws_ecs_cluster" "prv_routers_cluster" {
  name = "ts-prv-routers"

  tags = merge(
    var.stack_tags,
    {
      Role = local.aws_tag__role_tailscale
    }
  )
}

resource "random_pet" "prv_routers_name" {
  length = 1
}

resource "aws_ecs_task_definition" "prv_routers_task_definition" {
  family                   = "ts-prv-routers"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "ts-prv-routers"
      image     = "tailscale/tailscale:latest"
      cpu       = 256
      memory    = 512
      essential = true
      environment = [
        { name = "TS_ACCEPT_DNS", value = "true" },
        { name = "TS_HOSTNAME", value = "prv-router-${random_pet.prv_routers_name.id}" },
        { name = "TS_AUTH_KEY", value = tailscale_tailnet_key.tailscale_auth_key.key },
        { name = "TS_ROUTES", value = data.aws_vpc.vpc.cidr_block }
      ]
      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = merge(
    var.stack_tags,
    {
      Role = local.aws_tag__role_tailscale
    }
  )
}

resource "aws_ecs_service" "prv_routers_service" {
  name            = "ts-prv-routers"
  cluster         = aws_ecs_cluster.prv_routers_cluster.id
  task_definition = aws_ecs_task_definition.prv_routers_task_definition.id
  launch_type     = "FARGATE"
  desired_count   = local.prv_routers_count_min

  network_configuration {
    subnets          = data.aws_subnets.subnets_prv.ids
    assign_public_ip = false
    security_groups  = data.aws_security_groups.sg_main.ids
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [task_definition]
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  tags = merge(
    var.stack_tags,
    {
      Role = local.aws_tag__role_tailscale
    }
  )
}
