terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_nat_gateways" "vpc" {
  filter {
    name   = "vpc-id"
    values = [var.awsVpcId]
  }
}

data "aws_nat_gateway" "each" {
  for_each = toset(data.aws_nat_gateways.vpc.ids)
  id       = each.value
}

resource "aws_ecr_repository" "locust" {
  name                 = var.ecrRepositoryName
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_iam_role" "eks_cluster" {
  name = "${var.clusterName}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role" "eks_node" {
  name = "${var.clusterName}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node.name
}

resource "aws_ec2_tag" "cluster_shared" {
  for_each    = toset(var.privateSubnetIds)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.clusterName}"
  value       = "shared"
}

resource "aws_ec2_tag" "subnet_elb_role" {
  for_each    = toset(var.privateSubnetIds)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_eks_cluster" "this" {
  name     = var.clusterName
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetesVersion

  vpc_config {
    subnet_ids              = var.privateSubnetIds
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_ec2_tag.cluster_shared,
    aws_ec2_tag.subnet_elb_role,
  ]
}

resource "aws_eks_access_entry" "cluster_creator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_creator_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_creator]
}

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.clusterName}-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.privateSubnetIds
  instance_types  = [var.nodeInstanceType]

  scaling_config {
    desired_size = var.workerReplicas
    max_size     = max(var.workerReplicas, var.workerReplicas + 2)
    min_size     = max(1, var.workerReplicas - 1)
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy_attachment.eks_node_ecr,
    aws_eks_access_policy_association.cluster_creator_admin,
  ]
}
