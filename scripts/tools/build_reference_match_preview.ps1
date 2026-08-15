param(
	[string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path,
	[string]$OutputRelativePath = "paper_doll_preview\reference_match_final_contact_sheet.png"
)

$ErrorActionPreference = "Stop"
$sourceDirectory = Join-Path $ProjectRoot "assets\paper_doll\reference_match"
$outputPath = Join-Path $ProjectRoot $OutputRelativePath
$footPath = Join-Path $sourceDirectory "reference_match_body_on_foot_unisex.png"
$mountedPath = Join-Path $sourceDirectory "reference_match_body_mounted_unisex.png"
if (-not (Test-Path -LiteralPath $footPath -PathType Leaf)) { throw "Missing on-foot runtime sheet: $footPath" }
if (-not (Test-Path -LiteralPath $mountedPath -PathType Leaf)) { throw "Missing mounted runtime sheet: $mountedPath" }

$builder = @'
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
public static class ReferenceMatchPreview {
 public static void Build(string foot, string mounted, string output) {
  using(Bitmap a=new Bitmap(foot)) using(Bitmap b=new Bitmap(mounted)) using(Bitmap result=new Bitmap(1024,512,PixelFormat.Format32bppArgb)) {
   using(Graphics g=Graphics.FromImage(result)) {
    g.Clear(Color.FromArgb(18,24,33));
    g.InterpolationMode=InterpolationMode.NearestNeighbor;
    g.PixelOffsetMode=PixelOffsetMode.Half;
    g.DrawImage(a,new Rectangle(0,0,1024,256));
    g.DrawImage(b,new Rectangle(0,256,1024,256));
   }
   result.Save(output,ImageFormat.Png);
  }
 }
}
'@
Add-Type -ReferencedAssemblies "System.Drawing.dll" -TypeDefinition $builder
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath) | Out-Null
[ReferenceMatchPreview]::Build($footPath, $mountedPath, $outputPath)
Write-Output $outputPath
