/**
 * Web Serial Printer Bridge
 * Standalone functions for ESC/POS printing via Web Serial API.
 * Called from Dart via dart:js_interop.
 * Supports multiple simultaneous printer connections keyed by type.
 */

// Initialize connections store
window.__printerConnections = window.__printerConnections || {};

/**
 * Request a serial port from the user and open it.
 * @param {string} type - Printer type key ('label' or 'receipt')
 * @param {number|null} usbVendorId - Optional USB vendor ID filter
 * @param {number|null} usbProductId - Optional USB product ID filter
 * @returns {string} JSON: { success, vendorId?, productId?, error? }
 */
async function __printerConnect(type, usbVendorId, usbProductId) {
  try {
    const filters = [];
    if (usbVendorId != null) {
      // Only include usbProductId if it's a valid non-null value
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
    // Store for later use, keyed by type
    const writer = port.writable.getWriter();
    window.__printerConnections[type] = { port, writer };
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
    await conn.writer.write(data);
    return JSON.stringify({ success: true });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
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
