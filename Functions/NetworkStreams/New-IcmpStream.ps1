﻿function New-IcmpStream {
[CmdletBinding(DefaultParameterSetName = 'Client')]
    Param (
        [Parameter(Position = 0, ParameterSetName = 'Client', Mandatory = $true)]
        [Net.IPAddress]$ServerIp,
        
        [Parameter(Position = 0, ParameterSetName = 'Listener', Mandatory = $true)]
        [Switch]$Listener,

        [Parameter(Position = 1, Mandatory = $true)]
        [String]$BindAddress,
        
        [Parameter()]
        [Int]$BufferSize = 4608,
        
        [Parameter()]
        [Int]$Timeout = 60
    )
    
    $IcmpSocket = New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Raw, [Net.Sockets.ProtocolType]::Icmp)
    $SocketLocalEndPoint = New-Object Net.IPEndPoint @(([Net.IPAddress]::Parse($BindAddress)), $null)
    $IcmpSocket.Bind($SocketLocalEndPoint)
    $IcmpSocket.IOControl([Net.Sockets.IOControlCode]::ReceiveAll, [byte[]]@(1, 0, 0, 0), [byte[]]@(1, 0, 0, 0))
    $SocketDestinationBuffer = New-Object Byte[] 4608
    
    Write-Verbose "Listening on $($IcmpSocket.LocalEndPoint.Address.IPAddressToString) [icmp]"

    if ($Listener.IsPresent) {
        
        $RemoteEndPoint = New-Object Net.IPEndPoint @([Net.IPAddress]::Any, $null)                
        $ConnectResult = $IcmpSocket.BeginReceiveFrom($SocketDestinationBuffer, 0, 4608, [Net.Sockets.SocketFlags]::None, [ref]$RemoteEndPoint, $null, $null)
        
        $Stopwatch = [Diagnostics.Stopwatch]::StartNew()
        [console]::TreatControlCAsInput = $true
      
        do {
            if ([console]::KeyAvailable) {          
                $Key = [console]::ReadKey($true)
                if ($Key.Key -eq [Consolekey]::Escape) {
                    Write-Warning 'Caught escape sequence, stopping Icmp setup.'
                    [console]::TreatControlCAsInput = $false
                    $SocketDestinationBuffer = $null
                    $IcmpSocket.Dispose()
                    $Stopwatch.Stop()
                    return
                }
            }

            if ($Stopwatch.Elapsed.TotalSeconds -gt $Timeout) {
                Write-Warning "Timeout exceeded, stopping Icmp setup."
                [console]::TreatControlCAsInput = $false
                $SocketDestinationBuffer = $null
                $IcmpSocket.Dispose()
                $Stopwatch.Stop()
                return
            }
        } until ($ConnectResult.IsCompleted)
        
        [console]::TreatControlCAsInput = $false
        $Stopwatch.Stop()

        $SocketFlags = 0
        $SocketBytesRead = $IcmpSocket.EndReceiveFrom($ConnectResult, [ref]$RemoteEndPoint)

        Write-Verbose "Connection from $($RemoteEndPoint.ToString()) [icmp] accepted."
                
        if ($SocketBytesRead.Count) { 
            $InitialBytes = $SocketDestinationBuffer[0..($SocketBytesRead - 1)] 
            [Array]::Clear($SocketDestinationBuffer, 0, $SocketBytesRead)
        }

        $Properties = @{
            Socket = $IcmpSocket
            Buffer = $SocketDestinationBuffer
            Read = $IcmpSocket.BeginReceive($SocketDestinationBuffer, 0, 4608, 0, $null, $null)
        }
        $IcmpStream = New-Object -TypeName psobject -Property $Properties
    }        
    else { # Client
        $RemoteEndPoint = New-Object Net.IPEndPoint @($ServerIp, $null) 
        $IcmpSocket.Connect($RemoteEndPoint)

        Write-Verbose "Sending ICMP traffic to $($ServerIp.IPAddressToString)"
        Write-Verbose "Make sure to send some data to the server!"

        $Properties = @{
            Socket = $IcmpSocket
            Buffer = $SocketDestinationBuffer
            Read = $IcmpSocket.BeginReceive($SocketDestinationBuffer, 0, 4608, 0, $null, $null)
        }
        $IcmpStream = New-Object -TypeName psobject -Property $Properties
    }
    return $InitialBytes, $IcmpStream
}