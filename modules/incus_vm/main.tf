# ------------------------------------------------------------------
# Module: incus_vm
# Creates a single Talos Linux VM inside Incus.
#
# The image is referenced by alias (e.g. "talos-abc123def456-v1.13.2")
# which was imported manually into the Incus image store by the
# import-talos-image.sh script before this module runs.
# ------------------------------------------------------------------

terraform {
  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.2.0"
    }
  }
}

resource "incus_instance" "vm" {
  name     = var.vm_name
  project  = var.incus_project
  image    = var.talos_image_alias
  type     = "virtual-machine"
  profiles = var.profiles

  config = merge(
    {
      "limits.cpu"    = tostring(var.vcpu)
      "limits.memory" = "${var.memory_mb}MiB"

      # Talos does not ship a Secure Boot-signed bootloader.
      "security.secureboot" = "false"

      # Talos machine config delivered via the NoCloud datasource.
      # The nocloud image variant reads user-data from a CDROM/vfat disk
      # with volume label "cidata". Incus generates this disk automatically
      # from user.user-data when the cloud-init:config device is attached.
      "user.user-data" = var.machine_config
    },
    var.ip_address != "" ? {
      # Incus passes this to the nocloud network-config file on the cidata disk.
      "user.network-config" = yamlencode({
        version = 2
        ethernets = {
          enp5s0 = {
            addresses = [var.ip_address]
            gateway4  = var.gateway
          }
        }
      })
    } : {}
  )

  # Root disk – virtio-blk so UEFI sees a plain PCI block device (vda),
  # not a SCSI device which Secure Boot can block even when secureboot=false.
  device {
    name = "root"
    type = "disk"
    properties = {
      pool     = var.storage_pool
      path     = "/"
      size     = "${var.disk_gb}GiB"
      "io.bus" = "virtio-blk"
    }
  }

  # NoCloud config disk – Incus builds a small ISO with volume label "cidata"
  # from user.user-data and user.network-config, then attaches it as a CDROM.
  # Talos's nocloud datasource reads user-data (machine config) and
  # network-config from this disk on first boot.
  device {
    name = "cloud-init"
    type = "disk"
    properties = {
      source = "cloud-init:config"
    }
  }

  running = true

  lifecycle {
    # Machine config changes after first boot go through talosctl, not tofu.
    # Talos upgrades too: the image only seeds a new VM, and changing it
    # forces replacement.
    ignore_changes = [config["user.user-data"], image]
  }
}

