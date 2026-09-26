ArmorMakesSense = ArmorMakesSense or {}

ArmorMakesSense.MP = ArmorMakesSense.MP or {}
local MP = ArmorMakesSense.MP

MP.NET_MODULE = "ArmorMakesSenseRuntime"
MP.HARNESS_PING_COMMAND = "harness_ping"
MP.DIAG_COMMAND = "diag"
MP.REQUEST_SNAPSHOT_COMMAND = "request_snapshot"
MP.SNAPSHOT_COMMAND = "snapshot"
MP.DIAG_DUMP_REQUEST_COMMAND = "diag_dump_request"
MP.DIAG_DUMP_COMMAND = "diag_dump"
MP.SNAPSHOT_REQUEST_MIN_SECONDS = 5
MP.SNAPSHOT_REQUEST_TIMEOUT_SECONDS = 60
MP.SNAPSHOT_UI_REFRESH_SECONDS = 30
MP.SCRIPT_VERSION = "2.0.1"
MP.SCRIPT_BUILD = "ams-b42-2026-09-26-v201"

return MP
