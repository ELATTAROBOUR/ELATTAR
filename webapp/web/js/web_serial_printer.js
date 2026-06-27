/**
 * Web Serial Printer Helper
 * Handles USB Serial connection to thermal printers (ESC/POS).
 * Used by the Flutter web app via dart:js_interop.
 */

class WebSerialPrinter {
  constructor() {
    this.port = null;
    this.reader = null;
    this.writer = null;
  }

  /**
   * Request a serial port from the user and open it.
   * @param {object} options - Optional filters { usbVendorId, usbProductId }
   * @returns {object|null} Port info { vendorId, productId, serialNumber } or null if cancelled
   */
  async connect(options = {}) {
    try {
      // Request port from user
      const filters = [];
      if (options.usbVendorId && options.usbProductId) {
        filters.push({ usbVendorId: options.usbVendorId, usbProductId: options.usbProductId });
      }

      const port = await navigator.serial.requestPort({ filters: filters.length > 0 ? filters : undefined });

      // Get port info
      const info = port.getInfo();

      // Open the port
      await port.open({
        baudRate: 9600,  // Common for thermal printers
        dataBits: 8,
        stopBits: 1,
        parity: 'none',
        flowControl: 'none',
      });

      this.port = port;
      this.writer = port.writable.getWriter();

      return {
        connected: true,
        vendorId: info.usbVendorId,
        productId: info.usbProductId,
        serialNumber: null, // Web Serial API doesn't expose serial number directly
      };
    } catch (e) {
      if (e.name === 'NotFoundError') {
        // User cancelled the picker
        return null;
      }
      console.error('WebSerialPrinter connect error:', e);
      throw e;
    }
  }

  /**
   * Send raw bytes to the printer.
   * @param {Uint8Array} data - The raw bytes to send
   * @returns {boolean} true if successful
   */
  async print(data) {
    if (!this.port || !this.writer) {
      throw new Error('Printer not connected. Call connect() first.');
    }

    try {
      await this.writer.write(data);
      return true;
    } catch (e) {
      console.error('WebSerialPrinter print error:', e);
      throw e;
    }
  }

  /**
   * Disconnect and close the serial port.
   */
  async disconnect() {
    try {
      if (this.writer) {
        try {
          await this.writer.close();
        } catch (e) {
          // Ignore close errors
        }
        this.writer = null;
      }
      if (this.port) {
        try {
          await this.port.close();
        } catch (e) {
          // Ignore close errors
        }
        this.port = null;
      }
    } catch (e) {
      console.error('WebSerialPrinter disconnect error:', e);
    }
  }

  /**
   * Check if a port is currently connected.
   */
  isConnected() {
    return this.port !== null && this.writer !== null;
  }

  /**
   * Get all previously granted serial ports.
   * @returns {Array} Array of port info objects
   */
  async getPorts() {
    try {
      const ports = await navigator.serial.getPorts();
      return ports.map(p => {
        const info = p.getInfo();
        return {
          vendorId: info.usbVendorId,
          productId: info.usbProductId,
        };
      });
    } catch (e) {
      console.error('WebSerialPrinter getPorts error:', e);
      return [];
    }
  }
}

// Global instance
window.__webSerialPrinter = new WebSerialPrinter();
