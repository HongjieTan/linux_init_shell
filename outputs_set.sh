#!/usr/bin/env bash
set -euo pipefail

NIRI_CONFIG="${HOME}/.config/niri/config.kdl"
XRESOURCES="${HOME}/.Xresources"
KMSCON_CONF="/etc/kmscon/kmscon.conf"
LIMINE_CONF="/boot/limine.conf"

if [[ "$(id -u)" -eq 0 ]]; then
    echo "Please run this script as a regular user, not directly as root." >&2
    exit 1
fi

echo "Admin rights are required to perform system configuration, please enter your sudo password once:"
sudo -v || exit 1

if ! command -v niri >/dev/null 2>&1; then
  echo "Error: niri command not found" >&2
  exit 1
fi
if ! niri msg outputs >/dev/null 2>&1; then
  echo "Error: niri msg outputs failed to execute (is niri running?)" >&2
  exit 1
fi

PARSED="$(
  niri msg outputs | perl -ne '
    if (/^Output\s+"(?:[^"\\]|\\.)*"\s+\(([^)]+)\)/) {
      $out = $1;
      next;
    }
    next unless defined $out;
    while (/(\d+)x(\d+)@([\d.]+)/g) {
      my ($w, $h, $r) = ($1, $2, $3);
      my $area = $w * $h;
      if (!exists $best{$out} || $area > $best{$out}[3]) {
        $best{$out} = [$w, $h, $r, $area];
      } elsif ($area == $best{$out}[3] && $r > $best{$out}[2]) {
        $best{$out}[2] = $r;
      }
    }
    END {
      for my $o (sort keys %best) {
        my ($w, $h, $r) = @{$best{$o}};
        printf "%s|%dx%d|%s\n", $o, $w, $h, $r;
      }
    }
  '
)"

if [[ -z "${PARSED}" ]]; then
  echo "Error: No output was parsed from niri msg outputs" >&2
  exit 1
fi

declare -A OUT_RES OUT_HZ OUT_SCALE
MAX_SCALE="0"
MAX_SCALE_RES=""

format_hz() { perl -pe 's/0+$//; s/\.$//' <<<"$1"; }

while IFS='|' read -r name res hz; do
  [[ -z "${name}" ]] && continue
  w="${res%x*}"

  scale=""
  if   (( w >= 3840 )); then scale="2"
  elif (( w >= 2560 )); then scale="1.5"
  elif (( w >= 1920 )); then scale="1"
  fi

  OUT_RES["$name"]="$res"
  OUT_HZ["$name"]="$(format_hz "$hz")"
  OUT_SCALE["$name"]="$scale"

  if [[ -n "$scale" ]] && awk -v a="$scale" -v b="$MAX_SCALE" 'BEGIN{exit !(a>b)}'; then
    MAX_SCALE="$scale"
    MAX_SCALE_RES="$res"
  fi
done <<< "$PARSED"

echo "== Result =="
for name in "${!OUT_RES[@]}"; do
  printf '  %-12s %s@%s  scale=%s\n' \
    "$name" "${OUT_RES[$name]}" "${OUT_HZ[$name]}" "${OUT_SCALE[$name]:-none}"
done
echo "  max scale: ${MAX_SCALE}  (Resolution: ${MAX_SCALE_RES:-none})"
echo

# ---------- niri config.kdl ----------
mkdir -p "$(dirname "$NIRI_CONFIG")"
[[ -f "$NIRI_CONFIG" ]] || : > "$NIRI_CONFIG"

update_kdl_block() {
  local file="$1" name="$2" block="$3" tmp
  tmp="$(mktemp)"
  KDL_NAME="$name" KDL_BLOCK="$block" perl -0777 -e '
    my $name  = $ENV{KDL_NAME};
    my $block = $ENV{KDL_BLOCK};
    local $/;
    my $content = <STDIN>;
    # output
    my $pat = qr/^[ \t]*output[ \t]+"\Q$name\E"[ \t]*\{[^{}]*\}[ \t]*\n?/m;
    if ($content =~ /$pat/) {
      $content =~ s/$pat/$block\n/;
    } else {
      $content .= "\n" unless $content =~ /\n\z/;
      $content .= $block . "\n";
    }
    print $content;
  ' < "$file" > "$tmp"
  mv "$tmp" "$file"
}

for name in "${!OUT_RES[@]}"; do
  res="${OUT_RES[$name]}"
  hz="${OUT_HZ[$name]}"
  sc="${OUT_SCALE[$name]}"

  block="output \"$name\" {"
  block+=$'\n'"    mode \"${res}@${hz}\""
  if [[ -n "$sc" ]]; then
    block+=$'\n'"    scale $sc"
  fi
  block+=$'\n'"    variable-refresh-rate on-demand=true"
  block+=$'\n'"}"
  update_kdl_block "$NIRI_CONFIG" "$name" "$block"
done
echo "updated $NIRI_CONFIG"

# ---------- ~/.Xresources ----------
if [[ "$MAX_SCALE" != "0" ]]; then
  dpi=$(awk -v s="$MAX_SCALE" 'BEGIN{printf "%d", 96*s}')
  if [[ -f "$XRESOURCES" ]] && grep -q '^Xft\.dpi:' "$XRESOURCES"; then
    sed -i "s|^Xft\.dpi:.*|Xft.dpi: $dpi|" "$XRESOURCES"
  else
    echo "Xft.dpi: $dpi" >> "$XRESOURCES"
  fi
  echo "updated Xft.dpi: $dpi"
fi

# ---------- kmscon.conf ----------
if [[ -f "$KMSCON_CONF" ]]; then
    new_font=""
    case "$MAX_SCALE" in
        2)        new_font=30 ;;
        1.5|1.50) new_font=25 ;;
        *)        new_font=""  ;;  
    esac
    if [[ -n "$new_font" ]]; then
        if sudo grep -qE '^[[:space:]]*font-size[[:space:]]*=' "$KMSCON_CONF"; then
        sudo sed -i -E "s|^[[:space:]]*(font-size[[:space:]]*=[[:space:]]*).*|\1$new_font|" "$KMSCON_CONF"
        fi
        echo "updated kmscon font-size=$new_font"
    fi
fi

# ---------- limine.conf ----------
  if [[ -z "$MAX_SCALE_RES" ]]; then
    echo "Warning: No valid resolution can be written to limine.conf, skipped" >&2
  else
    case "$MAX_SCALE" in
      2|1.5|1.50) term_font_scale="3x3" ;;
      1)          term_font_scale="2x2" ;;
      *)          term_font_scale="" ;;
    esac
    if [[ -n "$term_font_scale" ]]; then
      
      sudo sed -i '/^term_font_size:/d; /^interface_resolution:/d; /^term_font_scale:/d' "$LIMINE_CONF"
      sudo awk -v r="$MAX_SCALE_RES" -v f="$term_font_scale" '
        /^### Theme/ && !done {
          print
          print "term_font_size: 9x16"
          print "interface_resolution: " r
          print "term_font_scale: " f
          print ""
          done = 1
          next
        }
        { print }
        END {
          if (!done) {
            print "Warning: ### Theme line not found, limine configuration not inserted." > "/dev/stderr"
          }
        }
      ' "$LIMINE_CONF" | sudo tee "$LIMINE_CONF.tmp" > /dev/null && sudo mv "$LIMINE_CONF.tmp" "$LIMINE_CONF"
      echo "updated $LIMINE_CONF"
    fi
  fi
echo
echo "All done."