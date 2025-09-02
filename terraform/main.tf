resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = local.address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "api" {
  name                 = "api-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.api_subnet]
}

resource "azurerm_network_security_group" "api_nsg" {
  name                = "${var.prefix}-api-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "api_assoc" {
  subnet_id                 = azurerm_subnet.api.id
  network_security_group_id = azurerm_network_security_group.api_nsg.id
}

# Attacker NSG (SSH only)
// Attacker shares the API subnet and NSG

# Admin passwords for VM provisioning (not exposed in outputs)
resource "random_password" "api_admin" {
  length  = 20
  special = true
}

resource "random_password" "attacker_admin" {
  length  = 20
  special = true
}

# Per-user passwords
resource "random_password" "user_pw" {
  for_each = toset(local.user_list)
  length   = 14
  special  = true
  # Exclude ':' and other problematic chars for chpasswd/useradd parsing
  override_special = "!@#$%^*()_+-=[]{}.,?"
}

# Public IPs for attacker and each API
resource "azurerm_public_ip" "attacker" {
  name                = "${var.prefix}-attacker-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
  domain_name_label   = substr("${local.prefix_label}-attacker", 0, 60)
}

resource "azurerm_public_ip" "api" {
  for_each            = var.only_attacker ? {} : { for u in local.user_list : u => u }
  name                = substr("${var.prefix}-api-${lookup(local.user_labels, each.key)}-pip", 0, 80)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
  domain_name_label   = substr("${local.prefix_label}-${lookup(local.user_labels, each.key)}", 0, 60)
}

resource "azurerm_network_interface" "attacker" {
  name                = "${var.prefix}-attacker-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.api.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.attacker.id
  }
}

resource "azurerm_network_interface" "api" {
  for_each            = azurerm_public_ip.api
  name                = substr("${var.prefix}-api-${lookup(local.user_labels, each.key)}-nic", 0, 80)
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.api.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.value.id
  }
}

data "azurerm_platform_image" "ubuntu" {
  location  = azurerm_resource_group.rg.location
  publisher = "Canonical"
  offer     = "0001-com-ubuntu-server-jammy"
  sku       = "22_04-lts"
}

// Note: Skip data source lookup for Kali to avoid plan-time failures if listings are empty for the region

# Cloud-init templates
locals {
  api_cloudinits = { for u in local.user_list : u => templatefile("${path.module}/templates/cloud-init-api.yaml.tftpl", {
    username = lookup(local.user_usernames, u)
    password = random_password.user_pw[u].result
  }) }

  attacker_cloudinit = templatefile("${path.module}/templates/cloud-init-attacker.yaml.tftpl", {
    users_block    = join("\n", [
      for u in local.user_list : join("\n", [
        "  - name: \"${lookup(local.user_usernames, u)}\"",
        "    groups: [sudo]",
        "    shell: /bin/bash",
        "    sudo: ALL=(ALL) NOPASSWD:ALL",
        "    lock_passwd: false"
      ])
    ])
    chpasswd_list   = join("\n", [for u in local.user_list : "    ${lookup(local.user_usernames, u)}:${random_password.user_pw[u].result}"])
    usernames_lines = join("\n", [for u in local.user_list : "${lookup(local.user_usernames, u)}"])
    user_pass_pairs = join("\n", [for u in local.user_list : "${lookup(local.user_usernames, u)}:${random_password.user_pw[u].result}"])
  })

  attacker_post_script = templatefile("${path.module}/templates/attacker-post.sh.tftpl", {
    user_pass_pairs      = join("\n", [for u in local.user_list : "${lookup(local.user_usernames, u)}:${random_password.user_pw[u].result}"])
    seed_script_content  = try(file("${path.module}/../seed-api-discovery.sh"), "")
  })
}

# Trigger to recreate attacker VM when cloud-init changes
resource "null_resource" "attacker_userdata" {
  triggers = {
    hash = sha1(local.attacker_cloudinit)
  }
}

resource "azurerm_linux_virtual_machine" "attacker" {
  name                = "${var.prefix}-attacker"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.attacker_vm_size
  admin_username      = var.attacker_admin_username
  admin_password      = random_password.attacker_admin.result
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.attacker.id]

  source_image_reference {
    publisher = var.use_kali_attacker ? "kali-linux" : data.azurerm_platform_image.ubuntu.publisher
    offer     = var.use_kali_attacker ? "kali"       : data.azurerm_platform_image.ubuntu.offer
    sku       = var.use_kali_attacker ? "kali"       : data.azurerm_platform_image.ubuntu.sku
    version   = "latest"
  }

  dynamic "plan" {
    for_each = var.use_kali_attacker ? [1] : []
    content {
      name      = "kali"
      product   = "kali"
      publisher = "kali-linux"
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "${var.prefix}-attacker-osdisk"
  }

  computer_name  = "attacker"
  custom_data    = base64encode(local.attacker_cloudinit)

  lifecycle {
    replace_triggered_by = [
      null_resource.attacker_userdata
    ]
  }
}

# Post-provision hardening: ensure attendee users exist, sshd allows passwords, and seed script is present
resource "azurerm_virtual_machine_extension" "attacker_post" {
  name                       = "${var.prefix}-attacker-post"
  virtual_machine_id         = azurerm_linux_virtual_machine.attacker.id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = format(
      "bash -lc 'cat >/tmp/attacker-post.sh <<\"EOF\"\n%s\nEOF\nsed -i \"s/\\r$//\" /tmp/attacker-post.sh\nchmod 0755 /tmp/attacker-post.sh\nbash /tmp/attacker-post.sh'",
      replace(local.attacker_post_script, "'", "'\"'\"'")
    )
  })

  depends_on = [azurerm_linux_virtual_machine.attacker]
}

resource "azurerm_linux_virtual_machine" "api" {
  for_each                   = azurerm_network_interface.api
  name                       = substr("${var.prefix}-api-${lookup(local.user_labels, each.key)}", 0, 64)
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  size                       = var.api_vm_size
  admin_username             = var.api_admin_username
  admin_password             = random_password.api_admin.result
  disable_password_authentication = false

  network_interface_ids = [each.value.id]

  source_image_reference {
    publisher = data.azurerm_platform_image.ubuntu.publisher
    offer     = data.azurerm_platform_image.ubuntu.offer
    sku       = data.azurerm_platform_image.ubuntu.sku
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = substr("${var.prefix}-api-${lookup(local.user_labels, each.key)}-osdisk", 0, 80)
  }

  computer_name = substr("api-${lookup(local.user_labels, each.key)}", 0, 63)
  custom_data   = base64encode(local.api_cloudinits[each.key])
}

# Credentials output file
resource "local_file" "credentials" {
  filename = "${path.module}/credentials.csv"
  content  = join("\n", concat([
    "username,password,api_vm_ip,api_vm_fqdn,attacker_vm_ip,attacker_vm_fqdn"
  ], [for u in local.user_list : join(",", [
    lookup(local.user_usernames, u),
    random_password.user_pw[u].result,
    var.only_attacker ? "" : try(azurerm_linux_virtual_machine.api[u].public_ip_address, ""),
    var.only_attacker ? "" : try(azurerm_public_ip.api[u].fqdn, ""),
    azurerm_linux_virtual_machine.attacker.public_ip_address,
    azurerm_public_ip.attacker.fqdn
  ])]))
}
