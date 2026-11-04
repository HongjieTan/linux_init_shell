#!/usr/bin/env bash

TASKS=()
TASKS+=('添加库::sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm -y; sudo dnf copr enable wehagy/protonplus -y; sudo dnf copr enable atim/starship -y; sudo dnf copr enable regunakyle/sarasa-gothic -y; sudo dnf copr enable komapro/nerd-fonts -y; sudo dnf copr enable scottames/ghostty -y; sudo dnf copr enable douglascdev/dnf5-autosnapper -y; sudo dnf copr enable jmarcoshp/grub-btrfs -y; sudo dnf copr enable lionheartp/Hyprland -y')
TASKS+=('安装软件::sudo dnf config-manager setopt fedora.mirrorlist='\''https://mirrors.cernet.edu.cn/api/rpm/mirrorlist/fedora/releases/$releasever/Everything/$basearch/os/'\''; sudo dnf config-manager setopt fedora.metalink=; sudo dnf config-manager setopt updates.mirrorlist='\''https://mirrors.cernet.edu.cn/api/rpm/mirrorlist/fedora/updates/$releasever/Everything/$basearch/'\''; sudo dnf config-manager setopt updates.metalink=; sudo dnf install dnf5-autosnapper ufw fcitx5-rime libreoffice-calc libreoffice-impress libreoffice-writer papirus-icon-theme xrdb chromium adw-gtk3-theme protonplus fastfetch steam google-noto-color-emoji-fonts sarasa-gothic firacode-nerd-font ghostty which git rsync mangohud kmscon plymouth-system-theme glib noctalia-git noctalia-greeter-git nano pam_oo7 oo7-daemon ddcutil rtkit seahorse fish gtksourceview5 gvfs btrfs-assistant grub-btrfs power-profiles-daemon flatpak -y; sudo dnf swap ffmpeg-free ffmpeg --allowerasing; sudo dnf install --setopt=install_weak_deps=False hyprland -y; sudo dnf install xdg-desktop-portal-hyprland hyprland-guiutils -y; sudo dnf remove vim-data ibus NetworkManager-wwan NetworkManager-bluetooth systemd-network systemd-resolved fcitx5-configtool zram-generator power-profiles-daemon NetworkManager-team iptables-nft fcitx5-configtool podman -y; curl -fsSL https://raw.githubusercontent.com/lgse/strata/main/install.sh | bash')
TASKS+=('安装 flathub软件::flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; sudo flatpak remote-modify flathub --url=https://mirrors.cernet.edu.cn/flathub; flatpak install flathub com.usebottles.bottles; flatpak install flathub com.saivert.pwvucontrol; flatpak install flathub com.saivert.pwvucontrol')
TASKS+=('配置 kmscon::sudo mkdir -p /etc/kmscon/;printf '\''font-name=FiraCode Nerd Font Mono, Noto Sans Mono CJK SC\nfont-size=20\n'\'' | sudo tee /etc/kmscon/kmscon.conf ')
TASKS+=('安装 nvidia驱动::sudo dnf install akmods -y; sudo kmodgenca -a; sudo mokutil --import /etc/pki/akmods/certs/public_key.der; sudo dnf install akmod-nvidia; printf '\''font-name=FiraCode Nerd Font Mono, Noto Sans Mono CJK SC\nfont-size=30\n'\'' | sudo tee /etc/kmscon/kmscon.conf')
TASKS+=('基础配置::printf '\''installonly_limit=2'\'' | sudo tee -a /etc/dnf/dnf.conf; sudo swapoff /dev/zram0; cd /swap; sudo truncate -s 0 swapfile; sudo chattr +C swapfile; sudo fallocate -l 12G swapfile; sudo chmod 0600 swapfile; sudo mkswap swapfile; sudo swapon /swap/swapfile; printf '\''/swap/swapfile none swap sw 0 0'\'' | sudo tee -a /etc/fstab; sudo plymouth-set-default-theme -R bgrt; sudo grub2-mkconfig -o /boot/grub2/grub.cfg; sudo systemctl enable --now grub-btrfsd; gsudo awk -i inplace '\''/^post_transaction::::/ {$0="# "$0}'\''  /etc/dnf/libdnf5-plugins/actions.d/snapper.actions')
TASKS+=('软连接配置和文件::sudo mkdir -p /root/.config; sudo ln -s ~/.config/gtk-3.0 /root/.config/gtk-3.0; sudo ln -s ~/.config/gtk-4.0 /root/.config/gtk-4.0; sudo ln -s ~/.nanorc /root/.nanorc; sudo rm -rf /usr/share/icons/default; sudo ln -s ~/.local/share/icons/default /usr/share/icons/default; sudo cp -rf ~/.local/share/icons/Bibata-* /usr/share/icons/; sudo cp -rf ~/Documents/Linux_BackUp/etc /; chsh -s $(which fish)')
TASKS+=('配置 gtk主题::gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3; gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3; gsettings set org.gnome.desktop.interface color-scheme '\''prefer-dark'\''')
TASKS+=('禁用无关服务::sudo systemctl disable --now systemd-oomd; sudo systemctl mask systemd-oomd; sudo systemctl disable --now systemd-networkd; sudo systemctl mask systemd-networkd; sudo systemctl disable --now systemd-userdbd; sudo systemctl mask systemd-userdbd; sudo systemctl disable --now systemd-homed; sudo systemctl mask systemd-homed')
TASKS+=('配置防火墙::sudo ufw default reject incoming; sudo ufw default allow outgoing; sudo ufw limit ssh; sudo ufw allow http; sudo ufw allow https; sudo ufw allow 7890; sudo ufw allow 4950,4955/udp; sudo ufw allow 6695:6699/tcp; sudo ufw allow 67/udp; sudo ufw allow 68/udp; sudo ufw enable')
TASKS+=('配置 greetd::sudo sed -i '\''s|^[[:space:]]*command[[:space:]]*=.*$|command = "/usr/bin/noctalia-greeter-session"|'\'' /etc/greetd/config.toml; sudo mkdir -p /etc/systemd/system/multi-user.target.wants; sudo ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/multi-user.target.wants/greetd.service; sudo systemctl daemon-reload; sudo systemctl enable --now greetd; systemctl --user enable --now oo7-daemon.service')
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
