terraform {
  backend "azurerm" {
    use_azuread_auth = true
    use_oidc         = true
  }
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.104.0"
    }
  }
}

provider "azurerm" {
  features {}
  use_oidc = true
}

resource "azurerm_resource_group" "rg-gha" {
  name     = "rg-terraform-github-actions"
  location = "Sweden Central"
}
