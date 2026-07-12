Begin {
    if ($PSScriptRoot) {
        $WorkingDirectory = $PSScriptRoot
    } else {
        if ((Get-Location).Path -like "*\Overseer") {
            $WorkingDirectory = Join-Path (Get-Location).Path "bin"
        } elseif ((Get-Location).Path -like "*\Overseer\bin") {
            $WorkingDirectory = (Get-Location).Path
        } else {
            throw "Unable to resolve working directory"
        }
    }

    Function Write-Eventlog{
        Param(
            [String]$EventType = "",
            [String]$Message = ""
        )
        # Create Eventlog
        $EventLog = $(Join-Path $(Join-Path $WorkingDirectory "..\LogFiles") "$($(get-Date).Day)_$($(get-Date).Month)_$($(get-Date).Year).txt")
        Write-Output "[$($(get-date).ToLongTimeString())][$EventType][$Message]" | Out-File -FilePath $EventLog -Append -Encoding ascii
    }
    
    Write-EventLog -EventType "START" -Message "Starting the Status Collector"

    # Load ENV data
    Get-Content (Join-Path (Join-Path $WorkingDirectory "..") ".env") | ForEach-Object {
        if ($_ -match "^\s*$" -or $_ -match "^\s*#") { return }

        $parts = $_ -split "=", 2
        $key   = $parts[0].Trim()
        $value = $parts[1].Trim()

        Set-Item -Path "Env:$key" -Value $value
    }    
    Write-EventLog -EventType "INFO" -Message "Loaded ENV Configuration Data"

    # Import correct SQLite module
    Add-Type -Path $(Join-Path $WorkingDirectory "\PSSQLite\1.1.0\x64\System.Data.SQLite.dll")
    $conn = New-Object System.Data.SQLite.SQLiteConnection
    $conn.ConnectionString = "Data Source=$($env:DATABASE_URL.Replace("sqlite:/",".."))"
    
    Write-EventLog -EventType "INFO" -Message "Connecting to SQL Database: $env:DATABASE_URL"    
}

Process {
    # Create List of target addresss
    $HostList = @()
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT * FROM Devices_Table;"
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        $HostInfo = New-Object -TypeName psobject -ArgumentList @{
            'Name' = $reader["Name"]
            'IPAddress' = $reader["IPAddress"]
        }
        $HostList += $HostInfo
    }
    $conn.Close()
    Write-EventLog -EventType "INFO" -Message "Found $($HostList.Count) Devices in the Database"

    $results = @()
    $HostList | ForEach-Object {
        $result = .\Invoke-PingSweeper.ps1 -ComputerName $_.IPAddress -Ports -1
        if($result.Status -eq $True){
            $_ | Add-Member -MemberType NoteProperty -Name Status -Value "Online"
        }else{
            $_ | Add-Member -MemberType NoteProperty -Name Status -Value "Offline"
        }

        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "UPDATE Devices_Table SET Status = @status WHERE Name = @Name"

        # Add parameters safely
        $null = $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@status", $_.Status)))
        $null = $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@Name", $_.Name)))

        # Execute
        $command = $cmd.ExecuteNonQuery()
        $conn.Close()

        Write-EventLog -EventType "STATUS" -Message "Host $($_.Name) Is $($_.Status)"
    }
}

End {
    Remove-Variable conn -ErrorAction SilentlyContinue
    Write-EventLog -EventType "EXIT" -Message "Quitting Status Collector"
}
