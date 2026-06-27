/**
 * Web Serial Printer Bridge
 * Standalone functions for ESC/POS printing via Web Serial API.
 * Called from Dart via dart:js_interop.
 * Supports multiple simultaneous printer connections keyed by type.
 */

// ─── Global State ──────────────────────────────────────────────────────────
window.__printerConnections = window.__printerConnections || {};
window.__printerSavedDevices = window.__printerSavedDevices || {};

// ─── Auto-Detection Initialization ─────────────────────────────────────────
(function _initPrinterBridge() {
  if (navigator.serial) {
    // When a serial device is connected AFTER page load, try to auto-reconnect
    // to any printer types that match the saved vendor/product IDs.
    navigator.serial.addEventListener('connect', async (event) => {
      const port = event.target;
      const info = port.getInfo();
      console.log('[PrinterBridge] Serial device connected:', info.usbVendorId, info.usbProductId);
      await _tryAutoReconnectAll();
    });

    // When a device is disconnected, clean up any stale connections.
    navigator.serial.addEventListener('disconnect', (event) => {
      const port = event.target;
      console.log('[PrinterBridge] Serial device disconnected');
      for (const type of Object.keys(window.__printerConnections)) {
        const conn = window.__printerConnections[type];
        if (conn && conn.port === port) {
          console.log('[PrinterBridge] Cleaned up connection for type:', type);
          delete window.__printerConnections[type];
        }
      }
    });
  }
})();

/**
 * Try to auto-reconnect all printer types that have saved device IDs.
 * Called on startup and when a serial device is connected.
 */
async function _tryAutoReconnectAll() {
  const saved = window.__printerSavedDevices || {};
  for (const type of Object.keys(saved)) {
    if (window.__printerConnections[type] && window.__printerConnections[type].port) {
      continue; // Already connected
    }
    const { vendorId, productId } = saved[type];
    if (vendorId != null) {
      await __printerAutoReconnect(type, vendorId, productId);
    }
  }
}

// ─── Connect (User-Initiated) ──────────────────────────────────────────────

/**
 * Request a serial port from the user via the browser chooser and open it.
 * On success, saves the device IDs both in JS (for onconnect) and returns them
 * to Dart (for persistent storage via DatabaseHelper).
 * @param {string} type - Printer type key ('label' or 'receipt')
 * @param {number|null} usbVendorId - Optional USB vendor ID filter
 * @param {number|null} usbProductId - Optional USB product ID filter
 * @returns {string} JSON: { success, vendorId?, productId?, error? }
 */
async function __printerConnect(type, usbVendorId, usbProductId) {
  try {
    const filters = [];
    if (usbVendorId != null) {
      const filter = { usbVendorId };
      if (usbProductId != null) {
        filter.usbProductId = usbProductId;
      }
      filters.push(filter);
    }
    const port = await navigator.serial.requestPort({
      filters: filters.length > 0 ? filters : undefined,
    });
    const info = port.getInfo();
    await port.open({
      baudRate: 9600,
      dataBits: 8,
      stopBits: 1,
      parity: 'none',
      flowControl: 'none',
    });
    const writer = port.writable.getWriter();
    window.__printerConnections[type] = { port, writer };

    // Save in JS for onconnect auto-detection
    __printerSetSavedDeviceIds(type, info.usbVendorId, info.usbProductId);

    return JSON.stringify({
      success: true,
      vendorId: info.usbVendorId,
      productId: info.usbProductId,
    });
  } catch (e) {
    if (e.name === 'NotFoundError') {
      return JSON.stringify({ success: false, cancelled: true });
    }
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

/**
 * Send raw bytes to a connected printer.
 * @param {string} type - Printer type key ('label' or 'receipt')
 * @param {Uint8Array} data - The ESC/POS raw bytes
 * @returns {string} JSON: { success, error? }
 */
async function __printerPrint(type, data) {
  try {
    const conn = window.__printerConnections[type];
    if (!conn || !conn.writer) {
      return JSON.stringify({ success: false, error: 'Printer not connected' });
    }
    // Web Serial API requires a BufferSource (Uint8Array, ArrayBuffer, etc.),
    // not a plain JS array. Convert if needed.
    const uint8Data = (data instanceof Uint8Array) ? data : new Uint8Array(data);
    await conn.writer.write(uint8Data);
    return JSON.stringify({ success: true });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

/**
 * Save USB vendor/product IDs for a printer type in JS bridge memory.
 * These are used by the onconnect handler to auto-reconnect when a device
 * is plugged in after page load.
 * Called from Dart on startup (after loading from DatabaseHelper)
 * and automatically after __printerConnect succeeds.
 * @param {string} type - Printer type key ('label' or 'receipt')
 * @param {number|null} usbVendorId - USB vendor ID
 * @param {number|null} usbProductId - USB product ID
 */
function __printerSetSavedDeviceIds(type, usbVendorId, usbProductId) {
  if (usbVendorId == null) {
    delete window.__printerSavedDevices[type];
  } else {
    window.__printerSavedDevices[type] = {
      vendorId: usbVendorId,
      productId: usbProductId,
    };
  }
}

/**
 * Get all saved device IDs as a JSON string.
 * Used for debugging and verification.
 * @returns {string} JSON: { label?: {vendorId, productId}, receipt?: ... }
 */
function __printerGetSavedDeviceIds() {
  return JSON.stringify(window.__printerSavedDevices);
}

/**
 * Scan all previously authorized serial ports without showing a dialog.
 * Returns basic info about each port (VID, PID).
 * @returns {string} JSON: { ports: [{vendorId, productId}], error? }
 */
async function __printerScanAllPorts() {
  try {
    const ports = await navigator.serial.getPorts();
    if (!ports || ports.length === 0) {
      return JSON.stringify({ ports: [] });
    }
    const results = [];
    for (const port of ports) {
      try {
        const info = port.getInfo();
        results.push({
          vendorId: info.usbVendorId,
          productId: info.usbProductId,
        });
      } catch (_) {
        // Skip ports that can't be queried
      }
    }
    return JSON.stringify({ ports: results });
  } catch (e) {
    return JSON.stringify({ ports: [], error: e.message || String(e) });
  }
}

/**
 * Disconnect and close a printer's serial port.
 * @param {string} type - Printer type key ('label' or 'receipt')
 * @returns {string} JSON: { success }
 */
async function __printerDisconnect(type) {
  try {
    const conn = window.__printerConnections[type];
    if (conn) {
      if (conn.writer) {
        try { await conn.writer.close(); } catch (_) {}
      }
      if (conn.port) {
        try { await conn.port.close(); } catch (_) {}
      }
      delete window.__printerConnections[type];
    }
    return JSON.stringify({ success: true });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

/**
 * Check if a specific printer type is connected.
 * @param {string} type - Printer type key ('label' or 'receipt')
 * @returns {string} JSON: { connected, vendorId?, productId? }
 */
function __printerIsConnected(type) {
  const conn = window.__printerConnections[type];
  if (conn && conn.port) {
    const info = conn.port.getInfo();
    return JSON.stringify({
      connected: true,
      vendorId: info.usbVendorId,
      productId: info.usbProductId,
    });
  }
  return JSON.stringify({ connected: false });
}

/**
 * Auto-reconnect to a previously authorized USB printer without showing a browser dialog.
 * Uses saved USB vendor/product IDs to find and reopen the matching port.
 * @param {string} type - Printer type key ('label' or 'receipt')
 * @param {number|null} usbVendorId - USB vendor ID to match
 * @param {number|null} usbProductId - USB product ID to match
 * @returns {string} JSON: { success, vendorId?, productId?, error? }
 */
async function __printerAutoReconnect(type, usbVendorId, usbProductId) {
  try {
    // Check if already connected for this type
    if (window.__printerConnections[type] && window.__printerConnections[type].port) {
      return JSON.stringify({ success: true });
    }

    const ports = await navigator.serial.getPorts();
    if (!ports || ports.length === 0) {
      return JSON.stringify({ success: false, error: 'No previously authorized ports' });
    }

    // Find a port matching the saved vendor/product ID
    for (const port of ports) {
      const info = port.getInfo();
      // If we have saved IDs, only match those; otherwise take any available port
      if (usbVendorId != null) {
        if (info.usbVendorId !== usbVendorId) continue;
        if (usbProductId != null && info.usbProductId !== usbProductId) continue;
      }

      // Found a matching port - try to open it
      try {
        await port.open({
          baudRate: 9600,
          dataBits: 8,
          stopBits: 1,
          parity: 'none',
          flowControl: 'none',
        });
        const writer = port.writable.getWriter();
        window.__printerConnections[type] = { port, writer };
        return JSON.stringify({
          success: true,
          vendorId: info.usbVendorId,
          productId: info.usbProductId,
        });
      } catch (_) {
        // Port might be already open or busy - try the next one
        continue;
      }
    }

    return JSON.stringify({ success: false, error: 'No matching port found' });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// WebUSB API (Alternative connection method for printers not visible via Web Serial)
// ═════════════════════════════════════════════════════════════════════════════

// Also listen for WebUSB device connect/disconnect events
(function _initWebUsb() {
  if (navigator.usb) {
    navigator.usb.addEventListener('connect', async (event) => {
      const device = event.target;
      console.log('[PrinterBridge] WebUSB device connected:', device.vendorId, device.productId, device.productName);
      await _tryAutoReconnectAllUsb();
    });

    navigator.usb.addEventListener('disconnect', (event) => {
      const device = event.target;
      console.log('[PrinterBridge] WebUSB device disconnected:', device.productName);
      for (const type of Object.keys(window.__printerConnections)) {
        const conn = window.__printerConnections[type];
        if (conn && conn.device === device) {
          console.log('[PrinterBridge] Cleaned up WebUSB connection for type:', type);
          delete window.__printerConnections[type];
        }
      }
    });
  }
})();

/**
 * Try to auto-reconnect all printer types via WebUSB (using saved IDs).
 */
async function _tryAutoReconnectAllUsb() {
  const saved = window.__printerSavedDevices || {};
  for (const type of Object.keys(saved)) {
    if (window.__printerConnections[type] && window.__printerConnections[type].device) {
      continue;
    }
    const { vendorId, productId } = saved[type];
    if (vendorId != null) {
      await __printerUsbAutoReconnect(type, vendorId, productId);
    }
  }
}

/**
 * Request a USB printer via WebUSB API (fallback if Web Serial doesn't find it).
 * Shows a browser chooser filtered by USB printer class (0x07) and vendor-specific (0xFF).
 * @param {string} type - Printer type key ('label' or 'receipt')
 * @returns {string} JSON: { success, vendorId?, productId?, productName?, error? }
 */
async function __printerUsbConnect(type) {
  try {
    if (!navigator.usb) {
      return JSON.stringify({ success: false, error: 'WebUSB API غير متاح في هذا المتصفح' });
    }

    // Request a USB device - try printer class first, then vendor-specific
    const device = await navigator.usb.requestDevice({
      filters: [
        { classCode: 7 },   // USB Printer Class
        { classCode: 255 }, // Vendor-specific (many POS thermal printers)
      ],
    });

    if (!device) {
      return JSON.stringify({ success: false, cancelled: true });
    }

    await device.open();
    if (device.configuration === null) {
      await device.selectConfiguration(1);
    }
    await device.claimInterface(0);

    // Find the OUT endpoint for sending data
    const outEndpoint = _findUsbOutEndpoint(device);

    // Store connection
    window.__printerConnections[type] = {
      device,
      usbProtocol: true,
      outEndpoint: outEndpoint,
    };

    // Save in JS for onconnect auto-detection
    __printerSetSavedDeviceIds(type, device.vendorId, device.productId);

    return JSON.stringify({
      success: true,
      vendorId: device.vendorId,
      productId: device.productId,
      productName: device.productName || null,
    });
  } catch (e) {
    if (e.name === 'NotFoundError') {
      return JSON.stringify({ success: false, cancelled: true });
    }
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

/**
 * Send raw bytes to a WebUSB-connected printer.
 * @param {string} type - Printer type key
 * @param {Uint8Array} data - Raw bytes to send
 * @returns {string} JSON: { success, error? }
 */
async function __printerUsbPrint(type, data) {
  try {
    const conn = window.__printerConnections[type];
    if (!conn || !conn.device) {
      return JSON.stringify({ success: false, error: 'الطابعة غير متصلة عبر WebUSB' });
    }

    const uint8Data = (data instanceof Uint8Array) ? data : new Uint8Array(data);

    if (conn.outEndpoint) {
      await conn.device.transferOut(conn.outEndpoint.endpointNumber, uint8Data);
    } else {
      // Fallback: try endpoint 2 (common for printer class devices)
      await conn.device.transferOut(2, uint8Data);
    }

    return JSON.stringify({ success: true });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

/**
 * Auto-reconnect to a previously authorized WebUSB device
 * (without showing a browser dialog).
 * @param {string} type - Printer type key
 * @param {number} usbVendorId - USB vendor ID to match
 * @param {number|null} usbProductId - USB product ID to match
 * @returns {string} JSON: { success, error? }
 */
async function __printerUsbAutoReconnect(type, usbVendorId, usbProductId) {
  try {
    if (!navigator.usb) {
      return JSON.stringify({ success: false, error: 'WebUSB not available' });
    }

    // Check if already connected for this type
    if (window.__printerConnections[type] && window.__printerConnections[type].device) {
      return JSON.stringify({ success: true });
    }

    const devices = await navigator.usb.getDevices();
    for (const device of devices) {
      if (device.vendorId === usbVendorId &&
          (usbProductId == null || device.productId === usbProductId)) {

        try {
          await device.open();
          if (device.configuration === null) {
            await device.selectConfiguration(1);
          }
          await device.claimInterface(0);

          const outEndpoint = _findUsbOutEndpoint(device);
          window.__printerConnections[type] = {
            device,
            usbProtocol: true,
            outEndpoint: outEndpoint,
          };

          return JSON.stringify({ success: true });
        } catch (_) {
          // Device might be busy - try next
          continue;
        }
      }
    }

    return JSON.stringify({ success: false, error: 'لم يتم العثور على طابعة WebUSB موافقة' });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

/**
 * Check if WebUSB API is available in this browser.
 * @returns {string} JSON: { available }
 */
function __printerUsbIsAvailable() {
  return JSON.stringify({ available: navigator.usb != null });
}

/**
 * Get all previously authorized WebUSB devices (no dialog).
 * @returns {string} JSON: { devices: [{vendorId, productId, productName}] }
 */
async function __printerUsbGetAuthorized() {
  try {
    if (!navigator.usb) {
      return JSON.stringify({ devices: [] });
    }
    const devices = await navigator.usb.getDevices();
    return JSON.stringify({
      devices: devices.map(d => ({
        vendorId: d.vendorId,
        productId: d.productId,
        productName: d.productName || null,
      })),
    });
  } catch (e) {
    return JSON.stringify({ devices: [], error: e.message || String(e) });
  }
}

/**
 * Find the first bulk OUT endpoint on a USB device.
 * @param {USBDevice} device
 * @returns {USBEndpoint|null}
 */
function _findUsbOutEndpoint(device) {
  try {
    if (!device.configuration) return null;
    for (const iface of device.configuration.interfaces) {
      for (const alt of iface.alternates) {
        for (const ep of alt.endpoints) {
          if (ep.direction === 'out' && (ep.type === 'bulk' || ep.type === 'interrupt')) {
            return ep;
          }
        }
      }
    }
  } catch (_) {}
  return null;
}

/**
 * Disconnect a previously connected WebUSB printer.
 * @param {string} type - Printer type key
 * @returns {string} JSON: { success }
 */
async function __printerUsbDisconnect(type) {
  try {
    const conn = window.__printerConnections[type];
    if (conn && conn.device) {
      try {
        await conn.device.close();
      } catch (_) {}
      delete window.__printerConnections[type];
    }
    return JSON.stringify({ success: true });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

/**
 * Check if a specific WebUSB printer is connected.
 * @param {string} type - Printer type key
 * @returns {string} JSON: { connected, vendorId?, productId?, productName? }
 */
function __printerUsbIsConnected(type) {
  const conn = window.__printerConnections[type];
  if (conn && conn.device) {
    return JSON.stringify({
      connected: true,
      vendorId: conn.device.vendorId,
      productId: conn.device.productId,
      productName: conn.device.productName || null,
    });
  }
  return JSON.stringify({ connected: false });
}

// ─── Universal Auto-Reconnect (tries both Serial and WebUSB) ────────────

/**
 * Try to auto-reconnect ALL printer types using BOTH methods (Serial first, then WebUSB).
 * This is called on startup and when any device connect event fires.
 */
async function _tryAutoReconnectAll() {
  const saved = window.__printerSavedDevices || {};
  for (const type of Object.keys(saved)) {
    // Already connected via either method?
    if (window.__printerConnections[type] &&
        (window.__printerConnections[type].port || window.__printerConnections[type].device)) {
      continue;
    }
    const { vendorId, productId } = saved[type];
    if (vendorId == null) continue;

    // Try Web Serial first
    await __printerAutoReconnect(type, vendorId, productId);

    // If still not connected, try WebUSB
    if (!window.__printerConnections[type] || !window.__printerConnections[type].port) {
      await __printerUsbAutoReconnect(type, vendorId, productId);
    }
  }
}
