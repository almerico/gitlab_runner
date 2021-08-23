provider "aws" {
  region = "eu-west-1"
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

data "aws_eks_cluster" "eks_selected" {
  name = var.cluster_name
}

resource "aws_s3_bucket" "gitlab_de" {
  bucket = var.bucket_name

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.gitlab_de.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
    ]

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.gitlab_de.id}/*",
      "arn:aws:s3:::${aws_s3_bucket.gitlab_de.id}",
    ]

    principals {
      type = "AWS"

      identifiers = [
        "arn:aws:iam::${var.aws_account_id}:root",
      ]
    }
  }
}


resource "kubernetes_namespace" "gitlab" {
  metadata {
    name   = "gitlab"
    labels = { managed_by = "terraform" }
  }
}

resource "kubernetes_secret" "registration-token" {
  depends_on = [kubernetes_namespace.gitlab]
  metadata {
    name      = "gitlab-runner"
    namespace = "gitlab"
    labels    = { managed_by = "terraform" }
  }

  data = {
    runner-registration-token = var.gitlab_registration_token
    runner-token              = ""
  }

  type = "Opaque"
}

resource "helm_release" "gitlab-runner" {

  depends_on       = [kubernetes_secret.registration-token, aws_s3_bucket.gitlab_de]
  name             = "de-gitlab-runner"
  chart            = "gitlab-runner"
  repository       = "http://charts.gitlab.io/"
  namespace        = "gitlab"
  create_namespace = true

  values = [
    <<-EOF
imagePullPolicy: IfNotPresent
gitlabUrl: https://gitlab.zoral.net/
terminationGracePeriodSeconds: 3600
concurrent: 10
checkInterval: 30
rbac:
  create: true
  rules: []
  clusterWideAccess: false
  podSecurityPolicy:
    enabled: false
    resourceNames:
    - gitlab-runner
metrics:
  enabled: false
runners:
  secret: gitlab-runner
  privileged: true
  config: |
    [[runners]]
      limit = 8
      name = "gitlab_manager"
      url = "https://${var.domain_name}"
      executor = "kubernetes"
      namespace = "gitlab"
      [runners.kubernetes]
        image = "ubuntu:16.04"
        namespace = "gitlab"
        [runners.cache.s3]
          BucketName = "${var.bucket_name}"
        # [runners.kubernetes.node_selector]
        #   workload-type = "gitlab"
      [runners.machine]
        IdleCount = 2                    # There must be 5 machines in Idle state - when Off Peak time mode is off
        IdleTime = 30                   # Each machine can be in Idle state up to 30 seconds (after this it will be removed) - when Off Peak time mode is off
        MachineName = "auto-scale-%s"
        MaxGrowthRate = 1

  cache:
    secretName: gcsaccess
  tags: "gitlab_runner_de"
  cache: {}
  builds: {}
  services: {}
  helpers: {}
securityContext:
  runAsUser: 100
  fsGroup: 65533
resources: {}
affinity: {}
# nodeSelector: {
#   workload-type: applications
# }
tolerations: []
hostAliases: []
podAnnotations: {}
podLabels: {}
secrets: []
configMaps: {}

EOF
  ]
}




////// Service account //////
resource "kubernetes_service_account" "gitlab_admin" {

  count = var.gitlab_sa_enable ? 1 : 0
  metadata {
    name      = "gitlab-admin"
    namespace = "gitlab"
    labels    = { managed_by = "terraform" }
  }
}
////// Service account secret //////
data "kubernetes_secret" "gitlab_admin" {
  count      = var.gitlab_sa_enable ? 1 : 0
  depends_on = [kubernetes_service_account.gitlab_admin]
  metadata {
    name      = kubernetes_service_account.gitlab_admin[0].default_secret_name
    namespace = "gitlab"
    labels    = { managed_by = "terraform" }
  }
}
////// Service account RoleBinding //////
resource "kubernetes_cluster_role_binding" "gitlab_admin" {
  count      = var.gitlab_sa_enable ? 1 : 0
  depends_on = [kubernetes_service_account.gitlab_admin]
  metadata {
    name   = "gitlab-admin"
    labels = { managed_by = "terraform" }
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "gitlab-admin"
    namespace = "gitlab"
  }
}

# //// Service account credentials outputs //////
# output "kubernetes_cluster_name" {
#   depends_on = [helm_release.gitlab-runner]
#   value      = data.aws_eks_cluster.eks_selected.name
# }
# output "kubernetes_api_url" {
#   depends_on = [helm_release.gitlab-runner]
#   value      = var.gitlab_sa_output == true ? data.aws_eks_cluster.eks_selected.endpoint : "gitlab_sa_output disabled"
# }
# output "kubernetes_ca_certificate" {
#   depends_on = [helm_release.gitlab-runner]
#   value      = var.gitlab_sa_output == true ? base64decode(data.aws_eks_cluster.eks_selected.master_auth.0.cluster_ca_certificate) : "gitlab_sa_output disabled"
#   sensitive  = true
# }
# output "gitlab_sa_token" {
#   depends_on = [helm_release.gitlab-runner]
#   value      = var.gitlab_sa_output == true ? data.kubernetes_secret.gitlab_admin.0.data.token : "gitlab_sa_output disabled"
#   sensitive  = true
# }
# data "template_file" "gitlab_kubeconfig" {
#   count    = var.gitlab_sa_enable ? 1 : 0
#   template = <<EOF
# apiVersion: v1
# kind: Config
# users:
# - name: gitlab-admin
#   user:
#     token: ${data.kubernetes_secret.gitlab_admin[0].data.token}
# clusters:
# - cluster:
#     certificate-authority-data: ${data.aws_eks_cluster.eks_selected.master_auth.0.cluster_ca_certificate}
#     server: https://${data.aws_eks_cluster.eks_selected.endpoint}
#   name: ${var.cluster_name}
# contexts:
# - context:
#     cluster: ${var.cluster_name}
#     user: gitlab-admin
#   name: ${var.cluster_name}
# current-context: ${var.cluster_name}
# EOF
# }

# output "gitlab_kubeconfig" { # Kubernetes | Gitlab | Kubeconfig (can be set as gitlab group variable)
#   value     = var.gitlab_sa_output == true ? data.template_file.gitlab_kubeconfig[0].rendered : "gitlab_sa_output disabled"
#   sensitive = true
# }
# data "google_client_config" "default" {}
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}
