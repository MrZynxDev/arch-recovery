#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=false
ASSUME_YES=false
SYSTEM_CONFIG=false
ERRORS=0
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/arch-recovery
LOG_FILE="$STATE_DIR/restore-$TIMESTAMP.log"
BACKUP_DIR="$STATE_DIR/backups/$TIMESTAMP"

usage() {
    cat <<'EOF'
Usage: ./restore.sh [options]

Options:
  --dry-run        Print planned actions without changing the system.
  --yes            Accept non-destructive prompts and package installation.
  --system-config  Offer carefully selected /etc configuration for restoration.
  --help           Show this help.

Hardware-specific boot, storage, GPU, hostname, UUID and interface configuration
is never restored automatically.
EOF
}

for argument in "$@"; do
    case "$argument" in
        --dry-run) DRY_RUN=true ;;
        --yes) ASSUME_YES=true ;;
        --system-config) SYSTEM_CONFIG=true ;;
        --help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$argument" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ $EUID -eq 0 ]]; then
    printf 'Run this script as a normal user. It invokes sudo only when needed.\n' >&2
    exit 1
fi

if [[ ! -f /etc/arch-release ]]; then
    printf 'This recovery kit supports Arch Linux only.\n' >&2
    exit 1
fi

if $DRY_RUN; then
    LOG_FILE=/tmp/arch-recovery-dry-run-$TIMESTAMP.log
else
    mkdir -p "$STATE_DIR" "$BACKUP_DIR"
fi
touch "$LOG_FILE"

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

warn() {
    log "WARNING: $*"
}

run() {
    log "+ $(printf '%q ' "$@")"
    if $DRY_RUN; then
        return 0
    fi
    set +e
    "$@" 2>&1 | tee -a "$LOG_FILE"
    local status=${PIPESTATUS[0]}
    set -e
    return "$status"
}

confirm() {
    local prompt=$1
    if $DRY_RUN || $ASSUME_YES; then
        log "$prompt [accepted]"
        return 0
    fi
    local answer
    read -r -p "$prompt [y/N] " answer
    [[ $answer =~ ^[Yy]$ ]]
}

read_package_file() {
    local file=$1
    local line
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -z $line || $line == \#* ]] && continue
        printf '%s\n' "$line"
    done < "$file"
}

check_internet() {
    log "Checking internet connectivity..."
    if command -v curl >/dev/null 2>&1; then
        run curl --fail --silent --show-error --head --max-time 15 https://archlinux.org/ >/dev/null
    elif command -v wget >/dev/null 2>&1; then
        run wget --spider --timeout=15 https://archlinux.org/ >/dev/null
    else
        run getent ahosts archlinux.org >/dev/null
    fi
}

install_official_packages() {
    local -a packages=()
    mapfile -t packages < <(
        {
            read_package_file "$ROOT_DIR/packages/official-portable.txt"
            read_package_file "$ROOT_DIR/packages/required-additions.txt"
        } | sort -u
    )
    ((${#packages[@]})) || return 0

    log "Official package count: ${#packages[@]}"
    if ! confirm "Update Arch and install official packages with sudo pacman?"; then
        warn "Official package installation skipped."
        return 0
    fi

    if ! run sudo pacman -Syu --needed --noconfirm "${packages[@]}"; then
        warn "Batch installation failed; retrying packages individually."
        local package
        for package in "${packages[@]}"; do
            if ! run sudo pacman -S --needed --noconfirm "$package"; then
                warn "Unable to install official package: $package"
                ((ERRORS += 1))
            fi
        done
    fi
}

bootstrap_yay() {
    command -v yay >/dev/null 2>&1 && return 0
    log "Yay is not installed; preparing an AUR bootstrap."
    if $DRY_RUN; then
        log "+ git clone https://aur.archlinux.org/yay.git <temporary-directory>/yay"
        log "+ makepkg -si --needed --noconfirm"
        return 0
    fi

    local temporary_directory
    temporary_directory=$(mktemp -d)
    if ! run git clone https://aur.archlinux.org/yay.git "$temporary_directory/yay"; then
        rm -rf "$temporary_directory"
        warn "Could not clone Yay. AUR packages will be skipped."
        return 1
    fi
    if ! (cd "$temporary_directory/yay" && run makepkg -si --needed --noconfirm); then
        rm -rf "$temporary_directory"
        warn "Could not build Yay. AUR packages will be skipped."
        return 1
    fi
    rm -rf "$temporary_directory"
}

install_aur_packages() {
    local -a packages=()
    mapfile -t packages < <(read_package_file "$ROOT_DIR/packages/aur-explicit.txt")
    ((${#packages[@]})) || return 0
    confirm "Bootstrap Yay if needed and install ${#packages[@]} AUR packages?" || return 0
    bootstrap_yay || return 0

    local package
    for package in "${packages[@]}"; do
        [[ $package == yay ]] && continue
        if ! run yay -S --needed --noconfirm "$package"; then
            warn "Unable to install AUR package: $package"
            ((ERRORS += 1))
        fi
    done
}

install_flatpaks() {
    local -a applications=()
    mapfile -t applications < <(read_package_file "$ROOT_DIR/packages/flatpak-apps.txt")
    ((${#applications[@]})) || return 0
    command -v flatpak >/dev/null 2>&1 || { warn "Flatpak is unavailable."; return 0; }
    confirm "Install ${#applications[@]} Flatpak applications?" || return 0

    if ! flatpak remotes --columns=name | grep -qx flathub; then
        run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
    fi
    local application
    for application in "${applications[@]}"; do
        run flatpak install -y --or-update flathub "$application" || {
            warn "Unable to install Flatpak application: $application"
            ((ERRORS += 1))
        }
    done
}

backup_existing() {
    local destination=$1
    [[ -e $destination || -L $destination ]] || return 0
    local relative=${destination#"$HOME"/}
    local backup="$BACKUP_DIR/$relative"
    run mkdir -p "$(dirname -- "$backup")"
    run cp -a -- "$destination" "$backup"
}

replace_home_placeholder() {
    local file=$1
    [[ -f $file ]] || return 0
    grep -Iq . "$file" 2>/dev/null || return 0
    grep -q '__HOME__' "$file" 2>/dev/null || return 0
    local escaped=${HOME//\\/\\\\}
    escaped=${escaped//&/\\&}
    escaped=${escaped//|/\\|}
    run sed -i "s|__HOME__|$escaped|g" "$file"
}

restore_tree() {
    local source_root=$1
    local destination_root=$2
    local source relative destination
    while IFS= read -r -d '' source; do
        relative=${source#"$source_root"/}
        destination="$destination_root/$relative"

        if [[ -f $source && -f $destination ]] && cmp -s "$source" "$destination"; then
            continue
        fi
        backup_existing "$destination"
        run mkdir -p "$(dirname -- "$destination")"
        run cp -a -- "$source" "$destination"
        $DRY_RUN || replace_home_placeholder "$destination"
    done < <(find "$source_root" \( -type f -o -type l \) -print0)
}

restore_user_files() {
    confirm "Restore selected dotfiles and scripts, backing up conflicts first?" || return 0
    restore_tree "$ROOT_DIR/dotfiles/home" "$HOME"
    restore_tree "$ROOT_DIR/assets/Pictures" "$HOME/Pictures"
    restore_tree "$ROOT_DIR/assets/icons" "$HOME/.icons"

    if [[ -d $HOME/.local/bin ]]; then
        run chmod u+x "$HOME/.local/bin/autoclicker-toggle" "$HOME/.local/bin/rightclick-start" "$HOME/.local/bin/rightclick-stop" || true
    fi
}

restore_vscode_extensions() {
    command -v code >/dev/null 2>&1 || return 0
    confirm "Install the recorded VS Code extensions?" || return 0
    local extension
    while IFS= read -r extension; do
        [[ -z $extension || $extension == \#* ]] && continue
        run code --install-extension "$extension" --force || {
            warn "Unable to install VS Code extension: $extension"
            ((ERRORS += 1))
        }
    done < "$ROOT_DIR/packages/vscode-extensions.txt"
}

enable_user_services() {
    confirm "Reload and enable the recorded user services?" || return 0
    run systemctl --user daemon-reload
    local unit
    while IFS= read -r unit; do
        [[ -z $unit || $unit == \#* ]] && continue
        if systemctl --user cat "$unit" >/dev/null 2>&1 || $DRY_RUN; then
            run systemctl --user enable --now "$unit" || warn "Could not enable user unit: $unit"
        else
            warn "User unit not available: $unit"
        fi
    done < "$ROOT_DIR/packages/user-services.txt"
}

install_system_file() {
    local relative=$1
    local mode=${2:-0644}
    local source="$ROOT_DIR/system-reference/$relative"
    local destination="/$relative"
    [[ -f $source ]] || { warn "Reference file missing: $relative"; return 0; }
    if [[ -e $destination ]] && cmp -s "$source" "$destination"; then
        return 0
    fi
    if [[ -e $destination ]]; then
        run sudo mkdir -p "/var/backups/arch-recovery-$TIMESTAMP$(dirname -- "$destination")"
        run sudo cp -a -- "$destination" "/var/backups/arch-recovery-$TIMESTAMP$destination"
    fi
    run sudo install -Dm"$mode" -- "$source" "$destination"
}

restore_system_configuration() {
    $SYSTEM_CONFIG || {
        log "System configuration was not requested. See system-reference/ and README.md."
        return 0
    }

    log "System configuration is reference material. Storage, boot, GPU, hostname and hardware files are never restored automatically."

    if confirm "Restore locale and virtual-console preferences?"; then
        install_system_file etc/locale.conf
        install_system_file etc/locale.gen
        install_system_file etc/vconsole.conf
        run sudo locale-gen || warn "locale-gen failed"
    fi

    if confirm "Restore portable zram-generator policy?"; then
        install_system_file etc/systemd/zram-generator.conf
    fi

    if confirm "Install the Nier Automata SDDM theme and select it?"; then
        local theme_source="$ROOT_DIR/system-reference/sddm-themes/nier-automata"
        local theme_destination=/usr/share/sddm/themes/nier-automata
        if [[ -e $theme_destination ]]; then
            run sudo cp -a -- "$theme_destination" "/var/backups/arch-recovery-$TIMESTAMP-nier-automata"
        fi
        run sudo mkdir -p "$theme_destination"
        run sudo cp -a -- "$theme_source/." "$theme_destination/"
        install_system_file etc/sddm.conf.d/theme.conf
    fi

    log "Network reference uses systemd-networkd + iwd and may conflict with NetworkManager."
    if confirm "Restore generic DHCP Ethernet/WLAN/WWAN networkd files?"; then
        install_system_file etc/systemd/network/20-ethernet.network
        install_system_file etc/systemd/network/20-wlan.network
        install_system_file etc/systemd/network/20-wwan.network
        if confirm "Enable systemd-networkd, resolved and iwd now?"; then
            run sudo systemctl enable --now systemd-networkd.service systemd-resolved.service iwd.service
            run sudo ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
        fi
    fi

    if confirm "Enable available non-network system services recorded by this kit?"; then
        local unit
        for unit in bluetooth.service cups.service docker.service sddm.service; do
            if systemctl cat "$unit" >/dev/null 2>&1 || $DRY_RUN; then
                run sudo systemctl enable --now "$unit" || warn "Could not enable system unit: $unit"
            else
                warn "System unit not available: $unit"
            fi
        done
    fi

    log "Not restored automatically: pacman.conf, mirrorlist, fstab, kernel cmdline, mkinitcpio files, GRUB customization, hostname, lm_sensors, ntsync module policy. Review and merge these manually."
}

main() {
    log "Arch Recovery restore started"
    log "Kit: $ROOT_DIR"
    log "Dry run: $DRY_RUN"
    log "Log: $LOG_FILE"

    check_internet || { warn "Internet connectivity check failed."; exit 1; }
    install_official_packages
    install_aur_packages
    install_flatpaks
    restore_user_files
    restore_vscode_extensions
    enable_user_services
    restore_system_configuration

    log "Restore finished with $ERRORS non-fatal error(s)."
    log "Review hardware/ and system-reference/ before configuring boot, storage, GPU or networking."
    log "Configure prayer location using ~/.config/environment.d/prayer.conf.example."
    ((ERRORS == 0))
}

main
