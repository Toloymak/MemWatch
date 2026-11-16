# MemWatch

[English](README.md) | **Русский**

Небольшое приложение для macOS в строке меню. Оно предупреждает о давлении памяти до того, как Mac начнёт тормозить или зависнет.

<!-- screenshot: docs/screenshot.png -->

## Зачем

Когда память заканчивается, macOS начинает тормозить и может зависнуть. Мониторинг системы (Activity Monitor) показывает проблему только тогда, когда она уже случилась. MemWatch работает в строке меню, заранее становится жёлтым или красным, отправляет уведомление и показывает, какие приложения используют больше всего памяти.

## Возможности

- Текст в строке меню `MEM NN%`. NN это `100 - kern.memorystatus_level`. Это собственная оценка заполненности памяти от ядра. Она не совпадает с "Memory Used" в Activity Monitor.
- Два уровня предупреждения: жёлтый (warning) и красный (critical).
- Уведомление, когда уровень растёт.
- Меню с цифрами по памяти, топ-10 приложений (процессы-помощники добавляются к своему приложению) и топ-5 отдельных процессов.
- Запуск при входе в систему.
- JSON-лог изменений уровня и самых больших потребителей памяти.
- Нет иконки в Dock. Нет внешних пакетов.

## Требования

- macOS 14 (Sonoma) или новее.
- Toolchain Swift 6 (Xcode 16 или новее, либо подходящие Command Line Tools).

## Скачать

MemWatch нет в магазине приложений. Готовое приложение можно скачать из GitHub Releases:

1. Откройте [Releases](https://github.com/Toloymak/MemWatch/releases) и скачайте `MemWatch-<версия>.zip`.
2. Распакуйте его.
3. Перенесите `MemWatch.app` в `/Applications` (или в `~/Applications`).

Приложение подписано ad-hoc и не нотаризовано, поэтому macOS Gatekeeper блокирует первый запуск. Чтобы открыть его, нажмите на `MemWatch.app` правой кнопкой мыши, выберите Open (Открыть) и ещё раз нажмите Open. Или снимите флаг карантина в Терминале:

```bash
xattr -dr com.apple.quarantine /Applications/MemWatch.app
```

Приложение универсальное: оно работает на Mac с Apple silicon и с Intel.

## Установка

Чтобы собрать его самому из исходников:

```bash
git clone https://github.com/Toloymak/MemWatch.git
cd MemWatch
Scripts/bundle.sh
open ~/Applications/MemWatch.app
```

`Scripts/bundle.sh` собирает release-бинарник, создаёт `build/MemWatch.app`, подписывает его ad-hoc и копирует в `~/Applications/MemWatch.app`. Если MemWatch уже запущен, скрипт сначала попросит его закрыться.

Только сборка, без app-бандла: `swift build -c release`.

Чтобы собрать `build/MemWatch.app`, не закрывая и не заменяя установленное приложение, запустите `Scripts/bundle.sh --no-install` (или задайте `MEMWATCH_NO_INSTALL=1`). Версию приложения задаёт `MEMWATCH_VERSION`, например `MEMWATCH_VERSION=0.2.0 Scripts/bundle.sh`. По умолчанию `0.1.0`.

Первый запуск:

- macOS спросит разрешение на уведомления. Нажмите Allow (Разрешить). Потом это можно поменять в System Settings > Notifications > MemWatch.
- Чтобы MemWatch запускался при входе в систему, откройте его меню и включите "Launch at Login".

## Использование

### Строка меню

| Состояние | Что вы видите |
|---|---|
| Норма | `MEM 52%` обычным цветом строки меню |
| Предупреждение | жёлтая точка перед текстом: `● MEM 72%` |
| Критический | весь текст красный и жирный |

### Меню

- Уровень, с причиной, если он не норма.
- Давление ядра, свободный уровень, App / Wired / Compressed / Cached files, использовано из общего объёма RAM.
- Занятый и общий swap, рост swap, swapouts и рост сжатой памяти.
- Топ приложений и топ процессов. Нажмите на строку, чтобы открыть Activity Monitor.
- "Open Activity Monitor", уведомления вкл/выкл, "Launch at Login", "Send Test Notification", "Quit".

### Флаги командной строки

Запускайте их из бинарника: `.build/release/MemWatch` или
`~/Applications/MemWatch.app/Contents/MacOS/MemWatch`.

| Флаг | Что делает |
|---|---|
| `--status` | Делает два замера с интервалом 2 секунды, печатает цифры, уровень и топ приложений, и выходит. |
| `--test-notify` | Отправляет одно тестовое уведомление и ждёт результат до 20 секунд. |
| `--login-item status\|on\|off` | Показывает, включает или выключает запуск при входе. По умолчанию `status`. |

Запускайте `--test-notify` и `--login-item` из бинарника внутри `.app`, потому что им нужен bundle id `local.memwatch`.

Пример вывода `--status` (цифры выдуманные):

```
MemWatch status  2026-01-15T10:30:00Z
Level:         NORMAL  (raw, no hysteresis)
Pressure:      1 (normal)   kern.memorystatus_vm_pressure_level
Free level:    48%   kern.memorystatus_level
RAM:           16.0 GB, page size 16384
App memory:    6.1 GB
Wired:         2.3 GB
Compressed:    1.4 GB  (holds 3.2 GB of data)
Cached files:  4.0 GB
Memory used:   9.8 GB  (App + Wired + Compressed)
Swap:          used 1.2 GB / total 3.0 GB, free 1.8 GB
Processes:     612 pids, 540 read, 72 not allowed (root, EPERM)
Top apps:
   1. Google Chrome                              3.1 GB  (24 procs)
   2. Xcode                                      2.4 GB  (6 procs)
   3. Docker                                     1.8 GB  (4 procs)
   4. Slack                                      0.9 GB  (7 procs)
Top processes:
   1. Google Chrome Helper (Renderer)            0.8 GB  pid 4121
   2. Xcode                                      0.7 GB  pid 3010
```

Некоторые строки здесь сокращены.

## Как работают уровни

Уровень зависит от числа в строке меню, `NN = 100 - kern.memorystatus_level`.

- **Critical** (красный): `NN >= 80`, или уровень давления ядра равен 4.
- **Warning** (жёлтый): `NN >= 70`.
- **Normal**: всё остальное.

Скорость swap, swapouts и сжатой памяти показывается в меню и в `--status`. На уровень они не влияют.

Переход вверх происходит сразу. Переход вниз требует 2 более низких замера подряд (минимум 5 секунд).

Уведомления отправляются, когда уровень растёт:

- Warning: не чаще одного раза в 15 минут.
- Critical: не чаще одного раза в 3 минуты. Пока память остаётся критической, уведомление повторяется каждые 3 минуты и сопровождается звуком.
- Уведомления можно выключить в меню.

Чтобы поменять пороги, отредактируйте `Thresholds.warningUsedPercent` и
`Thresholds.criticalUsedPercent` в файле `Sources/MemWatch/LevelEvaluator.swift`
(паузы между уведомлениями тоже там). Потом снова запустите `Scripts/bundle.sh`.

### Как отправляются уведомления

1. `UNUserNotificationCenter`, если вы разрешили уведомления в System Settings > Notifications > MemWatch.
2. Если уведомления не разрешены или произошла ошибка, MemWatch использует `osascript display notification`. macOS показывает такие уведомления от имени "Script Editor". Если вы отключили уведомления для Script Editor, вы их не увидите.

### Запуск при входе

Пункт меню использует `SMAppService.mainApp`. Если это не сработало, MemWatch записывает LaunchAgent
(`~/Library/LaunchAgents/local.memwatch.plist`), который открывает приложение.

## Как считаются цифры памяти

MemWatch делает замер каждые 3 секунды, а также сразу при событии давления памяти от ядра.

- Давление и свободный уровень: `sysctl kern.memorystatus_vm_pressure_level` и `kern.memorystatus_level`.
- App, Wired, Compressed и Cached files: `host_statistics64` (`internal_page_count - purgeable_count`, `wire_count`, `compressor_page_count`, `external_page_count + purgeable_count`).
- Swap: `sysctl vm.swapusage`.
- Самые большие потребители: `proc_pid_rusage`, поле `ri_phys_footprint`, для каждого процесса. Это колонка "Memory" в Activity Monitor.
- Группировка: процессы группируются по первому `.app` в пути к исполняемому файлу, поэтому "Google Chrome Helper (Renderer)" считается как "Google Chrome". У остальных процессов используется имя файла.

## Ограничения и известные проблемы

- Процессы, которыми владеет root (а также `kernel_task` и `WindowServer`), нельзя прочитать без sudo (`EPERM`). Они пропускаются и считаются как "not allowed". `sudo .build/release/MemWatch --status` может их прочитать.
- `phys_footprint` это не RSS. Он учитывает сжатые и выгруженные в swap страницы, поэтому совпадает с Activity Monitor, а не с `ps`. Сумма может быть больше объёма RAM.
- VM Docker показывается как `com.apple.Virtualization.VirtualMachine`, потому что она запускается из системного пути фреймворка, а не из `Docker.app`.
- macOS добавляет файлы swap при необходимости, поэтому "swap free" может уменьшаться и потом снова расти.
- Приложение подписано ad-hoc, оно не нотаризовано.

Файл лога: `~/Library/Logs/MemWatch.log`. Он в формате JSON lines и ротируется при достижении 5 MB.

## Удаление

1. Закройте MemWatch через его меню.
2. Сначала выключите "Launch at Login" в меню (или выполните `MemWatch --login-item off`).
3. Удалите `~/Applications/MemWatch.app`.
4. Удалите `~/Library/Logs/MemWatch.log`.
5. Если он есть, удалите `~/Library/LaunchAgents/local.memwatch.plist`.

## Выпуск релиза

Релизы делает GitHub Actions (`.github/workflows/release.yml`). Чтобы выпустить релиз, отправьте тег версии:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

Workflow собирает приложение, упаковывает его в zip и создаёт GitHub Release с zip-файлом и файлом `.sha256`. Тег с `-`, например `v0.2.0-beta.1`, создаёт prerelease. Workflow можно запустить и вручную на вкладке Actions. Тогда он только собирает zip и сохраняет его как артефакт workflow. Релиз при этом не создаётся.

## Лицензия

MIT. См. [LICENSE](LICENSE).
