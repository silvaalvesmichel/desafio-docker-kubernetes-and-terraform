variable "db_password" {
  description = "Postgres password. Supply it via TF_VAR_db_password or a git-ignored terraform.tfvars; it is never versioned."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must have at least 8 characters."
  }
}

variable "cluster_name" {
  description = "Name of the kind cluster."
  type        = string
  default     = "mural"
}

variable "node_image" {
  description = "kind node image (for example kindest/node:v1.33.1). Null uses the default of the kind provider."
  type        = string
  default     = null
}

variable "namespace" {
  description = "Namespace that receives the application."
  type        = string
  default     = "mural"
}

variable "host" {
  description = "Ingress host. Any *.localtest.me name resolves to 127.0.0.1."
  type        = string
  default     = "mural.localtest.me"
}

variable "http_port" {
  description = "Host port mapped to the ingress HTTP entrypoint."
  type        = number
  default     = 80
}

variable "https_port" {
  description = "Host port mapped to the ingress HTTPS entrypoint."
  type        = number
  default     = 443
}

variable "db_user" {
  description = "Postgres user."
  type        = string
  default     = "mural"
}

variable "db_name" {
  description = "Postgres database name."
  type        = string
  default     = "mural"
}

variable "traefik_chart_version" {
  description = "Version of the Traefik Helm chart."
  type        = string
  default     = "42.4.0"
}
