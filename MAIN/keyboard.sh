cat > ~/keyboard-ru-us.sh <<'SCRIPT'
#!/bin/sh
set -eu

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"

echo "[1/3] Настройка Labwc (Wayland)..."

mkdir -p "$CFG/labwc"

ENV_FILE="$CFG/labwc/environment"
TMP=$(mktemp)

if [ -f "$ENV_FILE" ]; then
    grep -vE '^[[:space:]]*(export[[:space:]]+)?XKB_DEFAULT_(LAYOUT|OPTIONS)=' \
        "$ENV_FILE" > "$TMP" || true
fi

cat >> "$TMP" <<'EOF'
XKB_DEFAULT_LAYOUT=us,ru
XKB_DEFAULT_OPTIONS=grp:alt_shift_toggle
EOF

mv "$TMP" "$ENV_FILE"

echo "[2/3] Настройка Wayfire..."

WF_FILE="$CFG/wayfire.ini"

if [ ! -f "$WF_FILE" ] && [ -f /etc/xdg/wayfire.ini ]; then
    cp /etc/xdg/wayfire.ini "$WF_FILE"
fi

if [ -f "$WF_FILE" ]; then
    TMP=$(mktemp)

    awk '
    BEGIN { inside=0; inserted=0 }

    /^[[:space:]]*\[input\][[:space:]]*$/ {
        print
        if (!inserted) {
            print "xkb_layout = us,ru"
            print "xkb_options = grp:alt_shift_toggle"
            inserted=1
        }
        inside=1
        next
    }

    /^[[:space:]]*\[/ { inside=0 }

    {
        if (inside && $0 ~ /^[[:space:]]*xkb_(layout|options)[[:space:]]*=/)
            next
        print
    }

    END {
        if (!inserted) {
            print ""
            print "[input]"
            print "xkb_layout = us,ru"
            print "xkb_options = grp:alt_shift_toggle"
        }
    }
    ' "$WF_FILE" > "$TMP"

    mv "$TMP" "$WF_FILE"
fi

echo "[3/3] Настройка X11..."

XSESSION="$HOME/.xsessionrc"
XKB_CMD="setxkbmap -layout us,ru -option grp:alt_shift_toggle"

if [ ! -f "$XSESSION" ] || ! grep -Fq "$XKB_CMD" "$XSESSION"; then
    printf '\n# RU/US keyboard layouts\n%s\n' "$XKB_CMD" >> "$XSESSION"
fi

if [ "${XDG_SESSION_TYPE:-}" = "x11" ] || {
    [ -n "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ];
}; then
    if command -v setxkbmap >/dev/null 2>&1; then
        setxkbmap -layout us,ru -option grp:alt_shift_toggle
        echo "Раскладки применены немедленно."
    else
        echo "Не найден setxkbmap."
    fi
else
    echo "Настройки сохранены. Перезайди в графическую сессию."
fi

echo ""
echo "ГОТОВО: US + RU, переключение Alt + Shift."
SCRIPT

chmod +x ~/keyboard-ru-us.sh
~/keyboard-ru-us.sh