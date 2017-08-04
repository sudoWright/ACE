function New-AceWebsite
{
    param
    (
        [Parameter(Mandatory)]
        [string]
        $DockerPath,

        [Parameter(Mandatory)]
        [string]
        $ConnectionString,

        [Parameter(Mandatory)]
        [string]
        $RabbitMQUserName,

        [Parameter(Mandatory)]
        [string]
        $RabbitMQPassword,

        [Parameter()]
        [string]
        $EncryptionPassphrase = 'P@ssw0rd!'
    )

    Set-Location $DockerPath
    
    $AppSettings = Get-Content "$($DockerPath)\ACEWebService\appsettings.Production.json" | ConvertFrom-Json
    $AppSettings.ConnectionStrings.DefaultConnection = $ConnectionString
    #$AppSettings.RabbitMQServer = $RabbitMQServer
    $AppSettings.RabbitMQUserName = $RabbitMQUserName
    $AppSettings.RabbitMQPassword = $RabbitMQPassword
    $AppSettings.EncryptionPassphrase = $EncryptionPassphrase
    $AppSettings | ConvertTo-Json | Out-File "$($DockerPath)\ACEWebService\appsettings.Production.json"

    docker build -t ace/iis-aspnetcore -f "$($DockerPath)\dockerfile" .
    docker run --name ace-webservice -d -it -p 80:80 -p 443:443 ace/iis-aspnetcore
    
    Start-Sleep -Seconds 3
    
    Start-Process "https://$(docker inspect --format="{{.NetworkSettings.Networks.nat.IPAddress}}" ace-webservice)/index.html"
}