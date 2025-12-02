# Bastion Deployment with Terraform

These file can be used to define and deploy a Virtual Machine (VM) on OpenStack. This VM is configured to act as a Bastion Host (or jump host), serving as the single secure SSH entry point to access resources located in the private network.

---

## What this Terraform configuration files does

* Creates an OpenStack keypair for SSH access to the bastion host.
* Provisions a bastion VM in OpenStack with a `public and private NIC`.
* Generates an Ansible inventory file pointing to the bastion VM with the correct SSH key.
* Uses a `null_resource` with local-exec to wait for the VM to be reachable via SSH.
* Runs the Ansible playbook (site.yml) to configure the bastion host automatically.

---

## Repository layout

```
terraform_bastion/
       ├─ main.tf
       ├─ terraform.tfvars
       └─ variables.tf
```

---

## Requirements

* **Controller:** Terraform ≥ 1.14.0
* (Same as Ansible-requirements): 
* **Controller:** Ansible ≥ 2.15.
* **OIDC client:** `client_id` + `client_secret` registered at your Identity Provider (IdP)
* (Optional) SMTP credentials if you want code/URL by emai.

---

## 1) Main.tf file

Provider settings and terraform requirements:

> **Note:** Keystone login is needed in order to proceed, otherwise you can think to use OIDC login to access the OpenStack cloud enviroment

```hcl
# ---------------------------------
# Provider = OpenStack
# ---------------------------------
terraform {
  required_version = ">= 1.4.0"
  required_providers {
	openstack = {
	source  = "terraform-provider-openstack/openstack"
	version = "~> 1.53.0"
	}
  }
}

provider "openstack" {
  auth_url    = var.auth_url
  user_name   = var.user_name
  password    = var.password
  tenant_name = var.tenant_name
  region      = var.region
}
```
---

## 2) Key generation

You can set your preferred name for your key pair, also pay attention to the path and key location of your public key (here: ~/.ssh/authorized_keys):

  ```hcl
  # ---------------------------------
  # Keypair
  # ---------------------------------
  resource "openstack_compute_keypair_v2" "bastion_key" {
  name       = "bastion-key"
  public_key = file("~/.ssh/authorized_keys")
  }
  ```
---

## 3) Network definition

In the network configuration is important to assign a public and a private network access:

```hcl
# ---------------------------------
# Network
# ---------------------------------

# Private network
data "openstack_networking_network_v2" "private" {
  name = "private_net"
}
# subnet
data "openstack_networking_subnet_v2" "private_subnet" {
  network_id = data.openstack_networking_network_v2.private.id
}

# public network
data "openstack_networking_network_v2" "public" {
  name = "public_net"
}

```
---

## 4) VM Bastion

The VM is configururated as reported, here is importatnt to define your bastion name inside the field `name`:

```hcl
# ---------------------------------
# VM Bastion
# ---------------------------------
resource "openstack_compute_instance_v2" "bastion" {
  name            = "NAME-OF-YOUR-BASTION"
  flavor_name     = var.flavor
  image_name      = var.image
  key_pair        = openstack_compute_keypair_v2.bastion_key.name

  # NIC pubblica
  network {
    uuid = data.openstack_networking_network_v2.public.id
  }

  # NIC privata
  network {
    uuid = data.openstack_networking_network_v2.private.id
  }

  metadata = {
    ansible_user = "ubuntu"
  }
}
```
---

## 6) Ansible part

This section creates the inventory file dynamically and executes the Ansible playbook using `null_resource` and `local-exec`:

```hcl
# ---------------------------------
# Inventory per Ansible
# ---------------------------------
resource "local_file" "inventory" {
  filename = "/home/ubuntu/ansible-role-vpn-bastion/ansible-role/inventory"
  content  = <<EOF
[bastion]
bastion1 ansible_host=${openstack_compute_instance_v2.bastion.access_ip_v4} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/my_private
EOF
}

# ---------------------------------
# Provisioning Ansible
# ---------------------------------
resource "null_resource" "ansible_provision" {
  depends_on = [
    openstack_compute_instance_v2.bastion,
    local_file.inventory
  ]

  provisioner "local-exec" {
    working_dir = "/home/ubuntu/ansible-role-vpn-bastion/ansible-role"
    command     =  <<EOT
    # Wait VM to be reachable via SSH
until ssh -o StrictHostKeyChecking=no -i /home/ubuntu/.ssh/my_private ubuntu@${openstack_compute_instance_v2.bastion.access_ip_v4} "echo ok" 2>/dev/null; do
  echo "Waiting for SSH on ${openstack_compute_instance_v2.bastion.access_ip_v4}..."
  sleep 5
done 

ansible-playbook -i inventory site.yml
EOT
  }
}
```
---

# variables value

> **NOTE:** do not commit this file, it contains sensible data! 

  ```
  auth_url      = "AUTHENTICATOR-URL"
  user_name     = "NAME-OF-THE-USER"
  password      = "SUPER-SECRET-PASSWORD"
  tenant_name   = "TENANT OR PROJECT NAME"
  region        = "RegionOne"

  public_network = "public"
  flavor         = "DESIRED FLAVOUR"
  image          = "Ubuntu 22.04"
  ```

* The `im` user is created for automation (e.g. Terraform/IM). If you provided `jump_user_pubkey`, it will be authorized in `~im/.ssh/authorized_keys`.
* Re-running the playbook is **idempotent**.

---

## Troubleshooting

* Template errors (undefined vars):   Make sure group_vars/bastion.vault.yml contains client_id, client_secret, and—if email is enabled—smtp_password.
* Private key Required:   Before running, you must create your private key file at the location specified in the inventory: ~/.ssh/my_private
* Loop asking for “Password:”   Ensure the PAM line is present in /etc/pam.d/sshd. Verify that UsePAM yes, KbdInteractiveAuthentication yes, and ChallengeResponseAuthentication yes are set in /etc/ssh/sshd_config. Then restart SSH: sudo systemctl restart sshd.

---

## Safety

* Never commit real secrets. Keep group_vars/bastion.vault.yml encrypted and .vault_pass.txt out of version control (and in .gitignore).
* Test on a disposable VM before adopting in production.


