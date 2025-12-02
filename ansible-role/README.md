# Bastion Ansible (PAM OAuth2 Device Flow)

This playbook turns an **Ubuntu 22.04** VM into a **bastion** that accepts SSH logins via **OpenID Connect (device code flow)** using the [`pam_oauth2_device`](https://github.com/LuigiMansi1/pam_oauth2_device) module.

> **Note:** OpenVPN is **not** installed here; you can add it later in the same host.

> **Note:** A modified version of the module had been used, check [`pam_oauth2_device`](https://github.com/riccardocaccia/pam_oauth2_device)
---

## What this playbook does

* Builds and installs the `pam_oauth2_device` PAM module from your fork.
* Writes `/etc/pam_oauth2_device/config.json` for your chosen IdP.
* Adjusts **PAM** and **sshd** to use OIDC device flow for SSH logins.
* Ensures local UNIX accounts exist for your OIDC users (e.g. the `preferred_username`) and any extra service users (`im`).
* Optionally sends the device code URL via SMTP (disabled by default).
* Creates `~/.ssh/authorized_keys` for the `im` user if you provide a public key.

---

## Repository layout

```
inventory
site.yml
group_vars/
  ├─ bastion.yml           # public settings (non-secret)
  └─ bastion.vault.yml     # secrets (put in Ansible Vault)
templates/
  └─ pam_config.json.j2
.gitignore
```

---

## Requirements

* **Target host:** Ubuntu 22.04 VM reachable over SSH (user with sudo, e.g. `ubuntu`).
* **Controller:** Ansible ≥ 2.15.
* **OIDC client:** `client_id` + `client_secret` registered at your Identity Provider (IdP).
* (Optional) SMTP credentials if you want code/URL by email.

---

## 1) Set the inventory

Edit `inventory` and set your bastion’s public IP and SSH user:

```ini
[bastion]
bastion1 ansible_host=BASTION_PUBLIC_IP ansible_user=ubuntu
```

---

## 2) Choose the IdP and fill provider endpoints

Open `group_vars/bastion.yml`:

* Pick your provider:

  ```yaml
  idp_provider: "iam"   # or lifescience | egi
  ```
* IAM endpoints are prefilled. For other IdPs, replace the placeholders:

  ```yaml
  oidc_providers:
    iam:
      device_endpoint:   "https://iam.recas.ba.infn.it/devicecode"
      token_endpoint:    "https://iam.recas.ba.infn.it/token"
      userinfo_endpoint: "https://iam.recas.ba.infn.it/userinfo"
    lifescience:
      device_endpoint:   "FILL_ME"
      token_endpoint:    "FILL_ME"
      userinfo_endpoint: "FILL_ME"
    egi:
      device_endpoint:   "FILL_ME"
      token_endpoint:    "FILL_ME"
      userinfo_endpoint: "FILL_ME"
  ```
* Leave `username_attribute: "preferred_username"` unless your IdP uses a different claim.
* (Optional) Restrict access to specific IdP groups:

  ```yaml
  allowed_groups: ["group1", "group2"]   # empty list disables group checks
  ```

---

## 3) Put **secrets** into the Vault file

Edit `group_vars/bastion.vault.yml` and set:

```yaml
# OIDC client (confidential)
client_id: "YOUR_OIDC_CLIENT_ID"
client_secret: "YOUR_OIDC_CLIENT_SECRET"

# SMTP password (only if enable_email: true in bastion.yml)
smtp:
  smtp_password: "YOUR_SMTP_PASSWORD"

# Create local UNIX users before enabling PAM (must include the OIDC preferred_username)
preferred_username: "your_oidc_username"
extra_local_users:
  - "im"            # technical jump user (optional)
  # - "anotheruser" # add more if needed

# SSH public key for the 'im' user (optional)
jump_user_pubkey: "ssh-rsa AAAA... comment"
```

> The **`client_id`** is public but we keep it alongside the secret to keep all OIDC client fields in one place.

---

## 4) (Optional) enable email for device code/URL

In `group_vars/bastion.yml`:

```yaml
enable_email: true
smtp:
  smtp_server_url: "smtps://smtp.gmail.com:465"
  smtp_username: "your-smtp-user"
  # smtp_password goes in bastion.vault.yml
```

---

## 5) (Recommended) Encrypt secrets with **Ansible Vault**

Create a vault password file (kept **out** of git by `.gitignore`):

```bash
echo "your-strong-password" > .vault_pass.txt
chmod 600 .vault_pass.txt
```

Encrypt the secrets file:

```bash
ansible-vault encrypt group_vars/bastion.vault.yml --vault-password-file .vault_pass.txt
```

Edit or view later:

```bash
ansible-vault edit group_vars/bastion.vault.yml --vault-password-file .vault_pass.txt
ansible-vault view group_vars/bastion.vault.yml --vault-password-file .vault_pass.txt
```

---

## 6) Run the playbook

### Option A — **Vault encrypted** (recommended)

```bash
ansible-playbook -i inventory site.yml --vault-password-file .vault_pass.txt
# or interactively:
# ansible-playbook -i inventory site.yml --ask-vault-pass
```

### Option B — **Vault not encrypted** (for quick local tests only)

```bash
ansible-playbook -i inventory site.yml
```

---

## 7) First login test

From your client:

```bash
ssh -l YOUR_OIDC_USERNAME BASTION_PUBLIC_IP
```

* You’ll see a **device flow URL** and **user code**.
* Open the URL, authenticate with the chosen IdP, and **approve**.
* Return to the terminal and hit **Enter**. The SSH session should open.
* On first login, the role ensures `pam_mkhomedir` will create your home directory.

> You can also test locally on the bastion with:
>
> ```bash
> sudo apt-get install -y pamtester
> pamtester -v pamtester YOUR_OIDC_USERNAME authenticate
> ```

---

## Notes & tips

* The playbook removes `@include common-auth` from `/etc/pam.d/sshd` and inserts:

  ```
  auth sufficient pam_oauth2_device.so /etc/pam_oauth2_device/config.json
  ```

  so SSH logins go through OIDC device flow (and *don’t* fall back to local passwords).
* The `im` user is created for automation (e.g. Terraform/IM). If you provided `jump_user_pubkey`, it will be authorized in `~im/.ssh/authorized_keys`.
* Re-running the playbook is **idempotent**.

---

## Troubleshooting

* **Loop asking for “Password:”**
  Ensure the PAM line is present in `/etc/pam.d/sshd`, `UsePAM yes`, `KbdInteractiveAuthentication yes`, and `ChallengeResponseAuthentication yes` are set in `/etc/ssh/sshd_config`. Then restart SSH: `sudo systemctl restart sshd`.

* **Immediate disconnect after link shown:**
  Often caused by a missing local UNIX user. Make sure `preferred_username` (and any accounts you want to use) are listed in `group_vars/bastion.vault.yml`. Re-run the playbook.

* **Template errors (undefined vars):**
  Make sure `group_vars/bastion.vault.yml` contains `client_id`, `client_secret`, and—if email is enabled—`smtp_password`.

* **Private key Required:**
  before running you have to create a file here: `~/.ssh/MY_KEY`, with your private key and fill the following field in the inventory with the location of the key (ansible_ssh_private_key_file).

---

## Safety

* Never commit real secrets. Keep `group_vars/bastion.vault.yml` **encrypted** and **.vault\_pass.txt** out of version control (already in `.gitignore`).
* Test on a disposable VM before adopting in production.


