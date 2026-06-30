namespace Dms.Infrastructure.Services;

/// <summary>مسارات النظام المُحلَّة في الإقلاع (تخزين الملفات + مجلد النسخ الاحتياطي).</summary>
public sealed record AppPaths(string StorageRoot, string BackupDir);
