# Skatteverket

[etrade]: https://us.etrade.com/home/welcome-back
[schwab]: https://www.schwab.com/client-home
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
2. Go to _Stock Plan_ -> _Tax Information_ -> _Cost Basis_.
3. Open the web browser inspector (_e.g., press `F12` in Google Chrome_).
4. Use the `Network` tab to record the outgoing HTTP requests.
5. _Optionally_ click the `Clear` button to get rid of the clutter.
6. Select the tax year and click `Apply`. A `gainsLosses.json` should appear in the `Network` view.
7. Click `gainsLosses.json`. The view will change, switch to the `Response` tab. Click the toggle to display `Raw` data, if there is one.
8. Copy-paste the contents of that tab, save it as `gainsLosses.json`.
9. Run the `./EtradeK4.ps1` script in the directory containing `gainsLosses.json`. This can take a while since it asks Riksbank's API for the exchange rates at the different dates.
10. Enjoy a clear table with SEK-converted values, rounded to full kronor, and ready to be copied into the [K4][k4] form.

### Compute [K4][k4] and dividends from [Schwab][schwab]

**Script**: `Scripts/SchwabK4+Dividends.ps1`

**Usage**:
1. Log into [Schwab][schwab].
2. Go to _Transaction History_.
3. Open the web browser inspector (_e.g., press `F12` in Firefox_).
4. Use the `Network` tab to record the outgoing HTTP requests.
5. _Optionally_ click the `Clear` button to get rid of the clutter.
6. Select the _Date range_ (_Previous Year_, most likely) and click `Search`. A `transactions` item should appear in the `Network` view.
7. Click `transactions`. The view will change, switch to the `Response` tab. Click the toggle to display `Raw` data, if there is one.
8. Copy-paste the contents of that tab, save it as `transactions.json`.
9. Run the `./SchwabK4+Dividends.ps1` script in the directory containing `transactions.json`. This can take a while since it asks Riksbank's API for the exchange rates at the different dates.
10. Enjoy a clear table with SEK-converted values, rounded to full kronor, and ready to be copied into the [K4][k4] form, and/or field 7.2 of the declaration (Ränteinkomster, utdelningar m.m.).
