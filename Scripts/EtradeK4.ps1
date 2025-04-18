# Load the shared bits.
. (Join-Path $PSScriptRoot "Shared.ps1")

$gainsLosses = $(get-content -raw -path gainsLosses.json | ConvertFrom-Json).data.gainsAndLosses.list.gainsLossDtlsList
$saleTransactions = $gainsLosses | Where-Object { $_.transactionType -eq "Sell" }

$k4 = @()
$totalClosing = 0
$totalClosingSEK = 0
$totalOpening = 0
$totalOpeningSEK = 0

# The new REST API is rate-limited. We need to fetch data for the interval, and then sample the specific days.
$rates = Get-SEKUSDPMIAtDateRange $($saleTransactions | ForEach-Object {
	$closingDate = [datetime]::ParseExact($_.closingTransDateSold, "MM/dd/yyyy", $null)
	$openingDate = [datetime]::ParseExact($_.openingTransDateAcquired, "MM/dd/yyyy", $null)
	$openingDate, $closingDate
})

foreach ($ct in $saleTransactions)
{
	$txDate = [datetime]::ParseExact($ct.closingTransDateSold, "MM/dd/yyyy", $null)
	$txRate = Get-SEKUSDPMIAtDate $rates $txDate
	
	$tx = $ct.closingTransTotalProceeds
	$txSEK = [int][math]::Round($tx * $txRate)
	
	$closingTransTotalProceeds = [math]::Max(0.0, $tx)
	$closingTransTotalProceedsSEK = [math]::Max(0, $txSEK)

	$txDate = [datetime]::ParseExact($ct.openingTransDateAcquired, "MM/dd/yyyy", $null)
	$txRate = Get-SEKUSDPMIAtDate $rates $txDate

	$tx = $ct.openingTransAdjCostBasis
	$txSEK = [int][math]::Round($tx * $txRate)

	$openingTransAdjCostBasis = [math]::Max(0.0, $tx)
	$openingTransAdjCostBasisSEK = [math]::Max(0, $txSEK)
	
	$totalClosing += $closingTransTotalProceeds
	$totalClosingSEK += $closingTransTotalProceedsSEK
	$totalOpening += $openingTransAdjCostBasis
	$totalOpeningSEK += $openingTransAdjCostBasisSEK

	$k4 += [ordered]@{
		"Purchased" = $ct.openingTransDateAcquired;
		"Sold" =  $ct.closingTransDateSold;
		"Symbol" = $ct.symbol ;
		"QTY"  = $ct.quantity ;
		"Closing Proceeds USD" = $closingTransTotalProceeds;
		"Closing Proceeds SEK" = $closingTransTotalProceedsSEK;
		"Purchase Price USD" = $openingTransAdjCostBasis;
		"Purchase Price SEK" = $openingTransAdjCostBasisSEK;
	}
}

$totalClosing = [math]::Round($totalClosing)
$totalOpening = [math]::Round($totalOpening)

Write-Warning "Please note that while this script generally does account for fees and commisions (by using Total Proceeds: The dollar value of the transaction after the deduction of any commissions and fees), it does not include disbursement fees if you deposit the proceeds in your Securities account, as opposed to wiring them out of E-Trade immediately.`n`nWhere the proceeds have been deposited can be checked in At Work -> My Account -> Orders, and expanding the individual orders.`n`nKeeping track of where to add the wire fee in this case is beyond the scope of this script, but you can look at wire history for the last 12 months by going to At Work -> My Account -> Holdings -> Other Holdings and expanding the Cash section.`n`nOne way to account for it is to divide the wire fee (can be worked out by the difference of the Wire Out value and the Shares Sold-Cash Proceeds Received) between the sell orders contributing to the wire amount, and subtracting that number from their respective Closing Proceeds USD (remember to recalculate the SEK afterwards)."

Write-Output 'Marknadsnoterade aktier, adktieindexobligationer, aktieoptioner m.m. / Listed shares, share index bonds, share options, etc.'

$k4 | ForEach {[PSCustomObject]$_} | Format-Table -AutoSize

$totals = @( @{'Valuta' = "SEK";
'Summa Vinst' = ([math]::Max(0, $totalClosingSEK - $totalOpeningSEK));
'Summa Förlust' = ([math]::Min(0, $totalClosingSEK - $totalOpeningSEK)) ;
'Forsäljningspris' = $totalClosingSEK;
'Omkostnadsbelopp'  = $totalOpeningSEK;
}, @{'Valuta' = "USD";
'Summa Vinst' = ([math]::Max(0, $totalClosing - $totalOpening));
'Summa Förlust' = ([math]::Min(0, $totalClosing - $totalOpening)) ;
'Forsäljningspris' = $totalClosing;
'Omkostnadsbelopp'  = $totalOpening;
}) 
$totals | ForEach {[PSCustomObject]$_} | Format-Table -AutoSize
