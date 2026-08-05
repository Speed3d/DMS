// ignore_for_file: prefer_initializing_formals
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

/// عميل الـ API: يرفق الـ JWT وترويسة الشركة الفعّالة، يجدّد التوكن تلقائياً عند 401،
/// ويحوّل الأخطاء لرسائل عربية.
class ApiClient {
  final Dio _dio;
  final String? Function() _token;
  final int? Function() _companyId;
  final String? Function()? _refreshToken;
  final Future<void> Function(AuthResult)? _onRefreshed;
  final Future<void> Function()? _onRefreshFailed;

  /// طلب تجديد واحد مشترك يمنع تكرار التجديد عند تزامن عدة طلبات فاشلة (401).
  Future<String?>? _refreshing;

  ApiClient({
    required String baseUrl,
    required String? Function() token,
    required int? Function() companyId,
    String? Function()? refreshToken,
    Future<void> Function(AuthResult)? onRefreshed,
    Future<void> Function()? onRefreshFailed,
  })  : _token = token,
        _companyId = companyId,
        _refreshToken = refreshToken,
        _onRefreshed = onRefreshed,
        _onRefreshFailed = onRefreshFailed,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final t = _token();
        if (t != null) options.headers['Authorization'] = 'Bearer $t';
        final c = _companyId();
        if (c != null) options.headers['X-Company-Id'] = '$c';
        handler.next(options);
      },
      onError: (e, handler) async {
        final path = e.requestOptions.path;
        final isAuthCall = path.contains('/auth/login') || path.contains('/auth/refresh');
        final alreadyRetried = e.requestOptions.extra['__retried'] == true;

        // 401 على طلب مصادَق (غير login/refresh) ⇒ حاول تجديد التوكن مرة واحدة ثم أعد الطلب.
        if (e.response?.statusCode == 401 && !isAuthCall && !alreadyRetried && _refreshToken != null) {
          final newToken = await _refreshAccessToken();
          if (newToken != null) {
            try {
              final opts = e.requestOptions;
              opts.extra['__retried'] = true;
              opts.headers['Authorization'] = 'Bearer $newToken';
              final res = await _dio.fetch(opts);
              return handler.resolve(res);
            } on DioException catch (retryErr) {
              return handler.next(retryErr);
            }
          } else {
            // فشل التجديد ⇒ الجلسة منتهية فعلاً.
            final onFail = _onRefreshFailed;
            if (onFail != null) await onFail();
          }
        }
        handler.next(e);
      },
    ));
  }

  /// يجدّد التوكن عبر refresh token المخزّن (طلب واحد مشترك عند التزامن). يعيد الـ access الجديد أو null.
  Future<String?> _refreshAccessToken() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    final rt = _refreshToken?.call();
    if (rt == null || rt.isEmpty) return null;
    try {
      // Dio منفصل بلا interceptors لتفادي حلقة التجديد.
      final bare = Dio(BaseOptions(baseUrl: _dio.options.baseUrl));
      final res = await bare.post('/auth/refresh', data: {'refreshToken': rt});
      final auth = AuthResult.fromJson(res.data);
      final onOk = _onRefreshed;
      if (onOk != null) await onOk(auth);
      return auth.accessToken;
    } catch (_) {
      return null;
    }
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

  Future<Company> createCompany(String name, String prefix, {String? defaultSignatoryName, String? defaultSignatoryTitle}) async =>
      Company.fromJson(await _post('/companies', {'name': name, 'prefix': prefix, 'isActive': true, 'defaultSignatoryName': defaultSignatoryName, 'defaultSignatoryTitle': defaultSignatoryTitle}));

  Future<Company> updateCompany(int id, String name, String prefix, bool isActive, {String? defaultSignatoryName, String? defaultSignatoryTitle}) async =>
      Company.fromJson(await _put('/companies/$id', {'name': name, 'prefix': prefix, 'isActive': isActive, 'defaultSignatoryName': defaultSignatoryName, 'defaultSignatoryTitle': defaultSignatoryTitle}));

  Future<Company> getCompany(int id) async => Company.fromJson(await _get('/companies/$id'));
  
  Future<void> deleteCompany(int id) => _delete('/companies/$id');

  Future<void> resetDb() async => _post('/system/reset-db', {});

  Future<List<EntityModel>> entities() async =>
      (await _get('/entities') as List).map((e) => EntityModel.fromJson(e)).toList();

  /// حذف جهة — يرفضه الخادم بـ 409 إن كانت مستخدَمة في صادر/وارد/أرشيف.
  Future<void> deleteEntity(int id) => _delete('/entities/$id');

  Future<EntityModel> createEntity(String name, String kind) async =>
      EntityModel.fromJson(await _post('/entities', {'name': name, 'kind': kind}));

  // ---------- الأقسام ----------
  /// أقسام الشركة الفعّالة، أو أقسام شركة بعينها عبر [companyId] — يتطلب صلاحية
  /// المانح (سوبر أدمن/رئيس شركة)، ويلزم لملء نموذج المستخدم متعدد الشركات (ADR-017).
  Future<List<DepartmentModel>> departments({int? companyId}) async =>
      (await _get('/departments${companyId == null ? '' : '?companyId=$companyId'}') as List)
          .map((e) => DepartmentModel.fromJson(e))
          .toList();

  Future<DepartmentModel> createDepartment(String name) async =>
      DepartmentModel.fromJson(await _post('/departments', {'name': name}));

  Future<DepartmentModel> updateDepartment(int id, String name, bool isActive) async =>
      DepartmentModel.fromJson(await _put('/departments/$id', {'name': name, 'isActive': isActive}));

  /// حذف قسم — يرفضه الخادم بـ 409 إن كان محالاً إليه كتب واردة.
  Future<void> deleteDepartment(int id) => _delete('/departments/$id');

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

  Future<int> getTemplateUsage(int id) async {
    final res = await _get('/templates/$id/usage');
    return res['count'] ?? 0;
  }

  Future<void> deleteTemplate(int id) => _delete('/templates/$id');

  Future<void> uploadCompanyLogo(int id, Uint8List bytes, String filename) async {
    final isPng = filename.toLowerCase().endsWith('.png');
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes,
          filename: filename,
          contentType: DioMediaType('image', isPng ? 'png' : 'jpeg')),
    });
    try {
      await _dio.post('/companies/$id/logo', data: form);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

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

  /// مسح صورة قالب (تفريغ الحقل وحذف الملف).
  Future<void> deleteTemplateImage(int id, String kind) => _delete('/templates/$id/images/$kind');

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

  Future<Uint8List> previewOutgoing(Map<String, dynamic> body) async {
    try {
      final res = await _dio.post<List<int>>('/outgoing/preview', data: body, options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

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

  Future<void> createDocumentType(String name) => _post('/document-types', {'name': name});

  Future<void> updateDocumentType(int id, String name) => _put('/document-types/$id', {'name': name});

  /// يفشل بـ409 إن كان النوع مستخدَماً في وارد أو أرشيف (الخادم يذكر العدد).
  Future<void> deleteDocumentType(int id) => _delete('/document-types/$id');

  // ---------- الوارد ----------
  Future<List<IncomingListItem>> incomingList({
    String? search, String? status, int? entityId,
    DateTime? from, DateTime? to, int? documentTypeId,
    int? departmentId, int? receiveMethod,
  }) async {
    final q = <String, dynamic>{};
    if (search != null && search.isNotEmpty) q['search'] = search;
    if (status != null && status.isNotEmpty) q['status'] = status;
    if (entityId != null) q['entityId'] = entityId;
    if (from != null) q['from'] = from.toIso8601String();
    if (to != null) q['to'] = to.toIso8601String();
    if (documentTypeId != null) q['documentTypeId'] = documentTypeId;
    if (departmentId != null) q['departmentId'] = departmentId;
    if (receiveMethod != null) q['receiveMethod'] = receiveMethod;
    return (await _get('/incoming', query: q) as List).map((e) => IncomingListItem.fromJson(e)).toList();
  }

  Future<IncomingDetail> incomingGet(int id) async =>
      IncomingDetail.fromJson(await _get('/incoming/$id'));

  Future<IncomingDetail> createIncoming(Map<String, dynamic> body) async =>
      IncomingDetail.fromJson(await _post('/incoming', body));

  Future<IncomingDetail> updateIncoming(int id, Map<String, dynamic> body) async =>
      IncomingDetail.fromJson(await _put('/incoming/$id', body));

  /// تغيير الحالة — يُرجِع `null` إن نجحت العملية و**لم يعُد المستخدم يرى الكتاب** بعدها
  /// (مثال: أرشفة تُخرجه من نطاقه). الخادم يردّ حينها `204` بلا جسم.
  Future<IncomingDetail?> changeIncomingStatus(int id, String status, String? note) async =>
      _detailOrGone(await _post('/incoming/$id/status', {'status': status, 'note': note}));

  /// إحالة إلى **قسم واحد أو أكثر معاً**، لكل قسم ملاحظته، مع ملاحظة عامة اختيارية (ADR-018).
  ///
  /// الإحالة **تراكمية**: تُضيف الأقسام ولا تُزيح الموجود، وإعادة الإحالة لقسم موجود
  /// **تُحدّث ملاحظته** ولا تُكرّره.
  ///
  /// تُرجِع `null` في الحالة النادرة التي تُخرج فيها العمليةُ الكتابَ من رؤية المُحيل.
  /// (نادرة الآن لأن «مَن أحال يبقى يرى» — انظر IncomingService.Query.)
  Future<IncomingDetail?> forwardIncoming(
    int id,
    List<({int departmentId, String? note})> departments, {
    String? generalNote,
  }) async =>
      _detailOrGone(await _post('/incoming/$id/forward', {
        'departments': [
          for (final d in departments) {'departmentId': d.departmentId, 'note': d.note}
        ],
        'generalNote': generalNote,
      }));

  /// Hint: كان الخادم يُنهي هذه العمليات بقراءة الكتاب، فيردّ **404 بعد نجاح العملية وحفظها**
  /// إن أخرجته من رؤية المنفِّذ — فيرى المستخدم فشلاً لعملٍ تمّ. صار يردّ `204`، ونترجمها هنا
  /// إلى «تمّت ولم يعُد الكتاب لديك».
  IncomingDetail? _detailOrGone(dynamic body) =>
      body is Map<String, dynamic> ? IncomingDetail.fromJson(body) : null;

  Future<IncomingDetail> linkIncoming(int id, int outgoingId) async =>
      IncomingDetail.fromJson(await _post('/incoming/$id/link/$outgoingId', null));

  Future<IncomingDetail> unlinkIncoming(int id) async =>
      IncomingDetail.fromJson(await _deleteReturnData('/incoming/$id/link'));

  Future<void> deleteIncoming(int id) => _delete('/incoming/$id');

  Future<List<MovementLogItem>> incomingMovements(int id) async =>
      (await _get('/incoming/$id/movements') as List).map((e) => MovementLogItem.fromJson(e)).toList();

  Future<List<AttachmentModel>> incomingAttachments(int id) async =>
      (await _get('/incoming/$id/attachments') as List).map((e) => AttachmentModel.fromJson(e)).toList();

  Future<AttachmentModel> uploadIncomingAttachment(int id, Uint8List bytes, String filename) async {
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)});
    try {
      final res = await _dio.post('/incoming/$id/attachments', data: form);
      return AttachmentModel.fromJson(res.data);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// [inline] يطلب الملف **للعرض** لا للتنزيل.
  ///
  /// ⚠️ بدونه يردّ الخادم بترويسة «ملف للتنزيل» (`Content-Disposition: attachment`)، فيختطف
  /// مديرُ التحميل (IDM وأمثاله) الطلبَ **حتى حين نجلبه بـXHR للمعاينة** — فلا يصل ردّ إلى
  /// Dio ويظهر الخطأ كأنه انقطاع شبكة، بينما يبدأ الملف بالتنزيل. وهذا ما كان يُفشل زر
  /// العين لكل المستخدمين بلا استثناء.
  Future<Uint8List> downloadIncomingAttachment(int id, int attachmentId, {bool inline = false}) async {
    try {
      final res = await _dio.get<List<int>>(
        '/incoming/$id/attachments/$attachmentId/download',
        queryParameters: inline ? const {'inline': 'true'} : null,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<void> deleteIncomingAttachment(int id, int attachmentId) => _delete('/incoming/$id/attachments/$attachmentId');

  /// حذف نسخة احتياطية — يرفضه الخادم بـ 409 إن كانت النسخة الناجحة الوحيدة.
  Future<void> backupDelete(int id) => _delete('/backup/$id');

  // ---------- الأرشيف ----------

  /// **عدسة الأرشيف** — الوارد المؤرشف + الأضابير الورقية في قائمة واحدة.
  ///
  /// Hint: الدمج يتم في الخادم لا هنا — ليبقى العميل رفيعاً، ولأن قاعدة رؤية الوارد
  /// (ADR-015 + ADR-018) لا يجوز أن تُنسخ في العميل حيث لا تُفرض أصلاً.
  Future<List<ArchiveLensItem>> archiveLens({
    String? search, int? year, int? month, int? departmentId, String? source,
  }) async {
    final q = <String, dynamic>{};
    if (search != null && search.isNotEmpty) q['search'] = search;
    if (year != null) q['year'] = year;
    if (month != null) q['month'] = month;
    if (departmentId != null) q['departmentId'] = departmentId;
    if (source != null) q['source'] = source;
    return (await _get('/archive/lens', query: q) as List)
        .map((e) => ArchiveLensItem.fromJson(e))
        .toList();
  }

  /// **استيراد دفعة أرشيف ورقي** — ملفات متعدّدة ببيانات وصفية مشتركة.
  ///
  /// Hint: الفشل **جزئي** — الخادم يُعالج كل ملف على حدة ويردّ نتيجته، فملفٌ تالف
  /// لا يُبطل الدفعة. سقف الدفعة 50 ملفاً (يُرفع الأرشيف شهراً شهراً).
  Future<BulkImportResult> archiveBulkImport({
    required List<({String name, Uint8List bytes})> files,
    int? year, int? month, int? departmentId, int? fromEntityId, int? documentTypeId,
    String? keywords,
  }) async {
    final form = FormData();
    for (final f in files) {
      form.files.add(MapEntry('files', MultipartFile.fromBytes(f.bytes, filename: f.name)));
    }
    if (year != null) form.fields.add(MapEntry('year', '$year'));
    if (month != null) form.fields.add(MapEntry('month', '$month'));
    if (departmentId != null) form.fields.add(MapEntry('departmentId', '$departmentId'));
    if (fromEntityId != null) form.fields.add(MapEntry('fromEntityId', '$fromEntityId'));
    if (documentTypeId != null) form.fields.add(MapEntry('documentTypeId', '$documentTypeId'));
    if (keywords != null && keywords.isNotEmpty) form.fields.add(MapEntry('keywords', keywords));

    try {
      final res = await _dio.post('/archive/bulk', data: form);
      return BulkImportResult.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

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

  /// [inline] للعرض داخل البرنامج — انظر [downloadIncomingAttachment].
  Future<Uint8List> downloadAttachment(int id, {bool inline = false}) async {
    try {
      final res = await _dio.get<List<int>>(
        '/attachments/$id',
        queryParameters: inline ? const {'inline': 'true'} : null,
        options: Options(responseType: ResponseType.bytes),
      );
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

  /// استعادة نسخة احتياطية — عملية تدميرية.
  /// Hint: الخادم يأخذ نسخة أمان تلقائياً ثم يدخل وضع صيانة، فتُرفض بقية الطلبات بـ 503 لثوانٍ.
  ///       المهلة موسّعة لأن الاستعادة أبطأ من طلب عادي.
  Future<void> backupRestore(int id) async {
    try {
      await _dio.post('/backup/$id/restore',
          data: {'confirmation': kRestoreConfirmation},
          options: Options(receiveTimeout: const Duration(minutes: 10)));
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Uint8List> backupDownload(int id) async {
    try {
      final res = await _dio.get<List<int>>('/backup/$id/download',
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// تغطية النسخ — عمر آخر نسخة **كاملة** ومدى إلحاح أخذ واحدة (ADR-020).
  Future<BackupCoverage> backupCoverage() async =>
      BackupCoverage.fromJson(await _get('/backup/coverage') as Map<String, dynamic>);

  /// **مرآة كاملة** إلى مسار على السيرفر (قرص خارجي عادةً) — تُضيف ولا تُكرّر.
  ///
  /// Hint: المهلة موسّعة — المرة الأولى قد تنسخ عشرات الغيغابايتات.
  Future<MirrorResult> backupMirror(String targetPath) async {
    try {
      final res = await _dio.post('/backup/mirror',
          data: {'targetPath': targetPath},
          options: Options(receiveTimeout: const Duration(hours: 3)));
      return MirrorResult.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// استعادة من مرآة — تدميرية، بنفس كلمة تأكيد الاستعادة العادية.
  Future<String> backupRestoreFromMirror(String sourcePath) async {
    try {
      final res = await _dio.post('/backup/mirror/restore',
          data: {'sourcePath': sourcePath, 'confirmation': kRestoreConfirmation},
          options: Options(receiveTimeout: const Duration(hours: 3)));
      return (res.data as Map<String, dynamic>)['message']?.toString() ?? 'تمت الاستعادة.';
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

  /// تصدير الكتاب إلى Word (‎.docx‎) — يعمل للمسودّة والمعتمد معاً
  /// (المسودّة تُصدَّر بالرقم «(مسودّة)» بدل الرقم الرسمي).
  Future<Uint8List> outgoingWord(int id) async {
    try {
      final res = await _dio.get<List<int>>('/outgoing/$id/word',
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Uint8List> outgoingPdf(int id) async {
    try {
      final res = await _dio.get<List<int>>('/outgoing/$id/pdf',
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Uint8List> previewDraftPdf(int id) async {
    try {
      final res = await _dio.get<List<int>>('/outgoing/$id/preview-draft',
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ---------- الموظفون (ADR-023) ----------
  Future<List<EmployeeListItem>> employees({bool? activeOnly, String? search}) async {
    final q = <String, dynamic>{};
    if (activeOnly != null) q['activeOnly'] = activeOnly;
    if (search != null && search.isNotEmpty) q['search'] = search;
    return (await _get('/employees', query: q) as List)
        .map((e) => EmployeeListItem.fromJson(e)).toList();
  }

  Future<EmployeeDetail> employee(int id) async =>
      EmployeeDetail.fromJson(await _get('/employees/$id'));

  Future<EmployeeDetail> createEmployee(
          Map<String, dynamic> profile, Map<String, dynamic> employment) async =>
      EmployeeDetail.fromJson(
          await _post('/employees', {'profile': profile, 'employment': employment}));

  Future<EmployeeDetail> updateEmployee(int id, Map<String, dynamic> profile) async =>
      EmployeeDetail.fromJson(await _put('/employees/$id', profile));

  /// إسناد الموظف للشركة **الفعّالة** أو تحديث شروط عمله فيها.
  Future<void> saveEmployment(int id, Map<String, dynamic> employment) =>
      _put('/employees/$id/employment', employment);

  Future<void> terminateEmployee(int id, DateTime date, String reason, String? notes) =>
      _post('/employees/$id/terminate', {
        'terminationDate': date.toIso8601String(),
        'reason': reason,
        'notes': notes,
      });

  Future<void> deleteEmployee(int id) => _delete('/employees/$id');

  /// البحث عن موظف قائم قبل إنشاء ملفّ ثانٍ له — يعيد `null` إن لم يوجد.
  Future<ExistingEmployeeHint?> lookupEmployee(String nationalId) async {
    final data = jsonObjectOrNull(await _get('/employees/lookup', query: {'nationalId': nationalId}));
    return data == null ? null : ExistingEmployeeHint.fromJson(data);
  }

  Future<List<SalaryHistoryItem>> salaryHistory(int id, {int take = 12}) async =>
      (await _get('/employees/$id/salary-history', query: {'take': take}) as List)
          .map((e) => SalaryHistoryItem.fromJson(e)).toList();

  /// صورة الموظف بالتوكن — الويب لا يمرّر الترويسات مع `Image.network`، فتُجلب بايتاتٍ.
  Future<Uint8List> employeePhoto(int id) async {
    try {
      final res = await _dio.get<List<int>>('/employees/$id/photo',
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<void> uploadEmployeePhoto(int id, String fileName, List<int> bytes) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    try {
      await _dio.post('/employees/$id/photo', data: form);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// مستمسكات الموظف (هوية · عقد · شهادات) — `OwnerType.Employee`.
  Future<List<AttachmentModel>> employeeAttachments(int id) async =>
      (await _get('/employees/$id/attachments') as List)
          .map((e) => AttachmentModel.fromJson(e)).toList();

  Future<void> uploadEmployeeAttachment(int id, String fileName, List<int> bytes) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    try {
      await _dio.post('/employees/$id/attachments', data: form);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// بايتات مستمسكٍ للعرض داخل البرنامج — `inline` بالنوع الحقيقي (مبدأ ADR-019).
  Future<Uint8List> employeeAttachmentBytes(int id, int attachmentId) async {
    try {
      final res = await _dio.get<List<int>>(
        '/employees/$id/attachments/$attachmentId/download',
        queryParameters: {'inline': true},
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ---------- الرواتب ----------
  Future<List<PayrollYear>> payrollYears() async =>
      (await _get('/payroll/years') as List).map((e) => PayrollYear.fromJson(e)).toList();

  Future<List<PayrollMonth>> payrollMonths(int year) async =>
      (await _get('/payroll/years/$year/months') as List)
          .map((e) => PayrollMonth.fromJson(e)).toList();

  /// الكشف، أو `null` إن لم يُنشأ بعد.
  Future<PayrollPeriodModel?> payrollPeriod(int year, int month) async {
    final data = jsonObjectOrNull(await _get('/payroll/periods/$year/$month'));
    return data == null ? null : PayrollPeriodModel.fromJson(data);
  }

  /// توليد **تراكميّ**: يضيف الناقص ولا يمسّ سطراً قائماً → `{added, existing, skipped}`.
  /// توليد/إضافة موظفين — و[amendmentReason] إلزاميّ إن كان الشهر مُسدَّداً (ADR-026).
  Future<Map<String, dynamic>> generatePayroll(int year, int month,
          {String? amendmentReason}) async =>
      Map<String, dynamic>.from(await _post('/payroll/periods/$year/$month',
          {'amendmentReason': amendmentReason}));

  Future<PayrollPeriodModel> updatePayrollSettings(
    int year, int month, {
    required String rowVersion,
    double? exchangeRate,
    required String workingDaysMode,
    required int workingDays,
    String? notes,
    String? amendmentReason,
  }) async =>
      PayrollPeriodModel.fromJson(await _put('/payroll/periods/$year/$month', {
        'rowVersion': rowVersion,
        'exchangeRate': exchangeRate,
        'workingDaysMode': workingDaysMode,
        'workingDays': workingDays,
        'amendmentReason': amendmentReason,
        'notes': notes,
      }));

  /// حفظ السطور دفعةً. ⚠️ **بلا صافٍ** — الخادم يحسبه ويتجاهل ما يرسله العميل.
  Future<PayrollPeriodModel> savePayrollEntries(
          int year, int month, String rowVersion, List<Map<String, dynamic>> entries,
          {String? amendmentReason}) async =>
      PayrollPeriodModel.fromJson(await _put('/payroll/periods/$year/$month/entries', {
        'rowVersion': rowVersion,
        'entries': entries,
        'amendmentReason': amendmentReason,
      }));

  Future<void> payPayroll(
    int year, int month, {
    required String rowVersion,
    required DateTime paidAt,
    int? outgoingBookId,
    String? manualBookNumber,
    String? notes,
  }) =>
      _post('/payroll/periods/$year/$month/pay', {
        'rowVersion': rowVersion,
        'paidAt': paidAt.toIso8601String(),
        'outgoingBookId': outgoingBookId,
        'manualBookNumber': manualBookNumber,
        'notes': notes,
      });

  Future<void> deletePayrollPeriod(int year, int month) =>
      _delete('/payroll/periods/$year/$month');

  Future<void> deletePayrollYear(int year) => _delete('/payroll/years/$year');

  /// مَن صُرف راتبه من شركة أخرى هذا الشهر (ADR-024) — قراءة خالصة.
  Future<List<ExternalPaymentHint>> externalPayments(int year, int month) async =>
      (await _get('/payroll/periods/$year/$month/external-payments') as List)
          .map((e) => ExternalPaymentHint.fromJson(e)).toList();

  Future<void> confirmExternalPayment(int entryId) =>
      _post('/payroll/entries/$entryId/confirm-external', null);

  /// ملفّ من مخرجات الكشف: `excel` · `pdf` · `receipts`.
  Future<Uint8List> payrollFile(int year, int month, String kind, {int? employeeId}) async {
    try {
      final res = await _dio.get<List<int>>('/payroll/periods/$year/$month/$kind',
          queryParameters: employeeId != null ? {'employeeId': employeeId} : null,
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  // ---------- الإجازات وسجلّ التغييرات ونهاية الخدمة (الدفعة ٢) ----------
  Future<List<LeaveModel>> leaves(int employeeId) async =>
      (await _get('/employees/$employeeId/leaves') as List)
          .map((e) => LeaveModel.fromJson(e)).toList();

  Future<LeaveModel> addLeave(int employeeId, Map<String, dynamic> body) async =>
      LeaveModel.fromJson(await _post('/employees/$employeeId/leaves', body));

  Future<LeaveModel> reviewLeave(int leaveId, bool approve, String? notes) async =>
      LeaveModel.fromJson(await _patch('/employees/leaves/$leaveId', {
        'approve': approve,
        'notes': notes,
      }));

  Future<void> deleteLeave(int leaveId) => _delete('/employees/leaves/$leaveId');

  Future<List<EmployeeLogItem>> employeeLog(int employeeId) async =>
      (await _get('/employees/$employeeId/log') as List)
          .map((e) => EmployeeLogItem.fromJson(e)).toList();

  /// مكافآت نهاية الخدمة **المقترَحة** لمن انتهت خدمتهم في هذا الشهر.
  Future<List<EndOfServiceSuggestion>> endOfServiceSuggestions(int year, int month) async =>
      (await _get('/payroll/periods/$year/$month/end-of-service') as List)
          .map((e) => EndOfServiceSuggestion.fromJson(e)).toList();

  // ---------- إعدادات الموظفين ----------
  Future<HrSettingsModel> hrSettings() async =>
      HrSettingsModel.fromJson(await _get('/hr/settings'));

  Future<HrSettingsModel> updateHrSettings(
    String mode,
    int days, {
    bool endOfServiceEnabled = false,
    String endOfServiceRatio = 'MonthPerYear',
    int? endOfServiceCustomDays,
  }) async =>
      HrSettingsModel.fromJson(await _put('/hr/settings', {
        'defaultWorkingDaysMode': mode,
        'defaultWorkingDays': days,
        'endOfServiceEnabled': endOfServiceEnabled,
        'endOfServiceRatio': endOfServiceRatio,
        'endOfServiceCustomDays': endOfServiceCustomDays,
      }));

  Future<HrSummary> hrSummary() async => HrSummary.fromJson(await _get('/hr/summary'));

  /// الإجازات المعلّقة في الشركة الفعّالة **مع أصحابها** — تجيب «مَن ينتظر؟».
  // ── تعديل الشهر المُسدَّد وإيصالاته الموقَّعة (ADR-026) ──

  /// سجلّ تعديلات الشهر بعد التسديد — الأحدث أولاً.
  Future<List<PayrollAmendment>> payrollAmendments(int year, int month) async =>
      (await _get('/payroll/periods/$year/$month/amendments') as List)
          .map((e) => PayrollAmendment.fromJson(e)).toList();

  Future<List<SignedReceipt>> signedReceipts(int entryId) async =>
      (await _get('/payroll/entries/$entryId/receipts') as List)
          .map((e) => SignedReceipt.fromJson(e)).toList();

  Future<void> uploadSignedReceipt(int entryId, String fileName, List<int> bytes) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    try {
      await _dio.post('/payroll/entries/$entryId/receipts', data: form);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// «رفض»: تعديل الشهر لا يمسّ هذا الموظف، وإيصاله باقٍ صحيحاً.
  Future<void> acknowledgeReceipt(int entryId) =>
      _post('/payroll/entries/$entryId/receipts/acknowledge', null);

  Future<Uint8List> signedReceiptBytes(int entryId, int attachmentId) async {
    try {
      final res = await _dio.get<List<int>>(
        '/payroll/entries/$entryId/receipts/$attachmentId/download',
        queryParameters: {'inline': true},
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data ?? <int>[]);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<List<PendingLeave>> pendingLeaves() async =>
      (await _get('/hr/leaves/pending') as List)
          .map((e) => PendingLeave.fromJson(e)).toList();

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

  Future<dynamic> _patch(String path, Object? body) async {
    try {
      return (await _dio.patch(path, data: body)).data;
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

  Future<dynamic> _deleteReturnData(String path) async {
    try {
      return (await _dio.delete(path)).data;
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
    } else if (status == 403) {
      message = 'غير مصرح لك للقيام بهذه العملية.';
    } else if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.unknown) {
      message = 'تعذّر الوصول إلى الخادم أو لا يوجد اتصال بالإنترنت.';
      isNet = true;
    }
    return ApiException(status, message, isNetworkError: isNet);
  }
}
