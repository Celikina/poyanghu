extends RefCounted
## T = B + M. Both populations share the same environmental coefficient.
const BASE_CAP := 60
const MIGRANT_CAP := 40
const SEASON_CAPACITY := {"spring": 8, "summer": 4, "autumn": 20, "winter": 40}
## 留湖基数单回合最多掉这么多点（恢复方向不限速）。
## 环境撞到 habitat() 里「植被 < 42 或 水质 < 45」那条台阶时，系数会从 0.7 左右直接摔到
## 0.3，按比例一步就是 60 → 25 的腰斩，生态红线（0.1.28 那版是「开局留湖 × 88%」）当场判负，
## 玩家连补水补种的机会都没有 —— 0.1.29 困难档实测「开局必被候鸟扣死」。限速之后退化
## 仍是连续的，但每一次结算最多掉 6 点，够玩家看清趋势再救。
const BASE_DROP_STEP := 6

static func snapshot(saved: Dictionary, total: int, season: String) -> Dictionary:
	total = clampi(total, 0, 100)
	if not saved.is_empty() and int(saved.get("total", -1)) == total \
			and int(saved.get("base", -1)) >= 0 and int(saved.get("base", -1)) <= 80 \
			and int(saved.get("migrants", -1)) >= 0 and int(saved.get("migrants", -1)) <= 40 \
			and int(saved.get("base", -1)) + int(saved.get("migrants", -1)) == total:
		var restored := saved.duplicate(true)
		for field in ["base", "migrants", "total"]: restored[field] = int(saved[field])
		# Convert the previous 80-point base cap without discarding total or injury history.
		if restored["base"] > BASE_CAP:
			restored["base"] = BASE_CAP
			restored["migrants"] = total - BASE_CAP
			restored.erase("base_reference")
		if restored.has("habitat"): restored["habitat"] = int(restored["habitat"])
		if restored.has("year"): restored["year"] = int(restored["year"])
		for field in ["base_reference", "base_environment", "environment_score"]:
			if restored.has(field): restored[field] = int(restored[field])
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
	return clampi(suitability, 0, 100)

static func environment_coefficient(suitability: int) -> float:
	# Suitable habitat admits the full winter cohort. Half-suitable habitat
	# admits half; severely degraded habitat admits almost none.
	return clampf(float(suitability - 20) / 60.0, 0.0, 1.0)

static func anchor_environment(saved: Dictionary, suitability: int) -> Dictionary:
	var out := saved.duplicate(true)
	var score := clampi(suitability - 20, 0, 60)
	out["environment_score"] = score
	out["base_reference"] = int(saved["base"])
	out["base_environment"] = score if score > 0 else 60
	out["habitat"] = suitability
	return out

static func arrivals(saved: Dictionary, season: String, suitability: int, return_loss: int = 0, year: int = 0) -> Dictionary:
	var out := saved.duplicate(true)
	var coefficient := environment_coefficient(suitability)
	# Preserve the opening count and card investments. Re-evaluate against the
	# same reference instead of multiplying by a poor habitat every turn.
	if not out.has("base_reference"):
		out = anchor_environment(out, int(saved.get("habitat", suitability)))
	var score := clampi(suitability - 20, 0, 60)
	var target := clampi(roundi(float(int(out["base_reference"]) * score) / maxi(1, int(out["base_environment"]))), 0, BASE_CAP)
	# 退化按比例算、但单回合掉幅封顶（见 BASE_DROP_STEP）：不然环境一撞台阶就是腰斩，
	# 判负即刻发生。恢复方向不设限速 —— 补种、护鸟这类投入本来就该立竿见影。
	var previous := clampi(int(saved.get("base", target)), 0, BASE_CAP)
	out["base"] = target if target >= previous else maxi(target, previous - BASE_DROP_STEP)
	# Once the resident cap is reached, discard invisible surplus. Subsequent
	# habitat deterioration must affect the actual sixty birds proportionally.
	if out["base"] == BASE_CAP and score > 0:
		out["base_reference"] = BASE_CAP
		out["base_environment"] = score
	out["environment_score"] = score
	out["loss"] = int(saved["loss"]) if str(saved["season"]) == season and (year == 0 or int(saved.get("year", year)) == year) else 0
	out["season"] = season
	if year > 0: out["year"] = year
	var arriving := roundi(float(SEASON_CAPACITY[season]) * coefficient)
	var returning_loss := int(SEASON_CAPACITY[season]) * return_loss / 40
	# Subtract injuries after the total cap: a crowded lake must not silently
	# refill actually injured birds when the same winter is recalculated.
	var capacity := mini(arriving, 100 - int(out["base"]))
	out["migrants"] = maxi(0, capacity - int(out["loss"]) - returning_loss)
	out["total"] = int(out["base"]) + int(out["migrants"])
	out["habitat"] = suitability
	return out

static func project(saved: Dictionary, season: String, suitability: int, _loss_multiplier: float, return_loss: int = 0, year: int = 0) -> Dictionary:
	# Difficulty already affects water/vegetation/quality. Do not multiply B's
	# losses again while leaving M on a different environmental coefficient.
	return arrivals(saved, season, suitability, return_loss, year)

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
		var score := int(out.get("environment_score", -1))
		if score > 0:
			out["base_reference"] = int(out["base"])
			out["base_environment"] = score
		elif score == 0 and delta != 0:
			out["base_reference"] = maxi(0, int(out.get("base_reference", out["base"])) + delta)
	out["total"] = int(out["base"]) + int(out["migrants"])
	return out
