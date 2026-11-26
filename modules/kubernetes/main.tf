# ------------------------------------------------------------------
# Module: kubernetes
# Bootstraps the Talos cluster and retrieves the kubeconfig.
# ------------------------------------------------------------------

terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.12.0"
    }
  }
}

locals {
  # Strip CIDR prefix from IP addresses (e.g. "192.168.1.10/24" -> "192.168.1.10")
  cp_ips     = [for cidr in var.control_plane_ips : split("/", cidr)[0]]
  worker_ips = [for cidr in var.worker_ips : split("/", cidr)[0]]
}

# ---- Bootstrap etcd on the first control-plane node -----------
resource "talos_machine_bootstrap" "this" {
  client_configuration = var.talos_client_config
  endpoint             = local.cp_ips[0]
  node                 = local.cp_ips[0]
}

# ---- Wait for the cluster to become healthy ------------------
data "talos_cluster_health" "this" {
  client_configuration = var.talos_client_config

  # All CP node IPs – health check validates etcd membership and API server
  control_plane_nodes = local.cp_ips

  # All worker node IPs – health check validates kubelet health on workers.
  # Without this the health check treats workers as "unexpected nodes" and fails.
  worker_nodes = local.worker_ips

  # Endpoint used to reach the Talos API (apid on port 50000).
  # Use the first CP node directly; this is not the Kubernetes API endpoint.
  endpoints = [local.cp_ips[0]]

  timeouts = {
    read = "10m"
  }

  depends_on = [talos_machine_bootstrap.this]
}

# ---- Retrieve kubeconfig -------------------------------------
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = var.talos_client_config
  endpoint             = local.cp_ips[0]
  node                 = local.cp_ips[0]

  depends_on = [data.talos_cluster_health.this]
}
