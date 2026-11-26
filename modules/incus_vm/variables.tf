variable "vm_name" {
  description = "Incus instance name."
  type        = string
}

variable "incus_project" {
  type    = string
  default = "default"
}

variable "profiles" {
  type = list(string)
}

variable "storage_pool" {
  type    = string
  default = "default"
}

variable "vcpu" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "disk_gb" {
  type    = number
  default = 20
}

variable "talos_image_alias" {
  description = "Talos image alias."
  type        = string
}

# variable "talos_version" {
#   description = "Talos version string, used for image alias de-duplication."
#   type        = string
# }

variable "machine_config" {
  description = "Talos machine configuration YAML (sensitive)."
  type        = string
  sensitive   = true
}

variable "ip_address" {
  description = "Static IP in CIDR notation. Empty string = DHCP."
  type        = string
  default     = ""
}

variable "gateway" {
  type    = string
  default = ""
}
