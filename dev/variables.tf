variable "rg_name" {
  type        = string
  description = "Name of the resource group"
}

variable "location" {
  type        = string
  description = "Location of the resource group"
}

variable "service_principal_name" {
  type        = string
  description = "Name of the service principal"
}

variable "key_vault_name" {
  type        = string
  description = "Name of the key vault"
}

variable "SUB_ID" {
  type        = string
  description = "Azure Subscription ID"
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the AKS cluster"
}

