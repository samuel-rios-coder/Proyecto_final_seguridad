# Proyecto 4 — Laboratorio IDS (Snort) con Vagrant + VMware

Laboratorio **autocontenido y aislado** para montar y operar un IDS con Snort, con
simulación de ataques (Nmap / Hydra / sqlmap) para verificar la detección.

> ⚠️ **Uso exclusivo de laboratorio.** La red `10.10.10.0/24` es privada y no tiene
> salida a Internet ni a tu LAN. Nunca ejecutes estos ataques fuera de este entorno.

---

## 1. Arquitectura

El laboratorio reproduce un escenario real de monitoreo: un **sensor IDS** escuchando
en modo promiscuo todo el tráfico de un segmento de red, mientras un **atacante**
agrede a una **víctima**. En producción el IDS se conectaría a un puerto SPAN/mirror
de un switch o a un TAP; aquí el **modo promiscuo** del adaptador virtual cumple ese rol.

```
         Internet / apt / Docker
                   │  (solo para instalar; se puede desconectar en la demo)
            ┌──────┴──────┐  NAT (VMnet8)
            │             │
   ╔════════╧═══════╗ ╔═══╧════════════╗ ╔════════════════╗
   ║   ATACANTE     ║ ║    VÍCTIMA      ║ ║      IDS        ║
   ║   (Kali-like)  ║ ║  SSH + DVWA     ║ ║   Snort 2.9     ║
   ║                ║ ║                 ║ ║  (promiscuo)    ║
   ║  nmap/hydra/   ║ ║  Docker:DVWA    ║ ║  sniffa TODO    ║
   ║  sqlmap        ║ ║  :80  SSH:22    ║ ║  el segmento    ║
   ╚═══════╤════════╝ ╚════════╤════════╝ ╚════════╤════════╝
     eth1  │ .30         eth1  │ .20        eth1   │ .10
   ━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━  ← RED PRIVADA AISLADA
                         10.10.10.0/24                           (host-only, sin salida)
          ───────────▶ ataque ───────────▶
          .30  ─────── Nmap / Hydra / sqlmap ──────▶  .20
                              ⇡
                        .10 observa y alerta (promiscuo)
```

| VM         | Rol                        | IP (red privada) | RAM    |
|------------|----------------------------|------------------|--------|
| `ids`      | Snort (sensor, promiscuo)  | 10.10.10.10      | 1536 MB|
| `victima`  | SSH + DVWA (Docker)        | 10.10.10.20      | 1024 MB|
| `atacante` | nmap / hydra / sqlmap      | 10.10.10.30      | 1024 MB|

Las tres usan la box `bento/ubuntu-22.04`. Cada VM tiene **2 tarjetas de red**:

- **Adaptador 1 — NAT:** da salida a Internet solo para instalar paquetes (`apt`) y
  descargar la imagen de DVWA. No participa en los ataques.
- **Adaptador 2 — Red privada (host-only `10.10.10.0/24`):** el segmento aislado donde
  ocurre todo. No tiene salida a Internet ni a tu LAN, así el tráfico de ataque nunca
  se escapa del laboratorio.

### ¿Por qué modo promiscuo?

Un switch (físico o virtual) normalmente solo entrega a cada puerto las tramas
dirigidas a su MAC. Para que el IDS vea el tráfico **entre atacante y víctima** (del que
no es destinatario), su tarjeta debe estar en **modo promiscuo**. En este proyecto se
activa de dos formas combinadas:

1. En el `Vagrantfile`, con `v.vmx["ethernet1.noPromisc"] = "FALSE"` (permite el modo
   promiscuo en el adaptador del sensor).
2. En el SO invitado, con `ip link set eth1 promisc on`, que aplica el servicio
   `ids-sniff` creado durante el aprovisionamiento. También se desactiva el *offloading*
   de la NIC (`ethtool -K`) para que Snort vea los paquetes tal cual viajan.

> **Nota:** NO usar `linkStatePropagation` en un adaptador host-only: ata el enlace a una
> NIC física inexistente y deja la interfaz en `NO-CARRIER`.

---

## 2. Requisitos (ya los tienes en este equipo)

- Vagrant 2.4.9 + plugin `vagrant-vmware-desktop`
- VMware Workstation 17
- Box `bento/ubuntu-22.04`

> **Nota de memoria:** tu host tiene 8 GB. Las tres VMs suman ~3.6 GB. Si notas el
> equipo lento, levanta solo `ids` + `victima` + `atacante` cuando los necesites, o
> baja/sube la RAM en el `Vagrantfile` (mapa `MEM`).

---

## 3. Puesta en marcha

Desde esta carpeta (`Proyecto_final_seguridad`), en PowerShell:

```bash
vagrant up
```

La **primera vez** tarda (instala Snort, Docker, descarga la imagen DVWA, etc.).
Si tu equipo va justo de RAM, puedes levantarlas de a una:

```bash
vagrant up victima
```

```bash
vagrant up ids
```

```bash
vagrant up atacante
```

Comprobar estado:

```bash
vagrant status
```

---

## 4. Operación (el flujo de la demo)

Abre **tres** terminales de PowerShell en esta carpeta.

**Terminal 1 — sensor IDS (deja esto corriendo):**

```bash
vagrant ssh ids -c "sudo snort-lab"
```

Verás las alertas en pantalla en tiempo real. (Para guardarlas en archivo usa
`sudo snort-lab fast`, que escribe en `/var/log/snort/alert`.)

**Terminal 2 — preparar DVWA (solo la primera vez):**
Abre `http://10.10.10.20/` en tu navegador de Windows → login `admin` / `password`
→ botón **Create / Reset Database** → menú **DVWA Security = Low**.

**Terminal 3 — lanzar los ataques:**

```bash
vagrant ssh atacante -c "cd lab && ./run-attacks.sh"
```

Elige del menú:

| Opción | Ataque              | Regla que dispara        |
|--------|---------------------|--------------------------|
| 1      | Nmap SYN scan       | SCAN (sid 1000001/1000002)|
| 2      | Hydra SSH           | SSH  (sid 1000010/1000011)|
| 3      | sqlmap contra DVWA  | SQLi (sid 1000020-1000023)|
| 4      | SQLi manual (curl)  | SQLi                     |
| 5      | Ping                | ICMP (sid 1000030)       |

Para las opciones 3 y 4 necesitas tu `PHPSESSID` de DVWA (F12 → Aplicación →
Cookies). El script te lo pide.

Deberías ver en la Terminal 1 algo como:

```
[**] [1:1000001:1] LAB SCAN Posible escaneo TCP SYN (Nmap) [**] ... {TCP} 10.10.10.30:... -> 10.10.10.20:...
[**] [1:1000011:1] LAB SSH Banner de cliente repetido [**] ... {TCP} 10.10.10.30:... -> 10.10.10.20:22
[**] [1:1000023:1] LAB SQLi Herramienta sqlmap (User-Agent) [**] ...
```

---

## 5. Análisis de logs

Arranca el sensor en modo archivo y analiza:

```bash
vagrant ssh ids -c "sudo snort-lab fast"
```

(En otra terminal, tras lanzar ataques:)

```bash
vagrant ssh ids -c "sudo /tmp/lab-scripts/analyze.sh"
```

O a mano dentro de la VM: `sudo tail -f /var/log/snort/alert`.

---

## 6. Resolución de problemas

| Síntoma | Causa / solución |
|---|---|
| Snort no muestra alertas del tráfico atacante→víctima | La interfaz del IDS no está en promiscuo. El provisioning lo activa con el servicio `ids-sniff`. Verifica: `vagrant ssh ids -c "ip link show \| grep PROMISC"`. Como respaldo, en VMware: *VM ids → Settings → Network Adapter 2* debe estar en el mismo vmnet que las otras. |
| Confirmar que llega tráfico al sensor | `vagrant ssh ids -c "sudo tcpdump -ni any host 10.10.10.30"` mientras atacas. |
| DVWA no responde | `vagrant ssh victima -c "sudo docker ps"`; si no está, `sudo docker start dvwa`. |
| `vagrant up` falla por el plugin de VMware | Confirma el servicio: en PowerShell `Get-Service VagrantVMware`. |
| Reconstruir una VM desde cero | `vagrant destroy -f ids && vagrant up ids`. |

---

## 7. Apagar / limpiar

```bash
vagrant halt
```

```bash
vagrant destroy -f
```

---

## 8. Estructura del proyecto

```
Proyecto_final_seguridad/
├── Vagrantfile              # define las 3 VMs, red privada y promiscuo del IDS
├── provision/
│   ├── ids.sh               # instala y configura Snort + reglas + promiscuo
│   ├── victim.sh            # SSH (pass débil) + DVWA en Docker
│   └── attacker.sh          # nmap, hydra, sqlmap + scripts de prueba
├── rules/
│   └── local.rules          # reglas de detección (SCAN, SSH, SQLi, ICMP)
├── scripts/
│   ├── run-attacks.sh       # menú de ataques (se usa en 'atacante')
│   └── analyze.sh           # resumen del log (se usa en 'ids')
└── README.md
```

---

## 9. Relación con el Módulo 10 (para el informe)

Con el lab arriba puedes además capturar con Wireshark/tcpdump en la VM `ids`
(`sudo tcpdump -ni <if> -w captura.pcap`) y demostrar:

- **SSH vs. texto claro:** compara una sesión `ssh labuser@10.10.10.20` (ilegible)
  con Telnet/FTP (credenciales visibles con *Follow TCP Stream*).
- **Límite de TLS:** la SQLi se detecta en HTTP; si DVWA fuera HTTPS, las reglas
  `http_uri` no verían el payload (quedaría cifrado).
- **Firma digital / no repudio:** firma el reporte `/var/log/snort/alert` con GPG
  (`gpg --clearsign`) para garantizar su integridad.
```
