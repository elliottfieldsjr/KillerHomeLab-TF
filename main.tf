provider "azurerm" {
  version = "=2.0.0"
  features {}
}

terraform {
  backend "azurerm" {
    resource_group_name  = "elliottf-terraform"
    storage_account_name = "saelliottf"
    container_name       = "terraform-state"
    key                  = "terraform.tfstate"
  }
}

variable ResourceGroup1Name {
  default = "1-DomainController_1-Workstation"
}

variable adminUsername {
  default = "mcitp-admin"
}

variable adminPassword {
  default = ""
}

variable WindowsServerLicenseType {
  default = "Windows_Server"
}

variable WindowsClientLicenseType {
  default = "Windows_Client"
}

variable NamingConvention {
  default = "khl"
}

variable NetBiosDomain {
  default = "killerhomelab"
}

variable InternalDomain {
  default = "killerhomelab"
}

variable SubDNSDomain {
  default = ""
}

variable SubDNSBaseDN {
  default = ""
}

variable TLD {
  default = "com"
}

variable Vnet1ID {
  default = "10.1"
}

variable ReverseLookup1 {
  default = "1.10"
}

variable DC1LastOctet {
  default = "10"
}

variable WK1LastOctet {
  default = "10"
}

variable DC1OSVersion {
  default = "2019-Datacenter"
}

variable WK1OSVersion {
  default = "19h1-pro"
}

variable DC1VMSize {
  default = "Standard_D2s_v3"
}

variable WK1VMSize {
  default = "Standard_D2s_v3"
}

variable Location1 {
  default = "USGovVirginia"
}

locals {
  PublicIPAddressName = "${local.Vnet1Name}-Bastion-pip"
  Vnet1Name = "${var.NamingConvention}-VNet1"  
  Vnet1Prefix = "${var.Vnet1ID}.0.0/16"    
  Vnet1Subnet1Name = "${var.NamingConvention}-VNet1-Subnet1"  
  Vnet1Subnet1Prefix = "${var.Vnet1ID}.1.0/24"      
  Vnet1Subnet2Name = "${var.NamingConvention}-VNet1-Subnet2"  
  Vnet1Subnet2Prefix = "${var.Vnet1ID}.2.0/24"        
  Vnet1BastionSubnetPrefix = "${var.Vnet1ID}.253.0/24"
  DC1Name = "${var.NamingConvention}-dc-01"      
  DC1IP = "${var.Vnet1ID}.1.${var.DC1LastOctet}" 
  WK1Name = "${var.NamingConvention}-wk-01"                         
  WK1IP = "${var.Vnet1ID}.2.${var.WK1LastOctet}"                    
  DomainName = "${var.SubDNSDomain}${var.InternalDomain}.${var.TLD}"    
  BaseDN = "${var.SubDNSBaseDN}DC=${var.InternalDomain},DC=${var.TLD}"      
  WKOUPath = "OU=Windows 10,OU=Workstations,${local.BaseDN}" 
}

resource "azurerm_resource_group" "rg1" {
  name     = var.ResourceGroup1Name
  location = var.Location1
}

resource "azurerm_template_deployment" "vnet" {
    name                = "DeployVNet"
    resource_group_name = azurerm_resource_group.rg1.name
  
    template_body = file("nestedtemplates/vnet.json")
  
    parameters = {
      "vnetName" = local.Vnet1Name
      "vnetprefix" = local.Vnet1Prefix
      "subnet1Name" = local.Vnet1Subnet1Name
      "subnet1Prefix" = local.Vnet1Subnet1Prefix
      "subnet2Name" = local.Vnet1Subnet2Name
      "subnet2Prefix" = local.Vnet1Subnet2Prefix      
      "BastionsubnetPrefix" = local.Vnet1BastionSubnetPrefix
      "location" = var.Location1                
    }
  
    deployment_mode = "Incremental"
  }

  resource "azurerm_template_deployment" "bastionhost" {
    name                = "DeployBastionHost"
    resource_group_name = azurerm_resource_group.rg1.name
  
    template_body = file("nestedtemplates/bastionhost.json")
  
    parameters = {
      "publicIPAddressName" = local.PublicIPAddressName
      "AllocationMethod" = "Static"
      "vnetName" = local.Vnet1Name
      "subnetName" = "AzureBastionSubnet"
      "location" = var.Location1                
    }
  
    deployment_mode = "Incremental"
    depends_on = [azurerm_template_deployment.vnet]
  }

    resource "azurerm_template_deployment" "deploydc1vm" {
    name                = "DeployDC1VM"
    resource_group_name = azurerm_resource_group.rg1.name

    template_body = file("nestedtemplates/1nic-2disk-vm.json")
  
    parameters = {
      "computerName" = local.DC1Name
      "computerIP" = local.DC1IP            
      "Publisher" = "MicrosoftWindowsServer"
      "Offer" = "WindowsServer"      
      "OSVersion" = var.DC1OSVersion
      "licenseType" = var.WindowsServerLicenseType      
      "DataDisk1Name" = "NTDS"
      "VMSize" = var.DC1VMSize
      "vnetName" = local.Vnet1Name
      "subnetName" = local.Vnet1Subnet1Name
      "vnetprefix" = local.Vnet1Prefix
      "subnetPrefix" = local.Vnet1Subnet1Prefix
      "adminUsername" = var.adminUsername
      "adminPassword" = var.adminPassword      
      "location" = var.Location1                
    }
  
    deployment_mode = "Incremental"
    depends_on = [azurerm_template_deployment.vnet]
  }

    resource "azurerm_template_deployment" "promotedc1" {
    name                = "PromoteDC1"
    resource_group_name = azurerm_resource_group.rg1.name

    template_body = file("nestedtemplates/firstdc.json")
  
    parameters = {
      "computerName" = local.DC1Name
      "NetBiosDomain" = var.NetBiosDomain
      "DomainName" = local.DomainName
      "adminUsername" = var.adminUsername
      "adminPassword" = var.adminPassword      
      "location" = var.Location1                
    }
  
    deployment_mode = "Incremental"
    depends_on = [azurerm_template_deployment.deploydc1vm]    
  }

    resource "azurerm_template_deployment" "updatevnet1dns" {
    name                = "UpdateVNet1DNS"
    resource_group_name = azurerm_resource_group.rg1.name

    template_body = file("nestedtemplates/updatevnetdns.json")
  
    parameters = {
      "vnetName" = local.Vnet1Name
      "vnetprefix" = local.Vnet1Prefix
      "subnet1Name" = local.Vnet1Subnet1Name
      "subnet1Prefix" = local.Vnet1Subnet1Prefix
      "subnet2Name" = local.Vnet1Subnet2Name
      "subnet2Prefix" = local.Vnet1Subnet2Prefix      
      "BastionsubnetPrefix" = local.Vnet1BastionSubnetPrefix
      "DNSServerIP" = local.DC1IP    
      "location" = var.Location1
    }
  
    deployment_mode = "Incremental"
    depends_on = [azurerm_template_deployment.promotedc1]    
  }  

    resource "azurerm_template_deployment" "restartdc1" {
    name                = "RestartDC1"
    resource_group_name = azurerm_resource_group.rg1.name

    template_body = file("nestedtemplates/restartvm.json")
  
    parameters = {
      "computerName" = local.DC1Name
      "location" = var.Location1
    }
  
    deployment_mode = "Incremental"
    depends_on = [azurerm_template_deployment.updatevnet1dns]    
  }  

    resource "azurerm_template_deployment" "configdns" {
    name                = "ConfigDNS"
    resource_group_name = azurerm_resource_group.rg1.name

    template_body = file("nestedtemplates/configdns.json")
  
    parameters = {
      "computerName" = local.DC1Name
      "DomainName" = local.DomainName      
      "ReverseLookup1" = var.ReverseLookup1
      "dc1lastoctet" = var.DC1LastOctet                        
      "location" = var.Location1
    }
  
    deployment_mode = "Incremental"
    depends_on = [azurerm_template_deployment.restartdc1]    
  }

    resource "azurerm_template_deployment" "createouous" {
    name                = "CreateOUs"
    resource_group_name = azurerm_resource_group.rg1.name

    template_body = file("nestedtemplates/createous.json")
  
    parameters = {
      "computerName" = local.DC1Name
      "BaseDN" = local.BaseDN    
      "location" = var.Location1
    }
  
    deployment_mode = "Incremental"
    depends_on = [azurerm_template_deployment.configdns]    
  }    

    resource "azurerm_template_deployment" "deploywk1vm" {
    name                = "DeployWK1VM"
    resource_group_name = azurerm_resource_group.rg1.name

    template_body = file("nestedtemplates/1nic-1disk-vm.json")
  
    parameters = {
      "computerName" = local.WK1Name
      "computerIP" = local.WK1IP            
      "Publisher" = "MicrosoftWindowsDesktop"
      "Offer" = "Windows-10"      
      "OSVersion" = var.WK1OSVersion
      "licenseType" = var.WindowsClientLicenseType      
      "VMSize" = var.WK1VMSize
      "vnetName" = local.Vnet1Name
      "subnetName" = local.Vnet1Subnet2Name
      "vnetprefix" = local.Vnet1Prefix
      "subnetPrefix" = local.Vnet1Subnet2Prefix
      "adminUsername" = var.adminUsername
      "adminPassword" = var.adminPassword      
      "location" = var.Location1                
    }
  
    deployment_mode = "Incremental"
    depends_on = [azurerm_template_deployment.restartdc1]
  }

    resource "azurerm_template_deployment" "domainjoinwk1vm" {
    name                = "DomainJoinWK1VM"
    resource_group_name = azurerm_resource_group.rg1.name

    template_body = file("nestedtemplates/domainjoin.json")
  
    parameters = {
      "computerName" = local.WK1Name
      "DomainName" = local.DomainName            
      "OUPath" = local.WKOUPath            
      "domainJoinOptions" = 3
      "adminUsername" = var.adminUsername
      "adminPassword" = var.adminPassword      
      "location" = var.Location1                
    }
  
    deployment_mode = "Incremental"
    depends_on = [azurerm_template_deployment.deploywk1vm]
  }
