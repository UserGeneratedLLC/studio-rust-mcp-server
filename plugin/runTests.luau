return function(TestEZ)
	local MCPPlugin = script.Parent

	local results = TestEZ.TestBootstrap:run({ MCPPlugin })

	assert(results.failureCount == 0 and #results.errors == 0, `Tests failed: {results.failureCount} failures, {#results.errors} errors`)
end
