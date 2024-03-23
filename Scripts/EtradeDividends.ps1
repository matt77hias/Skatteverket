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

$cashTransactions = $(get-content -raw -path getCashTransactions.json | ConvertFrom-Json).data.value.cashTransactionActivities
$dividendTransactions = $cashTransactions | Where-Object { $_.transactionType -eq "$+-DIV" }

$totalDividendUSD = 0.0
$totalTaxUSD = 0.0
$totalDividendSEK = 0
$totalTaxSEK = 0

# The new REST API is rate-limited. We need to fetch data for the interval, and then sample the specific days.
$divDates = $dividendTransactions | ForEach-Object { [datetime]::ParseExact($_.transactionDate, "MM/dd/yyyy", $null) }
$rates = Get-SEKUSDPMIAtDateRange $divDates

foreach ($ct in $dividendTransactions)
{
	$txDate = [datetime]::ParseExact($ct.transactionDate, "MM/dd/yyyy", $null)
	$txRate = Get-SEKUSDPMIAtDate $rates $txDate
	
	$tx = $ct.amount
	$txSEK = [int][math]::Round($tx * $txRate)
	
	$dividendUSD = [math]::Max(0.0, $tx)
	$taxUSD = [math]::Min(0.0, $tx)
	$dividendSEK = [math]::Max(0, $txSEK)
	$taxSEK = [math]::Min(0, $txSEK)
	
	$totalDividendUSD += $dividendUSD
	$totalTaxUSD += $taxUSD
	$totalDividendSEK += $dividendSEK
	$totalTaxSEK += $taxSEK
}

$totalDividendUSD = [math]::Round($totalDividendUSD)
$totalTaxUSD = [math]::Round($totalTaxUSD)

Write-Warning "Please note that this script only looks at the cash transaction register, which only looks 365 days back. Make sure the USD totals correspond with your 1042-S form."
$totals = New-Object PSObject |
	Add-Member -Type NoteProperty -Name 'Gross Income (Box 2) [Cross-check with 1042-S!]' -Value $totalDividendUSD -PassThru |
	Add-Member -Type NoteProperty -Name 'Federal Tax Withheld (Box 7a) [Cross-check with 1042-S!]' -Value $totalTaxUSD -PassThru |
	Add-Member -Type NoteProperty -Name 'Ränteinkomster, utdelningar m.m. 7.2' -Value $totalDividendSEK -PassThru |
	Add-Member -Type NoteProperty -Name 'Övriga upplysningar -> Avräkning av utländsk skatt' -Value $totalTaxSEK -PassThru

$totals | Format-List
