# Load the shared bits.
. (Join-Path $PSScriptRoot "Shared.ps1")

$transactions = $(get-content -raw -path transactions.json | ConvertFrom-Json).transactions
$saleTransactions = $transactions | Where-Object { $_.typeName -eq "ShareSaleViewModel" }
$disbursementTransactions = $transactions | Where-Object {
    $_.typeName -eq "CashDisbursementViewModel" -and
    $_.totalCommissionsAndFees -notin $null, ''
}
$dividendTransactions = $transactions | Where-Object {
	$_.typeName -eq "CashTransactionViewModel" -and
	$_.action -eq "Dividend"
}
$taxWithholdingTransactions = $transactions | Where-Object {
	$_.typeName -eq "CashTransactionViewModel" -and
	$_.action -eq "Tax Withholding"
}

foreach ($d in $dividendTransactions) {
	$d | Add-Member -MemberType NoteProperty -Name 'matchedToDisbursement' -Value $false
	foreach ($t in $taxWithholdingTransactions) {
		if ($d.eventDate -eq $t.eventDate -and $d.symbol -eq $t.symbol) {
			$d | Add-Member -MemberType NoteProperty -Name 'taxAmount' -Value $t.amount
			$taxWithholdingTransactions = $taxWithholdingTransactions | Where-Object { $_ -ne $t }
		}
	}
}

if ($taxWithholdingTransactions.Count -ne 0) {
    $pretty = $taxWithholdingTransactions | Format-Table -AutoSize | Out-String
    throw "Unmatched tax withholding transactions:`n$($pretty)"
}

$unmatchedDisbursements = [System.Collections.Generic.List[object]]::new()

foreach ($sale in $saleTransactions) {
    $saleAmount = Parse-DollarAmount $sale.amount
    $saleDate = [datetime]::ParseExact($sale.eventDate, "MM/dd/yyyy", $null)
    $matchedDisbursement = $null
	$matchedDisbursementFee = $null

    foreach ($disbursement in $disbursementTransactions) {
        $disbursementDate = [datetime]::ParseExact($disbursement.eventDate, "MM/dd/yyyy", $null)
        $disbursementAmount = Parse-DollarAmount $disbursement.amount
        $disbursementFee = Parse-DollarAmount $disbursement.totalCommissionsAndFees
        
        if ($disbursementDate -ge $saleDate) {
			$match = [math]::Round($saleAmount, 2) -eq [math]::Round(-($disbursementAmount + $disbursementFee), 2)
			# If not a cent-to-cent match, see if folding in a dividend happening up to this date makes the numbers match.
			if (-not $match) {
				foreach ($dividend in $dividendTransactions) {
					if ($dividend.matchedToDisbursement) {
						continue
					}
					$dividendDate = [datetime]::ParseExact($dividend.eventDate, "MM/dd/yyyy", $null)
					if ($disbursementDate -ge $dividendDate) {
						$dividendAmount = Parse-DollarAmount $dividend.amount
						$dividendTax = Parse-DollarAmount $dividend.taxAmount
						$match = ([math]::Round($saleAmount, 2) + [math]::Round($dividendAmount, 2) + [math]::Round($dividendTax, 2)) -eq [math]::Round(-($disbursementAmount + $disbursementFee), 2)
						if ($match) {
							$dividend.matchedToDisbursement = $true
							Write-Host "NOTE: Matched dividend of $($dividend.amount) (withheld tax $($dividend.taxAmount)) from $($dividendDate) to disbursement of $($disbursementAmount) from $($disbursementDate)"
							break
						}
					}
				}
			}
			if ($match) {
				$matchedDisbursement = $disbursement
				$matchedDisbursementFee = $disbursementFee
				break
			}
        }
    }

    if ($matchedDisbursement) {
        # Adjust sale amount and remove matched disbursement
		if ($matchedDisbursementFee -gt 0.0) {
			throw "Disbursement fee is expected to be negative, but encountered $($matchedDisbursementFee)"
		}
        $newAmount = $saleAmount + $matchedDisbursementFee
        $sale.amount = $newAmount.ToString("0.00", [Globalization.CultureInfo]::InvariantCulture)
        $disbursementTransactions = $disbursementTransactions | Where-Object { $_ -ne $matchedDisbursement }
    }
}

# Log remaining unmatched disbursements
foreach ($d in $disbursementTransactions) {
	$fee = Parse-DollarAmount $d.totalCommissionsAndFees
	if ($fee -ne 0.0) {
		Write-Warning "Unmatched disbursement with a fee, manual handling required: Date=$($d.eventDate), Amount=$(Parse-DollarAmount $d.amount), Fees=$($fee)"
	}
}

# The new REST API is rate-limited. We need to fetch data for the interval, and then sample the specific days.
$rates = Get-SEKUSDPMIAtDateRange $(foreach ($txn in ($saleTransactions + $dividendTransactions)) {
	if ($txn.transactionDetails) {
		$txn.transactionDetails | ForEach-Object {
			$detail = $_
			
			$closingDate = [datetime]::ParseExact($txn.eventDate, "MM/dd/yyyy", $null)
			$vestDateStr = if ($detail.type -eq "ESPP") { $detail.purchaseDate } else { $detail.vestDate }
			
			$openingDate = [datetime]::ParseExact($vestDateStr, "MM/dd/yyyy", $null)
			$openingDate, $closingDate
		}
	} else {
		[datetime]::ParseExact($txn.eventDate, "MM/dd/yyyy", $null)
	}
})

$k4 = @()
$totalClosing = 0.0
$totalClosingSEK = 0
$totalOpening = 0.0
$totalOpeningSEK = 0
$totalGains = 0
$totalGainsSEK = 0
$totalLosses = 0
$totalLossesSEK = 0

foreach ($ct in $saleTransactions)
{
	$quantity = [int]::Parse($ct.quantity, [Globalization.CultureInfo]::InvariantCulture)
	
	# Validate shares sum matches transaction total
    $totalDetailShares = 0
    foreach ($detail in $ct.transactionDetails) {
        $totalDetailShares += [int]::Parse($detail.shares, [Globalization.CultureInfo]::InvariantCulture)
    }
	if ($totalDetailShares -ne $quantity) {
        throw "Share quantity mismatch in transaction from $($ct.eventDate) for $($ct.amount). Details sum: $totalDetailShares, Transaction total: $quantity"
    }
	
	$txDate = [datetime]::ParseExact($ct.eventDate, "MM/dd/yyyy", $null)
	$txRate = Get-SEKUSDPMIAtDate $rates $txDate
	
	$totalTx = Parse-DollarAmount $ct.amount
	$totalTxSEK = $totalTx * $txRate
	foreach ($detail in $ct.transactionDetails)
    {
		$detailShares = [int]::Parse($detail.shares, [Globalization.CultureInfo]::InvariantCulture)
		$detailProportion = [double]$detailShares / [double]$quantity
		
		$closingTransTotalProceeds = [math]::Max(0.0, [math]::Round($totalTx * $detailProportion, 2))
		$closingTransTotalProceedsSEK = [math]::Max(0, [int][math]::Round($totalTxSEK * $detailProportion))

		$vestDateStr = if ($detail.type -eq "ESPP" ) { $detail.purchaseDate } else { $detail.vestDate }
		$txDate = [datetime]::ParseExact($vestDateStr, "MM/dd/yyyy", $null)
		$txRate = Get-SEKUSDPMIAtDate $rates $txDate

		$vestFmvStr = if ($detail.type -eq "ESPP" ) { $detail.purchaseFairMarketValue } else { $detail.vestFairMarketValue }
		$tx = [double]$detailShares * (Parse-DollarAmount($vestFmvStr))
		$txSEK = [int][math]::Round($tx * $txRate)

		$openingTransAdjCostBasis = [math]::Max(0.0, $tx)
		$openingTransAdjCostBasisSEK = [math]::Max(0, $txSEK)
		
		$result = [math]::Round($closingTransTotalProceeds - $openingTransAdjCostBasis, 2)
		if ($result -ge 0.0) {
			$totalGains += $result
			$totalGainsSEK += $closingTransTotalProceedsSEK - $openingTransAdjCostBasisSEK
		} else {
			$totalLosses += $result
			$totalLossesSEK += $closingTransTotalProceedsSEK - $openingTransAdjCostBasisSEK
		}
		$totalClosing += $closingTransTotalProceeds
		$totalClosingSEK += $closingTransTotalProceedsSEK
		$totalOpening += $openingTransAdjCostBasis
		$totalOpeningSEK += $openingTransAdjCostBasisSEK

		$k4 += [ordered]@{
			"Purchased" = $vestDateStr;
			"Sold" =  $ct.eventDate;
			"Symbol" = $ct.symbol;
			"Antal/QTY"  = $detailShares;
			"Försäljningspris SEK" = $closingTransTotalProceedsSEK;
			"Omkostnadsbelopp SEK" = $openingTransAdjCostBasisSEK;
			"Closing Proceeds USD" = $closingTransTotalProceeds;
			"Purchase Price USD" = $openingTransAdjCostBasis;
			"Type" = $detail.type;
		}
	}
}

$totalClosing = [math]::Round($totalClosing)
$totalOpening = [math]::Round($totalOpening)

Write-Warning "Please note that while this script generally does account for fees and commisions (by using Amount: The dollar value of the transaction after the deduction of any commissions and fees), it is only smart enough to include disbursement fees if they match exactly with the sum of the transaction, optionally including a single dividend event.`n`nIf you accumulated cash from multiple sales before wiring it out, keeping track of where to add the wire fee in this case is beyond the scope of this script."

Write-Output "`n=== K4 ===`nMarknadsnoterade aktier, adktieindexobligationer, aktieoptioner m.m. / Listed shares, share index bonds, share options, etc."

$k4 | ForEach {[PSCustomObject]$_} | Format-Table -AutoSize

$totals = @( @{'Valuta' = "SEK";
'Summa vinster' = $totalGainsSEK;
'Summa förluster' = $totalLossesSEK;
'Summa forsäljningspris' = $totalClosingSEK;
'Summa omkostnadsbelopp'  = $totalOpeningSEK;
}, @{'Valuta' = "USD";
'Summa vinster' = $totalGains;
'Summa förluster' = $totalLosses;
'Summa forsäljningspris' = $totalClosing;
'Summa omkostnadsbelopp'  = $totalOpening;
}) 
$totals | ForEach {[PSCustomObject]$_} | Format-Table -AutoSize

$totalDividendUSD = 0.0
$totalTaxUSD = 0.0
$totalDividendSEK = 0
$totalTaxSEK = 0

foreach ($ct in $dividendTransactions)
{
	$txDate = [datetime]::ParseExact($ct.eventDate, "MM/dd/yyyy", $null)
	$txRate = Get-SEKUSDPMIAtDate $rates $txDate
	
	$tx = Parse-DollarAmount $ct.amount
	$txSEK = [int][math]::Round($tx * $txRate)
	$txTax = Parse-DollarAmount $ct.taxAmount
	$txTaxSEK = [int][math]::Round($txTax * $txRate)
	
	$dividendUSD = [math]::Max(0.0, $tx)
	$taxUSD = [math]::Min(0.0, $txTax)
	$dividendSEK = [math]::Max(0, $txSEK)
	$taxSEK = [math]::Min(0, $txTaxSEK)
	
	$totalDividendUSD += $dividendUSD
	$totalTaxUSD += $taxUSD
	$totalDividendSEK += $dividendSEK
	$totalTaxSEK += $taxSEK
}

$totalDividendUSD = [math]::Round($totalDividendUSD, 2)
$totalTaxUSD = [math]::Round($totalTaxUSD, 2)

Write-Output "`n=== Dividends ==="
$totals = New-Object PSObject |
	Add-Member -Type NoteProperty -Name 'Gross Income (Box 2) [Cross-check with 1042-S!]' -Value $totalDividendUSD -PassThru |
	Add-Member -Type NoteProperty -Name 'Federal Tax Withheld (Box 7a) [Cross-check with 1042-S!]' -Value $totalTaxUSD -PassThru |
	Add-Member -Type NoteProperty -Name 'Ränteinkomster, utdelningar m.m. 7.2' -Value $totalDividendSEK -PassThru |
	Add-Member -Type NoteProperty -Name 'Övriga upplysningar -> Avräkning av utländsk skatt' -Value $totalTaxSEK -PassThru
$totals | Format-List
