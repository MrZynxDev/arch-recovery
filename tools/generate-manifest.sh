#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT="$ROOT_DIR/FILES-MANIFEST.tsv"
SOURCE_HOME=/home/zynx

printf 'type\tincluded_path\toriginal_location\trestore_destination\tportable\tmanual_review\tmay_be_sensitive\treason\n' > "$OUTPUT"
printf 'f\tFILES-MANIFEST.tsv\tgenerated for recovery kit\tnot applicable\tyes\tno\tno\tComplete included-object inventory\n' >> "$OUTPUT"

while IFS=$'\t' read -r type path; do
    original='generated for recovery kit'
    destination='not applicable'
    portable=yes
    review=no
    sensitive=no
    reason='Recovery kit metadata or documentation'

    case "$path" in
        dotfiles/home/*)
            relative=${path#dotfiles/home/}
            original="$SOURCE_HOME/$relative"
            destination="\$HOME/$relative"
            reason='Selected desktop, shell, editor, service, or user-script configuration'
            ;;
        assets/icons/*)
            relative=${path#assets/icons/}
            original="$SOURCE_HOME/.icons/$relative"
            destination="\$HOME/.icons/$relative"
            reason='Selected cursor/icon theme required by desktop configuration'
            review=yes
            ;;
        assets/Pictures/*)
            relative=${path#assets/Pictures/}
            original="$SOURCE_HOME/Pictures/$relative"
            destination="\$HOME/Pictures/$relative"
            reason='Wallpaper required by dynamic theme configuration'
            review=yes
            ;;
        system-reference/etc/*)
            relative=${path#system-reference/}
            original="/$relative"
            destination='reference only; selected groups offered by --system-config'
            portable=mixed
            review=yes
            sensitive='source identifiers redacted; review destination-specific settings'
            reason='Curated current system configuration reference'
            ;;
        system-reference/sddm-themes/*)
            relative=${path#system-reference/sddm-themes/}
            original="/usr/share/sddm/themes/$relative"
            destination="/usr/share/sddm/themes/$relative"
            portable=yes
            review=yes
            reason='Unmanaged active SDDM theme'
            ;;
        hardware/*)
            original='generated from source hardware/runtime inspection'
            destination='documentation only; never restored'
            portable=no
            review=yes
            sensitive='source hostname and filesystem UUIDs redacted'
            reason='Source hardware, service, kernel, and filesystem reference'
            ;;
        packages/*)
            original='generated from package managers or curated dependency audit'
            destination='package manager installation input or reference'
            review=yes
            reason='Explicit package inventory and restore policy'
            ;;
        tools/*)
            original='created for recovery kit'
            destination='run from repository'
            reason='Recovery kit maintenance and validation tooling'
            ;;
        restore.sh)
            destination='run from repository'
            reason='Guided idempotent restoration workflow'
            ;;
    esac

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$type" "$path" "$original" "$destination" "$portable" "$review" "$sensitive" "$reason" >> "$OUTPUT"
done < <(find "$ROOT_DIR" -mindepth 1 \
    ! -path "$OUTPUT" \
    ! -path "$ROOT_DIR/.git" \
    ! -path "$ROOT_DIR/.git/*" \
    -printf '%y\t%P\n' | LC_ALL=C sort -t $'\t' -k2)
