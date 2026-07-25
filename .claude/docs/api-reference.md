# مرجع الـ API

كل المسارات تحت `/api`. الاستجابات JSON (enums كنصوص). المصادقة: `Authorization: Bearer <JWT>`.
الشركة الفعّالة تُحدَّد بترويسة `X-Company-Id: <id>`: السوبر أدمن (اختياري؛ بلا ترويسة = يرى الكل)، والمستخدم متعدد الشركات (ضمن شركاته المسموحة `companyIds`؛ بلا ترويسة = أول شركة).

**صلاحيات الأقسام (ADR-012):** كل مستخدم له مجموعة أقسام مسموحة `modules` (من الأقسام السبعة: `Outgoing`, `Incoming`, `Archive`, `Reports`, `Users`, `Settings`, `Backup`). الوصول لمسارات القسم المحجوب يُرجِع **403**. السوبر أدمن ورئيس الشركة معفيان (كل الأقسام). «الإعدادات» يحكم كتابات الشركات/القوالب فقط.

## المصادقة — `/api/auth`
| الطريقة | المسار | الوصول | الوصف |
|---|---|---|---|
| POST | `/login` | عام | `{username,password}` → توكنات + بيانات المستخدم (تتضمّن `companyIds` و`modules`) |
| POST | `/refresh` | عام | `{refreshToken}` → توكنات جديدة (تدوير) + `companyIds`/`modules` محدّثة |
| POST | `/logout` | مصادَق | إبطال refresh token |
| GET | `/me` | مصادَق | بيانات المستخدم الحالي (`companyIds` + `modules` = الأقسام المسموحة) |
| POST | `/change-password` | مصادَق | `{currentPassword,newPassword}` |

## الشركات — `/api/companies`
| GET `/` · GET `/{id}` | مصادَق | قائمة/عنصر (يقتصر على شركات المستخدم المسموحة `companyIds`؛ السوبر أدمن يرى الكل) |
| POST `/` | **SuperAdmin** | إنشاء شركة |
| PUT `/{id}` | SuperAdmin/President | تعديل (التعطيل عبر `isActive=false`) |
| POST `/{id}/logo` | SuperAdmin/President/Manager | رفع الشعار (PNG/JPG ≤ 2MB) |
| GET `/{id}/logo` | عام | جلب الشعار |
| DELETE `/{id}` | **SuperAdmin** | حذف جذري **محروس**: يُمنع (409) مع وجود كتب معتمدة أو أرشيف — عطّل الشركة بدل حذفها |

## القوالب — `/api/templates`
| GET `/` · GET `/{id}` | مصادَق |
| POST `/` · PUT `/{id}` | SuperAdmin/President/Manager |
| POST `/{id}/images/{kind}` | Manager+ | رفع صورة (`header`/`footer`/`watermark`) multipart `file` |
| GET `/{id}/images/{kind}` | مصادَق | جلب الصورة |

## القوائم
- `/api/entities` — GET (مصادَق) · POST/PUT/DELETE (Manager+؛ الحذف يُرفض 409 إن كانت مستخدَمة).
- `/api/document-types` — GET (مصادَق) · POST/PUT (Manager+).
- `/api/departments` — GET (مصادَق) · POST/PUT/DELETE (Manager+). الأقسام: وجهة إحالة الوارد ومكان عمل الموظف (ADR-015). الحذف يُرفض 409 إن كان محالاً إليه كتب واردة (يُقترح التعطيل).
- `/api/exchange-rates` — GET `/` · GET `/latest?currency=USD` · POST (Manager+).

## المستخدمون والتفويض
- `/api/users` (SuperAdmin/President/Manager + قسم `Users`): GET، POST، PUT `/{id}`، POST `/{id}/reset-password`. الهرمية والعزل مفروضان في الخدمة.
  - المدخلات تحمل `companyIds` و`modules` (قائمة أسماء الأقسام). **ربط الشركات وتحديد الأقسام حصراً للسوبر أدمن ورئيس الشركة**؛ المدير/الموظف لا يغيّرانها (تُتجاهل ← افتراضي). أدوار السوبر أدمن/الرئيس تُخزَّن بكل الأقسام. غير السوبر أدمن يلزمه شركة واحدة على الأقل. الاستجابة تُعيد `companyIds` و`modules`.
- `/api/delegations` (Manager+): GET، POST، DELETE `/{id}`.

## الصادر — `/api/outgoing`
| الطريقة | المسار | الوصف |
|---|---|---|
| GET | `/?status=&search=` | قائمة (الموظف يرى عمله فقط) |
| GET | `/{id}` | تفاصيل (يتضمّن `rowVersion` base64) |
| POST | `/` | إنشاء مسودّة (Employee+) |
| PUT | `/{id}` | تعديل مسودّة |
| POST | `/{id}/approve` | اعتماد → رقم + PDF + QR (CanApprove) |
| PUT | `/{id}/edit-approved` | تعديل بعد الاعتماد (Manager+) — يتطلب `rowVersion` |
| DELETE | `/{id}` | حذف ناعم |
| GET | `/{id}/versions` | سجل الإصدارات |
| GET | `/{id}/pdf` | تنزيل PDF |
| GET | `/{id}/word` | تصدير Word |

## الوارد — `/api/incoming`
يتطلب قسم `Incoming`. الموظف/القارئ يرى الكتب التي استلمها فقط.

| الطريقة | المسار | الوصف |
|---|---|---|
| GET | `/?search=&status=&entityId=&from=&to=&documentTypeId=&departmentId=&receiveMethod=` | بحث (نصّي في الرقم الداخلي/الخارجي والموضوع والكلمات المفتاحية والملاحظات واسم الجهة). قيمة `status` أو `receiveMethod` غير صحيحة → **400**. الموظف/القارئ يرى كتبه + كتب قسمه (ADR-015) |
| GET | `/{id}` | تفاصيل (تتضمّن اسم الجهة ونوع المستند واسم المستلم ورقم الصادر المرتبط) |
| POST | `/` | تسجيل كتاب وارد (Employee+) — **ترقيم فوري** `PREFIX-IN-YEAR-#####`، الحالة الابتدائية `New` |
| PUT | `/{id}` | تعديل — المدير فأعلى في أي حالة عدا `Archived`؛ المنشئ في حالة `New` فقط |
| POST | `/{id}/status` | تغيير الحالة `{status,note}` — يخضع لمصفوفة الانتقالات (ADR-013). الأرشفة للمدير فأعلى؛ الموظف/القارئ: `New→InReview` فقط. الملاحظة **إلزامية** عند `Replied` يدوياً بلا ربط بصادر |
| POST | `/{id}/forward` | إحالة لقسم `{departmentId,note}` — للحالتين `New`/`InReview` فقط، وتنقل `New` تلقائياً إلى `InReview`. الكتاب يظهر بعدها لموظفي القسم |
| POST | `/{id}/status` | تغيير الحالة — الموظف يقتصر على `New→InReview` إلا بصلاحية `CanManageIncoming` فيدير كل الحالات عدا الأرشفة (ADR-015) |
| POST | `/{id}/link/{outgoingId}` | ربط بصادر **معتمد** (Manager+) → الحالة `Replied`. يُرفض على المغلق/المؤرشف، ويُرفض الربط المزدوج من الطرفين (**409**) |
| DELETE | `/{id}/link` | فك الارتباط (Manager+) — يُعيد `Replied` إلى `InReview`؛ يُرفض على المؤرشف أو بلا ارتباط (**400**) |
| DELETE | `/{id}` | حذف ناعم — المنشئ وهو `New`؛ المدير فأعلى لبقية الحالات؛ **المؤرشف: SuperAdmin فقط** |
| GET | `/{id}/movements` | سجل الحركة (**SuperAdmin/President فقط** — غيرهما 403) مع أسماء المنفّذين |
| GET/POST | `/{id}/attachments` | قائمة/رفع مرفق |
| DELETE | `/{id}/attachments/{attachmentId}` | حذف مرفق (غير القارئ) |
| GET | `/{id}/attachments/{attachmentId}/download` | تنزيل مرفق (يتطلب مصادقة) |

> **الربط العكسي:** `GET /api/outgoing/{id}` يُرجِع `replyToIncomingId` و`replyToIncomingNumber` للكتاب الوارد الذي يردّ عليه.

## الأرشيف — `/api/archive`
| الطريقة | المسار | الوصف |
|---|---|---|
| GET | `/?search=&from=&to=&documentTypeId=&entityId=` | بحث (نصّي + فترة زمنية على BookDate أو CreatedAt). الموظف/القارئ: عمله فقط |
| GET | `/{id}` | تفاصيل |
| POST | `/` | إنشاء (Employee+) — ترقيم تلقائي `PREFIX-AR-YEAR-#####` |
| PUT | `/{id}` | تعديل (المالك أو Manager+) |
| DELETE | `/{id}` | حذف ناعم |
| GET | `/{id}/attachments` | قائمة المرفقات |
| POST | `/{id}/attachments` | رفع مرفق (multipart `file`) — PDF/JPG/PNG/DOCX/XLSX، حد 25MB |

## المرفقات — `/api/attachments`
| GET `/{id}` | تنزيل المرفق (مع تحقق صلاحية المالك) |
| DELETE `/{id}` | حذف المرفق (Employee+) |

## التقارير — `/api/reports`
| الطريقة | المسار | الوصف |
|---|---|---|
| GET | `/financial?from=&to=&entityId=&source=` | تقرير مالي (JSON): يجمع الصادر المعتمد + الأرشيف بالدينار. `source`: All/Outgoing/Archive. الموظف/القارئ: عمله فقط |
| GET | `/financial/pdf?...` | تصدير التقرير PDF (QuestPDF) |
| GET | `/financial/excel?...` | تصدير التقرير Excel (.xlsx) |

## حالة النظام — `/api/system`
| GET | `/status` | **عام** | `{maintenance, reason, since}` — يبقى مجيباً أثناء الصيانة (استعادة نسخة). العميل يستعلم به ليعرف متى عاد النظام |

## النسخ الاحتياطي — `/api/backup` (SuperAdmin فقط)
| الطريقة | المسار | الوصف |
|---|---|---|
| GET | `/` | قائمة النسخ (يتضمّن `scope` و`category`) |
| POST | `/run` | نسخة يدوية فورية (كاملة: DB + ملفات → ZIP) |
| POST | `/{id}/restore` | **استعادة** — `{confirmation:"استعادة"}`. تأخذ نسخة أمان أولاً ثم تدخل وضع الصيانة (ADR-014) |
| GET | `/schedule` | إعداد الجدولة الحالي |
| PUT | `/schedule` | تحديث الجدولة `{frequency:Off/Daily/Weekly, enabled, hour}` — «يومي» يُنتج دورة جد/أب/ابن تلقائياً |
| GET | `/{id}/download` | تنزيل أرشيف النسخة (ZIP) |

> **النطاق والاحتفاظ (ADR-014):** اليومية «قاعدة فقط» (خفيفة)، والأسبوعية/الشهرية/اليدوية كاملة. الاحتفاظ: 7 يومية · 4 أسبوعية · 12 شهرية · 20 يدوية (التقليم تلقائي بعد كل نسخة ناجحة).

## التدقيق والتحقق
- `GET /api/audit?take=` (Manager+) — أحدث السجلات.
- `POST /api/verify` (عام) — `{qrContent}` → `{isValid, message, number, date, entity, amountInIqd, foundInDb}`.

## أكواد الأخطاء
`400` خرق قاعدة عمل · `401` غير مصادَق · `403` صلاحية غير كافية · `404` غير موجود · `409` تعارض (تزامن/تكرار) · `500` غير متوقّع. الجسم: `{ "error": "..." }`.
