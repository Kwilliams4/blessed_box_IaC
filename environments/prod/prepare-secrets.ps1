param(
  [string]$Region = "us-east-2",
  [string]$JwtSecretParameterName = "/blessedbox/prod/app/JWT_SECRET",
  [string]$JwtRefreshSecretParameterName = "/blessedbox/prod/app/JWT_REFRESH_SECRET"
)

$ErrorActionPreference = "Stop"

function Ensure-SecureParameter {
  param(
    [string]$Name
  )

  $null = aws ssm get-parameter `
    --region $Region `
    --name $Name `
    --query "Parameter.Name" `
    --output text 2>$null

  if ($LASTEXITCODE -eq 0) {
    Write-Output "$Name already exists; leaving it unchanged."
    return
  }

  $bytes = New-Object byte[] 64
  $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $random.GetBytes($bytes)
  }
  finally {
    $random.Dispose()
  }

  $value = [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
  $null = aws ssm put-parameter `
    --region $Region `
    --name $Name `
    --type SecureString `
    --value $value `
    --no-cli-pager

  if ($LASTEXITCODE -ne 0) {
    throw "Failed to create SSM SecureString parameter $Name."
  }

  Write-Output "$Name created as a SecureString."
}

Ensure-SecureParameter -Name $JwtSecretParameterName
Ensure-SecureParameter -Name $JwtRefreshSecretParameterName
