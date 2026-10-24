#!/usr/bin/env bash
# Setup inicial para Kali Linux recién instalado.
# Uso: sudo ./kali-setup.sh
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

info() { printf '\n\e[1;34m[*]\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m[+]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[!]\e[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Ejecuta este script con sudo: sudo $0" >&2
    exit 1
fi

# Usuario real (el que llamó a sudo) para configurar cosas en su $HOME
REAL_USER="${SUDO_USER:-root}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# ---------------------------------------------------------------------------
info "Actualizando el sistema (update + full-upgrade)"
apt-get update
apt-get "${APT_OPTS[@]}" full-upgrade
ok "Sistema actualizado"

# ---------------------------------------------------------------------------
info "Instalando paquetes básicos"
PACKAGES=(
    # Utilidades base
    curl wget git vim nano htop btop tree unzip zip p7zip-full
    tmux jq ripgrep fzf bat net-tools dnsutils
    ca-certificates gnupg apt-transport-https software-properties-common
    # Desarrollo
    build-essential gcc g++ make cmake gdb
    python3 python3-pip python3-venv pipx
    # Navegador y extras
    chromium flameshot terminator
    # Útiles para CTF
    seclists gobuster ffuf feroxbuster
    binwalk exiftool steghide hashcat john
    python3-pwntools ghidra
    # Pentesting web / red
    burpsuite zaproxy nmap masscan rustscan netcat-traditional socat
    sqlmap nikto whatweb wafw00f dirb dirsearch wfuzz
    hydra wpscan nuclei subfinder amass httpx-toolkit
    commix xsser mitmproxy wireshark
    # VPN
    wireguard wireguard-tools resolvconf
    # Pwn / Reversing
    radare2 checksec python3-ropgadget ropper ltrace strace patchelf
    ruby ruby-dev
    # Crypto (libs por apt porque Kali bloquea pip global, PEP 668)
    python3-pycryptodome python3-gmpy2 python3-z3 python3-sympy python3-requests
    python3-libnum
    # Forense / Stego
    foremost pngcheck sleuthkit stegseek volatility3 testdisk
)
# Si un nombre no existe apt aborta todo, así que se reintenta uno por uno
if ! apt-get "${APT_OPTS[@]}" install "${PACKAGES[@]}"; then
    warn "Instalación en bloque falló, reintentando paquete por paquete"
    FAILED=()
    for pkg in "${PACKAGES[@]}"; do
        apt-get "${APT_OPTS[@]}" install "$pkg" >/dev/null 2>&1 || FAILED+=("$pkg")
    done
    [[ ${#FAILED[@]} -gt 0 ]] && warn "No se pudieron instalar: ${FAILED[*]}"
fi
ok "Paquetes básicos instalados"

# ---------------------------------------------------------------------------
info "Instalando Visual Studio Code (repo oficial de Microsoft)"
if ! command -v code >/dev/null 2>&1; then
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg
    chmod 644 /etc/apt/keyrings/packages.microsoft.gpg
    echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        > /etc/apt/sources.list.d/vscode.list
    apt-get update
    apt-get "${APT_OPTS[@]}" install code
    ok "VS Code instalado"
else
    ok "VS Code ya estaba instalado"
fi

# ---------------------------------------------------------------------------
info "Instalando gems de Ruby (one_gadget, zsteg)"
gem install one_gadget zsteg && ok "Gems instaladas" || warn "Falló la instalación de gems"

# ---------------------------------------------------------------------------
info "Instalando pwndbg para $REAL_USER"
if [[ ! -d "$REAL_HOME/pwndbg" ]]; then
    sudo -u "$REAL_USER" git clone --depth 1 https://github.com/pwndbg/pwndbg "$REAL_HOME/pwndbg" \
        && (cd "$REAL_HOME/pwndbg" && sudo -u "$REAL_USER" ./setup.sh) \
        && ok "pwndbg instalado" || warn "Falló la instalación de pwndbg"
else
    ok "pwndbg ya estaba clonado en $REAL_HOME/pwndbg"
fi

# ---------------------------------------------------------------------------
info "Instalando RsaCtfTool en /opt/RsaCtfTool"
if [[ ! -d /opt/RsaCtfTool ]]; then
    git clone --depth 1 https://github.com/RsaCtfTool/RsaCtfTool /opt/RsaCtfTool \
        && python3 -m venv /opt/RsaCtfTool/venv \
        && /opt/RsaCtfTool/venv/bin/pip install /opt/RsaCtfTool \
        && ln -sf /opt/RsaCtfTool/venv/bin/RsaCtfTool /usr/local/bin/RsaCtfTool \
        && ok "RsaCtfTool instalado (comando: RsaCtfTool)" || warn "Falló la instalación de RsaCtfTool"
else
    ok "RsaCtfTool ya estaba instalado"
fi

# ---------------------------------------------------------------------------
info "Descargando CyberChef offline en /opt/cyberchef"
if [[ ! -d /opt/cyberchef ]]; then
    CC_URL="$(curl -fsSL https://api.github.com/repos/gchq/CyberChef/releases/latest \
        | jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url' | head -n1)"
    if [[ -n "$CC_URL" ]]; then
        mkdir -p /opt/cyberchef \
            && curl -fsSL "$CC_URL" -o /tmp/cyberchef.zip \
            && unzip -q /tmp/cyberchef.zip -d /opt/cyberchef \
            && ln -sf "$(ls /opt/cyberchef/CyberChef_*.html | head -n1)" /opt/cyberchef/cyberchef.html \
            && rm -f /tmp/cyberchef.zip \
            && ok "CyberChef listo: abre /opt/cyberchef/cyberchef.html" || warn "Falló la descarga de CyberChef"
    else
        warn "No se encontró el release de CyberChef"
    fi
else
    ok "CyberChef ya estaba en /opt/cyberchef"
fi

# ---------------------------------------------------------------------------
info "Descomprimiendo rockyou.txt"
if [[ -f /usr/share/wordlists/rockyou.txt.gz && ! -f /usr/share/wordlists/rockyou.txt ]]; then
    gunzip -k /usr/share/wordlists/rockyou.txt.gz && ok "rockyou.txt listo"
else
    ok "rockyou.txt ya estaba descomprimido (o no existe el .gz)"
fi

# ---------------------------------------------------------------------------
info "Limpiando paquetes innecesarios"
apt-get "${APT_OPTS[@]}" autoremove --purge
apt-get autoclean
ok "Limpieza completa"

# ---------------------------------------------------------------------------
if [[ -f /var/run/reboot-required ]]; then
    warn "Se requiere reiniciar para aplicar todos los cambios (kernel actualizado)."
fi
ok "Setup terminado para el usuario $REAL_USER ($REAL_HOME)"
