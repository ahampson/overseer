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

    # Load ENV data
    Get-Content (Join-Path (Join-Path $WorkingDirectory "..") ".env") |
        ForEach-Object {
            if ($_ -match "^\s*$" -or $_ -match "^\s*#") { return }

            $parts = $_ -split "=", 2
            $key   = $parts[0].Trim()
            $value = $parts[1].Trim()

            Set-Item -Path "Env:$key" -Value $value
        }

    # Import correct SQLite module
    Add-Type -Path $(Join-Path $WorkingDirectory "\PSSQLite\1.1.0\x64\System.Data.SQLite.dll")

    #Invoke-SqliteQuery -DataSource ..\db.sqlite  -Query "SELECT Name FROM DeviceType_Table;"

    $HostList = @()
}

Process {
    $conn = New-Object System.Data.SQLite.SQLiteConnection
    $conn.ConnectionString = "Data Source=../db.sqlite"
    $conn.Open()

    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT * FROM Devices_Table;"

    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        $HostList += $reader["IPAddress"]
    }
    $conn.Close()

    Write-Host "Found $($HostList.Count) Devices in the Database"

    $HostList | ForEach-Object {
        .\Invoke-PingSweeper.ps1 -ComputerName $_ -Ports -1
    }
}

End {
    Remove-Variable conn -ErrorAction SilentlyContinue
}
