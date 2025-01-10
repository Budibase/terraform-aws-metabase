output "listener_arn" {
  description = "https://www.terraform.io/docs/providers/aws/r/lb_listener.html#arn"
  value       = aws_lb_listener.https.arn
}

output "target_group_arn" {
  description = "https://www.terraform.io/docs/providers/aws/r/lb_target_group.html#arn"
  value       = aws_lb_target_group.this.arn
}
