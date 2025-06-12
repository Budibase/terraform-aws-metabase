resource "aws_lb" "this" {
  count = var.create_alb ? 1 : 0

  name_prefix     = "mb-"
  security_groups = ["${aws_security_group.alb.id}"]
  subnets         = tolist(var.public_subnet_ids)
  tags            = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
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
