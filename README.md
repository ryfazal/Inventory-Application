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
