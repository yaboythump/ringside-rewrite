# Clutch Bets original web source recovery

Source recovered with read-only access on November 21, 2026 from the owner's connected AppDeploy app `clutch-bets-a87y77`, version `1793757079956` (November 4, 2026).

This is **the deployed Clutch Bets web app**, not verified to be identical to the user's installed TestFlight iOS wrapper. The user reports the installed app repeatedly refreshing. This copy preserves the source for a separate V2 rebuild. It does not change the old deployed app, its data, its existing TestFlight binary, or its App Store record.

## Original features
- Dashboard with summary metrics, filters, searchable game lines and player props.
- Games: league filter and moneyline selections.
- Player Props: Over/Under selection and illustrative historical rate columns.
- My Picks: locally saved slips, statuses Draft/Placed/Won/Lost/Void, delete.
- Bet Slip: stake and combined payouts, sportsbook selection and external sportsbook links.
- AI Capper Studio: market-sourced signals, cross-book estimates and model scoring, model results ledger, $25 units, daily refresh and grading jobs.
- Coach Clutch Studio: presenter script preparation.
- Optional API integrations: The Odds API v4 for moneyline/spread/total data and Clutch Sports NBA props.

## Migration guardrails
- The dashboard's game lines and prop stats are **illustrative sample data**, not current sportsbook prices.
- The AppDeploy web backend requires its managed platform services; do not copy its routes into an insecure client-side secrets design.
- API credentials, existing hosted DB content, and phone-local storage are not included.
- The TestFlight refresh-loop root cause cannot be confirmed without the iOS wrapper or logs.
- V2 must use `com.ctnetworkstudios.clutchbetsv2` and leave the original bundle ID alone.
