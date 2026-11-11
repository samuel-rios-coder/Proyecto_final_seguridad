# Proyecto 4 — Laboratorio IDS (Snort) con Vagrant + VMware

Laboratorio **autocontenido y aislado** para montar y operar un IDS con Snort, con
simulación de ataques (Nmap / Hydra / sqlmap) para verificar la detección. Todo el
entorno se despliega con un solo `vagrant up`.

> ⚠️ **Uso exclusivo educativo y de laboratorio.** La red `10.10.10.0/24` es privada y
> no tiene salida a Internet ni a ninguna red real. Ejecutar estos ataques (Nmap, Hydra,
> sqlmap) contra sistemas de terceros sin autorización es ilegal. Úsese solo dentro de
> este entorno controlado.

---

## 1. Arquitectura

El laboratorio reproduce un escenario real de monitoreo: un **sensor IDS** escuchando
en modo promiscuo todo el tráfico de un segmento de red, mientras una máquina
**atacante** agrede a una **víctima**. En producción el IDS se conectaría a un puerto
SPAN/mirror de un switch o a un TAP de red; aquí el **modo promiscuo** del adaptador
virtual cumple ese rol.

```
         Internet / apt / Docker
                   │  (solo para instalar; se puede desconectar en la demo)
            ┌──────┴──────┐  NAT
            │             │
   ╔════════╧═══════╗ ╔═══╧════════════╗ ╔════════════════╗
   ║   ATACANTE     ║ ║    VÍCTIMA      ║ ║      IDS        ║
   ║                ║ ║  SSH + DVWA     ║ ║   Snort 2.9     ║
   ║  nmap/hydra/   ║ ║  Docker:DVWA    ║ ║  (promiscuo)    ║
   ║  sqlmap        ║ ║  :80  SSH:22    ║ ║  sniffa TODO    ║
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
  ocurre todo. No tiene salida a Internet ni a la LAN del anfitrión, así el tráfico de
  ataque nunca se escapa del laboratorio.

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

> **Nota técnica:** NO usar `linkStatePropagation` en un adaptador host-only: ata el
> enlace a una NIC física inexistente y deja la interfaz en `NO-CARRIER`.

---

## 2. Requisitos

- **Vagrant** 2.2 o superior
- **VMware Workstation / Fusion** + plugin [`vagrant-vmware-desktop`](https://developer.hashicorp.com/vagrant/docs/providers/vmware)
  (y el *VMware Utility* de Vagrant). También puede adaptarse a VirtualBox cambiando el
  provider en el `Vagrantfile`.
- Conexión a Internet en el primer arranque (para descargar la box y la imagen de DVWA).

> **Recursos:** las tres VMs suman ~3.6 GB de RAM. Se recomienda un anfitrión con al
> menos 8 GB. En equipos ajustados, pueden levantarse de a una, o ajustar la RAM de cada
> VM en el mapa `MEM` del `Vagrantfile`.

---

## 3. Puesta en marcha

Desde la carpeta del proyecto, en una terminal (PowerShell en Windows; `bash` en
Linux/macOS):

```bash
vagrant up
```

El **primer arranque** tarda (instala Snort, Docker y descarga la imagen de DVWA). En
equipos con poca RAM, pueden levantarse de a una:

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

## 4. Operación (flujo de la demo)

Se necesitan **tres** terminales abiertas en la carpeta del proyecto.

**Terminal 1 — sensor IDS (dejar corriendo):**

```bash
vagrant ssh ids -c "sudo snort-lab"
```

Muestra las alertas en pantalla en tiempo real. Para guardarlas en archivo, usar
`sudo snort-lab fast`, que escribe en `/var/log/snort/alert`.

**Terminal 2 — preparar DVWA (solo la primera vez):**

> La red del laboratorio está **aislada del anfitrión**, por lo que `http://10.10.10.20`
> no es accesible directamente desde el navegador del host. Hay dos formas de inicializar
> DVWA:
>
> - **Opción A (navegador):** añadir un reenvío de puerto en el `Vagrantfile` a la VM
>   `victima` —  `victima.vm.network "forwarded_port", guest: 80, host: 8080` — y tras
>   `vagrant reload victima`, abrir `http://localhost:8080`. Login `admin` / `password`
>   → **Create / Reset Database** → **DVWA Security = Low**.
> - **Opción B (desde la VM atacante):** inicializar la base de datos y obtener la cookie
>   de sesión con `curl` desde `atacante` (ver `scripts/` y la sección de SQLi).

**Terminal 3 — lanzar los ataques:**

```bash
vagrant ssh atacante -c "cd lab && ./run-attacks.sh"
```

Menú de ataques:

| Opción | Ataque              | Regla que dispara         |
|--------|---------------------|---------------------------|
| 1      | Nmap SYN scan       | SCAN (sid 1000001/1000002)|
| 2      | Hydra SSH           | SSH  (sid 1000010/1000011)|
| 3      | sqlmap contra DVWA  | SQLi (sid 1000020-1000023)|
| 4      | SQLi manual (curl)  | SQLi                      |
| 5      | Ping                | ICMP (sid 1000030)        |

Las opciones 3 y 4 piden el `PHPSESSID` de una sesión de DVWA (ver Opción A/B arriba).

En la Terminal 1 aparecerán alertas como:

```
[**] [1:1000002:1] LAB SCAN Nmap SYN con window 1024 [**] ... {TCP} 10.10.10.30:... -> 10.10.10.20:...
[**] [1:1000011:1] LAB SSH Banner de cliente repetido [**] ... {TCP} 10.10.10.30:... -> 10.10.10.20:22
[**] [1:1000023:1] LAB SQLi Herramienta sqlmap (User-Agent) [**] ...
```

---

## 5. Análisis de logs

Arrancar el sensor en modo archivo y analizar:

```bash
vagrant ssh ids -c "sudo snort-lab fast"
```

En otra terminal, tras lanzar ataques:

```bash
vagrant ssh ids -c "sudo /tmp/lab-scripts/analyze.sh"
```

O manualmente dentro de la VM: `sudo tail -f /var/log/snort/alert`.

---

## 6. Resolución de problemas

| Síntoma | Causa / solución |
|---|---|
| Snort no muestra alertas del tráfico atacante→víctima | La interfaz del IDS no está en promiscuo. El provisioning lo activa con el servicio `ids-sniff`. Verificar: `vagrant ssh ids -c "ip link show \| grep PROMISC"`. Como respaldo, en VMware: *VM ids → Settings → Network Adapter 2* debe estar en el mismo vmnet que las otras. |
| Confirmar que llega tráfico al sensor | `vagrant ssh ids -c "sudo tcpdump -ni any host 10.10.10.30"` durante un ataque. |
| DVWA no responde | `vagrant ssh victima -c "sudo docker ps"`; si no está, `sudo docker start dvwa`. |
| `eth1` en `NO-CARRIER` | No usar `linkStatePropagation` en el adaptador host-only (ver nota de Arquitectura). |
| `vagrant up` falla por el plugin de VMware | Verificar que el servicio del *VMware Utility* esté activo. |
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
│   ├── victim.sh            # SSH (contraseña débil de laboratorio) + DVWA en Docker
│   └── attacker.sh          # nmap, hydra, sqlmap + scripts de prueba
├── rules/
│   └── local.rules          # reglas de detección (SCAN, SSH, SQLi, ICMP)
├── scripts/
│   ├── run-attacks.sh       # menú de ataques (se ejecuta en 'atacante')
│   └── analyze.sh           # resumen del log (se ejecuta en 'ids')
├── .gitattributes           # fuerza LF para que los scripts funcionen al clonar
└── README.md
```

---

## 9. Relación con el Módulo 10 (Seguridad en la transmisión)

Con el laboratorio activo se puede capturar tráfico con Wireshark/tcpdump en la VM `ids`
(`sudo tcpdump -ni <if> -w captura.pcap`) para demostrar conceptos del módulo:

- **SSH vs. texto claro:** comparar una sesión `ssh labuser@10.10.10.20` (ilegible) con
  Telnet/FTP (credenciales visibles con *Follow TCP Stream*).
- **Límite de TLS:** la SQLi se detecta sobre HTTP; si DVWA usara HTTPS, las reglas
  `http_uri` no verían el payload (viajaría cifrado), ilustrando qué protege y qué no TLS.
- **Firma digital / no repudio:** firmar el reporte `/var/log/snort/alert` con GPG
  (`gpg --clearsign`) para garantizar su integridad y autenticidad.

---

## Licencia y aviso

Material educativo para la asignatura de Seguridad Informática. DVWA y las herramientas
incluidas son de sus respectivos autores. Este laboratorio se proporciona "tal cual",
con fines de aprendizaje sobre detección de intrusiones en un entorno aislado.
