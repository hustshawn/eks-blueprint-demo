provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks_blueprints.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks_blueprints.eks_cluster_id
}

data "aws_availability_zones" "available" {}


locals {
  name = basename(path.cwd)
  # var.cluster_name is for Terratest
  cluster_name = local.name
  region       = "ap-southeast-1"

  vpc_cidr        = "10.0.0.0/16"
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  node_group_name = "${local.cluster_name}-ng"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------

module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.10.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.23"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  managed_node_groups = {
    mg_5 = {
      node_group_name = local.node_group_name
      instance_types  = ["t3.medium"]
      capacity_type   = "SPOT" # ON_DEMAND or SPOT
      min_size        = 2
      max_size        = 5
      desired_size    = 2
      subnet_ids      = module.vpc.private_subnets
    }
  }

  fargate_profiles = {
    # Providing compute for default namespace
    default = {
      fargate_profile_name = "default"
      fargate_profile_namespaces = [
        {
          namespace = "fargate-only"
      }]
      subnet_ids = module.vpc.private_subnets
    }
  }

  tags = local.tags
}

module "eks_blueprints_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.10.0"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  # EKS Managed Add-ons
  enable_amazon_eks_vpc_cni = true
  amazon_eks_vpc_cni_config = {
    addon_version     = data.aws_eks_addon_version.latest["vpc-cni"].version
    resolve_conflicts = "OVERWRITE"
  }
  enable_amazon_eks_coredns = true
  amazon_eks_coredns_config = {
    addon_version     = data.aws_eks_addon_version.latest["coredns"].version
    resolve_conflicts = "OVERWRITE"
  }
  enable_amazon_eks_kube_proxy = true
  amazon_eks_kube_proxy_config = {
    addon_version     = data.aws_eks_addon_version.latest["kube-proxy"].version
    resolve_conflicts = "OVERWRITE"
  }
  enable_amazon_eks_aws_ebs_csi_driver = false

  # Add-ons
  enable_aws_load_balancer_controller = true
  enable_metrics_server               = true
  enable_aws_cloudwatch_metrics       = false
  enable_kubecost                     = false
  enable_gatekeeper                   = false
  enable_cluster_autoscaler           = false

  enable_karpenter                    = true
  enable_aws_node_termination_handler = true

  enable_cert_manager = true
  cert_manager_helm_config = {
    set_values = [
      {
        name  = "extraArgs[0]"
        value = "--enable-certificate-owner-ref=false"
      },
    ]
  }
  # enable_cert_manager_csi_driver = true
  enable_external_dns = true
  eks_cluster_domain  = "shawnzh.people.aws.dev"

  tags = local.tags
}


data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/kubernetes/karpenter/*"
  vars = {
    azs                     = join(",", local.azs)
    iam-instance-profile-id = "${local.name}-${local.node_group_name}"
    eks-cluster-id          = local.name
    eks-vpc_name            = local.name
  }
}

data "aws_eks_addon_version" "latest" {
  for_each = toset(["kube-proxy", "vpc-cni", "coredns"])

  addon_name         = each.value
  kubernetes_version = module.eks_blueprints.eks_cluster_version
  most_recent        = true
}

resource "kubectl_manifest" "karpenter_provisioner" {
  for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
  yaml_body = each.value
  depends_on = [
    module.eks_blueprints_kubernetes_addons
  ]
}


#---------------------------------------------------------------
# Supporting Resources
#---------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }

  tags = local.tags
}
