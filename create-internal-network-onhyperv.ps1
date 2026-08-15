#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$SwitchName = "Internal"
$HostIP     = "192.168.55.1"
$Prefix     = 24
$AdapterName = "vEthernet ($SwitchName)"

Write-Host "=== Hyper-V Internal Switch configuration ===" -ForegroundColor Cyan

# ------------------------------------------------------------
# 1. Hyper-V Internal Switch の確認・作成
# ------------------------------------------------------------

$VMSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue

if ($null -eq $VMSwitch) {

    Write-Host "Internal Switch '$SwitchName' を作成します..."

    New-VMSwitch `
        -Name $SwitchName `
        -SwitchType Internal | Out-Null

    Write-Host "Internal Switch を作成しました。" -ForegroundColor Green
}
else {

    if ($VMSwitch.SwitchType -ne "Internal") {
        throw "Switch '$SwitchName' はInternal Switchではありません。"
    }

    Write-Host "Internal Switch '$SwitchName' は既に存在します。" -ForegroundColor Yellow
}

# ------------------------------------------------------------
# 2. ホスト側仮想NICが作成されるまで少し待つ
# ------------------------------------------------------------

$MaxRetry = 10
$Retry = 0

while ($null -eq (Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue)) {

    if ($Retry -ge $MaxRetry) {
        throw "ホスト側NIC '$AdapterName' が見つかりません。"
    }

    Start-Sleep -Seconds 1
    $Retry++
}

$Adapter = Get-NetAdapter -Name $AdapterName

Write-Host "Host Adapter : $AdapterName"
Write-Host "Status       : $($Adapter.Status)"

# ------------------------------------------------------------
# 3. 現在のIPv4設定を確認
# ------------------------------------------------------------

$CurrentIPs = Get-NetIPAddress `
    -InterfaceAlias $AdapterName `
    -AddressFamily IPv4 `
    -ErrorAction SilentlyContinue

$TargetExists = $CurrentIPs | Where-Object {
    $_.IPAddress -eq $HostIP -and
    $_.PrefixLength -eq $Prefix
}

# ------------------------------------------------------------
# 4. 目的のIPが設定済みなら何もしない
# ------------------------------------------------------------

if ($TargetExists) {

    Write-Host ""
    Write-Host "既に目的のIPアドレスが設定されています。" -ForegroundColor Green
    Write-Host "$HostIP/$Prefix"

}
else {

    # --------------------------------------------------------
    # 5. 既存のIPv4アドレスを削除
    # --------------------------------------------------------

    if ($CurrentIPs) {

        Write-Host ""
        Write-Host "既存のIPv4アドレスを削除します..."

        foreach ($IP in $CurrentIPs) {

            Write-Host "  Remove: $($IP.IPAddress)/$($IP.PrefixLength)"

            Remove-NetIPAddress `
                -InterfaceIndex $Adapter.ifIndex `
                -IPAddress $IP.IPAddress `
                -Confirm:$false
        }
    }

    # --------------------------------------------------------
    # 6. 192.168.55.1/24 を設定
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "IPアドレスを設定します..."

    New-NetIPAddress `
        -InterfaceIndex $Adapter.ifIndex `
        -IPAddress $HostIP `
        -PrefixLength $Prefix `
        -AddressFamily IPv4 | Out-Null

    Write-Host "設定しました: $HostIP/$Prefix" -ForegroundColor Green
}

# ------------------------------------------------------------
# 7. 最終確認
# ------------------------------------------------------------

Write-Host ""
Write-Host "=== Configuration ===" -ForegroundColor Cyan

Get-NetIPAddress `
    -InterfaceAlias $AdapterName `
    -AddressFamily IPv4 |
    Select-Object InterfaceAlias, IPAddress, PrefixLength

Write-Host ""
Write-Host "完了しました。" -ForegroundColor Green
