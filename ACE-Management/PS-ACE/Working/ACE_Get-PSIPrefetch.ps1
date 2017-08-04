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

    $obj = Get-PSIPrefetch -ReturnHashtables
    
    $HostFQDN = Get-WmiObject Win32_ComputerSystem -Property 'Name','Domain' | ForEach-Object {"$($_.Name).$($_.Domain)"}

    foreach($o in $obj)
    {
        $o.Add('ComputerName', $HostFQDN)
        ConvertTo-JsonV2 -obj $o
    }
}


function Get-PSIPrefetch {
<#
    .SYNOPSIS

        Return prefetch file information.

        Author: Jared Atkinson, Lee Christensen (@tifkin_)
        License: BSD 3-Clause
        Required Dependencies: None
        Optional Dependencies: None

#>

    [CmdletBinding()]
    param
    (
        [Parameter()]
        [string]
        $Path,

        [switch]
        $ReturnHashtables
    )

    begin
    {
        if($PSBoundParameters.ContainsKey('Path'))
        {
            $props = @{FullName = $Path}
            $files = New-Object -TypeName psobject -Property $props
        }
        else
        {
            $files = Get-ChildItem -Path C:\Windows\Prefetch\* -Include *.pf
        }
    }

    process
    {
        foreach($file in $files)
        {
            $bytes = Get-Content -Path $file.FullName -Encoding Byte
        
            # Check for Prefetch file header 'SCCA'
            if([System.Text.Encoding]::ASCII.GetString($bytes[4..7]) -eq 'SCCA')
            {
                $Version = $bytes[0]
            
                switch($Version)
                {
                    0x11 # Windows XP
                    {
                        $AccessTimeBytes = $bytes[0x78..0x7F]
                        $RunCount = [BitConverter]::ToInt32($bytes, 0x90)
                    }
                    0x17 # Windows 7
                    {
                        $AccessTimeBytes = $bytes[0x80..0x87]
                        $RunCount = [BitConverter]::ToInt32($bytes, 0x98);
                    }
                    0x1A # Windows 8
                    {
                        $AccessTimeBytes = $bytes[0x80..0xBF]
                        $RunCount = [BitConverter]::ToInt32($bytes, 0xD0);
                    }
                }
            
                $Name = [Text.Encoding]::Unicode.GetString($bytes, 0x10, 0x3C).Split('\0')[0].TrimEnd("`0")
                $PathHash = [BitConverter]::ToString($bytes[0x4f..0x4c]).Replace("-","")
                $DeviceCount = [BitConverter]::ToInt32($bytes, 0x70)
                $DependencyString = [Text.Encoding]::Unicode.GetString($bytes, [BitConverter]::ToInt32($bytes, 0x64), [BitConverter]::ToInt32($bytes, 0x68)).Replace("`0",';').TrimEnd(';')
                $Dependencies = $DependencyString.Split(';')
                $Path = $Dependencies | Where-Object {$_ -like "*$($Name)"}
                $DependencyCount = $Dependencies.Length

                for($i = 0; $i -lt $AccessTimeBytes.Length; $i += 8)
                {
                    $Props = @{
                        Name = $Name
                        Path = $Path
                        PathHash = $PathHash
                        DependencyCount = $DependencyCount
                        PrefetchAccessTime = [DateTime]::FromFileTimeUtc([BitConverter]::ToInt64($AccessTimeBytes, $i))
                        DeviceCount = $DeviceCount
                        RunCount = $RunCount
                        DependencyFiles = $DependencyString
                    }

                    if($ReturnHashtables) {
                        $Props
                    } else {
                        New-Object -TypeName psobject -Property $Props
                    }
                }
            }
        }
    }

    end
    {

    }
}