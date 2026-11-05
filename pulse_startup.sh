cat > ~/setup-pulse-kiosk.sh <<'SETUP'
#!/bin/sh
set -eu

URL="https://pulse.sbm-soft.local"
DIR="$HOME/.local/bin"
LAUNCHER="$DIR/pulse-kiosk.sh"

echo "=== Настройка Pulse Kiosk ==="

# Проверяем наличие Chromium
BROWSER=""
for APP in chromium chromium-browser; do
    if command -v "$APP" >/dev/null 2>&1; then
        BROWSER=$(command -v "$APP")
        break
    fi
done

if [ -z "$BROWSER" ]; then
    echo "ОШИБКА: Chromium не найден."
    exit 1
fi

echo "Chromium: $BROWSER"

mkdir -p "$DIR"

# ---------------------------------------------
# Создаём скрипт запуска браузера
# ---------------------------------------------

cat > "$LAUNCHER" <<'EOF'
#!/bin/sh

URL="https://pulse.sbm-soft.local"

# Ждём загрузки рабочего стола и сети
sleep 8

BROWSER=""
for APP in chromium chromium-browser; do
    if command -v "$APP" >/dev/null 2>&1; then
        BROWSER=$(command -v "$APP")
        break
    fi
done

if [ -z "$BROWSER" ]; then
    echo "Chromium not found" >&2
    exit 1
fi

# Ждём доступности локального сайта (максимум около минуты)
if command -v curl >/dev/null 2>&1; then
    i=0
    while [ "$i" -lt 20 ]; do
        if curl -k -sS -o /dev/null \
            --connect-timeout 2 --max-time 4 "$URL"; then
            break
        fi
        i=$((i + 1))
        sleep 3
    done
fi

# Запускаем отдельный профиль Chromium в режиме Kiosk
exec "$BROWSER" \
    --kiosk \
    --start-maximized \
    --noerrdialogs \
    --disable-infobars \
    --no-first-run \
    --no-default-browser-check \
    --disable-session-crashed-bubble \
    --disable-features=TranslateUI \
    --password-store=basic \
    --user-data-dir="$HOME/.config/chromium-pulse-kiosk" \
    "$URL"
EOF

chmod +x "$LAUNCHER"

# ---------------------------------------------
# Определяем графическую среду
# ---------------------------------------------

if pgrep -x labwc >/dev/null 2>&1; then
    MODE="labwc"
elif pgrep -x wayfire >/dev/null 2>&1; then
    MODE="wayfire"
elif pgrep -x lxsession >/dev/null 2>&1; then
    MODE="lxde"
elif [ -n "${XDG_SESSION_TYPE:-}" ] &&
     [ "$XDG_SESSION_TYPE" = "x11" ]; then
    MODE="xdg"
elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
    MODE="labwc"
elif [ -f "$HOME/.config/labwc/autostart" ]; then
    MODE="labwc"
elif [ -f "$HOME/.config/wayfire.ini" ]; then
    MODE="wayfire"
else
    MODE="labwc"
fi

echo "Графическая среда: $MODE"

# ---------------------------------------------
# Настраиваем автозапуск
# ---------------------------------------------

python3 - "$MODE" "$LAUNCHER" <<'PY'
import sys
import re
import shlex
from pathlib import Path

mode = sys.argv[1]
launcher = Path(sys.argv[2]).resolve()
home = Path.home()

command = "/bin/sh " + shlex.quote(str(launcher))

if mode == "labwc":
    path = home / ".config/labwc/autostart"
    path.parent.mkdir(parents=True, exist_ok=True)

    text = path.read_text() if path.exists() else ""

    begin = "# BEGIN PULSE KIOSK"
    end = "# END PULSE KIOSK"

    block = f'{begin}\n{command} &\n{end}'

    if begin in text and end in text:
        before = text[:text.index(begin)]
        after = text[text.index(end) + len(end):]
        text = before + block + after
    else:
        text = text.rstrip() + "\n\n" + block + "\n"

    path.write_text(text)

elif mode == "wayfire":
    path = home / ".config/wayfire.ini"
    path.parent.mkdir(parents=True, exist_ok=True)

    lines = path.read_text().splitlines() if path.exists() else []

    start = next(
        (i for i, line in enumerate(lines)
         if re.match(r"^\s*\[autostart\]\s*$", line)),
        -1
    )

    if start == -1:
        if lines:
            lines.append("")
        lines.extend(["[autostart]", f"pulse_kiosk = {command}"])
    else:
        end = len(lines)
        for i in range(start + 1, len(lines)):
            if re.match(r"^\s*\[.*\]\s*$", lines[i]):
                end = i
                break

        lines = [
            line for i, line in enumerate(lines)
            if not (start < i < end and
                    re.match(r"^\s*pulse_kiosk\s*=", line))
        ]

        end = len(lines)
        for i in range(start + 1, len(lines)):
            if re.match(r"^\s*\[.*\]\s*$", lines[i]):
                end = i
                break

        lines.insert(end, f"pulse_kiosk = {command}")

    path.write_text("\n".join(lines) + "\n")

elif mode == "lxde":
    path = home / ".config/lxsession/LXDE-pi/autostart"
    path.parent.mkdir(parents=True, exist_ok=True)

    text = path.read_text() if path.exists() else ""

    if str(launcher) not in text:
        path.write_text(text.rstrip() + "\n@" + command + "\n")

else:
    path = home / ".config/autostart/pulse-kiosk.desktop"
    path.parent.mkdir(parents=True, exist_ok=True)

    executable = str(launcher).replace("\\", "\\\\").replace('"', '\\"')

    path.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=Pulse Kiosk\n"
        f'Exec=/bin/sh "{executable}"\n'
        "Terminal=false\n"
        "X-GNOME-Autostart-enabled=true\n"
    )

print("Автозапуск настроен.")
PY

echo ""
echo "=================================="
echo "           ГОТОВО"
echo "=================================="
echo "Адрес: $URL"
echo "Режим: Kiosk"
echo "Автозапуск: включён"
echo ""

# Запускаем немедленно, если скрипт вызван из рабочего стола
if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    nohup "$LAUNCHER" >/tmp/pulse-kiosk.log 2>&1 </dev/null &
    echo "Chromium запущен в текущей сессии."
fi

echo "После следующего входа в рабочий стол запуск будет автоматическим."
SETUP

chmod +x ~/setup-pulse-kiosk.sh
~/setup-pulse-kiosk.sh