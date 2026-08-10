# 1. Corriger docker-compose.yaml (app)
$dockerComposePath = "app\docker-compose.yaml"
(Get-Content $dockerComposePath) `
    -replace 'DB_PASSWORD: app_password', 'DB_PASSWORD: ${DB_PASSWORD}' `
    -replace 'MYSQL_PASSWORD: app_password', 'MYSQL_PASSWORD: ${DB_PASSWORD}' `
    -replace 'MYSQL_ROOT_PASSWORD: app_root_password', 'MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}' `
    | Set-Content $dockerComposePath

Write-Host "docker-compose.yaml corrige" -ForegroundColor Green

# 2. Corriger oauth2-proxy-values.yaml
$oauthPath = "infrastructure\base\security\dex\oauth2-proxy-values.yaml"
(Get-Content $oauthPath) -replace 'clientSecret: kubequest-oauth2-proxy-secret', 'clientSecret: "" # Override with --set config.clientSecret=<your-secret> at deploy time' | Set-Content $oauthPath

Write-Host "oauth2-proxy-values.yaml corrige" -ForegroundColor Green

Write-Host "`nTermine ! N'oublie pas de creer un fichier .env.example pour documenter les variables attendues." -ForegroundColor Cyan