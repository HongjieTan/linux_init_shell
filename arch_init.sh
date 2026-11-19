#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
    echo "Please run this script as a regular user, not directly as root." >&2
    exit 1
fi

echo "Admin rights are required to perform system configuration, please enter your sudo password once:"
sudo -v || exit 1

( while true; do sudo -n true 2>/dev/null || exit; sleep 60; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

run_root() {
    sudo "$@"
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IS_NVIDIA=0
if lsmod | grep -qE '^(nvidia|nouveau)'; then
    IS_NVIDIA=1
fi

install_software() {
    run_root pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
    run_root pacman-key --lsign-key F3B607488DB35A47
    run_root pacman -U --noconfirm \
        'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
        'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-27-1-any.pkg.tar.zst'

    if ! grep -q '^\[cachyos\]' /etc/pacman.conf; then
        printf '# cachyos repos\n[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n' |
            run_root tee -a /etc/pacman.conf >/dev/null
    fi

    if [[ "${LANG:-}" == *zh_CN* ]]; then
        printf 'Server = https://mirror.nju.edu.cn/cachyos/repo/$arch/$repo\nServer = https://mirrors.ustc.edu.cn/cachyos/repo/$arch/$repo\nServer = https://cdn77.cachyos.org/repo/$arch/$repo\n' |
            run_root tee /etc/pacman.d/cachyos-mirrorlist >/dev/null
        run_root pacman -Syu --needed fcitx5-rime kmscon kmscon-terminfo
    fi

    run_root pacman -Syu --needed \
        amd-ucode git fish base base-devel adw-gtk-theme glib2 btrfs-assistant chromium \
        fastfetch ghostty ghostty-terminfo gamemode onlyoffice-bin code nano \
        nano-syntax-highlighting pacman-contrib papirus-icon-theme steam \
        ttf-firacode-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra \ xorg-xrdb power-profiles-daemon snap-pac \
        bluez wireless-regdb openrgb i2c-tools noctalia noctalia-greeter \
        pipewire-libcamera rtkit niri xwayland-satellite xdg-desktop-portal-wlr \
        xdg-desktop-portal-gtk ufw less oo7 seahorse inotify-tools umu-launcher \
        file-roller unzip 7zip unrar ddcutil vulkan-tools mesa-utils paru eza \
        limine-snapper-sync limine-mkinitcpio-hook

    if [[ "$IS_NVIDIA" -eq 1 ]]; then
        run_root pacman -Syu --needed nvidia-open libva-nvidia-driver
    fi
}

install_other() {
    paru -S --needed bottles mangojuice-bin wechat pwvucontrol \
        code-marketplace code-features bibata-cursor-theme-bin

    local orphan_packages
    orphan_packages="$(pacman -Qtdq 2>/dev/null || true)"
    if [[ -n "$orphan_packages" ]]; then
        run_root pacman -Rns --noconfirm $orphan_packages
    fi

    curl -fsSL https://raw.githubusercontent.com/lgse/strata/main/install.sh | bash
}

fix_fstab() {
    run_root cp -a /etc/fstab "/etc/fstab.bak.$(date +%F)"
    run_root gawk -i inplace '
        BEGIN { OFS=" " }
        /^[[:space:]]*#/ { print; next }
        NF < 4 { print; next }
        {
            if ($3 == "btrfs") {
                keep = ""
                n = split($4, a, ",")
                for (i = 1; i <= n; i++)
                    if (a[i] ~ /^subvol=/ || a[i] ~ /^subvolid=/) keep = keep "," a[i]
                $4 = "defaults,noatime,compress=zstd:1" keep
            } else if ($3 == "ext4") {
                $4 = "defaults,noatime"
            }
            print
        }
    ' /etc/fstab
    run_root mount -a
}

limine_config_set() {
    local limine_conf="/etc/default/limine"
    local limine_boot_conf="/boot/limine.conf"
    local root_source partuuid

    root_source="$(findmnt -n -o SOURCE /)"
    if [[ "$root_source" == *"["* ]]; then
        root_source="${root_source%%\[*}"
    fi

    partuuid="$(blkid -s PARTUUID -o value "$root_source" 2>/dev/null || true)"
    if [[ -z "$partuuid" ]]; then
        echo "Error: Can't get root partition PARTUUID." >&2
        return 1
    fi

    echo "PARTUUID: $partuuid"

    if ! run_root test -f "$limine_conf"; then
        run_root mkdir -p "$(dirname "$limine_conf")"
        printf '%s\n' \
            'ESP_PATH="/boot"' \
            "KERNEL_CMDLINE[default]+=\"nowatchdog splash quiet rw rootflags=subvol=/@ root=PARTUUID=${partuuid}\"" \
            'BOOT_ORDER="*, *fallback, Snapshots"' \
            'ENABLE_UKI=yes' \
            'CUSTOM_UKI_NAME="arch"' \
            'MKINITCPIO_UKI_OPTIONS="--splash /usr/share/systemd/bootctl/splash-arch.bmp"' |
            run_root tee "$limine_conf" >/dev/null
        return 0
    fi

    run_root cp -a "$limine_conf" "${limine_conf}.bak.$(date +%Y%m%d%H%M%S)"

    if ! run_root grep -qE '^KERNEL_CMDLINE\[default\]\+=' "$limine_conf"; then
        printf '%s\n' "KERNEL_CMDLINE[default]+=\"nowatchdog splash quiet rw rootflags=subvol=/@ root=PARTUUID=${partuuid}\"" |
            run_root tee -a "$limine_conf" >/dev/null
    elif run_root grep -qE '^KERNEL_CMDLINE\[default\]\+=.*root=PARTUUID=' "$limine_conf"; then
        run_root sed -i -E \
            "/^KERNEL_CMDLINE\\[default\\]\\+=/ s|(root=PARTUUID=)[^\"[:space:]]*|\\1${partuuid}|" \
            "$limine_conf"
    else
        run_root sed -i -E \
            "/^KERNEL_CMDLINE\\[default\\]\\+=/ s|(\"?)$| root=PARTUUID=${partuuid}\\1|" \
            "$limine_conf"
    fi

    if ! run_root test -f "$limine_boot_conf"; then
        printf '%s\n' \
            '### Theme' \
            'term_palette: 1e1e2e;f38ba8;a6e3a1;f9e2af;89b4fa;f5c2e7;94e2d5;cdd6f4' \
            'term_palette_bright: 585b70;f38ba8;a6e3a1;f9e2af;89b4fa;f5c2e7;94e2d5;cdd6f4' \
            'term_background: 1e1e2e' \
            'term_foreground: cdd6f4' \
            'term_background_bright: 585b70' \
            'term_foreground_bright: cdd6f4' \
            'interface_branding_color: b4befe' \
            'interface_help_color: b4befe' \
            'interface_help_color_bright: b4befe' |
            run_root tee "$limine_boot_conf" >/dev/null
        return 0
    fi
}

swap_set() {
    run_root mkdir -p /swap
    run_root bash -c '
        cd /swap
        touch swapfile
        chattr +C swapfile
        truncate -s 0 swapfile
        fallocate -l 12G swapfile
        chmod 0600 swapfile
        mkswap swapfile
        swapon /swap/swapfile
    '
    if ! grep -qE '^/swap/swapfile[[:space:]]' /etc/fstab; then
        printf '/swap/swapfile none swap sw 0 0\n' |
            run_root tee -a /etc/fstab >/dev/null
    fi
}

user_set() {
    if [[ -d "$SCRIPT_DIR/home_base" ]]; then
        cp -rf "$SCRIPT_DIR/home_base/." "$HOME/"
    fi
    if [[ "${LANG:-}" == *zh_CN* && -d "$SCRIPT_DIR/home_add_zh" ]]; then
        cp -rf "$SCRIPT_DIR/home_add_zh/." "$HOME/"
    fi

    local profile="$HOME/.profile"
    local marker="# >>> NVIDIA Wayland/GBM environment variables >>>"
    local end_marker="# <<< NVIDIA Wayland/GBM environment variables <<<"

    if [[ "$IS_NVIDIA" -eq 1 ]] && ! grep -qF "$marker" "$profile" 2>/dev/null; then
        cat >> "$profile" <<EOF

${marker}
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export GBM_BACKEND=nvidia-drm
export NVD_BACKEND=direct
export __GL_SHADER_DISK_CACHE_SIZE=48000000000
export CUDA_DISABLE_PERF_BOOST=1
${end_marker}
EOF
    fi
}

sys_set() {
    run_root mv -f /usr/share/libalpm/hooks/zz-snap-pac-post.hook \
        /usr/share/libalpm/hooks/zz-snap-pac-post.hook.disabled

    run_root mkdir -p /root/.config
    run_root ln -sfn "$HOME/.config/gtk-3.0" /root/.config/gtk-3.0
    run_root ln -sfn "$HOME/.config/gtk-4.0" /root/.config/gtk-4.0
    run_root ln -sfn "$HOME/.nanorc" /root/.nanorc

    if [[ -d "$SCRIPT_DIR/root" ]]; then
        run_root cp -rf "$SCRIPT_DIR/root/." /
    fi

    run_root systemctl disable --now systemd-oomd
    run_root systemctl mask systemd-oomd
    run_root systemctl disable --now systemd-networkd
    run_root systemctl mask systemd-networkd
    run_root systemctl disable --now systemd-userdbd
    run_root systemctl mask systemd-userdbd
    run_root systemctl disable --now systemd-homed
    run_root systemctl mask systemd-homed

    if [[ "${LANG:-}" == *zh_CN* ]]; then
        run_root ln -sf /usr/lib/systemd/system/kmsconvt@.service \
            /etc/systemd/system/autovt@.service
        run_root mkdir -p /etc/kmscon
        printf 'mouse\nmulti-monitor=largest\nfont-engine=freetype\nfont-name=FiraCode Nerd Font Mono, Noto Sans Mono CJK SC\nfont-size=20\nfont-engine=pango' |
            run_root tee /etc/kmscon/kmscon.conf >/dev/null
        if [[ "$IS_NVIDIA" -eq 1 ]]; then
            printf 'mouse\nmulti-monitor=largest\nfont-engine=freetype\nfont-name=FiraCode Nerd Font Mono, Noto Sans Mono CJK SC\nfont-size=30\nfont-engine=pango' |
                run_root tee /etc/kmscon/kmscon.conf >/dev/null
        fi
    fi

    run_root chsh -s "$(command -v fish)" "$USER"
}

ufw_set() {
    run_root ufw default reject incoming
    run_root ufw default allow outgoing
    run_root ufw limit ssh
    run_root ufw allow http
    run_root ufw allow https
    run_root ufw allow 7890
    run_root ufw --force enable
    run_root systemctl enable ufw
}

greetd_set() {
    run_root sed -i \
        's|^[[:space:]]*command[[:space:]]*=.*$|command = "env XCURSOR_THEME=Bibata-Modern-Classic XCURSOR_SIZE=24 /usr/bin/noctalia-greeter-session"|' \
        /etc/greetd/config.toml
    run_root mkdir -p /etc/systemd/system/multi-user.target.wants
    run_root ln -sf /usr/lib/systemd/system/greetd.service \
        /etc/systemd/system/multi-user.target.wants/greetd.service
    run_root systemctl daemon-reload
    systemctl --user enable --now oo7-daemon
    run_root systemctl enable greetd
}

read -p "Do you want to do basic setup?(y/N) " ans
    case "$ans" in
        y|Y)
            echo ">>> Start basic setup."
            install_software
            limine_config_set
            fix_fstab
            swap_set
            user_set
            sys_set
            ufw_set
            greetd_set
            ;;
        *) echo ">>> skipped basic setup." ;;
    esac

read -p "Do you want to install third-party software (like AUR)?(y/N) " ans
    case "$ans" in
        y|Y)
            echo ">>> Start installing third-party software."
            install_other
            ;;
        *) echo ">>> skipped installing third-party software." ;;
    esac

echo
read -r -p "Press Enter to reboot, or press Ctrl C to cancel..."
run_root reboot
