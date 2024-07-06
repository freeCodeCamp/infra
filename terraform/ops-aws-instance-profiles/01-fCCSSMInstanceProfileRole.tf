resource "aws_iam_role" "ssmip_iam_role" {
  name = "fCCSSMInstanceProfileRole"
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

  description = "An IAM role that allows EC2 instances to use the SSM service"
}

resource "aws_iam_role_policy_attachment" "ssmip_iam_role_policy_attachment" {
  role       = aws_iam_role.ssmip_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssmip_instance_profile" {
  name = aws_iam_role.ssmip_iam_role.name
  role = aws_iam_role.ssmip_iam_role.name
}
