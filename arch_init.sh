#!/usr/bin/env bash

TASKS=()
TASKS+=('安装官方库软件::sudo pacman -Sy amd-ucode git fish base base-devel adw-gtk-theme glib2 btrfs-assistant chromium fastfetch fcitx5-rime ghostty ghostty-terminfo gamemode kmscon kmscon-terminfo libreoffice-fresh-zh-cn nano nano-syntax-highlighting pacman-contrib papirus-icon-theme steam ttf-firacode-nerd ttf-sarasa-gothic noto-fonts-extra xorg-xrdb power-profiles-daemon snap-pac bluez wireless-regdb openrgb i2c-tools noctalia noctalia-greeter libva-nvidia-driver pipewire-libcamera rtkit hyprland xdg-desktop-portal-hyprland ufw less oo7 seahorse grub-btrfs umu-launcher file-roller unzip 7zip unrar ddcutil vulkan-tools mesa-utils; git clone https://aur.archlinux.org/paru.git; cd paru; makepkg -si; sudo pacman -Rns paru-debug;')
TASKS+=('配置 swap::cd /swap; sudo truncate -s 0 swapfile; sudo chattr +C swapfile; sudo fallocate -l 12G swapfile; sudo chmod 0600 swapfile; sudo mkswap swapfile; sudo swapon /swap/swapfile; printf '\''/swap/swapfile none swap sw 0 0'\'' | sudo tee -a /etc/fstab; sudo systemctl enable --now grub-btrfsd')
TASKS+=('系统配置::sudo mv /usr/share/libalpm/hooks/zz-snap-pac-post.hook /usr/share/libalpm/hooks/zz-snap-pac-post.hook.disabled; printf '\''GRUB_DISABLE_BOOTNEXT=true'\'' | sudo tee -a /etc/default/grub; sudo sed -i '\''s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="loglevel=5 systemd.log_level=debug"|'\'' /etc/default/grub; sudo mkdir -p /root/.config; sudo ln -s ~/.config/gtk-3.0 /root/.config/gtk-3.0; sudo ln -s ~/.config/gtk-4.0 /root/.config/gtk-4.0; sudo ln -s ~/.nanorc /root/.nanorc; sudo cp -rf ~/.local/share/icons/Bibata-* /usr/share/icons/; sudo rm -rf /usr/share/icons/default; sudo ln -s ~/.local/share/icons/default /usr/share/icons/default; sudo cp -rf ~/Documents/Linux_BackUp/usr /; sudo cp -rf ~/Documents/Linux_BackUp/etc /; chsh -s $(which fish)')
TASKS+=('配置 gtk主题::gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3; gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3; gsettings set org.gnome.desktop.interface color-scheme '\''prefer-dark'\''')
TASKS+=('禁用无关服务::sudo systemctl disable --now systemd-oomd; sudo systemctl mask systemd-oomd; sudo systemctl disable --now systemd-networkd; sudo systemctl mask systemd-networkd; sudo systemctl disable --now systemd-userdbd; sudo systemctl mask systemd-userdbd; sudo systemctl disable --now systemd-homed; sudo systemctl mask systemd-homed')
TASKS+=('配置防火墙::sudo ufw default reject incoming; sudo ufw default allow outgoing; sudo ufw limit ssh; sudo ufw allow http; sudo ufw allow https; sudo ufw allow 7890; sudo ufw enable; sudo systemctl enable ufw')
TASKS+=('配置 kmscon::sudo ln -sf /usr/lib/systemd/system/kmsconvt@.service /etc/systemd/system/autovt@.service; sudo mkdir -p /etc/kmscon/; printf '\''font-name=FiraCode Nerd Font Mono, Sarasa Term SC\nfont-size=20\n'\'' | sudo tee /etc/kmscon/kmscon.conf')
TASKS+=('安装 Nvidia驱动::sudo pacman -Sy nvidia-open; printf '\''font-name=FiraCode Nerd Font Mono, Sarasa Term SC\nfont-size=30\n'\'' | sudo tee /etc/kmscon/kmscon.conf')
fix_fstab() {
    sudo cp /etc/fstab /etc/fstab.bak.$(date +%F)
    sudo gawk -i inplace 'BEGIN{OFS=" "}
     /^[[:space:]]*#/ {print; next}
     NF < 4 {print; next}
     {
         if ($3=="btrfs") {
             keep=""
             n=split($4, a, ",")
             for (i=1;i<=n;i++)
                 if (a[i] ~ /^subvol=/ || a[i] ~ /^subvolid=/) keep=keep "," a[i]
             $4="defaults,noatime,compress=zstd:1" keep
         } else if ($3=="ext4") {
             $4="defaults,noatime"
         }
         print
     }' /etc/fstab
     sudo mount -a
}
TASKS+=('配置 fstab::fix_fstab')
TASKS+=('配置 greetd::sudo sed -i '\''s|^[[:space:]]*command[[:space:]]*=.*$|command = "/usr/bin/noctalia-greeter-session"|'\'' /etc/greetd/config.toml; sudo mkdir -p /etc/systemd/system/multi-user.target.wants; sudo ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/multi-user.target.wants/greetd.service; sudo systemctl daemon-reload; systemctl --user enable --now oo7-daemon; sudo systemctl enable --now greetd')
TASKS+=('安装第三方软件软件:: paru -S bottles mangojuice-bin wechat pwvucontrol visual-studio-code-bin; sudo pacman -Rns $(pacman -Qtdq); curl -fsSL https://raw.githubusercontent.com/lgse/strata/main/install.sh | bash')

ask_and_run() {
    local desc="$1"
    local cmd="$2"
    local ans

    while true; do
        read -r -p "是否执行【${desc}】? [y/N]: " ans
        case "${ans:-n}" in
            y|Y|yes|YES|Yes)
                echo "==> 开始执行: ${cmd}"
                if eval "${cmd}"; then
                    echo "==> 执行成功: ${desc}"
                else
                    echo "!!! 执行失败(退出码 $?): ${desc}" >&2
                fi
                return 0
                ;;
            n|N|no|NO|No)
                echo "==> 已跳过: ${desc}"
                return 1
                ;;
            *)
                echo "请输入 y 或 n"
                ;;
        esac
    done
}

if sudo -v; then
    echo "sudo凭据已获取。"
else
    echo "认证失败，退出。" >&2
    exit 1
fi
total=${#TASKS[@]}
for ((i = 0; i < total; i++)); do
    task="${TASKS[i]}"
    desc="${task%%::*}"
    cmd="${task#*::}"

    echo
    echo "----- 第 $((i + 1))/${total} 步 -----"
    ask_and_run "$desc" "$cmd"
done

echo
echo "全部步骤处理完毕。"
