# versions.tf
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.3"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://192.168.56.10:8006/"
  api_token = var.proxmox_api_token
  insecure  = true
  ssh { # this is for terraform itself to comms with the hypervisor
    agent    = false
    username = "root"
    password = var.proxmox_password
  }
}