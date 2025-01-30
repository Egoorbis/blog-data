data "azurerm_client_config" "current" {}

data "azuread_service_principal" "aks-aad-server" {
  display_name = "Azure Kubernetes Service AAD Server"
}

data "azurerm_kubernetes_cluster" "aks" {
  name                = azurerm_kubernetes_cluster.aks.name
  resource_group_name = azurerm_resource_group.aks-rg.name
}
