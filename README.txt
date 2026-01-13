# Err-Disabled_Check
A PowerShell SSH script to detect Cisco switch ports in Err-Disabled state.

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
                   : $Debug   - If set to $true adds extra output on screen.  Forces console 
                   :            option to "true" (Defaults to $false)
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
                   : #>
                   $ScriptVer = "1.20"    <#--[ Current version # used in script ]--
