resource "aws_iam_role" "ec2ip_iam_role" {
  name = "fCCEC2InstanceProfileRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  max_session_duration = 3600
  tags                 = var.stack_tags

  description = "Same as fCCSSMInstanceProfileRole, but with the ability to describe instances"
}

resource "aws_iam_role_policy_attachment" "ec2ip_iam_role_policy_attachment_SSM" {
  role       = aws_iam_role.ec2ip_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "ec2ip_iam_policy_DescribeInstances" {
  name        = "fCCDescribeInstances"
  description = "An IAM policy that allows EC2 instances to describe themselves"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_policy" "ec2ip_iam_policy_CreateTags_for_EC2Instances" {
  name        = "fCCCreateTags"
  description = "An IAM policy that allows EC2 instances to create tags"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:CreateTags",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ec2:*:*:instance/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2ip_iam_role_policy_attachment_CreateTags_for_EC2Instances" {
  role       = aws_iam_role.ec2ip_iam_role.name
  policy_arn = aws_iam_policy.ec2ip_iam_policy_CreateTags_for_EC2Instances.arn
}

resource "aws_iam_role_policy_attachment" "ec2ip_iam_role_policy_attachment_DescribeInstances" {
  role       = aws_iam_role.ec2ip_iam_role.name
  policy_arn = aws_iam_policy.ec2ip_iam_policy_DescribeInstances.arn
}

resource "aws_iam_instance_profile" "ec2ip_instance_profile" {
  name = aws_iam_role.ec2ip_iam_role.name
  role = aws_iam_role.ec2ip_iam_role.name
}
