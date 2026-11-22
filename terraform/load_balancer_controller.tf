locals {
  load_balancer_controller_service_account = "aws-load-balancer-controller"
}

data "aws_iam_policy_document" "load_balancer_controller_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:${local.load_balancer_controller_service_account}"]
    }
  }
}

resource "aws_iam_role" "load_balancer_controller" {
  name               = "${local.name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.load_balancer_controller_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "load_balancer_controller" {
  # Permissions required by the controller to reconcile TargetGroupBindings.
  # Read operations need wildcard resources; mutations are scoped to this API TG.
  statement {
    sid    = "DescribeTargetGroupAndVpcResources"
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageVocabularyApiTargets"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
    ]
    resources = [module.alb.target_groups["api"].arn]
  }
}

resource "aws_iam_role_policy" "load_balancer_controller" {
  name   = "${local.name}-target-group-binding"
  role   = aws_iam_role.load_balancer_controller.id
  policy = data.aws_iam_policy_document.load_balancer_controller.json
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.14.0"
  namespace  = "kube-system"
  wait       = true
  timeout    = 600

  values = [yamlencode({
    clusterName = module.eks.cluster_name
    region      = var.aws_region
    vpcId       = module.vpc.vpc_id

    # Keep the existing Terraform ALB out of the controller's Ingress
    # reconciliation. This controller is installed here for TargetGroupBinding.
    ingressClass = "terraform-managed"

    serviceAccount = {
      create = true
      name   = local.load_balancer_controller_service_account
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.load_balancer_controller.arn
      }
    }
  })]

  depends_on = [
    aws_iam_role_policy.load_balancer_controller,
    module.eks,
  ]
}

resource "kubectl_manifest" "vocabulary_api_target_group_binding" {
  yaml_body = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "vocabulary-api"
      namespace = "default"
    }
    spec = {
      targetGroupARN = module.alb.target_groups["api"].arn
      targetType     = "ip"
      serviceRef = {
        name = "vocabulary-api"
        port = 80
      }
    }
  })

  depends_on = [helm_release.aws_load_balancer_controller]
}
