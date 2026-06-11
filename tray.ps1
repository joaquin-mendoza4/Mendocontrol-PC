# Icono en la bandeja del sistema: lanza server.ps1 oculto, lo vigila
# (lo reinicia si se cae) y permite ver la IP o salir desde el menu.
# Lanzar con start-tray.vbs para que no aparezca ninguna ventana.

param(
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Instancia unica: si ya hay un tray corriendo, salir en silencio.
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'MendocontrolTray', [ref]$created)
if (-not $created) { exit }

function Get-LanIP {
    try {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
            Sort-Object -Property { $_.IPAddress -notlike '192.168.*' } |
            Select-Object -First 1
        if ($ip) { return $ip.IPAddress }
    } catch {}
    return '127.0.0.1'
}

function Start-Server {
    return Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', (Join-Path $root 'server.ps1'), '-Port', $Port
    )
}

$script:server = Start-Server
$ip = Get-LanIP
$url = "http://${ip}:${Port}"

# Icono: circulo azul dibujado en memoria (sin archivos externos).
$bmp = New-Object System.Drawing.Bitmap 16, 16
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(47, 111, 235))
$g.FillEllipse($brush, 1, 1, 14, 14)
$g.Dispose()
$icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = $icon
$notify.Text = "Mendocontrol - $url"
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$miIp = $menu.Items.Add("Celular: $url")
$miIp.Add_Click({
    [System.Windows.Forms.MessageBox]::Show("Abri en el celular (misma red WiFi):`n`n$url", 'Mendocontrol') | Out-Null
})

$miOpen = $menu.Items.Add('Probar en este navegador')
$miOpen.Add_Click({ Start-Process $url })

[void]$menu.Items.Add('-')

$miExit = $menu.Items.Add('Salir')
$miExit.Add_Click({
    $script:timer.Stop()
    $notify.Visible = $false
    try { Stop-Process -Id $script:server.Id -Force -Confirm:$false } catch {}
    [System.Windows.Forms.Application]::Exit()
})

$notify.ContextMenuStrip = $menu
$notify.Add_DoubleClick({
    [System.Windows.Forms.MessageBox]::Show("Abri en el celular (misma red WiFi):`n`n$url", 'Mendocontrol') | Out-Null
})

# Vigila el server cada 5s y lo relanza si murio.
$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 5000
$script:timer.Add_Tick({
    if ($script:server.HasExited) {
        $script:server = Start-Server
        $notify.ShowBalloonTip(3000, 'Mendocontrol', 'El servidor se reinicio.', 'Warning')
    }
})
$script:timer.Start()

$notify.ShowBalloonTip(4000, 'Mendocontrol activo', "En el celular abri: $url", 'Info')

[System.Windows.Forms.Application]::Run()
