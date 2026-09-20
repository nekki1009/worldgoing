# Inspection-only layout of unmodified Godot captures, never an art source.
param([string]$Suffix = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$captureRoot = Join-Path $PSScriptRoot '../../output/equipment_matrix_20260918/mounted'
$font = [System.Drawing.Font]::new('Arial', 16)
foreach ($sex in @('male', 'female')) {
    foreach ($weapon in @('longsword_01', 'spear_01', 'axe_01', 'bow_01', 'crossbow_01')) {
        $sheet = [System.Drawing.Bitmap]::new(2048, 1088)
        $draw = [System.Drawing.Graphics]::FromImage($sheet)
        $draw.Clear([System.Drawing.Color]::FromArgb(35, 38, 47))
        $index = 0
        foreach ($frame in @('000', '025', '042', '053', '063', '078', '100')) {
            $source = [System.Drawing.Image]::FromFile((Join-Path $captureRoot "${sex}_ride_heavy_${weapon}_${frame}${Suffix}.png"))
            $x = ($index % 4) * 512
            $y = [Math]::Floor($index / 4) * 544
            $draw.DrawImage($source, [int]$x, [int]($y + 32), 512, 512)
            $draw.DrawString("$sex $weapon $frame%", $font, [System.Drawing.Brushes]::White, $x + 8, $y + 4)
            $source.Dispose()
            $index++
        }
        $sheet.Save((Join-Path $captureRoot "sheet_${sex}_${weapon}${Suffix}.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $draw.Dispose()
        $sheet.Dispose()
    }
}
$font.Dispose()
