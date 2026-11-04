$ErrorActionPreference = "SilentlyContinue"

"== до:"
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object InterfaceAlias, RouteMetric | Format-Table -AutoSize | Out-String

Stop-Service HappService -Force
Stop-Process -Name Happ, happd -Force
Start-Sleep -Seconds 3

# если остался мёртвый маршрут через его туннель — убираем
$bad = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.InterfaceAlias -like "*happ*" }
foreach ($r in $bad) {
    Remove-NetRoute -DestinationPrefix "0.0.0.0/0" -InterfaceIndex $r.InterfaceIndex -Confirm:$false
    "удалён маршрут через $($r.InterfaceAlias)"
}

$ad = Get-NetAdapter | Where-Object { $_.Name -like "*happ*" -and $_.Status -eq "Up" }
foreach ($a in $ad) {
    Disable-NetAdapter -Name $a.Name -Confirm:$false
    "отключён адаптер $($a.Name)"
}

"== после:"
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object InterfaceAlias, RouteMetric | Format-Table -AutoSize | Out-String
