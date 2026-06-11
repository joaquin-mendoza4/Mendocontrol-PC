# Instala (o quita, con -Remove) el inicio automatico de Mendocontrol:
# crea un acceso directo en la carpeta Inicio del usuario que lanza
# start-tray.vbs, asi arranca oculto con solo el icono en la bandeja.
# Tambien intenta abrir el firewall para el server (TCP) y el
# descubrimiento de la APK (UDP); si no hay permisos de admin, avisa.

param(
    [switch]$Remove,
    [int]$Port = 8765
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'Mendocontrol.lnk'

if ($Remove) {
    if (Test-Path $lnkPath) {
        Remove-Item $lnkPath -Confirm:$false
        Write-Host 'Inicio automatico quitado.' -ForegroundColor Green
    } else {
        Write-Host 'No estaba instalado.' -ForegroundColor Yellow
    }
    exit
}

$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$lnk.Arguments = '"' + (Join-Path $root 'start-tray.vbs') + '"'
$lnk.WorkingDirectory = $root
$lnk.Description = 'Mendocontrol - controlar la PC desde el celular'
$lnk.Save()
Write-Host "Inicio automatico instalado: $lnkPath" -ForegroundColor Green

# Reglas de firewall (solo red privada). Requieren admin; si falla, avisar.
try {
    if (-not (Get-NetFirewallRule -DisplayName 'Mendocontrol TCP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'Mendocontrol TCP' -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Private -ErrorAction Stop | Out-Null
    }
    if (-not (Get-NetFirewallRule -DisplayName 'Mendocontrol UDP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'Mendocontrol UDP' -Direction Inbound -Protocol UDP -LocalPort 8766 -Action Allow -Profile Private -ErrorAction Stop | Out-Null
    }
    Write-Host 'Reglas de firewall listas (TCP servidor + UDP descubrimiento).' -ForegroundColor Green
} catch {
    Write-Host 'No se pudieron crear las reglas de firewall (ejecuta este script como administrador para eso).' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Para arrancar ahora sin reiniciar: doble clic en start-tray.vbs' -ForegroundColor Cyan
