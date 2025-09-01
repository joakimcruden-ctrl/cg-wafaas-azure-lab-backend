locals {
  raw_users = split("\n", chomp(file(var.users_file)))
  user_list = [for u in local.raw_users : trimspace(u) if trimspace(u) != ""]

  # Best-effort sanitized prefix for DNS label usage without regex functions
  prefix_label = substr(
    replace(
      replace(
        replace(lower(var.prefix), " ", "-"),
        "_", "-"
      ),
      ".", "-"
    ),
    0, 60
  )

  # Per-user sanitized labels without regex: replace common separators and punctuation
  user_labels = {
    for u in local.user_list : u => (
      substr(
        replace(
          replace(
            replace(
              replace(
                replace(
                  replace(
                    replace(lower(u), " ", "-"),
                    "_", "-"
                  ),
                  ".", "-"
                ),
                "/", "-"
              ),
              "\\", "-"
            ),
            "@", "-"
          ),
          "+", "-"
        ),
        0, 50
      )
    )
  }

  address_space = ["10.10.0.0/16"]
  api_subnet    = "10.10.1.0/24"
}
