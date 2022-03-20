#Requires -RunAsAdministrator
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("Symlink", "Vpk")]
    [string]
    $Mode,

    [Parameter()]
    [switch]
    $Watch
)

# Links a folder from the repo to the game directory
$mapFoldersToGameRoot = @()

Push-Location -Path $PSScriptRoot
try {
    $name = Get-Location | Split-Path -Leaf

    $steamLocation = Get-Item -Path 'HKLM:\SOFTWARE\Wow6432Node\Valve\Steam\' | Foreach-Object {$_.GetValue("InstallPath")}  | Select-Object -First 1
    $installLocations = Get-Content -Path (Join-Path -Path $steamLocation -ChildPath "steamapps\libraryfolders.vdf") |
        Select-String '"path"*' -List | ForEach-Object {$_ -split "`t" -replace '"', '' -replace '\\\\', '\'  | Select-Object -Last 1}

    $baseInstall = $installLocations | Where-Object {
        Get-ChildItem -Path (Join-Path $_ "steamapps") -Filter "appmanifest_550.acf"
    }

    if(-not $baseInstall)
    {
        throw "Could not find Left 4 Dead 2"
    }

    $gameDir = Join-Path -Path $baseInstall -ChildPath "steamapps\common\Left 4 Dead 2"
    $vpkCommand = Join-Path -Path $gameDir -ChildPath "bin/vpk.exe"
    $gameFileDir = Join-Path -Path $gameDir -ChildPath "left4dead2"
    $addonPath = Join-Path -Path $gameFileDir -ChildPath "addons"
    $addonSource = Join-Path -Path $PSScriptRoot -ChildPath 'src'

    # Check the executable exists. If not, throw.
    Get-Command -Name $vpkCommand -CommandType Application -ErrorAction Stop | Out-Null



    # Loop through the folders to map
    # Get the child-items, and create symlinks for each

    function Update-Symlinks
    {
        Write-Host "Refreshing symlinks..."
        $addonItemPath = Join-Path -Path $addonPath -ChildPath $name
        if($Mode -eq "Symlink")
        {
            if((Test-Path -Path $addonItemPath) -and (Get-Item -Path $addonPath).Target -ne $addonSource)
            {
                if($addonItemPath.Mode[0] -eq 'l')
                {
                    (Get-Item -Path $addonItemPath).Delete();
                }
                else
                {
                    Remove-Item -Path $addonItemPath -Recurse -Confirm
                }
            }

            if(Test-Path (Join-Path -Path $addonPath -ChildPath "$name.vpk"))
            {
                Remove-Item -Path (Join-Path -Path $addonPath -ChildPath "$name.vpk") -Confirm
            }

            $newItemParams = @{
                Path = (Join-Path $addonPath -ChildPath $name)
                ItemType = "Junction"
                Value = $addonSource
            }
            New-Item @newItemParams

            # Create the symlink in addons folder
            $newItemParams = @{
                Path = (Join-Path $gameDir -ChildPath "sdk_content\$name")
                ItemType = "Junction"
                Value = $addonSource
            }
            New-Item @newItemParams -Force
        }
        elseif($Mode -eq "Vpk")
        {
            if(Test-Path -Path $addonItemPath)
            {
                if($addonItemPath.Mode[0] -eq 'l')
                {
                    $addonItemPath.Delete();
                }
                else
                {
                    Remove-Item -Path $addonItemPath -Recurse -Confirm
                }
            }

            & $vpkCommand $addonSource
            Move-Item -Path "src.vpk" -Destination "$addonItemPath.vpk" -Force
        }

        $mapFoldersToGameRoot | ForEach-Object {
            $source = Resolve-Path -Path (Join-Path -path $addonSource -ChildPath $_) -ErrorAction Continue
            $destRoot = Join-Path -Path $gameFileDir -ChildPath $_

            if(($null -ne $source))
            {
                #TODO: Get smarter about this - only remove folders that actually need deleted
                Get-ChildItem -Path $destRoot | Where-Object {$_.Target -like "$source*"} | ForEach-Object {
                    if($_.Mode[0] -eq 'l')
                    {
                        $_.Delete()
                    }
                    else
                    {
                        $_ | Remove-Item -Recurse -Confirm
                    }
                } # Cannot use remove-item for symlinks
                $source | Get-ChildItem | ForEach-Object {
                    $dest = (Join-Path -Path $destRoot -ChildPath ($_.Name))
                    # If the symbolic link is not pointed at the right place delete it
                    $destItem = Get-Item $dest -ErrorAction SilentlyContinue
                    if((Test-Path $dest) -and $destItem.Target -ne $_.FullName)
                    {
                        if($destItem.Mode[0] -eq 'l')
                        {
                            Get-Item -Path $dest | ForEach-Object {$_.Delete()}
                        }
                        else
                        {
                            Remove-Item -Path $dest -Confirm:$true -Recurse
                        }
                    }

                    if(-not (Test-Path $dest))
                    {
                        if($_ -is [System.IO.DirectoryInfo])
                        {
                            # Powershell scopes breaking your brain? Good. They're scoped to script by default.
                            $ItemType = "Junction"
                        }
                        else {
                            $ItemType = "HardLink"
                        }

                        New-Item -Path $dest -ItemType $ItemType -Value $_.FullName -Force
                    }
                }
            }
        }
    }

    Update-Symlinks

    $fsw = [System.IO.FileSystemWatcher]::new($addonSource)
    if($Watch.IsPresent)
    {
        $fsw.IncludeSubdirectories = $true
        $fsw.EnableRaisingEvents = $true
        Register-ObjectEvent -InputObject $fsw -EventName Changed -Action {Update-Symlinks} | Out-Null
        Register-ObjectEvent -InputObject $fsw -EventName Created -Action {Update-Symlinks} | Out-Null
        Register-ObjectEvent -InputObject $fsw -EventName Deleted -Action {Update-Symlinks} | Out-Null
        Register-ObjectEvent -InputObject $fsw -EventName Renamed -Action {Update-Symlinks} | Out-Null
    }

    while($Watch.IsPresent)
    {
        Write-Host "Watching for file changes..."
        $fsw.WaitForChanged("All")
        Update-Symlinks
    }
}
finally {
    Pop-Location
}