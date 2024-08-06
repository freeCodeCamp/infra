locals {
  prefix = "ops-mwlh"
}

data "aws_vpc" "vpc" {
  tags = {
    Name = "ops-mwnet-vpc"
  }
}

data "aws_security_group" "sg_main" {
  name   = "ops-mwnet-sg"
  vpc_id = data.aws_vpc.vpc.id
}

data "aws_subnets" "subnets_prv" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = {
    Type  = "Private"
    Stack = "mintworld"
  }
}

resource "aws_iam_role" "lh_iam_role" {
  name = "fCCLifecycleHandlerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  inline_policy {
    name = "fCCLifecycleHandlerPolicy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "autoscaling:CompleteLifecycleAction",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "s3:GetObject",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      }]
    })
  }
}

resource "aws_iam_role_policy_attachment" "lh_policy_attachment" {
  role       = aws_iam_role.lh_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "external" "npm_install" {
  program = ["bash", "-c", <<EOT
    set -e

    handle_error() {
      echo "{\"error\": \"$1\"}" >&2
      exit 1
    }

    {
      curl -sSf -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash || handle_error "Failed to install nvm"

      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" || handle_error "Failed to source nvm"

      nvm install 20 || handle_error "Failed to install Node.js 20"
      nvm use 20 || handle_error "Failed to use Node.js 20"

      cd ${path.module}/lambda || handle_error "Failed to change to lambda directory"
      npm ci || handle_error "npm ci failed"
    } >&2

    echo '{"status":"dependencies installed successfully"}'
EOT
  ]
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda/lifecycle-handler.zip"
  excludes    = ["package.json", "package-lock.json"]

  depends_on = [data.external.npm_install]
}

resource "aws_lambda_function" "lh_lambda" {
  function_name = "${local.prefix}-lifecycle-handler"
  description   = "Handles ASG lifecycle events for graceful shutdown"
  role          = aws_iam_role.lh_iam_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 300

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  vpc_config {
    subnet_ids         = data.aws_subnets.subnets_prv.ids
    security_group_ids = [data.aws_security_group.sg_main.id]
  }
}

resource "aws_cloudwatch_event_rule" "lh_asg_lifecycle_termination" {
  name        = "${local.prefix}-asg-lifecycle-termination"
  description = "Capture ASG Event - EC2 Instance-terminate Lifecycle Action"

  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance-terminate Lifecycle Action"]
    detail = {
      AutoScalingGroupName = [
        { wildcard = "ops-mwctl-*" },
        { wildcard = "ops-mwwkr-*" },
        { wildcard = "ops-mwweb-*" }
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "lh_invoke_lambda" {
  rule      = aws_cloudwatch_event_rule.lh_asg_lifecycle_termination.name
  target_id = "InvokeLambda"
  arn       = aws_lambda_function.lh_lambda.arn
}

resource "aws_lambda_permission" "lh_allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lh_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lh_asg_lifecycle_termination.arn
}

resource "aws_cloudwatch_log_group" "lh_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.lh_lambda.function_name}"
  retention_in_days = 14
}
