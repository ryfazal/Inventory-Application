<#
InventoryApp.ps1

A self-contained PowerShell application to track inventory pickups, returns, and deliveries.
- Single data store JSON file (items, locations, transactions)
- Menu UI (interactive) and CLI-friendly functions
- Immutable transaction log; inventory is derived from items + transactions
- CSV/JSON import/export
- Simple status handling (Open, InTransit, Completed, Cancelled)

Run:
  pwsh ./InventoryApp.ps1          # starts interactive menu

Or import functions:
  . ./InventoryApp.ps1
  Initialize-InventoryStore -Path './store.json'
  Add-InventoryItem -Sku 'SKU-001' -Name 'Widget A' -Location 'WH1' -Qty 100
  New-InventoryTransaction -Type Pickup -Sku 'SKU-001' -Qty 5 -From 'WH1' -Ref 'Order1001'
  Complete-InventoryTransaction -Id <txId>
  Get-InventoryReport

#>

param(
  [string]$Path = (Join-Path -Path (Get-Location) -ChildPath 'inventory_store.json'),
  [switch]$NonInteractive
)

#region ===== Data & Helpers =====
$script:StorePath = $Path

function Initialize-InventoryStore {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
  if (!(Test-Path $Path)) {
    $empty = @{ items=@(); locations=@(); transactions=@(); meta=@{ created=(Get-Date); version='1.0.0' } }
    $empty | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding UTF8
  }
  $script:StorePath = $Path
  Write-Verbose "Store initialized at $Path"
}

function Read-Store {
  if (!(Test-Path $script:StorePath)) { Initialize-InventoryStore -Path $script:StorePath }
  Get-Content $script:StorePath -Raw | ConvertFrom-Json
}

function Write-Store([hashtable]$data) {
  $data | ConvertTo-Json -Depth 6 | Set-Content -Path $script:StorePath -Encoding UTF8
}

function Save-Backup {
  [CmdletBinding()] param([string]$Suffix = (Get-Date -Format 'yyyyMMdd-HHmmss'))
  $backup = [IO.Path]::ChangeExtension($script:StorePath, ".$Suffix.json")
  Copy-Item -Path $script:StorePath -Destination $backup -Force
  Write-Host "Backup saved: $backup"
}

function New-Id { [guid]::NewGuid().ToString() }

#endregion

#region ===== Items & Locations =====
function Add-InventoryItem {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][string]$Sku,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Location,
    [int]$Qty = 0,
    [string]$Uom = 'ea',
    [hashtable]$Tags
  )
  $db = Read-Store
  if (-not ($db.locations -contains $Location)) { $db.locations += $Location }
  if ($db.items | Where-Object { $_.sku -eq $Sku }) { throw "Item with SKU '$Sku' already exists." }
  $item = [ordered]@{ id=New-Id; sku=$Sku; name=$Name; uom=$Uom; created=(Get-Date); active=$true; tags=$Tags }
  $db.items += $item
  Write-Store $db
  if ($Qty -ne 0) {
    # seed quantity via an Adjustment transaction
    New-InventoryTransaction -Type Adjustment -Sku $Sku -Qty $Qty -To $Location -Ref 'INIT'
  }
  return [pscustomobject]$item
}

function Set-ItemActive {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][string]$Sku,
    [Parameter(Mandatory)][bool]$Active
  )
  $db = Read-Store
  $item = $db.items | Where-Object sku -eq $Sku
  if (-not $item) { throw "Unknown SKU '$Sku'" }
  $item.active = $Active
  Write-Store $db
}

function Get-InventoryItems {
  [CmdletBinding()] param([string]$Sku,[switch]$Inactive)
  $db = Read-Store
  $q = $db.items
  if ($Sku) { $q = $q | Where-Object sku -eq $Sku }
  if (-not $Inactive) { $q = $q | Where-Object active }
  return $q | Sort-Object sku
}

#endregion

#region ===== Transactions =====
# Types: Pickup (leaves a location), Delivery (arrives at a location), Return (arrives from customer),
# Adjustment (manual correction), Transfer (between locations)
# Status: Open -> InTransit -> Completed | Cancelled

function New-InventoryTransaction {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][ValidateSet('Pickup','Delivery','Return','Adjustment','Transfer')][string]$Type,
    [Parameter(Mandatory)][string]$Sku,
    [Parameter(Mandatory)][int]$Qty,
    [string]$From,
    [string]$To,
    [string]$Ref,
    [hashtable]$Meta,
    [switch]$SyncServiceNow
  )
  if ($Qty -le 0) { throw 'Qty must be > 0' }
  $db = Read-Store
  $item = $db.items | Where-Object sku -eq $Sku
  if (-not $item) { throw "Unknown SKU '$Sku'" }
  if ($From -and -not ($db.locations -contains $From)) { $db.locations += $From }
  if ($To -and -not ($db.locations -contains $To)) { $db.locations += $To }

  $tx = [ordered]@{
    id = New-Id
    type = $Type
    sku = $Sku
    qty = [int]$Qty
    from = $From
    to = $To
    ref = $Ref
    status = 'Open'
    created = Get-Date
    updated = Get-Date
    meta = $Meta
  }

  switch ($Type) {
    'Pickup'    { if (-not $From) { throw "Pickup requires -From" } }
    'Delivery'  { if (-not $To)   { throw "Delivery requires -To" } }
    'Return'    { if (-not $To)   { throw "Return requires -To (receiving location)" } }
    'Transfer'  { if (-not $From -or -not $To) { throw "Transfer requires -From and -To" } }
    'Adjustment' { if (-not $To) { $tx.to = 'ADJUST'; } }
  }

  $db.transactions += $tx
  Write-Store $db

  # Optional ServiceNow sync
  $cfg = $null
  try { $cfg = Get-ServiceNowConfig } catch { $cfg = $null }
  if ($SyncServiceNow -or ($cfg -and $cfg.autoSync)) {
    try { Sync-TransactionToServiceNow -Id $tx.id | Out-Null } catch { Write-Warning "ServiceNow sync failed: $($_.Exception.Message)" }
  }

  return [pscustomobject]$tx
}

function Set-InventoryTransactionStatus {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][ValidateSet('Open','InTransit','Completed','Cancelled')][string]$Status
  )
  $db = Read-Store
  $tx = $db.transactions | Where-Object id -eq $Id
  if (-not $tx) { throw "Unknown transaction id $Id" }
  $tx.status = $Status
  $tx.updated = Get-Date
  Write-Store $db
  return $tx
}

function Complete-InventoryTransaction {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Id)
  $db = Read-Store
  $tx = $db.transactions | Where-Object id -eq $Id
  if (-not $tx) { throw "Unknown transaction id $Id" }
  if ($tx.type -eq 'Pickup') {
    $confirmed = $false
    if ($tx.meta -and $tx.meta.pickup -and $tx.meta.pickup.confirmed) { $confirmed = [bool]$tx.meta.pickup.confirmed }
    if (-not $confirmed) { throw "Pickup requires confirmation before completion. Use New-PickupCode and Confirm-Pickup first (or set confirmation via signature)." }
  }
  Set-InventoryTransactionStatus -Id $Id -Status Completed | Out-Null
  Apply-InventoryTransaction -Id $Id | Out-Null
  # Optional ServiceNow sync on completion
  $cfg = $null
  try { $cfg = Get-ServiceNowConfig } catch { $cfg = $null }
  if ($cfg -and $cfg.autoSync) {
    try { Sync-TransactionToServiceNow -Id $Id | Out-Null } catch { Write-Warning "ServiceNow sync failed: $($_.Exception.Message)" }
  }
  return (Get-InventoryTransactions | Where-Object id -eq $Id)
}

function Cancel-InventoryTransaction {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Id)
  Set-InventoryTransactionStatus -Id $Id -Status Cancelled
}

function Apply-InventoryTransaction {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Id)
  $db = Read-Store
  $tx = $db.transactions | Where-Object id -eq $Id
  if (-not $tx) { throw "Unknown transaction id $Id" }
  if ($tx.status -ne 'Completed') { throw "Only Completed transactions can be applied (current: $($tx.status))" }
  $tx.applied = $true
  $tx.appliedAt = Get-Date
  Write-Store $db
  return $tx
}

function Get-InventoryTransactions {
  [CmdletBinding()] param(
    [string]$Type,
    [string]$Sku,
    [string]$Status,
    [datetime]$Since
  )
  $db = Read-Store
  $q = $db.transactions
  if ($Type) { $q = $q | Where-Object type -eq $Type }
  if ($Sku) { $q = $q | Where-Object sku -eq $Sku }
  if ($Status) { $q = $q | Where-Object status -eq $Status }
  if ($Since) { $q = $q | Where-Object created -ge $Since }
  $q | Sort-Object created -Descending
}

#endregion

#region ===== Derived Inventory =====
function Get-InventoryLedger {
  [CmdletBinding()] param([string]$Sku)
  $db = Read-Store
  $txs = $db.transactions | Where-Object { $_.status -eq 'Completed' }
  if ($Sku) { $txs = $txs | Where-Object sku -eq $Sku }

  $rows = foreach ($t in $txs) {
    switch ($t.type) {
      'Pickup'    { [pscustomobject]@{ sku=$t.sku; location=$t.from; delta = -1 * $t.qty; ref=$t.ref; when=$t.updated; type=$t.type; id=$t.id } }
      'Delivery'  { [pscustomobject]@{ sku=$t.sku; location=$t.to;   delta = +1 * $t.qty; ref=$t.ref; when=$t.updated; type=$t.type; id=$t.id } }
      'Return'    { [pscustomobject]@{ sku=$t.sku; location=$t.to;   delta = +1 * $t.qty; ref=$t.ref; when=$t.updated; type=$t.type; id=$t.id } }
      'Transfer'  { 
        [pscustomobject]@{ sku=$t.sku; location=$t.from; delta = -1 * $t.qty; ref=$t.ref; when=$t.updated; type=$t.type; id=$t.id }
        [pscustomobject]@{ sku=$t.sku; location=$t.to;   delta = +1 * $t.qty; ref=$t.ref; when=$t.updated; type=$t.type; id=$t.id }
      }
      'Adjustment' { [pscustomobject]@{ sku=$t.sku; location=$t.to; delta = +1 * $t.qty; ref=$t.ref; when=$t.updated; type=$t.type; id=$t.id } }
    }
  }
  $rows
}

function Get-InventorySnapshot {
  [CmdletBinding()] param([string]$Sku)
  $db = Read-Store
  $items = $db.items
  if ($Sku) { $items = $items | Where-Object sku -eq $Sku }

  $ledger = Get-InventoryLedger -Sku $Sku

  $balances = @{}
  foreach ($row in $ledger) {
    $key = "$($row.sku)|$($row.location)"
    if (-not $balances.ContainsKey($key)) { $balances[$key] = 0 }
    $balances[$key] += [int]$row.delta
  }

  $rows = foreach ($k in $balances.Keys) {
    $parts = $k -split '\|'
    [pscustomobject]@{
      sku = $parts[0]
      location = $parts[1]
      qty = [int]$balances[$k]
    }
  }
  $rows | Sort-Object sku, location
}

function Get-InventoryReport {
  [CmdletBinding()] param([switch]$IncludeZero)
  $snapshot = Get-InventorySnapshot
  if (-not $IncludeZero) { $snapshot = $snapshot | Where-Object qty -ne 0 }
  $snapshot | Sort-Object sku, location | Format-Table -AutoSize
}

#endregion

#region ===== Import/Export =====
function Export-InventoryCsv {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
  $snapshot = Get-InventorySnapshot | Sort-Object sku, location
  $snapshot | Export-Csv -NoTypeInformation -Path $Path -Encoding UTF8
  Write-Host "Exported snapshot to $Path"
}

function Export-TransactionsCsv {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
  (Read-Store).transactions | Sort-Object created | Export-Csv -NoTypeInformation -Path $Path -Encoding UTF8
  Write-Host "Exported transactions to $Path"
}

function Import-ItemsCsv {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
  $rows = Import-Csv -Path $Path
  foreach ($r in $rows) {
    if (-not $r.sku -or -not $r.name) { continue }
    $existing = Get-InventoryItems -Sku $r.sku -Inactive
    if ($existing) { continue }

    # PowerShell 5.1 compatible fallbacks (no null-coalescing operator)
    $loc = if ($null -ne $r.location -and $r.location -ne '') { $r.location } else { 'WH1' }
    $qty = if ($null -ne $r.qty -and $r.qty -ne '') { [int]$r.qty } else { 0 }
    $uom = if ($null -ne $r.uom -and $r.uom -ne '') { $r.uom } else { 'ea' }

    Add-InventoryItem -Sku $r.sku -Name $r.name -Location $loc -Qty $qty -Uom $uom | Out-Null
  }
}
#endregion

#region ===== Menu UI =====
function Show-InventoryMenu {
  cls
  Write-Host '=== Inventory App ===' -ForegroundColor Cyan
  Write-Host "Store: $script:StorePath
"
  $options = @(
    '1) List Items',
    '2) Add Item',
    '3) New Transaction (Pickup/Delivery/Return/Transfer/Adjustment)',
    '4) List Transactions',
    '5) Complete Transaction',
    '6) Report Snapshot',
    '7) Export Snapshot CSV',
    '8) Export Transactions CSV',
    '9) Backup Store',
    '10) Generate Pickup Code',
    '11) Confirm Pickup',
    '0) Exit'
  )
  $options | ForEach-Object { Write-Host $_ }
  $choice = Read-Host 'Select'
  switch ($choice) {
    '1' { Get-InventoryItems | Format-Table sku,name,active,uom -AutoSize | Out-Host }
    '2' {
      $sku = Read-Host 'SKU'
      $name = Read-Host 'Name'
      $loc = Read-Host 'Default Location (e.g., WH1)'
      $qty = [int](Read-Host 'Initial Qty (0 ok)')
      try { Add-InventoryItem -Sku $sku -Name $name -Location $loc -Qty $qty | Out-Host }
      catch { Write-Host $_ -ForegroundColor Red }
    }
    '3' {
      $type = Read-Host 'Type [Pickup,Delivery,Return,Transfer,Adjustment]'
      $sku  = Read-Host 'SKU'
      $qty  = [int](Read-Host 'Qty')
      $from = if ($type -in 'Pickup','Transfer') { Read-Host 'From Location' } else { $null }
      $to   = if ($type -in 'Delivery','Return','Transfer','Adjustment') { Read-Host 'To Location' } else { $null }
      $ref  = Read-Host 'Reference (Order/ASN/RMA)'
      try {
        $tx = New-InventoryTransaction -Type $type -Sku $sku -Qty $qty -From $from -To $to -Ref $ref
        $tx | Format-List | Out-Host
      } catch { Write-Host $_ -ForegroundColor Red }
    }
    '4' { Get-InventoryTransactions | Select-Object id,type,sku,qty,from,to,status,ref,created | Format-Table -AutoSize | Out-Host }
    '5' {
      $id = Read-Host 'Transaction Id'
      try { Complete-InventoryTransaction -Id $id | Format-List | Out-Host } catch { Write-Host $_ -ForegroundColor Red }
    }
    '6' { Get-InventoryReport | Out-Host }
    '7' { $p = Read-Host 'CSV path'; Export-InventoryCsv -Path $p }
    '8' { $p = Read-Host 'CSV path'; Export-TransactionsCsv -Path $p }
    '9' { Save-Backup }
    '10' {
      $id = Read-Host 'Pickup Transaction Id'
      $picker = Read-Host 'Picker Name (optional)'
      try {
        $res = New-PickupCode -Id $id -PickerName $picker
        Write-Host "
Give this code to the picker (valid ~15 minutes):" -ForegroundColor Green
        Write-Host "Code: $($res.Code)" -ForegroundColor Cyan
      } catch { Write-Host $_ -ForegroundColor Red }
    }
    '11' {
      $id = Read-Host 'Pickup Transaction Id'
      $picker = Read-Host 'Picker Name'
      $m = Read-Host 'Method [OTP/SignatureFile]'
      try {
        if ($m -match '^(?i)otp$') {
          $code = Read-Host 'Enter OTP code from picker'
          Confirm-Pickup -Id $id -PickerName $picker -Code $code | Format-List | Out-Host
        } elseif ($m -match '^(?i)signaturefile$') {
          $path = Read-Host 'Path to signature image/PDF'
          Confirm-Pickup -Id $id -PickerName $picker -SignaturePath $path | Format-List | Out-Host
        } else { Write-Host 'Unknown method' -ForegroundColor Yellow }
      } catch { Write-Host $_ -ForegroundColor Red }
    }
    '0' { return $false }
    default { Write-Host 'Invalid choice' -ForegroundColor Yellow }
  }
  Write-Host "
Press Enter to continue..."; [void][System.Console]::ReadLine(); return $true
}
#endregion

#region ===== ServiceNow Integration =====
# Configuration is stored inside the JSON store under meta.servicenow
# Supports: Basic auth (username/password) or OAuth/Bearer token

function Set-ServiceNowConfig {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][string]$Instance,  # e.g., dev12345.service-now.com or yourcompany.service-now.com
    [string]$Username,
    [SecureString]$Password,
    [string]$Token,
    [string]$Table = 'x_inventory_tx',
    [switch]$AutoSync
  )
  $db = Read-Store
  if (-not $db.meta) { $db.meta = @{} }
  if (-not $db.meta.servicenow) { $db.meta.servicenow = @{} }

  $db.meta.servicenow.instance = $Instance
  $db.meta.servicenow.table = $Table
  $db.meta.servicenow.autoSync = [bool]$AutoSync

  if ($PSBoundParameters.ContainsKey('Token')) {
    $db.meta.servicenow.auth = @{ method='token'; token=$Token }
  } elseif ($Username -and $Password) {
    # Store password encrypted for CurrentUser scope
    $enc = $Password | ConvertFrom-SecureString
    $db.meta.servicenow.auth = @{ method='basic'; username=$Username; passwordEnc=$enc }
  }
  Write-Store $db
  return [pscustomobject]@{ Instance=$Instance; Table=$Table; AutoSync=[bool]$AutoSync }
}

function Get-ServiceNowConfig {
  $db = Read-Store
  return $db.meta.servicenow
}

function Get-SNAuthHeader {
  $cfg = Get-ServiceNowConfig
  if (-not $cfg -or -not $cfg.auth) { throw 'ServiceNow not configured. Use Set-ServiceNowConfig first.' }
  if ($cfg.auth.method -eq 'token') {
    return @{ Authorization = "Bearer $($cfg.auth.token)" }
  } elseif ($cfg.auth.method -eq 'basic') {
    $sec = $null
    try { $sec = $cfg.auth.passwordEnc | ConvertTo-SecureString }
    catch { throw 'Stored ServiceNow password cannot be decrypted under this user. Reconfigure credentials.' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    $pair = "{0}:{1}" -f $cfg.auth.username, $plain
    $bytes = [Text.Encoding]::UTF8.GetBytes($pair)
    $basic = [Convert]::ToBase64String($bytes)
    return @{ Authorization = "Basic $basic" }
  } else {
    throw 'Unknown ServiceNow auth method.'
  }
}

function Invoke-SNRequest {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][ValidateSet('GET','POST','PATCH','PUT','DELETE')][string]$Method,
    [Parameter(Mandatory)][string]$Path,
    [hashtable]$Body
  )
  $cfg = Get-ServiceNowConfig
  $headers = Get-SNAuthHeader
  $base = if ($cfg.instance -match '^https?://') { $cfg.instance } else { 'https://' + $cfg.instance }
  $uri = "$base/api/now/table/$Path"
  $params = @{ Method=$Method; Uri=$uri; Headers=$headers }
  if ($Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 6); $params['ContentType'] = 'application/json' }
  try {
    $res = Invoke-RestMethod @params
    return $res
  } catch {
    throw "ServiceNow call failed: $($_.Exception.Message)"
  }
}

function New-ServiceNowRecord {
  [CmdletBinding()] param(
    [string]$Table,
    [hashtable]$Fields
  )
  $cfg = Get-ServiceNowConfig
  $tbl = if ($Table) { $Table } else { $cfg.table }
  $res = Invoke-SNRequest -Method POST -Path $tbl -Body $Fields
  return $res.result
}

function Update-ServiceNowRecord {
  [CmdletBinding()] param(
    [string]$Table,
    [Parameter(Mandatory)][string]$SysId,
    [hashtable]$Fields
  )
  $cfg = Get-ServiceNowConfig
  $tbl = if ($Table) { $Table } else { $cfg.table }
  $res = Invoke-SNRequest -Method PATCH -Path "$tbl/$SysId" -Body $Fields
  return $res.result
}

function Sync-TransactionToServiceNow {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][string]$Id,
    [string]$Table
  )
  $db = Read-Store
  $tx = $db.transactions | Where-Object id -eq $Id
  if (-not $tx) { throw "Unknown transaction id $Id" }
  $cfg = Get-ServiceNowConfig
  if (-not $cfg) { throw 'ServiceNow not configured. Use Set-ServiceNowConfig.' }
  $tbl = if ($Table) { $Table } else { $cfg.table }

  $picker = $null
  $confirmed = $false
  if ($tx.meta -and $tx.meta.pickup) { $picker = $tx.meta.pickup.pickerName; $confirmed = [bool]$tx.meta.pickup.confirmed }

  $payload = @{
    short_description = "Inventory $($tx.type) for SKU $($tx.sku)"
    description       = "Qty=$($tx.qty), From=$($tx.from), To=$($tx.to), Ref=$($tx.ref)"
    u_tx_id           = $tx.id
    u_type            = $tx.type
    u_sku             = $tx.sku
    u_qty             = $tx.qty
    u_from            = $tx.from
    u_to              = $tx.to
    u_status          = $tx.status
    u_ref             = $tx.ref
    u_confirmed       = $confirmed
    u_picker          = $picker
    u_updated         = (Get-Date).ToString('o')
  }

  if (-not $tx.meta) { $tx.meta = @{} }
  if (-not $tx.meta.servicenow) { $tx.meta.servicenow = @{} }

  if (-not $tx.meta.servicenow.sys_id) {
    $created = New-ServiceNowRecord -Table $tbl -Fields $payload
    $tx.meta.servicenow = @{ sys_id=$created.sys_id; table=$tbl; instance=$cfg.instance }
  } else {
    $null = Update-ServiceNowRecord -Table $tbl -SysId $tx.meta.servicenow.sys_id -Fields $payload
  }
  $tx.updated = Get-Date
  Write-Store $db
  return [pscustomobject]@{ id=$tx.id; servicenowSysId=$tx.meta.servicenow.sys_id; table=$tbl; instance=$cfg.instance; status=$tx.status }
}

#endregion

#region ===== Startup =====
# Robust detection for direct execution in Windows PowerShell 5.1 and PowerShell 7+
# If you dot-source the file (". ./InventoryApp.ps1"), the InvocationName is '.' and this block will not run.
if ($MyInvocation -and $MyInvocation.InvocationName -ne '.' -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
  Initialize-InventoryStore -Path $script:StorePath
  if (-not $NonInteractive) {
    while (Show-InventoryMenu) { }
  }
}
#endregion
