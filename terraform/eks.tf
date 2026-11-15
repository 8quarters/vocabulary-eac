module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  kubernetes_version = "1.33"

  name                   = local.name
  endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    general = {
      name           = "general-node-group"
      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 3
      desired_size = 1
    }
  }
  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "eks-alb-sg"
  description = "Allow HTTP traffic to the EKS application load balancer"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "eks-alb-sg"
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "aws_lb" "eks_alb" {
  name               = "eks-backend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets # or private depending on architecture
}

resource "aws_lb_target_group" "eks_tg" {
  name        = "eks-backend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance" # or "ip" if using VPC CNI in overlay/ip mode
}


