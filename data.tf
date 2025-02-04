data "aws_ecs_cluster" "this" {
  count        = var.create_cluster ? 0 : 1
  cluster_name = var.cluster_name
}
