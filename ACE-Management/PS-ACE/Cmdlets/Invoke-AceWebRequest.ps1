function Invoke-AceWebRequest
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Uri,

        [Parameter(Mandatory = $true)]
        [string]
        $ApiKey,

        [Parameter()]
        [ValidateSet('Delete','Get','Post','Put')]
        [string]
        $Method = 'Get',

        [Parameter()]
        [string]
        $ContentType = 'application/json',

        [Parameter()]
        [string]
        $Body,

        [Parameter()]
        [switch]
        $CheckCert
    )
    Try
    {
        # Create web request
        $WebRequest = [System.Net.WebRequest]::Create($Uri)
    
        $WebRequest.Headers.Add('X-API-Version:1.0')
        $webrequest.Headers.Add("X-ApiKey:$($ApiKey)")

        $WebRequest.Method = $Method
        $WebRequest.ContentType = $ContentType

        if($CheckCert)
        {
            # Set the callback to check for null certificate and thumbprint matching.
            $WebRequest.ServerCertificateValidationCallback = {
        
                $ThumbPrint = 'BEA586E6FA3984D0B2935E10007352E092C37103'
        
                $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]$args[1]
                
                if ($certificate -eq $null)
                {
                    $Host.UI.WriteWarningLine("Null certificate.")
                    return $true
                }
        
                if ($certificate.Thumbprint -eq $ThumbPrint)
                {
                    return $true
                }
                else
                {
                    $Host.UI.WriteWarningLine("Thumbprint mismatch. Certificate thumbprint $($certificate.Thumbprint)")
                }
        
                return $false
            }
        }

        if($PSBoundParameters.ContainsKey('Body'))
        {
            $byteArray = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $Webrequest.ContentLength = $byteArray.Length
            
            $dataStream = $Webrequest.GetRequestStream()            
            $dataStream.Write($byteArray, 0, $byteArray.Length)
            $dataStream.Close()
        }

        # Get response stream
        $ResponseStream = $webrequest.GetResponse().GetResponseStream()
    
        # Create a stream reader and read the stream returning the string value.
        $StreamReader = New-Object System.IO.StreamReader -ArgumentList $ResponseStream
        $StreamReader.ReadToEnd()

        $StreamReader.Close()
        $ResponseStream.Close()
    }
    catch
    {
        Write-Error "Failed: $($_.exception.innerexception.message)"
    }
}