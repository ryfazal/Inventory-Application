# 📦 InventoryApp — PowerShell Inventory Management System

![PowerShell](https://img.shields.io/badge/PowerShell-7+-blue?logo=powershell)
![License](https://img.shields.io/badge/License-MIT-green)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-lightgrey)

A lightweight, offline-friendly PowerShell application for tracking **inventory pickups, deliveries, returns, transfers, and adjustments** — complete with **secure pickup confirmation** (via OTP code or signature verification).

---

## 🧰 Features

✅ Interactive text menu for managing inventory  
✅ JSON-based local datastore (`inventory_store.json`)  
✅ Immutable transaction log (audit-friendly)  
✅ Pickup confirmation via **OTP** or **signature file**  
✅ Export reports to CSV  
✅ Built-in backups and easy restore  

---

## ⚙️ Prerequisites

- Windows PowerShell 5.1 **or** PowerShell 7+
- Script execution enabled (if blocked, run this once):
  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
  ```

---

## 🚀 Installation

1. **Download** the repository or ZIP package  
   (includes `InventoryApp.ps1` and `inventory_store.json`)
2. Extract it somewhere easy, e.g.:
   ```
   C:\InventoryApp
   ```
3. **Run PowerShell**, then:
   ```powershell
   cd "C:\InventoryApp"
   .\InventoryApp.ps1
   ```

If you see nothing happen, unblock the file first:
```powershell
Unblock-File .\InventoryApp.ps1
```

---

## 🧮 Menu Overview

| Option | Action |
|--------|---------|
| 1 | List Items |
| 2 | Add Item |
| 3 | New Transaction (Pickup/Delivery/Return/Transfer/Adjustment) |
| 4 | List Transactions |
| 5 | Complete Transaction |
| 6 | Report Snapshot |
| 7 | Export Snapshot CSV |
| 8 | Export Transactions CSV |
| 9 | Backup Store |
| 10 | Generate Pickup Code |
| 11 | Confirm Pickup |
| 0 | Exit |

---

## 🔐 Pickup Confirmation Workflow

Before completing a **Pickup**, the person collecting the item must confirm possession:

### 🔹 Step 1 — Generate a Pickup Code
```powershell
New-PickupCode -Id <pickupTxId> -PickerName "John Smith"
```
Displays a **6-digit code** valid for ~15 minutes.

### 🔹 Step 2 — Confirm Pickup
**Option 1: OTP code**
```powershell
Confirm-Pickup -Id <pickupTxId> -PickerName "John Smith" -Code 123456
```

**Option 2: Signature file**
```powershell
Confirm-Pickup -Id <pickupTxId> -PickerName "John Smith" -SignaturePath "C:\signatures\john.png"
```

### 🔹 Step 3 — Complete the Pickup
```powershell
Complete-InventoryTransaction -Id <pickupTxId>
```

---

## 💾 Data Storage

All app data (items, locations, transactions) lives in:
```
inventory_store.json
```
You can back it up anytime from the menu (`9) Backup Store`) or manually copy the file.

---

## 📤 Exporting Reports

| Command | Description |
|----------|--------------|
| `Export-InventoryCsv -Path './snapshot.csv'` | Export inventory snapshot |
| `Export-TransactionsCsv -Path './transactions.csv'` | Export transaction log |

---

## 🧠 Troubleshooting

| Issue | Cause | Fix |
|-------|--------|-----|
| Script won’t run | Execution policy restriction | `Set-ExecutionPolicy RemoteSigned` |
| Nothing happens | Script blocked | `Unblock-File .\InventoryApp.ps1` |
| Can’t complete pickup | Not confirmed | Use `Confirm-Pickup` first |

---

## 🧩 Using as a Module

You can also dot-source and use functions directly:
```powershell
. .\InventoryApp.ps1
Initialize-InventoryStore -Path './store.json'
Add-InventoryItem -Sku 'SKU-001' -Name 'Widget A' -Location 'WH1' -Qty 100
```

---

## 🧾 License

MIT License © 2025 — Developed with ❤️ using PowerShell Automation

---

## 🖼️ Screenshots (optional)

> _Add your screenshots or GIF demos here:_
>
> ![Menu Screenshot](docs/menu-demo.png)
> ![Pickup Confirmation](docs/pickup-confirmation.png)
