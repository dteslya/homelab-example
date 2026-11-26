# ============================================================
# TrueNAS configuration (separate stack from the root module)
# ============================================================
# The root module creates the VM; this stack configures what runs inside it.
# It needs an installed TrueNAS and an API key, so it can't share an apply
# with the root module. See README.md → TrueNAS settings.

terraform {
  required_version = ">= 1.8.0" # state encryption with variables (backend.tf)

  required_providers {
    # JSON-RPC 2.0 over WebSocket (/api/current); the REST API is deprecated
    truenas = {
      source  = "PjSalty/truenas"
      version = "3.4.0"
    }
  }
}

provider "truenas" {
  url     = "wss://10.0.14.10"
  api_key = var.truenas_api_key

  # Self-signed cert, same as truenasInsecure in argocd/truenas-csi
  insecure_skip_verify = true

  # Refuse every delete. Datasets here hold data that Terraform must never
  # destroy; turn this off for one apply when a delete is really intended.
  destroy_protection = true
}
