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
  description = "CIDRs allowed to call the public EKS API. Set to an empty list to keep the API private."
  type        = list(string)
  default = [
    "49.204.160.0/22",
    "49.204.166.0/24",
    "49.204.168.0/24",
    "49.204.192.0/21",
    "49.204.200.0/22",
    "49.204.232.0/22",
    "49.205.66.0/23",
    "49.205.88.0/22",
    "49.205.96.0/20",
    "49.205.160.0/21",
    "49.205.168.0/24",
    "49.205.212.0/22",
    "49.205.202.0/24",
    "49.206.112.0/21",
    "49.207.44.0/24",
    "106.51.4.0/24",
    "106.51.6.0/24",
    "106.51.44.0/24",
    "106.51.48.0/22",
    "106.51.113.0/24",
    "106.51.114.0/24",
    "106.51.124.0/23",
    "106.51.152.0/22",
    "106.51.156.0/23",
    "106.51.255.0/24",
    "124.123.25.0/24",
    "124.123.26.0/24",
    "124.123.60.0/22",
    "124.123.94.0/23",
    "183.82.250.0/23",
    "183.83.33.0/24",
    "183.83.35.0/24",
    "183.83.48.0/24",
    "183.83.148.0/22",
    "183.83.247.0/24",
    "202.83.27.0/24",
    "202.83.28.0/24",
    "202.83.30.0/23",
  ]
}

variable "tags" {
  description = "Additional tags for AWS resources."
  type        = map(string)
  default     = {}
}
