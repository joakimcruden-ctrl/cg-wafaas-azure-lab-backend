locals {
  raw_users = split("\n", chomp(file(var.users_file)))
  user_list = [for u in local.raw_users : trimspace(u) if trimspace(u) != ""]

  # Sanitized prefix for DNS label usage: only [a-z0-9-], collapse dashes, trim edges, ensure starts with a letter, non-empty
  prefix_sanitized = regexreplace(
    regexreplace(
      regexreplace(lower(var.prefix), "[^a-z0-9-]", "-"),
      "-+", "-"
    ),
    "^-+|-+$", ""
  )
  prefix_label = length(local.prefix_sanitized) == 0 ? "a" : (can(regex("^[a-z].*", local.prefix_sanitized)) ? local.prefix_sanitized : "a${local.prefix_sanitized}")

  # Per-user sanitized labels: only [a-z0-9-], collapse dashes, trim edges, ensure non-empty, then cap length
  user_labels = {
    for u in local.user_list : u => (
      # Trim at 50 chars, then trim trailing dashes again if any
      regexreplace(
        substr(
          regexreplace(
            regexreplace(
              regexreplace(lower(u), "[^a-z0-9-]", "-"),
              "-+", "-"
            ),
            "^-+|-+$", ""
          ),
          0, 50
        ),
        "-+$", ""
      )
    )
  }

  # Replace any empty user label with a safe default
  user_labels = { for k, v in local.user_labels : k => (length(v) == 0 ? "user" : v) }

  address_space = ["10.10.0.0/16"]
  api_subnet    = "10.10.1.0/24"
}
