function Invoke-ManagedComputerCommand {
    <#
        .SYNOPSIS
            Runs wmi commands against a target system.

        .DESCRIPTION
            Runs wmi commands against a target system.
            Either directly or over PowerShell remoting.

        .PARAMETER ComputerName
            The target to run against. Must be resolvable.

        .PARAMETER Credential
            Credentials to use when using PowerShell remoting.

        .PARAMETER ScriptBlock
            The scriptblock to execute.
            Use $wmi to access the smo wmi object.
            Must not include a param block!

        .PARAMETER ArgumentList
            The arguments to pass to your scriptblock.
            Access them within the scriptblock using the automatic variable $args

        .PARAMETER EnableException
            Left in for legacy reasons. This command will throw no matter what
       #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Alias("Server")]
        [dbainstanceparameter]$ComputerName,
        [PSCredential]$Credential,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [string[]]$ArgumentList,
        [switch][Alias('Silent')]
        $EnableException # Left in for legacy but this command needs to throw
    )

    $computer = $ComputerName.ComputerName

    $null = Test-ElevationRequirement -ComputerName $computer -EnableException $true

    $resolved = Resolve-DbaNetworkName -ComputerName $computer -Turbo
    $ipaddr = $resolved.IpAddress
    $ArgumentList += $ipaddr

    [scriptblock]$setupScriptBlock = {
        $ipaddr = $args[$args.GetUpperBound(0)]

        # Just in case we go remote, ensure the assembly is loaded. Wenn SQL Server 2014 and 13.0.0.0__89845dcd8080cc91 -> Failed!!!
	# Find right library
		<#pkotov 
        [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
        $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $ipaddr
        $null = $wmi.Initialize()
		#>
		##Region pkotov begin
		$Count = -1
		$i = 0
		$t = Get-ChildItem "C:\Windows\assembly\GAC_MSIL\Microsoft.SqlServer.SqlWmiManagement\*"|Sort Name -Descending
		$t | Foreach{
						$t1 = $Null;
						$t1 = Get-ChildItem $_.FullName;
						Start-Job -Name $i -ScriptBlock {
									$ipaddr =  $args[1]
									$test = Add-Type -Path  $args[0] -PassThru;
									$m = New-Object ('Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer') $ipaddr;
									$m.Initialize()
							} -ArgumentList $t1.FullName,$ipaddr | Out-Null;
						$job = Get-Job -Name $i |  Wait-Job
						$CheckJob = Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue
						If($CheckJob -eq $true)
						{
							$Count = $i
							Return
						}
						$i ++
		}
		Get-Job | Remove-Job
		If($count -ge 0)
		{
			$test = Add-Type -Path (Get-ChildItem $t[$count].FullName).FullName -PassThru;
			$wmi = New-Object ('Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer') $ipaddr ;
			$null = $wmi.Initialize()
		}
		##Region pkotov end
    }

    $prescriptblock = $setupScriptBlock.ToString()
    $postscriptblock = $ScriptBlock.ToString()

    $scriptblock = [ScriptBlock]::Create("$prescriptblock  $postscriptblock")
    $Global:TestPKotov4 = $scriptblock#Test pkotov
    $Global:TestPKotov5 = $ArgumentList#Test pkotov
    Write-Message -Level Verbose -Message "Connecting to SQL WMI on $computer."

    try {
        Invoke-Command2 -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -Credential $Credential -ErrorAction Stop
    } catch {
        Write-Message -Level Verbose -Message "Local connection attempt to $computer failed. Connecting remotely."

        # For surely resolve stuff, and going by default with kerberos, this needs to match FullComputerName
        $hostname = $resolved.FullComputerName

        Invoke-Command2 -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ComputerName $hostname -Credential $Credential -ErrorAction Stop
    }
}
