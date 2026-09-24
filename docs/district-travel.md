# District travel and dashboard heat

The dashboard reads personal scavenging heat for the player's current district from travel_state. It no longer labels the district's fixed police setting as personal heat. Heat rises on completed searches through the existing heat trigger, cools using the existing owner settings, and remains isolated by player, district and season.

Travel defaults: walking 120 seconds/free; train 45 seconds/$50; driving 20 seconds/5 fuel. All routes use these flat durations. Cars must be owned, stored vehicles. Their new 100-unit tanks start empty; players can buy up to 10 fuel per click at $10/unit. Travel settings are available in Owner → Economy. Fuel is attached to each car, not an inventory commodity.

District pages and the Scavenging district selector show the travel panel before entry. The city map and remote management pages remain browsable. Scavenging and first-person movement validate current location on the server. Pending street actions and pursuits prevent departure. Prisoners cannot depart; incarceration moves their location to Blackwater Island. Timers run in real time and persist across refreshes; new travel/refuelling actions require an open season. Arrivals are settled by the next state read. There is no cancellation/refund after departure.

Fares and fuel are charged atomically at departure, under the economy lock, with immutable request receipts. Retrying an uncertain request reuses its ID. Fuel, car ownership, cash, destination lockdown and timings are checked server-side. Owner-configured durations/costs are captured by charging and recording the arrival time at departure.

Tests cover heat/location isolation, authoritative fares and timings, overlap blocking, persistent arrival, empty tanks, refuelling, fuel consumption, ownership, retry safety, walking, insufficient cash, closed seasons and movement bypass. Browser checks cover dashboard heat, driving/refuel choices, refresh persistence, arrival and mobile layout.
