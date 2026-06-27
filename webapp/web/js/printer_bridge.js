/**
 * Printer Bridge
 * ESC/POS printing via Web Serial API (primary) + WebUSB API (fallback).
 * Called from Dart via dart:js_interop.
 * Supports multiple simultaneous printer connections keyed by type.
 */

// ─── Global State ──────────────────────────────────────────────────────────
window.__printerConnections = window.__printerConnections || {};
window.__printerSavedDevices = window.__printerSavedDevices || {};

// ─── Auto-Detection Initialization ─────────────────────────────────────────
(function _initPrinterBridge() {
  // Web Serial: auto-reconnect when a serial device is connected
  if (navigator.serial) {
    navigator.serial.addEventListener('connect', async (event) => {
      const port = event.target;
      const info = port.getInfo();
      console.log('[PrinterBridge] Serial device connected:', info.usbVendorId, info.usbProductId);
      await _tryAutoReconnectAll();
    });
    navigator.serial.addEventListener('disconnect', (event) => {
      const port = event.target;
      for (const type of Object.keys(window.__printerConnections)) {
        const conn = window.__printerConnections[type];
        if (conn && conn.port === port) {
          delete window.__printerConnections[type];
        }
      }
    });
  }

  // WebUSB: auto-reconnect when a USB device is connected
  if (navigator.usb) {
    navigator.usb.addEventListener('connect', async (event) => {
      const device = event.target;
      console.log('[PrinterBridge] USB device connected:', device.vendorId, device.productId, device.productName);
      await _tryAutoReconnectAll();
    });
    navigator.usb.addEventListener('disconnect', (event) => {
      const device = event.target;
      for (const type of Object.keys(window.__printerConnections)) {
        const conn = window.__printerConnections[type];
        if (conn && conn.device === device) {
          delete window.__printerConnections[type];
        }
      }
    });
  }
})();

// ─── Auto-Reconnect All (tries Serial first, then WebUSB) ─────────────────

async function _tryAutoReconnectAll() {
  const saved = window.__printerSavedDevices || {};
  for (const type of Object.keys(saved)) {
    if (window.__printerConnections[type] &&
        (window.__printerConnections[type].port || window.__printerConnections[type].device)) {
      continue;
    }
    const { vendorId, productId } = saved[type];
    if (vendorId == null) continue;

    // Try Serial first (most common for thermal printers)
    await __printerAutoReconnect(type, vendorId, productId);

    // If still not connected, try WebUSB
    if (!window.__printerConnections[type] || !window.__printerConnections[type].port) {
      await __printerUsbAutoReconnect(type, vendorId, productId);
    }
  }
}

// ─── Saved Device IDs Utilities ────────────────────────────────────────────

function __printerSetSavedDeviceIds(type, usbVendorId, usbProductId) {
  if (usbVendorId == null) {
    delete window.__printerSavedDevices[type];
  } else {
    window.__printerSavedDevices[type] = { vendorId: usbVendorId, productId: usbProductId };
  }
}

function __printerGetSavedDeviceIds() {
  return JSON.stringify(window.__printerSavedDevices);
}

// ═════════════════════════════════════════════════════════════════════════════
// Web Serial API (Primary)
// ═════════════════════════════════════════════════════════════════════════════

async function __printerConnect(type, usbVendorId, usbProductId) {
  try {
    const filters = [];
    if (usbVendorId != null) {
      const filter = { usbVendorId };
      if (usbProductId != null) filter.usbProductId = usbProductId;
      filters.push(filter);
    }
    const port = await navigator.serial.requestPort({
      filters: filters.length > 0 ? filters : undefined,
    });
    const info = port.getInfo();
    await port.open({ baudRate: 9600, dataBits: 8, stopBits: 1, parity: 'none', flowControl: 'none' });
    const writer = port.writable.getWriter();
    window.__printerConnections[type] = { port, writer };
    __printerSetSavedDeviceIds(type, info.usbVendorId, info.usbProductId);
    return JSON.stringify({ success: true, vendorId: info.usbVendorId, productId: info.usbProductId });
  } catch (e) {
    if (e.name === 'NotFoundError') return JSON.stringify({ success: false, cancelled: true });
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

async function __printerPrint(type, data) {
  try {
    const conn = window.__printerConnections[type];
    if (!conn || !conn.writer) return JSON.stringify({ success: false, error: 'Printer not connected' });
    const uint8Data = (data instanceof Uint8Array) ? data : new Uint8Array(data);
    await conn.writer.write(uint8Data);
    return JSON.stringify({ success: true });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

async function __printerAutoReconnect(type, usbVendorId, usbProductId) {
  try {
    if (window.__printerConnections[type] && window.__printerConnections[type].port) {
      return JSON.stringify({ success: true });
    }
    const ports = await navigator.serial.getPorts();
    if (!ports || ports.length === 0) return JSON.stringify({ success: false, error: 'No previously authorized ports' });
    for (const port of ports) {
      const info = port.getInfo();
      if (usbVendorId != null) {
        if (info.usbVendorId !== usbVendorId) continue;
        if (usbProductId != null && info.usbProductId !== usbProductId) continue;
      }
      try {
        await port.open({ baudRate: 9600, dataBits: 8, stopBits: 1, parity: 'none', flowControl: 'none' });
        const writer = port.writable.getWriter();
        window.__printerConnections[type] = { port, writer };
        return JSON.stringify({ success: true, vendorId: info.usbVendorId, productId: info.usbProductId });
      } catch (_) { continue; }
    }
    return JSON.stringify({ success: false, error: 'No matching port found' });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

async function __printerDisconnect(type) {
  try {
    const conn = window.__printerConnections[type];
    if (conn) {
      if (conn.writer) { try { await conn.writer.close(); } catch (_) {} }
      if (conn.port) { try { await conn.port.close(); } catch (_) {} }
      delete window.__printerConnections[type];
    }
    return JSON.stringify({ success: true });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

function __printerIsConnected(type) {
  const conn = window.__printerConnections[type];
  if (conn && conn.port) {
    const info = conn.port.getInfo();
    return JSON.stringify({ connected: true, vendorId: info.usbVendorId, productId: info.usbProductId });
  }
  return JSON.stringify({ connected: false });
}

async function __printerScanAllPorts() {
  try {
    const ports = await navigator.serial.getPorts();
    if (!ports || ports.length === 0) return JSON.stringify({ ports: [] });
    const results = [];
    for (const port of ports) {
      try {
        const info = port.getInfo();
        results.push({ vendorId: info.usbVendorId, productId: info.usbProductId });
      } catch (_) {}
    }
    return JSON.stringify({ ports: results });
  } catch (e) {
    return JSON.stringify({ ports: [], error: e.message || String(e) });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// WebUSB API (Fallback)
// ═════════════════════════════════════════════════════════════════════════════

async function __printerUsbConnect(type) {
  try {
    if (!navigator.usb) return JSON.stringify({ success: false, error: 'WebUSB API غير متاح' });
    const device = await navigator.usb.requestDevice({
      filters: [{ classCode: 7 }, { classCode: 255 }],
    });
    if (!device) return JSON.stringify({ success: false, cancelled: true });
    await device.open();
    if (device.configuration === null) await device.selectConfiguration(1);
    await device.claimInterface(0);
    const outEndpoint = _findUsbOutEndpoint(device);
    window.__printerConnections[type] = { device, outEndpoint };
    __printerSetSavedDeviceIds(type, device.vendorId, device.productId);
    return JSON.stringify({ success: true, vendorId: device.vendorId, productId: device.productId, productName: device.productName || null });
  } catch (e) {
    if (e.name === 'NotFoundError') return JSON.stringify({ success: false, cancelled: true });
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

async function __printerUsbPrint(type, data) {
  try {
    const conn = window.__printerConnections[type];
    if (!conn || !conn.device) return JSON.stringify({ success: false, error: 'الطابعة غير متصلة' });
    const uint8Data = (data instanceof Uint8Array) ? data : new Uint8Array(data);
    if (conn.outEndpoint) {
      await conn.device.transferOut(conn.outEndpoint.endpointNumber, uint8Data);
    } else {
      await conn.device.transferOut(2, uint8Data);
    }
    return JSON.stringify({ success: true });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

async function __printerUsbAutoReconnect(type, usbVendorId, usbProductId) {
  try {
    if (!navigator.usb) return JSON.stringify({ success: false, error: 'WebUSB not available' });
    if (window.__printerConnections[type] && window.__printerConnections[type].device) {
      return JSON.stringify({ success: true });
    }
    const devices = await navigator.usb.getDevices();
    for (const device of devices) {
      if (device.vendorId === usbVendorId && (usbProductId == null || device.productId === usbProductId)) {
        try {
          await device.open();
          if (device.configuration === null) await device.selectConfiguration(1);
          await device.claimInterface(0);
          const outEndpoint = _findUsbOutEndpoint(device);
          window.__printerConnections[type] = { device, outEndpoint };
          return JSON.stringify({ success: true });
        } catch (_) { continue; }
      }
    }
    return JSON.stringify({ success: false, error: 'لم يتم العثور على طابعة موافقة' });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

function __printerUsbIsAvailable() {
  return JSON.stringify({ available: navigator.usb != null });
}

async function __printerUsbGetAuthorized() {
  try {
    if (!navigator.usb) return JSON.stringify({ devices: [] });
    const devices = await navigator.usb.getDevices();
    return JSON.stringify({ devices: devices.map(d => ({ vendorId: d.vendorId, productId: d.productId, productName: d.productName || null })) });
  } catch (e) {
    return JSON.stringify({ devices: [], error: e.message || String(e) });
  }
}

function _findUsbOutEndpoint(device) {
  try {
    if (!device.configuration) return null;
    for (const iface of device.configuration.interfaces) {
      for (const alt of iface.alternates) {
        for (const ep of alt.endpoints) {
          if (ep.direction === 'out' && (ep.type === 'bulk' || ep.type === 'interrupt')) return ep;
        }
      }
    }
  } catch (_) {}
  return null;
}

async function __printerUsbDisconnect(type) {
  try {
    const conn = window.__printerConnections[type];
    if (conn && conn.device) {
      try { await conn.device.close(); } catch (_) {}
      delete window.__printerConnections[type];
    }
    return JSON.stringify({ success: true });
  } catch (e) {
    return JSON.stringify({ success: false, error: e.message || String(e) });
  }
}

function __printerUsbIsConnected(type) {
  const conn = window.__printerConnections[type];
  if (conn && conn.device) {
    return JSON.stringify({ connected: true, vendorId: conn.device.vendorId, productId: conn.device.productId, productName: conn.device.productName || null });
  }
  return JSON.stringify({ connected: false });
}
