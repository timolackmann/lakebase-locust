terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.34"
    }
  }

  required_version = ">= 1.14.6"
}

resource "aws_security_group" "Locust_Firewall" {
  name        = "LocustNodes_rule"
  description = "Allow ingress for locust"
  vpc_id      = var.awsVpcId
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.Locust_Firewall.id
  description       = "SSH Traffic"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowedIngressCidr
}

resource "aws_vpc_security_group_ingress_rule" "locust_8089" {
  security_group_id = aws_security_group.Locust_Firewall.id
  description       = "Locust web UI"
  from_port         = 8089
  to_port           = 8089
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowedIngressCidr
}

resource "aws_vpc_security_group_ingress_rule" "locust_5557" {
  security_group_id            = aws_security_group.Locust_Firewall.id
  referenced_security_group_id = aws_security_group.Locust_Firewall.id
  description                  = "Locust worker communication (same SG)"
  from_port                    = 5557
  to_port                      = 5557
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.Locust_Firewall.id
  description       = "All Ports/Protocols"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

data "aws_ami" "AWSlinux2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-20251212"]
  }

  owners = ["amazon"]
}

resource "aws_instance" "locust_main" {
  ami                    = data.aws_ami.AWSlinux2.id
  instance_type          = var.locustMasterInstanceType
  vpc_security_group_ids = [aws_security_group.Locust_Firewall.id]
  key_name               = var.keyName
  subnet_id              = var.awsSubnetId
  tags = {
    Name      = "locust_main"
  }
}

resource "aws_instance" "locust_worker" {
  count                  = var.workernodeCount
  ami                    = data.aws_ami.AWSlinux2.id
  instance_type          = var.locustWorkerInstanceType
  vpc_security_group_ids = [aws_security_group.Locust_Firewall.id]
  key_name               = var.keyName
  subnet_id              = var.awsSubnetId

  tags = {
    Name      = "locust_worker",
  }  
}