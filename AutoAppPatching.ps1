$Winget_URL = "https://api.github.com/repos/microsoft/winget-cli/releases"
$Curr_Dir = $PSScriptRoot
$Log = "$PSScriptRoot\AutoAppPatchLog.txt"
# This file will be created/updated by the SentinelOne CVE monitoring script and expected
# to be titled the same in the same directory.
$Update_List = ""

<#
.DESCRIPTION
Function to install winget if it is not installed. Will request package from github, write to
an install file, the use 'Add-AppxPackage' to install Winget.
#>
Function Install-Winget {
    param (
        [String]$Endpoint,
        [String]$Dir,
        [string]$Log
    )
    try{
        # Attempting to install dependencies for Winget.
        $xamUrl = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.7.1"    
        $zip = "Microsoft.UI.Xaml.2.7.1.nupkg.zip"
        Invoke-WebRequest -Uri $xamUrl -OutFile "$Dir\$zip"
        Expand-Archive -Path "$Dir\$zip"
        Add-AppxPackage -Path "Microsoft.UI.Xaml.2.7.1.nupkg\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.7.appx"
        Add-AppxPackage -Path "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
    }catch{
        Write-Warning "Error installing dependencies for Winget."
        "Error installing dependencies for Winget." | Out-File -Append -FilePath $Log
    }
    try{
        # Requesting winget install info github endpoint
        $req = Invoke-RestMethod -Uri $Endpoint -Method Get -ErrorAction Stop
        $app_info = $req[0].assets | Where-Object {$_.Name -like "*msixbundle"}
        $install_file = "$Dir\$($app_info.name)"
        $download_url = $app_info.browser_download_url
        # Downloading Winget data and writing to appx install file.
        Invoke-WebRequest -Uri $download_url -UseBasicParsing -DisableKeepAlive -OutFile $install_file
        Add-AppxPackage -Path $install_file
        # Block to used to set environment variable
        $nameList = $app_info.name.Split(".")
        $wingets = Get-AppxPackage -AllUsers | Where-Object{$_.PackageFamilyName -like "*$($nameList[1])*"}
        $latestWinget = $wingets[$wingets.Count - 1]
        $pathPortion = $latestWinget.PackageFullName
        $PATH_ADDITION = ";C:\Program Files\WindowsApps\$pathPortion"
        [Environment]::SetEnvironmentVariable("PATH", $Env:PATH + "$PATH_ADDITION", [EnvironmentVariableTarget]::Machine)
        "Winget installed." | Out-File -Append -FilePath $Log
    }catch{
        Write-Warning "Error installing Winget."
        "Error installing Winget." | Out-File -Append -FilePath $Log
    }
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
        Install-Winget -Endpoint $Url -Dir $Folder -Log $Log
        "Installing Winget..."| Out-File -Append -FilePath $Log
    }else{
        $time = Get-Date
        "Winget already installed. Timestamp: $time"| Out-File -Append -FilePath $Log
    }
    Return $has_winget
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
    $app_list = Read-UpdateList -UpListFile $Update_List
    if(($app_list.Count -eq 0) -xor ($app_list -eq 0)){
        $time = Get-Date
        Write-Warning "Exiting due to failed app list fetch. $time"
        "Exiting due to failed app list fetch. $time" | Out-File -Append -FilePath $Log
        #Exit 1
    }

}else{
    $time = Get-Date
    Write-Warning "Exiting due to failed Winget install. $time"
    "Exiting due to failed Winget install. $time" | Out-File -Append -FilePath $Log
    #Exit 1
}