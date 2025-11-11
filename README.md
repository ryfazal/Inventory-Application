# ServiceNow Integration for InventoryApp

This package provides a ready-to-import ServiceNow schema and guide for integrating the **PowerShell InventoryApp** with your ServiceNow instance.  
It enables automatic and manual synchronization of inventory transactions (Pickups, Deliveries, Returns, etc.) between PowerShell and ServiceNow.

---

## 📁 Contents
| File | Description |
|------|--------------|
| **ServiceNow_Integration_Guide.pdf** | Step-by-step guide for setup and configuration |
| **ServiceNow_Table_x_inventory_tx.xml** | Defines the target table `x_inventory_tx` and all fields |
| **ServiceNow_ImportSet_TransformMap_x_inventory_tx.xml** | Defines import set table `u_inventory_tx_import` and Transform Map |
| **InventoryApp.ps1** | (Not included here) PowerShell app that integrates with ServiceNow |

---

## 🚀 Setup Instructions

### 1. Import the Target Table
1. In your ServiceNow instance, go to **System Definition → Tables**.
2. Use the ☰ (hamburger) menu → **Import XML**.
3. Upload and import `ServiceNow_Table_x_inventory_tx.xml`.

You’ll see a new table named `x_inventory_tx` with fields:
`u_tx_id`, `u_type`, `u_sku`, `u_qty`, `u_from`, `u_to`, `u_status`, `u_ref`, `u_confirmed`, `u_picker`, and `u_updated`.

---

### 2. Import the Import Set & Transform Map
1. Go to **System Import Sets → Load Data**.
2. Use **Import XML** again to upload `ServiceNow_ImportSet_TransformMap_x_inventory_tx.xml`.
3. Verify:
   - Import set table: `u_inventory_tx_import`
   - Transform Map: `Inventory TX Import to x_inventory_tx`
   - Coalesce key: `u_tx_id`

---

### 3. Configure PowerShell InventoryApp

Use the ServiceNow integration functions built into your PowerShell script:

```powershell
# Configure with Bearer Token
Set-ServiceNowConfig -Instance 'yourcompany.service-now.com' -Token '<YOUR_TOKEN>' -AutoSync

# Or configure with Basic Auth
Set-ServiceNowConfig -Instance 'yourcompany.service-now.com' -Username 'admin' -Password (Read-Host -AsSecureString) -AutoSync
```

---

### 4. Sync Transactions

**Automatic Sync:**  
Enabled via `-AutoSync` during setup. Every new or completed transaction is posted to ServiceNow.

**Manual Sync:**  
```powershell
Sync-TransactionToServiceNow -Id <TransactionId>
```

---

### 5. Test the Import Set

You can bulk-load transactions using CSV:

```csv
tx_id,type,sku,qty,from,to,status,ref,confirmed,picker,updated
TX123,Pickup,SKU-001,5,WH1,CustomerDock,Open,ORDER-1001,true,Alex,"2025-11-10 10:45:00"
```

1. Upload via **System Import Sets → Load Data** → select `u_inventory_tx_import`.
2. Run Transform → select `Inventory TX Import to x_inventory_tx`.

---

## 🔍 Troubleshooting

- Ensure the ServiceNow user has **import_set_loader** and **rest_service** roles.
- Verify the instance URL and credentials.
- If duplicate records appear, check that `u_tx_id` is set as **coalesce**.
- Use PowerShell’s `Write-Store` and `Read-Store` to inspect the JSON datastore.

---

## 🧾 License
