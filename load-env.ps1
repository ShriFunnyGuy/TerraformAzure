# load-env.ps1
Get-Content .env | ForEach-Object {
    if ($_ -match "^([A-Z0-9_]+)=(.+)$") {
        $name = $matches[1]
        $value = $matches[2]
        [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
        Write-Host "Loaded: $name"
    }
}
