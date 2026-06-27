// lib/models.dart
import 'package:intl/intl.dart';

class Ticket {
  int id;
  String customerName;
  String? agent;
  String customerPhone;
  String deviceModel;
  String problem;
  String status;
  DateTime receivedDate;
  DateTime? deliveryDate;
  double cost;
  String notes;
  String? technicianName;
  String? technicianPhone;
  String? complaintNumber;
  String deviceCondition;
  String? paymentMethod;
  String? paymentDetails;
  double partsCost;
  String? partsUsed;
  double commissionRate;
  int isClosed;
  String? expectedDelivery;
  int? updatedAt;

  Ticket({
    required this.id,
    required this.customerName,
    this.agent,
    required this.customerPhone,
    required this.deviceModel,
    required this.problem,
    required this.status,
    required this.receivedDate,
    this.deliveryDate,
    required this.cost,
    required this.notes,
    this.technicianName,
    this.technicianPhone,
    this.complaintNumber,
    this.deviceCondition = '',
    this.paymentMethod,
    this.paymentDetails,
    this.partsCost = 0.0,
    this.partsUsed,
    this.commissionRate = 50.0,
    this.isClosed = 0,
    this.expectedDelivery,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'deviceModel': deviceModel,
        'problem': problem,
        'status': status,
        'receivedDate': receivedDate.toIso8601String(),
        'deliveryDate': deliveryDate?.toIso8601String(),
        'cost': cost,
        'notes': notes,
        'agent': agent,
        'technicianName': technicianName,
        'technicianPhone': technicianPhone,
        'complaintNumber': complaintNumber,
        'deviceCondition': deviceCondition,
        'paymentMethod': paymentMethod,
        'paymentDetails': paymentDetails,
        'partsCost': partsCost,
        'partsUsed': partsUsed,
        'commissionRate': commissionRate,
        'isClosed': isClosed,
        'expectedDelivery': expectedDelivery,
        'updatedAt': updatedAt,
      };

  factory Ticket.fromJson(Map<String, dynamic> json) => Ticket(
        id: json['id'] as int,
        customerName: json['customerName'] as String,
        agent: json['agent'] as String?,
        customerPhone: json['customerPhone'] as String,
        deviceModel: json['deviceModel'] as String,
        problem: json['problem'] as String,
        status: json['status'] as String,
        receivedDate: DateTime.parse(json['receivedDate'] as String),
        deliveryDate: json['deliveryDate'] != null
            ? DateTime.parse(json['deliveryDate'] as String)
            : null,
        cost: (json['cost'] as num).toDouble(),
        notes: json['notes'] as String,
        technicianName: json['technicianName'] as String?,
        technicianPhone: json['technicianPhone'] as String?,
        complaintNumber: json['complaintNumber'] as String?,
        deviceCondition: json['deviceCondition'] as String? ?? '',
        paymentMethod: json['paymentMethod'] as String?,
        paymentDetails: json['paymentDetails'] as String?,
        partsCost: (json['partsCost'] as num?)?.toDouble() ?? 0.0,
        partsUsed: json['partsUsed'] as String?,
        commissionRate: (json['commissionRate'] as num?)?.toDouble() ?? 50.0,
        isClosed: json['isClosed'] as int? ?? 0,
        expectedDelivery: json['expectedDelivery'] as String?,
        updatedAt: json['updatedAt'] as int?,
      );
}

class SparePart {
  int id;
  String name;
  int quantity;
  double price;
  double cost;
  String? supplier;
  int? categoryId;
  String? categoryName;

  SparePart({
    required this.id,
    required this.name,
    required this.quantity,
    required this.price,
    this.cost = 0.0,
    this.supplier,
    this.categoryId,
    this.categoryName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'cost': cost,
        'quantity': quantity,
        'supplier': supplier,
        if (categoryId != null) 'category_id': categoryId,
      };

  factory SparePart.fromJson(Map<String, dynamic> json) => SparePart(
        id: json['id'] as int,
        name: json['name'] as String,
        quantity: json['quantity'] as int,
        price: (json['price'] as num).toDouble(),
        cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
        supplier: json['supplier'] as String?,
        categoryId: json['category_id'] as int?,
      );
}

class Accessory {
  int? id;
  String name;
  int quantity;
  double price; // Selling price
  double cost; // Cost price
  String? supplier;
  String warehouse;
  String? code;
  int? categoryId;
  String? categoryName;

  Accessory({
    this.id,
    required this.name,
    required this.quantity,
    required this.price,
    required this.cost,
    this.supplier,
    required this.warehouse,
    this.code,
    this.categoryId,
    this.categoryName,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'quantity': quantity,
        'price': price,
        'cost': cost,
        'supplier': supplier,
        'warehouse': warehouse,
        'code': code,
        if (categoryId != null) 'category_id': categoryId,
      };

  factory Accessory.fromJson(Map<String, dynamic> json) => Accessory(
        id: json['id'] as int?,
        name: json['name'] as String,
        quantity: json['quantity'] as int,
        price: (json['price'] as num).toDouble(),
        cost: (json['cost'] as num).toDouble(),
        supplier: json['supplier'] as String?,
        warehouse: json['warehouse'] as String? ?? 'المحل الرئيسي',
        code: json['code'] as String?,
        categoryId: json['category_id'] as int?,
      );
}

class Device {
  int? id;
  String model;
  String imei;
  String condition; // 'new' (جديد) or 'used' (مستعمل) or others
  int quantity;
  double price; // Selling price
  double cost; // Cost price
  String? supplier;
  String warehouse;
  String? code;
  int? categoryId;
  String? categoryName;

  Device({
    this.id,
    required this.model,
    required this.imei,
    required this.condition,
    required this.quantity,
    required this.price,
    required this.cost,
    this.supplier,
    required this.warehouse,
    this.code,
    this.categoryId,
    this.categoryName,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'model': model,
        'imei': imei,
        'condition': condition,
        'quantity': quantity,
        'price': price,
        'cost': cost,
        'supplier': supplier,
        'warehouse': warehouse,
        'code': code,
        if (categoryId != null) 'category_id': categoryId,
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as int?,
        model: json['model'] as String,
        imei: json['imei'] as String? ?? '',
        condition: json['condition'] as String? ?? 'new',
        quantity: json['quantity'] as int? ?? 1,
        price: (json['price'] as num).toDouble(),
        cost: (json['cost'] as num).toDouble(),
        supplier: json['supplier'] as String?,
        warehouse: json['warehouse'] as String? ?? 'المحل الرئيسي',
        code: json['code'] as String?,
        categoryId: json['category_id'] as int?,
      );
}

class DeferredPayment {
  int? id;
  String customerName;
  String customerPhone;
  double totalAmount;
  double paidAmount;
  double remainingAmount;
  String? dueDate;
  String? notes;
  String? transactionType; // 'device', 'accessory', 'repair', 'other'
  String createdDate;

  DeferredPayment({
    this.id,
    required this.customerName,
    required this.customerPhone,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    this.dueDate,
    this.notes,
    this.transactionType,
    required this.createdDate,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'totalAmount': totalAmount,
        'paidAmount': paidAmount,
        'remainingAmount': remainingAmount,
        'dueDate': dueDate,
        'notes': notes,
        'transactionType': transactionType,
        'createdDate': createdDate,
      };

  factory DeferredPayment.fromJson(Map<String, dynamic> json) =>
      DeferredPayment(
        id: json['id'] as int?,
        customerName: json['customerName'] as String,
        customerPhone: json['customerPhone'] as String,
        totalAmount: (json['totalAmount'] as num).toDouble(),
        paidAmount: (json['paidAmount'] as num).toDouble(),
        remainingAmount: (json['remainingAmount'] as num).toDouble(),
        dueDate: json['dueDate'] as String?,
        notes: json['notes'] as String?,
        transactionType: json['transactionType'] as String?,
        createdDate: json['createdDate'] as String,
      );
}

class DeferredPaymentHistory {
  int? id;
  int deferredId;
  double amountPaid;
  String paymentDate;
  String? notes;

  DeferredPaymentHistory({
    this.id,
    required this.deferredId,
    required this.amountPaid,
    required this.paymentDate,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'deferredId': deferredId,
        'amountPaid': amountPaid,
        'paymentDate': paymentDate,
        'notes': notes,
      };

  factory DeferredPaymentHistory.fromJson(Map<String, dynamic> json) =>
      DeferredPaymentHistory(
        id: json['id'] as int?,
        deferredId: json['deferredId'] as int,
        amountPaid: (json['amountPaid'] as num).toDouble(),
        paymentDate: json['paymentDate'] as String,
        notes: json['notes'] as String?,
      );
}

class Supplier {
  int? id;
  String name;
  String? phone;
  String? address;

  Supplier({
    this.id,
    required this.name,
    this.phone,
    this.address,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'address': address,
      };

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id'] as int?,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
      );
}

class SupplierDebt {
  int? id;
  int supplierId;
  String supplierName;
  double totalAmount;
  double paidAmount;
  double remainingAmount;
  String? dueDate;
  String? notes;
  String createdDate;

  SupplierDebt({
    this.id,
    required this.supplierId,
    required this.supplierName,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    this.dueDate,
    this.notes,
    required this.createdDate,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'totalAmount': totalAmount,
        'paidAmount': paidAmount,
        'remainingAmount': remainingAmount,
        'dueDate': dueDate,
        'notes': notes,
        'createdDate': createdDate,
      };

  factory SupplierDebt.fromJson(Map<String, dynamic> json) => SupplierDebt(
        id: json['id'] as int?,
        supplierId: json['supplierId'] as int,
        supplierName: json['supplierName'] as String? ?? '',
        totalAmount: (json['totalAmount'] as num).toDouble(),
        paidAmount: (json['paidAmount'] as num).toDouble(),
        remainingAmount: (json['remainingAmount'] as num).toDouble(),
        dueDate: json['dueDate'] as String?,
        notes: json['notes'] as String?,
        createdDate: json['createdDate'] as String,
      );
}

class SupplierPaymentHistory {
  int? id;
  int debtId;
  double amountPaid;
  String paymentDate;
  String? notes;

  SupplierPaymentHistory({
    this.id,
    required this.debtId,
    required this.amountPaid,
    required this.paymentDate,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'debtId': debtId,
        'amountPaid': amountPaid,
        'paymentDate': paymentDate,
        'notes': notes,
      };

  factory SupplierPaymentHistory.fromJson(Map<String, dynamic> json) =>
      SupplierPaymentHistory(
        id: json['id'] as int?,
        debtId: json['debtId'] as int,
        amountPaid: (json['amountPaid'] as num).toDouble(),
        paymentDate: json['paymentDate'] as String,
        notes: json['notes'] as String?,
      );
}

class GoodsReceipt {
  int? id;
  String receiptDate;
  String itemType; // 'spare_part', 'accessory', 'device'
  String itemName;
  int quantity;
  double cost;
  double price;
  String? supplier;
  String warehouse;

  GoodsReceipt({
    this.id,
    required this.receiptDate,
    required this.itemType,
    required this.itemName,
    required this.quantity,
    required this.cost,
    required this.price,
    this.supplier,
    required this.warehouse,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'receiptDate': receiptDate,
        'itemType': itemType,
        'itemName': itemName,
        'quantity': quantity,
        'cost': cost,
        'price': price,
        'supplier': supplier,
        'warehouse': warehouse,
      };

  factory GoodsReceipt.fromJson(Map<String, dynamic> json) => GoodsReceipt(
        id: json['id'] as int?,
        receiptDate: json['receiptDate'] as String,
        itemType: json['itemType'] as String,
        itemName: json['itemName'] as String,
        quantity: json['quantity'] as int,
        cost: (json['cost'] as num).toDouble(),
        price: (json['price'] as num).toDouble(),
        supplier: json['supplier'] as String?,
        warehouse: json['warehouse'] as String? ?? 'المحل الرئيسي',
      );
}

class InventoryTransfer {
  int? id;
  String transferDate;
  String itemType; // 'spare_part', 'accessory', 'device'
  String itemName;
  int quantity;
  String fromWarehouse;
  String toWarehouse;
  String? notes;

  InventoryTransfer({
    this.id,
    required this.transferDate,
    required this.itemType,
    required this.itemName,
    required this.quantity,
    required this.fromWarehouse,
    required this.toWarehouse,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'transferDate': transferDate,
        'itemType': itemType,
        'itemName': itemName,
        'quantity': quantity,
        'fromWarehouse': fromWarehouse,
        'toWarehouse': toWarehouse,
        'notes': notes,
      };

  factory InventoryTransfer.fromJson(Map<String, dynamic> json) =>
      InventoryTransfer(
        id: json['id'] as int?,
        transferDate: json['transferDate'] as String,
        itemType: json['itemType'] as String,
        itemName: json['itemName'] as String,
        quantity: json['quantity'] as int,
        fromWarehouse: json['fromWarehouse'] as String,
        toWarehouse: json['toWarehouse'] as String,
        notes: json['notes'] as String?,
      );
}

class InventoryAudit {
  int? id;
  String auditDate;
  String itemType; // 'spare_part', 'accessory', 'device'
  String itemName;
  int expectedQty;
  int actualQty;
  int difference;
  String? auditor;
  String? notes;

  InventoryAudit({
    this.id,
    required this.auditDate,
    required this.itemType,
    required this.itemName,
    required this.expectedQty,
    required this.actualQty,
    required this.difference,
    this.auditor,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'auditDate': auditDate,
        'itemType': itemType,
        'itemName': itemName,
        'expectedQty': expectedQty,
        'actualQty': actualQty,
        'difference': difference,
        'auditor': auditor,
        'notes': notes,
      };

  factory InventoryAudit.fromJson(Map<String, dynamic> json) => InventoryAudit(
        id: json['id'] as int?,
        auditDate: json['auditDate'] as String,
        itemType: json['itemType'] as String,
        itemName: json['itemName'] as String,
        expectedQty: json['expectedQty'] as int,
        actualQty: json['actualQty'] as int,
        difference: json['difference'] as int,
        auditor: json['auditor'] as String?,
        notes: json['notes'] as String?,
      );
}

class Warehouse {
  int? id;
  String name;

  Warehouse({
    this.id,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
      };

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
        id: json['id'] as int?,
        name: json['name'] as String,
      );
}

class Sale {
  int? id;
  DateTime saleDate;
  String? customerName;
  String? customerPhone;
  double totalAmount;
  double discount;
  double finalAmount;
  String paymentMethod;
  String itemsJson; // JSON string of sold items: [{type, id, name, qty, price}]

  Sale({
    this.id,
    required this.saleDate,
    this.customerName,
    this.customerPhone,
    required this.totalAmount,
    this.discount = 0.0,
    required this.finalAmount,
    required this.paymentMethod,
    required this.itemsJson,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'saleDate': saleDate.toIso8601String(),
        'customerName': customerName,
        'customerPhone': customerPhone,
        'totalAmount': totalAmount,
        'discount': discount,
        'finalAmount': finalAmount,
        'paymentMethod': paymentMethod,
        'itemsJson': itemsJson,
      };

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: json['id'] as int?,
        saleDate: DateTime.parse(json['saleDate'] as String),
        customerName: json['customerName'] as String?,
        customerPhone: json['customerPhone'] as String?,
        totalAmount: (json['totalAmount'] as num).toDouble(),
        discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
        finalAmount: (json['finalAmount'] as num).toDouble(),
        paymentMethod: json['paymentMethod'] as String? ?? 'cash',
        itemsJson: json['itemsJson'] as String? ?? '[]',
      );
}

class Category {
  int? id;
  String name;
  String type; // 'accessory', 'spare_part', 'device_brand', 'device_condition'

  Category({
    this.id,
    required this.name,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'type': type,
      };

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as int?,
        name: json['name'] as String,
        type: json['type'] as String,
      );
}

class ModificationLog {
  int? id;
  String actionDate;
  String
      actionType; // 'إضافة', 'تعديل', 'حذف', 'بيع', 'جرد', 'تحويل', 'سداد' etc.
  String
      itemType; // 'إكسسوار', 'قطعة غيار', 'جهاز', 'صيانة', 'بيعة', 'مورد', 'تصنيف' etc.
  String itemName;
  String? details;

  ModificationLog({
    this.id,
    required this.actionDate,
    required this.actionType,
    required this.itemType,
    required this.itemName,
    this.details,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'actionDate': actionDate,
        'actionType': actionType,
        'itemType': itemType,
        'itemName': itemName,
        'details': details,
      };

  factory ModificationLog.fromJson(Map<String, dynamic> json) =>
      ModificationLog(
        id: json['id'] as int?,
        actionDate: json['actionDate'] as String,
        actionType: json['actionType'] as String,
        itemType: json['itemType'] as String,
        itemName: json['itemName'] as String,
        details: json['details'] as String?,
      );
}

class AppUser {
  int? id;
  String email;
  String passwordHash;
  String role;
  String?
      name; // Display name (used for technician matching in ticket assignments)

  AppUser({
    this.id,
    required this.email,
    required this.passwordHash,
    required this.role,
    this.name,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'email': email,
        'passwordHash': passwordHash,
        'role': role,
        if (name != null) 'name': name,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int?,
        email: json['email'] as String,
        passwordHash: json['passwordHash'] as String,
        role: json['role'] as String? ?? 'staff',
        name: json['name'] as String?,
      );
}

class ReturnTransaction {
  int? id;
  DateTime returnDate;
  String? customerName;
  String? customerPhone;
  double totalAmount;
  String paymentMethod;
  String
      itemsJson; // JSON string of returned items: [{type, id, name, qty, price}]
  String? notes;

  ReturnTransaction({
    this.id,
    required this.returnDate,
    this.customerName,
    this.customerPhone,
    required this.totalAmount,
    required this.paymentMethod,
    required this.itemsJson,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'returnDate': returnDate.toIso8601String(),
        'customerName': customerName,
        'customerPhone': customerPhone,
        'totalAmount': totalAmount,
        'paymentMethod': paymentMethod,
        'itemsJson': itemsJson,
        'notes': notes,
      };

  factory ReturnTransaction.fromJson(Map<String, dynamic> json) =>
      ReturnTransaction(
        id: json['id'] as int?,
        returnDate: DateTime.parse(json['returnDate'] as String),
        customerName: json['customerName'] as String?,
        customerPhone: json['customerPhone'] as String?,
        totalAmount: (json['totalAmount'] as num).toDouble(),
        paymentMethod: json['paymentMethod'] as String? ?? 'cash',
        itemsJson: json['itemsJson'] as String? ?? '[]',
        notes: json['notes'] as String?,
      );
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Branch (Store Branch) Model
/// ─────────────────────────────────────────────────────────────────────────────
class StoreBranch {
  final int id;
  final String name;
  final String code;
  final int machineId;
  final String? phone;
  final String? address;
  final String? managerName;
  final String dbFileName;
  final String? repoUrl;
  final String? gitBranchName;
  final String? storeName;
  final String? storeEmail;
  final bool isActive;

  const StoreBranch({
    required this.id,
    required this.name,
    required this.code,
    required this.machineId,
    this.phone,
    this.address,
    this.managerName,
    required this.dbFileName,
    this.repoUrl,
    this.gitBranchName,
    this.storeName,
    this.storeEmail,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'machineId': machineId,
        'phone': phone ?? '',
        'address': address ?? '',
        'managerName': managerName ?? '',
        'dbFileName': dbFileName,
        'repoUrl': repoUrl ?? '',
        'gitBranchName': gitBranchName ?? '',
        'storeName': storeName ?? '',
        'storeEmail': storeEmail ?? '',
        'isActive': isActive,
      };

  factory StoreBranch.fromJson(Map<String, dynamic> json) => StoreBranch(
        id: json['id'] as int,
        name: json['name'] as String,
        code: json['code'] as String,
        machineId: json['machineId'] as int,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        managerName: json['managerName'] as String?,
        dbFileName: json['dbFileName'] as String? ?? 'ELATTAR_STORE.db',
        repoUrl: json['repoUrl'] as String?,
        gitBranchName: json['gitBranchName'] as String?,
        storeName: json['storeName'] as String?,
        storeEmail: json['storeEmail'] as String?,
        isActive: json['isActive'] as bool? ?? true,
      );

  StoreBranch copyWith({
    int? id,
    String? name,
    String? code,
    int? machineId,
    String? phone,
    String? address,
    String? managerName,
    String? dbFileName,
    String? repoUrl,
    String? gitBranchName,
    String? storeName,
    String? storeEmail,
    bool? isActive,
  }) =>
      StoreBranch(
        id: id ?? this.id,
        name: name ?? this.name,
        code: code ?? this.code,
        machineId: machineId ?? this.machineId,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        managerName: managerName ?? this.managerName,
        dbFileName: dbFileName ?? this.dbFileName,
        repoUrl: repoUrl ?? this.repoUrl,
        gitBranchName: gitBranchName ?? this.gitBranchName,
        storeName: storeName ?? this.storeName,
        storeEmail: storeEmail ?? this.storeEmail,
        isActive: isActive ?? this.isActive,
      );
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Branches Configuration (JSON-based storage)
/// ─────────────────────────────────────────────────────────────────────────────
class BranchesConfig {
  int currentBranchId;
  late List<StoreBranch> branches;

  BranchesConfig({
    this.currentBranchId = 1,
    required this.branches,
  });

  Map<String, dynamic> toJson() => {
        'currentBranchId': currentBranchId,
        'branches': branches.map((b) => b.toJson()).toList(),
      };

  factory BranchesConfig.fromJson(Map<String, dynamic> json) => BranchesConfig(
        currentBranchId: json['currentBranchId'] as int? ?? 1,
        branches: (json['branches'] as List<dynamic>?)
                ?.map((b) => StoreBranch.fromJson(b as Map<String, dynamic>))
                .toList() ??
            [],
      );

  StoreBranch? get currentBranch {
    try {
      return branches.firstWhere((b) => b.id == currentBranchId);
    } catch (_) {
      return branches.isNotEmpty ? branches.first : null;
    }
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Attendance Record (Check-in/Check-out) - نظام الحضور والانصراف
/// ─────────────────────────────────────────────────────────────────────────────
class Attendance {
  int? id;
  int? userId; // From users table
  String userName; // Denormalized for fast display
  String userRole; // 'staff', 'technician', 'admin'
  String date; // ISO date: YYYY-MM-DD
  String? checkIn; // ISO datetime
  String? checkOut; // ISO datetime
  String status; // 'present', 'late', 'absent', 'half_day'
  String? notes;

  Attendance({
    this.id,
    this.userId,
    required this.userName,
    required this.userRole,
    required this.date,
    this.checkIn,
    this.checkOut,
    this.status = 'present',
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (userId != null) 'userId': userId,
        'userName': userName,
        'userRole': userRole,
        'date': date,
        if (checkIn != null) 'checkIn': checkIn,
        if (checkOut != null) 'checkOut': checkOut,
        'status': status,
        if (notes != null) 'notes': notes,
      };

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
        id: json['id'] as int?,
        userId: json['userId'] as int?,
        userName: json['userName'] as String,
        userRole: json['userRole'] as String? ?? 'staff',
        date: json['date'] as String,
        checkIn: json['checkIn'] as String?,
        checkOut: json['checkOut'] as String?,
        status: json['status'] as String? ?? 'present',
        notes: json['notes'] as String?,
      );

  /// Get check-in time as DateTime
  DateTime? get checkInDateTime =>
      checkIn != null ? DateTime.tryParse(checkIn!) : null;

  /// Get check-out time as DateTime
  DateTime? get checkOutDateTime =>
      checkOut != null ? DateTime.tryParse(checkOut!) : null;

  /// Get the duration between check-in and check-out
  Duration? get duration {
    if (checkInDateTime != null && checkOutDateTime != null) {
      return checkOutDateTime!.difference(checkInDateTime!);
    }
    return null;
  }

  /// Formatted check-in time (HH:mm)
  String get formattedCheckIn => checkInDateTime != null
      ? DateFormat('HH:mm').format(checkInDateTime!)
      : '--:--';

  /// Formatted check-out time (HH:mm)
  String get formattedCheckOut => checkOutDateTime != null
      ? DateFormat('HH:mm').format(checkOutDateTime!)
      : '--:--';

  /// Duration as human-readable string
  String get formattedDuration {
    final d = duration;
    if (d == null) return '--';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) {
      return '$hours ساعة $minutes دقيقة';
    }
    return '$minutes دقيقة';
  }
}
