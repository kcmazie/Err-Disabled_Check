
<#==============================================================================
         File Name : Err-Disabled_Check.ps1
   Original Author : Kenneth C. Mazie (kcmjr AT kcmjr.com)
                   : 
       Description : This script is designed to work on Cisco switches.  Using the 
                   : Rensi PowerShell SSH module the script remotes into a switch
                   : and executes a "SHOW INTERFACE STATUS | I ERR" command.  The
                   : returned text is parsed and if any port is in an error-disabled
                   : state the port number is displayed on screen.  This script strictly
                   : reports, it does nothing to reset detected ports.
                   : 
             Notes : Normal operation is with no command line options.  It is recommended 
                   : that pre-stored ENCRYPTED credentials are used.  The routine to encrypt
                   : the password in the external config file can be found here: 
                   : https://github.com/kcmazie/CredentialsWithKey.  If stored creds are 
                   : not used a pop-up prompt will ask for the firewall logon credentials 
                   : at each run.  Some debugging options exist and can be activated 
                   : changing the option from $False to $True within the script.  If the
                   : script is run from an editor that is detected and the extra console
                   : messages are automatically enabled.  An external XML file named the
                   : same as the script is required to enter the details of your environment.
                   : Also a flat text file named "IPLIST.TXT" is required to feed in switch 
                   : IP addresses, one entry per line.  To exclude any IP start the line 
                   : with #.
                   :
      Requirements : The Rensi PowerShell SSH module is required.  If not detected the module 
                   : will be automatically installed during the first run.  A minimum PowerShell
                   : version of 5.1 is required.  PS version 7 will not work.  
                   : 
   Option Switches : $Console - If Set to $true will display status during run (Defaults to 
                   :            $True)
                   : $Debug - If set to $true adds extra output on screen.  Forces console 
                   :          option to "true" (Defaults to $false)
                   :
          Warnings : None.
                   :   
             Legal : Public Domain. Modify and redistribute freely. No rights reserved.
                   : SCRIPT PROVIDED "AS IS" WITHOUT WARRANTIES OR GUARANTEES OF 
                   : ANY KIND. USE AT YOUR OWN RISK. NO TECHNICAL SUPPORT PROVIDED.
                   : That being said, feel free to ask if you have questions...
                   :
           Credits : Code snippets and/or ideas came from many sources including but 
                   : not limited to the following:
                   : 
    Last Update by : Kenneth C. Mazie                                           
   Version History : v1.00 - 09-25-25 - Original 
    Change History : v1.10 - 10-17-25 - Added compensation for "permission denigned" response.  
                   :                    Added a try/catch for key exchange failure to retry
                   :                    using the -FORCE option. 
                   : v1.20 - 01-13-26 - Added code to clear out old keys from trusted host list
                   :                    when a key exchange failure occurs.
                   : v1.30 - 06-12-26 - Edited IP list to eliminate duplicate entries.
                   : #>
                   $ScriptVer = "1.30"    <#--[ Current version # used in script ]--
                   :                
==============================================================================#>
Clear-Host
#Requires -version 5

#--[ RUNTIME OPTION VARIATIONS ]-----------------------------------------------
$Console = $true
$Debug = $false #True

If($Debug){
    $Console = $true
}

#==============================================================================
#==[ Functions ]===============================================================

Function StatusMsg ($Msg, $Color, $ExtOption){
    If ($Null -eq $Color){
        $Color = "Magenta"
    }
    If ($ExtOption.Console){
        Write-Host "-- Script Status: " -NoNewline -ForegroundColor "Magenta"
        Write-host $Msg -ForegroundColor $Color
        }
    $Msg = ""
}

Function GetConsoleHost ($ExtOption){  #--[ Detect if we are using a script editor or the console ]--
    Switch ($Host.Name){
        'consolehost'{
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $False -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleMessage" -Value "PowerShell Console detected." -Force
        }
        'Windows PowerShell ISE Host'{
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $True -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleMessage" -Value "PowerShell ISE editor detected." -Force
        }
        'PrimalScriptHostImplementation'{
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $True -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "COnsoleMessage" -Value "PrimalScript or PowerShell Studio editor detected." -Force
        }
        "Visual Studio Code Host" {
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $True -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleMessage" -Value "Visual Studio Code editor detected." -Force
        }
    }
    If ($ExtOption.ConsoleState){
        StatusMsg "Detected session running from an editor..." "Magenta" $ExtOption
    }
    Return $ExtOption
}

Function PrepCredentials ($ExtOption){
    #--[ Prepare SSH Credentials ]--
    $UN = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name 
   	If ($Null -eq $ExtOption.Password){
        $Base64String = Get-Content ($ExtOption.CredDrive+$ExtOption.KeyFile)
	    $ByteArray = [System.Convert]::FromBase64String($Base64String)
	    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UN, ((Get-Content ($ExtOption.CredDrive+$ExtOption.PasswordFile)) | ConvertTo-SecureString -Key $ByteArray)
	    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Credential" -Value $Credential
    }Else{
	    $Credential = $Host.ui.PromptForCredential("Enter your credentials","Please enter your UserID and Password.","","")
	    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Credential" -Value $Credential
    }
    Return $ExtOption
}

Function LoadConfig ($ExtOption,$ConfigFile){  #--[ Read and load configuration file ]-------------------------------------
    StatusMsg "Loading external config file..." "Magenta" $ExtOption
    if (Test-Path -Path $ConfigFile -PathType Leaf){                       #--[ Error out if configuration file doesn't exist ]--
        [xml]$Config = Get-Content $ConfigFile  #--[ Read & Load XML ]--    
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Domain" -Value $Config.Settings.General.Domain  
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "EmailRecipient" -Value $Config.Settings.Email.EmailRecipient
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "SmtpServer" -Value $Config.Settings.Email.SmtpServer
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "EmailAltRecipient" -Value $Config.Settings.Email.EmailAltRecipient
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "EmailSender" -Value $Config.Settings.Email.EmailSender
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "EmailEnable" -Value $Config.Settings.Email.EmailEnable
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "CredDrive" -Value $Config.Settings.Credentials.CredDrive
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "PasswordFile" -Value $Config.Settings.Credentials.PasswordFile
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "KeyFile" -Value $Config.Settings.Credentials.KeyFile
    }Else{
        StatusMsg "MISSING XML CONFIG FILE.  File is required.  Script aborted..." " Red" $True
        $Message = (
'--[ External XML config file example ]-----------------------------------
--[ To be named the same as the script and located in the same folder as the script ]--
--[ Email settings in example are for future use.                                   ]--

<?xml version="1.0" encoding="utf-8"?>
<Settings>
    <General>
        <Domain>company.org</Domain>
    </General>
    <Credentials>
		<CredDrive>c:</CredDrive>
		<PasswordFile>\Users\me\documents\Password.txt<PasswordFile>
		<KeyFile>\Users\me\documents\key.txt</KeyFile>
	</Credentials>
	<Email>
		<EmailEnable>$true</EmailEnable>
		<EmailSender>some_email@company.org</EmailSender>
        <SmtpServer>mailhost.company.org</SmtpServer>
        <SmtpPort>25</SmtpPort>
        <EmailRecipient>my_email@company.org</EmailRecipient>
    	<EmailAltRecipient>your_email@compnay.org</EmailAltRecipient>
    </Email>
</Settings>  ')
        Write-host $Message -ForegroundColor Yellow
    }
    Return $ExtOption
}

Function SSHConnect ($IP, $ExtOption){  #--[ Perform the SSH Connection ]--
    $ErrorActionPreference = "Stop"
    Get-SSHSession | Select-Object SessionId | Remove-SSHSession | Out-Null  #--[ Remove any existing sessions ]--
    Try{
        New-SSHSession -ComputerName $IP -AcceptKey -Credential $ExtOption.Credential | Out-Null
    }Catch{
        $Exception = $_.Exception.Message
        $ErrorMsg = $_.Error.Message
        StatusMsg "-- SSH Failure: ($IP)" "Red" $ExtOption
        If ($Exception -like "*Permission*"){
            StatusMsg "-- Exception Msg: $Exception" "Red" $ExtOption
            StatusMsg "-- Exception Msg: $Exception" "Red" $ExtOption
            Return
        }Else{ 
            StatusMsg "-- Exception Msg: $Exception" "Red" $ExtOption
            StatusMsg "--     Error Msg: $ErrorMsg" "Red" $ExtOption
            StatusMsg " Retrying with -FORCE option..." "Yellow" $ExtOption
            Get-SSHTrustedHost -HostName $IP | Remove-SSHTrustedHost -HostName $IP  #--[ Remove any existing trusted host entry ]--
            New-SSHSession -ComputerName $IP -AcceptKey -Credential $ExtOption.Credential -force | Out-Null
        }
    }
    $Session = Get-SSHSession -Index 0 
    $Stream = $Session.Session.CreateShellStream("dumb", 0, 0, 0, 0, 1000)  #--[ Creates a dumb terminal session ]--
    $Stream.Read() | Out-Null
    $Command = 'terminal length 512'        #--[ Set the terminal length to 512 lines ]--
    $Stream.Write("`n `n `n")
    $Stream.Write("$Command`n")
    $Command = 'sh int status'
    $Stream.Write("`n `n `n")
    $Stream.Write("$Command`n")
    Start-Sleep -millisec 100 
    $ResponseRaw = $Stream.Read()
    $Response = $ResponseRaw -split "`r`n" | ForEach-Object{$_.trim()}    
    $Count = 0   
    While ((($Response[$Response.Count -1]) -notlike '*#')){
        Start-Sleep -millisec 50
        $ResponseRaw = $Stream.Read()   
        $Response = $ResponseRaw -split "`r`n" | ForEach-Object{$_.trim()}
        If (($ResponseRaw -like "*--*") -or ($Count -gt 20 )){Break}
        $Count++
    }        
    $Stream.Exit  
    Return $Response 
}

Function InstallModules {
    if (!(Get-Module -Name posh-ssh*)) {    
        Try{  
            import-module -name posh-ssh
        }Catch{
            Write-host "-- Error loading Posh-SSH module." -ForegroundColor Red
            Write-host "Error: " $_.Error.Message  -ForegroundColor Red
            Write-host "Exception: " $_.Exception.Message  -ForegroundColor Red
        }
    }
}

Function ShowVariables ($ExtOption,$Color){
    If ($Null -eq $Color){$Color = "Cyan"}
    Foreach ($Property in $ExtOption.psobject.Properties) {
        Write-Host $($property.Name).PadRight(18," ") -ForegroundColor Yellow -NoNewline
        Write-host "= " -NoNewline
        Write-host $($property.Value) -ForegroundColor $Color
    }
}
#==[ End of Functions ]===================================================

#==[ Begin ]============================================================== 
InstallModules  #--[ Load required PowerShell modules ]--
$ScriptName = ($MyInvocation.MyCommand.Name).Replace(".ps1","" ) 
$ConfigFile = $PSScriptRoot+"\"+$ScriptName+".xml"

#--[ Load external XML options file into custom runtime object ]--
$ExtOption = New-Object -TypeName psobject   #--[ Object to hold runtime options ]--
$ExtOption = LoadConfig $ExtOption $ConfigFile
$ExtOption = GetConsoleHost $ExtOption       #--[ Detect Runspace ]--
$ExtOption = PrepCredentials $ExtOption      #--[ Get Credentials ]--

#--[ Additional runtime variations into options object ]--
If ($Console){
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Console" -Value $True
} 
If ($Debug){
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Debug" -Value $True
    StatusMsg "--[ Debug mode: Option File Contents ]---------------------" "Yellow" $ExtOption
    ShowVariables $ExtOption "Yellow"
}

StatusMsg "--[ Beginning Run ]------------------------------------" "Yellow" $ExtOption 
$ListFileName = "$PSScriptRoot\IPlist.txt"
If (Test-Path -Path $ListFileName){  #--[ Verify that a text file exists and pull IP's from it. ]--
    $IPList = (Get-Content $ListFileName) | Sort-Object -Unique
    $IPCount = $IPList.count
    StatusMsg "$IPCount devices identified..." "Green" $ExtOption
    $ErrorActionPreference = "stop"
    StatusMsg "Processing IP list... " "Green" $ExtOption
    ForEach ($IP in $IPList){
        Try {
            $Hostname = ((Resolve-DnsName $IP).NameHost).Split(".")[0]
        }Catch{
            $Hostname = "[No DNS Record]"
        }

        If ($IP -notlike "*#*"){            
            $Result = ""
            If (Test-Connection -ComputerName $IP -count 1 -BufferSize 16 -Quiet) {
            #==[ Execute SSH ]===========================
            StatusMsg "Calling SSH for $Hostname ($IP)" "Cyan" $ExtOption
            $Result = SSHConnect $IP $ExtOption
            #============================================
                ForEach ($Line in $Result){
                    If ($Line -like "*err-*"){
                        $Line = [regex]::Replace($Line, "\s+", " ")
                        $ErrorActionPreference = "silentlycontinue"
                        StatusMsg "-- $Line" "Yellow" $ExtOption
                        $ErrorActionPreference = "stop"
                    }
                }
            }Else{
                StatusMsg "--- $IP is offline ---" "Red" $ExtOption
            }
        }Else{
            $Msg = $IP.Split("#")[1]+" is on the bypass list..."
            StatusMsg $Msg "Blue" $ExtOption
        }
    }  #>
}

Write-Host ""
StatusMsg "--- COMPLETED ---" "red" $ExtOption