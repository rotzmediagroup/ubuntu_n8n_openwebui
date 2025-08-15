# n8n + Open WebUI — One-Shot Installer (Ubuntu 22.04 / 24.04)

Spin up **n8n** and **Open WebUI** on a fresh Ubuntu server in one shot.  
The installer sets up Docker, creates persistent storage, opens firewall ports (if UFW is active), and places an updater script.

> ✅ Tested on **Ubuntu 22.04 (Jammy)** and **Ubuntu 24.04 (Noble)**  
> 🐳 Uses Docker + Docker Compose plugin  
> 🔁 Persistent volumes + restart policy  
> 🍪 Defaults to `N8N_SECURE_COOKIE=false` so HTTP works immediately on port **5678**  
> 🛡️ UFW ports opened automatically if active (**5678**, **8080**)  
> 🔐 Reverse-proxy (HTTPS) guides for **Caddy** and **Traefik** included

---

## Quick Start

SSH into your **fresh** Ubuntu 22.04/24.04 server and run:

```bash
sudo bash -c 'curl -fsSL https://raw.githubusercontent.com/rotzmediagroup/ubuntu_n8n_openwebui/main/install_n8n_openwebui.sh -o install_n8n_openwebui.sh && chmod +x install_n8n_openwebui.sh && ./install_n8n_openwebui.sh'
