namespace Dms.Domain;

public enum BackupFrequency { Off = 0, Daily = 1, Weekly = 2 }
public enum BackupType { Manual = 0, Scheduled = 1 }
public enum BackupStatus { Success = 0, Failed = 1 }

/// <summary>سجلّ عملية نسخ احتياطي (قاعدة البيانات + ملفات التخزين في أرشيف ZIP واحد).</summary>
public class BackupRecord
{
    public int BackupRecordId { get; set; }
    public DateTime CreatedAt { get; set; }
    public int? CreatedByUserId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public long SizeBytes { get; set; }
    public BackupType Type { get; set; }
    public BackupStatus Status { get; set; }
    public string? Note { get; set; }
}

/// <summary>إعداد جدولة النسخ الاحتياطي (صفّ مفرد، يتحكم به السوبر أدمن فقط).</summary>
public class BackupSchedule
{
    public int BackupScheduleId { get; set; }
    public BackupFrequency Frequency { get; set; } = BackupFrequency.Off;
    public bool Enabled { get; set; }

    /// <summary>ساعة التشغيل (0–23، توقيت الخادم المحلي).</summary>
    public int Hour { get; set; } = 2;

    public DateTime? LastRunAt { get; set; }
    public DateTime? NextRunAt { get; set; }
}
