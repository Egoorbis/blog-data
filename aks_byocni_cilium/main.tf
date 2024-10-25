resource "azuread_group" "aks-admins-group" {
  display_name     = "aks-admins"
  security_enabled = true
}

resource "azuread_application" "aks_app" {
  display_name            = "aks-app"
  owners                  = [data.azurerm_client_config.current.object_id]
  prevent_duplicate_names = true
}

resource "azuread_service_principal" "aks_spn" {
  client_id = azuread_application.aks_app.client_id
}

resource "azuread_service_principal_password" "aks_spn_password" {
  service_principal_id = azuread_service_principal.aks_spn.id
  end_date             = "2024-12-01T00:00:00Z"
}

resource "azuread_group_member" "aks-admins" {
  for_each = {
    user = data.azurerm_client_config.current.object_id
    spn  = azuread_service_principal.aks_spn.id
  }

  group_object_id  = azuread_group.aks-admins-group.id
  member_object_id = each.value
}

module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.1"
}

resource "azurerm_resource_group" "aks-rg" {
  name     = module.naming.resource_group.name_unique
  location = "switzerlandnorth"
}

module "avm-res-network-networksecuritygroup" {
  count               = 2
  source              = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version             = "0.2.0"
  resource_group_name = azurerm_resource_group.aks-rg.name
  name                = "${module.naming.network_security_group.name}-${count.index}"
  location            = azurerm_resource_group.aks-rg.location
}


module "avm-res-network-virtualnetwork" {
  source              = "Azure/avm-res-network-virtualnetwork/azurerm"
  version             = "0.4.0"
  location            = azurerm_resource_group.aks-rg.location
  resource_group_name = azurerm_resource_group.aks-rg.name
  name                = module.naming.virtual_network.name_unique

  address_space = ["10.11.0.0/16"]
  subnets = {
    subnet0 = {
      name             = "${module.naming.subnet.name_unique}0"
      address_prefixes = ["10.11.0.0/24"]
      network_security_group = {
        id = module.avm-res-network-networksecuritygroup[0].resource_id
      }
    }
    subnet1 = {
      name             = "${module.naming.subnet.name_unique}1"
      address_prefixes = ["10.11.1.0/24"]
      network_security_group = {
        id = module.avm-res-network-networksecuritygroup[1].resource_id
      }
    }
  }
}

module "avm-res-managedidentity-userassignedidentity" {
  source              = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version             = "0.3.3"
  name                = module.naming.user_assigned_identity.name_unique
  location            = azurerm_resource_group.aks-rg.location
  resource_group_name = azurerm_resource_group.aks-rg.name
}

module "avm-res-authorization-roleassignment" {
  source  = "Azure/avm-res-authorization-roleassignment/azurerm"
  version = "0.1.0"
  role_assignments_azure_resource_manager = {
    "aks" = {
      principal_id         = module.avm-res-managedidentity-userassignedidentity.principal_id
      role_definition_name = "Network Contributor"
      scope                = azurerm_resource_group.aks-rg.id
    }
  }
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                              = module.naming.kubernetes_cluster.name_unique
  location                          = azurerm_resource_group.aks-rg.location
  resource_group_name               = azurerm_resource_group.aks-rg.name
  dns_prefix                        = "cilium-aks"
  sku_tier                          = "Free"
  azure_policy_enabled              = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  local_account_disabled            = true
  role_based_access_control_enabled = true

  default_node_pool {
    name                   = "systempool"
    enable_auto_scaling    = true
    enable_host_encryption = true
    node_count             = 1
    min_count              = 1
    max_count              = 3
    vm_size                = "Standard_DS2_v2"
    vnet_subnet_id         = module.avm-res-network-virtualnetwork.subnets["subnet0"].resource_id
    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [module.avm-res-managedidentity-userassignedidentity.resource_id]
  }

  network_profile {
    network_plugin = "none"
  }

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }

  depends_on = [
    module.avm-res-authorization-roleassignment
  ]

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    managed                = true
    admin_group_object_ids = [azuread_group.aks-admins-group.id]
    tenant_id              = data.azurerm_client_config.current.tenant_id
  }
}
