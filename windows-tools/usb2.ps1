"=== COM порты ==="
$ports = Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue
if ($ports) { $ports | Select-Object Status, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String } else { "нет ни одного COM-порта" }

"=== проблемные / неизвестные устройства ==="
Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -ne "OK" -or $_.Class -eq "Unknown" -or $_.FriendlyName -match "USB|Serial|CH34|CP21|FT23|ESP" } |
    Select-Object Status, Class, FriendlyName, InstanceId |
    Format-Table -AutoSize -Wrap | Out-String

"=== все VID/PID на шине USB ==="
Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like "USB*" } |
    ForEach-Object { "{0,-38} {1}" -f $_.FriendlyName, ($_.InstanceId -replace '^USB\\',''  -replace '\\.*$','') } |
    Out-String
