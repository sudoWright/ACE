function Start-AceSweep
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [Guid[]]
        $ComputerId,

        [Parameter(Mandatory)]
        [Guid]
        $ScriptId,

        [Parameter(Mandatory)]
        [string]
        $Uri,

        [Parameter(Mandatory)]
        [string]
        $ApiKey
    )

    $body = @{
        ComputerId = $ComputerId
        ScriptId = $ScriptId
        Uri = $Uri
    }

    try
    {
        $result = Invoke-AceWebRequest -Method Post -Uri "$($Uri)/ace/sweep" -Body (ConvertTo-Json $body -Compress) -ContentType application/json -ApiKey $ApiKey -CheckCert
        Write-Output ($result | ConvertFrom-Json)   
    }
    catch
    {
        
    }
}