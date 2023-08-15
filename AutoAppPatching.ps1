$Winget_URL = "https://api.github.com/repos/microsoft/winget-cli/releases"
$Curr_Dir = $PSScriptRoot
$Log = "$PSScriptRoot\AutoAppPatchLog.txt"
# This file will be created/updated by the SentinelOne CVE monitoring script and expected
# to be titled the same in the same directory.
$Update_List = ""

<#
.DESCRIPTION
Separate function to handle dependency requirements. Will check if they are already installed and installed if not.
After attempting install, the function returns a hashmap containing bools used to inform the 'Install-Winget' if the
packages installed correctly or not.
#>
Function Install-Dependecies {
    param (
        [String]$Dir,
        [String]$Log
    )
    $has_xaml = $false
    $has_VClibs = $false
    $all_apps = Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName
    for($i=0;$i -lt $all_apps.Count;$i++){
        if($all_apps[$i].Name -eq "Microsoft.UI.Xaml.2.7"){
            $has_xaml = $true
        }elseif($all_apps[$i].Name -eq "Microsoft.VCLibs.140.00.UWPDesktop"){
            $has_VClibs = $true
        }
    }
    if(!$has_xaml){
        try{
            # Attempting to xaml dependency for Winget.
            $xamUrl = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.7.1"    
            $zip = "Microsoft.UI.Xaml.2.7.1.nupkg.zip"
            Invoke-WebRequest -Uri $xamUrl -OutFile "$Dir\$zip"
            Expand-Archive -Path "$Dir\$zip"
            Add-AppxPackage -Path "Microsoft.UI.Xaml.2.7.1.nupkg\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.7.appx"
            $has_xaml = $true
        }catch{
            Write-Warning "Error installing Microsoft.UI.Xaml.2.7 for Winget."
            "Error installing Microsoft.UI.Xaml.2.7 for Winget." | Out-File -Append -FilePath $Log
        }
    }else{
        $time = Get-Date
        "Microsoft.UI.Xaml.2.7 already installed. Timestamp: $time"| Out-File -Append -FilePath $Log
    }
    if(!$has_VClibs){
        try{
            # Attempting to VCLibs dependency for Winget.
            Add-AppxPackage -Path "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
            $has_VClibs = $true
        }catch{
            Write-Warning "Error installing MMicrosoft.VCLibs.140.00.UWPDesktop for Winget."
            "Error installing Microsoft.VCLibs.140.00.UWPDesktop for Winget." | Out-File -Append -FilePath $Log
        }
    }else{
        $time = Get-Date
        "Microsoft.VCLibs.140.00.UWPDesktop already installed. Timestamp: $time"| Out-File -Append -FilePath $Log
    }
    Start-Sleep -Seconds 2
    $pkgs = @{
        'Xaml' = $has_xaml
        'VClibs' = $has_VClibs
    }
    Return $pkgs
}

<#
.DESCRIPTION
Function to install winget if it is not installed. Will request package from github, write to
an install file, the use 'Add-AppxPackage' to install Winget. Will call 'Install-Dependecies' function
to handle dependencies and to determine if the Winget install can continue.
#>
Function Install-Winget {
    param (
        [String]$Endpoint,
        [String]$Dir,
        [string]$Log
    )
    $installed = $false
    $requirements = Install-Dependecies -Dir $Dir -Log $Log
    if(($requirements.Xaml -eq $true) -and ($requirements.VCLibs -eq $true)){
        try{
            # Requesting winget install info github endpoint
            $req = Invoke-RestMethod -Uri $Endpoint -Method Get -ErrorAction Stop
            $app_info = $req[0].assets | Where-Object {$_.Name -like "*msixbundle"}
            $install_file = "$Dir\$($app_info.name)"
            $download_url = $app_info.browser_download_url
            # Downloading Winget data and writing to appx install file.
            Invoke-WebRequest -Uri $download_url -UseBasicParsing -DisableKeepAlive -OutFile $install_file
            Add-AppxPackage -Path $install_file
            "Winget installed." | Out-File -Append -FilePath $Log
            Start-Sleep -Seconds 2
            $installed = $true
        }catch{
            Write-Host "Error installing Winget."
            "Error installing Winget." | Out-File -Append -FilePath $Log
        }
    }else{
        $time = Get-Date
        Write-Host "Unabale to install Winget due to dependency install failure. $time"
        "Unabale to install Winget due to dependency install failure. $time" | Out-File -Append -FilePath $Log
    }
    Return $installed
}

<#
.DESCRIPTION
Function to check if Winget is installed. If not, it use 'Install-Winget' function
to install Winget.
#>
Function Confirm-Winget {
    param(
        [String]$Url,
        [String]$Folder,
        [string]$Log
    )
    $has_winget = $false
    $all_apps = Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName
    for($i=0;$i -lt $all_apps.Count;$i++){
        if(($all_apps[$i].Name -eq "Microsoft.Winget.Source") -or ($all_apps[$i].Name -eq "Microsoft.DesktopAppInstaller")){
            $has_winget = $true
        }
    }
    if(!$has_winget){
        "Installing Winget..."| Out-File -Append -FilePath $Log
        $has_winget = Install-Winget -Endpoint $Url -Dir $Folder -Log $Log
    }else{
        $time = Get-Date
        "Winget already installed. Timestamp: $time"| Out-File -Append -FilePath $Log
    }
    Return $has_winget
}

Function Confirm-ENV_Vars{
    param(
        [String]$VarString
    )
    $envVarExists = $false
    $envVarList = $varsString.Split(";")
    for($i=0;$i -lt $envVarList.Count;$i++){
        if($envVarList[$i] -like "DesktopAppInstaller"){
            $envVarExists = $true
            Write-Host "Winget already set in PATH"
            Break
        }
    }
    Return $envVarExists
}

Function Set-ENV_Vars {
    $name = "DesktopAppInstaller"
    $wingets = Get-AppxPackage -AllUsers | Where-Object{$_.Name -like "*$name*"}
    $latestWinget = $wingets[$wingets.Count - 1]
    $path_addition = ";$($latestWinget.InstallLocation)"
    $sysVars = [Environment]::GetEnvironmentVariables('machine')
    $sysPathVars = $sysVars.Path
    $currScopeVars = $env:PATH
    # Checking if Winget path is set in machine scope
    $wingetSysENV = Confirm-ENV_Vars -VarString $sysPathVars
    # Checking if Winget path is set in current session scope
    $currScopeENV = Confirm-ENV_Vars -VarString $currScopeVars

    if(!$wingetSysENV){
        [Environment]::SetEnvironmentVariable("PATH", $Env:PATH + "$path_addition", [EnvironmentVariableTarget]::Machine)
    }
    if(!$currScopeENV){
        $env:PATH += "$path_addition"
    }
}

Function Read-UpdateList{
    param(
        [String]$UpListFile
    )
    $apps = ""
    try{
        $apps = Get-Content -Path $UpListFile
    }catch{
        $time = Get-Date
        Write-Host "Unable to fetch list of apps needing updates. $time"
        "Unable to fetch list of apps needing updates. $time" | Out-File -Append -FilePath $Log
        $apps = 0
    }
    Return $apps
}

$winget = Confirm-Winget -Url $Winget_URL -Folder $Curr_Dir -Log $Log
if($winget){
    Set-ENV_Vars
    winget list --accept-source-agreements --disable-interactivity
    <#$app_list = Read-UpdateList -UpListFile $Update_List
    if(($app_list.Count -eq 0) -xor ($app_list -eq 0)){
        $time = Get-Date
        Write-Warning "Exiting due to failed app list fetch. $time"
        "Exiting due to failed app list fetch. $time" | Out-File -Append -FilePath $Log
        #Exit 1
    }#>

}else{
    $time = Get-Date
    Write-Warning "Exiting due to failed Winget install. $time"
    "Exiting due to failed Winget install. $time" | Out-File -Append -FilePath $Log
    #Exit 1
}