# Gupta Fabricator Backend

This project now includes a small PowerShell backend with no external dependencies. It runs on Windows using the built-in .NET `HttpListener`.

## Run locally

Double-click:

```text
start-backend.bat
```

Or run from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\server.ps1
```

Open:

- Website: `http://localhost:3000/index11.html`
- Admin dashboard: `http://localhost:3000/admin.html`

## Admin login

Default local credentials:

- User: `admin`
- Password: `admin123`

Before putting the site online, set a stronger password:

```powershell
$env:ADMIN_PASSWORD="your-strong-password"
powershell -NoProfile -ExecutionPolicy Bypass -File .\server.ps1
```

## What is stored

Client enquiries and service orders are saved in:

```text
data/database.json
```

That file is blocked from public browser access by `server.js` and ignored by Git.

## Backend endpoints

- `POST /api/enquiries` saves quote/contact enquiries.
- `POST /api/orders` saves service purchase requests.
- `GET /api/admin/enquiries` lists enquiries for admin users.
- `GET /api/admin/orders` lists service orders for admin users.
- `PATCH /api/admin/enquiries/:id/status` updates enquiry status.
- `PATCH /api/admin/orders/:id/status` updates order status.
- `GET /api/export/enquiries.csv` exports enquiries.
- `GET /api/export/orders.csv` exports service orders.
