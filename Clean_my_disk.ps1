function TestRemotePort{
    param(
    [String]$ComputerName,
    [Int]$Port
    )
    <#
    .SYNOPSIS
    Function to test remote ports.
    .DESCRIPTION
    This script checks port on the remote computers
    .EXAMPLE
    TestRemotePort -ComputerName ServerName -Port 8080
    .PARAMETER ComputerName
    Remote Server Name
    .PARAMETER Port
    Remote port number
    .INPUTS
    ComputerNames can be passed and a port can be passed
    .OUTPUTS
    True or False
    #>
    Test-NetConnection -ComputerName $ComputerName -Port $Port
    }