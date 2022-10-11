# tflint-ignore: terraform_unused_declarations
variable "cluster_name" {
  description = "Name of cluster - used by Terratest for e2e test automation"
  type        = string
  default     = ""
}
variable "certificate_name" {
  type        = string
  description = "name for the certificate"
  default     = "example"
}

variable "eks_cluster_domain" {
  type        = string
  description = "Your DNS domain"
  default     = "example.com"
}

variable "acm_certificate_domain" {
  type        = string
  description = "ACME cert domain"
}

variable "cert_manager_letsencrypt_email" {
  type        = string
  description = "The email used for letsencrypt"
  default     = "example@gmail.com"
}
