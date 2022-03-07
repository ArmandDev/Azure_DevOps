#Single Powershell script to deploy artifacts in Integration account using REST API
#       \IntegrationAccount\Schemas\Common 				Common schemas that need to be deployed first (dependencies)
#       \IntegrationAccount\Schemas						Default schema directory
#       \IntegrationAccount\Maps\Xslt					Xslt maps
#       \IntegrationAccount\Maps\Liquid					Liquid maps
#       \IntegrationAccount\Partners					EDI Partners
#       \IntegrationAccount\Agreements					EDI Agreements
#       \IntegrationAccount\Certificates				Public certificates
#
#		!! Certificate, Agreement and Partner filenames should end with the environment shortname where the certificate should be deployed. eg. "Coditio-tst.cer"
#
# Check the Cloud Integration Methodology document for more information
#
# REMARK:	When using this script in your release pipeline, set the Azure Powershell version to 2.1.0. Later versions cause the script to fail.
#			Check this issue for updates: https://github.com/Azure/azure-powershell/issues/6261

#
# Parameters:
#	$artifactsPrefix: 
#	provide the prefix to be assigned to the names of all artifacts before uploading/creating - used to define the environment-name in case of shared useage in non-prod environments
#
#	$ExcludeSchemaFileExtensions:
#	In case of using nested xsd schemas, the extensions should not be added to the uploaded schema.
#	This parameter has been added to ensure the script remains backwards compatible.

param(
	[Parameter(Mandatory=$false)][string]$artifactsPrefix = "",
	[Parameter(Mandatory=$false)][bool]$ExcludeSchemaFileExtensions = $false
)

$integrationAccount = Get-AzureRmResource -ResourceId "#{Infra.Integration.IntegrationAccount.Id}#"
$resourceGroup = $integrationAccount.ResourceGroupName

$environment = "#{Infra.Environment.ShortName}#"
$keyvaultid = "#{Infra.Secrets.KeyVault.Id}#"
$keyvaultname = "#{Infra.Secrets.KeyVault.Name}#"

#Storage Account details
$storageAccountResource = Get-AzureRmResource -ResourceId "#{Infra.StorageAccount.Id}#"
$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $storageAccountResource.ResourceGroupName -Name $storageAccountResource.Name
$storageContainerName = "#{Infra.StorageAccount.DeployContainer.Name}#"

Write-Host "Current environment: $($environment)"

#Uri

$baseUri = "https://management.azure.com"
$suffixUri = "?api-version=2016-06-01"
$integrationAccountUri = "#{Infra.Integration.IntegrationAccount.Id}#"

$Global:acces_token = "";
$Global:subscriptionId = "";

function Get-AzureRmCachedAccessToken()
{
    # Script found here: https://gallery.technet.microsoft.com/scriptcenter/Easily-obtain-AccessToken-3ba6e593
    $ErrorActionPreference = 'Stop'
  
    if(-not (Get-Module AzureRm.Profile)) {
        Import-Module AzureRm.Profile
    }
    $azureRmProfileModuleVersion = (Get-Module AzureRm.Profile).Version
    # refactoring performed in AzureRm.Profile v3.0 or later
    if($azureRmProfileModuleVersion.Major -ge 3) {
        $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
        if(-not $azureRmProfile.Accounts.Count) {
            Write-Error "Ensure you have logged in before calling this function."    
        }
    } else {
        # AzureRm.Profile < v3.0
        $azureRmProfile = [Microsoft.WindowsAzure.Commands.Common.AzureRmProfileProvider]::Instance.Profile
        if(-not $azureRmProfile.Context.Account.Count) {
            Write-Error "Ensure you have logged in before calling this function."    
        }
    }
  
    $currentAzureContext = Get-AzureRmContext
    $Global:subscriptionId = $currentAzureContext.Subscription.Id
    Write-Debug ("AzureRmContext scoped to subscriptionId: " + $currentAzureContext.Subscription.Id)
    $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile)
    Write-Debug ("Getting access token for tenant: " + $currentAzureContext.Tenant.TenantId)
    $token = $profileClient.AcquireAccessToken($currentAzureContext.Tenant.TenantId)
    $Global:acces_token = $token.AccessToken

    Write-Host "Access-token and subscriptionId retrieved"

}

#Code to deploy all schemas present in the schemas folder as per Solution Structure 
function DeploySchemas()
{
	Param ([string]$targetFolderPath)

	foreach($schema in Get-ChildItem ("$targetFolderPath") -File)
	{
		#Read schema name
		$schemaName = $schema.Name
		if($ExcludeSchemaFileExtensions)
		{
			$schemaName = $schema.BaseName
		}
		Write-Host "Creating schema in Integration Account with name: " $schemaName
		
		#temp upload the xsd to blob storage (also large file support).
        $blobUri = (Set-AzureStorageBlobContent -File $schema.FullName -Container $storageContainerName -Blob $schemaName -Context $storageAccount.Context -Force).ICloudBlob.uri.AbsoluteUri
        Write-Host "Uploaded the XSD to temporary location in Blob Storage: " $($blobUri)

		$uri = $baseUri + $integrationAccountUri + "/schemas/$($artifactsPrefix)$($schemaName)" + $suffixUri
	    Write-Host "Creating/Updating the schema using URL: $($uri)"

        $jsonRequest = @{
            properties= @{
                schemaType = 'Xml'
                metadata= @{}
                contentType = 'application/xml'
                contentLink= @{
                    uri= $blobUri
                }
            }
        } | ConvertTo-Json

		InvokeRequest -uri $uri -jsonRequest $jsonRequest
		
        Remove-AzureStorageBlob -Container $storageContainerName -Blob $schemaName -Context $storageAccount.Context
        Write-Host "Removed XSD from temporary location in Blob Storage: "$($blobUri)
	}
}
#Code to deploy all maps present in the maps folder as per Solution Structure 
function DeployMaps()
{
	Param ([string]$targetFolderPath)
	
	foreach($map in Get-ChildItem ("$targetFolderPath") -File)
	{
		#Read map name
		$name = $map.FullName
		
		$uri = $baseUri + $integrationAccountUri + "/maps/$($artifactsPrefix)$($map.Name)" + $suffixUri
	    Write-Host "Creating/Updating the xslt using URL: $($uri)"
       
		#Read map
		$mapXML = Get-Content -Raw -Path $map.FullName
		
		$jsonRequest = @{
            properties= @{
               mapType = 'Xslt'
               metadata= @{}
               contentType = 'application/xml'
               content= $mapXML.ToString().Replace('"', '\"') 
            }
        } | ConvertTo-Json  | % { [System.Text.RegularExpressions.Regex]::Unescape($_) } 
		
		InvokeRequest -uri $uri -jsonRequest $jsonRequest -name $name
	}
}

#Code to deploy all partner present in the partners folder as per Solution Structure 
function DeployPartners()
{
	Param ([string]$targetFolderPath)
	
	foreach($partner in Get-ChildItem ("$targetFolderPath") -File)
	{
		#Read partner content as object
		$name = Get-Content -Raw -Path $partner.FullName | ConvertFrom-Json
		
		#Read partner content as json
		$jsonRequest = Get-Content -Raw -Path $partner.FullName
		
		$uri = $baseUri + $integrationAccountUri + "/partners/$($artifactsPrefix)$($name.name)" + $suffixUri
	    Write-Host "Creating/Updating the Partner using URL: $($uri)"

		InvokeRequest -uri $uri -jsonRequest $jsonRequest -name $name
	}
}

#Code to deploy all agreements present in the agreements folder as per Solution Structure 
function DeployAgreements()
{
	Param ([string]$targetFolderPath)

	foreach($agreement in Get-ChildItem ("$targetFolderPath") -File)
	{
		#Read agreement content as object
		$name = Get-Content -Raw -Path $agreement.FullName | ConvertFrom-Json
		
		#Read agreement content as json
		$jsonRequest = Get-Content -Raw -Path $agreement.FullName
		
		$uri = $baseUri + $integrationAccountUri + "/agreements/$($artifactsPrefix)$($name.name)" + $suffixUri
	    Write-Host "Creating/Updating the agreement using URL: $($uri)"

		InvokeRequest -uri $uri -jsonRequest $jsonRequest -name $name
	}
}

#Code to deploy all certificates present in the certificates folder as per Solution Structure 
function DeployCertificates()
{
	Param ([string]$targetFolderPath)
	
	foreach($certificate in Get-ChildItem ("$targetFolderPath") -File)
	{
		#Read certificate name
		$name = $certificate.FullName
		
		$cert = Get-Content -path $certificate.FullName -Encoding Byte
		
		$uri = $baseUri + $integrationAccountUri + "/certificates/$($artifactsPrefix)$($certificate.Name)" + $suffixUri
	    Write-Host "Creating/Updating the certificate using URL: $($uri)"	
		
		
		$hashPubCert = ([System.Convert]::ToBase64String($cert))

        $jsonRequest = @{
						properties = @{
									publicCertificate = $hashPubCert
									}
						}  | ConvertTo-Json -Depth 3
		
		InvokeRequest -uri $uri -jsonRequest $jsonRequest -name $name
	}
}

#Code to deploy all assemblies present in the assemblies folder as per Solution Structure 
function DeployAssemblies()
{
	Param ([string]$targetFolderPath)
		
	Write-host "Assemblies deployment"
	
	foreach($assembly in Get-ChildItem ("$targetFolderPath") -File)
	{
		#Read assembly name
		$name = $assembly.FullName
		$baseName = (Get-Item $assembly).Basename	
		
		#temp upload the .dll to blob storage (also large file support)
        $blobUri = (Set-AzureStorageBlobContent -File $assembly.FullName -Container $storageContainerName -Blob $assembly.Name -Context $storageAccount.Context -Force).ICloudBlob.uri.AbsoluteUri		
        Write-Host "Uploaded the assembly to temporary location in Blob Storage: " $($blobUri)

		$uri = $baseUri + $integrationAccountUri + "/assemblies/$($artifactsPrefix)$($assembly.Name)" + $suffixUri
	    Write-Host "Creating/Updating the assembly using URL: $($uri)"	
		
        $jsonRequest = @{
						properties = @{
										assemblyName= $baseName
										contentType= 'application/octet-stream'
										contentLink= @{
											uri = $blobUri
											}
										metadata= @{}
									}
								location = 'westeurpoe'
						} | ConvertTo-Json -Depth 3
		
		InvokeRequest -uri $uri -jsonRequest $jsonRequest -name $name

        Remove-AzureStorageBlob -Container $storageContainerName -Blob $assembly.Name -Context $storageAccount.Context
        Write-Host "Removed assembly from temporary location in Blob Storage: "$($blobUri)
	}
}
#Code to Invoke Web Request
function InvokeRequest()
{
		Param ($uri,$jsonRequest,$name)
		
		$params = @{
			ContentType ='application/json'
			Headers = @{ 
				'authorization'="Bearer $global:acces_token"
			}
			Body = $jsonRequest
			Method = 'Put'
			URI = $uri
		}
		
		Write-Host "Invoke Function Called"
		try
		{
			$duration = 60
			$response = Invoke-WebRequest @params

			if($response.StatusCode -eq 200)
			{
			    Write-Host "'$($name)' was created/updated: " $response.StatusCode $response.StatusDescription
			}
			else
			{
				while ($response.StatusCode -ne 200 -And $duration -gt 0)
				{
					$duration--
					Start-Sleep -s 1;
					$response = Invoke-WebRequest @params;
					Write-Host ("...Response code = " + $response.StatusCode + " ...Content Length " + $response.RawContentLength);
				}
			}
		}
		catch [Exception]
		{
			Write-Host "Failed to create or update the '$($name)': $_.Exception.Message"
			Write-Error $_.Exception.Message | format-list
		}


}
Get-AzureRmCachedAccessToken;

#Deploy Common schemas first
try
{
	$TargetDir = "$env:SYSTEM_DefaultWorkingDirectory\*\*\*\Schemas"
	Write-Host "##Common Schemas"
	if(Test-Path -Path $TargetDir)
	{
		DeploySchemas -targetFolderPath "$TargetDir\*"
	}
	else{
		Write-Host "No common schemas were deployed because build artifacts directory doesn't contain folder: $TargetDir"
	}
}
catch{
	Write-Error $_.Exception.Message | format-list
}

#Deploy schemas
try
{
	$TargetDir = "$env:SYSTEM_ARTIFACTSDIRECTORY\*\*\*\IntegrationAccount\Schemas"
	Write-Host "##Schemas" 
	if(Test-Path -Path $TargetDir)
	{
		DeploySchemas -targetFolderPath "$TargetDir\*"
	}
	else{
		Write-Host "No schemas were deployed because build artifacts directory doesn't contain folder: $TargetDir"
	}
}
catch{
	Write-Error $_.Exception.Message | format-list
}

#Deploy Xslt maps
try
{
	$TargetDir = "$env:SYSTEM_ARTIFACTSDIRECTORY\*\*\*\IntegrationAccount\Maps"
	Write-Host "##Xslt Maps" 
	if(Test-Path -Path $TargetDir)
	{
		DeployMaps -targetFolderPath "$TargetDir\*" -mapType "Xslt"
	}
	else{
		Write-Host "No XSLT maps were deployed because build artifacts directory doesn't contain folder: $TargetDir"
	}
}
catch{
	Write-Error $_.Exception | format-list
}

#Deploy Partners
try
{
	$TargetDir = "$env:SYSTEM_ARTIFACTSDIRECTORY\*\*\*\IntegrationAccount\Partners"
	Write-Host "##B2B Partners" 
	if(Test-Path -Path $TargetDir)
	{
		DeployPartners -targetFolderPath "$TargetDir\*.json"
	}
	else{
		Write-Host "No B2B partners were deployed because build artifacts directory doesn't contain folder: $TargetDir"
	}
}
catch{
	Write-Error $_.Exception.Message | format-list
}


#Deploy Agreements
try
{
	$TargetDir = "$env:SYSTEM_ARTIFACTSDIRECTORY\*\*\*\IntegrationAccount\Agreements"
	Write-Host "##B2B Agreements" 
	if(Test-Path -Path $TargetDir)
	{
		DeployAgreements -targetFolderPath "$TargetDir\*.json"
	}
	else{
		Write-Host "No B2B agreements were deployed because build artifacts directory doesn't contain folder: $TargetDir"
	}
}
catch{
	Write-Error $_.Exception.Message | format-list
}

#Deploy Certificates
try
{
	$TargetDir = "$env:SYSTEM_ARTIFACTSDIRECTORY\*\*\*\IntegrationAccount\Certificates"
	Write-Host "##B2B Certificates" 
	if(Test-Path -Path $TargetDir)
	{
		DeployCertificates -targetFolderPath "$TargetDir\*-$environment.cer"
	}
	else{
		Write-Host "No B2B certificates were deployed because build artifacts directory doesn't contain folder: $TargetDir"
	}
}
catch{
	Write-Error $_.Exception.Message | format-list
}

#Deploy Assemblies
try
{
	$TargetDir = "$env:SYSTEM_ARTIFACTSDIRECTORY\*\*\*\IntegrationAccount\Assemblies"
	Write-Host "##B2B Assemblies" 
	if(Test-Path -Path $TargetDir)
	{
		DeployAssemblies -targetFolderPath "$TargetDir\*.dll"
	}
	else{
		Write-Host "No B2B assemblies were deployed because build artifacts directory doesn't contain folder: $TargetDir"
	}
}
catch{
	Write-Error $_.Exception.Message | format-list
}

