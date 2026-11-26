# ============================================================
# Cluster Identity
# ============================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster. Used as a prefix for all resources."
  type        = string
  default     = "talos-k8s"
}

variable "cluster_endpoint_ip" {
  description = <<-EOT
    IP address (or DNS name) that will be used as the Kubernetes API server endpoint.
    For a single-CP setup this is the CP VM's IP. For HA, point this at a load-balancer VIP.
    Must be reachable by all nodes and by kubectl clients.
  EOT
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to install (must be supported by the chosen Talos version)."
  type        = string
  default     = "1.36.0"
}

variable "talos_version" {
  description = "Talos Linux version to use for the disk images and machine configs."
  type        = string
  default     = "v1.14.6"
}

# ============================================================
# Incus / LXD connection
# ============================================================

variable "incus_remote" {
  description = "Address of the Incus server, e.g. https://<host>:8443 (registered as the provider remote \"homelab\")."
  type        = string
  default     = "local"
}

variable "incus_token" {
  description = <<-EOT
    Trust token for Incus remote connection. Only needed for initial setup.
    Generate with `incus config trust add <client_name>` on the incus node.
    Set via TF_VAR_incus_token environment variable.
  EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "incus_project" {
  description = "Incus project in which all resources will be created."
  type        = string
  default     = "default"
}

variable "incus_storage_pool" {
  description = "Incus storage pool for VM root disks."
  type        = string
  default     = "default"
}

variable "incus_profiles" {
  # https://linuxcontainers.org/incus/docs/main/profiles/
  description = "Incus profiles to apply to VM instances"
  type        = list(string)
  default     = []
}

# ============================================================
# Control Plane nodes
# ============================================================

variable "control_plane_count" {
  description = "Number of control-plane nodes. Use 1 for single-CP, 3 (or any odd number) for HA."
  type        = number
  default     = 1

  validation {
    condition     = var.control_plane_count >= 1
    error_message = "At least one control-plane node is required."
  }
}

variable "control_plane_cpu" {
  description = "vCPU count for each control-plane VM."
  type        = number
  default     = 2
}

variable "control_plane_memory_mb" {
  description = "RAM in MiB for each control-plane VM."
  type        = number
  default     = 2048
}

variable "control_plane_disk_gb" {
  description = "Root disk size in GiB for each control-plane VM."
  type        = number
  default     = 20
}

variable "control_plane_ip_addresses" {
  description = <<-EOT
    Static IP addresses (CIDR notation, e.g. \"192.168.1.101/24\") for control-plane nodes,
    in order (index 0 = first CP node). Must have at least control_plane_count entries.
    Leave empty to rely on DHCP (not recommended for control-plane nodes).
  EOT
  type        = list(string)
  default     = []
}

# ============================================================
# Worker nodes
# ============================================================

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 0
    error_message = "Worker count must be 0 or greater."
  }
}

variable "worker_cpu" {
  description = "vCPU count for each worker VM."
  type        = number
  default     = 2
}

variable "worker_memory_mb" {
  description = "RAM in MiB for each worker VM."
  type        = number
  default     = 4096
}

variable "worker_disk_gb" {
  description = "Root disk size in GiB for each worker VM."
  type        = number
  default     = 40
}

variable "worker_ip_addresses" {
  description = <<-EOT
    Static IP addresses (CIDR notation) for worker nodes, in order.
    Leave empty to rely on DHCP.
  EOT
  type        = list(string)
  default     = []
}

# ============================================================
# Networking
# ============================================================

variable "gateway" {
  description = "Default gateway for static-IP nodes."
  type        = string
  default     = ""
}

variable "dns_servers" {
  description = "List of DNS server IPs to configure on nodes."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# ============================================================
# Talos Image
# ============================================================

variable "talos_image_alias" {
  description = "Talos image alias."
  type        = string
}

variable "talos_schematic_id" {
  description = <<-EOT
    Image Factory schematic ID of the imported Talos image (import-talos-image.sh
    logs it as "Schematic ID"). Sets the installer image, so reinstalls and
    upgrades keep the same system extensions.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.talos_schematic_id))
    error_message = "The schematic ID is a 64-character lowercase hex string."
  }
}


# ============================================================
# Truenas
# ============================================================

variable "truenas_iso_path" {
  description = "Path to bootable Truenas ISO image."
  type        = string
  default     = "/opt/TrueNAS-SCALE-25.10.7.iso"
}

variable "truenas_data_disks" {
  description = "Disk-by-id paths to pass through to the TrueNAS VM, in order"
  type        = list(string)
  default = [
    "/dev/disk/by-id/usb-EXAMPLE-SERIAL",
    # "/dev/disk/by-id/ata-...",  # add more here as you attach disks
  ]
}

# ============================================================
# State encryption
# ============================================================

variable "state_passphrase" {
  description = "Passphrase for OpenTofu state encryption (backend.tf). Set via TF_VAR_state_passphrase; keep a copy in the password manager."
  type        = string
  sensitive   = true
}
