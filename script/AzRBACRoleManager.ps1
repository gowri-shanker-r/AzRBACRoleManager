
<#

.SYNOPSYS

    Script helps assign or remove an RBAC role assignment to a user/group/service principal using a MS excel sheet as input (in specific format)


.DESCRIPTION

    This script has been designed to help Azure IAM Admin to assign and revoke Azure RBAC permission on Azure resources. The 
    script takes as input an xlsx spreadsheet which contains the RBAC details including 
        
        - Level at which the RBAC role should be assigned or removed (Subscription-level / ResourceGroup-level / Resource-level)
        - Subscription Name
        - Resource Group Name
        - Resource Name
        - Role Name
        - Object Name ((User Principal name / Group Display name / Service Principal Display name)
        - Object Type (User/Group/ServicePrincipal)
        - Whether the role needs to be assigned or removed (Add / Remove)
    
    The xlsx spreadsheet is expected to be in a specific format with some fields expected to have only a list of values. The script 
    will expect the user to login for connecting to Azure account and running Az cmdlets.

    The script will note the status in the same excel under the status field against each RBAC request entry. The status field will 
    either have the value Success which means RBAC assignment/removal completed or an error message indicating which of the input 
    fields had a problem

    I do acknowledge that this can be further optimized (future versions) and also that there will be better ways to do this as well :-)


.PARAMETERS

    rbacFile - Provide the full path of the template xlsx spreadsheet file
    tenantId - the GUID representing the Azure AD tenant against which this script has to be executed


.INPUTS

    1. File path of xlsx spreadsheet that contains RBAC details to be assigned or removed in a sepcific format
    2. Azure TenantId of the Azure Tenant under which the RBAC assignment/removal needs to be performed

  
.OUTPUTs

    1. Input xlsx spreadsheet is updated with status of each RBAC assignment or removal
    

.Author & Version History

    Script Author: Gowri Shanker Raghuraman
    
    Version: 1.0
    Creation Date: 12-Nov-2021
    Details: RBAC management script
    Change Author: Gowri Shanker Raghuraman


.LIMITATIONS / KNOWN ISSUES

    1. Script only works when provided with AD Group Display Name, Service Principal Display Name and User Principal Name (including domain name; refer to your Azure Active Directory)
    2. Exception andling is not implemented thoroughly so error messages may not be very friendly in some cases
    3. Hardwired to the excel template. Deviations in excel template will give unexpected results.
    4. When assigning an RBAC role, if it is already assigned at that scope, script doesnt skip it. It will execute assignment statement but fail and print a message noting the existence of RBAC role assignment.
    5. When assigning an RBAC role, if the parent scope already has the same role, the script will not skip and end up assigning the role at requested scope as well
    6. When removing an RBAC role, if it is not asigned, script doesnt skip it. It will go through and print a message on console. This error message is not user friendly and need revision
    7. If RG or resource has a Delete lock, removing RBAC role will fail. Script is not capable of removing the lock. This has to be done as a pre-req.
    8. Script is relatively slow in assigning/revoking role assignments as several cmdlets are executed for each entry in the excel. Performance optimization needs to be done as part of a revision
    9. There is no support for Nested Resource level role assignment and removal (Ex. RBAC assignment/removal on a Subnet inside a VNet). This need a revision


.PRE-REQUISITES

    1. Ensure Az and ImportExcel modules are installed on your local machine. If not run the following cmdlets
    
        Install-Module Az -Scope CurrentUser
        Install-Module ImportExcel -Scope CurrentUser

    Note: Using the CurrentUser scope will install the modules in your profile so you will not need Admin rights to install them

    2. The user account used to login should have Owner / User Access Administrator RBAC role assigned on the Subscription
    3. For RBAC removal, ensure no delete lock exists on resource and resource groups

.USAGE

    AzRBACRoleManager.ps1 -rbacFile <RBAC_xlsx_file_path> -tenantId <AAD_Tenant_ID>

#>


#-------------------------------------------------- [Params and Declarations] --------------------------------------------------#

param ([Parameter(Mandatory)]$rbacFile, [Parameter(Mandatory)]$tenantId)


#-------------------------------------------------- [Functions Start] --------------------------------------------------#

Function ValidateInstalledModules ()
{
    Try 
    {
        $module = Get-InstalledModule -Name "Az" -ErrorAction Stop;
        $module = Get-InstalledModule -Name "ImportExcel" -ErrorAction Stop;
    }
    Catch 
    {
        throw 'Required Modules not installed. Please install Az and ImportExcel modules and try again';
    }
}

Function CleanupInput ($inputString)
{
    if ($inputString -ne $null)
    {
        return $inputString.Trim();
    }
    return $inputString;
}

Function ValidateAndGetLevel ($level)
{
    $level = CleanupInput -inputString $level

    if ( ($level -eq 'Subscription-level') -or ($level -eq 'ResourceGroup-level') -or ($level -eq 'Resource-level') )
    {  
        return $level
    }
    else
    {
        throw 'Level is incorrect'
    }
}

Function ValidateAndGetSubscription ($tenantId, $subscriptionName)
{
    $subscriptionName = CleanupInput -inputString $subscriptionName

    Try
    {
        $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -TenantId $tenantId -ErrorAction Stop;
    }
    Catch 
    {
        #throw 'Subscription not found';
        throw $PSItem.Exception.Message;
    } 
    return $subscription.Id;
}

Function ValidateAndGetResourceGroup ($tenantId, $subscriptionId, $resourceGroupName)
{
    $resourceGroupName = CleanupInput -inputString $resourceGroupName

    $context = Set-AzContext -Subscription $subscriptionId -Tenant $tenantId
    Try
    {
        $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction Stop
    }
    Catch 
    {
        throw 'Resource Group not found in the Subscription'
    }
    return $rg.ResourceGroupName;
}

Function ValidateAndGetResource ($resourceGroupName, $resourceName)
{
    $resourceName = CleanupInput -inputString $resourceName

    $resource = Get-AzResource -Name $resourceName -ResourceGroupName $resourceGroupName
    if ($resource -eq $null)
    {
        throw 'Resource not found in the Resource Group and Subscription'
    }
    return $resource.ResourceType
}

Function ValidateAndGetRole ($tenantId, $subscriptionId, $roleName)
{
    $roleName = CleanupInput -inputString $roleName

    $context = $context = Set-AzContext -Subscription $subscriptionId -Tenant $tenantId

    $role = Get-AzRoleDefinition -Name $roleName
    if ($role -ne $null)
    {
        return $role.Name
    }
    
    throw 'RBAC role name not found';
}

Function ValidateAndGetADObject ($adObjectName, $adObjectType)
{
    $adObjectName = CleanupInput -inputString $adObjectName
    $adObjectType = CleanupInput -inputString $adObjectType

    if ($adObjectType -eq 'User')
    {
        $adObject = Get-AzADUser -UserPrincipalName $adObjectName
        if ($adObject -eq $null)
        {
            throw "User not found"
        }
    }
    elseif ($adObjectType -eq 'Group')
    {
        $adObject = Get-AzADGroup -DisplayName $adObjectName
        if ($adObject -eq $null)
        {
            throw "Group not found"
        }
    }
    elseif ($adObjectType -eq 'ServicePrincipal')
    {
        $adObject = Get-AzADServicePrincipal -DisplayName $adObjectName
        if ($adObject -eq $null)
        {
            throw "Service Principal not found"
        }
    }
    else
    {
        throw "AD Object type is incorrect"
    }
    
    return $adobject.Id;
}

Function ValidateAndGetAction ($action)
{
    $action = CleanupInput -inputString $action

    if ( ($action -eq 'Add') -or ($action -eq 'Remove') )
    {  
        return $action
    }
    else
    {
        throw 'Action is incorrect'
    }
}

Function AssignOrRemoveRBACRole ($tenantId, $level, $subscriptionName, $resourceGroupName, $resourceName, $roleName, $adObjectName, $adObjectType, $action)
{
    
    $level = ValidateAndGetLevel -level $level
    $action = ValidateAndGetAction -action $action

    if ($level -eq 'Subscription-level')
    {
        $subscriptionId = ValidateAndGetSubscription -tenantId $tenantId -subscriptionName $subscriptionName
        $adObjectId = ValidateAndGetADObject -adObjectName $adObjectName -adObjectType $adObjectType
        $roleName = ValidateAndGetRole -tenantId $tenantId -subscriptionId $subscriptionId -roleName $roleName

        $scope = '/subscriptions/' + $subscriptionId;
        if ($action -eq 'Add')
        {
            $output = New-AzRoleAssignment -ObjectId $adObjectId -Scope $scope -RoleDefinitionName $roleName -ErrorAction Stop
        }
        else
        {
            $output = Remove-AzRoleAssignment -ObjectId $adObjectId -Scope $scope -RoleDefinitionName $roleName -ErrorAction Stop
        }
    }
    elseif ($level -eq 'ResourceGroup-level')
    {
        $subscriptionId = ValidateAndGetSubscription -tenantId $tenantId -subscriptionName $subscriptionName
        $resourceGroupName = ValidateAndGetResourceGroup -tenantId $tenantId -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName
        $adObjectId = ValidateAndGetADObject -adObjectName $adObjectName -adObjectType $adObjectType
        $roleName = ValidateAndGetRole -tenantId $tenantId -subscriptionId $subscriptionId -roleName $roleName

        if ($action -eq 'Add')
        {
            $output = New-AzRoleAssignment -ObjectId $adObjectId -ResourceGroupName $resourceGroupName -RoleDefinitionName $roleName -ErrorAction Stop
        }
        else
        {
            $output = Remove-AzRoleAssignment -ObjectId $adObjectId -ResourceGroupName $resourceGroupName -RoleDefinitionName $roleName -ErrorAction Stop
        }
    }
    elseif ($level -eq 'Resource-level')
    {
        $subscriptionId = ValidateAndGetSubscription -tenantId $tenantId -subscriptionName $subscriptionName
        $resourceGroupName = ValidateAndGetResourceGroup -tenantId $tenantId -subscriptionId $subscriptionId -resourceGroupName $resourceGroupName
        $resourceType = ValidateAndGetResource -resourceGroupName $resourceGroupName -resourceName $resourceName
        $adObjectId = ValidateAndGetADObject -adObjectName $adObjectName -adObjectType $adObjectType
        $roleName = ValidateAndGetRole -tenantId $tenantId -subscriptionId $subscriptionId -roleName $roleName

        if ($action -eq 'Add')
        {
            $output = New-AzRoleAssignment -ObjectId $adObjectId -ResourceGroupName $resourceGroupName -ResourceName $resourceName -ResourceType $resourceType -RoleDefinitionName $roleName -ErrorAction Stop
        }
        else
        {
            $output = Remove-AzRoleAssignment -ObjectId $adObjectId -ResourceGroupName $resourceGroupName -ResourceName $resourceName -ResourceType $resourceType -RoleDefinitionName $roleName -ErrorAction Stop
        }
    }
    else
    {
        # nested resource level to be implemented
    }
    return 'Success'  
}

#-------------------------------------------------- [ Functions End] --------------------------------------------------#


#-------------------------------------------------- [ Main execution] --------------------------------------------------#

Try
{
    ValidateInstalledModules
}
Catch
{
    Write-Host $_;
    return;
}

$fileCheck = Test-Path $rbacFile -PathType Leaf
if ($fileCheck -eq $false)
{
    Write-Host 'RBAC Access xlsx spreadsheet file not found. Please provide valid file path'
    return
}

Try
{
    $xlsPackage = Open-ExcelPackage -Path $rbacFile
 }
catch
{
    Write $PSItem.Exception.Message;
    return
}

$xlsWorksheet = $xlsPackage.'RBAC Access'
if ($xlsWorksheet -eq $null)
{
    Write-Host 'Couldnt find a worksheet named [RBAC Access] in the xlsx file. Please check and try again'
    return
}

Write-Host '-----------------------------------------------------------------------------------------'
Write-Host 'START - RBAC Assignment or Removal Script execution'


Write-Host 'Connecting to Azure Account for running Az module commands. Navigate to sign-in page and sign-in using valid credentials'


$azContext = Connect-AzAccount -TenantId $tenantId
if ($azContext -eq $null)
{
    Write-Host 'Couldnt connect to Azure Account. Please check tenantId and credentials and try again'
    return
}

Write-Host 'Initiating RBAC Assignment or Removal.......................'

$startRow = 3
$rowCount = 1

foreach ($i in ($startRow..($xlsWorksheet.Dimension.Rows)))
{
    if (($xlsWorksheet.Cells["A$i"].Value -eq $null) -or ($xlsWorksheet.Cells["A$i"].Value -eq ''))
    {
        break
    }
    
    $level = $xlsWorksheet.Cells["A$i"].Value;
    $subscriptionName = $xlsWorksheet.Cells["B$i"].Value;
    $resourceGroupName = $xlsWorksheet.Cells["C$i"].Value;
    $resourceName = $xlsWorksheet.Cells["D$i"].Value;
    $roleName = $xlsWorksheet.Cells["E$i"].Value;
    $adObjectName = $xlsWorksheet.Cells["F$i"].Value;
    $adObjectType = $xlsWorksheet.Cells["G$i"].Value;
    $action = $xlsWorksheet.Cells["H$i"].Value;
    Try
    {
        $status = AssignOrRemoveRBACRole -tenantId $tenantId -level $level -subscriptionName $subscriptionName -resourceGroupName $resourceGroupName -resourceName $resourceName -roleName $roleName -adObjectName $adObjectName -adObjectType $adObjectType -action $action
        $xlsWorksheet.Cells["I$i"].Value = $status
        Write-Host "Row $rowCount - RBAC - $action - $status"
    }
    Catch
    {
        $xlsWorksheet.Cells["I$i"].Value = $_ 
        Write-Host "Row $rowCount - RBAC - $action - Error"
    }

    $rowCount += 1;
}

$xlsPackage.Save()
Close-ExcelPackage -ExcelPackage $xlsPackage

Write-Host 'Completing RBAC Assignment or Removal.......................'

Write-Host 'COMPLETED - RBAC Assignment or Removal Script execution'
Write-Host '-----------------------------------------------------------------------------------------'

#-------------------------------------------------- [ Main execution] --------------------------------------------------#

