function New-AceDatabase
{
    param
    (
        [Parameter(Mandatory)]
        [string]
        $DockerPath,

        [Parameter(Mandatory)]
        [string]
        $Password
    )

    Set-Location $DockerPath

    docker build -t ace/mssql-server-windows -f "$($DockerPath)\dockerfile" .
    docker run -d --name ace-sql -p 1433:1433 -e "sa_password=$($Password)" ace/mssql-server-windows

    $props = @{ConnectionString = "Server=$(docker inspect --format="{{.NetworkSettings.Networks.nat.IPAddress}}" ace-sql);Database=ACEWebService;User Id=sa;Password=$($Password);MultipleActiveResultSets=true"}
    
    $obj = New-Object -TypeName psobject -Property $props

    Write-Output $obj
}