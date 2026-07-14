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
    Set-Location $WorkingDirectory

    Function Write-Eventlog{
        Param(
            [String]$EventType = "",
            [String]$Message = ""
        )
        # Create Eventlog
        $EventLog = $(Join-Path $(Join-Path $WorkingDirectory "..\LogFiles") "$($(get-Date).Day)_$($(get-Date).Month)_$($(get-Date).Year).txt")
        Write-Output "[$($(get-date).ToLongTimeString())][$PID][$EventType][$Message]" | Out-File -FilePath $EventLog -Append -Encoding ascii
    }
    
    function Get-DBStatus{
        Add-Type -Path $(Join-Path $WorkingDirectory "\PSSQLite\1.1.0\x64\System.Data.SQLite.dll")
        $conn = New-Object System.Data.SQLite.SQLiteConnection
        $conn.ConnectionString = "Data Source=$DatabasePath"
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT * FROM StatusCollector_Table WHERE ProcessID = @PID;"
        $null = $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@PID", $PID)))
        $reader = $cmd.ExecuteReader()
        while($reader.Read()){
            If($reader['Status'] -ne "RUNNING"){
                Write-EventLog -EventType $reader['Status'] -Message "Status Collector has been told to stop and will now exit" 
                Return $false
            }else{
                Return $True
            }
        }
        $conn.Close()
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
}

Process {
    #Set File path for Datbase
    $DatabasePath = $(Join-Path $WorkingDirectory $($env:DATABASE_URL.Replace("sqlite:/","..")))
    If(!(Test-Path $DatabasePath)){
        Write-EventLog -EventType "ERROR" -Message "Database does not exist! You must run the build script first."
        Stop-Process -Id $PID
    }

    # Import correct SQLite module
    Add-Type -Path $(Join-Path $WorkingDirectory "\PSSQLite\1.1.0\x64\System.Data.SQLite.dll")
    $conn = New-Object System.Data.SQLite.SQLiteConnection
    $conn.ConnectionString = "Data Source=$DatabasePath"
    $cmd = $conn.CreateCommand()
    
    Write-EventLog -EventType "INFO" -Message "Connecting to SQL Database: $DatabasePath" 
    
    # Register this App's Process ID into the Database
    <#
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT * FROM StatusCollector_Table WHERE Status = 'PENDING';"
    $reader = $cmd.ExecuteReader()
    Do{
        If($reader['id'] -ge 1){
            Write-EventLog -EventType "INFO" -Message "Registering Process ID: $PID into the Database" 
        }Else{
            Write-EventLog -EventType "ERROR" -Message "App was not launched from the Overseer and will now exit!"
            Stop-Process -Id $PID
        }
    }while($reader.Read())
    $conn.Close()
    #>

    # Register this App's Process ID into the Database
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "INSERT OR IGNORE INTO StatusCollector_Table (Status, ProcessID) VALUES ( @status, @PID);"
    $null = $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@status", "RUNNING" )))
    $null = $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@PID", $PID)))
    $result = $cmd.ExecuteNonQuery()
    If($result -eq 1){
        Write-EventLog -EventType "INFO" -Message "Registering Process ID: $PID into the Database"
    }else{
        Write-EventLog -EventType "ERROR" -Message "Unable to register Process ID: $PID in Database"
    }
    $conn.Close()

    Do{
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
        Start-Sleep -Seconds 10
    }while(Get-DBStatus)
}
End {
    Write-EventLog -EventType "INFO" -Message "Removing Process ID: $PID from the Database"
    
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "DELETE FROM StatusCollector_Table WHERE ProcessID = @PID ;"
    $null = $cmd.Parameters.Add((New-Object System.Data.SQLite.SQLiteParameter("@PID", $PID)))
    $cmd.ExecuteNonQuery()
    $conn.Close()

    Remove-Variable conn -ErrorAction SilentlyContinue
    Write-EventLog -EventType "EXIT" -Message "Quitting Status Collector"
}
