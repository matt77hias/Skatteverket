# Helper for acquiring the archival exchange rate for a given date.
function Get-SEKUSDPMIAtDate ([datetime]$Date)
{
	$groups = $null
	do
	{
		$body = [string]::Format('<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:xsd="http://swea.riksbank.se/xsd">
	 <soap:Header/>
	 <soap:Body>
		 <xsd:getInterestAndExchangeRates>
			 <searchRequestParameters>
				 <aggregateMethod>D</aggregateMethod>
				 <datefrom>{0}</datefrom>
				 <dateto>{0}</dateto>
				 <languageid>en</languageid>
				 <min>false</min>
				 <avg>true</avg>
				 <max>true</max>
				 <ultimo>false</ultimo>
				 <!--1 or more repetitions:-->
				 <searchGroupSeries>
					 <groupid>11</groupid>
					 <seriesid>SEKUSDPMI</seriesid>
				 </searchGroupSeries>
			 </searchRequestParameters>
		 </xsd:getInterestAndExchangeRates>
	 </soap:Body>
 </soap:Envelope>', $Date.ToString("yyyy-MM-dd"))
		$groups = $([xml]$(Invoke-WebRequest -Method Post -Headers @{'Content-Type'='application/soap+xml;charset=utf-8;action=urn:getInterestAndExchangeRates'} -SkipHeaderValidation -Body $body -Uri 'https://swea.riksbank.se/sweaWS/services/SweaWebServiceHttpSoap12Endpoint' -UseBasicParsing)."Content").Envelope.body.getInterestAndExchangeRatesResponse.return.groups
		# Scan backwards in time for the latest rate, if the response for the current is empty.
		if ($null -eq $groups) { Write-Host $([string]::Format("No exchange rate for {0}, trying the previous day", $Date.ToString("yyyy-MM-dd"))) }
		$Date = $Date.AddDays(-1.0)
	}
	while ($null -eq $groups)
	return [double]$groups.series.resultrows.value.'#text'
}

$gainsLosses = $(get-content -raw -path gainsLosses.json | ConvertFrom-Json).data.gainsAndLosses.list.gainsLossDtlsList

$k4 = @()
$totalClosing = 0
$totalClosingSEK = 0
$totalOpening = 0
$totalOpeningSEK = 0

foreach ($ct in $gainsLosses)
{
	if ($ct.transactionType -eq "Sell")
	{
		$txDate = [datetime]::ParseExact($ct.closingTransDateSold, "MM/dd/yyyy", $null)
		$txRate = Get-SEKUSDPMIAtDate($txDate)
		
		$tx = $ct.closingTransTotalProceeds
		$txSEK = [int][math]::Round($tx * $txRate)
		
		$closingTransTotalProceeds = [math]::Max(0.0, $tx)
		$closingTransTotalProceedsSEK = [math]::Max(0, $txSEK)

		$txDate = [datetime]::ParseExact($ct.openingTransDateAcquired, "MM/dd/yyyy", $null)
		$txRate = Get-SEKUSDPMIAtDate($txDate)

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
}

$totalClosing = [math]::Round($totalClosing)
$totalOpening = [math]::Round($totalOpening)

Write-Warning "Please note that this script does not include fees or commisions. Make sure to adjust against the fees in your account orders report."

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