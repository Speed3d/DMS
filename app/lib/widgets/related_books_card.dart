import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/case_file_providers.dart';
import '../core/theme.dart';
import '../models.dart';

/// بطاقة **«الكتب المرتبطة»** — تُعرض في شاشتَي تفاصيل الوارد والصادر (ADR-045).
///
/// ✅ **وتظهر في الأرشيف بلا عملٍ إضافي**: عدسة الأرشيف تفتح الوارد المؤرشف بشاشة الوارد
/// نفسها، فالمراسلات القديمة تنال خيطها مجاناً.
///
/// 🔐 **والمحجوب يُعلَن بالعدد بلا أيّ تفصيل** (قرار المالك): من لا يعرف أن الخيط ناقص
/// **يبني قراراً على نصف صورة**، ورقمُ الكتاب المحجوب وعنوانه لا يصلان العميل أصلاً.
class RelatedBooksCard extends ConsumerWidget {
  const RelatedBooksCard({
    super.key,
    required this.kind,
    required this.bookId,
    required this.canManage,
    required this.onRelate,
    required this.onOpen,
    required this.onOpenCase,
  });

  final CaseMemberKind kind;
  final int bookId;

  /// هل يملك المستخدم ضمّ الكتب وإخراجها؟ (مرآةُ حارس الخادم).
  final bool canManage;

  /// «يخصّ كتاباً سابقاً».
  final VoidCallback onRelate;

  /// فتحُ كتابٍ عضوٍ في المعاملة.
  final void Function(CaseMember member) onOpen;

  /// فتحُ شاشة المعاملة نفسها.
  final void Function(int caseFileId) onOpenCase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(relatedCaseProvider((kind, bookId)));
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);

    return async.when(
      loading: () => const SizedBox.shrink(),
      // ⚠️ فشلُ الجلب لا يُسقط الشاشة ولا يُخيف: المعاملة معلومةٌ مساعدة لا جوهر الكتاب.
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        final members = data?.members ?? const <CaseMember>[];
        final hidden = data?.hiddenCount ?? 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 32),
            Row(
              children: [
                Icon(Icons.account_tree_rounded, size: 18, color: AppColors.action(context)),
                const SizedBox(width: 8),
                const Text('الكتب المرتبطة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (data != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => onOpenCase(data.caseFileId),
                      child: Text('— ${data.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.action(context))),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),

            if (members.isEmpty && hidden == 0)
              Text(
                data == null
                    ? 'هذا الكتاب لا ينتمي إلى معاملة بعد.'
                    : 'لا توجد كتبٌ أخرى في هذه المعاملة.',
                style: TextStyle(fontSize: 13, color: muted),
              )
            else
              for (final m in members) ...[
                _MemberRow(member: m, onOpen: () => onOpen(m)),
                if (m != members.last) const SizedBox(height: 10),
              ],

            // 🔐 **العدد يُعلَن والتفاصيل لا** — نظير «عددُ الملغاة يُعلَن» في لوحة المهام.
            if (hidden > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hidden == 1
                          ? 'وكتابٌ آخر في هذه المعاملة خارج صلاحيتك.'
                          : 'و$hidden كتبٍ أخرى في هذه المعاملة خارج صلاحيتك.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                ],
              ),
            ],

            if (canManage) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: onRelate,
                  icon: const Icon(Icons.add_link_rounded, size: 18),
                  // 🔑 **مدخلٌ مُسمّى باسم فعله** (درس ADR-027): المستخدم يظنّ أنه يربط
                  //    بكتاب، والنظام يُنشئ المعاملة خلف الستار — فلا يتعلّم مفهوماً جديداً.
                  label: const Text('يخصّ كتاباً سابقاً'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onOpen});

  final CaseMember member;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    final isIncoming = member.kind == CaseMemberKind.incoming;

    return Row(
      children: [
        // أيقونةٌ تفرّق النوعين بلمحة — فخيطٌ فيه واردٌ وصادر يُقرأ بلا تدقيق.
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (isIncoming ? AppColors.gold : AppColors.success).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded,
            size: 15,
            color: isIncoming ? AppColors.gold : AppColors.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔴 **`Wrap` لا `Row`** (بلاغ المالك 2026-09-21): الثلاثة — الرقم والنوع
              //    والتاريخ — عرضُها الطبيعيّ يتجاوز المتاح داخل بطاقةٍ ضيّقة، ففاضت
              //    **19 بكسلاً**. والبديلُ الآخر (`Flexible` بقصٍّ) كان **يقصّ رقم الكتاب**
              //    وهو **هويّته** — فالسطر الثاني أهونُ من رقمٍ ناقص.
              //
              // 🔒 **والحارس مُثبَتٌ أنه يحرس**: أُعيد `Row` مؤقّتاً فسقطت **خمسةُ**
              //    اختباراتٍ بفيضٍ حقيقيّ (**135 بكسلاً عند 340** و**94 عند 560**).
              //
              // ⚠️ **و`spacing` بدل `SizedBox` اليدويّ**: الفاصل المكتوب بين العناصر
              //    **لا يُطوى مع السطر**، فيبقى فراغاً معلّقاً في آخر السطر الأول.
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(member.number ?? '#${member.bookId}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  Text(member.kind.label, style: TextStyle(fontSize: 11, color: muted)),
                  Text(DateFormat('yyyy/MM/dd').format(member.date),
                      style: TextStyle(fontSize: 11, color: muted)),
                ],
              ),
              const SizedBox(height: 2),
              Text(member.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'فتح الكتاب',
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          onPressed: onOpen,
        ),
      ],
    );
  }
}
