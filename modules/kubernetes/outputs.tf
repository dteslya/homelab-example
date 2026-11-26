output "kubeconfig" {
  description = "Raw kubeconfig YAML content."
  value       = resource.talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}
