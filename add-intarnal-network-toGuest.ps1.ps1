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
    Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptName`" <VMName>"
    Write-Host ""
    Write-Host "VMName:"
    Write-Host "  先頭3桁: 002〜253"
    Write-Host "  4文字目: _"
    Write-Host "  5文字目以降: 任意の文字列"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  $ScriptName 002_Ubuntu"
    Write-Host "  $ScriptName 100_Windows"
    Write-Host "  $ScriptName 253_TestVM"
    Write-Host ""
    Write-Host "MAC address:"
    Write-Host "  VM名の先頭3桁をInternal NICのMAC末尾に使用します。"
    Write-Host ""
    Write-Host "  002_Ubuntu  -> 00-15-5D-10-00-02"
    Write-Host "  100_Windows -> 00-15-5D-10-00-64"
    Write-Host "  253_TestVM  -> 00-15-5D-10-00-FD"
    Write-Host ""
    Write-Host "Network:"
    Write-Host "  NIC 1 : Default Switch / Dynamic MAC"
    Write-Host "  NIC 2 : Internal / Static MAC"
    Write-Host ""
    Write-Host "前提:"
    Write-Host "  Hyper-Vに 'Internal' Switchが既に存在すること。"
    Write-Host "  ホスト側 vEthernet (Internal) のIP設定は"
    Write-Host "  別スクリプトで管理します。"
    Write-Host ""
}

# ============================================================
# Argument check
# ============================================================

if (
    $args.Count -eq 0 -or
    $args[0] -in @("/?", "-?", "-h", "--help", "/h", "/help", "--h")
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
    Write-Host "ERROR: VM名 '$VMName' の形式が正しくありません。" -ForegroundColor Red
    Write-Host ""
    Write-Host "正しい形式:"
    Write-Host "  NNN_文字列"
    Write-Host ""
    Write-Host "NNN は 002〜253 です。"
    Write-Host "例: 002_Ubuntu"
    Write-Host ""

    exit 3
}

$Number = [int]$Matches.Number

if ($Number -lt 2 -or $Number -gt 253) {

    Write-Host ""
    Write-Host "ERROR: VM名の先頭3桁 '$($Matches.Number)' は範囲外です。" -ForegroundColor Red
    Write-Host ""
    Write-Host "使用可能な範囲: 002〜253"
    Write-Host ""

    exit 4
}

# ============================================================
# MAC address generation
# ============================================================

$LastByte = $Number.ToString("X2")

$InternalMAC = "00155D1000$LastByte"

# 表示用
$DisplayMAC = ($InternalMAC -replace '(.{2})(?!$)', '$1-').TrimEnd("-")

# ============================================================
# Start
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Hyper-V VM Network Configuration" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "VM Name       : $VMName"
Write-Host "Number        : $Number"
Write-Host "Internal MAC  : $DisplayMAC"
Write-Host ""

# ============================================================
# VM existence check
# ============================================================

$VM = Get-VM -Name $VMName -ErrorAction SilentlyContinue

if ($null -eq $VM) {

    Write-Host "ERROR: VM '$VMName' が存在しません。" -ForegroundColor Red
    Write-Host ""
    Write-Host "既存のHyper-V VM名を指定してください。"

    exit 5
}

# ============================================================
# Internal Switch existence check
# ============================================================

$Switch = Get-VMSwitch -Name $InternalSwitch -ErrorAction SilentlyContinue

if ($null -eq $Switch) {

    Write-Host ""
    Write-Host "ERROR: Hyper-V Switch '$InternalSwitch' が存在しません。" -ForegroundColor Red
    Write-Host ""
    Write-Host "先にInternal Switch作成用スクリプトを実行してください。"

    exit 6
}

if ($Switch.SwitchType -ne "Internal") {

    Write-Host ""
    Write-Host "ERROR: '$InternalSwitch' はInternal Switchではありません。" -ForegroundColor Red
    Write-Host ""
    Write-Host "既存のSwitchを変更せず処理を中止します。"

    exit 7
}

Write-Host "Internal Switch '$InternalSwitch' を確認しました。"

# ============================================================
# Save original VM state
# ============================================================

$WasRunning = ($VM.State -eq "Running")

if ($WasRunning) {

    Write-Host ""
    Write-Host "VMを停止します..."

    Stop-VM `
        -Name $VMName `
        -Force

    while ((Get-VM -Name $VMName).State -ne "Off") {
        Start-Sleep -Seconds 1
    }
}

# ============================================================
# Get existing VM NICs
# ============================================================

$Adapters = Get-VMNetworkAdapter -VMName $VMName

# ============================================================
# Default Switch NIC
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
        -SwitchName $DefaultSwitch `
        -Name "Internet"

    Write-Host "  OK" -ForegroundColor Green
}
else {

    Write-Host ""
    Write-Host "Default Switch NICは既に存在します。"
}

# ============================================================
# Internal Switch NIC
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
        -SwitchName $InternalSwitch `
        -Name "Internal"

    Write-Host "  OK" -ForegroundColor Green
}
else {

    Write-Host ""
    Write-Host "Internal Switch NICは既に存在します。"
}

# ============================================================
# Re-fetch NICs
# ============================================================

$InternalNIC = Get-VMNetworkAdapter `
    -VMName $VMName `
    -Name "Internal"

$DefaultNIC = Get-VMNetworkAdapter `
    -VMName $VMName `
    -Name "Internet"

# ============================================================
# MAC duplicate check
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
    Write-Host "ERROR: MACアドレス $DisplayMAC は既に別のVMで使用されています。" -ForegroundColor Red
    Write-Host ""
    Write-Host "使用中のVM:"

    $ConflictVMs | ForEach-Object {
        Write-Host "  $_"
    }

    Write-Host ""
    Write-Host "VM名の先頭3桁を変更してください。"

    if ($WasRunning) {
        Start-VM -Name $VMName
    }

    exit 8
}

# ============================================================
# Set Internal NIC static MAC
# ============================================================

if ($InternalNIC.MacAddress -ne $InternalMAC) {

    Write-Host ""
    Write-Host "Internal NICのMACを設定します。"
    Write-Host "  Current : $($InternalNIC.MacAddress)"
    Write-Host "  Target  : $DisplayMAC"

    Set-VMNetworkAdapter `
        -VMName $VMName `
        -Name "Internal" `
        -StaticMacAddress $InternalMAC

    Write-Host "  OK" -ForegroundColor Green
}
else {

    Write-Host ""
    Write-Host "Internal NICのMACは既に正しく設定されています。"
}

# ============================================================
# Default Switch NIC = Dynamic MAC
# ============================================================

$DefaultNIC = Get-VMNetworkAdapter `
    -VMName $VMName `
    -Name "Internet"

if (-not $DefaultNIC.DynamicMacAddressEnabled) {

    Write-Host ""
    Write-Host "Default Switch NICをDynamic MACに設定します。"

    Set-VMNetworkAdapter `
        -VMName $VMName `
        -Name "Internet" `
        -DynamicMacAddress

    Write-Host "  OK" -ForegroundColor Green
}
else {

    Write-Host ""
    Write-Host "Default Switch NICはDynamic MACです。"
}

# ============================================================
# Final configuration
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Final Configuration" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Get-VMNetworkAdapter -VMName $VMName |
    Select-Object `
        Name,
        SwitchName,
        MacAddress,
        DynamicMacAddressEnabled,
        Status |
    Format-Table -AutoSize

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
Write-Host "完了しました。" -ForegroundColor Green
Write-Host ""

exit 0
