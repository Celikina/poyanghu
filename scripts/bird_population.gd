extends RefCounted
## Bird abundance and population health are separate. All helpers are pure.
const BASE_CAP := 80 # Leave room for existing long-term protection cards.
const SEASON_CAPACITY := {"spring": 8, "summer": 4, "autumn": 20, "winter": 40}

static func snapshot(saved: Dictionary, total: int, season: String) -> Dictionary:
	if not saved.is_empty() and int(saved.get("total", -1)) == total \
			and int(saved.get("base", -1)) >= 0 and int(saved.get("base", -1)) <= BASE_CAP \
			and int(saved.get("migrants", -1)) >= 0 and int(saved.get("migrants", -1)) <= 40 \
			and int(saved.get("base", -1)) + int(saved.get("migrants", -1)) == total:
		var restored := saved.duplicate(true)
		for field in ["base", "migrants", "total"]: restored[field] = int(saved[field])
		if restored.has("habitat"): restored["habitat"] = int(restored["habitat"])
		if restored.has("year"): restored["year"] = int(restored["year"])
		restored["loss"] = clampi(int(saved.get("loss", 0)), 0, 40)
		restored["season"] = str(saved.get("season", season))
		if not SEASON_CAPACITY.has(restored["season"]): restored["season"] = season
		return restored
	# Legacy saves keep their displayed value and do not invent a health deficit.
	var base := clampi(total, 0, BASE_CAP)
	return {"base": base, "migrants": maxi(0, total - base), "loss": 0,
		"season": season, "total": total}

static func habitat(metrics: Dictionary, deviation: int) -> int:
	var water := 100 if deviation == 0 else (70 if deviation <= 10 else 40)
	var vegetation := int(metrics.get("vegetation", 0))
	var quality := int(metrics.get("water_quality", 0))
	var suitability := (40 * vegetation + 30 * quality + 30 * water) / 100
	# A critical food/quality shortage cannot be hidden by a weighted average.
	if vegetation < 42 or quality < 45: suitability = mini(suitability, 39)
	if vegetation < 20 or quality < 20: suitability = mini(suitability, 19)
	if int(metrics.get("fish", 0)) < 25: suitability = mini(suitability, 59)
	return clampi(suitability, 0, 100)

static func arrivals(saved: Dictionary, season: String, suitability: int, return_loss: int = 0, year: int = 0) -> Dictionary:
	var out := saved.duplicate(true)
	out["loss"] = int(saved["loss"]) if str(saved["season"]) == season and (year == 0 or int(saved.get("year", year)) == year) else 0
	out["season"] = season
	if year > 0: out["year"] = year
	var arriving := int(SEASON_CAPACITY[season]) * suitability / 100
	var returning_loss := int(SEASON_CAPACITY[season]) * return_loss / 40
	# Subtract injuries after the total cap: a crowded lake must not silently
	# refill actually injured birds when the same winter is recalculated.
	var capacity := mini(arriving, 100 - int(out["base"]))
	out["migrants"] = maxi(0, capacity - int(out["loss"]) - returning_loss)
	out["total"] = int(out["base"]) + int(out["migrants"])
	out["habitat"] = suitability
	return out

static func project(saved: Dictionary, season: String, suitability: int, loss_multiplier: float, return_loss: int = 0, year: int = 0) -> Dictionary:
	var out := saved.duplicate(true)
	var change := 2 if suitability >= 80 else (1 if suitability >= 60 else (0 if suitability >= 40 else (-2 if suitability >= 20 else -4)))
	if change < 0: change = roundi(change * loss_multiplier)
	out["base"] = clampi(int(saved["base"]) + change, 0, BASE_CAP)
	return arrivals(out, season, suitability, return_loss, year)

static func change(saved: Dictionary, delta: int, migrant_only: bool = false, rescue: bool = false) -> Dictionary:
	var out := saved.duplicate(true)
	if delta < 0 and migrant_only:
		var taken := mini(-delta, int(out["migrants"]))
		out["migrants"] = int(out["migrants"]) - taken
		out["loss"] = int(out["loss"]) + taken
	else:
		if delta > 0 and rescue:
			var recovered := mini(delta, mini(int(out["loss"]), 100 - int(out["total"])))
			out["loss"] = int(out["loss"]) - recovered
			out["migrants"] = int(out["migrants"]) + recovered
			delta -= recovered
		out["base"] = clampi(int(out["base"]) + delta, 0, BASE_CAP)
		out["migrants"] = mini(int(out["migrants"]), 100 - int(out["base"]))
	out["total"] = int(out["base"]) + int(out["migrants"])
	return out
