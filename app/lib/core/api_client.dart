import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models.dart';

class ApiException implements Exception {
  final int? status;
  final String message;
  final bool isNetworkError;
  ApiException(this.status, this.message, {this.isNetworkError = false});
  @override
  String toString() => message;
}

/// عميل الـ API: يرفق الـ JWT وترويسة الشركة الفعّالة، ويحوّل الأخطاء لرسائل عربية.
class ApiClient {
  final Dio _dio;
  final String? Function() _token;
  final int? Function() _companyId;

  ApiClient({
    required String baseUrl,
    required String? Function() token,
    required int? Function() companyId,
  })  : _token = token,
        _companyId = companyId,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        )) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final t = _token();
      if (t != null) options.headers['Authorization'] = 'Bearer $t';
      final c = _companyId();
      if (c != null) options.headers['X-Company-Id'] = '$c';
      handler.next(options);
    }));
  }

  // ---------- المصادقة ----------
  Future<AuthResult> login(String username, String password) async {
    final data = await _post('/auth/login', {'username': username, 'password': password});
    return AuthResult.fromJson(data);
  }

  Future<void> changePassword(String current, String next) =>
      _post('/auth/change-password', {'currentPassword': current, 'newPassword': next});

  // ---------- القوائم المرجعية ----------
  Future<List<Company>> companies() async =>
      (await _get('/companies') as List).map((e) => Company.fromJson(e)).toList();

  Future<Company> createCompany(String name, String prefix) async =>
      Company.fromJson(await _post('/companies', {'name': name, 'prefix': prefix, 'isActive': true}));

  Future<List<EntityModel>> entities() async =>
      (await _get('/entities') as List).map((e) => EntityModel.fromJson(e)).toList();

  Future<EntityModel> createEntity(String name, String kind) async =>
      EntityModel.fromJson(await _post('/entities', {'name': name, 'kind': kind}));

  Future<List<TemplateModel>> templates() async =>
      (await _get('/templates') as List).map((e) => TemplateModel.fromJson(e)).toList();

  Future<TemplateModel> getTemplate(int id) async =>
      TemplateModel.fromJson(await _get('/templates/$id'));

  Future<TemplateModel> createTemplate(String name) async =>
      TemplateModel.fromJson(await _post('/templates', {
        'name': name, 'watermarkOpacity': 8,
        'marginTop': 24, 'marginRight': 40, 'marginBottom': 24, 'marginLeft': 40,
        'pageSize': 'A4', 'fontFamily': 'Amiri', 'isActive': true,
      }));

  Future<TemplateModel> updateTemplate(int id, Map<String, dynamic> body) async =>
      TemplateModel.fromJson(await _put('/templates/$id', body));

  /// رفع صورة قالب (kind: header/footer/watermark) كـ multipart.
  Future<void> uploadTemplateImage(int id, String kind, Uint8List bytes, String filename) async {
    final isPng = filename.toLowerCase().endsWith('.png');
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes,
          filename: filename,
          contentType: DioMediaType('image', isPng ? 'png' : 'jpeg')),
    });
    try {
      await _dio.post('/templates/$id/images/$kind', data: form);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// جلب صورة قالب (null إن لم توجد).
  Future<Uint8List?> getTemplateImage(int id, String kind) async {
    try {
      final res = await _dio.get<List<int>>('/templates/$id/images/$kind',
          options: Options(responseType: ResponseType.bytes));
      return res.data == null ? null : Uint8List.fromList(res.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _map(e);
    }
  }

  Future<List<ExchangeRateModel>> exchangeRates() async =>
      (await _get('/exchange-rates') as List).map((e) => ExchangeRateModel.fromJson(e)).toList();

  Future<void> createRate(String currency, num rate) =>
      _post('/exchange-rates', {'currency': currency, 'rate': rate, 'effectiveDate': DateTime.now().toIso8601String()});

  // ---------- الصادر ----------
  Future<List<OutgoingListItem>> outgoingList({String? status, String? search}) async {
    final q = <String, dynamic>{};
    if (status != null) q['status'] = status;
    if (search != null && search.isNotEmpty) q['search'] = search;
    return (await _get('/outgoing', query: q) as List).map((e) => OutgoingListItem.fromJson(e)).toList();
  }

  Future<OutgoingDetail> outgoingGet(int id) async =>
      OutgoingDetail.fromJson(await _get('/outgoing/$id'));

  Future<OutgoingDetail> createOutgoing(Map<String, dynamic> body) async =>
      OutgoingDetail.fromJson(await _post('/outgoing', body));

  Future<OutgoingDetail> updateOutgoing(int id, Map<String, dynamic> body) async =>
      OutgoingDetail.fromJson(await _put('/outgoing/$id', body));

  Future<OutgoingDetail> approve(int id) async =>
      OutgoingDetail.fromJson(await _post('/outgoing/$id/approve', null));

  Future<OutgoingDetail> editApproved(int id, Map<String, dynamic> body) async =>
      OutgoingDetail.fromJson(await _put('/outgoing/$id/edit-approved', body));

  Future<void> deleteOutgoing(int id) => _delete('/outgoing/$id');

  Future<List<VersionModel>> versions(int id) async =>
      (await _get('/outgoing/$id/versions') as List).map((e) => VersionModel.fromJson(e)).toList();

  // ---------- أنواع المستندات ----------
  Future<List<DocumentTypeModel>> documentTypes() async =>
      (await _get('/document-types') as List).map((e) => DocumentTypeModel.fromJson(e)).toList();

  // ---------- الأرشيف ----------
  Future<List<ArchiveListItem>> archiveList({String? search, DateTime? from, DateTime? to, int? documentTypeId, int? entityId}) async {
    final q = <String, dynamic>{};
    if (search != null && search.isNotEmpty) q['search'] = search;
    if (from != null) q['from'] = from.toIso8601String();
    if (to != null) q['to'] = to.toIso8601String();
    if (documentTypeId != null) q['documentTypeId'] = documentTypeId;
    if (entityId != null) q['entityId'] = entityId;
    return (await _get('/archive', query: q) as List).map((e) => ArchiveListItem.fromJson(e)).toList();
  }

  Future<ArchiveDetail> archiveGet(int id) async =>
      ArchiveDetail.fromJson(await _get('/archive/$id'));

  Future<ArchiveDetail> createArchive(Map<String, dynamic> body) async =>
      ArchiveDetail.fromJson(await _post('/archive', body));

  Future<ArchiveDetail> updateArchive(int id, Map<String, dynamic> body) async =>
      ArchiveDetail.fromJson(await _put('/archive/$id', body));

  Future<void> deleteArchive(int id) => _delete('/archive/$id');

  // ---------- المرفقات ----------
  Future<List<AttachmentModel>> archiveAttachments(int id) async =>
      (await _get('/archive/$id/attachments') as List).map((e) => AttachmentModel.fromJson(e)).toList();

  Future<AttachmentModel> uploadArchiveAttachment(int id, Uint8List bytes, String filename) async {
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)});
    try {
      final res = await _dio.post('/archive/$id/attachments', data: form);
      return AttachmentModel.fromJson(res.data);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Uint8List> downloadAttachment(int id) async {
    try {
      final res = await _dio.get<List<int>>('/attachments/$id', options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<void> deleteAttachment(int id) => _delete('/attachments/$id');

  // ---------- التقارير ----------
  Map<String, dynamic> _reportQuery(DateTime? from, DateTime? to, int? entityId, String source) {
    final q = <String, dynamic>{'source': source};
    if (from != null) q['from'] = from.toIso8601String();
    if (to != null) q['to'] = to.toIso8601String();
    if (entityId != null) q['entityId'] = entityId;
    return q;
  }

  Future<FinancialReport> financialReport({DateTime? from, DateTime? to, int? entityId, String source = 'All'}) async =>
      FinancialReport.fromJson(await _get('/reports/financial', query: _reportQuery(from, to, entityId, source)));

  Future<Uint8List> financialReportFile(String format, {DateTime? from, DateTime? to, int? entityId, String source = 'All'}) async {
    try {
      final res = await _dio.get<List<int>>('/reports/financial/$format',
          queryParameters: _reportQuery(from, to, entityId, source),
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ---------- النسخ الاحتياطي ----------
  Future<BackupScheduleModel> backupSchedule() async =>
      BackupScheduleModel.fromJson(await _get('/backup/schedule'));

  Future<BackupScheduleModel> updateBackupSchedule(String frequency, bool enabled, int hour) async =>
      BackupScheduleModel.fromJson(await _put('/backup/schedule', {'frequency': frequency, 'enabled': enabled, 'hour': hour}));

  Future<List<BackupRecordModel>> backupList() async =>
      (await _get('/backup') as List).map((e) => BackupRecordModel.fromJson(e)).toList();

  Future<BackupRecordModel> backupRun() async =>
      BackupRecordModel.fromJson(await _post('/backup/run', null));

  Future<Uint8List> backupDownload(int id) async {
    try {
      final res = await _dio.get<List<int>>('/backup/$id/download',
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ---------- المستخدمون والتفويض ----------
  Future<List<UserModel>> users() async =>
      (await _get('/users') as List).map((e) => UserModel.fromJson(e)).toList();

  Future<UserModel> createUser(Map<String, dynamic> body) async =>
      UserModel.fromJson(await _post('/users', body));

  Future<UserModel> updateUser(int id, Map<String, dynamic> body) async =>
      UserModel.fromJson(await _put('/users/$id', body));

  Future<void> resetPassword(int id, String newPassword) =>
      _post('/users/$id/reset-password', {'newPassword': newPassword});

  Future<List<DelegationModel>> delegations() async =>
      (await _get('/delegations') as List).map((e) => DelegationModel.fromJson(e)).toList();

  Future<void> createDelegation(int toUserId, DateTime start, DateTime? end) =>
      _post('/delegations', {
        'toUserId': toUserId,
        'startDate': start.toIso8601String(),
        'endDate': end?.toIso8601String(),
      });

  Future<void> revokeDelegation(int id) => _delete('/delegations/$id');

  Future<List<int>> outgoingPdf(int id) async {
    try {
      final res = await _dio.get<List<int>>('/outgoing/$id/pdf',
          options: Options(responseType: ResponseType.bytes));
      return res.data ?? <int>[];
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ---------- مساعدات ----------
  Future<dynamic> _get(String path, {Map<String, dynamic>? query}) async {
    try {
      return (await _dio.get(path, queryParameters: query)).data;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<dynamic> _post(String path, Object? body) async {
    try {
      return (await _dio.post(path, data: body)).data;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<dynamic> _put(String path, Object? body) async {
    try {
      return (await _dio.put(path, data: body)).data;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<void> _delete(String path) async {
    try {
      await _dio.delete(path);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  ApiException _map(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    String message = 'تعذّر الاتصال بالخادم.';
    bool isNet = false;
    if (data is Map && data['error'] != null) {
      message = data['error'].toString();
    } else if (status == 401) {
      message = 'الجلسة منتهية. سجّل الدخول مجدداً.';
    } else if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.unknown) {
      message = 'تعذّر الوصول إلى الخادم أو لا يوجد اتصال بالإنترنت.';
      isNet = true;
    }
    return ApiException(status, message, isNetworkError: isNet);
  }
}
