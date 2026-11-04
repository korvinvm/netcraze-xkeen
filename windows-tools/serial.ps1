param([string]$Port = "COM4", [int]$Baud = 115200, [int]$Seconds = 8)
$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
$sp.ReadTimeout = 500
try { $sp.Open() } catch { "не открылся: $($_.Exception.Message)"; exit 1 }
"open $Port @ $Baud"
$end = (Get-Date).AddSeconds($Seconds)
$buf = New-Object System.Text.StringBuilder
while ((Get-Date) -lt $end) {
    try {
        $data = $sp.ReadExisting()
        if ($data) { [void]$buf.Append($data) }
    } catch { }
    Start-Sleep -Milliseconds 120
}
$sp.Close()
$text = $buf.ToString()
if ([string]::IsNullOrWhiteSpace($text)) { "тишина в порту" } else { $text }
