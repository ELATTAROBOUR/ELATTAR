import 'package:flutter_test/flutter_test.dart';
import '../lib/database_helper.dart';

void main() {
  group('Memory-based 3-way Row Merge Tests', () {
    test('Non-conflicting updates should merge both changes', () {
      final columns = ['id', 'name', 'quantity', 'price', 'cost', 'supplier', 'category_id'];
      
      final baseRow = {
        'id': 11,
        'name': 'Screen Base',
        'quantity': 5,
        'price': 100.0,
        'cost': 50.0,
        'supplier': 'Supplier A',
        'category_id': 1,
      };

      // Local changed quantity from 5 to 8
      final localRow = {
        'id': 11,
        'name': 'Screen Base',
        'quantity': 8,
        'price': 100.0,
        'cost': 50.0,
        'supplier': 'Supplier A',
        'category_id': 1,
      };

      // Remote changed name from 'Screen Base' to 'Screen Remote Modified'
      final remoteRow = {
        'id': 11,
        'name': 'Screen Remote Modified',
        'quantity': 5,
        'price': 100.0,
        'cost': 50.0,
        'supplier': 'Supplier A',
        'category_id': 1,
      };

      final merged = DatabaseHelper.mergeRows(baseRow, localRow, remoteRow, columns, 'spare_parts');

      // Assertions
      expect(merged['id'], 11);
      expect(merged['name'], 'Screen Remote Modified'); // remote change preserved
      expect(merged['quantity'], 8); // local change preserved
      expect(merged['price'], 100.0);
      expect(merged['cost'], 50.0);
      expect(merged['supplier'], 'Supplier A');
      expect(merged['category_id'], 1);
    });

    test('Ticket status merge: more advanced status should win', () {
      final columns = ['id', 'customerName', 'status', 'cost'];

      final baseRow = {
        'id': 101,
        'customerName': 'Ahmed',
        'status': 'pending',
        'cost': 200.0,
      };

      // Local updated status to 'in_progress'
      final localRow = {
        'id': 101,
        'customerName': 'Ahmed',
        'status': 'in_progress',
        'cost': 200.0,
      };

      // Remote updated status to 'repaired' (more advanced than 'in_progress')
      final remoteRow = {
        'id': 101,
        'customerName': 'Ahmed',
        'status': 'repaired',
        'cost': 200.0,
      };

      final merged = DatabaseHelper.mergeRows(baseRow, localRow, remoteRow, columns, 'tickets');

      // Assertions: 'repaired' has higher weight (3) than 'in_progress' (2)
      expect(merged['status'], 'repaired');
    });

    test('Ticket status merge: local advanced status should win over remote', () {
      final columns = ['id', 'customerName', 'status', 'cost'];

      // Local updated status to 'delivered' (weight 4)
      final localRow = {
        'id': 101,
        'customerName': 'Ahmed',
        'status': 'delivered',
        'cost': 200.0,
      };

      // Remote updated status to 'repaired' (weight 3)
      final remoteRow = {
        'id': 101,
        'customerName': 'Ahmed',
        'status': 'repaired',
        'cost': 200.0,
      };

      final merged = DatabaseHelper.mergeRows(null, localRow, remoteRow, columns, 'tickets');

      // Assertions: 'delivered' (4) wins over 'repaired' (3)
      expect(merged['status'], 'delivered');
    });

    test('Conflict on general fields: local should win by default', () {
      final columns = ['id', 'name', 'price'];

      // Local changed price to 120.0
      final localRow = {
        'id': 11,
        'name': 'Screen Base',
        'price': 120.0,
      };

      // Remote changed price to 150.0
      final remoteRow = {
        'id': 11,
        'name': 'Screen Base',
        'price': 150.0,
      };

      final merged = DatabaseHelper.mergeRows(null, localRow, remoteRow, columns, 'spare_parts');

      // Assertions: Local wins by default on general conflicts
      expect(merged['price'], 120.0);
    });
  });
}
