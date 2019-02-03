$file = "$psscriptroot\chocoInstall.txt"
if (Test-Path $file) {
    $programs = [string[]](Get-Content $file | Select-Object -Skip 3)
    if (!($programs.count -eq 0)) {
        $notInstalled = @()
        ForEach ($i in $programs) {
            if (choco upgrade $i --noop | Select-String -Pattern "is not installed. Installing..."){
                $notInstalled += $i
            }
            else {
                Write-Host "$i is already installed."
            }
        }
        
        if (!($notInstalled.count -eq 0)){
            Write-Host "Found programs in chocoInstall.txt that are not installed: " $notInstalled
            Write-Host -NoNewline "Install? (Y/N)"
            $response = read-host
            if ( $response -ne "Y" ) { return; }
            
            ForEach ($j in $notInstalled) {
                choco install $j -y
            }
        }
    }
}else {
    Write-Host "Cannot find chocoInstall.txt."
}
