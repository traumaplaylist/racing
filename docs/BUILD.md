# Сборка и проверка

## Стек

- **Godot 4.5.1-stable** (`4.5.1.stable.official.f62fdbde1`), GDScript.
- Рендерер **Forward+** (Vulkan, на Windows откат на D3D12, затем на OpenGL 3.3, если Vulkan недоступен). Для будущего Android задан рендерер **Mobile** (`rendering_method.mobile`). SSAO, glow и цветокоррекция в Mobile и Compatibility отключаются сами.
- Шаблоны экспорта той же версии: `Godot_v4.5.1-stable_export_templates.tpz` с github.com/godotengine/godot/releases.
  Распаковать содержимое `templates/` в
  - Linux: `~/.local/share/godot/export_templates/4.5.1.stable/`
  - Windows: `%APPDATA%\Godot\export_templates\4.5.1.stable\`
  - нужны минимум `windows_release_x86_64.exe` и `version.txt`.

## Команды

```bash
tools/build_windows.sh
```

Скрипт проверяет версию движка, импортирует проект, гоняет автотесты правил и экспортирует
`build/windows/CanyonClash.exe` (PCK встроен в exe), затем пакует `build/CanyonClash-v0.1-windows-x86_64.zip`.

Тот же экспорт вручную:

```bash
godot --headless --import
godot --headless --export-release "Windows Desktop" build/windows/CanyonClash.exe
```

## Ассеты (Blender)

Модели и текстуры закоммичены, поэтому для сборки игры Blender не нужен. Пересобрать их:

```bash
uv venv -p 3.13 .venv-assets && VIRTUAL_ENV=.venv-assets uv pip install bpy==5.3.0 pillow
.venv-assets/bin/python tools/assets/gen_textures.py   # assets/textures/*.png
.venv-assets/bin/python tools/assets/make_cars.py      # assets/models/car_*.glb
.venv-assets/bin/python tools/assets/make_props.py     # assets/models/<prop>.glb
godot --headless --import
```

`bpy` — это Blender как Python-модуль, отдельная установка Blender не требуется. Просмотр моделей с игровыми материалами:
`godot res://tests/model_view.tscn -- --view=res://assets/models/car_buggy.glb`.

## Тесты

```bash
godot --headless res://tests/sim_test.tscn      # правила, оружие, бонусы, профиль; код выхода = число провалов
godot --headless res://tests/balance.tscn       # 12 заездов автопилота: исходы, время, урон
```

Тесты используют отдельный профиль `user://profile_test.json` и не трогают игровой.

## Отладочные флаги (только debug-сборки и редактор)

Передаются после `--`, в release-экспорте игнорируются (`OS.is_debug_build()`):

| Флаг | Что делает |
|---|---|
| `--debug-scene=race\|garage\|results` | Открыть экран сразу |
| `--debug-autopilot` | Машиной игрока управляет ИИ |
| `--debug-result=<reason>` | Фиктивный итог для экрана результатов (`finished_first`, `last_standing`, `rival_finished`, `destroyed`, `no_winner`, `timeout`) |
| `--debug-pause=<сек>` | Поставить паузу через N секунд |
| `--debug-shot=<сек>:<file.png>` | Сохранить скриншот и выйти |
| `--debug-profile=<имя>` | Изолированный профиль `user://profile_<имя>.json` |

Пример (скриншот заезда под Xvfb):

```bash
xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 -- --debug-scene=race --debug-autopilot --debug-shot=20:/tmp/race.png
```

## Структура

| Путь | Назначение |
|---|---|
| `scripts/config.gd` | Таблица баланса и правил: машины, оружие, бонусы, награды, улучшения |
| `scripts/track/track_data.gd` | Осевая линия трассы, проекция, контрольные точки (чистая математика) |
| `scripts/track/track_builder.gd` | Визуал каньона (заменяемый блокинг; правила его не используют) |
| `scripts/race/race_car.gd` | Аркадная модель машины: продольное и боковое сцепление, дрифт, реверс |
| `scripts/race/race_manager.gd` | Состояние гонки и порядок тика: команды → сброс → движение → столкновения → прогресс → оружие → бонусы → урон → финиши → выживший → итог |
| `scripts/race/bot_driver.gd` | ИИ: тот же набор команд, что у игрока |
| `scripts/autoload/game.gd` | Профиль, переходы между экранами, InputMap |
| `scripts/autoload/loc.gd`, `data/strings_en.json` | Строки интерфейса отдельно от логики |
| `scripts/ui/*` | HUD, гараж, результаты |
