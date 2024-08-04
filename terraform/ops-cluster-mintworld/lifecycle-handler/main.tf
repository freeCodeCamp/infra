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

data "github_release" "lifecycle_handler" {
  repository  = "infra"
  owner       = "freeCodeCamp"
  retrieve_by = "latest"
}

data "external" "lambda_package" {
  program = ["bash", "-c", <<-EOT
    URL="${data.github_release.lifecycle_handler.assets[0].browser_download_url}"
    FILENAME="${path.module}/lambda_package.zip"
    curl -L -o "$FILENAME" "$URL"
    SHA256=$(sha256sum "$FILENAME" | awk '{print $1}')
    echo "{\"filename\": \"$FILENAME\", \"sha256\": \"$SHA256\"}"
  EOT
  ]
}

resource "aws_iam_role" "nomad_drain_lambda_role" {
  name = "fCCLambdaRoleDrainNomad"

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
    name = "fCCLambdaPolicyDrainNomad"
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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.nomad_drain_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "nomad_drain_lambda" {
  function_name = "${local.prefix}-nomad-drain-function"
  role          = aws_iam_role.nomad_drain_lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 300

  filename         = data.external.lambda_package.result.filename
  source_code_hash = data.external.lambda_package.result.sha256

  vpc_config {
    subnet_ids         = data.aws_subnets.subnets_prv.ids
    security_group_ids = [data.aws_security_group.sg_main.id]
  }
}

resource "aws_cloudwatch_event_rule" "asg_lifecycle_termination" {
  name        = "${local.prefix}-asg-lifecycle-termination"
  description = "Capture ASG instance terminating events"

  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance-terminate Lifecycle Action"]
    detail = {
      AutoScalingGroupName = [
        { wildcard = "ops-mwwkr-*" },
        { wildcard = "ops-mwweb-*" }
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "invoke_lambda" {
  rule      = aws_cloudwatch_event_rule.asg_lifecycle_termination.name
  target_id = "InvokeLambda"
  arn       = aws_lambda_function.nomad_drain_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nomad_drain_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.asg_lifecycle_termination.arn
}

resource "aws_cloudwatch_log_group" "nomad_drain_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.nomad_drain_lambda.function_name}"
  retention_in_days = 14
}
