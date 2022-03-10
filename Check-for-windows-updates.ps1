#create Task in task scheduler 

function create_task {
    
    $task_name = Join-path -Path '\' -ChildPath 'Auto install Windows Updates V1.0'


$chek_if_task_exist = schtasks /query /fo csv 2> $null | ConvertFrom-Csv | Where-Object { $_.TaskName -eq $task_name }
    if( $chek_if_task_exist )
    {
     return $true
    }
    else
    {
        $action = New-ScheduledTaskAction  -Execute 'Powershell.exe' -Argument 'C:\work\test.ps1'
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
        $trigger =  New-ScheduledTaskTrigger -Daily -At 9am
        Register-ScheduledTask -Principal $taskPrincipal -Action $action -Trigger $trigger -TaskName "Auto install Windows Updates V1.0" -Description "This task will inastall updates whithout to reboot your PC."
    }
}

create_task

# check if powershel module exist
# if module exist check for updates and install
function auto_updates {

    if (Get-Module -ListAvailable -Name "PSWindowsUpdate") {
        Get-WindowsUpdate -Download -Install -IgnoreReboot -Confirm:$false
    }
     else {
        Install-Module -Name PSWindowsUpdate -Force -Confirm:$false

        if (Get-Module -ListAvailable -Name "PSWindowsUpdate") {
            Get-WindowsUpdate -Download -Install -IgnoreReboot -Confirm:$false
        }
    }

}auto_updates