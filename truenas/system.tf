# Builds the same tar as Manage Configuration → Download File with
# "Export Password Secret Seed" (README.md → TrueNAS config). Runs before
# the 03:00 B2 Cloud Sync of the backups dataset.
resource "truenas_cronjob" "config_backup" {
  user            = "root"
  command         = "sqlite3 /data/freenas-v1.db \".backup /tmp/freenas-v1.db\" && tar -cf ${truenas_dataset.this["backups/truenas"].mount_point}/truenas-config.tar -C /tmp freenas-v1.db -C /data pwenc_secret && rm /tmp/freenas-v1.db"
  schedule_minute = "30"
  schedule_hour   = "2"
}

# Through the in-cluster mail relay (README.md → Mail relay), which allows
# TrueNAS by IP without authentication.
resource "truenas_mail_config" "this" {
  fromemail      = "truenas@lab.example.com"
  fromname       = "Truenas"
  outgoingserver = "10.0.4.203"
  port           = 587
  security       = "PLAIN"
  smtp           = false
}

resource "truenas_alert_service" "email" {
  name  = "E-Mail"
  type  = "Mail"
  level = "WARNING"

  # Empty sends to the admin user's e-mail address
  settings_json = jsonencode({
    email = ""
  })
}

# Reads Paperless's export/ for the Mac mirror (README.md → Paperless mirror).
# Read-only access comes from the exporter's 644/755 modes, not an ACL.
resource "truenas_user" "docmirror" {
  username          = "docmirror"
  full_name         = "docmirror"
  password_disabled = true
  shell             = "/usr/bin/sh"
  home              = "${truenas_dataset.this["home"].mount_point}/docmirror"
  sshpubkey         = "ssh-ed25519 AAAA...REPLACE_WITH_YOUR_PUBLIC_KEY user@laptop"
}
