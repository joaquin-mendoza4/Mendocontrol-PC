' Lanza tray.ps1 totalmente oculto (sin ventana de consola, ni siquiera un parpadeo).
Dim sh, dir
Set sh = CreateObject("WScript.Shell")
dir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "tray.ps1""", 0, False
