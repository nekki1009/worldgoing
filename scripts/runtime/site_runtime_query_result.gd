class_name SiteRuntimeQueryResult
extends RefCounted

const SiteRuntimeFailureReasonType = preload("res://scripts/runtime/site_runtime_failure_reason.gd")

var success: bool = false
var site_id: String = ""
var revision: int = 0
var snapshot: SiteRuntimeSnapshot
var failure_reason: int = SiteRuntimeFailureReasonType.Code.NONE
