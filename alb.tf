resource "aws_lb" "this" {
  count = var.create_alb ? 1 : 0

  name_prefix     = "mb-"
  security_groups = ["${aws_security_group.alb.id}"]
  subnets         = tolist(var.public_subnet_ids)
  tags            = var.tags

  access_logs {
    bucket  = aws_s3_bucket.this.bucket
    enabled = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  count = var.create_alb ? 1 : 0

  load_balancer_arn = var.alb_arn != "" ? var.alb_arn : aws_lb.this[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  count = var.create_alb ? 1 : 0

  load_balancer_arn = var.alb_arn != "" ? var.alb_arn : aws_lb.this[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "No valid routing rule"
      status_code  = "400"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count = var.create_alb ? 1 : 0

  bucket = aws_s3_bucket.this.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.create_alb ? 1 : 0

  bucket = aws_s3_bucket.this.bucket
  rule {
    id = "log"

    status = "Enabled"

    expiration {
      days = var.log_retention
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "this" {
  count = var.create_alb ? 1 : 0

  depends_on = [aws_s3_bucket_ownership_controls.this]

  bucket = aws_s3_bucket.this.id
  acl    = "private"
}

resource "aws_s3_bucket" "this" {
  count = var.create_alb ? 1 : 0

  bucket_prefix = "mb-"
  force_destroy = !var.protection
  tags          = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket_policy" "this" {
  count = var.create_alb ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.s3.json
}

data "aws_elb_service_account" "this" {}

data "aws_iam_policy_document" "s3" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this.arn]
    }
  }
}

resource "aws_security_group" "alb" {
  count = var.create_alb ? 1 : 0

  name_prefix = "${var.id}-alb-"
  vpc_id      = var.vpc_id
  tags        = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "alb_egress_ecs" {
  count = var.create_alb ? 1 : 0

  description              = "ECS"
  type                     = "egress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.alb[0].id
  source_security_group_id = aws_security_group.ecs.id
}

resource "aws_security_group_rule" "alb_ingress_http" {
  count = var.create_alb ? 1 : 0

  description       = "Internet"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.alb[0].id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_ingress_https" {
  count = var.create_alb ? 1 : 0

  description       = "Internet"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.alb[0].id
  cidr_blocks       = ["0.0.0.0/0"]
}
