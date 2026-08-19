#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ============================================================
# Configuration
# ============================================================

$ScriptName = Split-Path -Leaf $PSCommandPath

$DefaultSwitch = "Default Switch"
$InternalSwitch = "Internal"

# ============================================================
# Help
# ============================================================

function Show-Help {

    Write-Host ""
    Write-Host "============================================================"
    Write-Host " Hyper-V VM Network Configuration"
    Write-Host "============================================================"
    Write-Host ""

    Write-Host "Usage:"
    Write-Host ""
    Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptName`" <VMName>"
    Write-Host ""

    Write-Host "VMName:"
    Write-Host ""
    Write-Host "  NNN_文字列"
    Write-Host ""
    Write-Host "  NNN : 002～253"
    Write-Host "  '_' : 必須"
    Write-Host "  文字列 : 任意"
    Write-Host ""

    Write-Host "Examples:"
    Write-Host ""
    Write-Host "  $ScriptName 002_Ubuntu"
    Write-Host "  $ScriptName 024_ubuntu24"
    Write-Host "  $ScriptName 100_Windows"
    Write-Host "  $ScriptName 253_TestVM"
    Write-Host ""

    Write-Host "MAC address:"
    Write-Host ""
    Write-Host "  VM名の先頭3桁を10進数として解釈し、"
    Write-Host "  Internal NICのMACアドレス末尾1バイトに使用します。"
    Write-Host ""

    Write-Host "  002 -> 00-15-5D-10-00-02"
    Write-Host "  024 -> 00-15-5D-10-00-18"
    Write-Host "  100 -> 00-15-5D-10-00-64"
    Write-Host "  253 -> 00-15-5D-10-00-FD"
    Write-Host ""

    Write-Host "Network:"
    Write-Host ""
    Write-Host "  Default Switch"
    Write-Host "      -> Internet connection"
    Write-Host "      -> Dynamic MAC"
    Write-Host ""
    Write-Host "  Internal Switch"
    Write-Host "      -> Host / Guest internal communication"
    Write-Host "      -> Static MAC"
    Write-Host ""

    Write-Host "Prerequisites:"
    Write-Host ""
    Write-Host "  * Hyper-V"
    Write-Host "  * 'Internal' Hyper-V switch must already exist"
    Write-Host "  * VM must already exist"
    Write-Host ""

    Write-Host "Note:"
    Write-Host ""
    Write-Host "  Host-side vEthernet (Internal) IP configuration"
    Write-Host "  is NOT performed by this script."
    Write-Host ""

    Write-Host "============================================================"
    Write-Host ""
}


# ============================================================
# Argument validation
# ============================================================

if (
    $args.Count -eq 0 -or
    $args[0] -in @(
        "/?",
        "-?",
        "/h",
        "-h",
        "/help",
        "--help"
    )
) {
    Show-Help
    exit 0
}


if ($args.Count -ne 1) {

    Write-Host ""
    Write-Host "ERROR: 引数の数が正しくありません。" -ForegroundColor Red
    Write-Host ""

    Show-Help

    exit 2
}


$VMName = $args[0]


# ============================================================
# VM name validation
# ============================================================

if ($VMName -notmatch '^(?<Number>\d{3})_(?<Suffix>.+)$') {

    Write-Host ""
    Write-Host "ERROR: VM名の形式が正しくありません。" -ForegroundColor Red
    Write-Host ""
    Write-Host "指定されたVM名:"
    Write-Host "  $VMName"
    Write-Host ""
    Write-Host "正しい形式:"
    Write-Host "  NNN_文字列"
    Write-Host ""
    Write-Host "NNNは002～253です。"
    Write-Host ""

    exit 3
}


$Number = [int]$Matches.Number


if ($Number -lt 2 -or $Number -gt 253) {

    Write-Host ""
    Write-Host "ERROR: VM名の先頭3桁が範囲外です。" -ForegroundColor Red
    Write-Host ""
    Write-Host "指定された値: $($Matches.Number)"
    Write-Host "許可される範囲: 002～253"
    Write-Host ""

    exit 4
}


# ============================================================
# Generate MAC address
# ============================================================

$LastByte = $Number.ToString("X2")

# Hyper-V Microsoft OUI
$InternalMAC = "00155D1000$LastByte"

# 表示用
$DisplayMAC = ($InternalMAC -replace '(.{2})(?!$)', '$1-').TrimEnd("-")


# ============================================================
# Display configuration
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Hyper-V VM Network Configuration" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "VM Name      : $VMName"
Write-Host "Number       : $Number"
Write-Host "Internal MAC : $DisplayMAC"
Write-Host ""

# ============================================================
# VM existence check
# ============================================================

$VM = Get-VM -Name $VMName -ErrorAction SilentlyContinue

if ($null -eq $VM) {

    Write-Host "ERROR: VM '$VMName' が存在しません。" -ForegroundColor Red
    Write-Host ""

    exit 5
}


# ============================================================
# Internal Switch existence check
# ============================================================

$Switch = Get-VMSwitch `
    -Name $InternalSwitch `
    -ErrorAction SilentlyContinue


if ($null -eq $Switch) {

    Write-Host ""
    Write-Host "ERROR: Hyper-V Switch '$InternalSwitch' が存在しません。" -ForegroundColor Red
    Write-Host ""
    Write-Host "先にInternal Switch作成用スクリプトを実行してください。"
    Write-Host ""

    exit 6
}


if ($Switch.SwitchType -ne "Internal") {

    Write-Host ""
    Write-Host "ERROR: '$InternalSwitch' はInternal Switchではありません。" -ForegroundColor Red
    Write-Host ""

    exit 7
}


Write-Host "Internal Switch '$InternalSwitch' を確認しました."


# ============================================================
# Check MAC address conflict BEFORE modifying VM
# ============================================================

$Conflict = Get-VMNetworkAdapter -All |
    Where-Object {
        $_.MacAddress -eq $InternalMAC -and
        $_.VMName -ne $VMName
    }


if ($null -ne $Conflict) {

    $ConflictVMs = $Conflict |
        Select-Object -ExpandProperty VMName -Unique

    Write-Host ""
    Write-Host "ERROR: MACアドレス $DisplayMAC は既に使用されています。" -ForegroundColor Red
    Write-Host ""

    Write-Host "使用中のVM:"
    foreach ($ConflictVM in $ConflictVMs) {
        Write-Host "  $ConflictVM"
    }

    Write-Host ""
    Write-Host "VM名の先頭3桁を変更してください。"
    Write-Host ""

    exit 8
}


# ============================================================
# Save original VM state
# ============================================================

$WasRunning = ($VM.State -eq "Running")


# ============================================================
# Stop VM if necessary
# ============================================================

if ($WasRunning) {

    Write-Host ""
    Write-Host "VMを停止します..."

    Stop-VM `
        -Name $VMName `
        -Force

    $RetryCount = 0

    while (
        (Get-VM -Name $VMName).State -ne "Off" -and
        $RetryCount -lt 30
    ) {

        Start-Sleep -Seconds 1
        $RetryCount++
    }


    if ((Get-VM -Name $VMName).State -ne "Off") {

        Write-Host ""
        Write-Host "ERROR: VMを停止できませんでした。" -ForegroundColor Red

        exit 9
    }
}


# ============================================================
# Get current network adapters
# ============================================================

$Adapters = Get-VMNetworkAdapter -VMName $VMName


# ============================================================
# Default Switch NIC
#
# NIC name is NOT used for identification.
# SwitchName is used instead.
# ============================================================

$DefaultNIC = $Adapters |
    Where-Object {
        $_.SwitchName -eq $DefaultSwitch
    } |
    Select-Object -First 1


if ($null -eq $DefaultNIC) {

    Write-Host ""
    Write-Host "Default Switch NICを追加します..."

    Add-VMNetworkAdapter `
        -VMName $VMName `
        -SwitchName $DefaultSwitch | Out-Null

    Write-Host "  OK" -ForegroundColor Green

}
else {

    Write-Host ""
    Write-Host "Default Switch NICは既に存在します。"

    Write-Host "  NIC : $($DefaultNIC.Name)"
}


# ============================================================
# Internal Switch NIC
#
# NIC name is NOT used for identification.
# SwitchName is used instead.
# ============================================================

$InternalNIC = $Adapters |
    Where-Object {
        $_.SwitchName -eq $InternalSwitch
    } |
    Select-Object -First 1


if ($null -eq $InternalNIC) {

    Write-Host ""
    Write-Host "Internal Switch NICを追加します..."

    Add-VMNetworkAdapter `
        -VMName $VMName `
        -SwitchName $InternalSwitch | Out-Null

    Write-Host "  OK" -ForegroundColor Green
}


# ============================================================
# Wait for Hyper-V to register the new NIC
# ============================================================

$InternalNIC = $null

$RetryCount = 0
$MaxRetry = 20


while ($null -eq $InternalNIC -and $RetryCount -lt $MaxRetry) {

    Start-Sleep -Milliseconds 500

    $InternalNIC = Get-VMNetworkAdapter -VMName $VMName |
        Where-Object {
            $_.SwitchName -eq $InternalSwitch
        } |
        Select-Object -First 1

    $RetryCount++
}


if ($null -eq $InternalNIC) {

    Write-Host ""
    Write-Host "ERROR: Internal Switchに接続されたNICを取得できませんでした。" -ForegroundColor Red
    Write-Host ""

    Write-Host "現在のNIC:"
    Get-VMNetworkAdapter -VMName $VMName |
        Select-Object Name, SwitchName, MacAddress |
        Format-Table -AutoSize

    if ($WasRunning) {
        Start-VM -Name $VMName
    }

    exit 10
}


# ============================================================
# Set Internal NIC static MAC
# ============================================================

if ($InternalNIC.MacAddress -ne $InternalMAC) {

    Write-Host ""
    Write-Host "Internal NICのMACを設定します。"

    Write-Host "  NIC     : $($InternalNIC.Name)"
    Write-Host "  Current : $($InternalNIC.MacAddress)"
    Write-Host "  Target  : $DisplayMAC"

    Set-VMNetworkAdapter `
        -VMName $VMName `
        -Name $InternalNIC.Name `
        -StaticMacAddress $InternalMAC

    Write-Host "  OK" -ForegroundColor Green

}
else {

    Write-Host ""
    Write-Host "Internal NICのMACは既に正しく設定されています。"
}


# ============================================================
# Default Switch NIC must use Dynamic MAC
# ============================================================

$DefaultNIC = Get-VMNetworkAdapter -VMName $VMName |
    Where-Object {
        $_.SwitchName -eq $DefaultSwitch
    } |
    Select-Object -First 1


if ($null -eq $DefaultNIC) {

    Write-Host ""
    Write-Host "WARNING: Default Switch NICが取得できませんでした。" -ForegroundColor Yellow

}
else {

    if (-not $DefaultNIC.DynamicMacAddressEnabled) {

        Write-Host ""
        Write-Host "Default Switch NICをDynamic MACに設定します。"

        Set-VMNetworkAdapter `
            -VMName $VMName `
            -Name $DefaultNIC.Name `
            -DynamicMacAddress

        Write-Host "  OK" -ForegroundColor Green

    }
    else {

        Write-Host ""
        Write-Host "Default Switch NICはDynamic MACです。"
    }
}


# ============================================================
# Final verification
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Final Configuration" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Get-VMNetworkAdapter -VMName $VMName |
    Select-Object `
        Name,
        SwitchName,
        MacAddress,
        DynamicMacAddressEnabled,
        Status |
    Format-Table -AutoSize


# ============================================================
# Verify Internal MAC
# ============================================================

$VerifyInternalNIC = Get-VMNetworkAdapter -VMName $VMName |
    Where-Object {
        $_.SwitchName -eq $InternalSwitch
    } |
    Select-Object -First 1


if (
    $null -eq $VerifyInternalNIC -or
    $VerifyInternalNIC.MacAddress -ne $InternalMAC
) {

    Write-Host ""
    Write-Host "ERROR: Internal NICのMAC設定を確認できませんでした。" -ForegroundColor Red
    Write-Host ""

    if ($WasRunning) {
        Start-VM -Name $VMName
    }

    exit 11
}


# ============================================================
# Restore original VM state
# ============================================================

if ($WasRunning) {

    Write-Host ""
    Write-Host "VMを起動します..."

    Start-VM -Name $VMName

    Write-Host "  OK" -ForegroundColor Green

}
else {

    Write-Host ""
    Write-Host "VMは元々停止していたため、停止状態を維持します。"
}


Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " 完了しました。" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

exit 0
