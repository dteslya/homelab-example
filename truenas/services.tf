# nfs and iscsitarget for truenas-csi and the static PVs; ssh for docmirror
# (README.md → Paperless mirror)
resource "truenas_service" "this" {
  for_each = { nfs = "nfs", iscsi = "iscsitarget", ssh = "ssh" }

  service = each.value
  enable  = true
}

# truenas-csi matches the portal by the exact iscsiPortal address in
# argocd/truenas-csi/configmap-patch.yaml; a 0.0.0.0 portal doesn't match.
# The driver creates its own targets, extents and initiator groups.
resource "truenas_iscsi_portal" "csi" {
  listen = [
    { ip = "10.0.14.10" }, # port 3260 is global since 25.10
  ]
}
