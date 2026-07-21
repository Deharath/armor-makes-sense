local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = { Testing = {} }

local writes = {}
local closeCount = 0
local writer = {
    writeln = function(_, line)
        writes[#writes + 1] = tostring(line)
    end,
    close = function()
        closeCount = closeCount + 1
    end,
}

getFileWriter = function()
    return writer
end
getSandboxFileWriter = nil

local Snapshot = dofile(
    (os.getenv("AMS_ROOT") or ".")
        .. "/common/media/lua/client/testing/ArmorMakesSense_BenchRunnerSnapshot.lua"
)

local runner = {
    id = "stream-test",
    label = "regression",
    preset = "benchmark_breathing_quick",
    mode = "sim",
    speedReq = 8,
    repeats = 1,
    setsApplied = 1,
    scenariosApplied = 1,
    total = 1,
    index = 0,
    scriptVersion = "1.3.0",
    scriptBuild = "test",
    startedAt = 10,
    snapshot = { lines = {} },
    stepResults = {},
}

local opened, path, openError = Snapshot.openStreamWriter(runner)
Support.assertTrue(opened, openError or "stream opens")
Support.assertEqual(path, "benchlogs/bench_regression_stream-test.log", "stream path")
Snapshot.streamAppend(runner, "[AMS_BENCH_START] id=stream-test preset=benchmark_breathing_quick", "start")
Snapshot.streamLine(runner, "[AMS_BENCH_SAMPLE] id=stream-test tag=breathing_live_native_driver")
runner.index = 1
Snapshot.streamAppend(runner, "[AMS_BENCH_DONE] id=stream-test reason=completed", "done")

local finalized, finalPath, finalError = Snapshot.finalizeBenchLog(
    runner,
    "completed",
    function() return 16 end,
    0.05
)
Support.assertTrue(finalized, finalError or "stream finalizes")
Support.assertEqual(finalPath, path, "stream remains the final artifact")
Support.assertEqual(closeCount, 1, "stream closes once")

local text = table.concat(writes, "\n")
Support.assertTrue(string.find(text, "run_id=stream-test", 1, true) ~= nil, "parser metadata precedes markers")
Support.assertTrue(string.find(text, "breathing_live_native_driver", 1, true) ~= nil, "stream-only sample survives finalization")
Support.assertTrue(string.find(text, "# AMS Bench Completion", 1, true) ~= nil, "completion metadata appended")
Support.assertTrue(string.find(text, "completed_steps=1", 1, true) ~= nil, "completion state recorded")

print("ams benchmark stream snapshot checks passed")
