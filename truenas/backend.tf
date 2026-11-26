# ============================================================
# State backend – Backblaze B2 (S3-compatible API)
# ============================================================
# Bucket, region and endpoint live in the gitignored backend.hcl
# (see README.md → State backend):
#   tofu -chdir=truenas init -backend-config=../backend.hcl
# Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (.envrc).

terraform {
  backend "s3" {
    key = "homelab/truenas.tfstate"

    # B2 is not AWS: skip the AWS-only checks and checksum headers it rejects
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }

  # The state holds API keys and passwords, so B2 only ever sees
  # ciphertext. Losing the passphrase makes the state unrecoverable.
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }

    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method = method.aes_gcm.main
    }

    plan {
      method = method.aes_gcm.main
    }
  }
}
