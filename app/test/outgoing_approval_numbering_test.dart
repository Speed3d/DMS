import 'package:flutter_test/flutter_test.dart';
import 'package:dms_app/models.dart';

void main() {
  group('نماذج الترقيم الرسمي للصادر (ADR-064)', () {
    test('NumberingInfoModel: يحمل معلومات العداد والتسلسل التالي بدقة', () {
      final json = {
        'currentCounter': 12,
        'nextSerial': 13,
        'nextFormattedNumber': 'DEN-2026-00013',
        'year': 2026,
        'companyPrefix': 'DEN',
      };

      final model = NumberingInfoModel.fromJson(json);
      expect(model.currentCounter, 12);
      expect(model.nextSerial, 13);
      expect(model.nextFormattedNumber, 'DEN-2026-00013');
      expect(model.year, 2026);
      expect(model.companyPrefix, 'DEN');
    });

    test('CheckSerialModel: يحول فحص التسلسل المتاح والشواغر والأرقام المستخدمة', () {
      final gapJson = {
        'serial': 2,
        'formattedNumber': 'BIG-2026-00002',
        'currentCounter': 10,
        'isAvailable': true,
        'existingBookSubject': null,
        'existingBookDate': null,
        'status': 'AvailableGap',
      };

      final gapModel = CheckSerialModel.fromJson(gapJson);
      expect(gapModel.serial, 2);
      expect(gapModel.formattedNumber, 'BIG-2026-00002');
      expect(gapModel.isAvailable, true);
      expect(gapModel.status, 'AvailableGap');
      expect(gapModel.existingBookSubject, isNull);

      final usedJson = {
        'serial': 5,
        'formattedNumber': 'BIG-2026-00005',
        'currentCounter': 10,
        'isAvailable': false,
        'existingBookSubject': 'طلب تجهيز مواد',
        'existingBookDate': '2026-10-15T09:00:00Z',
        'status': 'AlreadyUsed',
      };

      final usedModel = CheckSerialModel.fromJson(usedJson);
      expect(usedModel.isAvailable, false);
      expect(usedModel.status, 'AlreadyUsed');
      expect(usedModel.existingBookSubject, 'طلب تجهيز مواد');
      expect(usedModel.existingBookDate, isNotNull);
    });
  });
}
