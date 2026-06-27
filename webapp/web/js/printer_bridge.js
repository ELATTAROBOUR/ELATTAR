/**
 * WebUSB Printer Bridge
 * Standalone functions for ESC/POS printing via WebUSB API.
 * Called from Dart via dart:js_interop.
 * Supports multiple simultaneous printer connections keyed by type.
 */

// ─── Global State ──────────────────────────────────────────────────────────
window.__printerConnections = window.__printerConnections || {};
window.__printerSavedDevices = window.__printerSavedDevices || {};

// ─── Auto-Detection Initialization (WebUSB) ────────────────────────────────
(function _initPrinterBridge() {
  if (navigator.usb) {
    // When a USB device is connected AFTER page load, try to auto-reconnect
    navigator.usb.addEventListener('connect', async (event) => {
      const device = event.target;
      console.log('[PrinterBridge] USB device connected:', device.vendorId, device.productId, device.productName);
      await _tryAutoReconnectAll();
    });

    // When a device is disconnected, clean up any stale connections.
    navigator.usb.addEventListener('disconnect', (event) => {
      const device = event.target;
      console.log('[PrinterBridge] USB device disconnected:', device.productName);
      for (const type of Object.keys(window.__printerConnections)) {
        const conn = window.__printerConnections[type];
        if (conn && conn.device === device) {
          console.log('[PrinterBridge] Cleaned up connection for type:', type);
          delete window.__printerConnections[type];
        }
      }
    });
  }
})();

/**
 * Try to auto-reconnect all printer types that have saved device IDs.
 * Called on startup and when a USB device is connected.
 */
async function _tryAutoReconnectAll() {
  const saved = window.__printerSavedDevices || {};
  for (const type of Object.keys(saved)) {
    if (window.__printerConnections[type] && window.__printerConnections[type].device) {
      continue; // Already connected
    }
    const { vendorId, productId } = saved[type];
    if (vendorId != null) {
      await __printerUsbAutoReconnect(type, vendorId, productId);
    }
  }
}

// ─── Saved Device IDs Utilities (shared) ──────────────────────────────────

/**
 * Save USB vendor/product IDs for a printer type in JS bridge memory.
 * These are used by the onconnect handler to auto-reconnect when a device
 * is plugged in after page load.
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
 * @returns {string} JSON: { label?: {vendorId, productId}, receipt?: ... }
 */
function __printerGetSavedDeviceIds() {
  return JSON.stringify(window.__printerSavedDevices);
}

/**
 * Request a USB printer via WebUSB API.
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
      outEndpoint,
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
      return JSON.stringify({ success: false, error: 'الطابعة غير متصلة' });
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
            outEndpoint,
          };

          return JSON.stringify({ success: true });
        } catch (_) {
          // Device might be busy - try next
          continue;
        }
      }
    }

    return JSON.stringify({ success: false, error: 'لم يتم العثور على طابعة موافقة' });
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
 * Disconnect a previously connected USB printer.
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
 * Check if a specific USB printer is connected.
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

