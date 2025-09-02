# cg-wafaas-azure-lab-backend
Cloud Guard WAFaaS Backend Deployment script

Workshop lab automation for deploying multiple API backends (VAmPI) and a shared attacker VM in Azure. Uses Terraform + cloud-init, reads a users file, creates per-user Linux accounts with sudo, enables password SSH login, and outputs credentials.

Quick start
- Prereqs: Azure subscription, `az` logged in, Terraform >= 1.3 installed.
- Edit `users.txt` with one name per line.
- Optionally edit `terraform.tfvars` (location, prefix, SSH CIDR).
- Linux/macOS: run `./scripts/deploy.sh`.
- Windows (PowerShell): run `powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1`.
- Terraform binary resolution: both scripts honor `TERRAFORM_EXE` env var; otherwise they use `terraform` from PATH; if neither is found, they prompt for the full path interactively.
- If you have multiple Azure subscriptions or no default is set, pass your subscription explicitly: `powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1 -Subscription "<subscription id or exact name>"`.

Only deploy the attacker VM
- Use `-onlyattacker` to deploy only the shared attacker VM and skip all API VMs.
- Linux/macOS: `./scripts/deploy.sh -onlyattacker`
- Windows (PowerShell): `powershell -ExecutionPolicy Bypass -File .\\scripts\\deploy.ps1 -OnlyAttacker`
- Equivalent Terraform variable: `-var=only_attacker=true`

Tear down
- Destroy all assets and delete the resource group: `powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1 -Delete`
- Alternative (any OS): `terraform -chdir=terraform init && terraform -chdir=terraform apply -auto-approve`.

Outputs
- `terraform/credentials.csv`: username, password, API VM IP/FQDN, attacker VM IP/FQDN.
- Terraform outputs also print summary info.
  - When deploying with `-onlyattacker`, API fields in the CSV are left empty.

Notes
- API VMs run VAmPI in Docker and expose it on port 80.
- Attacker VM defaults to Ubuntu with a wide set of tools installed during provisioning (network, web, recon, wireless, reversing, fuzzing, forensics, etc.).
- You can opt into Kali by setting `use_kali_attacker = true`. The scripts will attempt to accept Kali Marketplace terms and deploy Kali where available; otherwise they will fall back to Ubuntu.
- SSH password auth is enabled. Restrict access via `allowed_ssh_cidr`.
- Each API VM creates exactly one attendee user based on `users.txt`; the attacker VM creates all attendee users. All attendee users are added to `sudo` with NOPASSWD.
- Public DNS labels are set as `${prefix}-{username}.${region}.cloudapp.azure.com` for convenience.
 - The PowerShell script validates prerequisites (Terraform >= 1.3, Azure CLI installed and logged in, and a non-empty `users.txt`) before applying.

Switching attacker VM OS
- Default is Ubuntu (`use_kali_attacker = false`).
- To use Kali, set `use_kali_attacker = true` in `terraform/terraform.tfvars`.

Attacker tools (preinstalled)
- Shell/dev/ops: tmux, zsh, fzf, ripgrep (rg), fd-find (fd), bat (batcat), jq, yq, htop, btop, lsof, strace, ltrace, git, python3, python3-pip, python3-venv, pipx, golang-go, rustc, cargo, build-essential, cmake, nasm, mingw-w64, upx-ucl, neovim, curl, wget, aria2, openssh-client, rsync, rclone, gnupg, age, hashdeep, bsdextrautils, pandoc.
- Containers: docker.io, docker-compose, docker-compose-plugin, podman.
- Network/Recon: socat, netcat-openbsd, openssl, nmap, theharvester, spiderfoot, recon-ng, rustscan, masscan, zmap, dnsrecon, dnsenum, nbtscan, smbclient, enum4linux, ldap-utils.
- Web App: burpsuite, zaproxy, mitmproxy, ffuf, feroxbuster, gobuster, wfuzz, sqlmap, nikto, wpscan, joomscan.
- Passwords/Wordlists: hashcat, john, hydra, medusa, seclists, wordlists, cewl, crunch, hashid, hashcat-utils.
- Protocol/Responder: python3-impacket, responder, samba, samba-common-bin.
- Wireless/BT/SDR: aircrack-ng, hcxdumptool, hcxpcapngtool, reaver, kismet, bluez, bettercap, btlejack, gnuradio, gqrx-sdr, rfcat.
- Capture/Analysis: wireshark, tshark, tcpdump.
- Mobile/RE: android-tools-adb, android-tools-fastboot, apktool, jadx, ideviceinstaller, libimobiledevice-utils, ghidra, radare2, cutter.
- Binary/Forensics/Fuzzing: binwalk, binutils, file, vim-common, patchelf, gdb, lldb, afl++, honggfuzz, radamsa, sleuthkit, autopsy, bulk-extractor, foremost, scalpel, plaso, yara.

Notes about tools
- Commands `fd` and `bat` are available via symlinks to `fdfind` and `batcat`.
- If a tool is missing from Ubuntu repositories, provisioning attempts alternate installs via pipx/go/cargo where applicable (e.g., theHarvester, SpiderFoot, Recon-ng, Wfuzz, ffuf, gobuster, bettercap, feroxbuster, rustscan).
- Installation is best-effort to keep deployment resilient; some tools may be skipped if not available in apt and no alternate method is configured.

Security
- The generated `outputs/credentials.csv` contains passwords; handle and store securely.
- Prefer locking `allowed_ssh_cidr` to your Bastion/egress IP, not `0.0.0.0/0`.
