# Установка и подключение

Нужны macOS 14+ и Swift 6 (хватает Command Line Tools, Xcode не обязателен).

## Сборка

```bash
scripts/install.sh --login   # сборка → "/Applications/Agent Pulse.app", запуск при входе
```

`scripts/bundle.sh` только собирает `build/Agent Pulse.app`. Подпись — локальным сертификатом «Agent Pulse Local Signing», если он есть в связке ключей (иначе ad-hoc). Отладка состояний: `open "/Applications/Agent Pulse.app" --args --state sleep` (`idle`, `think`, `wait`).

Посмотреть маскота без настоящего агента: `scripts/demo-events.sh`. Тесты: `scripts/test.sh`.

## Claude Code

В меню-баре появится значок. «Установить хуки Claude Code…» добавит хуки в `~/.claude/settings.json` (с бэкапом рядом). Чужие хуки не трогаются; удаление возвращает файл к исходному виду.

## Claude в браузере

В меню «Подключить Claude в браузере…», затем `chrome://extensions` → «Режим разработчика» → «Загрузить распакованное» → открывшаяся папка `~/Library/Application Support/AgentPulse/ChromeExtension`.

## Figma

Меню → «Figma: показать плагин-компаньон», затем в Figma desktop: Plugins → Development → Import plugin from manifest… → выбрать `manifest.json`. Запускать плагин в файле, за которым нужно следить.

## Agent Pals

`scripts/install-agent-pals.sh путь/к/паку.zip`, затем «Настройки → Основное → Облик».

## Удаление

1. В меню маскота: «Настройки → Источники → Удалить хуки». Хуки снимутся из `~/.claude/settings.json` и из копий у Codex (`~/.codex/hooks.json`, аккаунты Codex в Orca), рядом останутся резервные копии `*.agentpulse-*.bak`.
2. «Подключить Claude в браузере» → «Отключить», затем удалить расширение в `chrome://extensions`.
3. Выйти из Agent Pulse и перетащить `/Applications/Agent Pulse.app` в Корзину.
4. Данные маскота (память дня, новости, оценки) — папка `~/Library/Application Support/AgentPulse`, её можно удалить.

Если приложение удалили, не сняв хуки, агенты не сломаются: команда хука сама завершается без ошибки, когда `pulse-hook` не найден.
