#!/usr/bin/env bash
# Provisioning de la VICTIMA: SSH (con password debil a proposito) + DVWA
set -euo pipefail
echo "[victima] === Provisioning victima (SSH + DVWA) ==="
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y openssh-server docker.io

# --- Usuario debil a proposito, para la demo de fuerza bruta SSH ---
if ! id labuser >/dev/null 2>&1; then
  useradd -m -s /bin/bash labuser
  echo "labuser:password123" | chpasswd
  echo "[victima] Usuario creado: labuser / password123"
fi

# --- Permitir autenticacion por contrasena (para que Hydra tenga sentido) ---
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh

# --- DVWA en Docker (puerto 80) ---
systemctl enable --now docker
if ! docker ps -a --format '{{.Names}}' | grep -q '^dvwa$'; then
  echo "[victima] Descargando y arrancando DVWA (puede tardar la primera vez)..."
  docker run -d --restart unless-stopped --name dvwa -p 80:80 vulnerables/web-dvwa
fi

echo "[victima] ================================================================"
echo "[victima]  SSH:  labuser@10.10.10.20  (pass: password123)"
echo "[victima]  DVWA: http://10.10.10.20/  (login admin/password)"
echo "[victima]  >> Primera vez: entra a DVWA, pulsa 'Create / Reset Database'"
echo "[victima]     y pon DVWA Security = Low."
echo "[victima] ================================================================"
