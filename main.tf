locals {
  private_subnets = split(",", var.private_subnets)
  port            = 6379
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "redis_engine" {
  name              = "redis-engine"
  retention_in_days = 5
}

resource "aws_cloudwatch_log_group" "redis_slow" {
  name              = "redis-slow"
  retention_in_days = 5
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id        = "lm-redis"
  description                 = "Lifemote Redis"
  preferred_cache_cluster_azs = ["${data.aws_region.current.name}a"]
  node_type                   = "cache.t4g.small"
  num_cache_clusters          = 1
  engine                      = "redis"
  engine_version              = "7.0"
  port                        = local.port
  security_group_ids          = [aws_security_group.redis.id]
  subnet_group_name           = aws_elasticache_subnet_group.redis.name
  maintenance_window          = "sun:15:00-sun:16:00"
  auto_minor_version_upgrade  = true
  automatic_failover_enabled  = false
  at_rest_encryption_enabled  = true
  kms_key_id                  = aws_kms_key.redis.arn
  transit_encryption_enabled  = true
  auth_token                  = random_password.redis_pass.result
  apply_immediately           = true

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine.name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "engine-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow.name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "slow-log"
  }
}

resource "aws_security_group" "redis" {
  name        = "redis-sg"
  description = "Redis SG"
  vpc_id      = var.vpc

  ingress {
    description     = "Allow redis connections from ECS security group"
    from_port       = local.port
    to_port         = local.port
    protocol        = "tcp"
    security_groups = [var.ecs_sg]
  }

  egress {
    description = ""
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "redis-subnet-group"
  subnet_ids = local.private_subnets
}

resource "aws_kms_key" "redis" {
  description              = "Redis KMS key"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  is_enabled               = true
  deletion_window_in_days  = 30
  enable_key_rotation      = true
}

resource "aws_kms_alias" "redis" {
  name          = "alias/redis"
  target_key_id = aws_kms_key.redis.key_id
}

data "aws_iam_policy_document" "redis_kms_key" {
  statement {
    sid       = "Enable IAM User Permissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "Allow access for Key Administrators"
    effect = "Allow"
    actions = [
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
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/terraform"]
    }
  }

  statement {
    sid    = "Allow use of the key"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "elasticache.eu-central-1.amazonaws.com",
        "dax.eu-central-1.amazonaws.com"
      ]
    }
  }

  statement {
    sid    = "Allow attachment of persistent resources"
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant"
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "elasticache.eu-central-1.amazonaws.com",
        "dax.eu-central-1.amazonaws.com"
      ]
    }
  }
}

resource "aws_kms_key_policy" "redis" {
  key_id                             = aws_kms_key.redis.id
  bypass_policy_lockout_safety_check = false
  policy                             = data.aws_iam_policy_document.redis_kms_key.json
}

resource "aws_secretsmanager_secret" "redis" {
  name        = "REDIS_AUTH_TOKEN"
  description = "Auth token for redis"
}

resource "random_password" "redis_pass" {
  length           = 64
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id     = aws_secretsmanager_secret.redis.id
  secret_string = random_password.redis_pass.result
}