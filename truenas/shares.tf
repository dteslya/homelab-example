locals {
  # Cluster node subnet. Pods reach NFS through their node's IP.
  nfs_networks = ["10.0.4.0/24"]

  # Datasets mounted by static PVs (argocd/*/pv-*.yaml). truenas-csi manages
  # the shares of its own volumes.
  nfs_shares = toset(["books", "photos", "documents", "backups"])
}

resource "truenas_share_nfs" "this" {
  for_each = local.nfs_shares

  path          = truenas_dataset.this[each.key].mount_point
  networks      = local.nfs_networks
  maproot_user  = "root"
  maproot_group = "wheel"
}
