# Helper for acquiring the archival exchange rates for a given list of dates.
function Get-SEKUSDPMIAtDateRange ([DateTime[]]$Dates)
{
	# Extend "earliest" by a week to make sure we have data even if the earliest date falls on a red day in Sweden.
	$earliest = $(($Dates | Measure-Object -Minimum).Minimum).AddDays(-7.0)
	$latest = ($Dates | Measure-Object -Maximum).Maximum
	return $(Invoke-RestMethod -Uri $([string]::Format("https://api.riksbank.se/swea/v1/Observations/SEKUSDPMI/{0}/{1}", $earliest.ToString("yyyy-MM-dd"), $latest.ToString("yyyy-MM-dd"))) -Method Get)
}

# Helper for querying the exchange rate array acquired with the above call for a given date.
function Get-SEKUSDPMIAtDate ($rates, [datetime]$Date)
{
	$rate = $null
	do
	{
		$rate = $rates | Where-Object { $_.date -eq $($Date.ToString("yyyy-MM-dd")) }
		# Scan backwards in time for the latest rate, if there's no record for the current.
		if ($null -eq $rate) { Write-Host $([string]::Format("No exchange rate for {0}, trying the previous day", $Date.ToString("yyyy-MM-dd"))) }
		$Date = $Date.AddDays(-1.0)
	}
	while ($null -eq $rate)
	#Write-Host $([string]::Format("Exchange rate for {0} is {1}", $Date.ToString("yyyy-MM-dd"), $rate.value))
	return [double]$rate.value
}

function Parse-DollarAmount ($dollarstr)
{
	# Remove currency symbols ($, £, etc.) and thousands separators (,)
	$cleanString = $dollarstr -replace '[\$,]', ''
	# Parse using InvariantCulture to enforce decimal point interpretation
	return [double]::Parse($cleanString, [Globalization.CultureInfo]::InvariantCulture)
}
