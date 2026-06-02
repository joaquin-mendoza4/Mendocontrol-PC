# Controlar PC desde el celular - servidor PowerShell (sin dependencias).
# Sirve index.html y recibe ordenes por WebSocket para mover el mouse,
# hacer clic, scroll y apagar/reiniciar la PC.

param(
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Control del mouse via user32.dll ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Mouse {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004;
    public const uint RIGHTDOWN = 0x0008, RIGHTUP = 0x0010;
    public const uint WHEEL = 0x0800;
    public static void MoveRel(int dx, int dy) {
        POINT p; GetCursorPos(out p);
        SetCursorPos(p.X + dx, p.Y + dy);
    }
    public static void Click(bool right) {
        if (right) { mouse_event(RIGHTDOWN,0,0,0,UIntPtr.Zero); mouse_event(RIGHTUP,0,0,0,UIntPtr.Zero); }
        else { mouse_event(LEFTDOWN,0,0,0,UIntPtr.Zero); mouse_event(LEFTUP,0,0,0,UIntPtr.Zero); }
    }
    public static void LeftDown() { mouse_event(LEFTDOWN,0,0,0,UIntPtr.Zero); }
    public static void LeftUp()   { mouse_event(LEFTUP,0,0,0,UIntPtr.Zero); }
    public static void Scroll(int amount) { mouse_event(WHEEL,0,0,(uint)amount,UIntPtr.Zero); }
}
"@

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

function Read-Exact($stream, [int]$count) {
    $buf = New-Object byte[] $count
    $off = 0
    while ($off -lt $count) {
        $n = $stream.Read($buf, $off, $count - $off)
        if ($n -le 0) { return $null }
        $off += $n
    }
    return $buf
}

function Send-WsFrame($stream, [byte]$opcode, [byte[]]$payload) {
    if ($null -eq $payload) { $payload = New-Object byte[] 0 }
    $len = $payload.Length
    $header = New-Object System.Collections.Generic.List[byte]
    $header.Add([byte](0x80 -bor $opcode))
    if ($len -lt 126) {
        $header.Add([byte]$len)
    } elseif ($len -le 65535) {
        $header.Add(126); $header.Add([byte](($len -shr 8) -band 0xFF)); $header.Add([byte]($len -band 0xFF))
    } else {
        $header.Add(127)
        for ($i = 7; $i -ge 0; $i--) { $header.Add([byte](($len -shr ($i*8)) -band 0xFF)) }
    }
    $bytes = $header.ToArray()
    $stream.Write($bytes, 0, $bytes.Length)
    if ($len -gt 0) { $stream.Write($payload, 0, $len) }
    $stream.Flush()
}

function Handle-Message($json) {
    try { $msg = $json | ConvertFrom-Json } catch { return }
    switch ($msg.t) {
        'm' { [Win32Mouse]::MoveRel([int]$msg.x, [int]$msg.y) }
        'c' { [Win32Mouse]::Click($msg.b -eq 'r') }
        's' { [Win32Mouse]::Scroll(-([int]$msg.y) * 12) }
        'd' { if ([int]$msg.s -eq 1) { [Win32Mouse]::LeftDown() } else { [Win32Mouse]::LeftUp() } }
        'p' {
            if ($msg.a -eq 's') { Start-Process shutdown -ArgumentList '/s','/t','0' -WindowStyle Hidden }
            elseif ($msg.a -eq 'r') { Start-Process shutdown -ArgumentList '/r','/t','0' -WindowStyle Hidden }
        }
    }
}

function Handle-WebSocket($stream) {
    while ($true) {
        $h = Read-Exact $stream 2
        if ($null -eq $h) { return }
        $opcode = $h[0] -band 0x0F
        $masked = ($h[1] -band 0x80) -ne 0
        $len = $h[1] -band 0x7F
        if ($len -eq 126) {
            $e = Read-Exact $stream 2; if ($null -eq $e) { return }
            $len = ($e[0] -shl 8) -bor $e[1]
        } elseif ($len -eq 127) {
            $e = Read-Exact $stream 8; if ($null -eq $e) { return }
            $len = 0; for ($i = 0; $i -lt 8; $i++) { $len = ($len -shl 8) -bor $e[$i] }
        }
        $mask = $null
        if ($masked) { $mask = Read-Exact $stream 4; if ($null -eq $mask) { return } }
        $payload = $null
        if ($len -gt 0) {
            $payload = Read-Exact $stream $len
            if ($null -eq $payload) { return }
            if ($masked) { for ($i = 0; $i -lt $len; $i++) { $payload[$i] = $payload[$i] -bxor $mask[$i % 4] } }
        }
        switch ($opcode) {
            0x8 { try { Send-WsFrame $stream 0x8 $payload } catch {}; return }  # close
            0x9 { Send-WsFrame $stream 0xA $payload }  # ping -> pong
            0x1 {           # text
                if ($payload) {
                    $text = [System.Text.Encoding]::UTF8.GetString($payload)
                    Handle-Message $text
                }
            }
        }
    }
}

function Compute-AcceptKey($key) {
    $magic = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $hash = $sha1.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($key + $magic))
    return [Convert]::ToBase64String($hash)
}

function Send-Http($stream, [string]$status, [string]$contentType, [byte[]]$body) {
    $head = "HTTP/1.1 $status`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nConnection: close`r`nCache-Control: no-cache`r`n`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $stream.Write($hb, 0, $hb.Length)
    if ($body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
    $stream.Flush()
}

function Handle-Client($client) {
    try {
        $stream = $client.GetStream()
        # Read request headers (until blank line).
        $reqBytes = New-Object System.Collections.Generic.List[byte]
        $one = New-Object byte[] 1
        $headerText = ''
        while ($true) {
            $n = $stream.Read($one, 0, 1)
            if ($n -le 0) { return }
            $reqBytes.Add($one[0])
            if ($reqBytes.Count -ge 4) {
                $c = $reqBytes.Count
                if ($reqBytes[$c-4] -eq 13 -and $reqBytes[$c-3] -eq 10 -and $reqBytes[$c-2] -eq 13 -and $reqBytes[$c-1] -eq 10) { break }
            }
            if ($reqBytes.Count -gt 16384) { return }
        }
        $headerText = [System.Text.Encoding]::ASCII.GetString($reqBytes.ToArray())
        $lines = $headerText -split "`r`n"
        $requestLine = $lines[0]
        $path = ($requestLine -split ' ')[1]

        $wsKey = $null
        foreach ($l in $lines) {
            if ($l -match '^(?i)Sec-WebSocket-Key:\s*(.+)$') { $wsKey = $Matches[1].Trim() }
        }

        if ($wsKey -and ($path -eq '/ws')) {
            $accept = Compute-AcceptKey $wsKey
            $resp = "HTTP/1.1 101 Switching Protocols`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Accept: $accept`r`n`r`n"
            $rb = [System.Text.Encoding]::ASCII.GetBytes($resp)
            $stream.Write($rb, 0, $rb.Length); $stream.Flush()
            Write-Host "Celular conectado." -ForegroundColor Green
            Handle-WebSocket $stream
            Write-Host "Celular desconectado." -ForegroundColor Yellow
            return
        }

        # Serve the page.
        $file = Join-Path $root 'index.html'
        if (Test-Path $file) {
            $body = [System.IO.File]::ReadAllBytes($file)
            Send-Http $stream '200 OK' 'text/html; charset=utf-8' $body
        } else {
            $body = [System.Text.Encoding]::UTF8.GetBytes('index.html no encontrado')
            Send-Http $stream '404 Not Found' 'text/plain; charset=utf-8' $body
        }
    } catch {
        # Ignore per-connection errors.
    } finally {
        try { $client.Close() } catch {}
    }
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
$listener.Start()
$ip = Get-LanIP

Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host '   Controlar PC - servidor activo' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '  En tu celular (misma red WiFi) abri:' -ForegroundColor White
Write-Host ("     http://{0}:{1}" -f $ip, $Port) -ForegroundColor Green
Write-Host ''
Write-Host '  Para detener: cerra esta ventana o Ctrl+C' -ForegroundColor DarkGray
Write-Host ''

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $client.NoDelay = $true
        Handle-Client $client
    }
} finally {
    $listener.Stop()
}
