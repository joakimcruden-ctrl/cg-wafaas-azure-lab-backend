locals {
  raw_users = split("\n", chomp(file(var.users_file)))
  # Include only non-empty, non-comment lines (lines starting with '#')
  user_list = [for u in local.raw_users : trimspace(u) if trimspace(u) != "" && !startswith(trimspace(u), "#")]

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

  # Lowercase Linux usernames derived from real names (no capitals, no spaces/punct). Ensure not empty and not starting with a digit.
  digits = ["0","1","2","3","4","5","6","7","8","9"]
  user_usernames = {
    for u in local.user_list : u => (
      # sanitize by removing common separators and punctuation
      (length(
        substr(
          replace(
            replace(
              replace(
                replace(
                  replace(
                    replace(
                      replace(lower(u), " ", ""),
                      "_", ""
                    ),
                    ".", ""
                  ),
                  "/", ""
                ),
                "\\", ""
              ),
              "@", ""
            ),
            "+", ""
          ),
          0, 32
        )
      ) == 0
        ? "user"
        : (
          contains(local.digits, substr(
            substr(
              replace(
                replace(
                  replace(
                    replace(
                      replace(
                        replace(
                          replace(lower(u), " ", ""),
                          "_", ""
                        ),
                        ".", ""
                      ),
                      "/", ""
                    ),
                    "\\", ""
                  ),
                  "@", ""
                ),
                "+", ""
              ),
              0, 32
            ), 0, 1))
          ? format("u%s",
              substr(
                replace(
                  replace(
                    replace(
                      replace(
                        replace(
                          replace(
                            replace(lower(u), " ", ""),
                            "_", ""
                          ),
                          ".", ""
                        ),
                        "/", ""
                      ),
                      "\\", ""
                    ),
                    "@", ""
                  ),
                  "+", ""
                ),
                0, 31
              )
            )
          : substr(
              replace(
                replace(
                  replace(
                    replace(
                      replace(
                        replace(
                          replace(lower(u), " ", ""),
                          "_", ""
                        ),
                        ".", ""
                      ),
                      "/", ""
                    ),
                    "\\", ""
                  ),
                  "@", ""
                ),
                "+", ""
              ),
              0, 32
            )
        )
      )
    )
  }

  address_space = ["10.10.0.0/16"]
  api_subnet    = "10.10.1.0/24"
}
