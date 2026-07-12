function Invoke-SqliteQuery {  
    <# 
    .SYNOPSIS 
        Runs a SQL script against a SQLite database.

    .DESCRIPTION 
        Runs a SQL script against a SQLite database.

        Paramaterized queries are supported. 

        Help details below borrowed from Invoke-Sqlcmd, may be inaccurate here.

    .PARAMETER DataSource
        Path to one or more SQLite data sources to query 

    .PARAMETER Query
        Specifies a query to be run.

    .PARAMETER InputFile
        Specifies a file to be used as the query input to Invoke-SqliteQuery. Specify the full path to the file.

    .PARAMETER QueryTimeout
        Specifies the number of seconds before the queries time out.

    .PARAMETER As
        Specifies output type - DataSet, DataTable, array of DataRow, PSObject or Single Value 

        PSObject output introduces overhead but adds flexibility for working with results: http://powershell.org/wp/forums/topic/dealing-with-dbnull/

    .PARAMETER SqlParameters
        Hashtable of parameters for parameterized SQL queries.  http://blog.codinghorror.com/give-me-parameterized-sql-or-give-me-death/

        Limited support for conversions to SQLite friendly formats is supported.
            For example, if you pass in a .NET DateTime, we convert it to a string that SQLite will recognize as a datetime

        Example:
            -Query "SELECT ServerName FROM tblServerInfo WHERE ServerName LIKE @ServerName"
            -SqlParameters @{"ServerName = "c-is-hyperv-1"}

    .PARAMETER SQLiteConnection
        An existing SQLiteConnection to use.  We do not close this connection upon completed query.

    .PARAMETER AppendDataSource
        If specified, append the SQLite data source path to PSObject or DataRow output

    .INPUTS 
        DataSource 
            You can pipe DataSource paths to Invoke-SQLiteQuery.  The query will execute against each Data Source.

    .OUTPUTS
       As PSObject:     System.Management.Automation.PSCustomObject
       As DataRow:      System.Data.DataRow
       As DataTable:    System.Data.DataTable
       As DataSet:      System.Data.DataTableCollectionSystem.Data.DataSet
       As SingleValue:  Dependent on data type in first column.

    .EXAMPLE

        #
        # First, we create a database and a table
            $Query = "CREATE TABLE NAMES (fullname VARCHAR(20) PRIMARY KEY, surname TEXT, givenname TEXT, BirthDate DATETIME)"
            $Database = "C:\Names.SQLite"
        
            Invoke-SqliteQuery -Query $Query -DataSource $Database

        # We have a database, and a table, let's view the table info
            Invoke-SqliteQuery -DataSource $Database -Query "PRAGMA table_info(NAMES)"
                
                cid name      type         notnull dflt_value pk
                --- ----      ----         ------- ---------- --
                  0 fullname  VARCHAR(20)        0             1
                  1 surname   TEXT               0             0
                  2 givenname TEXT               0             0
                  3 BirthDate DATETIME           0             0

        # Insert some data, use parameters for the fullname and birthdate
            $query = "INSERT INTO NAMES (fullname, surname, givenname, birthdate) VALUES (@full, 'Cookie', 'Monster', @BD)"
            Invoke-SqliteQuery -DataSource $Database -Query $query -SqlParameters @{
                full = "Cookie Monster"
                BD   = (get-date).addyears(-3)
            }

        # Check to see if we inserted the data:
            Invoke-SqliteQuery -DataSource $Database -Query "SELECT * FROM NAMES"
                
                fullname       surname givenname BirthDate            
                --------       ------- --------- ---------            
                Cookie Monster Cookie  Monster   3/14/2012 12:27:13 PM

        # Insert another entry with too many characters in the fullname.
        # Illustrate that SQLite data types may be misleading:
            Invoke-SqliteQuery -DataSource $Database -Query $query -SqlParameters @{
                full = "Cookie Monster$('!' * 20)"
                BD   = (get-date).addyears(-3)
            }

            Invoke-SqliteQuery -DataSource $Database -Query "SELECT * FROM NAMES"

                fullname              surname givenname BirthDate            
                --------              ------- --------- ---------            
                Cookie Monster        Cookie  Monster   3/14/2012 12:27:13 PM
                Cookie Monster![...]! Cookie  Monster   3/14/2012 12:29:32 PM

    .EXAMPLE
        Invoke-SqliteQuery -DataSource C:\NAMES.SQLite -Query "SELECT * FROM NAMES" -AppendDataSource

            fullname       surname givenname BirthDate             Database       
            --------       ------- --------- ---------             --------       
            Cookie Monster Cookie  Monster   3/14/2012 12:55:55 PM C:\Names.SQLite

        # Append Database column (path) to each result

    .EXAMPLE
        Invoke-SqliteQuery -DataSource C:\Names.SQLite -InputFile C:\Query.sql

        # Invoke SQL from an input file

    .EXAMPLE
        $Connection = New-SQLiteConnection -DataSource :MEMORY: 
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "CREATE TABLE OrdersToNames (OrderID INT PRIMARY KEY, fullname TEXT);"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "INSERT INTO OrdersToNames (OrderID, fullname) VALUES (1,'Cookie Monster');"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "PRAGMA STATS"

        # Execute a query against an existing SQLiteConnection
            # Create a connection to a SQLite data source in memory
            # Create a table in the memory based datasource, verify it exists with PRAGMA STATS

    .EXAMPLE
        $Connection = New-SQLiteConnection -DataSource :MEMORY: 
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "CREATE TABLE OrdersToNames (OrderID INT PRIMARY KEY, fullname TEXT);"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "INSERT INTO OrdersToNames (OrderID, fullname) VALUES (1,'Cookie Monster');"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "INSERT INTO OrdersToNames (OrderID) VALUES (2);"

        # We now have two entries, only one has a fullname.  Despite this, the following command returns both; very un-PowerShell!
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "SELECT * FROM OrdersToNames" -As DataRow | Where{$_.fullname}

            OrderID fullname      
            ------- --------      
                  1 Cookie Monster
                  2               

        # Using the default -As PSObject, we can get PowerShell-esque behavior:
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "SELECT * FROM OrdersToNames" | Where{$_.fullname}

            OrderID fullname                                                                         
            ------- --------                                                                         
                  1 Cookie Monster 

    .LINK
        https://github.com/RamblingCookieMonster/Invoke-SQLiteQuery

    .LINK
        New-SQLiteConnection

    .LINK
        Invoke-SQLiteBulkCopy

    .LINK
        Out-DataTable
    
    .LINK
        https://www.sqlite.org/datatype3.html

    .LINK
        https://www.sqlite.org/lang.html

    .LINK
        http://www.sqlite.org/pragma.html

    .FUNCTIONALITY
        SQL
    #>

    [CmdletBinding( DefaultParameterSetName='Src-Que' )]
    [OutputType([System.Management.Automation.PSCustomObject],[System.Data.DataRow],[System.Data.DataTable],[System.Data.DataTableCollection],[System.Data.DataSet])]
    param(
        [Parameter( ParameterSetName='Src-Que',
                    Position=0,
                    Mandatory=$true,
                    ValueFromPipeline=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false,
                    HelpMessage='SQLite Data Source required...' )]
        [Parameter( ParameterSetName='Src-Fil',
                    Position=0,
                    Mandatory=$true,
                    ValueFromPipeline=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false,
                    HelpMessage='SQLite Data Source required...' )]
        [Alias('Path','File','FullName','Database')]
        [validatescript({
            #This should match memory, or the parent path should exist
            $Parent = Split-Path $_ -Parent
            if(
                $_ -match ":MEMORY:|^WHAT$" -or
                ( $Parent -and (Test-Path $Parent))
            ){
                $True
            }
            else {
                Throw "Invalid datasource '$_'.`nThis must match :MEMORY:, or '$Parent' must exist"
            }
        })]
        [string[]]
        $DataSource,
    
        [Parameter( ParameterSetName='Src-Que',
                    Position=1,
                    Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [Parameter( ParameterSetName='Con-Que',
                    Position=1,
                    Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [string]
        $Query,
        
        [Parameter( ParameterSetName='Src-Fil',
                    Position=1,
                    Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [Parameter( ParameterSetName='Con-Fil',
                    Position=1,
                    Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [ValidateScript({ Test-Path $_ })]
        [string]
        $InputFile,

        [Parameter( Position=2,
                    Mandatory=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [Int32]
        $QueryTimeout=600,
    
        [Parameter( Position=3,
                    Mandatory=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [ValidateSet("DataSet", "DataTable", "DataRow","PSObject","SingleValue")]
        [string]
        $As="PSObject",
    
        [Parameter( Position=4,
                    Mandatory=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [System.Collections.IDictionary]
        $SqlParameters,

        [Parameter( Position=5,
                    Mandatory=$false )]
        [switch]
        $AppendDataSource,

        [Parameter( Position=6,
                    Mandatory=$false )]
        [validatescript({Test-Path $_ })]
        [string]$AssemblyPath = $SQLiteAssembly,

        [Parameter( ParameterSetName = 'Con-Que',
                    Position=7,
                    Mandatory=$true,
                    ValueFromPipeline=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [Parameter( ParameterSetName = 'Con-Fil',
                    Position=7,
                    Mandatory=$true,
                    ValueFromPipeline=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [Alias( 'Connection', 'Conn' )]
        [System.Data.SQLite.SQLiteConnection]
        $SQLiteConnection
    ) 

    Begin
    {
        #Assembly, should already be covered by psm1
            Try
            {
                [void][System.Data.SQLite.SQLiteConnection]
            }
            Catch
            {
                if( -not ($Library = Add-Type -path $SQLiteAssembly -PassThru -ErrorAction stop) )
                {
                    Throw "This module requires the ADO.NET driver for SQLite:`n`thttp://system.data.sqlite.org/index.html/doc/trunk/www/downloads.wiki"
                }
            }

        if ($PSBoundParameters.ContainsKey('InputFile')) 
        { 
            $filePath = $(Resolve-Path $InputFile).path 
            $Query =  [System.IO.File]::ReadAllText("$filePath")
            Write-Verbose "Extracted query from [$InputFile]"
        }
        Write-Verbose "Running Invoke-SQLiteQuery with ParameterSet '$($PSCmdlet.ParameterSetName)'.  Performing query '$Query'"

        If($As -eq "PSObject")
        {
            #This code scrubs DBNulls.  Props to Dave Wyatt
            $cSharp = @'
                using System;
                using System.Data;
                using System.Management.Automation;

                public class DBNullScrubber
                {
                    public static PSObject DataRowToPSObject(DataRow row)
                    {
                        PSObject psObject = new PSObject();

                        if (row != null && (row.RowState & DataRowState.Detached) != DataRowState.Detached)
                        {
                            foreach (DataColumn column in row.Table.Columns)
                            {
                                Object value = null;
                                if (!row.IsNull(column))
                                {
                                    value = row[column];
                                }

                                psObject.Properties.Add(new PSNoteProperty(column.ColumnName, value));
                            }
                        }

                        return psObject;
                    }
                }
'@

            Try
            {
                if ($PSEdition -eq 'Core') 
                {
                    # Core doesn't auto-load these assemblies unlike desktop?
                    # Not csharp coder, unsure why
                    # by fffnite
                    $Ref = @( 
                            'System.Data.Common'
                            'System.Management.Automation'
                            'System.ComponentModel.TypeConverter'
                            )
                }
                else 
                {
                    $Ref = @(
                            'System.Data'
                            'System.Xml'
                            )
                }
                Add-Type -TypeDefinition $cSharp -ReferencedAssemblies $Ref -ErrorAction stop
            }
            Catch
            {
                If(-not $_.ToString() -like "*The type name 'DBNullScrubber' already exists*")
                {
                    Write-Warning "Could not load DBNullScrubber.  Defaulting to DataRow output: $_"
                    $As = "Datarow"
                }
            }
        }

        #Handle existing connections
        if($PSBoundParameters.Keys -contains "SQLiteConnection")
        {
            if($SQLiteConnection.State -notlike "Open")
            {
                Try
                {
                    $SQLiteConnection.Open()
                }
                Catch
                {
                    Throw $_
                }
            }

            if($SQLiteConnection.state -notlike "Open")
            {
                Throw "SQLiteConnection is not open:`n$($SQLiteConnection | Out-String)"
            }

            $DataSource = @("WHAT")
        }
    }
    Process
    {
        foreach($DB in $DataSource)
        {

            if($PSBoundParameters.Keys -contains "SQLiteConnection")
            {
                $Conn = $SQLiteConnection
            }
            else
            {
                # Resolve the path entered for the database to a proper path name.
                # This accounts for a variaty of possible ways to provide a path, but
                # in the end the connection string needs a fully qualified file path.
                if ($DB -match ":MEMORY:") 
                {
                    $Database = $DB
                }
                else 
                {
                    $Database = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DB)    
                }
                
                if(Test-Path $Database)
                {
                    Write-Verbose "Querying existing Data Source '$Database'"
                }
                else
                {
                    Write-Verbose "Creating andn querying Data Source '$Database'"
                }

                $ConnectionString = "Data Source={0}" -f $Database

                $conn = New-Object System.Data.SQLite.SQLiteConnection -ArgumentList $ConnectionString
                $conn.ParseViaFramework = $true #Allow UNC paths, thanks to Ray Alex!
                Write-Debug "ConnectionString $ConnectionString"

                Try
                {
                    $conn.Open() 
                }
                Catch
                {
                    Write-Error $_
                    continue
                }
            }

            $cmd = $Conn.CreateCommand()
            $cmd.CommandText = $Query
            $cmd.CommandTimeout = $QueryTimeout

            if ($SqlParameters -ne $null)
            {
                $SqlParameters.GetEnumerator() |
                    ForEach-Object {
                        If ($_.Value -ne $null)
                        {
                            if($_.Value -is [datetime]) { $_.Value = $_.Value.ToString("yyyy-MM-dd HH:mm:ss") }
                            $cmd.Parameters.AddWithValue("@$($_.Key)", $_.Value)
                        }
                        Else
                        {
                            $cmd.Parameters.AddWithValue("@$($_.Key)", [DBNull]::Value)
                        }
                    } > $null
            }
    
            $ds = New-Object system.Data.DataSet 
            $da = New-Object System.Data.SQLite.SQLiteDataAdapter($cmd)
    
            Try
            {
                [void]$da.fill($ds)
                if($PSBoundParameters.Keys -notcontains "SQLiteConnection")
                {
                    $conn.Close()
                }
                $cmd.Dispose()
            }
            Catch
            { 
                $Err = $_
                if($PSBoundParameters.Keys -notcontains "SQLiteConnection")
                {
                    $conn.Close()
                }
                switch ($ErrorActionPreference.tostring())
                {
                    {'SilentlyContinue','Ignore' -contains $_} {}
                    'Stop' {     Throw $Err }
                    'Continue' { Write-Error $Err}
                    Default {    Write-Error $Err}
                }           
            }

            if($AppendDataSource)
            {
                #Basics from Chad Miller
                $Column =  New-Object Data.DataColumn
                $Column.ColumnName = "Datasource"
                $ds.Tables[0].Columns.Add($Column)

                Try
                {
                    #Someone better at regular expression, feel free to tackle this
                    $Conn.ConnectionString -match "Data Source=(?<DataSource>.*);"
                    $Datasrc = $Matches.DataSource.split(";")[0]
                }
                Catch
                {
                    $Datasrc = $DB
                }

                Foreach($row in $ds.Tables[0])
                {
                    $row.Datasource = $Datasrc
                }
            }

            switch ($As) 
            { 
                'DataSet' 
                {
                    $ds
                } 
                'DataTable'
                {
                    $ds.Tables
                } 
                'DataRow'
                {
                    $ds.Tables[0]
                }
                'PSObject'
                {
                    #Scrub DBNulls - Provides convenient results you can use comparisons with
                    #Introduces overhead (e.g. ~2000 rows w/ ~80 columns went from .15 Seconds to .65 Seconds - depending on your data could be much more!)
                    foreach ($row in $ds.Tables[0].Rows)
                    {
                        [DBNullScrubber]::DataRowToPSObject($row)
                    }
                }
                'SingleValue'
                {
                    $ds.Tables[0] | Select-Object -ExpandProperty $ds.Tables[0].Columns[0].ColumnName
                }
            }
        }
    }
}

# SIG # Begin signature block
# MIIr2wYJKoZIhvcNAQcCoIIrzDCCK8gCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUdbhVfgBeC8UwSYUUIiO11+mG
# wESggiUVMIIFbzCCBFegAwIBAgIQSPyTtGBVlI02p8mKidaUFjANBgkqhkiG9w0B
# AQwFADB7MQswCQYDVQQGEwJHQjEbMBkGA1UECAwSR3JlYXRlciBNYW5jaGVzdGVy
# MRAwDgYDVQQHDAdTYWxmb3JkMRowGAYDVQQKDBFDb21vZG8gQ0EgTGltaXRlZDEh
# MB8GA1UEAwwYQUFBIENlcnRpZmljYXRlIFNlcnZpY2VzMB4XDTIxMDUyNTAwMDAw
# MFoXDTI4MTIzMTIzNTk1OVowVjELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3Rp
# Z28gTGltaXRlZDEtMCsGA1UEAxMkU2VjdGlnbyBQdWJsaWMgQ29kZSBTaWduaW5n
# IFJvb3QgUjQ2MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAjeeUEiIE
# JHQu/xYjApKKtq42haxH1CORKz7cfeIxoFFvrISR41KKteKW3tCHYySJiv/vEpM7
# fbu2ir29BX8nm2tl06UMabG8STma8W1uquSggyfamg0rUOlLW7O4ZDakfko9qXGr
# YbNzszwLDO/bM1flvjQ345cbXf0fEj2CA3bm+z9m0pQxafptszSswXp43JJQ8mTH
# qi0Eq8Nq6uAvp6fcbtfo/9ohq0C/ue4NnsbZnpnvxt4fqQx2sycgoda6/YDnAdLv
# 64IplXCN/7sVz/7RDzaiLk8ykHRGa0c1E3cFM09jLrgt4b9lpwRrGNhx+swI8m2J
# mRCxrds+LOSqGLDGBwF1Z95t6WNjHjZ/aYm+qkU+blpfj6Fby50whjDoA7NAxg0P
# OM1nqFOI+rgwZfpvx+cdsYN0aT6sxGg7seZnM5q2COCABUhA7vaCZEao9XOwBpXy
# bGWfv1VbHJxXGsd4RnxwqpQbghesh+m2yQ6BHEDWFhcp/FycGCvqRfXvvdVnTyhe
# Be6QTHrnxvTQ/PrNPjJGEyA2igTqt6oHRpwNkzoJZplYXCmjuQymMDg80EY2NXyc
# uu7D1fkKdvp+BRtAypI16dV60bV/AK6pkKrFfwGcELEW/MxuGNxvYv6mUKe4e7id
# FT/+IAx1yCJaE5UZkADpGtXChvHjjuxf9OUCAwEAAaOCARIwggEOMB8GA1UdIwQY
# MBaAFKARCiM+lvEH7OKvKe+CpX/QMKS0MB0GA1UdDgQWBBQy65Ka/zWWSC8oQEJw
# IDaRXBeF5jAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zATBgNVHSUE
# DDAKBggrBgEFBQcDAzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EMAQQBMEMGA1Ud
# HwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwuY29tb2RvY2EuY29tL0FBQUNlcnRpZmlj
# YXRlU2VydmljZXMuY3JsMDQGCCsGAQUFBwEBBCgwJjAkBggrBgEFBQcwAYYYaHR0
# cDovL29jc3AuY29tb2RvY2EuY29tMA0GCSqGSIb3DQEBDAUAA4IBAQASv6Hvi3Sa
# mES4aUa1qyQKDKSKZ7g6gb9Fin1SB6iNH04hhTmja14tIIa/ELiueTtTzbT72ES+
# BtlcY2fUQBaHRIZyKtYyFfUSg8L54V0RQGf2QidyxSPiAjgaTCDi2wH3zUZPJqJ8
# ZsBRNraJAlTH/Fj7bADu/pimLpWhDFMpH2/YGaZPnvesCepdgsaLr4CnvYFIUoQx
# 2jLsFeSmTD1sOXPUC4U5IOCFGmjhp0g4qdE2JXfBjRkWxYhMZn0vY86Y6GnfrDyo
# XZ3JHFuu2PMvdM+4fvbXg50RlmKarkUT2n/cR/vfw1Kf5gZV6Z2M8jpiUbzsJA8p
# 1FiAhORFe1rYMIIGFDCCA/ygAwIBAgIQeiOu2lNplg+RyD5c9MfjPzANBgkqhkiG
# 9w0BAQwFADBXMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVk
# MS4wLAYDVQQDEyVTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIFJvb3QgUjQ2
# MB4XDTIxMDMyMjAwMDAwMFoXDTM2MDMyMTIzNTk1OVowVTELMAkGA1UEBhMCR0Ix
# GDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJs
# aWMgVGltZSBTdGFtcGluZyBDQSBSMzYwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAw
# ggGKAoIBgQDNmNhDQatugivs9jN+JjTkiYzT7yISgFQ+7yavjA6Bg+OiIjPm/N/t
# 3nC7wYUrUlY3mFyI32t2o6Ft3EtxJXCc5MmZQZ8AxCbh5c6WzeJDB9qkQVa46xiY
# Epc81KnBkAWgsaXnLURoYZzksHIzzCNxtIXnb9njZholGw9djnjkTdAA83abEOHQ
# 4ujOGIaBhPXG2NdV8TNgFWZ9BojlAvflxNMCOwkCnzlH4oCw5+4v1nssWeN1y4+R
# laOywwRMUi54fr2vFsU5QPrgb6tSjvEUh1EC4M29YGy/SIYM8ZpHadmVjbi3Pl8h
# JiTWw9jiCKv31pcAaeijS9fc6R7DgyyLIGflmdQMwrNRxCulVq8ZpysiSYNi79tw
# 5RHWZUEhnRfs/hsp/fwkXsynu1jcsUX+HuG8FLa2BNheUPtOcgw+vHJcJ8HnJCrc
# UWhdFczf8O+pDiyGhVYX+bDDP3GhGS7TmKmGnbZ9N+MpEhWmbiAVPbgkqykSkzyY
# Vr15OApZYK8CAwEAAaOCAVwwggFYMB8GA1UdIwQYMBaAFPZ3at0//QET/xahbIIC
# L9AKPRQlMB0GA1UdDgQWBBRfWO1MMXqiYUKNUoC6s2GXGaIymzAOBgNVHQ8BAf8E
# BAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDCDAR
# BgNVHSAECjAIMAYGBFUdIAAwTAYDVR0fBEUwQzBBoD+gPYY7aHR0cDovL2NybC5z
# ZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljVGltZVN0YW1waW5nUm9vdFI0Ni5jcmww
# fAYIKwYBBQUHAQEEcDBuMEcGCCsGAQUFBzAChjtodHRwOi8vY3J0LnNlY3RpZ28u
# Y29tL1NlY3RpZ29QdWJsaWNUaW1lU3RhbXBpbmdSb290UjQ2LnA3YzAjBggrBgEF
# BQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20wDQYJKoZIhvcNAQEMBQADggIB
# ABLXeyCtDjVYDJ6BHSVY/UwtZ3Svx2ImIfZVVGnGoUaGdltoX4hDskBMZx5NY5L6
# SCcwDMZhHOmbyMhyOVJDwm1yrKYqGDHWzpwVkFJ+996jKKAXyIIaUf5JVKjccev3
# w16mNIUlNTkpJEor7edVJZiRJVCAmWAaHcw9zP0hY3gj+fWp8MbOocI9Zn78xvm9
# XKGBp6rEs9sEiq/pwzvg2/KjXE2yWUQIkms6+yslCRqNXPjEnBnxuUB1fm6bPAV+
# Tsr/Qrd+mOCJemo06ldon4pJFbQd0TQVIMLv5koklInHvyaf6vATJP4DfPtKzSBP
# kKlOtyaFTAjD2Nu+di5hErEVVaMqSVbfPzd6kNXOhYm23EWm6N2s2ZHCHVhlUgHa
# C4ACMRCgXjYfQEDtYEK54dUwPJXV7icz0rgCzs9VI29DwsjVZFpO4ZIVR33LwXyP
# DbYFkLqYmgHjR3tKVkhh9qKV2WCmBuC27pIOx6TYvyqiYbntinmpOqh/QPAnhDge
# xKG9GX/n1PggkGi9HCapZp8fRwg8RftwS21Ln61euBG0yONM6noD2XQPrFwpm3Gc
# uqJMf0o8LLrFkSLRQNwxPDDkWXhW+gZswbaiie5fd/W2ygcto78XCSPfFWveUOSZ
# 5SqK95tBO8aTHmEa4lpJVD7HrTEn9jb1EGvxOb1cnn0CMIIGGjCCBAKgAwIBAgIQ
# Yh1tDFIBnjuQeRUgiSEcCjANBgkqhkiG9w0BAQwFADBWMQswCQYDVQQGEwJHQjEY
# MBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS0wKwYDVQQDEyRTZWN0aWdvIFB1Ymxp
# YyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIx
# MjM1OTU5WjBUMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVk
# MSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2RlIFNpZ25pbmcgQ0EgUjM2MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAmyudU/o1P45gBkNqwM/1f/bI
# U1MYyM7TbH78WAeVF3llMwsRHgBGRmxDeEDIArCS2VCoVk4Y/8j6stIkmYV5Gej4
# NgNjVQ4BYoDjGMwdjioXan1hlaGFt4Wk9vT0k2oWJMJjL9G//N523hAm4jF4UjrW
# 2pvv9+hdPX8tbbAfI3v0VdJiJPFy/7XwiunD7mBxNtecM6ytIdUlh08T2z7mJEXZ
# D9OWcJkZk5wDuf2q52PN43jc4T9OkoXZ0arWZVeffvMr/iiIROSCzKoDmWABDRzV
# /UiQ5vqsaeFaqQdzFf4ed8peNWh1OaZXnYvZQgWx/SXiJDRSAolRzZEZquE6cbcH
# 747FHncs/Kzcn0Ccv2jrOW+LPmnOyB+tAfiWu01TPhCr9VrkxsHC5qFNxaThTG5j
# 4/Kc+ODD2dX/fmBECELcvzUHf9shoFvrn35XGf2RPaNTO2uSZ6n9otv7jElspkfK
# 9qEATHZcodp+R4q2OIypxR//YEb3fkDn3UayWW9bAgMBAAGjggFkMIIBYDAfBgNV
# HSMEGDAWgBQy65Ka/zWWSC8oQEJwIDaRXBeF5jAdBgNVHQ4EFgQUDyrLIIcouOxv
# SK4rVKYpqhekzQwwDgYDVR0PAQH/BAQDAgGGMBIGA1UdEwEB/wQIMAYBAf8CAQAw
# EwYDVR0lBAwwCgYIKwYBBQUHAwMwGwYDVR0gBBQwEjAGBgRVHSAAMAgGBmeBDAEE
# ATBLBgNVHR8ERDBCMECgPqA8hjpodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3Rp
# Z29QdWJsaWNDb2RlU2lnbmluZ1Jvb3RSNDYuY3JsMHsGCCsGAQUFBwEBBG8wbTBG
# BggrBgEFBQcwAoY6aHR0cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGlj
# Q29kZVNpZ25pbmdSb290UjQ2LnA3YzAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Au
# c2VjdGlnby5jb20wDQYJKoZIhvcNAQEMBQADggIBAAb/guF3YzZue6EVIJsT/wT+
# mHVEYcNWlXHRkT+FoetAQLHI1uBy/YXKZDk8+Y1LoNqHrp22AKMGxQtgCivnDHFy
# AQ9GXTmlk7MjcgQbDCx6mn7yIawsppWkvfPkKaAQsiqaT9DnMWBHVNIabGqgQSGT
# rQWo43MOfsPynhbz2Hyxf5XWKZpRvr3dMapandPfYgoZ8iDL2OR3sYztgJrbG6VZ
# 9DoTXFm1g0Rf97Aaen1l4c+w3DC+IkwFkvjFV3jS49ZSc4lShKK6BrPTJYs4NG1D
# GzmpToTnwoqZ8fAmi2XlZnuchC4NPSZaPATHvNIzt+z1PHo35D/f7j2pO1S8BCys
# QDHCbM5Mnomnq5aYcKCsdbh0czchOm8bkinLrYrKpii+Tk7pwL7TjRKLXkomm5D1
# Umds++pip8wH2cQpf93at3VDcOK4N7EwoIJB0kak6pSzEu4I64U6gZs7tS/dGNSl
# jf2OSSnRr7KWzq03zl8l75jy+hOds9TWSenLbjBQUGR96cFr6lEUfAIEHVC1L68Y
# 1GGxx4/eRI82ut83axHMViw1+sVpbPxg51Tbnio1lB93079WPFnYaOvfGAA0e0zc
# fF/M9gXr+korwQTh2Prqooq2bYNMvUoUKD85gnJ+t0smrWrb8dee2CvYZXD5laGt
# aAxOfy/VKNmwuWuAh9kcMIIGYjCCBMqgAwIBAgIRAKQpO24e3denNAiHrXpOtyQw
# DQYJKoZIhvcNAQEMBQAwVTELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28g
# TGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBD
# QSBSMzYwHhcNMjUwMzI3MDAwMDAwWhcNMzYwMzIxMjM1OTU5WjByMQswCQYDVQQG
# EwJHQjEXMBUGA1UECBMOV2VzdCBZb3Jrc2hpcmUxGDAWBgNVBAoTD1NlY3RpZ28g
# TGltaXRlZDEwMC4GA1UEAxMnU2VjdGlnbyBQdWJsaWMgVGltZSBTdGFtcGluZyBT
# aWduZXIgUjM2MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA04SV9G6k
# U3jyPRBLeBIHPNyUgVNnYayfsGOyYEXrn3+SkDYTLs1crcw/ol2swE1TzB2aR/5J
# IjKNf75QBha2Ddj+4NEPKDxHEd4dEn7RTWMcTIfm492TW22I8LfH+A7Ehz0/safc
# 6BbsNBzjHTt7FngNfhfJoYOrkugSaT8F0IzUh6VUwoHdYDpiln9dh0n0m545d5A5
# tJD92iFAIbKHQWGbCQNYplqpAFasHBn77OqW37P9BhOASdmjp3IijYiFdcA0WQIe
# 60vzvrk0HG+iVcwVZjz+t5OcXGTcxqOAzk1frDNZ1aw8nFhGEvG0ktJQknnJZE3D
# 40GofV7O8WzgaAnZmoUn4PCpvH36vD4XaAF2CjiPsJWiY/j2xLsJuqx3JtuI4akH
# 0MmGzlBUylhXvdNVXcjAuIEcEQKtOBR9lU4wXQpISrbOT8ux+96GzBq8TdbhoFcm
# YaOBZKlwPP7pOp5Mzx/UMhyBA93PQhiCdPfIVOCINsUY4U23p4KJ3F1HqP3H6Slw
# 3lHACnLilGETXRg5X/Fp8G8qlG5Y+M49ZEGUp2bneRLZoyHTyynHvFISpefhBCV0
# KdRZHPcuSL5OAGWnBjAlRtHvsMBrI3AAA0Tu1oGvPa/4yeeiAyu+9y3SLC98gDVb
# ySnXnkujjhIh+oaatsk/oyf5R2vcxHahajMCAwEAAaOCAY4wggGKMB8GA1UdIwQY
# MBaAFF9Y7UwxeqJhQo1SgLqzYZcZojKbMB0GA1UdDgQWBBSIYYyhKjdkgShgoZsx
# 0Iz9LALOTzAOBgNVHQ8BAf8EBAMCBsAwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8E
# DDAKBggrBgEFBQcDCDBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgEDCDAlMCMGCCsG
# AQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwBBAIwSgYDVR0f
# BEMwQTA/oD2gO4Y5aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGlj
# VGltZVN0YW1waW5nQ0FSMzYuY3JsMHoGCCsGAQUFBwEBBG4wbDBFBggrBgEFBQcw
# AoY5aHR0cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVibGljVGltZVN0YW1w
# aW5nQ0FSMzYuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNv
# bTANBgkqhkiG9w0BAQwFAAOCAYEAAoE+pIZyUSH5ZakuPVKK4eWbzEsTRJOEjbIu
# 6r7vmzXXLpJx4FyGmcqnFZoa1dzx3JrUCrdG5b//LfAxOGy9Ph9JtrYChJaVHrus
# Dh9NgYwiGDOhyyJ2zRy3+kdqhwtUlLCdNjFjakTSE+hkC9F5ty1uxOoQ2ZkfI5WM
# 4WXA3ZHcNHB4V42zi7Jk3ktEnkSdViVxM6rduXW0jmmiu71ZpBFZDh7Kdens+PQX
# PgMqvzodgQJEkxaION5XRCoBxAwWwiMm2thPDuZTzWp/gUFzi7izCmEt4pE3Kf0M
# Ot3ccgwn4Kl2FIcQaV55nkjv1gODcHcD9+ZVjYZoyKTVWb4VqMQy/j8Q3aaYd/jO
# Q66Fhk3NWbg2tYl5jhQCuIsE55Vg4N0DUbEWvXJxtxQQaVR5xzhEI+BjJKzh3TQ0
# 26JxHhr2fuJ0mV68AluFr9qshgwS5SpN5FFtaSEnAwqZv3IS+mlG50rK7W3qXbWw
# i4hmpylUfygtYLEdLQukNEX1jiOKMIIGfDCCBOSgAwIBAgIQUPzSfdqXD5O+TnEK
# U46VQDANBgkqhkiG9w0BAQwFADBUMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2Vj
# dGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2RlIFNpZ25p
# bmcgQ0EgUjM2MB4XDTI0MDMwODAwMDAwMFoXDTI2MDMwODIzNTk1OVowdzELMAkG
# A1UEBhMCQ0ExEDAOBgNVBAgMB09udGFyaW8xKjAoBgNVBAoMIVRoZSBVbml2ZXJz
# aXR5IG9mIFdlc3Rlcm4gT250YXJpbzEqMCgGA1UEAwwhVGhlIFVuaXZlcnNpdHkg
# b2YgV2VzdGVybiBPbnRhcmlvMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEApkYxNSKQDX5LMCRzCkwuCYdwKejvNBSKKNOLHeZAGb65z0Uz0LUvxD3dXdRW
# mdgGd+jTLXJhpvsMy1GURIi8yQUmrc9Wz4TmbsvdJkup0pW1Mp1Pl8fdBHpNUgTp
# xsWo6x0e5sKZMM6qp9idi0Z1MQb1YCMKQ9BCuD0gu8deDPS0KUIMpkt0NB8S7Mnp
# ffb1y8Xkf78DDnsD4/iVGWWCIXtKXYRQTLDKfgBXurD4KfwcZIve6kY2rBh/yVZ7
# TVHi9cmeOGaeof73/5XjcpMXyyI8QKScE56q3vtdWAnC1b5rd7Kqqg8fp+Xv6ShP
# U9iJ0zjKtieYEA7rd40MfIWqrpwRgkeiB7IsQh7TqBPNxIHoFq4nHWVNjyFLaRx/
# dt4XzIyMnLQFvFvrWVkhsq+nqVagOOAOgPsuvcR6N6iZzRxE+HC2TfTY7lLVmAz2
# 1suCnEwI/XPb+oNN7QZlysVobBlhh08eWr4hw2HHB2FFxIWNcM8F5i7uAIEn7iPh
# kv+OdKmnDAtVGQqpx518BHBj4rz6ssAYVV6OjoCxmtV5aRV0x+n4C+M3XjwxhTMX
# fpNzSmA8+QU8DCwfJLv8AhASZkUExxVVfeW4/wRxa2XYamjQlC/QiQIGzRApLihG
# w+0EegKv/j9187uus/dg9mp2zvcQstugqM3F8tR53ipu/ccCAwEAAaOCAaUwggGh
# MB8GA1UdIwQYMBaAFA8qyyCHKLjsb0iuK1SmKaoXpM0MMB0GA1UdDgQWBBThnJ2f
# CdhBVqVYPQTkAqXJOZigvTAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAT
# BgNVHSUEDDAKBggrBgEFBQcDAzBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgEDAjAl
# MCMGCCsGAQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwBBAEw
# SQYDVR0fBEIwQDA+oDygOoY4aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdv
# UHVibGljQ29kZVNpZ25pbmdDQVIzNi5jcmwweQYIKwYBBQUHAQEEbTBrMEQGCCsG
# AQUFBzAChjhodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2Rl
# U2lnbmluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGln
# by5jb20wGgYDVR0RBBMwEYEPYWhhbXBzb25AdXdvLmNhMA0GCSqGSIb3DQEBDAUA
# A4IBgQB5rYvbCYnibz4edyR1m4tCzDIW2F2R3B+3D5U7/lJ4dG3txo4Cj4ViF5Wl
# u0hKcBq9NQ4E1Tk5kCxu0aPWjZ9mBm35ngX35av3veUd1z/oEi8xiuHAoyvHSEFP
# IWdKGepuzUNt9ps91cxKaASqPun+SlcFAde0tX4fR50Am56ERib6zfakenIXbraW
# DPl6aXQ5438Vvi5mJE7CzFW5anQZUAFYkAesynhktOcb7p1ehKDnRsHzo9k+/W5D
# b9HULv0dxQBggDa2UbJ/zR8FebVeu4iMh79lRJ8c4BtDcKZGngEgyLfKq9rFzPl6
# I5yf9XLUSjYHYrBVJAZqxTIsvViNBNpFbMc0gPLchNRmvys4WiRzENNymdp+biBA
# 4GhaGWLTIScwv8K/9ddbamW6iYA4eG2UMmJyU2HChTx0GVGZG5TpnLYZ7UyDEvo6
# cQYCHgdIqxfhbnW3un9AELMYTuSn3UE4qlmmaEf/78Lhg+HhypCO82cpi/exTUS/
# z/KlBCgwggaCMIIEaqADAgECAhA2wrC9fBs656Oz3TbLyXVoMA0GCSqGSIb3DQEB
# DAUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKTmV3IEplcnNleTEUMBIGA1UE
# BxMLSmVyc2V5IENpdHkxHjAcBgNVBAoTFVRoZSBVU0VSVFJVU1QgTmV0d29yazEu
# MCwGA1UEAxMlVVNFUlRydXN0IFJTQSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTAe
# Fw0yMTAzMjIwMDAwMDBaFw0zODAxMTgyMzU5NTlaMFcxCzAJBgNVBAYTAkdCMRgw
# FgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGlj
# IFRpbWUgU3RhbXBpbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQCIndi5RWedHd3ouSaBmlRUwHxJBZvMWhUP2ZQQRLRBQIF3FJmp1OR2
# LMgIU14g0JIlL6VXWKmdbmKGRDILRxEtZdQnOh2qmcxGzjqemIk8et8sE6J+N+Gl
# 1cnZocew8eCAawKLu4TRrCoqCAT8uRjDeypoGJrruH/drCio28aqIVEn45NZiZQI
# 7YYBex48eL78lQ0BrHeSmqy1uXe9xN04aG0pKG9ki+PC6VEfzutu6Q3IcZZfm00r
# 9YAEp/4aeiLhyaKxLuhKKaAdQjRaf/h6U13jQEV1JnUTCm511n5avv4N+jSVwd+W
# b8UMOs4netapq5Q/yGyiQOgjsP/JRUj0MAT9YrcmXcLgsrAimfWY3MzKm1HCxcqu
# inTqbs1Q0d2VMMQyi9cAgMYC9jKc+3mW62/yVl4jnDcw6ULJsBkOkrcPLUwqj7po
# S0T2+2JMzPP+jZ1h90/QpZnBkhdtixMiWDVgh60KmLmzXiqJc6lGwqoUqpq/1HVH
# m+Pc2B6+wCy/GwCcjw5rmzajLbmqGygEgaj/OLoanEWP6Y52Hflef3XLvYnhEY4k
# SirMQhtberRvaI+5YsD3XVxHGBjlIli5u+NrLedIxsE88WzKXqZjj9Zi5ybJL2Wj
# eXuOTbswB7XjkZbErg7ebeAQUQiS/uRGZ58NHs57ZPUfECcgJC+v2wIDAQABo4IB
# FjCCARIwHwYDVR0jBBgwFoAUU3m/WqorSs9UgOHYm8Cd8rIDZsswHQYDVR0OBBYE
# FPZ3at0//QET/xahbIICL9AKPRQlMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8E
# BTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBQ
# BgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLnVzZXJ0cnVzdC5jb20vVVNFUlRy
# dXN0UlNBQ2VydGlmaWNhdGlvbkF1dGhvcml0eS5jcmwwNQYIKwYBBQUHAQEEKTAn
# MCUGCCsGAQUFBzABhhlodHRwOi8vb2NzcC51c2VydHJ1c3QuY29tMA0GCSqGSIb3
# DQEBDAUAA4ICAQAOvmVB7WhEuOWhxdQRh+S3OyWM637ayBeR7djxQ8SihTnLf2sA
# BFoB0DFR6JfWS0snf6WDG2gtCGflwVvcYXZJJlFfym1Doi+4PfDP8s0cqlDmdfyG
# OwMtGGzJ4iImyaz3IBae91g50QyrVbrUoT0mUGQHbRcF57olpfHhQEStz5i6hJvV
# LFV/ueQ21SM99zG4W2tB1ExGL98idX8ChsTwbD/zIExAopoe3l6JrzJtPxj8V9ro
# cAnLP2C8Q5wXVVZcbw4x4ztXLsGzqZIiRh5i111TW7HV1AtsQa6vXy633vCAbAOI
# aKcLAo/IU7sClyZUk62XD0VUnHD+YvVNvIGezjM6CRpcWed/ODiptK+evDKPU2K6
# synimYBaNH49v9Ih24+eYXNtI38byt5kIvh+8aW88WThRpv8lUJKaPn37+YHYafo
# b9Rg7LyTrSYpyZoBmwRWSE4W6iPjB7wJjJpH29308ZkpKKdpkiS9WNsf/eeUtvRr
# tIEiSJHN899L1P4l6zKVsdrUu1FX1T/ubSrsxrYJD+3f3aKg6yxdbugot06YwGXX
# iy5UUGZvOu3lXlxA+fC13dQ5OlL2gIb5lmF6Ii8+CQOYDwXM+yd9dbmocQsHjcRP
# sccUd5E9FiswEqORvz8g3s+jR3SFCgXhN4wz7NgAnOgpCdUo4uDyllU9PzGCBjAw
# ggYsAgEBMGgwVDELMAkGA1UEBhMCR0IxGDAWBgNVBAoTD1NlY3RpZ28gTGltaXRl
# ZDErMCkGA1UEAxMiU2VjdGlnbyBQdWJsaWMgQ29kZSBTaWduaW5nIENBIFIzNgIQ
# UPzSfdqXD5O+TnEKU46VQDAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAig
# AoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgEL
# MQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU+jdcn2kGc60ENIDmqt1W
# u7g9FOkwDQYJKoZIhvcNAQEBBQAEggIAoxo9WPdmlXzCgPavX8Npi2fhYfMlOoBF
# puLLPI64vKmS2Z50YtTKSlTUzOft34tZ2Qn7vaUuZCkpexvdci0amnoYvokPjc24
# tR1jJPy68f+DHnpdYBdT6mNTALKkN59651OeGyjteqbwwEfWFBvYNAvJuKd66flG
# A0wUd2zHXEO8iRhwemr7zx/aJxGe3Qy6Qplb2gtRhY+ZQlbd6iiBVGbYfyuC1nPL
# JCKfb7gFBOWvj6xHvp+LuPr7oszJsPnZqKHa+1BPU9j1EMAFUwOeprVRWhb3plQo
# t2SGqX05za1wP6xFsC51CN9+wivRclgMLEETKKbF4GMlCBNyi6Osj7Z8dQMfzMAp
# Sdoo2ESUZoupRESonjuAlP8t3dnHe5xM7wzPAETLaZLz7roojSujL8uCsjxMeulF
# /Y1UkFWgPqZ/uGr5qMeeOac8eRv5HkTUWz1GXzTx5z5PA8Rp6CqO1kJ8a4PGJwGO
# uMhiXwG7w1SqWqtZU974bnuMvZ+N7nb5e+nW2GcsKdvdbyxfhX+n9oAyDwyy+nqJ
# I8iam/rySEcicELDXAGfTkENstcVQeBf2Zf7b5tvx8WQXnxX9ZSNDc5d2cc5GZgJ
# jBQV17HFc+0gcoDKH5o5eoT/DUctadlSao6oh9TqMCskvYAV6Yfz3FzdgkdQ5YDR
# UeacX/pDzrOhggMjMIIDHwYJKoZIhvcNAQkGMYIDEDCCAwwCAQEwajBVMQswCQYD
# VQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYDVQQDEyNTZWN0
# aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNgIRAKQpO24e3denNAiHrXpO
# tyQwDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwG
# CSqGSIb3DQEJBTEPFw0yNTA3MDQxNzE3NDlaMD8GCSqGSIb3DQEJBDEyBDCZ/FUv
# qB5SKfSMlgB9SQzcZAtNq6Lf3jmk3fpTlO+VBwg7ZfqJvk8SJHS70Bci/V8wDQYJ
# KoZIhvcNAQEBBQAEggIAh5tOijWJZXAmV/fsfLLTHYEMyWst0NFGr1EP5B0THxBN
# 3GWBl7qCIjieoi8AQfIrDZqcjsX73Fs3I4SBU4b/GSM1JWxGuuiTNofoGX+7nday
# lC+jydpBwG5CX81GMKbsg0+zMYeodqFs/SenSiwSYg9Wmey2JG1mGYso5jjILKQp
# nTWl133hyUcTPYbxCazRIA443kQ+hCjh08KT2DaTB9R6HGXw3r/OzEQ5xC5fho9Y
# gcZCFrrj0EyrZpduO/642AIf/UD9UXv9O/37p3qhNuySAH2Ev38YMXbyARwTRScK
# fLonpTX2RJ7DYQAtC0zXKTI3d9JMkH5hHa9zjNakLZIV/j4nSMr9CWOhlEKOonEv
# tHLGbCCz8HoUOAWSUwMWZ86PWVpkKEByP1vO5DaE4TBk+SqK+n4mGyj35HHPrj/l
# RgTnvpcUsqW4/FagQTx4CCq8/QS+aYVszEis2Vj3zO71SxLcFtCrogIc4H8vDk/S
# Edz6xsIrpiH0UaPgP1JyE8y3PIzjgPjdmr/WdIRiFSe1mztJO78oVhHoieaWcW2O
# i8lHUAVQ7uD01ZHazNqEJL2jk54QAyroTFwiAA8cH5hG/l3/l7Rtk5w+yLv88bR6
# 6B9VzuuzZL2mFjQpz90ziDuYhVxJJ4cLayqXTUXZOW2j8wRckDCHbYOkPWOlEMo=
# SIG # End signature block
