prefix           = "wafaas-lab"
location         = "westeurope"
users_file       = "../users.txt"
allowed_ssh_cidr = "0.0.0.0/0" # change to your IP or Bastion egress
api_vm_size      = "Standard_B1s"
attacker_vm_size = "Standard_B2s"
use_kali_attacker = true
