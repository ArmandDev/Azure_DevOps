param(
   [string][parameter(Mandatory = $false)] $keyVaultName = "#{Infra.Secrets.KeyVault.Name}#",
   [string][parameter(Mandatory = $false)] $outputVariableName = "Infra.KeyVault.AccessPolicies"
)


$keyVaultAccessPolicies = (Get-AzureRMKeyVault -VaultName $keyVaultName).accessPolicies

$armAccessPolicies = @()

if($keyVaultAccessPolicies)
{
   Write-Host "Key Vault '$keyVaultName' is found."

   foreach($keyVaultAccessPolicy in $keyVaultAccessPolicies)
   {
      $armAccessPolicy = [pscustomobject]@{
         tenantId = $keyVaultAccessPolicy.TenantId
         objectId = $keyVaultAccessPolicy.ObjectId
      }

      $armAccessPolicyPermissions = [pscustomobject]@{
         keys =  $keyVaultAccessPolicy.PermissionsToKeys
         secrets = $keyVaultAccessPolicy.PermissionsToSecrets
         certificates = $keyVaultAccessPolicy.PermissionsToCertificates
         storage = $keyVaultAccessPolicy.PermissionsToStorage
      }

      $armAccessPolicy | Add-Member -MemberType NoteProperty -Name permissions -Value $armAccessPolicyPermissions

      $armAccessPolicies += $armAccessPolicy
   }   
}

$armAccessPoliciesParameter = [pscustomobject]@{
    list = $armAccessPolicies
} 

$armAccessPoliciesParameter = $armAccessPoliciesParameter | ConvertTo-Json -Depth 5 -Compress

Write-Host "Current access policies: $armAccessPoliciesParameter"

Write-Host ("##vso[task.setvariable variable=$outputVariableName;]$armAccessPoliciesParameter")


