variable "cluster_name" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "talos_client_config" {
  description = "Talos client_configuration object from the talos_config module."
  sensitive   = true
}

variable "control_plane_ips" {
  description = "Control-plane node IPs in CIDR notation (e.g. [\"192.168.1.10/24\"])."
  type        = list(string)
}

variable "worker_ips" {
  description = "Worker node IPs in CIDR notation (e.g. [\"192.168.1.11/24\"])."
  type        = list(string)
  default     = []
}

