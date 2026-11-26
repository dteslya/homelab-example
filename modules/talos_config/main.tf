# ------------------------------------------------------------------
# Module: talos_config
# Generates Talos secrets, machine configs, and the talosconfig file.
# ------------------------------------------------------------------

terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.12.0"
    }
  }
}

# ---- Cluster secrets (PKI, tokens) ----------------------------
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version

  lifecycle {
    # The secrets keep the version contract they were created with. On a
    # talos_version change the provider plans every secret as unknown and
    # its Update does not restore them, which would wipe them from state.
    ignore_changes = [talos_version]
  }
}

# The nocloud installer for the same Image Factory schematic as the VM image,
# so reinstalls and upgrades keep its system extensions. Since Talos 1.14 it
# lives in its own document; the provider's default is the plain metal one.
locals {
  installer_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "UnattendedInstallConfig"
    installer = {
      image = "factory.talos.dev/nocloud-installer/${var.schematic_id}:${var.talos_version}"
    }
  })

  # Caps iSCSI writes to TrueNAS at 512 KiB (default 8 MiB). SCST needs one
  # buffer per command, and an 8 MiB one often fails to allocate in the
  # TrueNAS VM's fragmented RAM: it answers QUEUE FULL until the initiator's
  # 180 s timeout turns it into an I/O error, which corrupted Jellyfin's DB.
  iscsi_udev_patch = yamlencode({
    machine = {
      udev = {
        rules = [
          "ACTION==\"add|change\", SUBSYSTEM==\"block\", KERNEL==\"sd*\", ENV{DEVTYPE}==\"disk\", ATTRS{vendor}==\"TrueNAS*\", ATTR{queue/max_sectors_kb}=\"512\"",
        ]
      }
    }
  })
}

# ---- Base control-plane machine config (shared template) ------
data "talos_machine_configuration" "control_plane" {
  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.k8s_version

  config_patches = [
    # Enable KubePrism (in-cluster API load-balancer) for HA setups
    yamlencode({
      machine = {
        features = {
          kubePrism = { enabled = true, port = 7445 }
        }
      }
      cluster = {
        # Workloads on the CP only when there is nowhere else to run them:
        # a 4 GB CP with apps on it OOMs its own control-plane components.
        allowSchedulingOnControlPlanes = var.worker_count == 0
        inlineManifests = [
          {
            name     = "argocd-namespace",
            contents = file("${path.root}/bootstrap/argocd-namespace.yaml")
          },
          {
            name     = "argocd-installer",
            contents = file("${path.root}/bootstrap/argocd-installer.yaml")
          },
          {
            name     = "root-app",
            contents = file("${path.root}/bootstrap/root-app.yaml")
          }
        ]
      }
    })
  ]
}

# ---- Base worker machine config (shared template) -------------
data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.k8s_version
}

# ---- Per-node control-plane configs (with optional static IP) -
data "talos_machine_configuration" "control_plane_node" {
  count = var.control_plane_count

  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.k8s_version

  config_patches = concat(
    # Base patches (same as above)
    [
      yamlencode({
        machine = {
          # Needed by tailscale subnet router
          kubelet = {
            extraArgs = {
              allowed-unsafe-sysctls = "net.ipv4.ip_forward,net.ipv6.conf.all.forwarding"
            }
          }
          features = {
            kubePrism = { enabled = true, port = 7445 }
          }
        }
        cluster = {
          # See the base config above: NoSchedule on the CP whenever workers exist.
          allowSchedulingOnControlPlanes = var.worker_count == 0
          # Garbage-collect pods left Succeeded/Failed by graceful node shutdown
          # (default threshold of 12500 never triggers on a small cluster)
          controllerManager = {
            extraArgs = {
              terminated-pod-gc-threshold = "20"
            }
          }
        }
      }),
      local.installer_patch,
      local.iscsi_udev_patch,
    ],
    # Static network patch – only when an IP was provided
    length(var.control_plane_ips) > count.index ? [
      yamlencode({
        machine = {
          network = {
            interfaces = [
              {
                interface = "enp5s0"
                addresses = [var.control_plane_ips[count.index]]
                routes = var.gateway != "" ? [
                  { network = "0.0.0.0/0", gateway = var.gateway }
                ] : []
                dhcp = false
              }
            ]
            nameservers = var.dns_servers
          }
        }
      })
    ] : []
  )
}

# ---- Per-node worker configs ----------------------------------
data "talos_machine_configuration" "worker_node" {
  count = var.worker_count

  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.k8s_version

  config_patches = concat(
    [
      yamlencode({
        machine = {
          # Needed by tailscale subnet router
          kubelet = {
            extraArgs = {
              allowed-unsafe-sysctls = "net.ipv4.ip_forward,net.ipv6.conf.all.forwarding"
            }
          }
        }
      }),
      local.installer_patch,
      local.iscsi_udev_patch,
    ],
    # Static network patch – only when an IP was provided
    length(var.worker_ips) > count.index ? [
      yamlencode({
        machine = {
          network = {
            interfaces = [
              {
                interface = "enp5s0"
                addresses = [var.worker_ips[count.index]]
                routes = var.gateway != "" ? [
                  { network = "0.0.0.0/0", gateway = var.gateway }
                ] : []
                dhcp = false
              }
            ]
            nameservers = var.dns_servers
          }
        }
      })
    ] : []
  )
}

# ---- Client configuration (talosconfig) ----------------------
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  # List all CP endpoints so talosctl can fail-over in HA
  endpoints = length(var.control_plane_ips) > 0 ? [
    for cidr in slice(var.control_plane_ips, 0, var.control_plane_count) :
    split("/", cidr)[0]
  ] : []
}
