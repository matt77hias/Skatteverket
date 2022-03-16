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
		$groups = $([xml]$(Invoke-WebRequest -Method Post -Headers @{'Content-Type'='application/soap+xml;charset=utf-8;action=urn:getInterestAndExchangeRates'} -Body $body -Uri 'https://swea.riksbank.se/sweaWS/services/SweaWebServiceHttpSoap12Endpoint' -UseBasicParsing)."Content").Envelope.body.getInterestAndExchangeRatesResponse.return.groups
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
$totalOpening = 0
$totalGain = 0
$totalLoss = 0
