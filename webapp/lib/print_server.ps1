<#
.SYNOPSIS
  ELATTAR Print Server — local HTTP bridge for PDF printing from the web app.

.DESCRIPTION
  Lightweight PowerShell HTTP server that lets the Flutter web app print PDF
  documents directly to Windows printers — no browser print dialog needed.
  Also enumerates installed printers for auto-detection.

USAGE
  powershell -ExecutionPolicy Bypass -File print_server.ps1
  (Run this once on the Windows machine; keep it open while using the web app.)

ENDPOINTS
  GET  /status          → { "status": "ok", "port": 19283, "os": "Windows ..." }
  GET  /list-printers   → [ { "name": "...", "isDefault": true/false }, ... ]
  POST /print           → Print a PDF (multipart: field "printer" + file "file")

  The /print endpoint expects:
    - printer (string): Name of the target printer
    - file    (binary): The PDF bytes to print

  Returns 200 { "success": true, "message": "..." }
  Returns 400/500 { "success": false, "error": "..." }

.NOTES
  Port : 19283  (change via -Port parameter)
  CORS : Enabled for any origin (required by GitHub Pages / local dev servers)
#>

param(
  [int]$Port = 19283
)

# ─── Helper: Send HTTP response ─────────────────────────────────────────────
function Send-Response {
  param(
    $Context,
    [int]$StatusCode = 200,
    [string]$ContentType = 'application/json; charset=utf-8',
    $Body
  )
  $response = $Context.Response
  $response.StatusCode = $StatusCode
  $response.ContentType = $ContentType

  # CORS headers — allow requests from any origin
  $response.Headers.Add('Access-Control-Allow-Origin', '*')
  $response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
  $response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')

  if ($Body -ne $null) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
  }
  $response.OutputStream.Close()
}

# ─── Helper: JSON encode ────────────────────────────────────────────────────
function To-Json {
  param($Obj)
  return ConvertTo-Json -InputObject $Obj -Compress -Depth 3
}

# ─── GET /status ────────────────────────────────────────────────────────────
function Handle-Status {
  param($Context)
  $info = @{
    status = 'ok'
    port   = $Port
    os     = (Get-CimInstance Win32_OperatingSystem).Caption
  }
  Send-Response -Context $Context -Body (To-Json $info)
}

# ─── GET /list-printers ────────────────────────────────────────────────────
function Handle-ListPrinters {
  param($Context)
  try {
    $printers = Get-CimInstance Win32_Printer | Where-Object { $_.Name -ne $null } | ForEach-Object {
      @{
        name      = $_.Name
        isDefault = [bool]$_.Default
        status    = if ($_.PrinterStatus -eq 3) { 'idle' } else { 'busy' }
      }
    }
    Send-Response -Context $Context -Body (To-Json @($printers))
  } catch {
    Send-Response -Context $Context -StatusCode 500 -Body (To-Json @{ success = $false; error = $_.Exception.Message })
  }
}

# ─── POST /print ────────────────────────────────────────────────────────────
function Handle-Print {
  param($Context)

  try {
    $request = $Context.Request

    # --- Parse multipart/form-data ---
    $contentType = $request.ContentType
    if ($contentType -notmatch 'multipart/form-data;\s*boundary=(.+)') {
      Send-Response -Context $Context -StatusCode 400 -Body (To-Json @{
        success = $false
        error   = 'Expected multipart/form-data with boundary'
      })
      return
    }
    $boundary = $Matches[1]

    # Read the entire request body
    $buffer = New-Object byte[] 1048576  # 1 MB chunks
    $ms = New-Object System.IO.MemoryStream
    try {
      do {
        $read = $request.InputStream.Read($buffer, 0, $buffer.Length)
        if ($read -gt 0) { $ms.Write($buffer, 0, $read) }
      } while ($read -gt 0)
    } finally {
      $request.InputStream.Close()
    }
    $bodyBytes = $ms.ToArray()
    $ms.Dispose()

    # Simple multipart parser
    $delimiter = [System.Text.Encoding]::ASCII.GetBytes("--$boundary")
    $newline   = [System.Text.Encoding]::ASCII.GetBytes("`r`n")

    $printerName = $null
    $pdfBytes    = $null

    $idx = 0
    while ($idx -lt $bodyBytes.Length) {
      # Find next boundary
      $boundaryStart = [System.Array]::IndexOf($bodyBytes, [byte]'-', $idx)
      if ($boundaryStart -eq -1 -or $boundaryStart -ge $bodyBytes.Length - 2) { break }
      # Check if it starts with --
      if ($bodyBytes[$boundaryStart] -ne 0x2D -or $bodyBytes[$boundaryStart+1] -ne 0x2D) { break }

      $partStart = $boundaryStart
      # Find end of boundary line
      $eol = [System.Array]::IndexOf($bodyBytes, [byte]0x0A, $partStart)
      if ($eol -eq -1) { break }
      # Skip past the newline after boundary
      $partHeaderStart = $eol + 1
      if ($partHeaderStart -ge $bodyBytes.Length) { break }

      # Find blank line (end of headers)
      $blankLine = -1
      for ($i = $partHeaderStart; $i -lt $bodyBytes.Length - 3; $i++) {
        if ($bodyBytes[$i] -eq 0x0D -and $bodyBytes[$i+1] -eq 0x0A -and
            $bodyBytes[$i+2] -eq 0x0D -and $bodyBytes[$i+3] -eq 0x0A) {
          $blankLine = $i
          break
        }
      }
      if ($blankLine -eq -1) { break }

      # Read headers
      $headerBytes = $bodyBytes[$partHeaderStart..($blankLine - 1)]
      $headers = [System.Text.Encoding]::ASCII.GetString($headerBytes)

      # Content start
      $contentStart = $blankLine + 4

      # Find next boundary
      $nextBoundary = $bodyBytes.Length
      $searchFrom = $contentStart
      while ($searchFrom -lt $bodyBytes.Length) {
        $bStart = [System.Array]::IndexOf($bodyBytes, [byte]'-', $searchFrom)
        if ($bStart -eq -1 -or $bStart -ge $bodyBytes.Length - 2) { $nextBoundary = $bodyBytes.Length; break }
        if ($bodyBytes[$bStart] -eq 0x2D -and $bodyBytes[$bStart+1] -eq 0x2D) {
          # Check if -1 is newline or start
          if ($bStart -eq 0 -or $bodyBytes[$bStart-1] -eq 0x0A) {
            $nextBoundary = $bStart
            break
          }
        }
        $searchFrom = $bStart + 1
      }

      # Content (trim trailing \r\n)
      $contentEnd = $nextBoundary
      if ($contentEnd -ge 2 -and $bodyBytes[$contentEnd-2] -eq 0x0D -and $bodyBytes[$contentEnd-1] -eq 0x0A) {
        $contentEnd -= 2
      }
      $contentLength = $contentEnd - $contentStart
      if ($contentLength -le 0) { break }

      $contentBytes = $bodyBytes[$contentStart..($contentEnd - 1)]

      # Check if it's the printer name field
      if ($headers -match 'name="printer"') {
        $printerName = [System.Text.Encoding]::UTF8.GetString($contentBytes)
      }
      # Check if it's the file
      elseif ($headers -match 'name="file"') {
        $pdfBytes = $contentBytes
      }

      $idx = $nextBoundary
    }

    # --- Validate ---
    if ([string]::IsNullOrWhiteSpace($printerName)) {
      Send-Response -Context $Context -StatusCode 400 -Body (To-Json @{
        success = $false
        error   = 'Missing "printer" field'
      })
      return
    }
    if ($pdfBytes -eq $null -or $pdfBytes.Length -eq 0) {
      Send-Response -Context $Context -StatusCode 400 -Body (To-Json @{
        success = $false
        error   = 'Missing or empty "file" (PDF)'
      })
      return
    }

    # --- Save PDF to temp file ---
    $tempFile = [System.IO.Path]::GetTempFileName() + '.pdf'
    [System.IO.File]::WriteAllBytes($tempFile, $pdfBytes)

    try {
      Write-Host "[PRINT] Sending to printer: $printerName"

      # Print using Start-Process -Verb PrintTo (works with Edge, Adobe, etc.)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $tempFile
      $psi.Verb = 'PrintTo'
      $psi.Arguments = "`"$printerName`""
      $psi.UseShellExecute = $true
      $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
      $proc = [System.Diagnostics.Process]::Start($psi)

      if ($proc -eq $null) {
        throw "Failed to start print process - no PDF viewer with PrintTo support?"
      }

      # Wait up to 30 seconds for printing
      $proc.WaitForExit(30000) | Out-Null

      if ($proc.HasExited -and $proc.ExitCode -ne 0) {
        Write-Host "[WARN] Print process exited with code $($proc.ExitCode)"
      }

      Write-Host "[OK] Print job submitted to '$printerName'"

      Send-Response -Context $Context -Body (To-Json @{
        success = $true
        message = "تم إرسال مهمة الطباعة إلى $printerName"
      })
    } catch {
      Write-Host "[ERR] Print failed: $_"
      Send-Response -Context $Context -StatusCode 500 -Body (To-Json @{
        success = $false
        error   = $_.Exception.Message
      })
    } finally {
      # Clean up temp file after 5 seconds (give print spooler time to read it)
      Start-Sleep -Seconds 5
      if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    }
  } catch {
    Write-Host "[ERR] /print handler: $_"
    Send-Response -Context $Context -StatusCode 500 -Body (To-Json @{
      success = $false
      error   = $_.Exception.Message
    })
  }
}

# ─── Main HTTP server loop ──────────────────────────────────────────────────
try {
  $listener = New-Object System.Net.HttpListener
  $listener.Prefixes.Add("http://localhost:$Port/")
  $listener.Start()

  Write-Host ""
  Write-Host "╔══════════════════════════════════════════════════════════╗"
  Write-Host "║       ELATTAR Print Server                       ║"
  Write-Host "╠══════════════════════════════════════════════════════════╣"
  Write-Host "║  Listening on: http://localhost:$Port/                  ║"
  Write-Host "║  Endpoints:                                             ║"
  Write-Host "║    GET  /status          ─ Server health                ║"
  Write-Host "║    GET  /list-printers   ─ Installed printers           ║"
  Write-Host "║    POST /print           ─ Send PDF to printer          ║"
  Write-Host "╠══════════════════════════════════════════════════════════╣"
  Write-Host "║  Press Ctrl+C to stop.                                  ║"
  Write-Host "╚══════════════════════════════════════════════════════════╝"
  Write-Host ""

  while ($listener.IsListening) {
    try {
      $context = $listener.GetContext()
      $request = $context.Request
      $urlPath = $request.Url.AbsolutePath.TrimEnd('/')

      Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $($request.HttpMethod) $urlPath"

      # Handle CORS preflight
      if ($request.HttpMethod -eq 'OPTIONS') {
        Send-Response -Context $context -Body ''
        continue
      }

      # Route
      if ($urlPath -eq '/status' -or $urlPath -eq '') {
        Handle-Status -Context $context
      }
      elseif ($urlPath -eq '/list-printers') {
        Handle-ListPrinters -Context $context
      }
      elseif ($urlPath -eq '/print') {
        Handle-Print -Context $context
      }
      else {
        Send-Response -Context $context -StatusCode 404 -Body (To-Json @{
          error = "Unknown endpoint: $urlPath"
        })
      }
    } catch {
      Write-Host "[ERR] Request handler: $_"
    }
  }
} finally {
  if ($listener -and $listener.IsListening) { $listener.Stop() }
  Write-Host "[SHUTDOWN] Print server stopped."
}
