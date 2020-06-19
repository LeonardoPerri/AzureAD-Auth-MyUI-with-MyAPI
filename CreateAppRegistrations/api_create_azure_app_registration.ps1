Param( [string]$tenantId = "" )
$displayName = "mi-api"
$userAccessScope = '{
		"lang": null,
		"origin": "Application",		
		"adminConsentDescription": "Allow access to the API",
		"adminConsentDisplayName": "mi-api-access",
		"id": "--- replaced in scripts ---",
		"isEnabled": true,
		"type": "User",
		"userConsentDescription": "Allow access to mi-api access_as_user",
		"userConsentDisplayName": "Allow access to mi-api",
		"value": "access_as_user"
}' | ConvertTo-Json | ConvertFrom-Json

##################################
### testParams
##################################

function testParams {

	if (!$tenantId) 
	{ 
		Write-Host "tenantId is null"
		exit 1
	}
}

testParams

Write-Host "Begin API Azure App Registration"

##################################
### Create Azure App Registration
##################################

$identifier = New-Guid
$identifierUrl = "api://" + $identifier 
$myApiAppRegistration = az ad app create `
	--display-name $displayName `
	--available-to-other-tenants true `
	--oauth2-allow-implicit-flow  false `
	--identifier-uris $identifierUrl `
	--required-resource-accesses `@api_required_resources.json 

$data = ($myApiAppRegistration | ConvertFrom-Json)
$appId = $data.appId
Write-Host " - Created API $displayName with appId: $appId"

##################################
### Add optional claims to App Registration 
##################################

az ad app update --id $appId --optional-claims `@api_optional_claims.json
Write-Host " - Optional claims added to App Registration: $appId"

##################################
###  Add scopes (oauth2Permissions)
##################################

# 1. read oauth2Permissions
$apiApp = az ad app show --id $appId | Out-String | ConvertFrom-Json
$oauth2Permissions = $apiApp.oauth2Permissions

# 2. set to enabled to false from the defualt scope, because we want to remove this
$oauth2Permissions[0].isEnabled = 'false'
$oauth2Permissions = ConvertTo-Json -InputObject @($oauth2Permissions) 
# Write-Host "$oauth2Permissions" 
# disable oauth2Permission in Azure App Registration
$oauth2Permissions | Out-File -FilePath .\oauth2Permissionsold.json
az ad app update --id $appId --set oauth2Permissions=`@oauth2Permissionsold.json

# 3. delete the default oauth2Permission
az ad app update --id $appId --set oauth2Permissions='[]'

# 4. add the new scope required add the new oauth2Permissions values
$oauth2PermissionsNew += (ConvertFrom-Json -InputObject $userAccessScope)
$oauth2PermissionsNew[0].id = $identifier 
$oauth2PermissionsNew = ConvertTo-Json -InputObject @($oauth2PermissionsNew) 
# Write-Host "$oauth2PermissionsNew" 
$oauth2PermissionsNew | Out-File -FilePath .\oauth2Permissionsnew.json
az ad app update --id $appId --set oauth2Permissions=`@oauth2Permissionsnew.json
Write-Host " - Updated scopes (oauth2Permissions) for App Registration: $appId"

##################################
###  Create a ServicePrincipal for the API App Registration
##################################

az ad sp create --id $appId | Out-String | ConvertFrom-Json
Write-Host " - Created Service Principal for API App registration"

##################################
### Set signInAudience to AzureADandPersonalMicrosoftAccount
##################################

# https://docs.microsoft.com/en-us/graph/api/application-update
$idAppForGraphApi = $apiApp.objectId
#Write-Host " - id = apiApp.objectId: $idAppForGraphApi"
$tokenResponse = az account get-access-token --resource https://graph.microsoft.com
$token = ($tokenResponse | ConvertFrom-Json).accessToken
#Write-Host "$token"
$uri = 'https://graph.microsoft.com/v1.0/applications/' + $idAppForGraphApi
Write-Host " - $uri"
$headers = @{
    "Authorization" = "Bearer $token"
}

Invoke-RestMethod -ContentType application/json -Uri $uri -Method Patch -Headers $headers -Body '{"signInAudience" : "AzureADandPersonalMicrosoftAccount", "groupMembershipClaims": "None"}'
Write-Host " - Updated signInAudience to AzureADandPersonalMicrosoftAccount"


return $appId