terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.38.0" }
  }
}

variable "kube_context" {
  description = "Explicit AKS kubeconfig context; never use the local kind context."
  type        = string
}
variable "kube_config_path" {
  type    = string
  default = "~/.kube/config"
}
variable "image" {
  description = "Public GHCR application image, pinned by its real published digest."
  type        = string
  validation {
    condition     = can(regex("^ghcr\\.io/[a-z0-9._/-]+@sha256:[a-f0-9]{64}$", var.image))
    error_message = "Provide a published public GHCR image pinned by sha256 digest."
  }
}
provider "kubernetes" {
  config_path    = pathexpand(var.kube_config_path)
  config_context = var.kube_context
}

# Namespace is an administrator bootstrap operation; the application identity
# only has RBAC Writer inside cicd-azure and cannot create namespaces.
locals {
  namespace = "cicd-azure"
  base      = "${path.module}/../../../k8s/base"
  documents = concat(
    [yamldecode(file("${local.base}/deployment.yaml")),
      yamldecode(file("${local.base}/service.yaml")),
    yamldecode(file("${local.base}/pdb.yaml"))],
    [for doc in split("\n---\n", replace(file("${local.base}/web.yaml"), "\r\n", "\n")) : yamldecode(doc)]
  )
  manifests = {
    for doc in local.documents : "${doc.kind}/${doc.metadata.name}" => merge(doc, {
      metadata = merge(doc.metadata, { namespace = local.namespace })
      }, doc.kind == "Deployment" ? {
      spec = merge(doc.spec, {
        template = merge(doc.spec.template, {
          spec = merge(doc.spec.template.spec, {
            containers = [for c in doc.spec.template.spec.containers : merge(c, { image = var.image })]
          })
        })
      })
    } : {})
  }
}

resource "kubernetes_manifest" "app" {
  for_each = local.manifests
  manifest = each.value
}

output "access_command" {
  value = "kubectl --context ${var.kube_context} -n ${local.namespace} port-forward svc/demo-web 8081:80"
}
