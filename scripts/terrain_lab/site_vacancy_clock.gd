extends RefCounted
## R5 S9 (pure): the owner's proven political day for a vacancy clock (plan 475, owner seat progress on episode 232).
## The owner's day is the latest G0 proven day stamped on a person affiliated with that owner. Only stored PersonSocial v3
## stamps are read (proven.day, written when a person was observed on that day and the next). Nothing is derived from the
## current state, from unobserved days, or from the controlled person alone. An unaffiliated person's stamp is ignored.

const SiteSocial := preload("res://scripts/terrain_lab/site_social.gd")

## A person is affiliated with the owner when its stored social packet already records a relation to the owner's org key.
static func affiliated(packet: Dictionary, owner_ref: Dictionary) -> bool:
	var orgs: Variant = packet.get("orgs", {})
	return orgs is Dictionary and orgs.has(SiteSocial.org_key(owner_ref))

## The latest proven day among the affiliated packets; -1 when none carries a proven stamp.
static func owner_proven_day(packets: Array, owner_ref: Dictionary) -> int:
	var latest := -1
	for packet: Variant in packets:
		if not packet is Dictionary or not affiliated(packet, owner_ref): continue
		var proven: Variant = packet.get("proven", {})
		if not proven is Dictionary or proven.is_empty() or not proven.has("day"): continue
		latest = maxi(latest, int(proven.day))
	return latest
