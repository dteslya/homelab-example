locals {
  pool = "wd_green_pool"

  # Datasets the cluster mounts through static PVs, plus the parents
  # truenas-csi creates its volumes under. truenas-csi creates and deletes
  # its own pvc-* datasets and zvols: never add them here.
  datasets = toset([
    "k8s",
    "k8s/iscsi", # truenas-iscsi-config zvols (datasetPath in the StorageClass)
    "books",
    "photos",
    "documents",
    "backups",
    "backups/truenas", # config DB + secret seed, a child so the backups NFS share doesn't expose it
    "home",            # docmirror's home: TrueNAS keeps SSH keys in the home, which must be on a pool
  ])
}

resource "truenas_dataset" "this" {
  for_each = local.datasets

  pool           = local.pool
  name           = basename(each.key)
  parent_dataset = dirname(each.key) == "." ? null : dirname(each.key)
}
