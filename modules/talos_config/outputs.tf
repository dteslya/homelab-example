output "control_plane_configs" {
  description = "List of per-node control-plane machine configuration YAMLs."
  value       = data.talos_machine_configuration.control_plane_node[*].machine_configuration
  sensitive   = true
}

output "worker_configs" {
  description = "List of per-node worker machine configuration YAMLs."
  value       = data.talos_machine_configuration.worker_node[*].machine_configuration
  sensitive   = true
}

output "talosconfig" {
  description = "Talos client configuration file content."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "client_configuration" {
  description = "Raw client_configuration object (used by the kubernetes module)."
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
}
