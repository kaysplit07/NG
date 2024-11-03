terraform {
  backend "azurerm" {
    storage_account_name = var.storage_account_name
    container_name       = var.container_name
    key                  = "${var.environment}/${var.project_name}.tfstate"
    resource_group_name  = var.resource_group_name
  }
}


variable "storage_account_name" {
  description = "The name of the Azure storage account for Terraform state"
  type        = string
}

variable "container_name" {
  description = "The name of the Azure storage container for Terraform state"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group containing the storage account"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
}

variable "project_name" {
  description = "Name of the project for organizing the state file"
  type        = string
}

