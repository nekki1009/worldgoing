param([string]$Project)
# Rename the copied Godot project so its user:// folder is separate from the original game.
$text = [IO.File]::ReadAllText($Project)
$new = $text.Replace('config/name="worldgoing"', 'config/name="worldgoing_crowd10k_test"')
if ($new -eq $text) {
	Write-Host "config/name=""worldgoing"" not found in $Project"
	exit 3
}
[IO.File]::WriteAllText($Project, $new, (New-Object Text.UTF8Encoding($false)))
Write-Host "Renamed the project to worldgoing_crowd10k_test"
exit 0
