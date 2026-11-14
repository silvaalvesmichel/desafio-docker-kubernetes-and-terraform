output "url" {
  description = "Address of the Mural in the browser."
  value       = local.url
}

output "cluster_name" {
  description = "Name of the kind cluster."
  value       = kind_cluster.this.name
}

output "namespace" {
  description = "Namespace of the application."
  value       = kubernetes_namespace_v1.mural.metadata[0].name
}

output "kubeconfig_path" {
  description = "Kubeconfig of the cluster (use with kubectl --kubeconfig or KUBECONFIG)."
  value       = kind_cluster.this.kubeconfig_path
}

output "images" {
  description = "Images built and loaded into the cluster."
  value       = { for name, image in local.images : name => image.ref }
}
