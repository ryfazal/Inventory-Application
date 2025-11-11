# 🧭 InventoryApp & ServiceNow Integration Guide

A **PowerShell-based inventory management application** with seamless **ServiceNow integration** for pickups, deliveries, returns, and transfers.  
Tracks real-time stock movements using a JSON datastore and provides optional REST-based sync to ServiceNow.

---

## ⚙️ Features

- 🧱 Single-file JSON datastore — items, locations, and transactions stored together  
- 🔐 Pickup confirmation — OTP or signature before completing a pickup  
- 🧾 Import/Export — CSV & JSON for migration or backups  
- 🧮 Derived stock — calculated from immutable transaction log  
- 🌐 ServiceNow integration — push transactions directly to a ServiceNow custom table  
- 📊 Interactive CLI menu or scriptable PowerShell functions  

---

## 🚀 Getting Started

### 1️⃣ Run Interactively
```powershell
pwsh ./InventoryApp.ps1
```
or on Windows PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\InventoryApp.ps1
```

### 2️⃣ Import Functions for Script Use
```powershell
. ./InventoryApp.ps1
Initialize-InventoryStore -Path './store.json'
Add-InventoryItem -Sku 'SKU-001' -Name 'Widget A' -Location 'WH1' -Qty 100
New-InventoryTransaction -Type Pickup -Sku 'SKU-001' -Qty 5 -From 'WH1' -Ref 'Order1001'
Complete-InventoryTransaction -Id <txId>
Get-InventoryReport
```

---

## 🧩 Key Commands

| Function | Purpose |
|-----------|----------|
| `Initialize-InventoryStore` | Creates or loads the JSON datastore |
| `Add-InventoryItem` | Adds new inventory item (SKU) |
| `Get-InventoryItems` | Lists active or all items |
| `New-InventoryTransaction` | Logs pickups, deliveries, returns, transfers, adjustments |
| `Complete-InventoryTransaction` | Confirms and applies a transaction |
| `Get-InventoryReport` | Prints stock report |
| `Export-InventoryCsv` / `Export-TransactionsCsv` | Export to CSV |
| `Import-ItemsCsv` | Import new SKUs from CSV |
| `Save-Backup` | Save JSON backup snapshot |

---

## 🧪 Sample PowerShell Session

```powershell
=== Inventory App ===
1) List Items
2) Add Item
3) New Transaction (Pickup)
Select: 3
Type [Pickup]: Pickup
SKU: SKU-001
Qty: 5
From Location: WH1
Reference: ORDER1001
Transaction TX123 created (Open)

> New-PickupCode -Id TX123 -PickerName "Alex"
Code: 482913 (valid 15 min)

> Confirm-Pickup -Id TX123 -PickerName "Alex" -Code 482913
Pickup confirmed ✔

> Complete-InventoryTransaction -Id TX123
Transaction TX123 marked Completed and synced to ServiceNow.
```

---

## 🔐 Pickup Confirmation

Pickups require confirmation before completion to ensure accountability.

Two supported methods:
1. **OTP Code** — generated via `New-PickupCode`, confirmed by `Confirm-Pickup`  
2. **Signature File** — image/PDF proof attached via `Confirm-Pickup -SignaturePath`

If confirmation isn’t present, completion will fail until validated.

---

## 🌐 ServiceNow Integration

The InventoryApp can automatically sync transactions to a ServiceNow instance.

### Configure ServiceNow Connection

```powershell
# OAuth (Bearer Token)
Set-ServiceNowConfig -Instance 'yourcompany.service-now.com' -Token '<token>' -AutoSync

# Basic Auth (Username/Password)
Set-ServiceNowConfig -Instance 'yourcompany.service-now.com' -Username 'admin' -Password (Read-Host -AsSecureString) -AutoSync
```

### Manual Sync
```powershell
Sync-TransactionToServiceNow -Id <TransactionId>
```

---

## 🧱 Embedded ServiceNow Table Definition (XML)

Below is an example **table XML** for import into your ServiceNow instance:  
Go to **System Definition → Tables → Import XML** and paste this content.

```xml
<record_update table="sys_db_object">
  <sys_db_object action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <label>Inventory Transaction</label>
    <is_extendable>false</is_extendable>
  </sys_db_object>
</record_update>

<record_update table="sys_dictionary">
  <sys_dictionary action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <element>u_tx_id</element>
    <column_label>Transaction ID</column_label>
    <internal_type>string</internal_type>
  </sys_dictionary>

  <sys_dictionary action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <element>u_type</element>
    <column_label>Type</column_label>
    <internal_type>string</internal_type>
  </sys_dictionary>

  <sys_dictionary action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <element>u_sku</element>
    <column_label>SKU</column_label>
    <internal_type>string</internal_type>
  </sys_dictionary>

  <sys_dictionary action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <element>u_qty</element>
    <column_label>Quantity</column_label>
    <internal_type>integer</internal_type>
  </sys_dictionary>

  <sys_dictionary action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <element>u_from</element>
    <column_label>From</column_label>
    <internal_type>string</internal_type>
  </sys_dictionary>

  <sys_dictionary action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <element>u_to</element>
    <column_label>To</column_label>
    <internal_type>string</internal_type>
  </sys_dictionary>

  <sys_dictionary action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <element>u_status</element>
    <column_label>Status</column_label>
    <internal_type>string</internal_type>
  </sys_dictionary>

  <sys_dictionary action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <element>u_ref</element>
    <column_label>Reference</column_label>
    <internal_type>string</internal_type>
  </sys_dictionary>

  <sys_dictionary action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <element>u_confirmed</element>
    <column_label>Confirmed</column_label>
    <internal_type>boolean</internal_type>
  </sys_dictionary>

  <sys_dictionary action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <element>u_picker</element>
    <column_label>Picker</column_label>
    <internal_type>string</internal_type>
  </sys_dictionary>

  <sys_dictionary action="INSERT_OR_UPDATE">
    <name>x_inventory_tx</name>
    <element>u_updated</element>
    <column_label>Updated Timestamp</column_label>
    <internal_type>glide_date_time</internal_type>
  </sys_dictionary>
</record_update>
```

---

## 🧾 Import Set + Transform Map Example

Paste this XML under **System Import Sets → Load Data → Import XML** to create your Import Set and Transform Map.

```xml
<record_update table="sys_import_set_table">
  <sys_import_set_table action="INSERT_OR_UPDATE">
    <name>u_inventory_tx_import</name>
    <label>Inventory TX Import</label>
  </sys_import_set_table>
</record_update>

<record_update table="sys_transform_map">
  <sys_transform_map action="INSERT_OR_UPDATE">
    <name>Inventory TX Import to x_inventory_tx</name>
    <source_table>u_inventory_tx_import</source_table>
    <target_table>x_inventory_tx</target_table>
    <coalesce>true</coalesce>
  </sys_transform_map>
</record_update>
```

---

## 🧠 Troubleshooting

| Issue | Resolution |
|--------|-------------|
| JSON file missing | Run `Initialize-InventoryStore` again |
| Pickup won’t complete | Confirm via OTP or signature first |
| ServiceNow sync failed | Check credentials and table permissions |
| Duplicate records | Ensure `u_tx_id` is set as **coalesce key** |

---

## 📁 Recommended Folder Layout

```
/InventoryApp/
  ├── InventoryApp.ps1
  ├── inventory_store.json
  ├── README_Full_InventoryApp.md
  └── README_Full_InventoryApp.pdf
```

