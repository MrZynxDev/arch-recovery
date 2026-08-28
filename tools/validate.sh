#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FAILED=false

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILED=true; }

if bash -n "$ROOT_DIR/restore.sh"; then
    pass 'restore.sh syntax'
else
    fail 'restore.sh syntax'
fi

required_paths=(
    packages/official-explicit.txt
    packages/official-portable.txt
    packages/aur-explicit.txt
    packages/flatpak-apps.txt
    packages/required-additions.txt
    packages/user-services.txt
    packages/vscode-extensions.txt
    dotfiles/home/.config/hypr/hyprland.lua
    dotfiles/home/.config/waybar/config.jsonc
    dotfiles/home/.config/theme/bin/apply-theme
    assets/Pictures/Wallpapers/7.jpg
    assets/icons/Bibata-Modern-Ice/index.theme
    assets/icons/BlackSur/index.theme
    system-reference/etc/systemd/zram-generator.conf
    system-reference/sddm-themes/nier-automata/Main.qml
)
for path in "${required_paths[@]}"; do
    if [[ -e $ROOT_DIR/$path ]]; then
        pass "required path exists: $path"
    else
        fail "required path missing: $path"
    fi
done

for file in official-explicit.txt official-portable.txt aur-explicit.txt; do
    path="$ROOT_DIR/packages/$file"
    if [[ -f $path ]] && ! grep -Ev '^(#.*|[a-zA-Z0-9@._+:-]+|)$' "$path" | grep -q .; then
        pass "$file format"
    else
        fail "$file format"
    fi
    if [[ -z $(grep -Ev '^(#.*|$)' "$path" | sort | uniq -d) ]]; then
        pass "$file has no duplicates"
    else
        fail "$file contains duplicates"
    fi
done

if [[ -z $(find "$ROOT_DIR" -xtype l -print) ]]; then
    pass 'no broken symlinks'
else
    fail 'broken symlinks found'
    find "$ROOT_DIR" -xtype l -print >&2
fi

if [[ -z $(find "$ROOT_DIR" -type f -size +50M -print) ]]; then
    pass 'no individual files larger than 50 MiB'
else
    fail 'files larger than 50 MiB found'
    find "$ROOT_DIR" -type f -size +50M -print >&2
fi

secret_pattern='(gh[opusr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{16,}|bearer[[:space:]]+[A-Za-z0-9._-]{16,}|BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY|api[_-]?key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_./+=-]{12,}|access[_-]?token[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_./+=-]{12,}|client[_-]?secret[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_./+=-]{12,})'
if rg -n -i --hidden --glob '!SHA256SUMS' --glob '!FILES-MANIFEST.tsv' "$secret_pattern" "$ROOT_DIR"; then
    fail 'high-confidence secret pattern detected'
else
    pass 'no high-confidence secret patterns'
fi

for forbidden in .env .ssh .gnupg node_modules .cache; do
    if find "$ROOT_DIR" -name "$forbidden" -print -quit | grep -q .; then
        fail "forbidden path found: $forbidden"
    else
        pass "forbidden path absent: $forbidden"
    fi
done

if [[ -f $ROOT_DIR/SHA256SUMS ]]; then
    if (cd "$ROOT_DIR" && sha256sum -c --quiet SHA256SUMS); then
        pass 'SHA256SUMS verification'
    else
        fail 'SHA256SUMS verification'
    fi
fi

if $FAILED; then
    exit 1
fi
pass 'recovery kit validation complete'
