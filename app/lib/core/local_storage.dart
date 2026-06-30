import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models.dart';

final localStorageProvider = Provider((ref) => LocalStorage());

class LocalStorage {
  Box get _draftsBox => Hive.box('dms_offline_drafts');
  Box get _cacheBox => Hive.box('dms_cache');

  // --- مسودات الأوفلاين (Offline Drafts) ---
  Future<void> saveDraft(Map<String, dynamic> payload) async {
    final draftId = DateTime.now().millisecondsSinceEpoch.toString();
    final draftData = {
      'id': draftId,
      'createdAt': DateTime.now().toIso8601String(),
      'subject': payload['subject'] ?? 'بدون عنوان',
      'date': payload['date'] ?? DateTime.now().toIso8601String(),
      'payload': payload, // حقل يحوي الـ JSON المطلوب إرساله لاحقاً
    };
    await _draftsBox.put(draftId, draftData);
  }

  List<Map<String, dynamic>> getDrafts() {
    return _draftsBox.values.map((e) {
      // تحويل الأنواع المتداخلة لـ Map<String, dynamic> لأن Hive يحفظها كـ Map<dynamic, dynamic>
      final map = Map<String, dynamic>.from(e as Map);
      map['payload'] = Map<String, dynamic>.from(map['payload'] as Map);
      return map;
    }).toList();
  }

  Future<void> deleteDraft(String id) async {
    await _draftsBox.delete(id);
  }

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
