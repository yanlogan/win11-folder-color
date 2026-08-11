#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Recolor default Windows 11/10 folder icons system-wide (including Medium / Large / Tiles / Content).

.DESCRIPTION
  Patches C:\Windows\SystemResources\imageres.dll.mun icon groups used for folder glyphs
  and folder thumbnails. Also sets Explorer Shell Icons as a fallback for small views.

  Requires Resource Hacker (freeware): https://angusj.com/resourcehacker/

.PARAMETER Color
  Target folder color as #RRGGBB (default #800000 maroon).

.PARAMETER IconPath
  Optional existing .ico to use instead of recoloring the system folder icon.

.PARAMETER Restore
  Restore the original imageres.dll.mun from backup and clear Shell Icons overrides.

.PARAMETER SkipShellIcons
  Do not write HKLM Shell Icons values 3/4.

.PARAMETER WorkDir
  Working directory for backups and temp files (default: %LOCALAPPDATA%\win11-folder-color).

.EXAMPLE
  .\Set-FolderColor.ps1 -Color '#800000'

.EXAMPLE
  .\Set-FolderColor.ps1 -IconPath 'C:\Icons\my-folder.ico'

.EXAMPLE
  .\Set-FolderColor.ps1 -Restore
#>
[CmdletBinding(DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Apply')]
    [ValidatePattern('^#?[0-9A-Fa-f]{6}$')]
    [string]$Color = '#800000',

    [Parameter(ParameterSetName = 'Apply')]
    [string]$IconPath,

    [Parameter(ParameterSetName = 'Restore', Mandatory = $true)]
    [switch]$Restore,

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$SkipShellIcons,

    [string]$WorkDir = $(Join-Path $env:LOCALAPPDATA 'win11-folder-color'),

    [string]$ResourceHacker = $(
        @(
            "${env:ProgramFiles(x86)}\Resource Hacker\ResourceHacker.exe",
            "$env:ProgramFiles\Resource Hacker\ResourceHacker.exe",
            "$PSScriptRoot\tools\ResourceHacker.exe"
        ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Icon groups that affect default / thumbnail folder looks on modern Windows.
$FolderIconGroups = @(3, 4, 5, 6, 162, 174)
$ImageresMun = Join-Path $env:SystemRoot 'SystemResources\imageres.dll.mun'
$AdminSidGrant = '*S-1-5-32-544:(F)'

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated PowerShell (Run as administrator).'
    }
}

function Resolve-ColorRgb([string]$Hex) {
    $h = $Hex.Trim().TrimStart('#')
    return [pscustomobject]@{
        R = [Convert]::ToInt32($h.Substring(0, 2), 16)
        G = [Convert]::ToInt32($h.Substring(2, 2), 16)
        B = [Convert]::ToInt32($h.Substring(4, 2), 16)
        Hex = '#' + $h.ToUpperInvariant()
    }
}

function Invoke-ResourceHacker {
    param(
        [Parameter(Mandatory)][string]$Open,
        [Parameter(Mandatory)][string]$Save,
        [Parameter(Mandatory)][string]$Action,
        [string]$Res,
        [Parameter(Mandatory)][string]$Mask,
        [string]$LogPath
    )
    if (-not $ResourceHacker -or -not (Test-Path -LiteralPath $ResourceHacker)) {
        throw @"
Resource Hacker not found.
Install from https://angusj.com/resourcehacker/
or place ResourceHacker.exe next to this script under .\tools\
"@
    }
    if (-not $LogPath) {
        $LogPath = Join-Path $WorkDir ("rh-{0}.log" -f [guid]::NewGuid().ToString('N'))
    }
    $args = @(
        '-open', $Open,
        '-save', $Save,
        '-action', $Action,
        '-mask', $Mask,
        '-log', $LogPath
    )
    if ($Res) { $args = @('-open', $Open, '-save', $Save, '-action', $Action, '-res', $Res, '-mask', $Mask, '-log', $LogPath) }

    $p = Start-Process -FilePath $ResourceHacker -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $Save)) {
        throw "Resource Hacker failed (exit $($p.ExitCode)). See log: $LogPath"
    }
    if (-not (Test-Path -LiteralPath $Save)) {
        throw "Resource Hacker did not produce: $Save (log: $LogPath)"
    }
}

function Get-IcoPngFrames([string]$IcoPath) {
    $bytes = [IO.File]::ReadAllBytes($IcoPath)
    if ($bytes.Length -lt 6) { throw "Invalid ICO: $IcoPath" }
    $type = [BitConverter]::ToUInt16($bytes, 2)
    $count = [BitConverter]::ToUInt16($bytes, 4)
    if ($type -ne 1 -or $count -lt 1) { throw "Not a valid ICO icon file: $IcoPath" }

    $frames = New-Object System.Collections.Generic.List[byte[]]
    for ($i = 0; $i -lt $count; $i++) {
        $entry = 6 + ($i * 16)
        $size = [BitConverter]::ToUInt32($bytes, $entry + 8)
        $offset = [BitConverter]::ToUInt32($bytes, $entry + 12)
        $payload = New-Object byte[] $size
        [Array]::Copy($bytes, [int]$offset, $payload, 0, [int]$size)
        if ($payload.Length -lt 8 -or $payload[0] -ne 0x89 -or $payload[1] -ne 0x50) {
            return $null
        }
        [void]$frames.Add($payload)
    }
    return , $frames.ToArray()
}

function Get-IconSizedPngs([string]$IcoPath, [int[]]$Sizes = @(16, 32, 48, 64, 128, 256)) {
    $out = New-Object System.Collections.Generic.List[byte[]]
    foreach ($s in $Sizes) {
        $icon = $null
        $bmp = $null
        $g = $null
        $ms = $null
        try {
            $icon = New-Object Drawing.Icon($IcoPath, $s, $s)
            $bmp = New-Object Drawing.Bitmap $s, $s, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [Drawing.Graphics]::FromImage($bmp)
            $g.Clear([Drawing.Color]::Transparent)
            $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.DrawIcon($icon, (New-Object Drawing.Rectangle 0, 0, $s, $s))
            $ms = New-Object IO.MemoryStream
            $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
            [void]$out.Add($ms.ToArray())
        }
        finally {
            if ($g) { $g.Dispose() }
            if ($bmp) { $bmp.Dispose() }
            if ($icon) { $icon.Dispose() }
            if ($ms) { $ms.Dispose() }
        }
    }
    return , $out.ToArray()
}

function Write-IcoFromPngs([string]$Path, [byte[][]]$Pngs) {
    $count = $Pngs.Count
    $headerSize = 6 + (16 * $count)
    $offset = $headerSize
    $offsets = New-Object int[] $count
    for ($i = 0; $i -lt $count; $i++) {
        $offsets[$i] = $offset
        $offset += $Pngs[$i].Length
    }

    $fs = [IO.File]::Create($Path)
    $bw = New-Object IO.BinaryWriter($fs)
    try {
        $bw.Write([uint16]0)
        $bw.Write([uint16]1)
        $bw.Write([uint16]$count)
        for ($i = 0; $i -lt $count; $i++) {
            $ms = New-Object IO.MemoryStream(, $Pngs[$i])
            $bmp = New-Object Drawing.Bitmap $ms
            try {
                $w = if ($bmp.Width -ge 256) { [byte]0 } else { [byte]$bmp.Width }
                $h = if ($bmp.Height -ge 256) { [byte]0 } else { [byte]$bmp.Height }
                $bw.Write($w)
                $bw.Write($h)
                $bw.Write([byte]0)
                $bw.Write([byte]0)
                $bw.Write([uint16]1)
                $bw.Write([uint16]32)
                $bw.Write([uint32]$Pngs[$i].Length)
                $bw.Write([uint32]$offsets[$i])
            }
            finally {
                $bmp.Dispose()
                $ms.Dispose()
            }
        }
        foreach ($png in $Pngs) { $bw.Write($png) }
    }
    finally {
        $bw.Close()
        $fs.Close()
    }
}

function Recolor-Bitmap([Drawing.Bitmap]$Bmp, $Target) {
    $rect = New-Object Drawing.Rectangle 0, 0, $Bmp.Width, $Bmp.Height
    $data = $Bmp.LockBits($rect, [Drawing.Imaging.ImageLockMode]::ReadWrite, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride = $data.Stride
        $len = $stride * $Bmp.Height
        $bytes = New-Object byte[] $len
        [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $len)

        $tr = [double]$Target.R
        $tg = [double]$Target.G
        $tb = [double]$Target.B
        # Approximate lightness of solid target color for ramp midpoint.
        $targetL = (0.299 * $tr + 0.587 * $tg + 0.114 * $tb) / 255.0
        if ($targetL -lt 0.05) { $targetL = 0.05 }

        for ($y = 0; $y -lt $Bmp.Height; $y++) {
            $row = $y * $stride
            for ($x = 0; $x -lt $Bmp.Width; $x++) {
                $i = $row + ($x * 4)
                $b = [int]$bytes[$i]
                $g = [int]$bytes[$i + 1]
                $r = [int]$bytes[$i + 2]
                $a = [int]$bytes[$i + 3]
                if ($a -eq 0) { continue }

                $max = [Math]::Max($r, [Math]::Max($g, $b))
                $min = [Math]::Min($r, [Math]::Min($g, $b))
                # Keep near-gray shadows / edges.
                if (($max - $min) -lt 14) { continue }

                $L = (0.299 * $r + 0.587 * $g + 0.114 * $b) / 255.0
                if ($L -le $targetL) {
                    $t = $L / $targetL
                    $nr = [int][Math]::Round($tr * $t)
                    $ng = [int][Math]::Round($tg * $t)
                    $nb = [int][Math]::Round($tb * $t)
                }
                else {
                    $t = [Math]::Min(1.0, ($L - $targetL) / [Math]::Max(0.01, 1.0 - $targetL))
                    # Lift toward a lighter tint of the same hue family.
                    $nr = [int][Math]::Round($tr + (255 - $tr) * $t * 0.55)
                    $ng = [int][Math]::Round($tg + (255 - $tg) * $t * 0.55)
                    $nb = [int][Math]::Round($tb + (255 - $tb) * $t * 0.55)
                }

                $bytes[$i] = [byte][Math]::Min(255, [Math]::Max(0, $nb))
                $bytes[$i + 1] = [byte][Math]::Min(255, [Math]::Max(0, $ng))
                $bytes[$i + 2] = [byte][Math]::Min(255, [Math]::Max(0, $nr))
            }
        }

        [Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $len)
    }
    finally {
        $Bmp.UnlockBits($data)
    }
}

function Convert-PngBytesToBitmap([byte[]]$PngBytes) {
    $tmp = Join-Path $WorkDir ("frame-{0}.png" -f [guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllBytes($tmp, $PngBytes)
    $src = [Drawing.Bitmap]::FromFile($tmp)
    try {
        $canvas = New-Object Drawing.Bitmap $src.Width, $src.Height, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [Drawing.Graphics]::FromImage($canvas)
        try { $g.DrawImage($src, 0, 0, $src.Width, $src.Height) }
        finally { $g.Dispose() }
        return $canvas
    }
    finally {
        $src.Dispose()
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function New-RecoloredIcon([string]$SourceIco, [string]$DestIco, $Target) {
    $pngFrames = Get-IcoPngFrames $SourceIco
    if ($null -eq $pngFrames) {
        Write-Host '    Stock icon is not PNG-based; rasterizing via GDI...' -ForegroundColor DarkYellow
        $pngFrames = Get-IconSizedPngs $SourceIco
    }
    # PowerShell may unwrap a single-element byte[][] into byte[]
    if ($pngFrames -is [byte[]]) {
        $pngFrames = , $pngFrames
    }

    $out = New-Object System.Collections.Generic.List[byte[]]
    foreach ($png in $pngFrames) {
        $canvas = Convert-PngBytesToBitmap $png
        try {
            Recolor-Bitmap $canvas $Target
            $ms = New-Object IO.MemoryStream
            $canvas.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
            [void]$out.Add($ms.ToArray())
            $ms.Dispose()
        }
        finally { $canvas.Dispose() }
    }
    Write-IcoFromPngs $DestIco ($out.ToArray())
}

function Grant-MunAccess([string]$Path) {
    & takeown.exe /F $Path /A | Out-Null
    & icacls.exe $Path /grant $AdminSidGrant | Out-Null
    & icacls.exe $Path /grant ("{0}:(F)" -f $env:USERNAME) | Out-Null
}

function Stop-ExplorerShell {
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($n in @('ShellExperienceHost', 'StartMenuExperienceHost', 'SearchHost')) {
        Get-Process $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

function Clear-IconCaches {
    Remove-Item (Join-Path $env:LOCALAPPDATA 'IconCache.db') -Force -ErrorAction SilentlyContinue
    $exp = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    Get-ChildItem $exp -Filter 'iconcache*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem $exp -Filter 'thumbcache*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

function Set-ShellIcons([string]$Ico) {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'
    if (-not (Test-Path $key)) { New-Item $key -Force | Out-Null }
    New-ItemProperty -Path $key -Name '3' -PropertyType String -Value $Ico -Force | Out-Null
    New-ItemProperty -Path $key -Name '4' -PropertyType String -Value $Ico -Force | Out-Null
}

function Clear-ShellIcons {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'
    if (Test-Path $key) {
        Remove-ItemProperty -Path $key -Name '3', '4' -ErrorAction SilentlyContinue
    }
}

function Install-Mun([string]$PatchedMun, [string]$BackupMun) {
    if (-not (Test-Path -LiteralPath $ImageresMun)) {
        throw "Missing system file: $ImageresMun"
    }

    $dir = Split-Path $ImageresMun -Parent
    Grant-MunAccess $ImageresMun
    & takeown.exe /F $dir /A | Out-Null
    & icacls.exe $dir /grant '*S-1-5-32-544:(OI)(CI)F' | Out-Null

    if (-not (Test-Path -LiteralPath $BackupMun)) {
        Copy-Item -LiteralPath $ImageresMun -Destination $BackupMun -Force
        Write-Step "Backup saved: $BackupMun"
    }

    Stop-ExplorerShell

    $renamed = Join-Path $dir 'imageres.dll.mun.precolor_backup'
    if (Test-Path -LiteralPath $ImageresMun) {
        if (Test-Path -LiteralPath $renamed) {
            Remove-Item -LiteralPath $renamed -Force -ErrorAction SilentlyContinue
        }
        Rename-Item -LiteralPath $ImageresMun -NewName 'imageres.dll.mun.precolor_backup' -Force
    }

    try {
        Copy-Item -LiteralPath $PatchedMun -Destination $ImageresMun -Force
    }
    catch {
        if (Test-Path -LiteralPath $renamed) {
            Rename-Item -LiteralPath $renamed -NewName 'imageres.dll.mun' -Force
        }
        throw
    }

    # Keep a second on-disk original name if rename backup exists; prefer WorkDir backup as source of truth.
    if ((Test-Path -LiteralPath $renamed) -and -not (Test-Path -LiteralPath $BackupMun)) {
        Copy-Item -LiteralPath $renamed -Destination $BackupMun -Force
    }
}

function Restore-Mun([string]$BackupMun) {
    if (-not (Test-Path -LiteralPath $BackupMun)) {
        $alt = Join-Path (Split-Path $ImageresMun -Parent) 'imageres.dll.mun.precolor_backup'
        if (Test-Path -LiteralPath $alt) { $BackupMun = $alt }
        else { throw "No backup found at $BackupMun" }
    }

    $dir = Split-Path $ImageresMun -Parent
    & takeown.exe /F $dir /A | Out-Null
    & icacls.exe $dir /grant '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if (Test-Path -LiteralPath $ImageresMun) {
        Grant-MunAccess $ImageresMun
    }

    Stop-ExplorerShell
    if (Test-Path -LiteralPath $ImageresMun) {
        Rename-Item -LiteralPath $ImageresMun -NewName 'imageres.dll.mun.colored_removed' -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $ImageresMun) {
            throw "Could not replace locked file: $ImageresMun"
        }
    }
    Copy-Item -LiteralPath $BackupMun -Destination $ImageresMun -Force
}

# -------------------- main --------------------
Assert-Admin
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$backupMun = Join-Path $WorkDir 'imageres.dll.mun.original'
$stableIco = Join-Path $WorkDir 'folder-colored.ico'

if ($Restore) {
    Write-Step 'Restoring original folder icons...'
    Restore-Mun -BackupMun $backupMun
    Clear-ShellIcons
    # Ensure thumbnails are allowed again.
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name IconsOnly -Type DWord -Value 0 -Force
    Clear-IconCaches
    Start-Process explorer
    Write-Host 'Restored. If icons look wrong, sign out/in once.' -ForegroundColor Green
    return
}

$rgb = Resolve-ColorRgb $Color
Write-Step ("Target color {0} (R={1} G={2} B={3})" -f $rgb.Hex, $rgb.R, $rgb.G, $rgb.B)

if ($IconPath) {
    if (-not (Test-Path -LiteralPath $IconPath)) { throw "Icon not found: $IconPath" }
    Copy-Item -LiteralPath $IconPath -Destination $stableIco -Force
    Write-Step "Using provided icon: $IconPath"
}
else {
    Write-Step 'Extracting stock folder icon from imageres.dll.mun...'
    if (-not (Test-Path -LiteralPath $ImageresMun)) { throw "Missing $ImageresMun" }
    $workDll = Join-Path $WorkDir 'imageres.work.dll'
    Copy-Item -LiteralPath $(if (Test-Path $backupMun) { $backupMun } else { $ImageresMun }) -Destination $workDll -Force
    $stockIco = Join-Path $WorkDir 'stock-folder.ico'
    Invoke-ResourceHacker -Open $workDll -Save $stockIco -Action extract -Mask 'ICONGROUP,3,'
    Write-Step 'Recoloring extracted icon...'
    New-RecoloredIcon -SourceIco $stockIco -DestIco $stableIco -Target $rgb
}

Write-Step 'Building patched imageres.dll.mun...'
$step = Join-Path $WorkDir 'step0.dll'
Copy-Item -LiteralPath $(if (Test-Path $backupMun) { $backupMun } else { $ImageresMun }) -Destination $step -Force
$prev = 0
foreach ($id in $FolderIconGroups) {
    $next = $prev + 1
    $in = Join-Path $WorkDir ("step{0}.dll" -f $prev)
    $out = Join-Path $WorkDir ("step{0}.dll" -f $next)
    Write-Host ("    ICONGROUP {0}" -f $id)
    Invoke-ResourceHacker -Open $in -Save $out -Action addoverwrite -Res $stableIco -Mask ("ICONGROUP,{0}," -f $id)
    $prev = $next
}
$patched = Join-Path $WorkDir 'imageres.dll.mun.patched'
Copy-Item -LiteralPath (Join-Path $WorkDir ("step{0}.dll" -f $prev)) -Destination $patched -Force

Write-Step 'Installing patched mun (Explorer will restart)...'
Install-Mun -PatchedMun $patched -BackupMun $backupMun

if (-not $SkipShellIcons) {
    Write-Step 'Setting Shell Icons fallback (3/4)...'
    Set-ShellIcons -Ico $stableIco
}

# Keep real thumbnails for files; mun patch covers folder medium/tiles/content.
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name IconsOnly -Type DWord -Value 0 -Force

Clear-IconCaches
Start-Process explorer
Start-Sleep -Seconds 1
Start-Process (Join-Path $env:SystemRoot 'System32\ie4uinit.exe') -ArgumentList '-show' -WindowStyle Hidden -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("Done. Default folders should now be {0}." -f $rgb.Hex) -ForegroundColor Green
Write-Host "Backup: $backupMun"
Write-Host 'Restore later:  .\Set-FolderColor.ps1 -Restore'
Write-Host 'Note: Feature updates may restore stock icons — re-run this script.'
