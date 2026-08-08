class_name DeterministicHash
extends RefCounted

const MODULUS: int = 2_147_483_647
const MIX_A: int = 374_761_393
const MIX_B: int = 668_265_263
const MIX_C: int = 1_442_695_041
const MIX_D: int = 1_274_126_177
const MIX_E: int = 1_668_919_233

static func value(world_seed: int, candidate_cell: Vector2i, salt: int) -> int:
	var mixed: int = posmod(world_seed, MODULUS)
	mixed = posmod(mixed + candidate_cell.x * MIX_A, MODULUS)
	mixed = posmod(mixed + candidate_cell.y * MIX_B, MODULUS)
	mixed = posmod(mixed + salt * MIX_C, MODULUS)
	# Non-linear integer mixing keeps independent salts from sharing the same bias.
	mixed = mixed ^ (mixed >> 16)
	mixed = posmod(mixed * MIX_D, MODULUS)
	mixed = mixed ^ (mixed >> 13)
	mixed = posmod(mixed * MIX_E, MODULUS)
	return posmod(mixed ^ (mixed >> 16), MODULUS)

static func normalized(world_seed: int, candidate_cell: Vector2i, salt: int) -> float:
	return float(value(world_seed, candidate_cell, salt)) / float(MODULUS - 1)

static func int_range(world_seed: int, candidate_cell: Vector2i, salt: int, minimum: int, maximum: int) -> int:
	if maximum <= minimum:
		return minimum
	var span: int = maximum - minimum + 1
	var index: int = mini(floori(normalized(world_seed, candidate_cell, salt) * float(span)), span - 1)
	return minimum + index
