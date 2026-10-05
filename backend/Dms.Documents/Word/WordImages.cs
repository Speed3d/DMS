using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
using Dms.Documents.Images;
using A = DocumentFormat.OpenXml.Drawing;
using DW = DocumentFormat.OpenXml.Drawing.Wordprocessing;
using PIC = DocumentFormat.OpenXml.Drawing.Pictures;

namespace Dms.Documents.Word;

/// <summary>صورٌ في Word (ADR-057): مضمَّنةٌ في السطر (الترويسة · التذييل · الختم) أو خلف النصّ (العلامة المائية).</summary>
internal static class WordImages
{
    /// <summary>نقطةٌ واحدة بوحدات EMU.</summary>
    private const long EmuPerPoint = 12700;

    private static int _id;
    private static uint NextId() => (uint)Interlocked.Increment(ref _id);

    /// <summary>يحجّم الصورة لتسع صندوقاً بالنقاط مع حفظ نسبتها (كـ<c>FitArea</c> في الـPDF).</summary>
    public static (double W, double H) Fit(byte[] image, double maxW, double maxH)
    {
        var (w, h) = ImageOps.Size(image);
        var scale = Math.Min(maxW / w, maxH / h);
        return (w * scale, h * scale);
    }

    private static string AddPart(OpenXmlPart owner, byte[] image)
    {
        ImagePart part = owner switch
        {
            MainDocumentPart m => m.AddImagePart(ImagePartType.Png),
            HeaderPart hp => hp.AddImagePart(ImagePartType.Png),
            FooterPart fp => fp.AddImagePart(ImagePartType.Png),
            _ => throw new InvalidOperationException("جزءٌ لا يقبل الصور."),
        };
        using (var s = new MemoryStream(image)) part.FeedData(s);
        return owner.GetIdOfPart(part);
    }

    private static A.Graphic Graphic(string relId, long cx, long cy, uint id, string name) => new(
        new A.GraphicData(
            new PIC.Picture(
                new PIC.NonVisualPictureProperties(
                    new PIC.NonVisualDrawingProperties { Id = id, Name = name },
                    new PIC.NonVisualPictureDrawingProperties()),
                new PIC.BlipFill(new A.Blip { Embed = relId }, new A.Stretch(new A.FillRectangle())),
                new PIC.ShapeProperties(
                    new A.Transform2D(new A.Offset { X = 0, Y = 0 }, new A.Extents { Cx = cx, Cy = cy }),
                    new A.PresetGeometry(new A.AdjustValueList()) { Preset = A.ShapeTypeValues.Rectangle })))
        { Uri = "http://schemas.openxmlformats.org/drawingml/2006/picture" });

    /// <summary>صورةٌ في السطر بأبعادٍ بالنقاط.</summary>
    public static Run Inline(OpenXmlPart owner, byte[] image, double wPt, double hPt, string name)
    {
        var relId = AddPart(owner, image);
        var id = NextId();
        long cx = (long)(wPt * EmuPerPoint), cy = (long)(hPt * EmuPerPoint);
        return new Run(new Drawing(new DW.Inline(
            new DW.Extent { Cx = cx, Cy = cy },
            new DW.EffectExtent { LeftEdge = 0, TopEdge = 0, RightEdge = 0, BottomEdge = 0 },
            new DW.DocProperties { Id = id, Name = name },
            new DW.NonVisualGraphicFrameDrawingProperties(new A.GraphicFrameLocks { NoChangeAspect = true }),
            Graphic(relId, cx, cy, id, name))
        { DistanceFromTop = 0, DistanceFromBottom = 0, DistanceFromLeft = 0, DistanceFromRight = 0 }));
    }

    /// <summary>صورةٌ **خلف النصّ** في وسط الصفحة — العلامة المائية (شفافيتها مدمجةٌ في الصورة كما في الـPDF).</summary>
    public static Run Behind(OpenXmlPart owner, byte[] image, double wPt, double hPt, string name)
    {
        var relId = AddPart(owner, image);
        var id = NextId();
        long cx = (long)(wPt * EmuPerPoint), cy = (long)(hPt * EmuPerPoint);
        var anchor = new DW.Anchor(
            new DW.SimplePosition { X = 0, Y = 0 },
            new DW.HorizontalPosition(new DW.HorizontalAlignment("center")) { RelativeFrom = DW.HorizontalRelativePositionValues.Page },
            new DW.VerticalPosition(new DW.VerticalAlignment("center")) { RelativeFrom = DW.VerticalRelativePositionValues.Page },
            new DW.Extent { Cx = cx, Cy = cy },
            new DW.EffectExtent { LeftEdge = 0, TopEdge = 0, RightEdge = 0, BottomEdge = 0 },
            new DW.WrapNone(),
            new DW.DocProperties { Id = id, Name = name },
            new DW.NonVisualGraphicFrameDrawingProperties(new A.GraphicFrameLocks { NoChangeAspect = true }),
            Graphic(relId, cx, cy, id, name))
        {
            DistanceFromTop = 0, DistanceFromBottom = 0, DistanceFromLeft = 0, DistanceFromRight = 0,
            SimplePos = false, RelativeHeight = 0, BehindDoc = true, Locked = false,
            LayoutInCell = true, AllowOverlap = true,
        };
        return new Run(new Drawing(anchor));
    }
}
