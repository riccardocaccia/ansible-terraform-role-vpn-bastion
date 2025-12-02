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

# ---------------------------------
# Keypair
# ---------------------------------
resource "openstack_compute_keypair_v2" "bastion_key" {
  name       = "bastion-key"
  public_key = file("~/.ssh/authorized_keys")
}

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
