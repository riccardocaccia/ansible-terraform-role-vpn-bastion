# ---------------------------------
# Provider = OpenStack
# ---------------------------------
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
  public_key = file("~/.ssh/id_ed25519.pub")
}

# ---------------------------------
# Network
# ---------------------------------

# private network
resource "openstack_networking_network_v2" "private" {
  name = "bastion-private"
}

resource "openstack_networking_subnet_v2" "private_subnet" {
  name       = "bastion-private-subnet"
  network_id = openstack_networking_network_v2.private.id
  cidr       = "10.20.0.0/24"
  ip_version = 4
}

# Public network
data "openstack_networking_network_v2" "public" {
  name = var.public_network
}

# ---------------------------------
# VM Bastion
# ---------------------------------
resource "openstack_compute_instance_v2" "bastion" {
  name            = "vpn-bastion"
  flavor_name     = var.flavor
  image_name      = var.image
  key_pair        = openstack_compute_keypair_v2.bastion_key.name

  # NIC pubblica
  network {
    uuid = data.openstack_networking_network_v2.public.id
  }

  # NIC privata
  network {
    uuid = openstack_networking_network_v2.private.id
  }

  metadata = {
    ansible_user = "ubuntu"
  }
}

# ---------------------------------
# Inventory per Ansible
# ---------------------------------
resource "local_file" "inventory" {
  filename = "${path.module}/../ansible-role-vpn-bastion/inventory"
  content  = <<EOF
[bastion]
bastion1 ansible_host=${openstack_compute_instance_v2.bastion.access_ip_v4} ansible_user=ubuntu
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
    command = <<EOF
cd ../ansible-role-vpn-bastion && ansible-playbook -i inventory site.yml
EOF
  }
}
