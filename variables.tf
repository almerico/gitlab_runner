
////// Gitlab Variables //////

variable "gitlab_sa_enable" {
  type        = bool
  description = "Create ServiceAccount for Gitlab"
  default     = true
}
variable "gitlab_sa_output" {
  type        = bool
  description = "Show output of Gitlab kubernetes ServiceAccount"
  default     = true

}

variable "gitlab_registration_token" {
  description = "Can be found under Settings > CI/CD and expand the Runners section of group you want to make the runner work for"
  type        = string
  default     = ""
}
variable "cluster_name" {
  type    = string
  default = "zde-k8s-dev-eks-linux"
}
variable "bucket_name" {
  type    = string
  default = "gitlab-de-net"
}
variable "domain_name" {
  type    = string
  default = ""
}

variable "aws_account_id" {
  type    = string
  default = ""
}
