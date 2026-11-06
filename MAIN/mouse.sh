cat > ~/fix-mouse.sh <<'SCRIPT'
#!/bin/sh
set -eu

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
SPEED="0.6"

echo "======================================"
echo " Raspberry Pi - Mouse configuration"
echo "======================================"

# Проверяем права администратора
sudo -v

# ------------------------------------------------
# 1. Отключаем энергосбережение USB HID
# ------------------------------------------------

echo ""
echo "[1/3] Настройка USB-приёмников..."

RULE_TMP=$(mktemp)
RULE_FILE="/etc/udev/rules.d/99-wireless-hid-no-autosuspend.rules"

echo "# Disable USB autosuspend for HID devices" > "$RULE_TMP"

SEEN=" "
FOUND=0

for IFACE in /sys/bus/usb/devices/*:*; do
    [ -e "$IFACE/driver" ] || continue

    DRIVER=$(basename "$(readlink -f "$IFACE/driver")")

    [ "$DRIVER" = "usbhid" ] || continue

    DEV="${IFACE%%:*}"

    [ -r "$DEV/idVendor" ] || continue
    [ -r "$DEV/idProduct" ] || continue

    VID=$(cat "$DEV/idVendor")
    PID=$(cat "$DEV/idProduct")

    KEY="$VID:$PID"

    case "$SEEN" in
        *" $KEY "*) continue ;;
    esac

    SEEN="${SEEN}${KEY} "
    FOUND=1

    # Отключаем энергосбережение прямо сейчас
    if [ -e "$DEV/power/control" ]; then
        echo on | sudo tee "$DEV/power/control" >/dev/null
    fi

    # Сохраняем настройку для последующих подключений
    printf 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="%s", ATTR{idProduct}=="%s", TEST=="power/control", ATTR{power/control}="on"\n' \
        "$VID" "$PID" >> "$RULE_TMP"

    echo "USB HID: $VID:$PID -> power ON"
done

if [ "$FOUND" -eq 1 ]; then
    sudo cp "$RULE_FILE" "$RULE_FILE.bak" 2>/dev/null || true
    sudo install -m 644 "$RULE_TMP" "$RULE_FILE"
    sudo udevadm control --reload-rules
    echo "USB autosuspend отключён для обнаруженных HID-устройств."
else
    echo "USB HID-приёмники не обнаружены."
fi

rm -f "$RULE_TMP"

# ------------------------------------------------
# 2. Настройка Labwc (Wayland)
# ------------------------------------------------

if pgrep -x labwc >/dev/null 2>&1; then

    echo ""
    echo "[2/3] Обнаружен Labwc."

    mkdir -p "$CFG/labwc"

    RC="$CFG/labwc/rc.xml"

    if [ -f "$RC" ]; then
        cp "$RC" "$RC.bak"
    fi

    python3 - "$RC" "$SPEED" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, speed = sys.argv[1], sys.argv[2]

try:
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
    tree = ET.parse(path, parser=parser)
    root = tree.getroot()
except FileNotFoundError:
    root = ET.Element("labwc_config")
    tree = ET.ElementTree(root)

if root.tag != "labwc_config":
    raise SystemExit("Ошибка: неизвестная структура rc.xml. Исходный файл сохранён.")

libinput = root.find("libinput")

if libinput is None:
    libinput = ET.SubElement(root, "libinput")

device = None

for item in libinput.findall("device"):
    if item.get("category") == "non-touch":
        device = item
        break

if device is None:
    device = ET.SubElement(libinput, "device", {"category": "non-touch"})

for tag, value in (
    ("pointerSpeed", speed),
    ("accelProfile", "adaptive"),
):
    node = device.find(tag)

    if node is None:
        node = ET.SubElement(device, tag)

    node.text = value

if hasattr(ET, "indent"):
    ET.indent(tree, space="  ")

tree.write(path, encoding="utf-8", xml_declaration=True)

print("Mouse speed:", speed)
print("Acceleration: adaptive")
PY

    # Перечитываем настройки Labwc
    pkill -HUP -x labwc 2>/dev/null || true

# ------------------------------------------------
# 3. Настройка Wayfire
# ------------------------------------------------

elif pgrep -x wayfire >/dev/null 2>&1; then

    echo ""
    echo "[2/3] Обнаружен Wayfire."

    mkdir -p "$CFG"

    WF="$CFG/wayfire.ini"

    if [ ! -f "$WF" ] && [ -f /etc/xdg/wayfire.ini ]; then
        cp /etc/xdg/wayfire.ini "$WF"
    fi

    if [ -f "$WF" ]; then
        cp "$WF" "$WF.bak"
    fi

    python3 - "$WF" "$SPEED" <<'PY'
import sys
import re

path, speed = sys.argv[1], sys.argv[2]

try:
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()
except FileNotFoundError:
    lines = []

values = {
    "mouse_cursor_speed": speed,
    "mouse_accel_profile": "adaptive",
}

start = None
end = len(lines)

for i, line in enumerate(lines):
    if re.match(r"^\s*\[input\]\s*$", line):
        start = i
        break

if start is None:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines.extend(["\n", "[input]\n"])
    start = len(lines) - 1
else:
    for i in range(start + 1, len(lines)):
        if re.match(r"^\s*\[.*\]\s*$", lines[i]):
            end = i
            break

for key, value in values.items():
    pattern = re.compile(r"^\s*" + re.escape(key) + r"\s*=")
    found = False

    for i in range(start + 1, end):
        if pattern.match(lines[i]):
            lines[i] = f"{key} = {value}\n"
            found = True

    if not found:
        lines.insert(end, f"{key} = {value}\n")
        end += 1

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)

print("Mouse speed:", speed)
print("Acceleration: adaptive")
PY

# ------------------------------------------------
# 4. Настройка X11
# ------------------------------------------------

elif [ "${XDG_SESSION_TYPE:-}" = "x11" ] || {
    [ -n "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ];
}; then

    echo ""
    echo "[2/3] Обнаружен X11."

    XRC="$HOME/.xsessionrc"

    if [ -f "$XRC" ]; then
        cp "$XRC" "$XRC.bak"
    fi

    if ! grep -q "BEGIN RPI MOUSE FIX" "$XRC" 2>/dev/null; then
        cat >> "$XRC" <<'EOF'

# BEGIN RPI MOUSE FIX
if command -v xinput >/dev/null 2>&1; then
    for id in $(xinput --list --id-only 2>/dev/null); do
        xinput --set-prop "$id" "libinput Accel Profile Enabled" 1 0 >/dev/null 2>&1 || true
        xinput --set-prop "$id" "libinput Accel Speed" 0.6 >/dev/null 2>&1 || true
    done
fi
# END RPI MOUSE FIX
EOF
    fi

    if command -v xinput >/dev/null 2>&1; then
        for id in $(xinput --list --id-only 2>/dev/null); do
            xinput --set-prop "$id" "libinput Accel Profile Enabled" 1 0 >/dev/null 2>&1 || true
            xinput --set-prop "$id" "libinput Accel Speed" 0.6 >/dev/null 2>&1 || true
        done
        echo "Настройки применены."
    else
        echo "Не найден xinput. Настройки сохранены для следующего входа."
    fi

else
    echo ""
    echo "[2/3] Графическая среда не определена."
    echo "USB-настройки применены, настройки мыши пропущены."
fi

echo ""
echo "[3/3] ГОТОВО!"
echo ""
echo "Скорость мыши: $SPEED"
echo "Профиль ускорения: adaptive"
echo "USB autosuspend: OFF для обнаруженных HID"
echo ""
echo "Для Wayland рекомендуется перезайти в систему."
SCRIPT

chmod +x ~/fix-mouse.sh
~/fix-mouse.sh