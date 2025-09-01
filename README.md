# cg-wafaas-azure-lab-backend
Cloud Guard WAFaaS Backend Deployment script

Workshop lab automation for deploying multiple API backends (VAmPI) and a shared attacker VM in Azure. Uses Terraform + cloud-init, reads a users file, creates per-user Linux accounts with sudo, enables password SSH login, and outputs credentials.

Quick start
- Prereqs: Azure subscription, `az` logged in, Terraform >= 1.3 installed.
- Edit `users.txt` with one name per line.
- Optionally edit `terraform.tfvars` (location, prefix, SSH CIDR).
- Run: `./scripts/deploy.sh` or `terraform -chdir=terraform init && terraform -chdir=terraform apply -auto-approve`.

Outputs
- `terraform/credentials.csv`: username, password, API VM IP/FQDN, attacker VM IP/FQDN.
- Terraform outputs also print summary info.

Notes
- API VMs run VAmPI in Docker and expose it on port 80.
- Attacker VM is Ubuntu with common tools (nmap, sqlmap, gobuster, ffuf, curl, httpie, jq, git, Docker). Swap to Kali by changing variables and accepting Marketplace terms.
- SSH password auth is enabled. Restrict access via `allowed_ssh_cidr`.
- Each API VM creates exactly one attendee user based on `users.txt`; the attacker VM creates all attendee users. All attendee users are added to `sudo` with NOPASSWD.
- Public DNS labels are set as `${prefix}-{username}.${region}.cloudapp.azure.com` for convenience.

Switching attacker VM to Kali
- Set `use_kali_attacker = true` in `terraform/terraform.tfvars`.
- Ensure your subscription has accepted the Kali Marketplace terms for the chosen region.

Security
- The generated `outputs/credentials.csv` contains passwords; handle and store securely.
- Prefer locking `allowed_ssh_cidr` to your Bastion/egress IP, not `0.0.0.0/0`.
