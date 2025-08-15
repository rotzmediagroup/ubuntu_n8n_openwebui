# n8n + Open WebUI — One-Shot Installer (Ubuntu 22.04 / 24.04)

Spin up **n8n** and **Open WebUI** on a fresh Ubuntu server in one shot.  
The script installs Docker, configures persistent storage, opens firewall ports (when UFW is active), and drops an updater script.

> ✅ Tested on **Ubuntu 22.04 (Jammy)** and **Ubuntu 24.04 (Noble)**  
> 🐳 Uses Docker + Docker Compose plugin  
> 🔁 Persistent volumes + restart policy  
> 🛡️ UFW ports opened automatically if UFW is active (5678, 8080)

---

## Quick Start

SSH into your **fresh** Ubuntu 22.04/24.04 server and run:

```bash
sudo bash -c 'curl -fsSL https://raw.githubusercontent.com/<your-user>/<your-repo>/main/install_n8n_openwebui.sh -o install_n8n_openwebui.sh && chmod +x install_n8n_openwebui.sh && ./install_n8n_openwebui.sh'
