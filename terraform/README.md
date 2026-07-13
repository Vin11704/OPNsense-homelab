# Terraform setup: Documentation of steps and fixes
These are some of the procedures and decisions I made throughout my implementation of Terraform to create VMs in Proxmox. This is still a work in progress.

## Cloud-init Template
To clone a VM in proxmox, a cloud-init template is recommended to be used. The cloud-init template is a pre-configured VM image that allows for automated configuration of the VM during the cloning process. 

To adhere to best practices (separation of duties, least privilege), it is recommended to create a new role in Proxmox called `TerraformProv` with the following permissions:
`VM.Config.Cloudinit, Datastore.AllocateSpace, Datastore.Allocate, VM.Config.Options, VM.GuestAgent.Audit, VM.Clone, SDN.Use, VM.Config.CPU, VM.Config.HWType, VM.Allocate, VM.PowerMgmt, VM.Audit, Datastore.Audit, Sys.Audit, VM.Config.CDROM, VM.Config.Disk, VM.Config.Memory, VM.Config.Network`

Full steps of role and user creation:
```shell
# create user first
pveum user add terraform@pve 

# create role
pveum role add TerraformProv -privs "VM.Config.Cloudinit, Datastore.AllocateSpace, Datastore.Allocate, VM.Config.Options, VM.GuestAgent.Audit, VM.Clone, SDN.Use, VM.Config.CPU, VM.Config.HWType, VM.Allocate, VM.PowerMgmt, VM.Audit, Datastore.Audit, Sys.Audit, VM.Config.CDROM, VM.Config.Disk, VM.Config.Memory, VM.Config.Network"

# create ACL for the user and role
pveum aclmod / -user terraform@pve -role TerraformProv

# privsep=0 is required so the token directly inherits the users's full permissions set.
pveum user token add terraform@pve provider-token --privsep=0 
```

After that, create the cloud-init template in Proxmox:
```shell
# 1. Download Ubuntu 24.04 cloud image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# 2. Create the empty VM shell
qm create 9000 --name ubuntu-2404-cloudinit-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr1

# 3. Import the image as a disk into local-lvm
qm importdisk 9000 noble-server-cloudimg-amd64.img local-lvm

# 4. Attach the imported disk as scsi0
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0

# 5. Add the cloud-init drive (config injection point)
qm set 9000 --ide2 local-lvm:cloudinit

# 6. Set boot order
qm set 9000 --boot order=scsi0

# 7. Add serial console (cloud images are headless by default)
qm set 9000 --serial0 socket --vga serial0

# 8. Convert to template
qm template 9000
```
### Why vmbr1 (LAN) as bridge?
Because the cloud-init template will be used to create VMs that will be connected to the LAN network. Using vmbr1 as the bridge ensures that the cloned VM's DHCP and network security settings are assigned by OPNsense located in the same LAN network.

### Why scsi0 first as boot order?
We do not want the first boot to be ide2 or other drives, as the cloud-init drive is only used for configuration injection. The first boot should be from the main disk (scsi0) to ensure that the VM boots properly. The serial0 and vga command are used to enable the serial console for the VM, else we cannot even access the VM. 



## Terraform 
The files used include:
- main.tf -- This file contains the main Terraform setup, including provider configurations, resource definitions, cloud configurations and SSH key generation.
- terraform.tfvars -- This file contains the sensitive variable values for Terraform. **DO NOT FORGET** to include this in .gitignore.
- variables.tf -- This file contains the variable definitions for Terraform, including variable types, default values, and descriptions.
- versions.tf -- This file contains the required Terraform version and provider versions.

Run `terraform init` to initialize the Terraform working directory and download the required provider plugins. Then run `terraform plan` to see the execution plan and verify that the configuration is correct. Finally, run `terraform apply` to create the resources defined in the configuration files. 

To destroy the resources created by Terraform, run `terraform destroy`. This will remove all resources defined in the configuration files.


`terraform init` --> `terraform plan` --> `terraform apply` --> `terraform destroy`

## Strong Reminders
There are some things that are important to remember when cloning VMs in proxmox with Terraform:
- ALWAYS ensure that OPNsense is powered on before running `terraform apply`. If OPNsense is not powered on, the Terraform apply will fail (stuck at creation of the VM).
- If you are using a custom cloud-init template, ensure that the template is properly configured and available in Proxmox. If the template is not available, Terraform will fail to create the VM.
- Ensure the permissions of the newly created TerraformProv role are correctly set.
- After cloning is complete, check if package downloaded:
`dpkg -l qemu-guest-agent`




