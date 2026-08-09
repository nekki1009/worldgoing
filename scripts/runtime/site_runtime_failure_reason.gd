class_name SiteRuntimeFailureReason
extends RefCounted

enum Code {
	NONE,
	INVALID_SITE_ID,
	SITE_NOT_FOUND,
	SITE_IDENTITY_MISMATCH,
	INVALID_FEATURE_ID,
	DUPLICATE_FEATURE,
	FEATURE_NOT_FOUND,
}

static func to_code(reason: int) -> String:
	match reason:
		Code.INVALID_SITE_ID:
			return "INVALID_SITE_ID"
		Code.SITE_NOT_FOUND:
			return "SITE_NOT_FOUND"
		Code.SITE_IDENTITY_MISMATCH:
			return "SITE_IDENTITY_MISMATCH"
		Code.INVALID_FEATURE_ID:
			return "INVALID_FEATURE_ID"
		Code.DUPLICATE_FEATURE:
			return "DUPLICATE_FEATURE"
		Code.FEATURE_NOT_FOUND:
			return "FEATURE_NOT_FOUND"
		_:
			return "NONE"
