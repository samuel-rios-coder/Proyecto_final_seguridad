#!/usr/bin/env bash
# Provisioning del ATACANTE: herramientas para probar el IDS
set -euo pipefail
echo "[atacante] === Provisioning atacante (nmap/hydra/sqlmap) ==="
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y nmap hydra sqlmap curl ettercap-text-only dos2unix

# --- Instalar scripts de prueba en el home de vagrant ---
mkdir -p /home/vagrant/lab
cp /tmp/lab-scripts/* /home/vagrant/lab/ 2>/dev/null || true
dos2unix /home/vagrant/lab/* 2>/dev/null || true
chmod +x /home/vagrant/lab/*.sh 2>/dev/null || true
chown -R vagrant:vagrant /home/vagrant/lab

# --- Lista corta de contrasenas para la demo de fuerza bruta ---
printf '123456\nadmin\nqwerty\nletmein\nroot\ntoor\npassword123\n' > /home/vagrant/lab/pass.txt
chown vagrant:vagrant /home/vagrant/lab/pass.txt

echo "[atacante] ================================================================"
echo "[atacante]  Scripts de prueba en:  /home/vagrant/lab/"
echo "[atacante]  Ejecuta:               cd lab && ./run-attacks.sh"
echo "[atacante] ================================================================"
