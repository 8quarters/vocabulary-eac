module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  kubernetes_version = "1.33"

  name                   = local.name
  endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true
  
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets

  eks_managed_node_groups = {
    general = {
      name            = "general-node-group"
      instance_types  = ["t3.medium"]
      
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
