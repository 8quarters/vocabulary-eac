variable "aws_region" {
  description = "AWS Region for the VPC, EKS cluster, public ALB, and S3 bucket."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short lowercase name used for resource naming."
  type        = string
  default     = "vocabulary"

  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 20 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-20 lowercase letters, digits, or hyphens, beginning with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Short lowercase environment name used for resource naming."
  type        = string
  default     = "dev"

  validation {
    condition     = length(var.environment) >= 2 && length(var.environment) <= 10 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "environment must be 2-10 lowercase letters, digits, or hyphens, beginning with a letter and ending with a letter or digit."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR of the new VPC. A /16 to /20 VPC produces /20 to /24 public and private subnets."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && try(tonumber(split("/", var.vpc_cidr)[1]), -1) >= 16 && try(tonumber(split("/", var.vpc_cidr)[1]), -1) <= 20
    error_message = "vpc_cidr must be an IPv4 CIDR with a prefix from /16 through /20."
  }
}

variable "eks_kubernetes_version" {
  description = "Kubernetes minor version for the EKS cluster."
  type        = string
  default     = "1.36"
}

variable "eks_node_instance_types" {
  description = "EC2 instance types for the EKS managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_min_size" {
  description = "Minimum managed worker nodes."
  type        = number
  default     = 1
}

variable "eks_node_desired_size" {
  description = "Initial managed worker nodes."
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum managed worker nodes."
  type        = number
  default     = 3
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to call the public EKS API. Empty keeps the API private; use a runner inside the VPC for later deployments."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags for AWS resources."
  type        = map(string)
  default     = {}
}
