# win11-folder-color

Recolor **default** Windows 11 / Windows 10 folder icons system-wide — including **Details, Medium, Large, Tiles, and Content** views — while keeping normal file thumbnails.

Windows ignores the classic `Shell Icons` registry trick for medium+ folder views because those views use **folder thumbnails** from `imageres.dll.mun`. This script patches that file (with a backup) and optionally sets `Shell Icons` as a small-icon fallback.

![concept](https://img.shields.io/badge/Windows-11%20%2F%2010-blue) ![ps](https://img.shields.io/badge/PowerShell-5.1%2B-steelblue) ![license](https://img.shields.io/badge/license-MIT-green)

## Requirements

- Windows 10 1903+ or Windows 11 (uses `C:\Windows\SystemResources\imageres.dll.mun`)
- **Administrator** PowerShell
- [Resource Hacker](https://angusj.com/resourcehacker/) installed  
  (or put `ResourceHacker.exe` in `.\tools\`)

> Resource Hacker is freeware by Angus Johnson. This repo does **not** redistribute it.

## Quick start

```powershell
# elevated PowerShell
Set-ExecutionPolicy -Scope Process Bypass
cd path\to\win11-folder-color

# maroon (default)
.\Set-FolderColor.ps1

# any color
.\Set-FolderColor.ps1 -Color '#C71313'
.\Set-FolderColor.ps1 -Color 1E90FF

# your own .ico (skips recolor)
.\Set-FolderColor.ps1 -IconPath 'D:\Icons\folder-blue.ico'

# restore stock icons
.\Set-FolderColor.ps1 -Restore
```

Explorer restarts once during install.

## What it changes

| Item | Purpose |
|------|---------|
| `imageres.dll.mun` icon groups `3,4,5,6,162,174` | Default + thumbnail folder glyphs (medium/tiles/content) |
| `HKLM\...\Explorer\Shell Icons` values `3` and `4` | Small/list fallback |
| Backup under `%LOCALAPPDATA%\win11-folder-color\` | Original mun + generated `.ico` |

It sets `IconsOnly=0` so **photo/video thumbnails stay enabled**.

## After Windows Update

Feature updates often restore stock `.mun` files. Re-run:

```powershell
.\Set-FolderColor.ps1 -Color '#800000'
```

If icons look wrong after an update, restore first, then apply again:

```powershell
.\Set-FolderColor.ps1 -Restore
.\Set-FolderColor.ps1 -Color '#800000'
```

## Safety notes

- Patches a **system resource file**. Always keep the backup (script creates one automatically).
- `sfc /scannow` or some cumulative updates may revert the patch.
- Special folders (Desktop, Downloads, OneDrive, custom `desktop.ini` icons) keep their own icons.
- Do this on a personal machine; company-managed PCs may block ownership changes.
- On some 24H2/25H2 builds, a reboot may rarely restore stock resources — just re-run the script.

## How it works

1. Copies `imageres.dll.mun` (or the saved original backup).
2. Extracts stock folder `ICONGROUP,3` with Resource Hacker.
3. Recolors that icon to `-Color` (or uses `-IconPath`).
4. Overwrites folder-related icon groups in a working copy.
5. Takes ownership, renames the live mun, installs the patched file, clears icon caches, restarts Explorer.

## Restore manually

If needed:

```powershell
# elevated
$bak = "$env:LOCALAPPDATA\win11-folder-color\imageres.dll.mun.original"
$dst = "$env:SystemRoot\SystemResources\imageres.dll.mun"
# stop Explorer from Task Manager, then:
Copy-Item $bak $dst -Force
```

Or use `.\Set-FolderColor.ps1 -Restore`.

## License

MIT — see [LICENSE](LICENSE).

Windows® is a trademark of Microsoft Corporation. This project is not affiliated with Microsoft.
