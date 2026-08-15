param(
	[string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path,
	[string]$OutputRelativePath = "assets\paper_doll\reference_match"
)

$ErrorActionPreference = "Stop"
$referenceDirectory = Join-Path $ProjectRoot "assets\doll\reference"
$outputDirectory = Join-Path $ProjectRoot $OutputRelativePath
if (-not (Test-Path -LiteralPath $referenceDirectory -PathType Container)) {
	throw "Missing acceptance reference directory: $referenceDirectory"
}
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Add-Type -AssemblyName "System.Drawing"
function Find-ReferenceImageBySize {
	param([int]$Width, [int]$Height)
	foreach ($file in @(Get-ChildItem -LiteralPath $referenceDirectory -Filter "*.png" -File)) {
		$bitmap = [System.Drawing.Bitmap]::new($file.FullName)
		try {
			if ($bitmap.Width -eq $Width -and $bitmap.Height -eq $Height) {
				return $file.FullName
			}
		} finally {
			$bitmap.Dispose()
		}
	}
	throw ("No acceptance reference image with size {0}x{1} exists in {2}" -f $Width, $Height, $referenceDirectory)
}

# The filenames are localized and may be stored with a legacy code page.
# Resolve by stable board dimensions instead of embedding a filename.
$onFootCandidate = @(Get-ChildItem -LiteralPath $referenceDirectory -Filter "*.png" -File |
	Where-Object { $_.Name -eq "不戴帽步行.png" })
$mountedCandidate = @(Get-ChildItem -LiteralPath $referenceDirectory -Filter "*.png" -File |
	Where-Object { $_.Name -eq "不帶帽騎馬.png" })
$onFootPath = if ($onFootCandidate.Count -eq 1) { $onFootCandidate[0].FullName } else { Find-ReferenceImageBySize 2170 725 }
$mountedPath = if ($mountedCandidate.Count -eq 1) { $mountedCandidate[0].FullName } else { Find-ReferenceImageBySize 1774 887 }

$builderSource = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

public static class ReferenceAssetRuntimeBuilder {
	private const int Frame = 64;
	private const int Columns = 8;
	private const int Rows = 3;

	private static bool IsBackground(Color color) {
		int max = Math.Max(color.R, Math.Max(color.G, color.B));
		int min = Math.Min(color.R, Math.Min(color.G, color.B));
		// Flood-fill only from the board edge, so this broad threshold removes
		// antialiased white halo pixels. Hair holes are repaired after every
		// frame-level cleanup, where exterior and interior are distinguishable.
		return color.A > 0 && max >= 228 && max - min < 24;
	}

	private static void RemoveBorderBackground(Bitmap bitmap) {
		int width = bitmap.Width;
		int height = bitmap.Height;
		bool[] visited = new bool[width * height];
		Queue<Point> queue = new Queue<Point>();
		for (int x = 0; x < width; x++) {
			queue.Enqueue(new Point(x, 0));
			queue.Enqueue(new Point(x, height - 1));
		}
		for (int y = 0; y < height; y++) {
			queue.Enqueue(new Point(0, y));
			queue.Enqueue(new Point(width - 1, y));
		}
		int[] dx = new int[] { -1, 1, 0, 0 };
		int[] dy = new int[] { 0, 0, -1, 1 };
		while (queue.Count > 0) {
			Point point = queue.Dequeue();
			if (point.X < 0 || point.Y < 0 || point.X >= width || point.Y >= height) continue;
			int index = point.Y * width + point.X;
			if (visited[index]) continue;
			visited[index] = true;
			if (!IsBackground(bitmap.GetPixel(point.X, point.Y))) continue;
			bitmap.SetPixel(point.X, point.Y, Color.Transparent);
			for (int i = 0; i < 4; i++) {
				queue.Enqueue(new Point(point.X + dx[i], point.Y + dy[i]));
			}
		}
	}

	private static Bitmap Trim(Bitmap input) {
		KeepLargestAlphaComponent(input);
		int minX = input.Width, minY = input.Height, maxX = -1, maxY = -1;
		for (int y = 0; y < input.Height; y++) {
			for (int x = 0; x < input.Width; x++) {
				if (input.GetPixel(x, y).A <= 12) continue;
				minX = Math.Min(minX, x);
				minY = Math.Min(minY, y);
				maxX = Math.Max(maxX, x);
				maxY = Math.Max(maxY, y);
			}
		}
		if (maxX < minX) return new Bitmap(1, 1, PixelFormat.Format32bppArgb);
		return input.Clone(
			new Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1),
			PixelFormat.Format32bppArgb
		);
	}

	private static void KeepLargestAlphaComponent(Bitmap bitmap) {
		int width = bitmap.Width;
		int height = bitmap.Height;
		bool[] foreground = new bool[width * height];
		bool[] visited = new bool[width * height];
		for (int y = 0; y < height; y++) {
			for (int x = 0; x < width; x++) {
				foreground[y * width + x] = bitmap.GetPixel(x, y).A > 12;
			}
		}
		int[] dx = new int[] { -1, 1, 0, 0 };
		int[] dy = new int[] { 0, 0, -1, 1 };
		List<Point> largest = new List<Point>();
		for (int y = 0; y < height; y++) {
			for (int x = 0; x < width; x++) {
				int start = y * width + x;
				if (!foreground[start] || visited[start]) continue;
				List<Point> component = new List<Point>();
				Queue<Point> queue = new Queue<Point>();
				visited[start] = true;
				queue.Enqueue(new Point(x, y));
				while (queue.Count > 0) {
					Point point = queue.Dequeue();
					component.Add(point);
					for (int i = 0; i < 4; i++) {
						int nx = point.X + dx[i];
						int ny = point.Y + dy[i];
						if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
						int index = ny * width + nx;
						if (foreground[index] && !visited[index]) {
							visited[index] = true;
							queue.Enqueue(new Point(nx, ny));
						}
					}
				}
				if (component.Count > largest.Count) largest = component;
			}
		}
		bool[] keep = new bool[width * height];
		foreach (Point point in largest) keep[point.Y * width + point.X] = true;
		for (int y = 0; y < height; y++) {
			for (int x = 0; x < width; x++) {
				if (!keep[y * width + x]) bitmap.SetPixel(x, y, Color.Transparent);
			}
		}
	}

	private static void RemoveIslands(Bitmap bitmap) {
		int width = bitmap.Width;
		int height = bitmap.Height;
		bool[] foreground = new bool[width * height];
		bool[] visited = new bool[width * height];
		for (int y = 0; y < height; y++) {
			for (int x = 0; x < width; x++) {
				Color color = bitmap.GetPixel(x, y);
				int max = Math.Max(color.R, Math.Max(color.G, color.B));
				int min = Math.Min(color.R, Math.Min(color.G, color.B));
				double luminance = color.R * 0.2126 + color.G * 0.7152 + color.B * 0.0722;
				foreground[y * width + x] = color.A > 12
					&& (luminance < 224.4 || max - min > 36);
			}
		}
		int[] dx = new int[] { -1, 1, 0, 0 };
		int[] dy = new int[] { 0, 0, -1, 1 };
		for (int y = 0; y < height; y++) {
			for (int x = 0; x < width; x++) {
				int start = y * width + x;
				if (!foreground[start] || visited[start]) continue;
				List<Point> component = new List<Point>();
				Queue<Point> queue = new Queue<Point>();
				visited[start] = true;
				queue.Enqueue(new Point(x, y));
				while (queue.Count > 0) {
					Point point = queue.Dequeue();
					component.Add(point);
					for (int i = 0; i < 4; i++) {
						int nx = point.X + dx[i];
						int ny = point.Y + dy[i];
						if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
						int index = ny * width + nx;
						if (foreground[index] && !visited[index]) {
							visited[index] = true;
							queue.Enqueue(new Point(nx, ny));
						}
					}
				}
				if (component.Count < 512) {
					foreach (Point point in component) bitmap.SetPixel(point.X, point.Y, Color.Transparent);
				}
			}
		}
	}

	private static Bitmap Extract(Bitmap source, Rectangle crop) {
		using (Bitmap cropped = source.Clone(crop, PixelFormat.Format32bppArgb)) {
			RemoveBorderBackground(cropped);
			RemoveIslands(cropped);
			return Trim(cropped);
		}
	}

	private static int Median(List<int> values) {
		values.Sort();
		return values[values.Count / 2];
	}

	private static Bitmap DownsampleMedian(Bitmap source, int width, int height) {
		Bitmap result = new Bitmap(width, height, PixelFormat.Format32bppArgb);
		for (int y = 0; y < height; y++) {
			int sourceY0 = (int)Math.Floor((double)y * source.Height / height);
			int sourceY1 = Math.Max(sourceY0 + 1, (int)Math.Ceiling((double)(y + 1) * source.Height / height));
			for (int x = 0; x < width; x++) {
				int sourceX0 = (int)Math.Floor((double)x * source.Width / width);
				int sourceX1 = Math.Max(sourceX0 + 1, (int)Math.Ceiling((double)(x + 1) * source.Width / width));
				int sampleCount = (sourceX1 - sourceX0) * (sourceY1 - sourceY0);
				List<int> red = new List<int>();
				List<int> green = new List<int>();
				List<int> blue = new List<int>();
				for (int sourceY = sourceY0; sourceY < sourceY1; sourceY++) {
					for (int sourceX = sourceX0; sourceX < sourceX1; sourceX++) {
						Color color = source.GetPixel(sourceX, sourceY);
						if (color.A <= 32) continue;
						red.Add(color.R);
						green.Add(color.G);
						blue.Add(color.B);
					}
				}
				// A small amount of foreground coverage is enough to retain the
				// one-pixel silhouette; the median rejects minority hair specks.
				if (red.Count * 4 < sampleCount) {
					result.SetPixel(x, y, Color.Transparent);
					continue;
				}
				result.SetPixel(x, y, Color.FromArgb(
					255,
					Median(red),
					Median(green),
					Median(blue)
				));
			}
		}
		return result;
	}

	private static Color MedianOpaqueNeighbour(Bitmap bitmap, int x, int y) {
		List<int> red = new List<int>();
		List<int> green = new List<int>();
		List<int> blue = new List<int>();
		for (int ny = Math.Max(0, y - 2); ny <= Math.Min(bitmap.Height - 1, y + 2); ny++) {
			for (int nx = Math.Max(0, x - 2); nx <= Math.Min(bitmap.Width - 1, x + 2); nx++) {
				Color color = bitmap.GetPixel(nx, ny);
				if (color.A <= 12) continue;
				red.Add(color.R);
				green.Add(color.G);
				blue.Add(color.B);
			}
		}
		if (red.Count == 0) return Color.Transparent;
		return Color.FromArgb(255, Median(red), Median(green), Median(blue));
	}

	private static bool TryFillHairPinhole(Bitmap bitmap, int x, int y, int headBottom) {
		if (bitmap.GetPixel(x, y).A > 12) return false;
		bool horizontal = false;
		bool vertical = false;
		for (int distance = 1; distance <= 3; distance++) {
			if (x - distance >= 0 && x + distance < bitmap.Width
				&& bitmap.GetPixel(x - distance, y).A > 12
				&& bitmap.GetPixel(x + distance, y).A > 12) horizontal = true;
			if (y - distance >= 0 && y + distance < headBottom
				&& bitmap.GetPixel(x, y - distance).A > 12
				&& bitmap.GetPixel(x, y + distance).A > 12) vertical = true;
		}
		if (!horizontal || !vertical) return false;
		Color fill = MedianOpaqueNeighbour(bitmap, x, y);
		int spread = Math.Max(fill.R, Math.Max(fill.G, fill.B))
			- Math.Min(fill.R, Math.Min(fill.G, fill.B));
		double luminance = fill.R * 0.2126 + fill.G * 0.7152 + fill.B * 0.0722;
		if (fill.A <= 12 || spread >= 28 || luminance < 150.0) return false;
		bitmap.SetPixel(x, y, fill);
		return true;
	}

	private static void FillEnclosedHeadHoles(Bitmap reduced) {
		// White hair is close to the board colour. Chroma-keying can therefore
		// leave tiny transparent holes that become black specks on a dark UI.
		// Only fill small transparent components fully enclosed in the head band;
		// genuine silhouette gaps stay connected to this band's outer boundary.
		int headBottom = Math.Min(24, reduced.Height);
		bool[] visited = new bool[reduced.Width * headBottom];
		int[] dx = new int[] { -1, 1, 0, 0 };
		int[] dy = new int[] { 0, 0, -1, 1 };
		for (int y = 0; y < headBottom; y++) {
			for (int x = 0; x < reduced.Width; x++) {
				int start = y * reduced.Width + x;
				if (visited[start] || reduced.GetPixel(x, y).A > 12) continue;
				List<Point> hole = new List<Point>();
				Queue<Point> queue = new Queue<Point>();
				bool touchesBoundary = false;
				visited[start] = true;
				queue.Enqueue(new Point(x, y));
				while (queue.Count > 0) {
					Point point = queue.Dequeue();
					hole.Add(point);
					if (point.X == 0 || point.X == reduced.Width - 1 || point.Y == 0 || point.Y == headBottom - 1) {
						touchesBoundary = true;
					}
					for (int i = 0; i < 4; i++) {
						int nx = point.X + dx[i];
						int ny = point.Y + dy[i];
						if (nx < 0 || ny < 0 || nx >= reduced.Width || ny >= headBottom) continue;
						int index = ny * reduced.Width + nx;
						if (!visited[index] && reduced.GetPixel(nx, ny).A <= 12) {
							visited[index] = true;
							queue.Enqueue(new Point(nx, ny));
						}
					}
				}
				if (touchesBoundary || hole.Count > 12) continue;
				foreach (Point point in hole) {
					Color fill = MedianOpaqueNeighbour(reduced, point.X, point.Y);
					if (fill.A > 12) reduced.SetPixel(point.X, point.Y, fill);
				}
			}
		}
		// Some pinholes remain linked to the exterior by a hairline channel. Two
		// passes are enough for the largest observed two-pixel gap.
		for (int pass = 0; pass < 2; pass++) {
			for (int y = 1; y < headBottom - 1; y++) {
				for (int x = 1; x < reduced.Width - 1; x++) {
					TryFillHairPinhole(reduced, x, y, headBottom);
				}
			}
		}
	}

	private static void FillSheetHeadHoles(Bitmap sheet) {
		for (int row = 0; row < Rows; row++) {
			for (int column = 0; column < Columns; column++) {
				Rectangle area = new Rectangle(column * Frame, row * Frame, Frame, Frame);
				using (Bitmap frame = sheet.Clone(area, PixelFormat.Format32bppArgb)) {
					FillEnclosedHeadHoles(frame);
					for (int y = 0; y < Frame; y++) {
						for (int x = 0; x < Frame; x++) {
							sheet.SetPixel(area.X + x, area.Y + y, frame.GetPixel(x, y));
						}
					}
				}
			}
		}
	}

	private static Bitmap BuildSheet(
		Bitmap source,
		Rectangle[] crops,
		int[] targetWidths,
		bool mounted
	) {
		int targetHeight = mounted ? 52 : 56;
		int rowOffset = mounted ? 4 : 0;
		Bitmap sheet = new Bitmap(Frame * Columns, Frame * Rows, PixelFormat.Format32bppArgb);
		using (Graphics graphics = Graphics.FromImage(sheet)) {
			graphics.Clear(Color.Transparent);
			graphics.CompositingMode = CompositingMode.SourceCopy;
			for (int row = 0; row < Rows; row++) {
				using (Bitmap silhouette = Extract(source, crops[row]))
				using (Bitmap reduced = DownsampleMedian(silhouette, targetWidths[row], targetHeight)) {
					int x = (Frame - targetWidths[row]) / 2;
					int y = rowOffset;
					for (int column = 0; column < Columns; column++) {
						graphics.DrawImageUnscaled(reduced, column * Frame + x, row * Frame + y);
					}
				}
			}
		}
		ClearFrameBackground(sheet);
		ClearFrameEdgeIslands(sheet);
		RemoveSmallFrameComponents(sheet);
		FillSheetHeadHoles(sheet);
		return sheet;
	}

	private static bool IsFrameBackground(Color color) {
		return color.A > 0
			&& color.R >= 242
			&& color.G >= 242
			&& color.B >= 242
			&& Math.Abs(color.R - color.G) < 24
			&& Math.Abs(color.G - color.B) < 24;
	}

	private static void ClearFrameBackground(Bitmap sheet) {
		int[] dx = new int[] { -1, 1, 0, 0 };
		int[] dy = new int[] { 0, 0, -1, 1 };
		for (int row = 0; row < Rows; row++) {
			for (int column = 0; column < Columns; column++) {
				int originX = column * Frame;
				int originY = row * Frame;
				bool[] visited = new bool[Frame * Frame];
				Queue<Point> queue = new Queue<Point>();
				for (int x = 0; x < Frame; x++) {
					queue.Enqueue(new Point(originX + x, originY));
					queue.Enqueue(new Point(originX + x, originY + Frame - 1));
				}
				for (int y = 0; y < Frame; y++) {
					queue.Enqueue(new Point(originX, originY + y));
					queue.Enqueue(new Point(originX + Frame - 1, originY + y));
				}
				while (queue.Count > 0) {
					Point point = queue.Dequeue();
					int localX = point.X - originX;
					int localY = point.Y - originY;
					if (localX < 0 || localY < 0 || localX >= Frame || localY >= Frame) continue;
					int index = localY * Frame + localX;
					if (visited[index]) continue;
					visited[index] = true;
					if (!IsFrameBackground(sheet.GetPixel(point.X, point.Y))) continue;
					sheet.SetPixel(point.X, point.Y, Color.Transparent);
					for (int i = 0; i < 4; i++) {
						queue.Enqueue(new Point(point.X + dx[i], point.Y + dy[i]));
					}
				}
			}
		}
	}

	private static void ClearFrameEdgeIslands(Bitmap sheet) {
		for (int row = 0; row < Rows; row++) {
			for (int column = 0; column < Columns; column++) {
				int originX = column * Frame;
				int originY = row * Frame;
				for (int y = 0; y < Frame; y++) {
					for (int x = 0; x < Frame; x++) {
						if (x >= 4 && x < Frame - 4 && y >= 4 && y < Frame - 4) continue;
						Color pixel = sheet.GetPixel(originX + x, originY + y);
						if (pixel.A > 0 && pixel.R > 90 && pixel.G > 45 && pixel.B < 80) {
							sheet.SetPixel(originX + x, originY + y, Color.Transparent);
						}
					}
				}
			}
		}
	}

	private static bool IsRenderedForeground(Color color) {
		if (color.A <= 12) return false;
		double luminance = color.R * 0.2126 + color.G * 0.7152 + color.B * 0.0722;
		int max = Math.Max(color.R, Math.Max(color.G, color.B));
		int min = Math.Min(color.R, Math.Min(color.G, color.B));
		return luminance < 224.4 || max - min > 36;
	}

	private static void RemoveSmallFrameComponents(Bitmap sheet) {
		const int MinimumComponentPixels = 24;
		int[] dx = new int[] { -1, 1, 0, 0 };
		int[] dy = new int[] { 0, 0, -1, 1 };
		for (int row = 0; row < Rows; row++) {
			for (int column = 0; column < Columns; column++) {
				int originX = column * Frame;
				int originY = row * Frame;
				bool[] visited = new bool[Frame * Frame];
				for (int localY = 0; localY < Frame; localY++) {
					for (int localX = 0; localX < Frame; localX++) {
						int start = localY * Frame + localX;
						if (visited[start] || !IsRenderedForeground(sheet.GetPixel(originX + localX, originY + localY))) continue;
						List<Point> component = new List<Point>();
						Queue<Point> queue = new Queue<Point>();
						visited[start] = true;
						queue.Enqueue(new Point(localX, localY));
						while (queue.Count > 0) {
							Point point = queue.Dequeue();
							component.Add(point);
							for (int i = 0; i < 4; i++) {
								int nx = point.X + dx[i];
								int ny = point.Y + dy[i];
								if (nx < 0 || ny < 0 || nx >= Frame || ny >= Frame) continue;
								int index = ny * Frame + nx;
								if (visited[index] || !IsRenderedForeground(sheet.GetPixel(originX + nx, originY + ny))) continue;
								visited[index] = true;
								queue.Enqueue(new Point(nx, ny));
							}
						}
						if (component.Count < MinimumComponentPixels) {
							foreach (Point point in component) sheet.SetPixel(originX + point.X, originY + point.Y, Color.Transparent);
						}
					}
				}
			}
		}
	}

	public static void Build(string onFootPath, string mountedPath, string outputDirectory) {
		using (Bitmap onFootSource = new Bitmap(onFootPath))
		using (Bitmap mountedSource = new Bitmap(mountedPath)) {
			RemoveBorderBackground(onFootSource);
			RemoveBorderBackground(mountedSource);
			Rectangle[] footCrops = new Rectangle[] {
				new Rectangle(313, 42, 407, 603),
				new Rectangle(720, 50, 518, 594),
				new Rectangle(1470, 50, 280, 594),
			};
			Rectangle[] mountedCrops = new Rectangle[] {
				new Rectangle(196, 39, 306, 744),
				new Rectangle(669, 38, 298, 745),
				new Rectangle(1093, 39, 590, 743),
			};
			// These widths are measured from the two no-equipment acceptance
			// boards (不戴帽步行 / 不帶帽騎馬), then normalized to the fixed
			// runtime frame heights.  DOWN, UP, and SIDE are intentionally not
			// forced to one common width: the back views are narrower than the
			// front views in the supplied art.
			int[] footWidths = new int[] { 38, 31, 26 };
		int[] mountedWidths = new int[] { 21, 21, 41 };
			using (Bitmap footSheet = BuildSheet(onFootSource, footCrops, footWidths, false)) {
				footSheet.Save(
					System.IO.Path.Combine(outputDirectory, "reference_match_body_on_foot_unisex.png"),
					ImageFormat.Png
				);
			}
			using (Bitmap mountedSheet = BuildSheet(mountedSource, mountedCrops, mountedWidths, true)) {
				mountedSheet.Save(
					System.IO.Path.Combine(outputDirectory, "reference_match_body_mounted_unisex.png"),
					ImageFormat.Png
				);
			}
		}
	}
}
'@

Add-Type -ReferencedAssemblies "System.Drawing.dll" -TypeDefinition $builderSource
[ReferenceAssetRuntimeBuilder]::Build($onFootPath, $mountedPath, $outputDirectory)
Get-ChildItem -LiteralPath $outputDirectory -Filter "reference_match_body_*.png" |
	Select-Object FullName,Length,LastWriteTime
