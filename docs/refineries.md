# Player-owned refineries
The first site is Copper Quay Refinery on new Waterfront plot RF-01. Buying it uses the existing server-priced property sale and tax transaction. Attached business, building and stocked bunker fuel transfer with the title. Players can also construct the refinery building on permitted industrial plots.

Customers choose a recipe and batch count, then review an immutable preview before confirming. The server checks the current season, district, owner, tariff version, recipe version, input stock, cash and refinery fuel. Stale previews are rejected. Transactions consume ore and the owner's bunker fuel, credit refined output and pay either a cash fee or an output percentage. All-or-nothing settlement and request IDs prevent duplicate charges or output.

Initial recipes: 20 iron ore → 10 iron ingots; 20 copper ore → 10 copper ingots. Both burn 5 coal per batch. Default fees: $20 per batch or 10% of the output; one fee mode applies. Whole-item output fees round up, visible before confirmation. Owners processing their own ore pay no service fee but still consume ore and fuel.

The proprietor loads coal from their market inventory; bunker fuel is never supplied for free. Coal may also be mined through the existing public or owned mines. No new fuel commodity or Drilling Shore access is enabled. Recipe fuel is a database commodity reference so crude oil can be configured once its future system is launched.

Owner → Refineries & refining controls recipes. Existing economy settings control fee limits, batch limits, bunker capacity and defaults. Existing district controls manage building prices, zoning, plot titles and opening status. Fuel movements, receipt history and administrative changes are recorded. Cash charges and owner payouts always have ledger entries. Fuel held in bunkers stays included in net worth.

Property/stock are seasonal. Previous receipts remain immutable; new seasons start from the catalog with city titles and empty fuel bunkers. Refined output uses the existing player market and auctions.

The interface reuses the dashboard HUD, foundry artwork and commodity presentation. Navigation is through Dashboard → Refineries, mining equipment, or a district refinery's business detail panel. Browser and PostgreSQL tests run in GitHub Actions only.

