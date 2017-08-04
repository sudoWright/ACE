param
(
    [Parameter(Mandatory)]
    [string]
    $DnsName,

    [Parameter(Mandatory)]
    [string]
    $Passphrase
)

function Get-HostsFile {
<#
.SYNOPSIS

Parses a HOSTS file.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause
Required Dependencies: None
Optional Dependencies: None

.PARAMETER Path

Specifies an alternate HOSTS path. Defaults to
%SystemRoot%\System32\drivers\etc\hosts.

.PARAMETER Show

Opens the HOSTS file in notepad upon completion.

.EXAMPLE

Get-HostsFile

.EXAMPLE

Get-HostsFile -Path .\hosts
#>

    Param (
        [ValidateScript({Test-Path $_})]
        [String]
        $Path = (Join-Path $Env:SystemRoot 'System32\drivers\etc\hosts'),

        [Switch]
        $Show
    )

    $Hosts = Get-Content $Path -ErrorAction Stop

    $CommentLine = '^\s*#'
    $HostLine = '^\s*(?<IPAddress>\S+)\s+(?<Hostname>\S+)(\s*|\s+#(?<Comment>.*))$'

    $TestIP = [Net.IPAddress] '127.0.0.1'
    $LineNum = 0

    for ($i = 0; $i -le $Hosts.Length; $i++) {
        if (!($Hosts[$i] -match $CommentLine) -and ($Hosts[$i] -match $HostLine)) {
            $IpAddress = $Matches['IPAddress']
            $Comment = ''

            if ($Matches['Comment']) {
                $Comment = $Matches['Comment']
            }

            $Result = New-Object PSObject -Property @{
                LineNumber = $LineNum
                IPAddress = $IpAddress
                IsValidIP = [Net.IPAddress]::TryParse($IPAddress, [Ref] $TestIP)
                Hostname = $Matches['Hostname']
                Comment = $Comment.Trim(' ')
            }

            $Result.PSObject.TypeNames.Insert(0, 'Hosts.Entry')

            Write-Output $Result
        }

        $LineNum++
    }

    if ($Show) {
        notepad $Path
    }
}

function New-HostsFileEntry {
<#
.SYNOPSIS

Replace or append an entry to a HOSTS file.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause
Required Dependencies: Get-HostsFile
Optional Dependencies: None

.PARAMETER IPAddress

Specifies the IP address to which the specified hostname will resolve.

.PARAMETER Hostname

Specifies the hostname that should resolve to the specified IP address.

.PARAMETER Comment

Optionally, specify a comment to be added to the HOSTS entry.

.PARAMETER Path

Specifies an alternate HOSTS path. Defaults to
%SystemRoot%\System32\drivers\etc\hosts.

.PARAMETER PassThru

Outputs a parsed HOSTS file upon completion.

.PARAMETER Show

Opens the HOSTS file in notepad upon completion.

.EXAMPLE

New-HostsFileEntry -IPAddress '127.0.0.1' -Hostname 'c2.evil.com'

.EXAMPLE

New-HostsFileEntry -IPAddress '127.0.0.1' -Hostname 'c2.evil.com' -Comment 'Malware C2'
#>

    [CmdletBinding()] Param (
        [Parameter(Mandatory = $True, Position = 0)]
        [Net.IpAddress]
        $IPAddress,

        [Parameter(Mandatory = $True, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Hostname,

        [Parameter(Position = 2)]
        [ValidateNotNull()]
        [String]
        $Comment,

        [ValidateScript({Test-Path $_})]
        [String]
        $Path = (Join-Path $Env:SystemRoot 'System32\drivers\etc\hosts'),

        [Switch]
        $PassThru,

        [Switch]
        $Show
    )

    $HostsRaw = Get-Content $Path
    $Hosts = Get-HostsFile -Path $Path

    $HostEntry = "$IpAddress $Hostname"

    if ($Comment) {
        $HostEntry += " # $Comment"
    }

    $HostEntryReplaced = $False

    for ($i = 0; $i -lt $Hosts.Length; $i++) {
        if ($Hosts[$i].Hostname -eq $Hostname) {
            if ($Hosts[$i].IpAddress -eq $IPAddress) {
                Write-Verbose "Hostname '$Hostname' and IP address '$IPAddress' already exist in $Path."
            } else {
                Write-Verbose "Replacing hostname '$Hostname' in $Path."
                $HostsRaw[$Hosts[$i].LineNumber] = $HostEntry
            }

            $HostEntryReplaced = $True
        }
    }

    if (!$HostEntryReplaced) {
        Write-Verbose "Appending hostname '$Hostname' and IP address '$IPAddress' to $Path."
        $HostsRaw += $HostEntry
    }

    $HostsRaw | Out-File -Encoding ascii -FilePath $Path -ErrorAction Stop

    if ($PassThru) { Get-HostsFile -Path $Path }

    if ($Show) {
        notepad $Path
    }
}

# Generate SSL Certificate
$SecurePass = ConvertTo-SecureString -String $Passphrase -AsPlainText -Force
$newCert = New-SelfSignedCertificate -DnsName $DnsName -CertStoreLocation Cert:\LocalMachine\My
Write-Output $newCert

# Update Thumbprint in appsettings.json
$AppSettings = Get-Content C:\inetpub\ACEWebService\appsettings.Production.json | ConvertFrom-Json
$AppSettings.Thumbprint = $newCert.Thumbprint
$AppSettings | ConvertTo-Json | Out-File C:\inetpub\ACEWebService\appsettings.Production.json

# Update Hosts field
New-HostsFileEntry -IPAddress $AppSettings.RabbitMQServer -Hostname rabbitmq.ace.local
New-HostsFileEntry -IPAddress $Appsettings.ConnectionStrings.DefaultConnection.Split('=')[1].Split(';')[0] -Hostname sql.ace.local

# Create Web Site
Import-Module IISAdministration
Get-IISSite | Remove-IISSite -Confirm:$false
New-IISSite -Name "ACEWebService" -PhysicalPath C:\inetpub\ACEWebService -BindingInformation "*:80:"

# Create Binding
$sm = Get-IISServerManager
$sm.Sites["ACEWebService"].Bindings.Add("*:443:", $newCert.GetCertHash(), "My", "0") | Out-Null
$sm.CommitChanges()

Start-Sleep -Seconds 10

# Start ACEWebService
Start-IISSite -Name ACEWebService