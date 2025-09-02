variable "prefix" {
  description = "Name prefix for all resources"
  type        = string
  default     = "wafaas-lab"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "westeurope"
}

variable "users_file" {
  description = "Path to text file with one user name per line"
  type        = string
  default     = "../users.txt"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH to VMs (use Bastion public egress or your IP). Use 0.0.0.0/0 for open."
  type        = string
  default     = "0.0.0.0/0"
}

variable "api_vm_size" {
  description = "VM size for API VMs"
  type        = string
  default     = "Standard_B1s"
}

variable "attacker_vm_size" {
  description = "VM size for attacker VM"
  type        = string
  default     = "Standard_B2s"
}

variable "use_kali_attacker" {
  description = "If true, use Kali marketplace image for attacker (will accept terms via scripts). Otherwise Ubuntu."
  type        = bool
  default     = false
}

variable "only_attacker" {
  description = "If true, deploy only the attacker VM and skip API VMs"
  type        = bool
  default     = false
}

variable "api_admin_username" {
  description = "Admin username for API VMs (not used by attendees)"
  type        = string
  default     = "labadmin"
}

variable "attacker_admin_username" {
  description = "Admin username for attacker VM (not used by attendees)"
  type        = string
  default     = "labadmin"
}
