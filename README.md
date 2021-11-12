# AzRBACRoleManager

## SYNOPSYS

    Script helps assign or remove an RBAC role assignment to a user/group/service principal using a MS excel sheet as input (in specific format)


## DESCRIPTION

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


## PARAMETERS

    **rbacFile** - Provide the full path of the template xlsx spreadsheet file
    **tenantId** - the GUID representing the Azure AD tenant against which this script has to be executed


## INPUTS

    - File path of xlsx spreadsheet that contains RBAC details to be assigned or removed in a sepcific format
    - Azure TenantId of the Azure Tenant under which the RBAC assignment/removal needs to be performed

  
## OUTPUTs

    - Input xlsx spreadsheet is updated with status of each RBAC assignment or removal
    

## Author & Version History

    **Script Author**: Gowri Shanker Raghuraman
    **Version**: 1.0
    **Creation Date**: 12-Nov-2021
    **Details**: RBAC management script
    **Change Author**: Gowri Shanker Raghuraman


## LIMITATIONS / KNOWN ISSUES

    - Script only works when provided with AD Group Display Name, Service Principal Display Name and User Principal Name (including domain name; refer to your Azure Active Directory)
    - Exception andling is not implemented thoroughly so error messages may not be very friendly in some cases
    - Hardwired to the excel template. Deviations in excel template will give unexpected results.
    - When assigning an RBAC role, if it is already assigned at that scope, script doesnt skip it. It will execute assignment statement but fail and print a message noting the existence of RBAC role assignment.
    - When assigning an RBAC role, if the parent scope already has the same role, the script will not skip and end up assigning the role at requested scope as well
    - When removing an RBAC role, if it is not asigned, script doesnt skip it. It will go through and print a message on console. This error message is not user friendly and need revision
    - If RG or resource has a Delete lock, removing RBAC role will fail. Script is not capable of removing the lock. This has to be done as a pre-req.
    - Script is relatively slow in assigning/revoking role assignments as several cmdlets are executed for each entry in the excel. Performance optimization needs to be done as part of a revision
    - There is no support for Nested Resource level role assignment and removal (Ex. RBAC assignment/removal on a Subnet inside a VNet). This need a revision


## PRE-REQUISITES

    - Ensure Az and ImportExcel modules are installed on your local machine. If not run the following cmdlets
    
        *Install-Module Az -Scope CurrentUser*
        *Install-Module ImportExcel -Scope CurrentUser*

    **Note**: Using the CurrentUser scope will install the modules in your profile so you will not need Admin rights to install them

    - The user account used to login should have Owner / User Access Administrator RBAC role assigned on the Subscription
    - For RBAC removal, ensure no delete lock exists on resource and resource groups

## USAGE

    *ManageRBACAssignment.ps1 -rbacFile <RBAC_xlsx_file_path> -tenantId <AAD_Tenant_ID>*
