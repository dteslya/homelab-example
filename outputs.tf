output "cluster_name" {
  description = "Name of the deployed cluster."
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = local.cluster_endpoint
}

output "control_plane_vm_names" {
  description = "Incus VM names for control-plane nodes."
  value       = [for k, v in module.control_plane_vms : v.vm_name]
}

output "worker_vm_names" {
  description = "Incus VM names for worker nodes."
  value       = [for k, v in module.worker_vms : v.vm_name]
}

output "talosconfig_path" {
  description = "Path to the generated talosconfig credential file."
  value       = local_sensitive_file.talosconfig.filename
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig credential file."
  value       = local_sensitive_file.kubeconfig.filename
}

output "kubeconfig" {
  description = "Raw kubeconfig content (sensitive)."
  value       = module.kubernetes.kubeconfig
  sensitive   = true
}
