# Accepts a list of computer names (default: all local IP addresses) 
# and a list of ports to test.
Param(
    [String[]]$ComputerName = $(Get-NetIPAddress | Select-Object -ExpandProperty IPAddress),
    [int[]]$Ports = @(80,135,443,3389)
)

# ScriptBlock that performs the connectivity test.
# If Port <= 0, it performs a simple ping-style Test-NetConnection.
# Otherwise, it tests the specific port.
$PingTest = {
    Param(
        [String]$Target,
        [Int]$Port
    )

    # If Port <= 0, treat as a ping-style test
    if ($Port -le 0) {
        # Use Test-Connection with a short timeout
        try {
            $Result = Test-Connection -ComputerName $Target -Count 1 -Quiet
        } catch {
            $Result = $false
        }
        Write-Output $Result
        return
    }

    # Fast TCP port test with custom timeout
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($Target, $Port, $null, $null)

        # Timeout in milliseconds (adjust as needed)
        $wait = $async.AsyncWaitHandle.WaitOne(800)

        if (-not $wait) {
            # Timeout hit
            $client.Close()
            Write-Output $false
        } else {
            $client.EndConnect($async)
            $client.Close()
            Write-Output $true
        }
    } catch {
        Write-Output $false
    }
}
# Holds all background jobs created for parallel testing
$TaskList = @()

# Iterate through each target computer/IP
ForEach($Target in $ComputerName){

    # If multiple ports are provided, test each port individually
    If($Ports.length -ge 2){
        ForEach($Port in $Ports){
            # Start a background job for each port test
            $TaskList += Start-Job -Name $($Target+"_"+$Port) -ScriptBlock $PingTest -ArgumentList $Target,$Port
        }

    # If exactly one port is provided, test that port AND a no-port test (-1)
    }If($Ports.length -eq 1){
        # Start job for single port and ping-style test
        $TaskList += Start-Job -Name $($Target+"_"+$Port) -ScriptBlock $PingTest -ArgumentList $Target,$Ports

    # If no ports are provided, run a single ping-style test
    }
    $TaskList += Start-Job -Name $Target -ScriptBlock $PingTest -ArgumentList $Target
}

$Report = @()

# Collect results from all jobs, waiting for completion,
# and automatically removing each job afterward.
Get-Job | ForEach-Object{
    $Results = New-Object -TypeName psobject -Property @{
        'Name'=$($_.Name).Split('_')[0]
        'Port'=$($_.Name).Split('_')[1]
    }
    If(Receive-Job -Job $_ -Wait -AutoRemoveJob){
        Write-Host -ForegroundColor Green "[!] $($_.Name)"
        $Results | Add-Member -MemberType NoteProperty -Name Status -Value $true
    }else{
        Write-Host -ForegroundColor Red "[x] $($_.Name)"
        $Results | Add-Member -MemberType NoteProperty -Name Status -Value $false
    }
    $Report += $Results
}

Write-Output $Report
