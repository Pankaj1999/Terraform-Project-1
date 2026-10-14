resource "azurerm_resource_group" "rg1" {
  name     = var.rg_name
  location = var.location
}

resource "tls_private_key" "aks_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

module "ServicePrincipal" {
  source                 = "../modules/ServicePrincipal"
  service_principal_name = var.service_principal_name

  depends_on = [azurerm_resource_group.rg1]
}

resource "azurerm_role_assignment" "sp_role_assignment" {
  principal_id         = module.ServicePrincipal.service_principal_object_id
  role_definition_name = "Contributor"
  scope                = "/subscriptions/${var.SUB_ID}"

  depends_on = [module.ServicePrincipal]
}

module "keyvault" {
  source              = "../modules/keyvault"
  key_vault_name      = var.key_vault_name
  location            = var.location
  resource_group_name = var.rg_name

  #service_principal_name = var.service_principal_name
  #service_principal_object_id = module.ServicePrincipal.service_principal_object_id
  #service_principal_tenant_id = module.ServicePrincipal.service_principal_tenant_id

  depends_on = [module.ServicePrincipal]
}

resource "azurerm_key_vault_secret" "sp_client_id" {
  name         = module.ServicePrincipal.service_principal_client_id
  value        = module.ServicePrincipal.service_principal_client_secret
  key_vault_id = module.keyvault.key_vault_id

  depends_on = [module.keyvault]
}

resource "azurerm_key_vault_secret" "aks_ssh_private_key" {
  name         = "aks-ssh-private-key"
  value        = tls_private_key.aks_ssh.private_key_pem
  key_vault_id = module.keyvault.key_vault_id

  depends_on = [module.keyvault]
}

module "aks" {
  source              = "../modules/aks/"
  client_id           = module.ServicePrincipal.service_principal_client_id
  client_secret       = module.ServicePrincipal.service_principal_client_secret
  location            = var.location
  resource_group_name = var.rg_name
  aks_cluster_name    = var.aks_cluster_name
  ssh_public_key      = tls_private_key.aks_ssh.public_key_openssh

  depends_on = [module.ServicePrincipal]
}

resource "local_file" "kubeconfig" {
  content  = module.aks.config
  filename = "${path.module}/kubeconfig.yaml"

  depends_on = [module.aks]
}