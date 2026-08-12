# win11-folder-color

Перекрашивает **дефолтные** иконки папок Windows 11 / Windows 10 на всю систему — включая виды **Таблица (Details), Средние, Крупные, Плитки (Tiles) и Содержимое (Content)** — и при этом оставляет обычные превью файлов (фото/видео).

Дополнительно ставит **цвет выделения** того же оттенка:
- фон выделения текста (`Hilight` / `HilightText`)
- рамка/заливка drag-выделения (`HotTrackingColor`)

Опционально (`-IncludeSystemAccent`) — ещё и системный accent (`AccentPalette` / Start / taskbar). **По умолчанию выключено**, потому что это перекрашивает меню Пуск и панель задач.
Классический трюк с реестром `Shell Icons` Windows игнорирует на medium+ видах: там рисуются **thumbnail папок** из `imageres.dll.mun`. Скрипт патчит этот файл (с бэкапом) и дополнительно прописывает `Shell Icons` как запасной вариант для мелких иконок.

![concept](https://img.shields.io/badge/Windows-11%20%2F%2010-blue) ![ps](https://img.shields.io/badge/PowerShell-5.1%2B-steelblue) ![license](https://img.shields.io/badge/license-MIT-green)

## Требования

- Windows 10 1903+ или Windows 11 (нужен `C:\Windows\SystemResources\imageres.dll.mun`)
- PowerShell **от администратора**
- Установленный [Resource Hacker](https://angusj.com/resourcehacker/)  
  (или положите `ResourceHacker.exe` в `.\tools\`)  
  **Не нужен** для режима `-SelectionOnly`

> Resource Hacker — freeware от Angus Johnson. Этот репозиторий его **не распространяет**.

## Быстрый старт

```powershell
# PowerShell от имени администратора
Set-ExecutionPolicy -Scope Process Bypass
cd path\to\win11-folder-color

# бордовый (по умолчанию): папки + выделение
.\Set-FolderColor.ps1

# любой цвет
.\Set-FolderColor.ps1 -Color '#C71313'
.\Set-FolderColor.ps1 -Color 1E90FF

# только выделение текста/marquee (без патча иконок и без Start/taskbar)
.\Set-FolderColor.ps1 -SelectionOnly -Color '#800000'

# то же + системный accent (Start/taskbar тоже перекрасятся)
.\Set-FolderColor.ps1 -SelectionOnly -Color '#800000' -IncludeSystemAccent

# папки без смены выделения
.\Set-FolderColor.ps1 -Color '#800000' -SkipSelection

# своя .ico (без перекраски)
.\Set-FolderColor.ps1 -IconPath 'D:\Icons\folder-blue.ico'

# вернуть сток (иконки + выделение)
.\Set-FolderColor.ps1 -Restore
```

Во время установки иконок Explorer один раз перезапустится.  
Для **выделения текста** часто нужен **выход из учётки / вход** (или перезагрузка).

## Что меняется

| Что | Зачем |
|------|--------|
| Группы иконок `3,4,5,6,162,174` в `imageres.dll.mun` | Дефолтные и thumbnail-иконки папок (medium / tiles / content) |
| `HKLM\...\Explorer\Shell Icons` значения `3` и `4` | Запасной вариант для мелких/списочных видов |
| `HKCU\Control Panel\Colors` → `Hilight`, `HilightText`, `HotTrackingColor` | Выделение текста и прямоугольник выделения |
| `HKCU\...\Explorer\Accent` + DWM accent (`-IncludeSystemAccent`) | Start / taskbar / рамки Explorer (опционально) |
| Бэкап в `%LOCALAPPDATA%\win11-folder-color\` | Оригинальный mun, `.ico`, `selection-colors.json` |

Скрипт выставляет `IconsOnly=0`, чтобы **превью фото и видео оставались включены**.

## После обновления Windows

Крупные обновления часто возвращают стоковые `.mun`. Просто запустите снова:

```powershell
.\Set-FolderColor.ps1 -Color '#800000'
```

Если после обновления иконки выглядят криво — сначала откат, потом снова цвет:

```powershell
.\Set-FolderColor.ps1 -Restore
.\Set-FolderColor.ps1 -Color '#800000'
```

## Важно по безопасности

- Патчится **системный ресурсный файл**. Бэкап создаётся автоматически — не удаляйте его.
- `sfc /scannow` или некоторые накопительные обновления могут откатить патч.
- Особые папки (Desktop, Downloads, OneDrive, свои иконки через `desktop.ini`) свои значки сохраняют.
- Лучше на личной машине; на корпоративных ПК смена владельца системных файлов может быть запрещена.
- На части сборок 24H2/25H2 после перезагрузки сток иногда возвращается — просто перезапустите скрипт.
- Не весь UI Win11 слушает классические `Hilight`/`HotTrackingColor` (UWP/WinUI часто живут своей жизнью).

## Как это работает

1. Копирует `imageres.dll.mun` (или сохранённый оригинальный бэкап).
2. Достаёт стоковую папку `ICONGROUP,3` через Resource Hacker.
3. Перекрашивает её в `-Color` (или берёт `-IconPath`).
4. Перезаписывает связанные группы иконок в рабочей копии.
5. Берёт ownership, переименовывает живой mun, ставит патч, чистит кэш иконок, перезапускает Explorer.
6. Пишет цвета выделения в реестр и сохраняет бэкап прежних значений.

## Ручной откат

При необходимости:

```powershell
# от администратора
$bak = "$env:LOCALAPPDATA\win11-folder-color\imageres.dll.mun.original"
$dst = "$env:SystemRoot\SystemResources\imageres.dll.mun"
# остановите Explorer в Диспетчере задач, затем:
Copy-Item $bak $dst -Force
```

Или просто: `.\Set-FolderColor.ps1 -Restore`.

## Лицензия

MIT — см. [LICENSE](LICENSE).

Windows® — товарный знак Microsoft Corporation. Проект не связан с Microsoft.
