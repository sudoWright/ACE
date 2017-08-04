function Get-AceSweep
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [string]
        $Uri,

        [Parameter(Mandatory)]
        [string]
        $ApiKey,

        [Parameter()]
        [Guid]
        $Id
    )

    if ($PSBoundParameters.ContainsKey('Id'))
    {
        $Url = "$($Uri)/ace/sweep/$($Id)"
    }
    else
    {
        $Url = "$($Uri)/ace/sweep"
    }

    try
    {
        $result = Invoke-AceWebRequest -Method Get -Uri $Url -ApiKey $ApiKey -CheckCert -ErrorAction Stop
        Write-Output ($result | ConvertFrom-Json)        
    }
    catch
    {
        
    }
}