locals {
  raw_users   = split("\n", chomp(file(var.users_file)))
  user_list   = [for u in local.raw_users : trimspace(u) if trimspace(u) != ""]

  # sanitize for DNS label usage
  user_labels = { for u in local.user_list : u => substr(replace(lower(u), "[^a-z0-9-]", "-"), 0, 50) }

  address_space = ["10.10.0.0/16"]
  api_subnet    = "10.10.1.0/24"
}
