# GitHub Actions OIDC for EC2-only disaster recovery (Region B / Tokyo)
# Replaces Region-B/github-oidc.tf; do not keep both copies in the module.

# Provider is account-global. Confirm it does not already exist before applying.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # No thumbprint is needed for GitHub with this AWS provider version.
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "github_dr_runner" {
  name = "skripsi-github-dr-ec2-start-and-ssh"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            # Support both classic and immutable GitHub OIDC subject formats.
            # Job MUST declare: environment: dr-lab
            "token.actions.githubusercontent.com:sub" = [
              "repo:ZulPratama21/skripsi-aws-dr:environment:dr-lab",
              "repo:ZulPratama21@87340122/skripsi-aws-dr@1392553952:environment:dr-lab"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_dr_runner" {
  role = aws_iam_role.github_dr_runner.id
  name = "start-secondary-ec2-temporary-ssh"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances"]
        Resource = "arn:aws:ec2:ap-northeast-1:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.web_server_b.id}"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = "arn:aws:ec2:ap-northeast-1:${data.aws_caller_identity.current.account_id}:security-group/${aws_security_group.web_sg.id}"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus", "ec2:DescribeSecurityGroups"]
        Resource = "*"
      }
    ]
  })
}

output "github_dr_role_arn" {
  value = aws_iam_role.github_dr_runner.arn
}
