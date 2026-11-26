variable "cluster_name" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "talos_version" {
  type = string
}

variable "schematic_id" {
  type = string
}

variable "k8s_version" {
  type = string
}

variable "control_plane_count" {
  type = number
}

variable "worker_count" {
  type = number
}

variable "control_plane_ips" {
  type    = list(string)
  default = []
}

variable "worker_ips" {
  type    = list(string)
  default = []
}

variable "gateway" {
  type    = string
  default = ""
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "9.9.9.9"]
}
