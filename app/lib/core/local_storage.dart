import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models.dart';

final localStorageProvider = Provider((ref) => LocalStorage());

/// التخزين المؤقت للبيانات المرجعية على الجهاز.
///
/// ⚠️ **مسوّدات الأوفلاين القديمة أُزيلت من هنا** (ADR-051) — حلّ محلّها `form_drafts.dart`:
/// مسوّداتٌ لها صاحبٌ وشركة وتُحفظ أثناء الكتابة.
class LocalStorage {
  Box get _cacheBox => Hive.box('dms_cache');

  // --- التخزين المؤقت للبيانات الأساسية (Cache) ---
  Future<void> cacheEntities(List<EntityModel> entities) async {
    final list = entities.map((e) => e.toJson()).toList();
    await _cacheBox.put('entities', list);
  }

  List<EntityModel> getCachedEntities() {
    final list = _cacheBox.get('entities') as List?;
    if (list == null) return [];
    return list.map((e) => EntityModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> cacheTemplates(List<TemplateModel> templates) async {
    final list = templates.map((t) => t.toJson()).toList();
    await _cacheBox.put('templates', list);
  }

  List<TemplateModel> getCachedTemplates() {
    final list = _cacheBox.get('templates') as List?;
    if (list == null) return [];
    return list.map((e) => TemplateModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
}
