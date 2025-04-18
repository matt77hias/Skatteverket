# Load the shared bits.
. (Join-Path $PSScriptRoot "Shared.ps1")

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
