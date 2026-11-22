data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  eks_azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.eks_azs

  private_subnets = [for index, az in local.eks_azs : cidrsubnet(var.vpc_cidr, 4, index)]
  public_subnets  = [for index, az in local.eks_azs : cidrsubnet(var.vpc_cidr, 4, index + 8)]

  enable_dns_support   = true
  enable_dns_hostnames = true
  create_igw           = true

  # Private worker nodes need outbound access to AWS APIs and image registries.
  enable_nat_gateway = true
  single_nat_gateway = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  tags = local.common_tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = "${local.name}-eks"
  kubernetes_version = var.eks_kubernetes_version

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  endpoint_private_access      = true
  endpoint_public_access       = length(var.eks_public_access_cidrs) > 0
  endpoint_public_access_cidrs = length(var.eks_public_access_cidrs) > 0 ? var.eks_public_access_cidrs : null

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
  }

  eks_managed_node_groups = {
    general = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.eks_node_instance_types
      min_size       = var.eks_node_min_size
      desired_size   = var.eks_node_desired_size
      max_size       = var.eks_node_max_size
      subnet_ids     = module.vpc.private_subnets
    }
  }

  # IP targets use pod IPs on worker ENIs. Permit the ALB to reach port 8080.
  node_security_group_additional_rules = {
    alb_to_api = {
      description              = "API traffic from the CloudFront origin ALB"
      type                     = "ingress"
      protocol                 = "tcp"
      from_port                = 8080
      to_port                  = 8080
      source_security_group_id = module.alb.security_group_id
    }
  }

  tags = local.common_tags
}
