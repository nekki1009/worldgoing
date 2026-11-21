# Read-only fixtures; evaluate only the pure guard definition, never the publisher.
$ErrorActionPreference = 'Stop'
$testProject = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$testTask = Join-Path $testProject 'output/steel_mingguang_walk_20260919'
$publisherPath = Join-Path $PSScriptRoot 'publish_equipment_walk_models.ps1'
$testResultPath = Join-Path $testTask ('atlas/publication_guard_self_test_' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ') + '.json')
$testResult = [ordered]@{ status='FAIL'; publisher_executed=$false; godot_started=$false; positive=@(); negative=@() }

function Assert-GuardTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Read-ProtectedHashes {
    $values = @{}
    foreach ($sex in @('male','female')) {
        foreach ($ext in @('.blend','.glb','.json')) {
            $file = Join-Path $testProject "assets/characters/human/q35/standard_anime_${sex}_character_pack$ext"
            $values[$file] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        }
    }
    foreach ($name in @('model_publication_v5.json','atlas/publication.json')) {
        $file = Join-Path $testTask $name
        $values[$file] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
    return $values
}

try {
    $protectedBefore = Read-ProtectedHashes
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($publisherPath, [ref]$tokens, [ref]$parseErrors)
    Assert-GuardTest ($parseErrors.Count -eq 0) 'Publisher parse failed'
    $functions = @($ast.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-SteelMingguangCaptureBinding'
    }, $true))
    Assert-GuardTest ($functions.Count -eq 1) 'Exactly one production guard required'
    $guardText = $functions[0].Extent.Text
    $source = (Get-Content -LiteralPath $publisherPath -Raw).Replace("`r`n", "`n")
    $oldSource = (Get-Content -LiteralPath (Join-Path $testTask 'atlas/publication_guard_20260924_before.ps1.txt') -Raw).Replace("`r`n", "`n")
    $callLine = "        Assert-SteelMingguangCaptureBinding `$run `$capture `$sex `$Revision `$projectDir `$report.candidate_sha256['.glb']`n"
    Assert-GuardTest ($source.Contains("    if (`$SteelMingguang) {`n" + $callLine)) 'Guard is not inside SteelMingguang scope'
    $unchanged = $source.Replace($guardText.Replace("`r`n", "`n") + "`n`n", '').Replace($callLine, '')
    Assert-GuardTest ($unchanged -ceq $oldSource) 'An unrelated legacy publisher statement changed'
    $testResult.legacy_source_unchanged_except_scoped_guard = $true
    $testResult.publisher_sha256 = (Get-FileHash -LiteralPath $publisherPath -Algorithm SHA256).Hash
    # This evaluates only a function declaration extracted by the parser.
    . ([scriptblock]::Create($guardText))
    $publication = Get-Content -LiteralPath (Join-Path $testTask 'model_publication_v5.json') -Raw | ConvertFrom-Json
    foreach ($sex in @('male','female')) {
        $runPath = Join-Path $testTask ('verification/' + $publication.native_runs.$sex + '/result.json')
        $capturePath = Join-Path $testTask "candidate_v5/$sex/result.json"
        $build = Get-Content -LiteralPath (Join-Path $testTask "combined/v5/$sex/build.json") -Raw | ConvertFrom-Json -AsHashtable
        $runJson = Get-Content -LiteralPath $runPath -Raw
        $captureJson = Get-Content -LiteralPath $capturePath -Raw
        $run = $runJson | ConvertFrom-Json
        $capture = $captureJson | ConvertFrom-Json
        Assert-SteelMingguangCaptureBinding $run $capture $sex 'v5' $testProject $build.candidate_sha256['.glb']
        $testResult.positive += @{sex=$sex;run=$publication.native_runs.$sex;candidate_sha256=$capture.candidate_sha256;accepted=$true}
        foreach ($case in @('mode','project','script','revision','sex','candidate_revision','candidate_sex',
                            'missing_scope_flag','extra_candidate','capture_sex','capture_path','capture_sha','empty_sha')) {
            $badRun = $runJson | ConvertFrom-Json
            $badCapture = $captureJson | ConvertFrom-Json
            switch ($case) {
                'mode' { $badRun.mode = 'headless' }
                'project' { $badRun.arguments[1] = 'C:\unrelated-project' }
                'script' { $badRun.arguments[3] = 'res://scripts/tests/unrelated_test.gd' }
                'revision' { $badRun.arguments[5] = 'candidate_v4' }
                'sex' { $badRun.arguments[6] = $(if ($sex -eq 'male') {'female'} else {'male'}) }
                'candidate_revision' { $badRun.arguments[9] = $badRun.arguments[9].Replace('/v5/', '/v4/') }
                'candidate_sex' { $badRun.arguments[9] = $badRun.arguments[9].Replace("/$sex/", '/other/') }
                'missing_scope_flag' { $badRun.arguments[7] = '--unrelated-batch' }
                'extra_candidate' { $badRun.arguments += '--candidate=res://different.glb' }
                'capture_sex' { $badCapture.sex = 'other' }
                'capture_path' { $badCapture.candidate_path = $badCapture.candidate_path.Replace('/v5/', '/v4/') }
                'capture_sha' { $badCapture.candidate_sha256 = '0' * 64 }
                'empty_sha' { $badCapture.candidate_sha256 = '' }
            }
            $rejection = ''
            try { Assert-SteelMingguangCaptureBinding $badRun $badCapture $sex 'v5' $testProject $build.candidate_sha256['.glb'] }
            catch { $rejection = $_.Exception.Message }
            Assert-GuardTest ($rejection.StartsWith('Steel ')) "Counterexample not rejected by intended guard: $sex/$case"
            $testResult.negative += @{sex=$sex;case=$case;rejected=$true;reason=$rejection}
        }
    }
    $protectedAfter = Read-ProtectedHashes
    foreach ($file in $protectedBefore.Keys) {
        Assert-GuardTest ($protectedBefore[$file] -eq $protectedAfter[$file]) ('Protected data changed: ' + $file)
    }
    $testResult.protected_files_unchanged_sha256 = $protectedAfter
    Assert-GuardTest ($testResult.positive.Count -eq 2 -and $testResult.negative.Count -eq 26) 'Fixture coverage differs'
    $testResult.status = 'PASS'
} catch {
    $testResult.error = $_.Exception.Message
} finally {
    $content = $testResult | ConvertTo-Json -Depth 8
    $stream = [IO.File]::Open($testResultPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($content)
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
    Write-Output "STEEL_PUBLICATION_GUARD_TEST=$($testResult.status) POSITIVE=$($testResult.positive.Count) NEGATIVE=$($testResult.negative.Count) EVIDENCE=$testResultPath"
}
if ($testResult.status -ne 'PASS') { throw $testResult.error }
