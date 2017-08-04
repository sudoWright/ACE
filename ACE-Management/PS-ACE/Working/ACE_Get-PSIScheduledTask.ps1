function Start-AceScript
{
    function ConvertTo-JsonV2 
    {
        param
        (
            $obj
        )
    
        Begin 
        {
            $null = [System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")
            $Serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        }

        Process 
        {
            try 
            {
                $Serializer.Serialize($Obj)
            } 
            catch 
            {
                Write-Error $_
            }    
        }
    }

    $obj = Get-PSIScheduledTask -ReturnHashtables
    
    $HostFQDN = Get-WmiObject Win32_ComputerSystem -Property 'Name','Domain' | ForEach-Object {"$($_.Name).$($_.Domain)"}

    foreach($o in $obj)
    {
        $o.Add('ComputerName', $HostFQDN)
        ConvertTo-JsonV2 -obj $o
    }
}


function Get-PSIScheduledTask {
<#
    .SYNOPSIS

        Returns detailed information about scheduled tasks.

        Author: Lee Christensen (@tifkin_), Jared Atkinson
        License: BSD 3-Clause
        Required Dependencies: None
        Optional Dependencies: None

#>
    [CmdletBinding()]
    Param (
        [switch]
        $ReturnHashtables
    )

    begin
    {
        # Based on Get-ScheduledTask in the Windows 7 Resource Kit PowerShell Pack
        function Get-DIGSScheduledTaskData
        {
        <#
        .Synopsis
            Gets tasks scheduled on the computer
        .Description
            Gets scheduled tasks that are registered on a computer
        .Example
            Get-ScheduleTask -Recurse
        #>
        param(
        # The name or name pattern of the scheduled task
        [Parameter()]
        $Name = "*",
    
        # The folder the scheduled task is in
        [Parameter()]
        [String[]]
        $Folder = "",
    
        # If this is set, hidden tasks will also be shown.  
        # By default, only tasks that are not marked by Task Scheduler as hidden are shown.
        [Switch]
        $Hidden,    
    
        # The name of the computer to connect to.
        $ComputerName,
    
        # The credential used to connect
        [Management.Automation.PSCredential]
        $Credential,
    
        # If set, will get tasks recursively beneath the specified folder
        [switch]
        $Recurse
        )
    
        process {
            $scheduler = New-Object -ComObject Schedule.Service
            if ($Credential) { 
                $NetworkCredential = $Credential.GetNetworkCredential()
                $scheduler.Connect($ComputerName, 
                    $NetworkCredential.UserName, 
                    $NetworkCredential.Domain, 
                    $NetworkCredential.Password)            
            } else {
                $scheduler.Connect($ComputerName)        
            }    
                
            $taskFolder = $scheduler.GetFolder($folder)
            $taskFolder.GetTasks($Hidden -as [bool]) | Where-Object {
                $_.Name -like $name
            }
            if ($Recurse) {
                $taskFolder.GetFolders(0) | ForEach-Object {
                    $psBoundParameters.Folder = $_.Path
                    Get-DIGSScheduledTaskData @psBoundParameters
                }
            }        
        }
    }

        # Thanks to https://p0w3rsh3ll.wordpress.com/2015/02/05/backporting-the-get-filehash-function/
        function Get-DIGSFileHash
        {
	    [CmdletBinding(DefaultParameterSetName = "Path")]
	    param(
		    [Parameter(Mandatory=$true, ParameterSetName="Path", Position = 0)]
		    [System.String[]]
		    $Path,

		    [Parameter(Mandatory=$true, ParameterSetName="LiteralPath", ValueFromPipelineByPropertyName = $true)]
		    [Alias("PSPath")]
		    [System.String[]]
		    $LiteralPath,
	
		    [Parameter(Mandatory=$true, ParameterSetName="Stream")]
		    [System.IO.Stream]
		    $InputStream,

		    [ValidateSet("SHA1", "SHA256", "SHA384", "SHA512", "MACTripleDES", "MD5", "RIPEMD160")]
		    [System.String]
		    $Algorithm="SHA256"
	    )

	    begin
	    {
		    # Construct the strongly-typed crypto object
		    $hasher = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
	    }

	    process
	    {
		    if($PSCmdlet.ParameterSetName -eq "Stream")
		    {
			    Get-DIGSStreamHash -InputStream $InputStream -RelatedPath $null -Hasher $hasher
		    }
		    else
		    {
			    $pathsToProcess = @()
			    if($PSCmdlet.ParameterSetName  -eq "LiteralPath")
			    {
				    $pathsToProcess += Resolve-Path -LiteralPath $LiteralPath | Foreach-Object { $_.ProviderPath }
			    }
			    if($PSCmdlet.ParameterSetName -eq "Path")
			    {
				    $pathsToProcess += Resolve-Path $Path | Foreach-Object { $_.ProviderPath }
			    }

			    foreach($filePath in $pathsToProcess)
			    {
				    if(Test-Path -LiteralPath $filePath -PathType Container)
				    {
					    continue
				    }

				    try
				    {
					    # Read the file specified in $FilePath as a Byte array
					    [system.io.stream]$stream = [system.io.file]::OpenRead($filePath)
					    Get-DIGSStreamHash -InputStream $stream  -RelatedPath $filePath -Hasher $hasher
				    }
				    catch [Exception]
				    {
					    $errorMessage = 'FileReadError {0}:{1}' -f $FilePath, $_
					    Write-Error -Message $errorMessage -Category ReadError -ErrorId "FileReadError" -TargetObject $FilePath
					    return
				    }
				    finally
				    {
					    if($stream)
					    {
						    $stream.Close()
					    }
				    }                            
			    }
		    }
	    }
    }

        function Get-DIGSStreamHash
        {
	    param(
		    [System.IO.Stream]
		    $InputStream,

		    [System.String]
		    $RelatedPath,

		    [System.Security.Cryptography.HashAlgorithm]
		    $Hasher)

	    # Compute file-hash using the crypto object
	    [Byte[]] $computedHash = $Hasher.ComputeHash($InputStream)
	    [string] $hash = [BitConverter]::ToString($computedHash) -replace '-',''

	    if ($RelatedPath -eq $null)
	    {
		    $retVal = [PSCustomObject] @{
			    Algorithm = $Algorithm.ToUpperInvariant()
			    Hash = $hash
		    }
		    $retVal.psobject.TypeNames.Insert(0, "Microsoft.Powershell.Utility.FileHash")
		    $retVal
	    }
	    else
	    {
		    $retVal = [PSCustomObject] @{
			    Algorithm = $Algorithm.ToUpperInvariant()
			    Hash = $hash
			    Path = $RelatedPath
		    }
		    $retVal.psobject.TypeNames.Insert(0, "Microsoft.Powershell.Utility.FileHash")
		    $retVal

	    }
    }

        function Get-ClassID
        {
            param($ClassId)
  
            $Value = Get-ItemProperty "HKLM:\Software\Classes\CLSID\$($ClassId)\InprocServer32" -Name "(Default)" -ErrorAction SilentlyContinue
            if($Value) {
                $Value.'(Default)'
            } else {
                ''
            }
        }  
    }

    process
    {
        $Tasks = Get-DIGSScheduledTaskData -Recurse

        foreach($Task in $Tasks)
        {
            $ActionComClassId = $null
            $ActionComDll = $null
            $ActionComDllMD5 = $null
            $ActionComDllSHA256 = $null
            $ActionComData = $null
            $ActionExecCommand = $null
            $ActionExecCommandMD5 = $null
            $ActionExecCommandSHA256 = $null
            $ActionExecArguments = $null
            $ActionExecWorkingDirectory = $null
                
            $Xml = [Xml]$Task.Xml
    
            $ActionCom = $Xml.Task.Actions.ComHandler
            $ActionComDll = if($ActionCom.ClassId) { Get-ClassID ($ActionCom.ClassId)} else { $null }
        
            if($ActionComDll)
            {
                $ActionComDllMD5 =  (Get-DIGSFileHash -Path $ActionComDll -Algorithm MD5).Hash
                $ActionComDllSHA256 = (Get-DIGSFileHash -Path $ActionComDll -Algorithm SHA256).Hash
            }
            $ActionComData = if($ActionCom.Data) { $ActionCom.Data.InnerXml} else {$null}

            $ActionExec = $Xml.Task.Actions.Exec
            if($ActionExec.Command)
            {
                $ActionExecPath = [System.Environment]::ExpandEnvironmentVariables($ActionExec.Command)
            
                $CleanedPath = $ActionExecPath.Replace("`"", "")
                if(Test-Path $CleanedPath -ErrorAction SilentlyContinue)
                {
                    $ActionExecCommandMD5 = (Get-DIGSFileHash -Path $CleanedPath -Algorithm MD5).Hash
                    $ActionExecCommandSHA256 = (Get-DIGSFileHash -Path $CleanedPath -Algorithm SHA256).Hash
                }
            }

            $Output = @{
                Name = $Task.Name
                Path = $Task.Path
                Enabled = $Task.Enabled
                LastRunTime = $Task.LastRunTime
                LastTaskResult = $Task.LastTaskResult
                NumberOfMissedRuns = $Task.NumberOfMissedRuns
                NextRunTime = $Task.NextRunTime
                Xml = $Task.Xml
                ActionComClassId = $ActionCom.ClassId
                ActionComDll = $ActionComDll
                ActionComDllMD5 = $ActionComDllMd5
                ActionComDllSHA256 = $ActionComDllSHA256
                ActionComData = $ActionComData
                ActionExecCommand = $ActionExec.Command
                ActionExecCommandMD5 = $ActionExecCommandMD5
                ActionExecCommandSHA256 = $ActionExecCommandSHA256
                ActionExecArguments = $ActionExec.Arguments
                ActionExecWorkingDirectory = $ActionExec.WorkingDirectory
            }

            if($ReturnHashtables) {
                $Output
            } else {
                New-Object PSObject -Property $Output
            }
        }
    }

    end
    {

    }
}