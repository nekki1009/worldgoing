class_name SiteRuntimeCommandResult
extends RefCounted

const SiteRuntimeFailureReasonType = preload("res://scripts/runtime/site_runtime_failure_reason.gd")

var success: bool = false
var changed: bool = false
var site_id: String = ""
var revision: int = 0
var failure_reason: int = SiteRuntimeFailureReasonType.Code.NONE
