# ── Terraform Configuration ───────────────────────────────────────────────────
# Defines the required providers and the Kubernetes connection.
# We use Minikube as our local Kubernetes cluster.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }

  required_version = ">= 1.0"
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}
