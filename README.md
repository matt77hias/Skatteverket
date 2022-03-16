# Skatteverket

[etrade]: https://us.etrade.com/home/welcome-back
[k4]:     https://www.skatteverket.se/privat/etjansterochblanketter/blanketterbroschyrer/blanketter/info/2104.4.39f16f103821c58f680006244.html

## Features

### Compute dividends from [E*Trade][etrade]

**Script**: `Scripts/EtradeDividends.ps1`

**Usage**:
1. Log into [E*Trade][etrade].
2. Go to _Stock Plan_ -> _Holdings_ -> _Other Holdings_.
3. Open the web browser inspector (_e.g., press `F12` in Google Chrome_).
4. Use the `Network` tab to record the outgoing HTTP requests.
5. _Optionally_ click the `Clear` button to get rid of the clutter.
6. Expand the `Cash` section. A `getCashTransactions.json` should appear in the `Network` view.
7. Click `getCashTransactions.json`. The view will change, switch to the `Response` tab.
8. Copy-paste the contents of that tab, save it as `getCashTransactions.json`.
9. Run the `./EtradeDividends.ps1` in the directory containing the `getCashTransactions.json`. This can take a while since it asks Riksbank's API for the exchange rates at the different dates.
10. Enjoy a clear list with SEK-converted values, rounded to full kronor.
11. Cross-check the USD amounts with the 1042-S form from [E*Trade][etrade]. (`getCashTransactions.json` only looks back 365 days.)

### Compute [K4][k4] from [E*Trade][etrade]

**Script**: `Scripts/EtradeK4.ps1`

**Usage**:
1. Log into [E*Trade][etrade].
1. Go to _Stock Plan_ -> _Tax Information_ -> _Cost Basis_.
2. Open the web browser inspector (_e.g., press `F12` in Google Chrome_).
3. Use the `Network` tab to record the outgoing HTTP requests.
4. _Optionally_ click the `Clear` button to get rid of the clutter.
5. Select the tax year and click `Apply`. A `gainsLosses.json` should appear in the `Network` view.
6. Click `gainsLosses.json`. The view will change, switch to the `Response` tab.
7. Copy-paste the contents of that tab, save it as `gainsLosses.json`.
8. Run the `./EtradeK4.ps1` in the directory containing the `gainsLosses.json`. This can take a while since it asks Riksbank's API for the exchange rates at the different dates.
9. Enjoy a clear table with SEK-converted values, rounded to full kronor, and ready to be copied into the K4 form.
