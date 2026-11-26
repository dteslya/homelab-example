locals {
  # Daily at 00:00, kept for 2 weeks. Datasets are relative to the pool.
  snapshot_tasks = {
    books     = { dataset = "books", recursive = false }
    photos    = { dataset = "photos", recursive = false }
    documents = { dataset = "documents", recursive = false }
    backups   = { dataset = "backups", recursive = true }

    # The media library is truenas-csi's dynamic volume for the media-library
    # PVC (argocd/media-storage/pvc-library.yaml). If that PVC is ever
    # recreated, the volume gets a new name: update it here.
    media = { dataset = "pvc-4a28813b-00fe-4654-bbe9-e607dfc0cdcc", recursive = false }

    # Every truenas-iscsi-config zvol. truenas-csi deletes volumes with
    # recursive + force, so the snapshots don't block PVC deletion.
    k8s-iscsi = { dataset = "k8s/iscsi", recursive = true }
  }
}

resource "truenas_snapshot_task" "this" {
  for_each = local.snapshot_tasks

  dataset        = "${local.pool}/${each.value.dataset}"
  recursive      = each.value.recursive
  lifetime_value = 2
  lifetime_unit  = "WEEK"
}
