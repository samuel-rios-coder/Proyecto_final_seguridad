# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Proyecto 4 - Laboratorio IDS (Snort) sobre VMware + Vagrant
# ------------------------------------------------------------
# 3 VMs en una red privada aislada 10.10.10.0/24:
#   ids       10.10.10.10  -> Ubuntu + Snort (sensor en modo promiscuo)
#   victima   10.10.10.20  -> Ubuntu + SSH + DVWA (Docker)
#   atacante  10.10.10.30  -> Ubuntu + nmap, hydra, sqlmap
#
# Todas usan la box bento/ubuntu-22.04 (ya descargada para vmware_desktop),
# asi no hay que bajar Kali. El atacante trae las mismas herramientas.
#
# Uso:
#   vagrant up                 (levanta las 3; ver orden recomendado en README)
#   vagrant ssh ids
#   vagrant halt / vagrant destroy -f

BOX   = "bento/ubuntu-22.04"
NETID = "10.10.10"

# RAM ajustada a un host de 8 GB. Sube estos valores si tu equipo tiene mas.
MEM = { "ids" => 1536, "victima" => 1024, "atacante" => 1024 }
CPU = { "ids" => 2,    "victima" => 1,    "atacante" => 1 }

NODES = [
  { name: "ids",      ip: "#{NETID}.10", script: "provision/ids.sh"      },
  { name: "victima",  ip: "#{NETID}.20", script: "provision/victim.sh"   },
  { name: "atacante", ip: "#{NETID}.30", script: "provision/attacker.sh" },
]

Vagrant.configure("2") do |config|
  config.vm.box = BOX
  # En un laboratorio aislado no necesitamos la carpeta compartida por defecto.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  NODES.each do |node|
    config.vm.define node[:name] do |vm|
      vm.vm.hostname = node[:name]

      # Red privada aislada (host-only vmnet que crea el plugin de VMware).
      vm.vm.network "private_network", ip: node[:ip]

      vm.vm.provider "vmware_desktop" do |v|
        v.vmx["memsize"]  = MEM[node[:name]].to_s
        v.vmx["numvcpus"] = CPU[node[:name]].to_s
        v.gui = false

        # El sensor IDS debe oir TODO el trafico de la red privada, no solo
        # el dirigido a su MAC. Permitimos modo promiscuo en su 2a tarjeta
        # (ethernet1 = la red privada; ethernet0 = NAT de Vagrant).
        # OJO: no usar linkStatePropagation en un adaptador host-only: ata el
        # enlace a una NIC fisica inexistente y deja la interfaz en NO-CARRIER.
        if node[:name] == "ids"
          v.vmx["ethernet1.noPromisc"] = "FALSE"
        end
      end

      # Copiamos reglas y scripts que usa cada rol.
      vm.vm.provision "file", source: "rules",   destination: "/tmp/lab-rules"
      vm.vm.provision "file", source: "scripts", destination: "/tmp/lab-scripts"

      vm.vm.provision "shell", path: node[:script], env: { "NETID" => NETID }
    end
  end
end
