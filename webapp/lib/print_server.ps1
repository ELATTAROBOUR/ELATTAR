<#
.SYNOPSIS
    ELATTAR Print Server - Local HTTP server for thermal printer communication.
.DESCRIPTION
    This script runs a lightweight HTTP server on localhost that bridges the
    web app to ESC/POS thermal printers (XP-370B, XP-80C) via Windows USB/serial ports.
    
    It uses WMI to find printer port names by printer name, then sends raw
    ESC/POS data to the port (USBxxx or COMxxx).
    
    USAGE:
        powershell -ExecutionPolicy Bypass -File print_server.ps1
    
    The server listens on http://localhost:19283 and provides:
        GET  /status          → Server & printer status
        POST /print/label     → Print to label printer (XP-370B)
        POST /print/receipt   → Print to receipt printer (XP-80C)
#>

param(
    [int]$Port = 19283,
    [string]$LabelPrinter = "Xprinter XP-370B (Copy 1)",
    [string]$ReceiptPrinter = "XP-80C"
)

Add-Type -AssemblyName System.IO.Ports
Add-Type -AssemblyName System.Management

$script:running = $true
$script:connections = @{}  # "label" / "receipt" → port object

# ─── Helper Functions ───────────────────────────────────────────────────────

function Get-PrinterPortName {
    param([string]$PrinterName)
    try {
        $searcher = New-Object System.Management.ManagementObjectSearcher(
            "SELECT * FROM Win32_Printer WHERE Name = '$PrinterName'"
        )
        $printer = $searcher.Get() | Select-Object -First 1
        if ($printer) {
            $portName = $printer.PortName  # e.g., "USB001", "COM3"
            Write-Host "[OK] Printer '$PrinterName' → Port: $portName"
            return $portName
        }
        Write-Host "[WARN] Printer '$PrinterName' not found in Windows"
        return $null
    } catch {
        Write-Host "[ERR] WMI query failed: $_"
        return $null
    }
}

function Open-PrinterPort {
    param([string]$PortName)
    try {
        if ($PortName -match '^COM\d+$') {
            # Serial port
            $port = New-Object System.IO.Ports.SerialPort
            $port.PortName = $PortName
            $port.BaudRate = 9600
            $port.DataBits = 8
            $port.StopBits = [System.IO.Ports.StopBits]::One
            $port.Parity = [System.IO.Ports.Parity]::None
            $port.ReadTimeout = 1000
            $port.WriteTimeout = 5000
            $port.Open()
            Write-Host "[OK] Opened serial port: $PortName"
            return $port
        } elseif ($PortName -match '^USB\d+$') {
            # USB virtual printer port - use FileStream to write raw data
            $path = "\\localhost\$PortName"
            $stream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
            Write-Host "[OK] Opened USB port: $PortName"
            return $stream
        } else {
            Write-Host "[ERR] Unknown port type: $PortName"
            return $null
        }
    } catch {
        Write-Host "[ERR] Failed to open port '$PortName': $_"
        return $null
    }
}

function Close-PrinterPort {
    param($PortObj)
    try {
        if ($PortObj -is [System.IO.Ports.SerialPort]) {
            if ($PortObj.IsOpen) { $PortObj.Close() }
            $PortObj.Dispose()
        } elseif ($PortObj -is [System.IO.Stream]) {
            $PortObj.Close()
            $PortObj.Dispose()
        }
    } catch { Write-Host "[WARN] Error closing port: $_" }
}

function Send-RawData {
    param($PortObj, [byte[]]$Data)
    if (-not $PortObj) { return $false }
    try {
        if ($PortObj -is [System.IO.Ports.SerialPort]) {
            $PortObj.Write($Data, 0, $Data.Length)
        } elseif ($PortObj -is [System.IO.Stream]) {
            $PortObj.Write($Data, 0, $Data.Length)
            $PortObj.Flush()
        }
        return $true
    } catch {
        Write-Host "[ERR] Write failed: $_"
        return $false
    }
}

# ─── HTTP Server ────────────────────────────────────────────────────────────

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "============================================"
Write-Host "  ELATTAR Print Server"
Write-Host "  Label printer  : $LabelPrinter"
Write-Host "  Receipt printer: $ReceiptPrinter"
Write-Host "  Listening on   : http://localhost:$Port/"
Write-Host "============================================"
Write-Host ""

# Auto-connect on startup
Write-Host "[INIT] Connecting to label printer..."
$labelPortName = Get-PrinterPortName -PrinterName $LabelPrinter
if ($labelPortName) {
    $port = Open-PrinterPort -PortName $labelPortName
    if ($port) { $script:connections["label"] = @{PortName=$labelPortName; Port=$port} }
}

Write-Host "[INIT] Connecting to receipt printer..."
$receiptPortName = Get-PrinterPortName -PrinterName $ReceiptPrinter
if ($receiptPortName) {
    $port = Open-PrinterPort -PortName $receiptPortName
    if ($port) { $script:connections["receipt"] = @{PortName=$receiptPortName; Port=$port} }
}
Write-Host ""

while ($script:running) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    $bodyBytes = $null
    try {
        if ($request.InputStream) {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $bodyText = $reader.ReadToEnd()
            $reader.Close()
            if ($bodyText -and $bodyText.Length -gt 0) {
                $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyText)
            }
        }
    } catch { }

    $urlPath = $request.Url.AbsolutePath.Trim('/').ToLower()
    $method = $request.HttpMethod.ToUpper()

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $method /$urlPath"

    $responseHeaders = $response.Headers
    $responseHeaders.Add("Access-Control-Allow-Origin", "*")
    $responseHeaders.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $responseHeaders.Add("Access-Control-Allow-Headers", "Content-Type")
    $responseHeaders.Add("Content-Type", "application/json")

    # Handle CORS preflight
    if ($method -eq "OPTIONS") {
        $response.StatusCode = 204
        $response.Close()
        continue
    }

    $resultJson = ""

    if ($method -eq "GET" -and $urlPath -eq "status") {
        $labelConnected = $script:connections.ContainsKey("label") -and $script:connections["label"].Port -ne $null
        $receiptConnected = $script:connections.ContainsKey("receipt") -and $script:connections["receipt"].Port -ne $null
        $resultJson = @{
            status = "running"
            labelPrinter = @{
                name = $LabelPrinter
                portName = if ($labelConnected) { $script:connections["label"].PortName } else { $null }
                connected = $labelConnected
            }
            receiptPrinter = @{
                name = $ReceiptPrinter
                portName = if ($receiptConnected) { $script:connections["receipt"].PortName } else { $null }
                connected = $receiptConnected
            }
        } | ConvertTo-Json
    }
    elseif ($method -eq "POST") {
        $printerKey = $null
        if ($urlPath -eq "print/label")  { $printerKey = "label" }
        if ($urlPath -eq "print/receipt") { $printerKey = "receipt" }

        if (-not $printerKey) {
            $resultJson = @{success=$false; error="Unknown endpoint: /$urlPath"} | ConvertTo-Json
        }
        elseif (-not $script:connections.ContainsKey($printerKey) -or -not $script:connections[$printerKey].Port) {
            $resultJson = @{success=$false; error="Printer not connected"} | ConvertTo-Json
        }
        else {
            $parsed = $null
            try { $parsed = $bodyText | ConvertFrom-Json } catch {}
            
            if (-not $parsed -or -not $parsed.data) {
                $resultJson = @{success=$false; error="Missing 'data' field (base64) in request body"} | ConvertTo-Json
            } else {
                try {
                    $rawBytes = [System.Convert]::FromBase64String($parsed.data)
                    $portObj = $script:connections[$printerKey].Port
                    $ok = Send-RawData -PortObj $portObj -Data $rawBytes
                    $resultJson = @{success=$ok; error=if(-not$ok){"Write failed"}} | ConvertTo-Json
                    Write-Host "  -> Printed $($rawBytes.Length) bytes to $printerKey"
                } catch {
                    $resultJson = @{success=$false; error="Base64 decode error: $_"} | ConvertTo-Json
                }
            }
        }
    }
    else {
        $resultJson = @{success=$false; error="Method not supported"} | ConvertTo-Json
    }

    $buffer = [System.Text.Encoding]::UTF8.GetBytes($resultJson)
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.Close()
}

$listener.Stop()
# Cleanup
foreach ($key in $script:connections.Keys) {
    Close-PrinterPort -PortObj $script:connections[$key].Port
}
Write-Host "[SHUTDOWN] Print server stopped."
