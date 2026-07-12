function Invoke-SQLiteBulkCopy {
<#
.SYNOPSIS
    Use a SQLite transaction to quickly insert data

.DESCRIPTION
    Use a SQLite transaction to quickly insert data.  If we run into any errors, we roll back the transaction.
    
    The data source is not limited to SQL Server; any data source can be used, as long as the data can be loaded to a DataTable instance or read with a IDataReader instance.

.PARAMETER DataSource
    Path to one ore more SQLite data sources to query 

.PARAMETER Force
    If specified, skip the confirm prompt

.PARAMETER  NotifyAfter
	The number of rows to fire the notification event after transferring.  0 means don't notify.  Notifications hit the verbose stream (use -verbose to see them)

.PARAMETER QueryTimeout
    Specifies the number of seconds before the queries time out.

.PARAMETER SQLiteConnection
    An existing SQLiteConnection to use.  We do not close this connection upon completed query.

.PARAMETER ConflictClause
    The conflict clause to use in case a conflict occurs during insert. Valid values: Rollback, Abort, Fail, Ignore, Replace

    See https://www.sqlite.org/lang_conflict.html for more details

.EXAMPLE
    #
    #Create a table
        Invoke-SqliteQuery -DataSource "C:\Names.SQLite" -Query "CREATE TABLE NAMES (
            fullname VARCHAR(20) PRIMARY KEY,
            surname TEXT,
            givenname TEXT,
            BirthDate DATETIME)" 

    #Build up some fake data to bulk insert, convert it to a datatable
        $DataTable = 1..10000 | %{
            [pscustomobject]@{
                fullname = "Name $_"
                surname = "Name"
                givenname = "$_"
                BirthDate = (Get-Date).Adddays(-$_)
            }
        } | Out-DataTable

    #Copy the data in within a single transaction (SQLite is faster this way)
        Invoke-SQLiteBulkCopy -DataTable $DataTable -DataSource $Database -Table Names -NotifyAfter 1000 -ConflictClause Ignore -Verbose 
        
.INPUTS
    System.Data.DataTable

.OUTPUTS
    None
        Produces no output

.NOTES
    This function borrows from:
        Chad Miller's Write-Datatable
        jbs534's Invoke-SQLBulkCopy
        Mike Shepard's Invoke-BulkCopy from SQLPSX

.LINK
    https://github.com/RamblingCookieMonster/Invoke-SQLiteQuery

.LINK
    New-SQLiteConnection

.LINK
    Invoke-SQLiteBulkCopy

.LINK
    Out-DataTable

.FUNCTIONALITY
    SQL
#>
    [cmdletBinding( DefaultParameterSetName = 'Datasource',
                    SupportsShouldProcess = $true,
                    ConfirmImpact = 'High' )]
    param(
        [parameter( Position = 0,
                    Mandatory = $true,
                    ValueFromPipeline = $false,
                    ValueFromPipelineByPropertyName= $false)]
        [System.Data.DataTable]
        $DataTable,

        [Parameter( ParameterSetName='Datasource',
                    Position=1,
                    Mandatory=$true,
                    ValueFromRemainingArguments=$false,
                    HelpMessage='SQLite Data Source required...' )]
        [Alias('Path','File','FullName','Database')]
        [validatescript({
            #This should match memory, or the parent path should exist
            if ( $_ -match ":MEMORY:" -or (Test-Path $_) ) {
                $True
            }
            else {
                Throw "Invalid datasource '$_'.`nThis must match :MEMORY:, or must exist"
            }
        })]
        [string]
        $DataSource,

        [Parameter( ParameterSetName = 'Connection',
                    Position=1,
                    Mandatory=$true,
                    ValueFromPipeline=$false,
                    ValueFromPipelineByPropertyName=$true,
                    ValueFromRemainingArguments=$false )]
        [Alias( 'Connection', 'Conn' )]
        [System.Data.SQLite.SQLiteConnection]
        $SQLiteConnection,

        [parameter( Position=2,
                    Mandatory = $true)]
        [string]
        $Table,

        [Parameter( Position=3,
                     Mandatory=$false,
                     ValueFromPipeline=$false,
                     ValueFromPipelineByPropertyName=$false,
                     ValueFromRemainingArguments=$false)]
        [ValidateSet("Rollback","Abort","Fail","Ignore","Replace")]
        [string]
        $ConflictClause,

        [int]
        $NotifyAfter = 0,

        [switch]
        $Force,

        [Int32]
        $QueryTimeout = 600

    )

    Write-Verbose "Running Invoke-SQLiteBulkCopy with ParameterSet '$($PSCmdlet.ParameterSetName)'."

    Function CleanUp
    {
        [cmdletbinding()]
        param($conn, $com, $BoundParams)
        #Only dispose of the connection if we created it
        if($BoundParams.Keys -notcontains 'SQLiteConnection')
        {
            $conn.Close()
            $conn.Dispose()
            Write-Verbose "Closed connection"
        }
        $com.Dispose()
    }

    function Get-ParameterName
    {
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string[]]$InputObject,

            [Parameter(ValueFromPipelineByPropertyName = $true)]
            [string]$Regex = '(\W+)',

            [Parameter(ValueFromPipelineByPropertyName = $true)]
            [string]$Separator = '_'
        )

        Process{
            $InputObject | ForEach-Object {
                if($_ -match $Regex){
                    $Groups = @($_ -split $Regex | Where-Object {$_})
                    for($i = 0; $i -lt $Groups.Count; $i++){
                        if($Groups[$i] -match $Regex){
                            $Groups[$i] = ($Groups[$i].ToCharArray() | ForEach-Object {[string][int]$_}) -join $Separator
                        }
                    }
                    $Groups -join $Separator
                } else {
                    $_
                }
            }
        }
    }

    function New-SqliteBulkQuery {
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string]$Table,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string[]]$Columns,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string[]]$Parameters,

            [Parameter(ValueFromPipelineByPropertyName = $true)]
            [string]$ConflictClause = ''
        )

        Begin{
            $EscapeSingleQuote = "'","''"
            $Delimeter = ", "
            $QueryTemplate = "INSERT{0} INTO {1} ({2}) VALUES ({3})"
        }

        Process{
            $fmtConflictClause = if($ConflictClause){" OR $ConflictClause"}
            $fmtTable = "'{0}'" -f ($Table -replace $EscapeSingleQuote)
            $fmtColumns = ($Columns | ForEach-Object { "'{0}'" -f ($_ -replace $EscapeSingleQuote) }) -join $Delimeter
            $fmtParameters = ($Parameters | ForEach-Object { "@$_"}) -join $Delimeter

            $QueryTemplate -f $fmtConflictClause, $fmtTable, $fmtColumns, $fmtParameters
        }
    }

    #Connections
        if($PSBoundParameters.Keys -notcontains "SQLiteConnection")
        {
            if ($DataSource -match ':MEMORY:') 
            {
                $Database = $DataSource
            }
            else 
            {
                $Database = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DataSource)    
            }

            $ConnectionString = "Data Source={0}" -f $Database
            $SQLiteConnection = New-Object System.Data.SQLite.SQLiteConnection -ArgumentList $ConnectionString
            $SQLiteConnection.ParseViaFramework = $true #Allow UNC paths, thanks to Ray Alex!
        }

        Write-Debug "ConnectionString $($SQLiteConnection.ConnectionString)"
        Try
        {
            if($SQLiteConnection.State -notlike "Open")
            {
                $SQLiteConnection.Open()
            }
            $Command = $SQLiteConnection.CreateCommand()
            $CommandTimeout = $QueryTimeout
            $Transaction = $SQLiteConnection.BeginTransaction()
        }
        Catch
        {
            Throw $_
        }
    
    write-verbose "DATATABLE IS $($DataTable.gettype().fullname) with value $($Datatable | out-string)"
    $RowCount = $Datatable.Rows.Count
    Write-Verbose "Processing datatable with $RowCount rows"

    if ($Force -or $PSCmdlet.ShouldProcess("$($DataTable.Rows.Count) rows, with BoundParameters $($PSBoundParameters | Out-String)", "SQL Bulk Copy"))
    {
        #Get column info...
            [array]$Columns = $DataTable.Columns | Select-Object -ExpandProperty ColumnName
            $ColumnTypeHash = @{}
            $ColumnToParamHash = @{}
            $Index = 0
            foreach($Col in $DataTable.Columns)
            {
                $Type = Switch -regex ($Col.DataType.FullName)
                {
                    # I figure we create a hashtable, can act upon expected data when doing insert
                    # Might be a better way to handle this...
                    '^(|\ASystem\.)Boolean$' {"BOOLEAN"} #I know they're fake...
                    '^(|\ASystem\.)Byte\[\]' {"BLOB"}
                    '^(|\ASystem\.)Byte$'  {"BLOB"}
                    '^(|\ASystem\.)Datetime$'  {"DATETIME"}
                    '^(|\ASystem\.)Decimal$' {"REAL"}
                    '^(|\ASystem\.)Double$' {"REAL"}
                    '^(|\ASystem\.)Guid$' {"TEXT"}
                    '^(|\ASystem\.)Int16$'  {"INTEGER"}
                    '^(|\ASystem\.)Int32$'  {"INTEGER"}
                    '^(|\ASystem\.)Int64$' {"INTEGER"}
                    '^(|\ASystem\.)UInt16$'  {"INTEGER"}
                    '^(|\ASystem\.)UInt32$'  {"INTEGER"}
                    '^(|\ASystem\.)UInt64$' {"INTEGER"}
                    '^(|\ASystem\.)Single$' {"REAL"}
                    '^(|\ASystem\.)String$' {"TEXT"}
                    Default {"BLOB"} #Let SQLite handle the rest...
                }

                #We ref columns by their index, so add that...
                $ColumnTypeHash.Add($Index,$Type)

                # Parameter names can only be alphanumeric: https://www.sqlite.org/c3ref/bind_blob.html
                # So we have to replace all non-alphanumeric chars in column name to use it as parameter later.
                # This builds hashtable to correlate column name with parameter name.
                $ColumnToParamHash.Add($Col.ColumnName, (Get-ParameterName $Col.ColumnName))

                $Index++
            }

        #Build up the query
            if ($PSBoundParameters.ContainsKey('ConflictClause'))
            {
                $Command.CommandText = New-SqliteBulkQuery -Table $Table -Columns $ColumnToParamHash.Keys -Parameters $ColumnToParamHash.Values -ConflictClause $ConflictClause
            }
            else
            {
                $Command.CommandText = New-SqliteBulkQuery -Table $Table -Columns $ColumnToParamHash.Keys -Parameters $ColumnToParamHash.Values
            }

            foreach ($Column in $Columns)
            {
                $param = New-Object System.Data.SQLite.SqLiteParameter $ColumnToParamHash[$Column]
                [void]$Command.Parameters.Add($param)
            }
            
            for ($RowNumber = 0; $RowNumber -lt $RowCount; $RowNumber++)
            {
                $row = $Datatable.Rows[$RowNumber]
                for($col = 0; $col -lt $Columns.count; $col++)
                {
                    # Depending on the type of thid column, quote it
                    # For dates, convert it to a string SQLite will recognize
                    switch ($ColumnTypeHash[$col])
                    {
                        "BOOLEAN" {
                            $Command.Parameters[$ColumnToParamHash[$Columns[$col]]].Value = [int][boolean]$row[$col]
                        }
                        "DATETIME" {
                            Try
                            {
                                $Command.Parameters[$ColumnToParamHash[$Columns[$col]]].Value = $row[$col].ToString("yyyy-MM-dd HH:mm:ss")
                            }
                            Catch
                            {
                                $Command.Parameters[$ColumnToParamHash[$Columns[$col]]].Value = $row[$col]
                            }
                        }
                        Default {
                            $Command.Parameters[$ColumnToParamHash[$Columns[$col]]].Value = $row[$col]
                        }
                    }
                }

                #We have the query, execute!
                    Try
                    {
                        [void]$Command.ExecuteNonQuery()
                    }
                    Catch
                    {
                        #Minimal testing for this rollback...
                            Write-Verbose "Rolling back due to error:`n$_"
                            $Transaction.Rollback()
                        
                        #Clean up and throw an error
                            CleanUp -conn $SQLiteConnection -com $Command -BoundParams $PSBoundParameters
                            Throw "Rolled back due to error:`n$_"
                    }

                if($NotifyAfter -gt 0 -and $($RowNumber % $NotifyAfter) -eq 0)
                {
                    Write-Verbose "Processed $($RowNumber + 1) records"
                }
            }  
    }
    
    #Commit the transaction and clean up the connection
        $Transaction.Commit()
        CleanUp -conn $SQLiteConnection -com $Command -BoundParams $PSBoundParameters
    
}
# SIG # Begin signature block
# MIIr2wYJKoZIhvcNAQcCoIIrzDCCK8gCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUBJP//sKG/18PNlIXWWBUy5Wt
# J4SggiUVMIIFbzCCBFegAwIBAgIQSPyTtGBVlI02p8mKidaUFjANBgkqhkiG9w0B
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
# MQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUM5h26/aMc1kv56WSwKQo
# 7VSktTkwDQYJKoZIhvcNAQEBBQAEggIAiEWLK0iO0IAGmAyAZzGLIhprCrNzznn7
# LWA6DkcVW2PpaSsCU2aXYR1EEXSg8TJ+Yi/2LbD0L+zsu80HZ3BKCe3DiYWQE11P
# QqcYJRpqve7ZkkKSJDkxdrb9eYJNN6QXs4LjfqOH03qQZkxzBKT0N6GtXS45b7KM
# uGj1lYdQ3E41tEPT/fvTdzBm40+rDJsxIrz3zA+gdYqlmaZC8sSEmiTjlWImjHVb
# CwMSd5FS+qYsIq2P5r6/ADzuXY3daPSUIaU0qCS3HBWKfU1pRe+rhnpWXU2bMtrh
# ALIi6Z+Li4plfVNN1V2adMssVV14Coq95vp6Np0a8dGL9H3pks4DpMnxrE99fg83
# UaxnFCS5kT6jbI7m4ZDS/L7ZlQp42qv3hGB+GHW122fR5NccrIVqiqJfh1CYfbNB
# sEn+UVjN4EjFGbpXKHqng9nastDUapdT65vkgF3WpAGXfMWS+OfQ1+6zRN3Vf+9I
# UntgCjU6wFg7T8gpmVqER/Xik4JApbYfzQQC8G4ur1wRt/gD80EnNt7mLcZknAsk
# uP2wOegP+UqNH2CWjXJWw3b1Yi5BfZfNhtodNNqmFC03Ppcyv7CaTcrYPRhcdutk
# mww/7E9qik0pKSiQgcNqisu1KpMpTTTxtyayD9no8uVgQxUsm3h1DkGRvIVdKWb8
# f4J7pCydJzahggMjMIIDHwYJKoZIhvcNAQkGMYIDEDCCAwwCAQEwajBVMQswCQYD
# VQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYDVQQDEyNTZWN0
# aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNgIRAKQpO24e3denNAiHrXpO
# tyQwDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwG
# CSqGSIb3DQEJBTEPFw0yNTA3MDQxNzE3NDRaMD8GCSqGSIb3DQEJBDEyBDBG9Yvp
# YN/lv4XVznrUVD+LkfSY+UESLGbywOnzE6kDw7ZkYcl7bacv7ayaYG8cWRMwDQYJ
# KoZIhvcNAQEBBQAEggIAYz/Hn/kt+fpcQa6jg1WzZK2QqYAM8dZId+4TaxfCLPgW
# g7uVSG5w02zK10JIU1ZcezseN443t/0KJds8xaA3DfPwEX2N0I9nrxhRa2Wga9jp
# Om0d/nUBCxzz/Dgh1O7H62cuBKzSizhHlqQaGSoj8IzzDa1dHBWCSeYyJv3AuDlU
# d1QS5kXR9KPB2Gp0RW6E9Sw6C68gzxWmKAJGT1BEIukJEniAf/3bfaLZgXpz12KJ
# TiuGrjSHsH/fKHT4LbZxvp6ceJk5u7Sm+r1dsP0zAbTy+viqnOwBSzB5wwPPJuyu
# /NsWTUI/+90jtAwHmtufUBimBqjokjEL0sZkXViw/NiENnI+umDCwyo4hHpT23eK
# Y0hdkcOLi8zcNgYdGC5zCFiBK9ZosqwWnXhyMK1wuboY3icvskjSU3kMB0/9iqbp
# lynJ2S0WD2OQeMY9XiIC5abOTjXI2pJaz347b5va19pCvREzivA5/wnO8VO1inR9
# tOkwEuZM/GBP7gFEZTNqzaSaeXsieid1TvxRBU1zavV2l5X27F2nd/T90TR8GNaM
# Y2GvtRy8Gi8axFED6xW4yCFu3nA2cq4IWoWLk2Xq73ynQRLJhghGbQXMKaclSqL3
# EXzqbALQJScFq7190fN+F23+Z32CKS7hScKqgc4r09M1iEz1XvoG6dnl/YCFekU=
# SIG # End signature block
