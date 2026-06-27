import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models.dart';
import '../database_helper.dart';
import '../main.dart';

class TicketCard extends StatefulWidget {
  final Ticket ticket;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Function(Ticket) onPreviewLabel;
  final Function(Ticket) onPreviewReceipt;
  final Function(Ticket) onPrintLabel;
  final Function(Ticket) onPrintReceipt;
  final Function(Ticket, String) onStatusChanged;

  const TicketCard({
    super.key,
    required this.ticket,
    required this.onEdit,
    required this.onDelete,
    required this.onPreviewLabel,
    required this.onPreviewReceipt,
    required this.onPrintLabel,
    required this.onPrintReceipt,
    required this.onStatusChanged,
  });

  @override
  State<TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<TicketCard> {
  Color getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'repaired':
        return Colors.green;
      case 'delivered':
        return Colors.grey;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String getStatusText(String status) {
    switch (status) {
      case 'pending':
        return '⏳ قيد الانتظار';
      case 'in_progress':
        return '🔧 تحت الصيانة';
      case 'repaired':
        return '✅ تم الإصلاح';
      case 'delivered':
        return '📦 تم التسليم';
      case 'rejected':
        return '❌ المرفوض';
      default:
        return status;
    }
  }

  void _showActionsBottomSheet(BuildContext context) {
    final primaryGold = const Color(0xFFD4AF37);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'إجراءات الإيصال #${widget.ticket.id}',
                    style: TextStyle(
                      color: primaryGold,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  Text(
                    'العميل: ${widget.ticket.customerName} | ${widget.ticket.deviceModel}',
                    style: TextStyle(
                      color: AppTheme.textMuted(context),
                      fontSize: 13,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const Divider(height: 24, thickness: 0.5),

                  ListTile(
                    leading: Icon(
                      Icons.swap_horizontal_circle_outlined,
                      color: primaryGold,
                    ),
                    title: const Text(
                      'تغيير حالة الإصلاح',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                    subtitle: Text(
                      'الحالة الحالية: ${getStatusText(widget.ticket.status)}',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showStatusChangeDialog(context);
                    },
                  ),

                  ListTile(
                    leading: const Icon(
                      Icons.edit_outlined,
                      color: Colors.blueAccent,
                    ),
                    title: const Text(
                      'تعديل بيانات الإيصال',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onEdit();
                    },
                  ),

                  ListTile(
                    leading: const Icon(
                      Icons.visibility_outlined,
                      color: Colors.tealAccent,
                    ),
                    title: const Text(
                      'معاينة الإيصال (PDF)',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onPreviewReceipt(widget.ticket);
                    },
                  ),

                  ListTile(
                    leading: const Icon(
                      Icons.print_outlined,
                      color: Colors.tealAccent,
                    ),
                    title: const Text(
                      'طباعة الإيصال (PDF)',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onPrintReceipt(widget.ticket);
                    },
                  ),

                  ListTile(
                    leading: const Icon(
                      Icons.qr_code_scanner_outlined,
                      color: Colors.amberAccent,
                    ),
                    title: const Text(
                      'معاينة ملصق الباركود',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onPreviewLabel(widget.ticket);
                    },
                  ),

                  ListTile(
                    leading: const Icon(
                      Icons.print_outlined,
                      color: Colors.amberAccent,
                    ),
                    title: const Text(
                      'طباعة ملصق الباركود',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onPrintLabel(widget.ticket);
                    },
                  ),

                  const Divider(height: 12, thickness: 0.5),

                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                    ),
                    title: const Text(
                      'حذف الإيصال',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.redAccent,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onDelete();
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showStatusChangeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            title: const Text(
              'تغيير حالة الإصلاح',
              style: TextStyle(
                color: Color(0xFFD4AF37),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusOption(context, 'pending'),
                  _buildStatusOption(context, 'in_progress'),
                  _buildStatusOption(context, 'repaired'),
                  _buildStatusOption(context, 'delivered'),
                  _buildStatusOption(context, 'rejected'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusOption(BuildContext context, String statusKey) {
    final statusColor = getStatusColor(statusKey);
    final statusText = getStatusText(statusKey);
    final isCurrent = widget.ticket.status == statusKey;

    return ListTile(
      leading: Icon(
        isCurrent ? Icons.check_circle : Icons.circle_outlined,
        color: statusColor,
      ),
      title: Text(
        statusText,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: AppTheme.text(context),
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        widget.onStatusChanged(widget.ticket, statusKey);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);
    final primaryGold = const Color(0xFFD4AF37);
    final statusColor = getStatusColor(widget.ticket.status);
    final statusText = getStatusText(widget.ticket.status);

    return Card(
      color: AppTheme.cardBg(context),
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: InkWell(
        onTap: () => _showActionsBottomSheet(context),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: primaryGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: primaryGold.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '#${widget.ticket.id}',
                      style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  if (widget.ticket.agent != null &&
                      widget.ticket.agent!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          widget.ticket.agent!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.ticket.customerName,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        fontFamily: 'Cairo',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${widget.ticket.cost.toStringAsFixed(2)} ج.م',
                    style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoChip(
                    context,
                    Icons.phone,
                    widget.ticket.customerPhone,
                  ),
                  _buildInfoChip(
                    context,
                    Icons.phone_android,
                    widget.ticket.deviceModel,
                  ),
                  _buildInfoChip(
                    context,
                    Icons.build_circle_outlined,
                    widget.ticket.problem,
                  ),
                  if (widget.ticket.technicianName != null &&
                      widget.ticket.technicianName!.isNotEmpty)
                    _buildInfoChip(
                      context,
                      Icons.person_outline,
                      widget.ticket.technicianName!,
                    ),
                  _buildInfoChip(
                    context,
                    Icons.access_time,
                    DateFormat(
                      'yyyy/MM/dd HH:mm',
                    ).format(widget.ticket.receivedDate),
                  ),
                ],
              ),
              if (widget.ticket.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'ملاحظات: ${widget.ticket.notes}',
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
              if (widget.ticket.deviceCondition.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'حالة الجهاز: ${widget.ticket.deviceCondition}',
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.border(context).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textDisabled(context)),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: AppTheme.textMuted(context),
              fontSize: 12,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }
}

class TicketDialog extends StatefulWidget {
  final Ticket? ticket;
  final Function(Map<String, dynamic>) onSave;
  final List<Map<String, String>> technicians;
  final List<Ticket> existingTickets;
  final List<SparePart> spareParts;

  const TicketDialog({
    super.key,
    this.ticket,
    required this.onSave,
    required this.technicians,
    required this.existingTickets,
    required this.spareParts,
  });

  @override
  State<TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<TicketDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _deviceController;
  late TextEditingController _problemController;
  late TextEditingController _costController;
  late TextEditingController _notesController;
  late TextEditingController _agentController;
  late TextEditingController _deviceConditionController;
  late TextEditingController _technicianNameController;
  late TextEditingController _technicianPhoneController;
  late TextEditingController _partsCostController;
  late TextEditingController _commissionRateController;
  late TextEditingController _expectedDeliveryController;
  late String _status;
  List<Map<String, String>> filteredTechnicians = [];
  List<Map<String, dynamic>> _selectedParts = [];

  List<String> allCustomerNames = [];
  List<String> allCustomerPhones = [];
  List<String> allDeviceModels = [];

  List<String> filteredCustomerNames = [];
  List<String> filteredCustomerPhones = [];
  List<String> filteredDeviceModels = [];

  List<Ticket> customerHistory = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.ticket?.customerName);
    _phoneController = TextEditingController(
      text: widget.ticket?.customerPhone,
    );
    _deviceController = TextEditingController(text: widget.ticket?.deviceModel);
    _problemController = TextEditingController(text: widget.ticket?.problem);
    _costController = TextEditingController(
      text: widget.ticket?.cost.toString() ?? '0',
    );
    _notesController = TextEditingController(text: widget.ticket?.notes);
    _agentController = TextEditingController(text: widget.ticket?.agent);
    _deviceConditionController = TextEditingController(
      text: widget.ticket?.deviceCondition,
    );
    _technicianNameController = TextEditingController(
      text: widget.ticket?.technicianName,
    );
    _technicianPhoneController = TextEditingController(
      text: widget.ticket?.technicianPhone,
    );
    _partsCostController = TextEditingController(
      text: widget.ticket?.partsCost.toString() ?? '0',
    );
    _commissionRateController = TextEditingController(
      text: widget.ticket?.commissionRate.toString() ?? '50.0',
    );
    _expectedDeliveryController = TextEditingController(
      text: widget.ticket?.expectedDelivery,
    );
    _status = widget.ticket?.status ?? 'pending';
    filteredTechnicians = [];

    if (widget.ticket?.partsUsed != null &&
        widget.ticket!.partsUsed!.isNotEmpty) {
      try {
        _selectedParts = List<Map<String, dynamic>>.from(
          jsonDecode(widget.ticket!.partsUsed!),
        );
      } catch (e) {
        debugPrint('Error decoding partsUsed: $e');
      }
    }

    final tickets = widget.existingTickets;
    allCustomerNames = tickets
        .map((t) => t.customerName.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    allCustomerPhones = tickets
        .map((t) => t.customerPhone.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    allDeviceModels = tickets
        .map((t) => t.deviceModel.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    if (widget.ticket != null) {
      _updateCustomerHistory(widget.ticket!.customerPhone);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _deviceController.dispose();
    _problemController.dispose();
    _costController.dispose();
    _notesController.dispose();
    _agentController.dispose();
    _deviceConditionController.dispose();
    _technicianNameController.dispose();
    _technicianPhoneController.dispose();
    _partsCostController.dispose();
    _commissionRateController.dispose();
    _expectedDeliveryController.dispose();
    super.dispose();
  }

  void _calculateTotalPartsCost() {
    double total = 0.0;
    for (var p in _selectedParts) {
      total += (p['price'] as num) * (p['quantity'] as num);
    }
    setState(() {
      _partsCostController.text = total.toStringAsFixed(2);
    });
  }

  void _showAddPartToTicketDialog() {
    SparePart? selectedInventoryPart;
    int qty = 1;
    final qtyController = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: AppTheme.cardBg(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: const Text(
                  'إضافة قطعة غيار للإيصال',
                  style: TextStyle(
                    color: Color(0xFFD4AF37),
                    fontSize: 18,
                    fontFamily: 'Cairo',
                  ),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<SparePart>(
                        isExpanded: true,
                        dropdownColor: AppTheme.cardBg(context),
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 15,
                          fontFamily: 'Cairo',
                        ),
                        decoration: const InputDecoration(
                          labelText: 'اختر قطعة الغيار من المستودع',
                        ),
                        items: widget.spareParts.map((p) {
                          return DropdownMenuItem<SparePart>(
                            value: p,
                            child: Text(
                              '${p.name} (المتاح: ${p.quantity} - السعر: ${p.price} ج.م)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedInventoryPart = val;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: qtyController,
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الكمية المطلوبة',
                        ),
                        onChanged: (val) {
                          qty = int.tryParse(val) ?? 1;
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'إلغاء',
                      style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontSize: 15,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: const Color(0xFF1A2A3A),
                    ),
                    onPressed: () {
                      if (selectedInventoryPart != null) {
                        final existingIndex = _selectedParts.indexWhere(
                          (p) => p['partId'] == selectedInventoryPart!.id,
                        );
                        setState(() {
                          if (existingIndex != -1) {
                            _selectedParts[existingIndex]['quantity'] += qty;
                          } else {
                            _selectedParts.add({
                              'partId': selectedInventoryPart!.id,
                              'name': selectedInventoryPart!.name,
                              'quantity': qty,
                              'price': selectedInventoryPart!.price,
                            });
                          }
                          _calculateTotalPartsCost();
                        });
                        Navigator.pop(context);
                      }
                    },
                    child: const Text(
                      'إضافة',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _filterCustomerNames(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredCustomerNames = [];
      } else {
        filteredCustomerNames = allCustomerNames
            .where((name) => name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _filterCustomerPhones(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredCustomerPhones = [];
      } else {
        filteredCustomerPhones = allCustomerPhones
            .where((phone) => phone.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _filterDeviceModels(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredDeviceModels = [];
      } else {
        filteredDeviceModels = allDeviceModels
            .where((model) => model.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _selectCustomerName(String name) {
    setState(() {
      _nameController.text = name;
      filteredCustomerNames = [];
      if (_phoneController.text.isEmpty) {
        final hasMatch = widget.existingTickets.any(
          (t) => t.customerName.trim() == name.trim(),
        );
        if (hasMatch) {
          final match = widget.existingTickets.firstWhere(
            (t) => t.customerName.trim() == name.trim(),
          );
          _phoneController.text = match.customerPhone;
          _updateCustomerHistory(match.customerPhone);
        }
      }
    });
  }

  void _selectCustomerPhone(String phone) {
    setState(() {
      _phoneController.text = phone;
      filteredCustomerPhones = [];
      if (_nameController.text.isEmpty) {
        final hasMatch = widget.existingTickets.any(
          (t) => t.customerPhone.trim() == phone.trim(),
        );
        if (hasMatch) {
          final match = widget.existingTickets.firstWhere(
            (t) => t.customerPhone.trim() == phone.trim(),
          );
          _nameController.text = match.customerName;
        }
      }
      _updateCustomerHistory(phone);
    });
  }

  void _selectDeviceModel(String model) {
    setState(() {
      _deviceController.text = model;
      filteredDeviceModels = [];
    });
  }

  void _updateCustomerHistory(String phone) {
    final cleanPhone = phone.trim();
    setState(() {
      if (cleanPhone.isEmpty) {
        customerHistory = [];
      } else {
        customerHistory = widget.existingTickets
            .where(
              (t) =>
                  t.customerPhone.trim() == cleanPhone &&
                  (widget.ticket == null || t.id != widget.ticket!.id),
            )
            .toList();
        customerHistory.sort(
          (a, b) => b.receivedDate.compareTo(a.receivedDate),
        );
      }
    });
  }

  Widget _buildHistoryStatusBadge(String status) {
    Color badgeColor;
    String text;
    switch (status) {
      case 'pending':
        badgeColor = Colors.orange;
        text = '⏳ الانتظار';
        break;
      case 'in_progress':
        badgeColor = Colors.blue;
        text = '🔧 صيانة';
        break;
      case 'repaired':
        badgeColor = Colors.green;
        text = '✅ تم';
        break;
      case 'delivered':
        badgeColor = Colors.purple;
        text = '📦 تسليم';
        break;
      case 'rejected':
        badgeColor = Colors.red;
        text = '❌ مرفوض';
        break;
      default:
        badgeColor = Colors.grey;
        text = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: badgeColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'Cairo',
        ),
      ),
    );
  }

  void _filterTechnicians(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredTechnicians = [];
      } else {
        filteredTechnicians = widget.technicians
            .where(
              (tech) =>
                  tech['name']!.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  void _selectTechnician(Map<String, String> tech) {
    setState(() {
      _technicianNameController.text = tech['name']!;
      _technicianPhoneController.text = tech['phone']!;
      filteredTechnicians = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 550),
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.ticket == null
                      ? '➕ إضافة إيصال جديد'
                      : '✏️ تعديل إيصال',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD4AF37),
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 16),

                // Customer Information Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[900]!.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'معلومات العميل',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD4AF37),
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم العميل *',
                        ),
                        validator: (v) => v?.isEmpty ?? true ? 'مطلوب' : null,
                        onChanged: _filterCustomerNames,
                      ),
                      if (filteredCustomerNames.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          constraints: const BoxConstraints(maxHeight: 120),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceTint(context),
                            border: Border.all(
                              color: const Color(
                                0xFFD4AF37,
                              ).withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredCustomerNames.length,
                            itemBuilder: (context, index) {
                              final name = filteredCustomerNames[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    color: AppTheme.text(context),
                                    fontSize: 16,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                onTap: () => _selectCustomerName(name),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف *',
                        ),
                        validator: (v) => v?.isEmpty ?? true ? 'مطلوب' : null,
                        onChanged: (val) {
                          _filterCustomerPhones(val);
                          _updateCustomerHistory(val);
                        },
                      ),
                      if (filteredCustomerPhones.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          constraints: const BoxConstraints(maxHeight: 120),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceTint(context),
                            border: Border.all(
                              color: const Color(
                                0xFFD4AF37,
                              ).withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredCustomerPhones.length,
                            itemBuilder: (context, index) {
                              final phone = filteredCustomerPhones[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  phone,
                                  style: TextStyle(
                                    color: AppTheme.text(context),
                                    fontSize: 16,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                onTap: () => _selectCustomerPhone(phone),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        controller: _deviceController,
                        decoration: const InputDecoration(
                          labelText: 'نوع الجهاز *',
                        ),
                        validator: (v) => v?.isEmpty ?? true ? 'مطلوب' : null,
                        onChanged: _filterDeviceModels,
                      ),
                      if (filteredDeviceModels.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          constraints: const BoxConstraints(maxHeight: 120),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceTint(context),
                            border: Border.all(
                              color: const Color(
                                0xFFD4AF37,
                              ).withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredDeviceModels.length,
                            itemBuilder: (context, index) {
                              final model = filteredDeviceModels[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  model,
                                  style: TextStyle(
                                    color: AppTheme.text(context),
                                    fontSize: 16,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                onTap: () => _selectDeviceModel(model),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        controller: _problemController,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'العطل *'),
                        validator: (v) => v?.isEmpty ?? true ? 'مطلوب' : null,
                      ),
                    ],
                  ),
                ),

                // Customer History Section
                if (customerHistory.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber[900]!.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.history,
                              color: Color(0xFFD4AF37),
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'سجل العميل (${customerHistory.length} أجهزة):',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD4AF37),
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: customerHistory.length,
                            separatorBuilder: (context, index) => const Divider(
                              color: Colors.white24,
                              height: 12,
                            ),
                            itemBuilder: (context, index) {
                              final hist = customerHistory[index];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '📱 ${hist.deviceModel}',
                                        style: TextStyle(
                                          color: AppTheme.text(context),
                                          fontSize: 13,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      _buildHistoryStatusBadge(hist.status),
                                    ],
                                  ),
                                  Text(
                                    '🔧 عطل: ${hist.problem}',
                                    style: TextStyle(
                                      color: AppTheme.textMuted(context),
                                      fontSize: 12,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Technician Information Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[900]!.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'معلومات الفني',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD4AF37),
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        controller: _technicianNameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم الفني',
                          hintText: 'ابحث عن فني...',
                        ),
                        onChanged: _filterTechnicians,
                      ),
                      if (filteredTechnicians.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceTint(context),
                            border: Border.all(
                              color: const Color(
                                0xFFD4AF37,
                              ).withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredTechnicians.length,
                            itemBuilder: (context, index) {
                              final tech = filteredTechnicians[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  tech['name']!,
                                  style: TextStyle(
                                    color: AppTheme.text(context),
                                    fontSize: 16,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                subtitle: Text(
                                  tech['phone']!,
                                  style: TextStyle(
                                    color: AppTheme.textMuted(context),
                                    fontSize: 13,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                onTap: () => _selectTechnician(tech),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        controller: _technicianPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الفني',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Spare Parts Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple[900]!.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'قطع الغيار المستخدمة',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD4AF37),
                              fontFamily: 'Cairo',
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              foregroundColor: const Color(0xFF1A2A3A),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text(
                              'إضافة قطعة',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            onPressed: _showAddPartToTicketDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_selectedParts.isEmpty)
                        Text(
                          'لا توجد قطع غيار مضافة حالياً.',
                          style: TextStyle(
                            color: AppTheme.textMuted(context),
                            fontSize: 13,
                            fontFamily: 'Cairo',
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _selectedParts.length,
                          itemBuilder: (context, index) {
                            final item = _selectedParts[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                item['name'],
                                style: TextStyle(
                                  color: AppTheme.text(context),
                                  fontSize: 15,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              subtitle: Text(
                                'الكمية: ${item['quantity']} | السعر: ${item['price']} ج.م',
                                style: TextStyle(
                                  color: AppTheme.textMuted(context),
                                  fontSize: 13,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _selectedParts.removeAt(index);
                                    _calculateTotalPartsCost();
                                  });
                                },
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Pricing, Status and Additional Info Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[900]!.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'معلومات إضافية والمالية',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD4AF37),
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _status,
                        dropdownColor: AppTheme.cardBg(context),
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        decoration: const InputDecoration(labelText: 'الحالة'),
                        items: const [
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('⏳ قيد الانتظار'),
                          ),
                          DropdownMenuItem(
                            value: 'in_progress',
                            child: Text('🔧 تحت الصيانة'),
                          ),
                          DropdownMenuItem(
                            value: 'repaired',
                            child: Text('✅ تم الإصلاح'),
                          ),
                          DropdownMenuItem(
                            value: 'delivered',
                            child: Text('📦 تم التسليم'),
                          ),
                          DropdownMenuItem(
                            value: 'rejected',
                            child: Text('❌ المرفوض'),
                          ),
                          DropdownMenuItem(
                            value: 'bought_from_customer',
                            child: Text('💜 تم الشراء من العميل'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _status = v!),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        controller: _costController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'التكلفة المبدئية/النهائية (ج.م) *',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              style: TextStyle(
                                color: AppTheme.text(context),
                                fontSize: 15,
                                fontFamily: 'Cairo',
                              ),
                              controller: _partsCostController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'تكلفة القطع (ج.م)',
                                helperText: 'تُحسب تلقائياً',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              style: TextStyle(
                                color: AppTheme.text(context),
                                fontSize: 15,
                                fontFamily: 'Cairo',
                              ),
                              controller: _commissionRateController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'عمولة الفني (%)',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        controller: _notesController,
                        decoration: const InputDecoration(labelText: 'ملاحظات'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        controller: _agentController,
                        decoration: const InputDecoration(
                          labelText: 'الوكيل',
                          hintText: 'اسم الوكيل (اختياري)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        controller: _deviceConditionController,
                        decoration: const InputDecoration(
                          labelText: 'حالة الجهاز',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 16,
                          fontFamily: 'Cairo',
                        ),
                        controller: _expectedDeliveryController,
                        decoration: const InputDecoration(
                          labelText: 'توقيت التسليم (مثال: ساعتين، يوم، إلخ)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceTint(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(
                              0xFFD4AF37,
                            ).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'رقم الشكوى:',
                              style: TextStyle(
                                color: AppTheme.textMuted(context),
                                fontSize: 14,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            Text(
                              DatabaseHelper.complaintNumber,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD4AF37),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Form Actions (Save / Cancel)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            widget.onSave({
                              'customerName': _nameController.text.trim(),
                              'customerPhone': _phoneController.text.trim(),
                              'deviceModel': _deviceController.text.trim(),
                              'problem': _problemController.text.trim(),
                              'status': _status,
                              'cost':
                                  double.tryParse(_costController.text) ?? 0.0,
                              'notes': _notesController.text.trim(),
                              'agent': _agentController.text.trim(),
                              'deviceCondition': _deviceConditionController.text
                                  .trim(),
                              'technicianName': _technicianNameController.text
                                  .trim(),
                              'technicianPhone': _technicianPhoneController.text
                                  .trim(),
                              'partsCost':
                                  double.tryParse(_partsCostController.text) ??
                                  0.0,
                              'partsUsed': _selectedParts.isNotEmpty
                                  ? jsonEncode(_selectedParts)
                                  : null,
                              'commissionRate':
                                  double.tryParse(
                                    _commissionRateController.text,
                                  ) ??
                                  50.0,
                              'expectedDelivery': _expectedDeliveryController.text.trim(),
                            });
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          foregroundColor: const Color(0xFF1A2A3A),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'حفظ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(fontSize: 18, fontFamily: 'Cairo'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
