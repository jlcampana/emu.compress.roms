#!/usr/bin/env bash
# Instalador de emu-compress.
#
#   curl -fsSL https://raw.githubusercontent.com/jlcampana/emu.compress.roms/main/install.sh | bash
#
# Con opciones:
#
#   curl -fsSL .../install.sh | bash -s -- --with-dolphin --yes
#
# Todo el código está dentro de funciones y main se llama en la última línea:
# si la descarga se corta a medias, bash no ejecuta nada.

set -euo pipefail

REPO="jlcampana/emu.compress.roms"
REF="${EMU_COMPRESS_REF:-main}"
BIN_DIR="${EMU_COMPRESS_BIN_DIR:-$HOME/.local/bin}"
NAME="emu-compress"

WITH_DEPS=1
WITH_DOLPHIN=0
ASSUME_YES=0
UNINSTALL=0
FROM_REMOTE=0

if [[ -t 1 ]]; then
    C_B=$'\e[1m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_0=$'\e[0m'
else
    C_B=""; C_G=""; C_Y=""; C_R=""; C_0=""
fi

say()  { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Instalador de $NAME

Uso: install.sh [opciones]
     curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash -s -- [opciones]

Opciones:
  --bin-dir DIR    Carpeta de instalación (por defecto: ~/.local/bin)
  --system         Instala en /usr/local/bin (usa sudo)
  --no-deps        No instala paquetes del sistema; solo copia el script
  --with-dolphin   Instala también dolphin-tool (necesario para RVZ de GC/Wii):
                   Fedora: paquete dolphin-emu-tool; resto: Flatpak de Flathub
  --ref REF        Rama o etiqueta de GitHub a descargar (por defecto: main)
  --remote         Descarga el script de GitHub aunque haya una copia local
  --uninstall      Elimina $NAME de la carpeta de instalación
  -y, --yes        No pide confirmación
  -h, --help       Muestra esta ayuda

Variables de entorno: EMU_COMPRESS_REF, EMU_COMPRESS_BIN_DIR.

Distribuciones soportadas para instalar dependencias: Fedora (y derivadas
RHEL con EPEL), Ubuntu, Debian y derivadas. En otras se instala el script y
se indica qué falta.
EOF
}

parse_args() {
    while (( $# )); do
        case "$1" in
            --bin-dir)      [[ $# -ge 2 ]] || die "--bin-dir necesita un valor"
                            BIN_DIR=$2; shift 2 ;;
            --bin-dir=*)    BIN_DIR=${1#*=}; shift ;;
            --system)       BIN_DIR=/usr/local/bin; shift ;;
            --no-deps)      WITH_DEPS=0; shift ;;
            --with-dolphin) WITH_DOLPHIN=1; shift ;;
            --ref)          [[ $# -ge 2 ]] || die "--ref necesita un valor"
                            REF=$2; shift 2 ;;
            --ref=*)        REF=${1#*=}; shift ;;
            --remote)       FROM_REMOTE=1; shift ;;
            --uninstall)    UNINSTALL=1; shift ;;
            -y|--yes)       ASSUME_YES=1; shift ;;
            -h|--help)      usage; exit 0 ;;
            *)              die "opción desconocida: $1 (usa --help)" ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Privilegios y confirmación
# ---------------------------------------------------------------------------
SUDO=()
init_sudo() {
    if (( EUID == 0 )); then
        SUDO=()
    elif command -v sudo >/dev/null 2>&1; then
        SUDO=(sudo)
    else
        return 1
    fi
}

# Con "curl | bash" stdin es el propio script: se pregunta por /dev/tty.
confirm() {
    (( ASSUME_YES )) && return 0
    local answer
    if ! { : </dev/tty; } 2>/dev/null; then
        warn "sin terminal para preguntar; continúo (usa --yes para evitar este aviso)"
        return 0
    fi
    printf '%s [S/n] ' "$1" >/dev/tty
    read -r answer </dev/tty || answer=""
    [[ -z "$answer" || "$answer" =~ ^[sSyY] ]]
}

# ---------------------------------------------------------------------------
# Distribución y paquetes
# ---------------------------------------------------------------------------
OS_ID=""
OS_NAME=""
PKG=""   # dnf | apt | ""

detect_os() {
    local id="" like="" name=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        id=$(. /etc/os-release && printf '%s' "${ID:-}")
        like=$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")
        name=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-${NAME:-}}")
    fi
    OS_ID=$id
    OS_NAME=${name:-desconocido}
    case " $id $like " in
        *" fedora "*|*" rhel "*|*" centos "*)
            command -v dnf >/dev/null 2>&1 && PKG=dnf ;;
        *" debian "*|*" ubuntu "*)
            command -v apt-get >/dev/null 2>&1 && PKG=apt ;;
    esac
}

APT_UPDATED=0
apt_update_once() {
    (( APT_UPDATED )) && return 0
    say "  actualizando la lista de paquetes (apt-get update)..."
    "${SUDO[@]}" apt-get update -qq || warn "apt-get update falló; sigo con la lista actual"
    APT_UPDATED=1
}

pkg_available() {
    local p=$1
    case "$PKG" in
        dnf) dnf -q repoquery --latest-limit=1 "$p" 2>/dev/null | grep -q . ;;
        apt) apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}' \
                 | grep -qv -e '^(none)$' -e '^$' ;;
        *)   return 1 ;;
    esac
}

# Primer paquete disponible de la lista.
first_available() {
    local p
    for p in "$@"; do
        if pkg_available "$p"; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

pkg_install() {
    case "$PKG" in
        dnf) "${SUDO[@]}" dnf install -y "$@" ;;
        apt) "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive \
                 apt-get install -y --no-install-recommends "$@" ;;
    esac
}

have() { command -v "$1" >/dev/null 2>&1; }

have_7z() { have 7z || have 7za || have 7zr; }

have_dolphin() {
    have dolphin-tool && return 0
    have flatpak || return 1
    flatpak list --columns=application 2>/dev/null \
        | grep -Eqi '^org\.DolphinEmu\.dolphin-emu$|primehack'
}

install_deps() {
    step "Dependencias"
    say "  sistema: $OS_NAME"

    if [[ -z "$PKG" ]]; then
        warn "distribución no soportada para instalar paquetes automáticamente"
        case "$OS_ID" in
            steamos)
                warn "en SteamOS el sistema es de solo lectura; emu-compress usa las"
                warn "herramientas de EmuDeck (~/.config/EmuDeck/backend/tools/chdconv)" ;;
            arch|manjaro|endeavouros|cachyos)
                warn "prueba: sudo pacman -S mame-tools 7zip" ;;
        esac
        return 0
    fi

    if ! init_sudo; then
        warn "no eres root y no hay sudo; no puedo instalar paquetes"
        return 0
    fi

    [[ "$PKG" == apt ]] && apt_update_once

    local -a want=() missing=()
    local p
    if have chdman; then
        ok "chdman ya instalado"
    elif p=$(first_available mame-tools); then
        want+=("$p")
    else
        missing+=("chdman (paquete mame-tools)")
    fi

    if have_7z; then
        ok "7z ya instalado"
    elif p=$(first_available 7zip p7zip-full p7zip); then
        want+=("$p")
        [[ "$p" == p7zip && "$PKG" == dnf ]] && pkg_available p7zip-plugins \
            && want+=(p7zip-plugins)
    else
        missing+=("7z (paquete 7zip o p7zip)")
    fi

    if (( ${#want[@]} )); then
        say "  paquetes a instalar: ${want[*]}"
        if confirm "  ¿Instalar con ${PKG}?"; then
            if pkg_install "${want[@]}"; then
                ok "instalado: ${want[*]}"
            else
                warn "falló la instalación de: ${want[*]}"
            fi
        else
            warn "instalación de paquetes cancelada"
        fi
    fi

    for p in "${missing[@]}"; do
        warn "no encontrado en los repositorios: $p"
        [[ "$PKG" == apt ]] && warn "en Ubuntu puede hacer falta: sudo add-apt-repository universe"
        [[ "$PKG" == dnf && "$OS_ID" != fedora ]] && warn "en RHEL y derivadas puede hacer falta EPEL"
    done
    return 0
}

install_dolphin() {
    step "Dolphin (RVZ de GameCube/Wii)"
    if have_dolphin; then
        ok "dolphin-tool disponible"
        return 0
    fi
    if (( ! WITH_DOLPHIN )); then
        warn "no hay dolphin-tool: los RVZ de GC/Wii se omitirán"
        warn "vuelve a ejecutar el instalador con --with-dolphin para instalarlo"
        return 0
    fi

    if [[ "$PKG" == dnf ]] && init_sudo && pkg_available dolphin-emu-tool; then
        if confirm "  ¿Instalar dolphin-emu-tool con dnf?" \
            && pkg_install dolphin-emu-tool; then
            ok "dolphin-emu-tool instalado"
            return 0
        fi
        warn "no se pudo instalar dolphin-emu-tool; pruebo con Flatpak"
    fi

    if ! have flatpak; then
        warn "no hay flatpak; instálalo y ejecuta:"
        warn "flatpak install --user flathub org.DolphinEmu.dolphin-emu"
        return 0
    fi
    if confirm "  ¿Instalar Dolphin desde Flathub (Flatpak, solo para tu usuario)?"; then
        flatpak remote-add --user --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo || true
        if flatpak install --user -y --noninteractive flathub org.DolphinEmu.dolphin-emu; then
            ok "Dolphin Flatpak instalado"
        else
            warn "falló la instalación del Flatpak de Dolphin"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Script
# ---------------------------------------------------------------------------
TMP_DIR=""
cleanup() { [[ -n "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"; return 0; }

# Copia local si el instalador se ejecuta desde un clon del repositorio.
local_copy() {
    (( FROM_REMOTE )) && return 1
    local src=${BASH_SOURCE[0]:-}
    [[ -n "$src" && -f "$src" ]] || return 1
    local dir
    dir=$(cd -- "$(dirname -- "$src")" && pwd -P)
    [[ -f "$dir/$NAME" ]] || return 1
    printf '%s\n' "$dir/$NAME"
}

download() {
    local url=$1 out=$2
    if have curl; then
        curl -fsSL --retry 3 -o "$out" "$url"
    elif have wget; then
        wget -q -O "$out" "$url"
    else
        die "hace falta curl o wget para descargar $NAME"
    fi
}

# Ejecuta con sudo solo si la carpeta destino no es escribible.
as_needed() {
    local dir=$1; shift
    if [[ -w "$dir" ]] || { [[ ! -e "$dir" ]] && [[ -w "$(dirname -- "$dir")" ]]; }; then
        "$@"
    else
        init_sudo || die "no se puede escribir en $dir y no hay sudo"
        "${SUDO[@]}" "$@"
    fi
}

install_script() {
    step "Instalando $NAME en $BIN_DIR"
    local src
    if src=$(local_copy); then
        say "  origen: copia local $src"
    else
        TMP_DIR=$(mktemp -d)
        src="$TMP_DIR/$NAME"
        local url="https://raw.githubusercontent.com/$REPO/$REF/$NAME"
        say "  origen: $url"
        download "$url" "$src" || die "no se pudo descargar $url"
    fi

    head -n1 "$src" | grep -q '^#!.*bash' || die "el archivo descargado no parece $NAME"
    bash -n "$src" || die "el archivo descargado tiene errores de sintaxis"

    as_needed "$BIN_DIR" mkdir -p -- "$BIN_DIR"
    as_needed "$BIN_DIR" install -m 0755 -- "$src" "$BIN_DIR/$NAME"
    ok "$("$BIN_DIR/$NAME" --version 2>/dev/null || echo "$NAME") → $BIN_DIR/$NAME"

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *)
            warn "$BIN_DIR no está en tu PATH. Añade a ~/.bashrc:"
            warn "export PATH=\"$BIN_DIR:\$PATH\""
            ;;
    esac
}

uninstall() {
    step "Desinstalando $NAME"
    local target="$BIN_DIR/$NAME"
    if [[ -e "$target" ]]; then
        as_needed "$BIN_DIR" rm -f -- "$target"
        ok "eliminado $target"
    else
        warn "no existe $target (usa --bin-dir o --system si lo instalaste en otro sitio)"
    fi
    say "  Las dependencias (mame-tools, 7zip, Dolphin) no se desinstalan."
}

summary() {
    step "Herramientas"
    local emudeck="$HOME/.config/EmuDeck/backend/tools/chdconv"
    local t found
    for t in chdman 7z dolphin-tool cso 3dstool extract-xiso; do
        found=""
        case "$t" in
            7z)           have_7z && found="sí" ;;
            dolphin-tool) have_dolphin && found="sí" ;;
            chdman)       { have chdman || [[ -x "$emudeck/chdman5" ]]; } && found="sí" ;;
            cso)          { have maxcso || have ciso || [[ -x "$emudeck/ciso" ]]; } && found="sí" ;;
            *)            { have "$t" || [[ -x "$emudeck/$t" ]]; } && found="sí" ;;
        esac
        if [[ -n "$found" ]]; then
            [[ "$t" == cso ]] && ok "maxcso/ciso" || ok "$t"
        else
            case "$t" in
                chdman)       warn "$t: falta (necesario para CHD)" ;;
                7z)           warn "$t: falta (necesario para 7z)" ;;
                dolphin-tool) warn "$t: falta (RVZ de GC/Wii; usa --with-dolphin)" ;;
                cso)          warn "maxcso/ciso: falta (CSO de PSP; basta uno de los dos)" ;;
                3dstool)      warn "$t: falta (recorte de 3DS)" ;;
                extract-xiso) warn "$t: falta (XISO de Xbox)" ;;
            esac
        fi
    done
    say ""
    say "Las herramientas sin paquete (ciso, 3dstool, extract-xiso) se toman de"
    say "EmuDeck si está instalado ($emudeck)."
    say ""
    say "Prueba: ${C_B}cd /ruta/a/tus/roms && $NAME list${C_0}"
}

main() {
    parse_args "$@"
    trap cleanup EXIT
    if (( UNINSTALL )); then
        uninstall
        return 0
    fi
    detect_os
    if (( WITH_DEPS )); then
        install_deps
    fi
    install_script
    install_dolphin
    summary
}

main "$@"
