# Memory headroom for SCST, the iSCSI target. It allocates a buffer per
# command, and with ARC allowed 87% of the VM's 8 GiB the free RAM ended up
# too fragmented for it: commands got QUEUE FULL until the initiator timed
# out, which corrupted Jellyfin's DB. The Talos nodes also cap iSCSI writes at
# 512 KiB (iscsi_udev_patch in modules/talos_config).

resource "truenas_tunable" "zfs_arc_max" {
  type    = "ZFS"
  var     = "zfs_arc_max"
  value   = tostring(4608 * 1024 * 1024) # 4.5 GiB
  comment = "Leave RAM for SCST and the kernel (see truenas/tunables.tf)"
  enabled = true
}

resource "truenas_tunable" "min_free_kbytes" {
  type    = "SYSCTL"
  var     = "vm.min_free_kbytes"
  value   = "262144" # 256 MiB, up from ~66 MiB
  comment = "Keep free RAM for SCST buffer allocations (see truenas/tunables.tf)"
  enabled = true
}
