resource "tls_private_key" "tf_test_clone" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "tf_test_clone_ssh_key" {
  filename        = "${path.module}/tf-test-clone_id_ed25519"
  content         = tls_private_key.tf_test_clone.private_key_openssh
  file_permission = "0600"
}

resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

    source_raw {
        data = <<-EOF
#cloud-config
hostname: tf-test-clone
package_update: true
packages:
  - qemu-guest-agent
users:
  - default
  - name: malv
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
      - ${trimspace(tls_private_key.tf_test_clone.public_key_openssh)}
    sudo: ALL=(ALL) NOPASSWD:ALL
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF
    file_name = "tf-test-clone-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "clone" {
    name = "tf-test-clone"
    node_name = "pve"
    vm_id = 110

    clone {
        vm_id = 9000
        full = true
    }

    agent {
        enabled = true
    }

    cpu {
        cores = 2
    }

    memory{
        dedicated = 2048
    }

    network_device {
        bridge = "vmbr1"
    }

    initialization {
        datastore_id = "local-lvm"

        user_data_file_id = proxmox_virtual_environment_file.cloud_config.id

        ip_config {
          ipv4 {
            address = "dhcp"
          }
        }

    }
}