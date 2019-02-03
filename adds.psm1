#Disable various services
Function DisableServices {
	
	$services = @(
	    "diagnosticshub.standardcollector.service" # Microsoft (R) Diagnostics Hub Standard Collector Service
	    "DiagTrack"                                # Diagnostics Tracking Service
	    #"dmwappushservice"                         # WAP Push Message Routing Service (see known issues)
	    "HomeGroupListener"                        # HomeGroup Listener
	    "HomeGroupProvider"                        # HomeGroup Provider
	    "lfsvc"                                    # Geolocation Service
	    "MapsBroker"                               # Downloaded Maps Manager
	    "NetTcpPortSharing"                        # Net.Tcp Port Sharing Service
	    "RemoteAccess"                             # Routing and Remote Access
	    "RemoteRegistry"                           # Remote Registry
	    "SharedAccess"                             # Internet Connection Sharing (ICS)
	    "TrkWks"                                   # Distributed Link Tracking Client
	    "WbioSrvc"                                 # Windows Biometric Service
	    #"WlanSvc"                                 # WLAN AutoConfig
	    "WMPNetworkSvc"                            # Windows Media Player Network Sharing Service
	    "XblAuthManager"                           # Xbox Live Auth Manager
	    "XblGameSave"                              # Xbox Live Game Save Service
	    "XboxNetApiSvc"                            # Xbox Live Networking Service
	)

	foreach ($service in $services) {
	    Write-Output "Trying to disable $service"
	    Get-Service -Name $service | Set-Service -StartupType Disabled
	}
}

#Check if reg value exists
# Source: https://gallery.technet.microsoft.com/scriptcenter/deactivate-Nagle-Algorithm-66ca7608
Function Exists-RegistryValue($pspath, $propertyname) {
    $exists = Get-ItemProperty -Path "$pspath" -Name "$propertyname" -ea SilentlyContinue
    If (($exists -ne $null) -and ($exists.Length -ne 0)) {
        Return $true
    }
    Return $false
}

# Disable Nagle Algorithm
# Modified from: https://gallery.technet.microsoft.com/scriptcenter/deactivate-Nagle-Algorithm-66ca7608
Function DisableNagle{
	$strTargetNICAddress = Test-Connection -ComputerName (hostname) -Count 1  | Select -ExpandProperty IPV4Address 
	$strTargetNICAddress = $strTargetNICAddress.IPAddressToString

	foreach($item in Get-Childitem -LiteralPath HKLM:\system\currentcontrolset\services\tcpip\parameters\interfaces)
	{
	    
	    $key = Get-ItemProperty $item.PSPath
	    
	    if(([string]$key.IPAddress -match $strTargetNICAddress) -OR ([string]$key.DHCPIPAddress -match $strTargetNICAddress))
	    {
	        Write-Host "Interface: " $item.PSPath
	        # only one is supposed to have a value, so both vars printed quick and dirty
	        Write-Host "IP: " $key.IPAddress $key.DHCPIPAddress

			Set-ItemProperty -LiteralPath $item.PSPath -Name TcpAckFrequency -Value 1 -ea "Stop"
			Set-ItemProperty -LiteralPath $item.PSPath -Name TCPNoDelay -Value 1 -ea "Stop"

	        if(-not [Boolean](Exists-RegistryValue $item.PSPath "TcpAckFrequency"))
	        {
	        	Write-Host "Successfully disabled Nagle's algorithm."
	        }
	    }
	}
}

# Nvidia Driver Check, cleans and installs new drivers
# Modified from: https://github.com/lord-carlos/nvidia-update
Function UpdateNvidiaDrivers{
	# Checking currently installed driver version
	Write-Host "Attempting to detect currently installed driver version..."
	try {  
		$ins_version = (Get-WmiObject Win32_PnPSignedDriver | Where-Object {$_.devicename -like "*nvidia*" -and $_.devicename -notlike "*audio*"}).DriverVersion.SubString(7).Remove(1,1).Insert(3,".")
	} catch {
		Write-Host "Unable to detect a compatible Nvidia device."
		return;
	}
	Write-Host "Installed version: `t$ins_version"

	# Set locations
	$location = "US"
	$extractDir = [Environment]::GetFolderPath("Desktop")

	# Checking if 7zip is installed
	if (Test-Path $env:programfiles\7-zip\7z.exe) {
		$archiverProgram = "$env:programfiles\7-zip\7z.exe"
	} else {
		Write-Host "7zip not installed. Cannot extract driver package. Cancelling."
		return;
	}

	# Checking latest driver version from Nvidia website, internet explorer needs to have been opened atleast once to initilize Invoke-WebRequest
	$link = Invoke-WebRequest -Uri 'https://www.nvidia.com/Download/processFind.aspx?psid=101&pfid=816&osid=57&lid=1&whql=1&lang=en-us&ctk=0' -Method GET
	if(!($?))
	{
		Write-Host "Error: Something went wrong with Invoke-WebRequest, open Internet Explorer once to initlize"
		return;
	}
	$version = $link.parsedhtml.GetElementsByClassName("gridItem")[2].innerText
	Write-Host "Latest version: `t$version"


	# Comparing installed driver version to latest driver version from Nvidia
	if($version -eq $ins_version) {
		Write-Host "Latest Nvidia Drivers installed."
		return;
	}

	# Confirm install
	Write-Host -nonewline "New Nvidia Driver $version found. Continue with install? (Y/N) "
	$response = read-host
	if ( $response -ne "Y" ) { return; }

	# Checking Windows version
	if ([Environment]::OSVersion.Version -ge (new-object 'Version' 9,1)) {
		$windowsVersion = "win10"
	} else {
		$windowsVersion = "win8-win7"
	}

	# Checking Windows version
	if ((Get-WmiObject win32_operatingsystem | Select-Object osarchitecture).osarchitecture -eq "64-bit")
	{
		$windowsArchitecture = "64bit"
	} else {
		$windowsArchitecture = "32bit"
	}

	# Generating the download link
	$url = "http://$location.download.nvidia.com/Windows/$version/$version-desktop-$windowsVersion-$windowsArchitecture-international-whql.exe"
	Write-Host $url

	# Create a new temp folder NVIDIA
	$nvidiaTempFolder = "$extractDir\nvidia_$version"
	New-Item -Path $nvidiaTempFolder -ItemType Directory 2>&1 | Out-Null

	# Download installer
	$dlFile = "$nvidiaTempFolder\$version.exe"
	Write-Host "Downloading $version to $dlFile"
	Start-BitsTransfer -Source $url -Destination $dlFile

	# Extracting setup files
	$extractFolder = "$nvidiaTempFolder\$version"
	$filesToExtract = "Display.Driver NVI2 EULA.txt ListDevices.txt setup.cfg setup.exe"
	Write-Host "Download finished, extracting files..."
	if ($archiverProgram -eq "$env:programfiles\7-zip\7z.exe") {
		Start-Process -FilePath $archiverProgram -ArgumentList "x $dlFile $filesToExtract -o""$extractFolder""" -wait
	}
	# Remove unneeded dependencies from setup.cfg
	(Get-Content "$extractFolder\setup.cfg") | Where-Object {$_ -notmatch 'name="\${{(EulaHtmlFile|FunctionalConsentFile|PrivacyPolicyFile)}}'} | Set-Content "$extractFolder\setup.cfg" -Encoding UTF8 -Force

	# Installing drivers
	Write-Host "Installing $version..."
	$install_args = "-s -noreboot -noeula -clean"
	Start-Process -FilePath "$extractFolder\setup.exe" -ArgumentList $install_args -wait
}

# Add telemetry ips to firewall
Function DisableTeleIps{
	Write-Output "Adding telemetry ips to firewall"
    $ips = [string[]](Get-Content $psscriptroot\telemetryIPs.txt | Select-Object -Skip 3)
	Remove-NetFirewallRule -DisplayName "Block Telemetry IPs" -ErrorAction SilentlyContinue
	New-NetFirewallRule -DisplayName "Block Telemetry IPs" -Direction Outbound `
	-Action Block -RemoteAddress ($ips)
}

# Disable Enhanced pointer precision
Function DisableEnhancedPointerPrecision {
	Write-Output "Disabling Enhanced pointer precision..."
	Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Type String -Value 0
	Set-ItemProperty "HKCU:\Control Panel\Mouse" "MouseSensitivity" "10"
	Set-ItemProperty "HKCU:\Control Panel\Mouse" "MouseSpeed" "0"
	Set-ItemProperty "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0"
	Set-ItemProperty "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0"
	Set-ItemProperty "HKCU:\Control Panel\Mouse" "SmoothMouseXCurve" ([byte[]](0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0xCC, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x80, 0x99, 0x19, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x66, 0x26, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x33, 0x33, 0x00, 0x00, 0x00, 0x00, 0x00))
	Set-ItemProperty "HKCU:\Control Panel\Mouse" "SmoothMouseYCurve" ([byte[]](0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x38, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x70, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA8, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00))
}

# Change volume control to classic style
Function ChangeVolumeClassic {
	Write-Output "Changing volume control to classic style..."
	If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\MTCUVC")) {
		New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\MTCUVC" -Force | Out-Null
	}
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\MTCUVC" -Name "EnableMtcUvc" -Type Dword -Value 0
}


## Install Chocolatey if not already installed
Function InstallChoco {
	Write-Host "Installing chocolatey..."
	$error.clear()
	try { choco }
	catch { 
		Write-Host -nonewline "Install chocolatey? (Y/N) "
		$response = read-host
		if ( $response -ne "Y" ) { return; }
		Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
	}
	if (!$error) {
		Write-Host "Chocolatey already installed."
	}
}

## Install all packages in chocoInstall.txt
Function InstallChocoPkgs {
	$file = "$psscriptroot\chocoInstall.txt"
	Write-Host "Installing all packages in $file that are not already installed..."
	if (Test-Path $file) {
		$toInstall = [string[]](Get-Content $file | Select-Object -Skip 3)
		if (!($toInstall.count -eq 0)) {
			$installed = [string[]](choco list --local-only | ForEach {"$_".Split(" ")[0]})
			$notInstalled = $toInstall | Where {$installed -NotContains $_}
			
			if (!($notInstalled.count -eq 0)){
				Write-Host "Found packages in $file that are not installed: $notInstalled"
				Write-Host -NoNewline "Install? (Y/N)"
				$response = read-host
				if ( $response -ne "Y" ) { return; }
				
				ForEach ($j in $notInstalled) {
					choco install $j -y
				}
			}else {
				Write-Host "All packages from $file installed."
			}
		}
	}else {
		Write-Host "Cannot find chocoInstall.txt."
	}
}

# Update choco
Function UpdateChoco {
	Write-Host "Updating chocolatey..."
	$error.clear()
	try { choco }
	catch { Write-Host "Chocolatey is not installed." }
	if (!$error) {
		choco upgrade chocolatey -y
		choco upgrade all -y
	}
}

Function DisableTransparency {
    Write-Host "Disabling Transparency"
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Type Dword -Value 0
}

## Set Gaming Performance to high priority
Function GamingRegSet{
	if ((Test-Path ${env:ProgramFiles(x86)}\Steam\)) # Assumption: If steam is not installed then there's no point adjusting PC performance for gaming
	{
		Write-Output "Set gaming performance to high priority..."
		Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Scheduling Category" -Type String -Value "High"
		Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "SFIO Priority" -Type String -Value "High"
		Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Background Only" -Type String -Value "False"
		Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Priority" -Type DWord -Value 6
		Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Type DWord -Value 0
		Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Type DWord -Value 0xFFFFFFFF
	}
	else {
		Write-Host "Steam is not installed. Assuming gaming performance registry tweaks are not needed."
	}
}
