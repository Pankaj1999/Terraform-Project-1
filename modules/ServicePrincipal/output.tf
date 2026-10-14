output "service_principal_name" {
  value = azuread_application.main.display_name
}

output "service_principal_object_id" {
  value = azuread_service_principal.main.object_id
}

output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}

output "service_principal_client_id" {
  value = azuread_service_principal.main.client_id
}

output "service_principal_client_secret" {
  value = azuread_service_principal_password.main.value
}
