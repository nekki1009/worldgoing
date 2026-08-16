class_name PaperDollV2Validator
extends RefCounted

## Single admission boundary for V2 templates and manifests.
##
## The validator intentionally delegates the field-level checks to the data
## objects that own those contracts.  Keeping this entry point small gives
## packers, editor tools and tests one stable API without creating a second
## source of truth for dimensions or layer rules.

static func validate_template(template: PaperDollV2BodyTemplate) -> PackedStringArray:
	if template == null:
		return PackedStringArray(["null body template"])
	return template.validation_issues()

static func validate_manifest(
	manifest: PaperDollV2AssetManifest,
	template: PaperDollV2BodyTemplate = null
) -> PackedStringArray:
	if manifest == null:
		return PackedStringArray(["null asset manifest"])
	return manifest.validation_issues(template)

static func validate_catalog(catalog: PaperDollV2Catalog) -> PackedStringArray:
	if catalog == null:
		return PackedStringArray(["null V2 catalog"])
	return catalog.validation_issues()
