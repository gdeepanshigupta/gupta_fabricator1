param(
  [int]$Port = 3000,
  [string]$AdminUser = $env:ADMIN_USER,
  [string]$AdminPassword = $env:ADMIN_PASSWORD
)

if ([string]::IsNullOrWhiteSpace($AdminUser)) {
  $AdminUser = "admin"
}

if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
  $AdminPassword = "admin123"
}

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $RootDir "data"
$DbFile = Join-Path $DataDir "database.json"

$ServiceCatalog = @(
  [pscustomobject]@{
    id = "gates-grills"
    name = "Gates & Grills"
    startingPrice = "From Rs 220/sq ft"
    summary = "Main gates, sliding gates, window grills, balcony grills, and decorative security work."
  },
  [pscustomobject]@{
    id = "railings-staircases"
    name = "Railings & Staircases"
    startingPrice = "From Rs 650/running ft"
    summary = "MS and stainless steel railings, staircases, handrails, and balcony protection."
  },
  [pscustomobject]@{
    id = "sheds-structures"
    name = "Sheds & Structures"
    startingPrice = "From Rs 145/sq ft"
    summary = "Parking sheds, roof frames, shopfront frames, mezzanine supports, and light structures."
  },
  [pscustomobject]@{
    id = "repair-modification"
    name = "Repair & Modification"
    startingPrice = "Inspection-based estimate"
    summary = "Repair, extension, alignment, strengthening, repainting, and custom workshop jobs."
  }
)

$MimeTypes = @{
  ".html" = "text/html; charset=utf-8"
  ".css" = "text/css; charset=utf-8"
  ".js" = "application/javascript; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".png" = "image/png"
  ".jpg" = "image/jpeg"
  ".jpeg" = "image/jpeg"
  ".webp" = "image/webp"
  ".svg" = "image/svg+xml"
  ".ico" = "image/x-icon"
}

function Get-NowIso {
  return [DateTimeOffset]::UtcNow.ToString("o")
}

function New-RecordId($Prefix) {
  $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString("x")
  $random = [Guid]::NewGuid().ToString("N").Substring(0, 8)
  return "$Prefix`_$stamp`_$random"
}

function ConvertTo-SafeText($Value, [int]$Max = 500) {
  if ($null -eq $Value) {
    return ""
  }

  $text = [string]$Value
  $text = $text.Trim()
  if ($text.Length -gt $Max) {
    return $text.Substring(0, $Max)
  }
  return $text
}

function ConvertTo-SafePhone($Value) {
  $phone = ConvertTo-SafeText $Value 40
  return ($phone -replace "[^\d+()\-\s]", "")
}

function Ensure-Database {
  if (-not (Test-Path -LiteralPath $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir | Out-Null
  }

  if (-not (Test-Path -LiteralPath $DbFile)) {
    [pscustomobject]@{
      enquiries = @()
      orders = @()
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $DbFile -Encoding UTF8
  }
}

function Read-Database {
  Ensure-Database
  $raw = Get-Content -LiteralPath $DbFile -Raw -Encoding UTF8
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return [pscustomobject]@{ enquiries = @(); orders = @() }
  }

  $db = $raw | ConvertFrom-Json
  if ($null -eq $db.PSObject.Properties["enquiries"]) {
    $db | Add-Member -MemberType NoteProperty -Name enquiries -Value @()
  }
  if ($null -eq $db.PSObject.Properties["orders"]) {
    $db | Add-Member -MemberType NoteProperty -Name orders -Value @()
  }
  return $db
}

function Save-Database($Db) {
  $Db | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $DbFile -Encoding UTF8
}

function Send-Text($Context, [int]$Status, [string]$Text, [string]$ContentType = "text/plain; charset=utf-8") {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Context.Response.StatusCode = $Status
  $Context.Response.ContentType = $ContentType
  $Context.Response.ContentLength64 = $bytes.Length
  $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Context.Response.OutputStream.Close()
}

function Send-Json($Context, [int]$Status, $Payload) {
  $json = $Payload | ConvertTo-Json -Depth 20
  $Context.Response.Headers.Set("Cache-Control", "no-store")
  Send-Text $Context $Status $json "application/json; charset=utf-8"
}

function Send-Error($Context, [int]$Status, [string]$Message, $Details = $null) {
  Send-Json $Context $Status ([pscustomobject]@{
    ok = $false
    message = $Message
    details = $Details
  })
}

function Read-RequestBody($Request) {
  $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
  $raw = $reader.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return [pscustomobject]@{}
  }

  if (($Request.ContentType -as [string]) -like "*application/json*") {
    return $raw | ConvertFrom-Json
  }

  $obj = [pscustomobject]@{}
  foreach ($pair in $raw.Split("&")) {
    if ([string]::IsNullOrWhiteSpace($pair)) { continue }
    $parts = $pair.Split("=", 2)
    $key = [System.Uri]::UnescapeDataString($parts[0])
    $value = if ($parts.Count -gt 1) { [System.Uri]::UnescapeDataString($parts[1].Replace("+", " ")) } else { "" }
    $obj | Add-Member -MemberType NoteProperty -Name $key -Value $value -Force
  }
  return $obj
}

function Get-BodyField($Body, [string]$Name, [int]$Max = 500) {
  $property = $Body.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return ""
  }
  return ConvertTo-SafeText $property.Value $Max
}

function Test-AdminAuth($Request) {
  $header = $Request.Headers["Authorization"]
  if ([string]::IsNullOrWhiteSpace($header) -or -not $header.StartsWith("Basic ")) {
    return $false
  }

  try {
    $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($header.Substring(6)))
    $parts = $decoded.Split(":", 2)
    return ($parts.Count -eq 2 -and $parts[0] -eq $AdminUser -and $parts[1] -eq $AdminPassword)
  } catch {
    return $false
  }
}

function Require-Admin($Context) {
  if (Test-AdminAuth $Context.Request) {
    return $true
  }

  $Context.Response.Headers.Set("WWW-Authenticate", 'Basic realm="Gupta Fabricator Admin"')
  Send-Error $Context 401 "Admin login required."
  return $false
}

function Get-ClientMeta($Request) {
  return @{
    ip = if ($Request.Headers["X-Forwarded-For"]) { $Request.Headers["X-Forwarded-For"] } else { $Request.RemoteEndPoint.ToString() }
    userAgent = if ($Request.Headers["User-Agent"]) { $Request.Headers["User-Agent"] } else { "" }
  }
}

function New-EnquiryRecord($Body, $Request) {
  $meta = Get-ClientMeta $Request
  return [pscustomobject]@{
    id = New-RecordId "enq"
    createdAt = Get-NowIso
    name = Get-BodyField $Body "name" 120
    phone = ConvertTo-SafePhone (Get-BodyField $Body "phone" 40)
    email = Get-BodyField $Body "email" 160
    project = Get-BodyField $Body "project" 120
    message = Get-BodyField $Body "message" 1600
    source = if (Get-BodyField $Body "source" 80) { Get-BodyField $Body "source" 80 } else { "contact-form" }
    status = "new"
    ip = $meta.ip
    userAgent = $meta.userAgent
  }
}

function New-OrderRecord($Body, $Request) {
  $serviceId = Get-BodyField $Body "serviceId" 80
  $service = $ServiceCatalog | Where-Object { $_.id -eq $serviceId } | Select-Object -First 1
  $meta = Get-ClientMeta $Request

  return [pscustomobject]@{
    id = New-RecordId "ord"
    createdAt = Get-NowIso
    serviceId = $serviceId
    serviceName = if ($service) { $service.name } else { Get-BodyField $Body "serviceName" 140 }
    startingPrice = if ($service) { $service.startingPrice } else { "" }
    name = Get-BodyField $Body "name" 120
    phone = ConvertTo-SafePhone (Get-BodyField $Body "phone" 40)
    email = Get-BodyField $Body "email" 160
    address = Get-BodyField $Body "address" 500
    size = Get-BodyField $Body "size" 120
    finish = Get-BodyField $Body "finish" 120
    preferredDate = Get-BodyField $Body "preferredDate" 40
    notes = Get-BodyField $Body "notes" 1600
    status = "new"
    ip = $meta.ip
    userAgent = $meta.userAgent
  }
}

function Get-Summary($Db) {
  $enquiries = @($Db.enquiries)
  $orders = @($Db.orders)
  return [pscustomobject]@{
    totalEnquiries = $enquiries.Count
    totalOrders = $orders.Count
    openEnquiries = @($enquiries | Where-Object { $_.status -notin @("closed", "won") }).Count
    openOrders = @($orders | Where-Object { $_.status -notin @("completed", "cancelled") }).Count
    updatedAt = Get-NowIso
  }
}

function Set-ObjectProperty($Object, [string]$Name, $Value) {
  if ($Object.PSObject.Properties[$Name]) {
    $Object.$Name = $Value
  } else {
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
  }
}

function ConvertTo-CsvText($Rows, $Fields) {
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add((($Fields | ForEach-Object { '"' + ($_.label -replace '"', '""') + '"' }) -join ","))

  foreach ($row in @($Rows)) {
    $line = (($Fields | ForEach-Object {
      $value = ""
      if ($row.PSObject.Properties[$_.key]) {
        $value = [string]$row.$($_.key)
      }
      '"' + ($value -replace '"', '""') + '"'
    }) -join ",")
    $lines.Add($line)
  }

  return ($lines -join "`r`n") + "`r`n"
}

function Send-Csv($Context, [string]$Type) {
  if (-not (Require-Admin $Context)) { return }
  $db = Read-Database
  $rows = if ($Type -eq "orders") { @($db.orders) } else { @($db.enquiries) }

  if ($Type -eq "orders") {
    $fields = @(
      @{ label = "ID"; key = "id" },
      @{ label = "Created At"; key = "createdAt" },
      @{ label = "Status"; key = "status" },
      @{ label = "Service"; key = "serviceName" },
      @{ label = "Starting Price"; key = "startingPrice" },
      @{ label = "Name"; key = "name" },
      @{ label = "Phone"; key = "phone" },
      @{ label = "Email"; key = "email" },
      @{ label = "Address"; key = "address" },
      @{ label = "Size"; key = "size" },
      @{ label = "Finish"; key = "finish" },
      @{ label = "Preferred Date"; key = "preferredDate" },
      @{ label = "Notes"; key = "notes" }
    )
  } else {
    $fields = @(
      @{ label = "ID"; key = "id" },
      @{ label = "Created At"; key = "createdAt" },
      @{ label = "Status"; key = "status" },
      @{ label = "Project"; key = "project" },
      @{ label = "Name"; key = "name" },
      @{ label = "Phone"; key = "phone" },
      @{ label = "Email"; key = "email" },
      @{ label = "Message"; key = "message" },
      @{ label = "Source"; key = "source" }
    )
  }

  $csv = ConvertTo-CsvText $rows $fields
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($csv)
  $date = (Get-Date).ToString("yyyy-MM-dd")
  $Context.Response.StatusCode = 200
  $Context.Response.ContentType = "text/csv; charset=utf-8"
  $Context.Response.Headers.Set("Content-Disposition", "attachment; filename=`"$Type-$date.csv`"")
  $Context.Response.Headers.Set("Cache-Control", "no-store")
  $Context.Response.ContentLength64 = $bytes.Length
  $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Context.Response.OutputStream.Close()
}

function Handle-Api($Context, [string]$Path, [string]$Method) {
  if ($Method -eq "GET" -and $Path -eq "/api/health") {
    Send-Json $Context 200 ([pscustomobject]@{ ok = $true; service = "Gupta Fabricator backend"; time = Get-NowIso })
    return
  }

  if ($Method -eq "GET" -and $Path -eq "/api/services") {
    Send-Json $Context 200 ([pscustomobject]@{ ok = $true; services = $ServiceCatalog })
    return
  }

  if ($Method -eq "POST" -and $Path -eq "/api/enquiries") {
    try {
      $body = Read-RequestBody $Context.Request
      $record = New-EnquiryRecord $body $Context.Request
      $errors = @()
      if (-not $record.name) { $errors += "Name is required." }
      if (-not $record.phone) { $errors += "Phone number is required." }
      if (-not $record.project) { $errors += "Project type is required." }
      if ($errors.Count -gt 0) {
        Send-Error $Context 422 "Please complete the required enquiry fields." $errors
        return
      }

      $db = Read-Database
      $db.enquiries = @($record) + @($db.enquiries)
      Save-Database $db
      Send-Json $Context 201 ([pscustomobject]@{ ok = $true; message = "Enquiry saved."; enquiry = $record })
    } catch {
      Send-Error $Context 400 "Could not save enquiry."
    }
    return
  }

  if ($Method -eq "POST" -and $Path -eq "/api/orders") {
    try {
      $body = Read-RequestBody $Context.Request
      $record = New-OrderRecord $body $Context.Request
      $validService = @($ServiceCatalog | Where-Object { $_.id -eq $record.serviceId }).Count -gt 0
      $errors = @()
      if (-not $validService) { $errors += "Please choose a valid service." }
      if (-not $record.name) { $errors += "Name is required." }
      if (-not $record.phone) { $errors += "Phone number is required." }
      if (-not $record.address) { $errors += "Site address is required." }
      if ($errors.Count -gt 0) {
        Send-Error $Context 422 "Please complete the required order fields." $errors
        return
      }

      $db = Read-Database
      $db.orders = @($record) + @($db.orders)
      Save-Database $db
      Send-Json $Context 201 ([pscustomobject]@{ ok = $true; message = "Service order saved."; order = $record })
    } catch {
      Send-Error $Context 400 "Could not save order."
    }
    return
  }

  if ($Method -eq "GET" -and $Path -eq "/api/admin/summary") {
    if (-not (Require-Admin $Context)) { return }
    $db = Read-Database
    Send-Json $Context 200 ([pscustomobject]@{ ok = $true; summary = Get-Summary $db })
    return
  }

  if ($Method -eq "GET" -and $Path -eq "/api/admin/enquiries") {
    if (-not (Require-Admin $Context)) { return }
    $db = Read-Database
    Send-Json $Context 200 ([pscustomobject]@{ ok = $true; records = @($db.enquiries); summary = Get-Summary $db })
    return
  }

  if ($Method -eq "GET" -and $Path -eq "/api/admin/orders") {
    if (-not (Require-Admin $Context)) { return }
    $db = Read-Database
    Send-Json $Context 200 ([pscustomobject]@{ ok = $true; records = @($db.orders); summary = Get-Summary $db })
    return
  }

  $statusMatch = [regex]::Match($Path, "^/api/admin/(enquiries|orders)/([^/]+)/status$")
  if ($Method -eq "PATCH" -and $statusMatch.Success) {
    if (-not (Require-Admin $Context)) { return }
    try {
      $type = $statusMatch.Groups[1].Value
      $id = [System.Uri]::UnescapeDataString($statusMatch.Groups[2].Value)
      $body = Read-RequestBody $Context.Request
      $nextStatus = Get-BodyField $body "status" 40
      $allowed = if ($type -eq "orders") { @("new", "confirmed", "in_progress", "completed", "cancelled") } else { @("new", "contacted", "quoted", "won", "closed") }
      if ($nextStatus -notin $allowed) {
        Send-Error $Context 422 "Invalid status."
        return
      }

      $db = Read-Database
      $items = if ($type -eq "orders") { @($db.orders) } else { @($db.enquiries) }
      $record = $items | Where-Object { $_.id -eq $id } | Select-Object -First 1
      if (-not $record) {
        Send-Error $Context 404 "Record not found."
        return
      }

      Set-ObjectProperty $record "status" $nextStatus
      Set-ObjectProperty $record "updatedAt" (Get-NowIso)
      if ($type -eq "orders") { $db.orders = $items } else { $db.enquiries = $items }
      Save-Database $db
      Send-Json $Context 200 ([pscustomobject]@{ ok = $true; record = $record })
    } catch {
      Send-Error $Context 400 "Could not update status."
    }
    return
  }

  $exportMatch = [regex]::Match($Path, "^/api/export/(enquiries|orders)\.csv$")
  if ($Method -eq "GET" -and $exportMatch.Success) {
    Send-Csv $Context $exportMatch.Groups[1].Value
    return
  }

  Send-Error $Context 404 "API route not found."
}

function Resolve-StaticPath([string]$UrlPath) {
  $decodedPath = [System.Uri]::UnescapeDataString($UrlPath)
  if ($decodedPath -eq "/") {
    $decodedPath = "/index.html"
  }

  $relative = $decodedPath.TrimStart("/") -replace "/", [System.IO.Path]::DirectorySeparatorChar
  if ([string]::IsNullOrWhiteSpace($relative)) { return $null }
  if ($relative.Contains("..")) { return $null }
  $relativeLower = $relative.ToLowerInvariant()
  if ($relativeLower.StartsWith(".git") -or $relativeLower.StartsWith("data")) { return $null }

  $blocked = @("server.ps1", "start-backend.bat", ".gitignore", "BACKEND.md", "package.json", "server.js")
  if ($relativeLower -in $blocked) { return $null }

  $filePath = Join-Path $RootDir $relative
  $extension = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
  if (-not $MimeTypes.ContainsKey($extension)) { return $null }
  if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { return $null }

  return $filePath
}

function Serve-Static($Context, [string]$Path, [string]$Method) {
  if ($Method -ne "GET" -and $Method -ne "HEAD") {
    Send-Text $Context 405 "Method not allowed"
    return
  }

  $filePath = Resolve-StaticPath $Path
  if (-not $filePath) {
    Send-Text $Context 404 "Not found"
    return
  }

  $extension = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
  $bytes = [System.IO.File]::ReadAllBytes($filePath)
  $Context.Response.StatusCode = 200
  $Context.Response.ContentType = $MimeTypes[$extension]
  $Context.Response.Headers.Set("Cache-Control", $(if ($extension -eq ".html") { "no-store" } else { "public, max-age=3600" }))
  $Context.Response.ContentLength64 = if ($Method -eq "HEAD") { 0 } else { $bytes.Length }
  if ($Method -ne "HEAD") {
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  }
  $Context.Response.OutputStream.Close()
}

function Handle-Request($Context) {
  $path = $Context.Request.Url.AbsolutePath
  $method = $Context.Request.HttpMethod.ToUpperInvariant()

  try {
    if ($path.StartsWith("/api/")) {
      Handle-Api $Context $path $method
    } else {
      Serve-Static $Context $path $method
    }
  } catch {
    Write-Host $_
    Send-Error $Context 500 "Server error."
  }
}

Ensure-Database

$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)

try {
  $listener.Start()
  Write-Host "Gupta Fabricator backend running at $prefix"
  Write-Host "Website: $prefix`index11.html"
  Write-Host "Admin dashboard: $prefix`admin.html"
  if ($AdminPassword -eq "admin123") {
    Write-Host "Default admin password is admin123. Set ADMIN_PASSWORD before going live."
  }
  Write-Host "Press Ctrl+C to stop."

  while ($listener.IsListening) {
    $context = $listener.GetContext()
    Handle-Request $context
  }
} finally {
  if ($listener.IsListening) {
    $listener.Stop()
  }
  $listener.Close()
}
