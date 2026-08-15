param(
	[string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path,
	[string]$SourceRelativePath = "paper_doll_preview\reference_matched_six_view_sheet.png",
	[string]$OutputRelativePath = "assets\paper_doll\reference_match"
)

$ErrorActionPreference = "Stop"
$sourcePath = Join-Path $ProjectRoot $SourceRelativePath
$outputDirectory = Join-Path $ProjectRoot $OutputRelativePath
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
	throw "Reference-matched preview is missing: $sourcePath"
}
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$builderSource = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;

public static class ReferenceMatchedRuntimeBuilder {
    private sealed class PixelQueue {
        private readonly Queue<Point> queue = new Queue<Point>();
        public void Add(Point point) { queue.Enqueue(point); }
        public bool Any { get { return queue.Count > 0; } }
        public Point Take() { return queue.Dequeue(); }
    }

    private static bool IsBackground(Color color) {
        return color.A > 0 && color.R >= 245 && color.G >= 245 && color.B >= 245
            && Math.Abs(color.R - color.G) < 10
            && Math.Abs(color.G - color.B) < 10;
    }

    private static void RemoveBorderBackground(Bitmap bitmap) {
        int width = bitmap.Width;
        int height = bitmap.Height;
        bool[] visited = new bool[width * height];
        PixelQueue queue = new PixelQueue();
        // The generated board has a white border.  Seed every border pixel,
        // then flood-fill only background-colored pixels so enclosed white
        // highlights remain part of the armor/hair.
        for (int x = 0; x < width; x++) {
            if (IsBackground(bitmap.GetPixel(x, 0))) queue.Add(new Point(x, 0));
            if (IsBackground(bitmap.GetPixel(x, height - 1))) queue.Add(new Point(x, height - 1));
        }
        for (int y = 0; y < height; y++) {
            if (IsBackground(bitmap.GetPixel(0, y))) queue.Add(new Point(0, y));
            if (IsBackground(bitmap.GetPixel(width - 1, y))) queue.Add(new Point(width - 1, y));
        }
        int[] dx = new int[] { -1, 1, 0, 0 };
        int[] dy = new int[] { 0, 0, -1, 1 };
        while (queue.Any) {
            Point point = queue.Take();
            if (point.X < 0 || point.Y < 0 || point.X >= width || point.Y >= height) continue;
            int index = point.Y * width + point.X;
            if (visited[index]) continue;
            visited[index] = true;
            if (!IsBackground(bitmap.GetPixel(point.X, point.Y))) continue;
            bitmap.SetPixel(point.X, point.Y, Color.Transparent);
            for (int i = 0; i < 4; i++) {
                queue.Add(new Point(point.X + dx[i], point.Y + dy[i]));
            }
        }
        // Generated board background is white but is separated by anti-aliased
        // light edges. Remove the remaining near-white pixels only in the
        // extracted crops below, where the silhouette bounds are known.
    }

    private static Bitmap BuildSheet(Bitmap source, Rectangle frontCrop, Rectangle backCrop, Rectangle sideCrop, bool mounted) {
        const int frameSize = 64;
        const int rows = 3;
        const int columns = 8;
        const int anchorY = 56;
        Bitmap sheet = new Bitmap(frameSize * columns, frameSize * rows, PixelFormat.Format32bppArgb);
        using (Graphics sheetGraphics = Graphics.FromImage(sheet)) {
            sheetGraphics.Clear(Color.Transparent);
            sheetGraphics.CompositingMode = CompositingMode.SourceCopy;
            sheetGraphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            sheetGraphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            for (int row = 0; row < rows; row++) {
                // row 0 = front, row 1 = back (same centered fit), row 2 = side
                Rectangle sourceRect = row == 0 ? frontCrop : (row == 1 ? backCrop : sideCrop);
                int targetHeight = mounted ? 52 : 56;
                // The reference boards use a wider back silhouette than the
                // raw crops. Keep this explicit per pose so UP is not a thin
                // front crop and SIDE remains a readable profile.
                int[] targetWidths = mounted
                    ? new int[] { 24, 41, 40 }
                    : new int[] { 37, 44, 31 };
                int targetWidth = targetWidths[row];
                int x = (frameSize - targetWidth) / 2;
                int y = anchorY - targetHeight;
                for (int column = 0; column < columns; column++) {
                    Rectangle destination = new Rectangle(
                        column * frameSize + x,
                        row * frameSize + (mounted ? 4 : y),
                        targetWidth,
                        targetHeight
                    );
                    sheetGraphics.DrawImage(source, destination, sourceRect, GraphicsUnit.Pixel);
                }
            }
        }
        for (int y = 0; y < sheet.Height; y++) {
            for (int x = 0; x < sheet.Width; x++) {
                Color pixel = sheet.GetPixel(x, y);
                if (IsBackground(pixel)) sheet.SetPixel(x, y, Color.Transparent);
            }
        }
        return sheet;
    }

    public static void Build(string sourcePath, string outputDirectory) {
        using (Bitmap source = new Bitmap(sourcePath)) {
            RemoveBorderBackground(source);
            // Bounds are measured from the actual generated sheet, not the old
            // asset boards.  Each crop is a complete, already aligned silhouette.
            Rectangle onFootFront = new Rectangle(217, 27, 205, 368);
            Rectangle onFootBack = new Rectangle(648, 27, 174, 368);
            Rectangle onFootSide = new Rectangle(1094, 30, 136, 364);
            Rectangle mountedFront = new Rectangle(208, 430, 211, 502);
            Rectangle mountedBack = new Rectangle(627, 433, 217, 499);
            Rectangle mountedSide = new Rectangle(937, 436, 421, 496);
            using (Bitmap onFoot = BuildSheet(source, onFootFront, onFootBack, onFootSide, false)) {
                onFoot.Save(System.IO.Path.Combine(outputDirectory, "reference_match_body_on_foot_unisex.png"), ImageFormat.Png);
            }
            using (Bitmap mounted = BuildSheet(source, mountedFront, mountedBack, mountedSide, true)) {
                mounted.Save(System.IO.Path.Combine(outputDirectory, "reference_match_body_mounted_unisex.png"), ImageFormat.Png);
            }
        }
    }
}
'@

Add-Type -ReferencedAssemblies "System.Drawing.dll" -TypeDefinition $builderSource
[ReferenceMatchedRuntimeBuilder]::Build($sourcePath, $outputDirectory)
Get-ChildItem -LiteralPath $outputDirectory -Filter "reference_match_body_*.png" | Select-Object FullName,Length,LastWriteTime
