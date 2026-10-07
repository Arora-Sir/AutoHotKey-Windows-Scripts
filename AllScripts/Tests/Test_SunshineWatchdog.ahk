#Requires AutoHotkey v2.0
#NoTrayIcon
SendMode("Input")
SetWorkingDir(A_ScriptDir . "\..")

; =============================================================================
; AUTOMATED TEST SUITE: SUNSHINE DISPLAY WATCHDOG LOGIC
; =============================================================================
; Validates stream event parsing, session termination keywords, process dormancy, boot freshness, and state transition logic with complete mock isolation.

passedCount := 0
failedCount := 0
testResults := []

Assert(testName, actual, expected) {
	global passedCount, failedCount, testResults
	if (actual == expected) {
		passedCount++
		testResults.Push("[PASS] " . testName . " (Got: '" . actual . "')")
	} else {
		failedCount++
		testResults.Push("[FAIL] " . testName . " (Expected: '" . expected . "', Got: '" . actual . "')")
	}
}

; Test runner mirroring SunshineWatchdog_LastClientEvent with process mock capability
RunClientEventTest(logContent, mockProcessRunning := true, uptimeSecOverride := 0) {
	tmpLog := A_Temp . "\sunshine_test_" . A_TickCount . "_" . Random(1000, 9999) . ".log"
	try FileDelete(tmpLog)
	if (logContent != "")
		FileAppend(logContent, tmpLog, "UTF-8")

	outConnectId := ""
	outDisconnectId := ""

	; Host process liveness guard
	if (!mockProcessRunning) {
		try FileDelete(tmpLog)
		return { event: "DISCONNECTED", connId: "", discId: "" }
	}

	if (!FileExist(tmpLog))
		return { event: "", connId: "", discId: "" }

	file := FileOpen(tmpLog, "r")
	if !IsObject(file)
		return { event: "", connId: "", discId: "" }

	LogLength := file.Length
	ReadLength := 65536
	if (LogLength > ReadLength)
		file.Seek(LogLength - ReadLength, 0)

	Text := file.Read()
	file.Close()
	try FileDelete(tmpLog)

	if (Text == "")
		return { event: "", connId: "", discId: "" }

	LastConnectedPos := 0, LastDisconnectedPos := 0, SearchPos := 1
	Loop {
		FoundPos := InStr(Text, "CLIENT CONNECTED", , SearchPos)
		if !FoundPos
			break
		LastConnectedPos := FoundPos
		SearchPos := FoundPos + 1
	}

	; Search for all session termination keywords logged by Sunshine
	disconnectKeywords := [
		"CLIENT DISCONNECTED",
		"Ping Timeout",
		"Async encoder teardown complete",
		"Connection Terminated",
		"Sunshine version:",
		"Registered Sunshine mDNS service"
	]
	for kw in disconnectKeywords {
		SearchPos := 1
		Loop {
			FoundPos := InStr(Text, kw, , SearchPos)
			if !FoundPos
				break
			if (FoundPos > LastDisconnectedPos)
				LastDisconnectedPos := FoundPos
			SearchPos := FoundPos + 1
		}
	}

	; Extract full log line containing the latest connect event
	if (LastConnectedPos > 0) {
		lineStart := InStr(SubStr(Text, 1, LastConnectedPos), "`n", false, -1)
		lineStart := (lineStart > 0) ? lineStart + 1 : 1
		lineEnd := InStr(Text, "`n", false, LastConnectedPos)
		lineLen := (lineEnd > 0) ? (lineEnd - lineStart) : (StrLen(Text) - lineStart + 1)
		outConnectId := Trim(SubStr(Text, lineStart, lineLen), "`r`n ")
	}

	; Extract full log line containing the latest disconnect or termination event
	if (LastDisconnectedPos > 0) {
		lineStart := InStr(SubStr(Text, 1, LastDisconnectedPos), "`n", false, -1)
		lineStart := (lineStart > 0) ? lineStart + 1 : 1
		lineEnd := InStr(Text, "`n", false, LastDisconnectedPos)
		lineLen := (lineEnd > 0) ? (lineEnd - lineStart) : (StrLen(Text) - lineStart + 1)
		outDisconnectId := Trim(SubStr(Text, lineStart, lineLen), "`r`n ")
	}

	if (LastConnectedPos == 0 && LastDisconnectedPos == 0)
		return { event: "", connId: outConnectId, discId: outDisconnectId }

	; Reject stale connect events recorded prior to the current Windows boot session
	if (LastConnectedPos > LastDisconnectedPos) {
		if RegExMatch(outConnectId, "\[(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})", &m) {
			connectTs := m[1] . m[2] . m[3] . m[4] . m[5] . m[6]
			try {
				connectAgeSec := DateDiff(A_Now, connectTs, "Seconds")
				systemUptimeSec := (uptimeSecOverride > 0) ? uptimeSecOverride : (A_TickCount / 1000)
				if (connectAgeSec > systemUptimeSec + 30)
					return { event: "DISCONNECTED", connId: outConnectId, discId: outDisconnectId }
			}
		}
	}

	retEvent := (LastDisconnectedPos > LastConnectedPos) ? "DISCONNECTED" : "CONNECTED"
	return { event: retEvent, connId: outConnectId, discId: outDisconnectId }
}

nowTs := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
pastTs := FormatTime(DateAdd(A_Now, -7200, "Seconds"), "yyyy-MM-dd HH:mm:ss")

; -----------------------------------------------------------------------------
; TEST SUITE EXECUTION
; -----------------------------------------------------------------------------

; 1. Clean Disconnect
log1 := "[" pastTs ".100]: Info: CLIENT CONNECTED`n[" pastTs ".200]: Info: CLIENT DISCONNECTED`n"
res1 := RunClientEventTest(log1)
Assert("Test 1: Graceful CLIENT DISCONNECTED", res1.event, "DISCONNECTED")

; 2. Ping Timeout Disconnect (The exact failure mode when network drops or app quits)
log2 := "[" pastTs ".100]: Info: CLIENT CONNECTED`n[" pastTs ".200]: Info: 192.168.1.100: Ping Timeout`n"
res2 := RunClientEventTest(log2)
Assert("Test 2: Abnormal Ping Timeout disconnect", res2.event, "DISCONNECTED")

; 3. Initial Ping Timeout
log3 := "[" pastTs ".100]: Info: CLIENT CONNECTED`n[" pastTs ".200]: Error: Initial Ping Timeout`n"
res3 := RunClientEventTest(log3)
Assert("Test 3: Initial Ping Timeout disconnect", res3.event, "DISCONNECTED")

; 4. Async encoder teardown
log4 := "[" pastTs ".100]: Info: CLIENT CONNECTED`n[" pastTs ".200]: Info: Async encoder teardown complete`n"
res4 := RunClientEventTest(log4)
Assert("Test 4: Async encoder teardown complete", res4.event, "DISCONNECTED")

; 5. Connection Terminated
log5 := "[" pastTs ".100]: Info: CLIENT CONNECTED`n[" pastTs ".200]: Info: Connection Terminated by server`n"
res5 := RunClientEventTest(log5)
Assert("Test 5: Connection Terminated message", res5.event, "DISCONNECTED")

; 6. Sunshine service restart after connect
log6 := "[" pastTs ".100]: Info: CLIENT CONNECTED`n[" pastTs ".200]: Info: Registered Sunshine mDNS service`n"
res6 := RunClientEventTest(log6)
Assert("Test 6: Sunshine restart resets stale session", res6.event, "DISCONNECTED")

; 7. Active Streaming Session (Connect occurs AFTER prior disconnect)
log7 := "[" pastTs ".100]: Info: CLIENT DISCONNECTED`n[" nowTs ".200]: Info: CLIENT CONNECTED`n"
res7 := RunClientEventTest(log7)
Assert("Test 7: Active session reports CONNECTED", res7.event, "CONNECTED")

; 8. Active Reconnect After Ping Timeout
log8 := "[" pastTs ".100]: Info: 192.168.1.100: Ping Timeout`n[" nowTs ".200]: Info: CLIENT CONNECTED`n"
res8 := RunClientEventTest(log8)
Assert("Test 8: Reconnection after timeout reports CONNECTED", res8.event, "CONNECTED")

; 9. Host Process Inactive (sunshine.exe closed)
log9 := "[" nowTs ".100]: Info: CLIENT CONNECTED`n"
res9 := RunClientEventTest(log9, false)
Assert("Test 9: Process not running returns DISCONNECTED", res9.event, "DISCONNECTED")

; 10. Stale Pre-Boot Connection (System booted 5 minutes ago, connect from 2 hours ago)
log10 := "[" pastTs ".100]: Info: CLIENT CONNECTED`n"
res10 := RunClientEventTest(log10, true, 300)
Assert("Test 10: Pre-boot connect rejected as DISCONNECTED", res10.event, "DISCONNECTED")

; 11. Empty Log
res11 := RunClientEventTest("")
Assert("Test 11: Empty log reports idle empty event", res11.event, "")

; 12. Log containing only disconnects
log12 := "[" nowTs ".100]: Info: CLIENT DISCONNECTED`n"
res12 := RunClientEventTest(log12)
Assert("Test 12: Only disconnects present reports DISCONNECTED", res12.event, "DISCONNECTED")

; 13. Manual Override Equality Logic (Simulating session boundary clearing)
savedDiscId := "[2026-09-23 17:53:20.904]: Info: 192.168.1.100: Ping Timeout"
currDiscId := savedDiscId
isOverrideClearedOnIdle := (currDiscId != "" && currDiscId != savedDiscId)
Assert("Test 13: Manual override persists while idle", isOverrideClearedOnIdle, false)

freshDiscId := "[2026-09-23 22:15:00.000]: Info: CLIENT DISCONNECTED"
isOverrideClearedOnNewEvent := (freshDiscId != "" && freshDiscId != savedDiscId)
Assert("Test 14: Manual override clears on fresh disconnect", isOverrideClearedOnNewEvent, true)

; 14. Real Live File Test
realLogPath := "C:\Program Files\Sunshine\config\sunshine.log"
localPathsFile := A_ScriptDir . "\..\LocalPaths.ahk"
if FileExist(localPathsFile) {
	try {
		content := FileRead(localPathsFile)
		if RegExMatch(content, 'PATH_SUNSHINE_LOG\s*:=\s*"([^"]+)"', &m)
			realLogPath := m[1]
	}
}
if FileExist(realLogPath) {
	liveFile := FileOpen(realLogPath, "r")
	liveText := ""
	if IsObject(liveFile) {
		len := liveFile.Length
		chunk := (len > 65536) ? 65536 : len
		liveFile.Seek(len - chunk, 0)
		liveText := liveFile.Read()
		liveFile.Close()
	}
	realRes := RunClientEventTest(liveText, ProcessExist("sunshine.exe"))
	Assert("Test 15: Real live log correctly detects DISCONNECTED", realRes.event, "DISCONNECTED")
}

; -----------------------------------------------------------------------------
; REPORT OUTPUT
; -----------------------------------------------------------------------------
report := "====================================================`n"
report .= "SUNSHINE DISPLAY WATCHDOG AUTOMATED TEST REPORT`n"
report .= "====================================================`n"
report .= "Total Tests Run: " . (passedCount + failedCount) . "`n"
report .= "Passed: " . passedCount . "`n"
report .= "Failed: " . failedCount . "`n`n"
for line in testResults {
	report .= line . "`n"
}
report .= "====================================================`n"

outReportPath := A_Temp . "\sunshine_watchdog_test_report.txt"
try FileDelete(outReportPath)
FileAppend(report, outReportPath, "UTF-8")

; Write to stdout when run from console or script runner
try FileAppend(report, "*")

if (failedCount > 0)
	ExitApp(1)
ExitApp(0)
