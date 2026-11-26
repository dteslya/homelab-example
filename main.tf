terraform {
  required_version = ">= 1.8.0" # state encryption with variables (backend.tf)

  required_providers {
    # Incus provider – manages VMs, storage volumes, networks
    incus = {
      source  = "lxc/incus"
      version = "1.2.1"
    }
    # Talos provider – generates machine configs and bootstraps the cluster
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0"
    }
    # Used for local kubeconfig / talosconfig output files
    local = {
      source  = "hashicorp/local"
      version = ">= 2.9.0"
    }
  }
}

# ============================================================
# Provider configuration
# ============================================================

provider "incus" {
  accept_remote_certificate    = true
  generate_client_certificates = true
  default_remote               = "homelab"

  remote {
    name    = "homelab"
    address = var.incus_remote
    token   = var.incus_token
  }
}

provider "talos" {}

# ============================================================
# Locals
# ============================================================

locals {
  cluster_endpoint = "https://${var.cluster_endpoint_ip}:6443"

  cp_has_static_ips     = length(var.control_plane_ip_addresses) >= var.control_plane_count
  worker_has_static_ips = length(var.worker_ip_addresses) >= var.worker_count
}

# ============================================================
# Module: Talos machine config generation
# ============================================================

module "talos_config" {
  source = "./modules/talos_config"

  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  talos_version    = var.talos_version
  schematic_id     = var.talos_schematic_id
  k8s_version      = var.kubernetes_version

  control_plane_count = var.control_plane_count
  worker_count        = var.worker_count

  control_plane_ips = var.control_plane_ip_addresses
  worker_ips        = var.worker_ip_addresses
  gateway           = var.gateway
  dns_servers       = var.dns_servers
}

# ============================================================
# Module: Incus VM provisioning
# ============================================================

module "control_plane_vms" {
  source = "./modules/incus_vm"

  for_each = toset([for i in range(var.control_plane_count) : tostring(i)])

  vm_name           = "${var.cluster_name}-cp-${each.key}"
  incus_project     = var.incus_project
  profiles          = var.incus_profiles
  storage_pool      = var.incus_storage_pool
  vcpu              = var.control_plane_cpu
  memory_mb         = var.control_plane_memory_mb
  disk_gb           = var.control_plane_disk_gb
  talos_image_alias = var.talos_image_alias

  machine_config = module.talos_config.control_plane_configs[tonumber(each.key)]
}

module "worker_vms" {
  source = "./modules/incus_vm"

  for_each = toset([for i in range(var.worker_count) : tostring(i)])

  vm_name           = "${var.cluster_name}-worker-${each.key}"
  incus_project     = var.incus_project
  profiles          = var.incus_profiles
  storage_pool      = var.incus_storage_pool
  vcpu              = var.worker_cpu
  memory_mb         = var.worker_memory_mb
  disk_gb           = var.worker_disk_gb
  talos_image_alias = var.talos_image_alias

  machine_config = module.talos_config.worker_configs[tonumber(each.key)]
}

# ============================================================
# Truenas VM provisioning
# ============================================================

resource "incus_instance" "truenas" {

  name = "truenas"
  # image = ""
  type = "virtual-machine"

  device {
    name = "enp1s0"
    type = "nic"
    properties = {
      nictype = "bridged"
      parent  = "br-vlan14"
    }
  }

  device {
    name = "root"
    type = "disk"

    properties = {
      path = "/"
      pool = var.incus_storage_pool
      size = "32GiB"
    }
  }

  # The TrueNAS install ISO, attached as a USB device so it shows up as
  # bootable installer media.
  # Uncomment if doing fresh install.
  #
  # device {
  #   name = "install-iso"
  #   type = "disk"
  #   properties = {
  #     source          = var.truenas_iso_path
  #     "io.bus"        = "usb"
  #     "boot.priority" = "10"
  #   }
  # }

  # One disk device per entry in var.truenas_data_disks
  dynamic "device" {
    for_each = { for idx, path in var.truenas_data_disks : idx => path }
    content {
      name = "data-hdd-${device.key}"
      type = "disk"
      properties = {
        source   = device.value
        "io.bus" = "virtio-scsi"
      }
    }
  }

  config = {
    "limits.cpu"          = 4
    "limits.memory"       = "8GiB"
    "security.secureboot" = "false"
  }
}

# ============================================================
# Module: Kubernetes bootstrap
# ============================================================

module "kubernetes" {
  source = "./modules/kubernetes"

  cluster_name        = var.cluster_name
  cluster_endpoint    = local.cluster_endpoint
  talos_client_config = module.talos_config.client_configuration

  # Pass full CIDR lists – the module strips prefixes internally
  control_plane_ips = var.control_plane_ip_addresses
  worker_ips        = var.worker_ip_addresses

  depends_on = [
    module.control_plane_vms,
    module.worker_vms,
  ]
}

# ============================================================
# Write credentials to disk
# ============================================================

resource "local_sensitive_file" "talosconfig" {
  content         = module.talos_config.talosconfig
  filename        = "${path.module}/output/talosconfig"
  file_permission = "0600"
}

resource "local_sensitive_file" "kubeconfig" {
  content         = module.kubernetes.kubeconfig
  filename        = "${path.module}/output/kubeconfig"
  file_permission = "0600"
}
