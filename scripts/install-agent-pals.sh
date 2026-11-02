#!/usr/bin/env bash
# Ставит облик Agent Pals (Lottie-пак с UI8) туда, где его ищет маскот.
# Пак платный и в репозиторий не кладётся — только локально.
# Использование: scripts/install-agent-pals.sh путь/к/agent-pals-….zip [Бот]
#   Бот (по умолчанию Circle) сразу выбирается обликом в конфиге.
set -euo pipefail
ZIP="${1:?Укажи путь к zip пака Agent Pals}"
BOT="${2:-Circle}"
DEST="$HOME/Library/Application Support/AgentPulse/Skins/AgentPals"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

unzip -q "$ZIP" -d "$TMP"
PACK="$(find "$TMP" -type d -name "Lottie Pack" -print -quit)"
[[ -n "$PACK" ]] || { echo "В архиве нет папки «Lottie Pack»" >&2; exit 1; }

mkdir -p "$DEST"
# Только JSON-клипы: <Бот>/<Клип>.json. Исходник Figma и readme не нужны.
for dir in "$PACK"/*/; do
    bot="$(basename "$dir")"
    mkdir -p "$DEST/$bot"
    cp "$dir"*.json "$DEST/$bot/"
done
echo "Боты: $(ls "$DEST" | tr '\n' ' ')"

CONFIG="$HOME/Library/Application Support/AgentPulse/config.json"
if [[ -d "$DEST/$BOT" ]]; then
    /usr/bin/python3 - "$CONFIG" "agent-pals/$BOT" <<'PY'
import json, os, sys
path, skin = sys.argv[1], sys.argv[2]
config = json.load(open(path)) if os.path.exists(path) else {}
config.setdefault("mascot", {})["skin"] = skin
json.dump(config, open(path, "w"), ensure_ascii=False, indent=2)
PY
    echo "Облик: $BOT"
fi
