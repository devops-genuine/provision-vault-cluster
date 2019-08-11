# --------------------------------------------------------------
# AWS Provider Configuration
# Refer credential with aws profile at ~/.aws/credential
# --------------------------------------------------------------
provider "aws" {
  region = "ap-southeast-1"
  profile = "default"
}

# --------------------------------------------------------------
# Set your AWS S3 Bucket Name
# --------------------------------------------------------------
variable "bucket_name" {
  default = "example-vault-backup-bucket"
}

data "aws_caller_identity" "current" {}

# -------------------- AWS S3 -------------------
resource "aws_iam_user" "vault-data-mgt-user" {
  name = "vault-data-manager"
}

resource "aws_iam_user_policy_attachment" "vault-data-mgt-policy-attach" {
  user       = "${aws_iam_user.vault-data-mgt-user.name}"
  policy_arn = "${aws_iam_policy.iam_policy_vault_data_bucket.arn}"
}

resource "aws_s3_bucket" "s3-vault-data-bucket" {
  bucket = "${var.bucket_name}"
  acl    = "private"
  force_destroy = false
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "${var.bucket_name}"
  }
}


resource "aws_iam_policy" "iam_policy_vault_data_bucket" {
  name = "vault-data-bucket-policy"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.s3-vault-data-bucket.arn}",
        "${aws_s3_bucket.s3-vault-data-bucket.arn}/*"
      ]
    }
  ]
}
POLICY
}

# -------------------- AWS KMS -------------------
resource "aws_iam_user" "kms-admin-user" {
  name = "kms-admin"
  tags = {
    Name        = "kms-admin"
  }
}

resource "aws_iam_user" "vault-unsealer-user" {
  name = "vault-unsealer"
  tags = {
    Name        = "vault-unsealer"
  }
}

resource "aws_kms_key" "vault-unseal-key" {
  description             = "vault-unseal-key"
  deletion_window_in_days = 30
    policy = <<POLICY
{
    "Id": "vault-auto-unseal-policy",
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Enable IAM User Permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            },
            "Action": "kms:*",
            "Resource": "*"
        },
        {
            "Sid": "Allow access for Key Administrators",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_iam_user.kms-admin-user.arn}"
            },
            "Action": [
                "kms:Create*",
                "kms:Describe*",
                "kms:Enable*",
                "kms:List*",
                "kms:Put*",
                "kms:Update*",
                "kms:Revoke*",
                "kms:Disable*",
                "kms:Get*",
                "kms:Delete*",
                "kms:TagResource",
                "kms:UntagResource",
                "kms:ScheduleKeyDeletion",
                "kms:CancelKeyDeletion"
            ],
            "Resource": "*"
        },
        {
            "Sid": "Allow use of the key",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_iam_user.vault-unsealer-user.arn}"
            },
            "Action": [
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:DescribeKey"
            ],
            "Resource": "*"
        },
        {
            "Sid": "Allow attachment of persistent resources",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_iam_user.kms-admin-user.arn}"
            },
            "Action": [
                "kms:CreateGrant",
                "kms:ListGrants",
                "kms:RevokeGrant"
            ],
            "Resource": "*",
            "Condition": {
                "Bool": {
                    "kms:GrantIsForAWSResource": "true"
                }
            }
        }
    ]
}
POLICY
}

resource "aws_kms_alias" "vault-unseal-key-alias" {
  name          = "alias/vault-unseal-key"
  target_key_id = "${aws_kms_key.vault-unseal-key.key_id}"
}