param([string]$Port = "COM4", [int]$Baud = 115200, [int]$Seconds = 15)
$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
$sp.ReadTimeout = 500
$sp.DtrEnable = $false
$sp.RtsEnable = $false
try { $sp.Open() } catch { "не открылся: $($_.Exception.Message)"; exit 1 }
# аппаратный сброс ESP через линии DTR/RTS
$sp.DtrEnable = $false
$sp.RtsEnable = $true
Start-Sleep -Milliseconds 200
$sp.RtsEnable = $false
Start-Sleep -Milliseconds 100
"reset sent"
$end = (Get-Date).AddSeconds($Seconds)
$buf = New-Object System.Text.StringBuilder
while ((Get-Date) -lt $end) {
    try { $d = $sp.ReadExisting(); if ($d) { [void]$buf.Append($d) } } catch { }
    Start-Sleep -Milliseconds 100
}
$sp.Close()
$buf.ToString()
