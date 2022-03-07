Param(
    [string]$resourceGroup,
    [int]$numberRetained=100
    )

# Remove all deployments for the resource group, retaining only the first $numberRetained.
# There is an arbitrary limit of 800 deployments for a resource group.

# Note: New Az modules available in Powershell Task version 4 (in preview at time of writing)
# $deployments = Get-AzResourceGroupDeployment -resourceGroupName $resourceGroup

$deployments = Get-AzureRmResourceGroupDeployment -resourceGroupName $resourceGroup
$numberOfDeployments = $deployments.Count 

if($numberOfDeployments -gt $numberRetained){

    $numberDeleted = $numberOfDeployments - $numberRetained
    Write-Host "$numberOfDeployments deployments found. Cleaning up $numberDeleted deployments, retaining $numberRetained"
    
    $deployments | Select-Object -Skip $numberRetained | ForEach-Object {
        $name = $_.DeploymentName
        $_ | Remove-AzureRmResourceGroupDeployment 
        # $_ | Remove-AzResourceGroupDeployment
        Write-Host "Removed deployment $name"
        
    }
}
else {
    Write-Host "$numberOfDeployments found. Nothing to clean."
}