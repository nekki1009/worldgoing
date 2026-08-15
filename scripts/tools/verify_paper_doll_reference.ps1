param(
	[string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path,
	[string]$ReferenceRelativePath = "assets\doll\reference",
	[string]$RuntimeQaRelativePath = ".visual_captures\paper_doll\qa",
	[string]$RuntimeMatchRelativePath = "assets\paper_doll\reference_match",
	[double]$RatioTolerance = 0.03,
	[double]$BottomTolerance = 0.04,
	[double]$DirectionRatioTolerance = 0.08
)

$ErrorActionPreference = "Stop"
$referenceDirectory = Join-Path $ProjectRoot $ReferenceRelativePath
$runtimeDirectory = Join-Path $ProjectRoot $RuntimeQaRelativePath
$runtimeMatchDirectory = Join-Path $ProjectRoot $RuntimeMatchRelativePath
$reportPath = Join-Path $runtimeDirectory "reference_gate_report.txt"

if (-not (Test-Path -LiteralPath $referenceDirectory -PathType Container)) {
	throw "Reference directory is missing: $referenceDirectory"
}

$metricSource = @'
using System;
using System.Collections.Generic;
using System.Drawing;
public static class PaperDollReferenceMetrics {
    private static bool IsForeground(Color color) {
        double luminance = color.R * 0.2126 + color.G * 0.7152 + color.B * 0.0722;
        int max = Math.Max(color.R, Math.Max(color.G, color.B));
        int min = Math.Min(color.R, Math.Min(color.G, color.B));
        return color.A > 12 && (luminance < 224.4 || max - min > 36);
    }

    public static string MeasureReference(string path) {
        return MeasureReferenceComponents(path);
    }

    private static string MeasureReferenceComponents(string path) {
        using (Bitmap source = new Bitmap(path)) {
            int sampleWidth = Math.Min(768, source.Width);
            int sampleHeight = Math.Max(1, (int)Math.Round((double)source.Height * sampleWidth / source.Width));
            using (Bitmap bitmap = new Bitmap(sampleWidth, sampleHeight)) {
                using (Graphics graphics = Graphics.FromImage(bitmap)) {
                    graphics.DrawImage(source, 0, 0, sampleWidth, sampleHeight);
                }
                bool[] foreground = new bool[sampleWidth * sampleHeight];
                bool[] visited = new bool[sampleWidth * sampleHeight];
                for (int y = 0; y < sampleHeight; y++) {
                    for (int x = 0; x < sampleWidth; x++) {
                        foreground[y * sampleWidth + x] = IsForeground(bitmap.GetPixel(x, y));
                    }
                }
                int[] dx = new int[] { -1, 0, 1, -1, 1, -1, 0, 1 };
                int[] dy = new int[] { -1, -1, -1, 0, 0, 1, 1, 1 };
                List<int[]> components = new List<int[]>();
                for (int y = 0; y < sampleHeight; y++) {
                    for (int x = 0; x < sampleWidth; x++) {
                        int start = y * sampleWidth + x;
                        if (!foreground[start] || visited[start]) continue;
                        Queue<Point> queue = new Queue<Point>();
                        queue.Enqueue(new Point(x, y));
                        visited[start] = true;
                        int count = 0, minX = x, minY = y, maxX = x, maxY = y;
                        while (queue.Count > 0) {
                            Point point = queue.Dequeue();
                            count++;
                            minX = Math.Min(minX, point.X); minY = Math.Min(minY, point.Y);
                            maxX = Math.Max(maxX, point.X); maxY = Math.Max(maxY, point.Y);
                            for (int i = 0; i < dx.Length; i++) {
                                int nx = point.X + dx[i], ny = point.Y + dy[i];
                                if (nx < 0 || ny < 0 || nx >= sampleWidth || ny >= sampleHeight) continue;
                                int index = ny * sampleWidth + nx;
                                if (foreground[index] && !visited[index]) {
                                    visited[index] = true;
                                    queue.Enqueue(new Point(nx, ny));
                                }
                            }
                        }
                        if (count >= 80) components.Add(new int[] { count, minX, minY, maxX, maxY });
                    }
                }
                components.Sort((left, right) => right[0].CompareTo(left[0]));
                if (components.Count < 3) return "view=0;empty=true\nview=1;empty=true\nview=2;empty=true";
                components.Sort((left, right) => left[1].CompareTo(right[1]));
                string[] rows = new string[3];
                double scaleX = (double)source.Width / sampleWidth;
                double scaleY = (double)source.Height / sampleHeight;
                for (int view = 0; view < 3; view++) {
                    int[] c = components[view];
                    int width = (int)Math.Ceiling((c[3] - c[1] + 1) * scaleX);
                    int height = (int)Math.Ceiling((c[4] - c[2] + 1) * scaleY);
                    double ratio = (double)width / Math.Max(1, height);
                    double normalizedBottom = (double)(c[4] + 1) / sampleHeight;
                    rows[view] = String.Format(
                        "view={0};empty=false;x={1};y={2};w={3};h={4};ratio={5:R};bottom={6:R}",
                        view,
                        (int)Math.Floor(c[1] * scaleX),
                        (int)Math.Floor(c[2] * scaleY),
                        width,
                        height,
                        ratio,
                        normalizedBottom
                    );
                }
                return String.Join("\n", rows);
            }
        }
    }

    public static string MeasureRuntime(string path) {
        using (Bitmap bitmap = new Bitmap(path)) {
            const int frameWidth = 64;
            const int frameHeight = 64;
            int rowCount = Math.Min(4, bitmap.Height / frameHeight);
            int columnCount = Math.Min(8, bitmap.Width / frameWidth);
            string[] rows = new string[rowCount];
            for (int row = 0; row < rowCount; row++) {
                int minX = frameWidth, minY = frameHeight, maxX = -1, maxY = -1;
                for (int column = 0; column < columnCount; column++) {
                    for (int y = 0; y < frameHeight; y++) {
                        for (int x = 0; x < frameWidth; x++) {
                            Color color = bitmap.GetPixel(column * frameWidth + x, row * frameHeight + y);
                            if (!IsForeground(color)) continue;
                            minX = Math.Min(minX, x); maxX = Math.Max(maxX, x);
                            minY = Math.Min(minY, y); maxY = Math.Max(maxY, y);
                        }
                    }
                }
                if (maxX < minX) {
                    rows[row] = String.Format("view={0};empty=true", row);
                    continue;
                }
                int width = maxX - minX + 1;
                int height = maxY - minY + 1;
                double ratio = (double)width / Math.Max(1, height);
                double normalizedBottom = (double)(maxY + 1) / frameHeight;
                rows[row] = String.Format(
                    "view={0};empty=false;x={1};y={2};w={3};h={4};ratio={5:R};bottom={6:R}",
                    row, minX, minY, width, height, ratio, normalizedBottom
                );
            }
            return String.Join("\n", rows);
        }
    }

	public static int CountHairPinholes(string path) {
		using (Bitmap bitmap = new Bitmap(path)) {
			const int frameWidth = 64;
			const int frameHeight = 64;
			int pinholes = 0;
			for (int row = 0; row < Math.Min(3, bitmap.Height / frameHeight); row++) {
				for (int column = 0; column < Math.Min(8, bitmap.Width / frameWidth); column++) {
					int originX = column * frameWidth;
					int originY = row * frameHeight;
					for (int y = 1; y < 23; y++) {
						for (int x = 1; x < frameWidth - 1; x++) {
							if (bitmap.GetPixel(originX + x, originY + y).A > 12) continue;
							bool horizontal = false;
							bool vertical = false;
							for (int distance = 1; distance <= 3; distance++) {
								if (x - distance >= 0 && x + distance < frameWidth
									&& bitmap.GetPixel(originX + x - distance, originY + y).A > 12
									&& bitmap.GetPixel(originX + x + distance, originY + y).A > 12) horizontal = true;
								if (y - distance >= 0 && y + distance < 24
									&& bitmap.GetPixel(originX + x, originY + y - distance).A > 12
									&& bitmap.GetPixel(originX + x, originY + y + distance).A > 12) vertical = true;
							}
							if (!horizontal || !vertical) continue;
							int lightNeutralNeighbours = 0;
							for (int ny = Math.Max(0, y - 2); ny <= Math.Min(23, y + 2); ny++) {
								for (int nx = Math.Max(0, x - 2); nx <= Math.Min(frameWidth - 1, x + 2); nx++) {
									Color color = bitmap.GetPixel(originX + nx, originY + ny);
									int max = Math.Max(color.R, Math.Max(color.G, color.B));
									int min = Math.Min(color.R, Math.Min(color.G, color.B));
									double luminance = color.R * 0.2126 + color.G * 0.7152 + color.B * 0.0722;
									if (color.A > 12 && max - min < 28 && luminance >= 150.0) lightNeutralNeighbours++;
								}
							}
							if (lightNeutralNeighbours >= 8) pinholes++;
						}
					}
				}
			}
			return pinholes;
		}
	}
}
'@

Add-Type -ReferencedAssemblies "System.Drawing.dll" -TypeDefinition $metricSource

function Convert-MetricLine {
	param([string]$Line)
	$metric = @{}
	foreach ($field in $Line.Split(';')) {
		$parts = $field.Split('=', 2)
		if ($parts.Count -eq 2) { $metric[$parts[0]] = $parts[1] }
	}
	if ($metric["empty"] -eq "true") { return $metric }
	foreach ($key in @("view", "x", "y", "w", "h")) { $metric[$key] = [int]$metric[$key] }
	foreach ($key in @("ratio", "bottom")) { $metric[$key] = [double]::Parse($metric[$key], [Globalization.CultureInfo]::InvariantCulture) }
	return $metric
}

function New-RangeSet {
	return @(
		[pscustomobject]@{ MinRatio = [double]::PositiveInfinity; MaxRatio = [double]::NegativeInfinity; MinBottom = [double]::PositiveInfinity; MaxBottom = [double]::NegativeInfinity },
		[pscustomobject]@{ MinRatio = [double]::PositiveInfinity; MaxRatio = [double]::NegativeInfinity; MinBottom = [double]::PositiveInfinity; MaxBottom = [double]::NegativeInfinity },
		[pscustomobject]@{ MinRatio = [double]::PositiveInfinity; MaxRatio = [double]::NegativeInfinity; MinBottom = [double]::PositiveInfinity; MaxBottom = [double]::NegativeInfinity }
	)
}

function Add-ReferenceMetric {
	param([object]$Range, [hashtable]$Metric)
	$Range.MinRatio = [Math]::Min($Range.MinRatio, $Metric["ratio"])
	$Range.MaxRatio = [Math]::Max($Range.MaxRatio, $Metric["ratio"])
	$Range.MinBottom = [Math]::Min($Range.MinBottom, $Metric["bottom"])
	$Range.MaxBottom = [Math]::Max($Range.MaxBottom, $Metric["bottom"])
}

$referenceRanges = @{
	on_foot = New-RangeSet
	mounted = New-RangeSet
}
$referenceDirectionRanges = @{
	on_foot = @(
		[pscustomobject]@{ MinRatio = [double]::PositiveInfinity; MaxRatio = [double]::NegativeInfinity },
		[pscustomobject]@{ MinRatio = [double]::PositiveInfinity; MaxRatio = [double]::NegativeInfinity },
		[pscustomobject]@{ MinRatio = [double]::PositiveInfinity; MaxRatio = [double]::NegativeInfinity }
	)
	mounted = @(
		[pscustomobject]@{ MinRatio = [double]::PositiveInfinity; MaxRatio = [double]::NegativeInfinity },
		[pscustomobject]@{ MinRatio = [double]::PositiveInfinity; MaxRatio = [double]::NegativeInfinity },
		[pscustomobject]@{ MinRatio = [double]::PositiveInfinity; MaxRatio = [double]::NegativeInfinity }
	)
}
$report = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$referenceFiles = @(Get-ChildItem -LiteralPath $referenceDirectory -Filter "*.png" -File | Sort-Object Name)
if ($referenceFiles.Count -eq 0) { $failures.Add("No PNG files found in $referenceDirectory") }

foreach ($file in $referenceFiles) {
	$metrics = @([PaperDollReferenceMetrics]::MeasureReference($file.FullName).Split("`n") | ForEach-Object { Convert-MetricLine $_ })
	if ($metrics.Count -ne 3 -or $metrics[0]["empty"] -eq "true") {
		$failures.Add("Reference does not contain three measurable views: $($file.Name)")
		continue
	}
	$mode = if ([double]$metrics[0]["ratio"] -lt 0.56) { "mounted" } else { "on_foot" }
	for ($view = 0; $view -lt 3; $view++) {
		$metric = $metrics[$view]
		if ($metric["empty"] -eq "true") {
			$failures.Add("Reference view is empty: $($file.Name) view=$view")
			continue
		}
		Add-ReferenceMetric -Range $referenceRanges[$mode][$view] -Metric $metric
		$referenceDirectionRanges[$mode][$view].MinRatio = [Math]::Min($referenceDirectionRanges[$mode][$view].MinRatio, $metric["ratio"])
		$referenceDirectionRanges[$mode][$view].MaxRatio = [Math]::Max($referenceDirectionRanges[$mode][$view].MaxRatio, $metric["ratio"])
		$report.Add("reference file=$($file.Name) mode=$mode view=$view x=$($metric['x']) y=$($metric['y']) w=$($metric['w']) h=$($metric['h']) ratio=$('{0:F3}' -f $metric['ratio']) bottom=$('{0:F3}' -f $metric['bottom'])")
	}
}

$runtimeFiles = @{
	on_foot = Join-Path $runtimeMatchDirectory "reference_match_body_on_foot_unisex.png"
	mounted = Join-Path $runtimeMatchDirectory "reference_match_body_mounted_unisex.png"
}
foreach ($mode in @("on_foot", "mounted")) {
	$path = $runtimeFiles[$mode]
	if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
		$failures.Add("Runtime contact sheet is missing: $path")
		continue
	}
	$metrics = @([PaperDollReferenceMetrics]::MeasureRuntime($path).Split("`n") | ForEach-Object { Convert-MetricLine $_ })
	$hairPinholes = [PaperDollReferenceMetrics]::CountHairPinholes($path)
	$report.Add("runtime_match mode=$mode hair_pinholes=$hairPinholes")
	if ($hairPinholes -ne 0) {
		$failures.Add("$mode contains $hairPinholes transparent pinhole(s) inside the light hair region")
	}
	$runtimeRatios = @()
	for ($view = 0; $view -lt 3; $view++) {
		$metric = $metrics[$view]
		$range = $referenceRanges[$mode][$view]
		$runtimeRatios += [double]$metric["ratio"]
		if ($metric["empty"] -eq "true") {
			$failures.Add("Runtime view is empty: mode=$mode view=$view")
			continue
		}
	$report.Add("runtime_match mode=$mode view=$view x=$($metric['x']) y=$($metric['y']) w=$($metric['w']) h=$($metric['h']) ratio=$('{0:F3}' -f $metric['ratio']) reference_ratio=[$('{0:F3}' -f $range.MinRatio),$('{0:F3}' -f $range.MaxRatio)] bottom=$('{0:F3}' -f $metric['bottom']) reference_bottom=[$('{0:F3}' -f $range.MinBottom),$('{0:F3}' -f $range.MaxBottom)]")
		if ($metric["ratio"] -lt $range.MinRatio - $RatioTolerance -or $metric["ratio"] -gt $range.MaxRatio + $RatioTolerance) {
			$failures.Add("$mode view=$view ratio $([string]::Format('{0:F3}', $metric['ratio'])) outside reference [$([string]::Format('{0:F3}', $range.MinRatio)),$([string]::Format('{0:F3}', $range.MaxRatio))]")
		}
		if ($metric["bottom"] -lt $range.MinBottom - $BottomTolerance -or $metric["bottom"] -gt $range.MaxBottom + $BottomTolerance) {
			$failures.Add("$mode view=$view bottom $([string]::Format('{0:F3}', $metric['bottom'])) outside reference [$([string]::Format('{0:F3}', $range.MinBottom)),$([string]::Format('{0:F3}', $range.MaxBottom))]")
		}
	}
	# Compare direction-to-direction proportions, not only each view against a
	# broad global range.  The reference set contains both clean silhouettes and
	# equipment variants, so derive the full possible ratio interval from the
	# independent DOWN and UP ranges.  Separately reject the concrete visual bug
	# reported by QA: a rear/UP silhouette that is materially wider than DOWN.
	$referenceDownUpMin = $referenceDirectionRanges[$mode][1].MinRatio / [Math]::Max(0.001, $referenceDirectionRanges[$mode][0].MaxRatio)
	$referenceDownUpMax = $referenceDirectionRanges[$mode][1].MaxRatio / [Math]::Max(0.001, $referenceDirectionRanges[$mode][0].MinRatio)
	$runtimeDownUp = $runtimeRatios[1] / [Math]::Max(0.001, $runtimeRatios[0])
	if ($runtimeDownUp -lt $referenceDownUpMin - $DirectionRatioTolerance -or $runtimeDownUp -gt $referenceDownUpMax + $DirectionRatioTolerance) {
		$failures.Add("$mode DOWN/UP ratio $([string]::Format('{0:F3}', $runtimeDownUp)) outside reference [$([string]::Format('{0:F3}', $referenceDownUpMin)),$([string]::Format('{0:F3}', $referenceDownUpMax))]")
	}
	if ($runtimeRatios[1] -gt $runtimeRatios[0] + 0.05) {
		$failures.Add("$mode UP is materially wider than DOWN: up=$([string]::Format('{0:F3}', $runtimeRatios[1])) down=$([string]::Format('{0:F3}', $runtimeRatios[0]))")
	}
}

$report.Add("reference_dir=$ReferenceRelativePath")
$report.Add("runtime_dir=$RuntimeQaRelativePath")
$report.Add("runtime_match_dir=$RuntimeMatchRelativePath")
$report.Add("ratio_tolerance=$RatioTolerance bottom_tolerance=$BottomTolerance direction_ratio_tolerance=$DirectionRatioTolerance")
$report.Add("result=" + ($(if ($failures.Count -eq 0) { "PASS" } else { "FAIL" })))
foreach ($failure in $failures) { $report.Add("failure=$failure") }
New-Item -ItemType Directory -Force -Path $runtimeDirectory | Out-Null
[System.IO.File]::WriteAllLines($reportPath, $report, [System.Text.UTF8Encoding]::new($true))

if ($failures.Count -eq 0) {
	Write-Output "PAPER DOLL REFERENCE QA PASS"
	exit 0
}
Write-Output "PAPER DOLL REFERENCE QA FAIL ($($failures.Count) issue(s))"
$failures | ForEach-Object { Write-Output "FAIL: $_" }
Write-Output "REPORT: $reportPath"
exit 1
