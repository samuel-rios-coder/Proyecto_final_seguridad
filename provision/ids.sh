#!/usr/bin/env bash
# Provisioning del SENSOR IDS (Snort) - se ejecuta como root
set -uo pipefail
NETID="${NETID:-10.10.10}"
echo "[ids] === Provisioning sensor Snort para ${NETID}.0/24 ==="

# --- Detectar la interfaz de la red privada de forma robusta ---
# 1) la que ya tenga una IP 10.10.10.x; 2) si no, la que NO tiene la ruta
#    por defecto (es decir, la que no es la NAT de Vagrant).
detect_labif() {
  local ifc
  ifc="$(ip -o -4 addr show | awk -v net="${NETID}." '$4 ~ net {print $2; exit}')"
  if [ -z "$ifc" ]; then
    local defif
    defif="$(ip route show default | awk '{print $5; exit}')"
    ifc="$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|ens|enp)' | grep -v "^${defif}$" | head -n1)"
  fi
  echo "$ifc"
}

LABIF="$(detect_labif)"
# Esperar hasta ~30s a que la interfaz suba con su IP (netplan puede tardar).
for i in $(seq 1 15); do
  if [ -n "$LABIF" ] && ip -4 addr show "$LABIF" 2>/dev/null | grep -q "${NETID}."; then
    break
  fi
  [ -n "$LABIF" ] && ip link set "$LABIF" up 2>/dev/null || true
  netplan apply 2>/dev/null || true
  sleep 2
  LABIF="$(detect_labif)"
done
echo "[ids] Interfaz de laboratorio detectada: '${LABIF}'"
if [ -z "$LABIF" ]; then
  echo "[ids] AVISO: no se detecto la interfaz de la red privada. Continuo igual;"
  echo "[ids]        revisa que eth1 tenga carrier (ver README, seccion troubleshooting)."
  LABIF="eth1"   # valor por defecto para no dejar comandos vacios
fi

# --- Instalar Snort sin preguntas ---
export DEBIAN_FRONTEND=noninteractive
echo "snort snort/interface string ${LABIF}"          | debconf-set-selections
echo "snort snort/address_range string ${NETID}.0/24" | debconf-set-selections
apt-get update -y
apt-get install -y snort ethtool tcpdump

# --- Configurar snort.conf ---
CONF=/etc/snort/snort.conf
cp -n "${CONF}" "${CONF}.bak"
sed -i "s|^ipvar HOME_NET .*|ipvar HOME_NET ${NETID}.0/24|"        "${CONF}"
sed -i "s|^ipvar EXTERNAL_NET .*|ipvar EXTERNAL_NET any|"          "${CONF}"
sed -i 's|^include \$RULE_PATH|#include $RULE_PATH|'               "${CONF}"
sed -i 's|^#\s*include \$RULE_PATH/local.rules|include $RULE_PATH/local.rules|' "${CONF}"

# --- Instalar nuestras reglas ---
install -m 644 /tmp/lab-rules/local.rules /etc/snort/rules/local.rules

# --- Guardar interfaz/red tambien para el servicio ---
if [ -f /etc/snort/snort.debian.conf ]; then
  sed -i "s|^DEBIAN_SNORT_INTERFACE=.*|DEBIAN_SNORT_INTERFACE=\"${LABIF}\"|"   /etc/snort/snort.debian.conf
  sed -i "s|^DEBIAN_SNORT_HOME_NET=.*|DEBIAN_SNORT_HOME_NET=\"${NETID}.0/24\"|" /etc/snort/snort.debian.conf
fi

# --- Lanzador 'snort-lab' (se crea SIEMPRE, antes que nada mas) ---
cat > /usr/local/bin/snort-lab <<EOF
#!/usr/bin/env bash
# Arranca Snort en consola sobre la interfaz del laboratorio.
#   snort-lab          -> alertas en pantalla (consola)
#   snort-lab fast     -> alertas a /var/log/snort/alert (modo 'fast')
IF="\${IDS_IF:-${LABIF}}"
MODE="\${1:-console}"
if [ ! -d /sys/class/net/"\$IF" ]; then
  echo "La interfaz '\$IF' no existe. Interfaces disponibles:"; ip -br link
  echo "Usa:  sudo IDS_IF=<interfaz> snort-lab"; exit 1
fi
ip link set "\$IF" promisc on 2>/dev/null || true
if [ "\$MODE" = "fast" ]; then
  exec snort -A fast -q -u snort -g snort -c /etc/snort/snort.conf -i "\$IF" -l /var/log/snort
else
  exec snort -A console -q -u snort -g snort -c /etc/snort/snort.conf -i "\$IF"
fi
EOF
chmod +x /usr/local/bin/snort-lab

# --- Servicio: promiscuo + sin offloading (no debe abortar el provisioning) ---
cat > /etc/systemd/system/ids-sniff.service <<EOF
[Unit]
Description=Pone la interfaz del IDS en modo promiscuo y desactiva offloading
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '/sbin/ip link set ${LABIF} promisc on || true'
ExecStart=/bin/sh -c '/sbin/ethtool -K ${LABIF} gro off lro off tso off gso off || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable ids-sniff.service || true
systemctl start  ids-sniff.service || true

# --- Validar configuracion (sin abortar si falla) ---
echo "[ids] Validando configuracion de Snort..."
if snort -T -c "${CONF}" -i "${LABIF}"; then
  echo "[ids] Configuracion valida."
else
  echo "[ids] AVISO: la validacion devolvio error (revisa la interfaz)."
fi

echo "[ids] ================================================================"
echo "[ids]  Lanzador instalado: sudo snort-lab   (interfaz: ${LABIF})"
echo "[ids]  Logs (modo fast):   /var/log/snort/alert"
echo "[ids] ================================================================"
