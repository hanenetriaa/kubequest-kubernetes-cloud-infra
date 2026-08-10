# ========================================
# 1. Corriger monitoring/values.yaml (Grafana)
# ========================================
$monitoringPath = "infrastructure\base\monitoring\values.yaml"
(Get-Content $monitoringPath) -replace 'adminPassword: kubequest', "# Override with --set grafana.adminPassword=<your-password> at deploy time`n  adminPassword: `"`"" | Set-Content $monitoringPath

Write-Host "Grafana password corrige" -ForegroundColor Green

# ========================================
# 2. Corriger security/dex/values.yaml (secret OAuth)
# ========================================
$dexPath = "infrastructure\base\security\dex\values.yaml"
(Get-Content $dexPath) -replace 'secret: kubequest-oauth2-proxy-secret', "# Override with --set config.staticClients[0].secret=<your-secret> at deploy time`n      secret: `"`"" | Set-Content $dexPath

Write-Host "Dex secret corrige" -ForegroundColor Green

# ========================================
# 3. Verification finale - chercher d'autres mots de passe en clair
# ========================================
Write-Host "`n--- Verification finale ---" -ForegroundColor Cyan
Select-String -Path (Get-ChildItem -Recurse -Include *.yaml,*.yml).FullName -Pattern "password|secret|token|key" -CaseSensitive:$false | 
    Where-Object { $_.Line -notmatch '\{\{|""\s*$|:\s*$|#' } |
    Select-Object Path, LineNumber, Line
Select-String -Path (Get-ChildItem -Recurse -Include *.yaml,*.yml).FullName -Pattern "password\s*:\s*[^\s""]|secret\s*:\s*[^\s""{]|adminPassword\s*:\s*[^\s""]" -CaseSensitive:$false | 
    Where-Object { $_.Line -notmatch '\{\{|:\s*""\s*$' } |
    Select-Object -Property Path, LineNumber, Line | 
    Format-List
Write-Host "`nSi la liste ci-dessus est vide ou ne montre que des lignes commentees/vides, c'est bon." -ForegroundColor Yellow