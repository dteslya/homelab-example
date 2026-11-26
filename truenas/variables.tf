variable "truenas_api_key" {
  description = "TrueNAS API key used by the provider (TF_VAR_truenas_api_key in .envrc)."
  type        = string
  sensitive   = true
}

variable "state_passphrase" {
  description = "Passphrase for OpenTofu state encryption (backend.tf). Same as the root module: TF_VAR_state_passphrase."
  type        = string
  sensitive   = true
}
