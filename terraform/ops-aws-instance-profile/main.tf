variable "stack_tags" {
  type        = map(string)
  description = "Tags to apply to all resources in this stack"
  default = {
    Environment = "ops"
    Stack       = "common"
  }
}

resource "aws_iam_role" "stg_mw_instance_profile_role" {
  name               = "fCCSSMInstanceProfileRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  description          = "Allows EC2 instances to call AWS services like CloudWatch and Systems Manager on your behalf."
  max_session_duration = 3600

  tags = var.stack_tags
}

resource "aws_iam_role_policy_attachment" "stg_mw_instance_profile_role_attachment" {
  role       = aws_iam_role.stg_mw_instance_profile_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "stg_mw_instance_profile" {
  name = aws_iam_role.stg_mw_instance_profile_role.name
  role = aws_iam_role.stg_mw_instance_profile_role.name
}
