param([switch]$ValidationOnly)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$ruleName = if ($ValidationOnly) { 'OpenFlux.Test.IPv6.' + [guid]::NewGuid() } else { 'OpenFlux.Windows.IPv6' }
try {
    # Windows rejects the zero-length IPv6 prefix. Two /1 prefixes cover IPv6.
    $enabled = if ($ValidationOnly) { 'False' } else { 'True' }
    New-NetFirewallRule -Name $ruleName -DisplayName 'OpenFlux VPN IPv6 guard' -Direction Outbound -RemoteAddress '::/1','8000::/1' -Action Block -Enabled $enabled -ErrorAction Stop | Out-Null
    if ($ValidationOnly) {
        $rule = Get-NetFirewallRule -Name $ruleName
        $addresses = @($rule | Get-NetFirewallAddressFilter | Select-Object -ExpandProperty RemoteAddress)
        if ($rule.Enabled -ne 'False' -or $rule.Action -ne 'Block' -or $addresses.Count -ne 2) {
            throw 'IPv6 firewall validation failed'
        }
        Write-Output ('IPv6 firewall accepted: ' + ($addresses -join ', '))
    }
} finally {
    if ($ValidationOnly) {
        Remove-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    }
}
