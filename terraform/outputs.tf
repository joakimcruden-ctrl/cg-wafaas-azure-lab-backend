output "api_endpoints" {
  description = "API VM endpoints per user"
  value = { for u, pip in azurerm_public_ip.api : u => {
    ip   = try(azurerm_linux_virtual_machine.api[u].public_ip_address, null)
    fqdn = pip.fqdn
  } }
}

output "attacker_endpoint" {
  value = {
    ip   = azurerm_linux_virtual_machine.attacker.public_ip_address
    fqdn = azurerm_public_ip.attacker.fqdn
  }
}

output "credentials_file" {
  value = local_file.credentials.filename
}
