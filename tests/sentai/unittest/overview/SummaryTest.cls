/// Spec 018 T011/T012: the 11-area summary — 10 distinct reads, headlines of research R-3,
/// independent outcomes, no report run (clarification Q1).
Class sentai.unittest.overview.SummaryTest Extends sentai.unittest.SentaiTestCase
{

Method Entry(summary As %DynamicObject, area As %String) As %DynamicObject
{
    Set it = summary.areas.%GetIterator()
    While it.%GetNext(.k, .e) { Return:(e.area = area) e }
    Quit ""
}

Method TestElevenOkEntriesWithHeadlines()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Set s = ##class(sentai.overview.OverviewService).Summary("fake-token")
    Do $$$AssertEquals(s.areas.%Size(), 11)
    Set ids = "", it = s.areas.%GetIterator()
    While it.%GetNext(.k, .e) {
        Set ids = ids_$LB(e.area)
        Do $$$AssertEquals(e.outcome, "ok", e.area_" ok")
        Do $$$AssertTrue(e.readAt '= "")
    }
    Do $$$AssertEquals($LTS(ids, ","), "processes,locks,memory,activity,devices,licenses,web-sessions,security,web-apps,alerts,secrets")

    Set h = ..Entry(s, "processes").headline
    Do $$$AssertEquals(h.count, 3)
    Do $$$AssertEquals(h.busiest.Pid, 3944)
    Do $$$AssertEquals(..Entry(s, "locks").headline.count, 2)
    Set m = ..Entry(s, "memory").headline
    Do $$$AssertEquals(m.usedPercent, 84)
    Do $$$AssertEquals(m.mostUsed.description, "Security System")
    Do $$$AssertEquals(m.mostUsed.usedPercent, 100)
    Set a = ..Entry(s, "activity").headline
    Do $$$AssertEquals(a.uptime, "0d  2h 16m")
    Do $$$AssertEquals(a.lastBackup, "Never")
    Do $$$AssertEquals(a.globalRefsPerSecond, 3841)
    Do $$$AssertEquals(a.busyProcesses, 1)
    Do $$$AssertEquals(..Entry(s, "devices").headline.count, 2)
    Set l = ..Entry(s, "licenses").headline
    Do $$$AssertEquals(l.inUse, 1)
    Do $$$AssertEquals(l.authorized, 8)
    Do $$$AssertEquals(..Entry(s, "web-sessions").headline.count, 1)
    Set sec = ..Entry(s, "security").headline
    Do $$$AssertEquals(sec.accounts, 3)
    Do $$$AssertEquals(sec.enabledAccounts, 2)
    Do $$$AssertEquals(..Entry(s, "web-apps").headline.count, 2)
    Set al = ..Entry(s, "alerts").headline
    Do $$$AssertEquals(al.seriousAlerts, 7)
    Do $$$AssertEquals(al.applicationErrors, 0)
    Do $$$AssertEquals(..Entry(s, "secrets").headline.collections, 1)
    Do $$$AssertEquals(..Entry(s, "secrets").stepType, "secrets-inventory")
    Do $$$AssertEquals(..Entry(s, "processes").%GetTypeOf("stepType"), "null")
}

Method TestTenDistinctReadsAndNoReport()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Do ##class(sentai.overview.OverviewService).Summary("fake-token")
    Set paths = ##class(sentai.unittest.overview.OverviewFixtures).HitPaths()
    Do $$$AssertEquals($L(paths, ","), 10, paths)
    Do $$$AssertEquals(##class(sentai.unittest.overview.OverviewFixtures).Hits("/api/admin/v2/monitor/dashboard/main"), 1)
    Do $$$AssertNotTrue(paths [ "security/user?", "no per-account read")
    Do $$$AssertNotTrue(paths [ "wallet/secrets", "no secret read")
}

Method TestRefusedAreaLeavesOthersOk()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Do ##class(sentai.unittest.overview.OverviewFixtures).Refuse("/api/admin/v2/security/users")
    Set s = ##class(sentai.overview.OverviewService).Summary("fake-token")
    Set e = ..Entry(s, "security")
    Do $$$AssertEquals(e.outcome, "refused")
    Do $$$AssertEquals(e.problem.httpStatus, 403)
    Do $$$AssertEquals(e.problem.platformStatus.summary, "ERROR #822: Access Denied")
    Do $$$AssertEquals(e.%GetTypeOf("headline"), "null")
    Set ok = 0, it = s.areas.%GetIterator()
    While it.%GetNext(.k, .x) { Set:(x.outcome = "ok") ok = ok + 1 }
    Do $$$AssertEquals(ok, 10)
}

Method TestSilentAreaIsUnreachable()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Do ##class(sentai.unittest.overview.OverviewFixtures).Silence("/api/admin/v2/devices")
    Set s = ##class(sentai.overview.OverviewService).Summary("fake-token")
    Set e = ..Entry(s, "devices")
    Do $$$AssertEquals(e.outcome, "unreachable")
    Do $$$AssertEquals(e.problem.httpStatus, 0)
    Do $$$AssertTrue(e.problem.detail [ "PLATFORM_UNREACHABLE")
    Do $$$AssertEquals(..Entry(s, "locks").outcome, "ok")
}

Method TestSharedDashboardRefusalHitsBothAreas()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Do ##class(sentai.unittest.overview.OverviewFixtures).Refuse("/api/admin/v2/monitor/dashboard/main")
    Set s = ##class(sentai.overview.OverviewService).Summary("fake-token")
    Do $$$AssertEquals(..Entry(s, "activity").outcome, "refused")
    Do $$$AssertEquals(..Entry(s, "alerts").outcome, "refused")
    Do $$$AssertEquals(..Entry(s, "processes").outcome, "ok")
}

Method TestEmptyAndOddAnswers()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Do ##class(sentai.unittest.overview.OverviewFixtures).Script("/api/admin/v2/web-sessions", [])
    Do ##class(sentai.unittest.overview.OverviewFixtures).Script("/api/admin/v2/monitor/system-usage/shared-memory", [{"Description": "Lock Table", "SMHAllocated": 10, "SMHUsed": 5}])
    Set s = ##class(sentai.overview.OverviewService).Summary("fake-token")
    Set ws = ..Entry(s, "web-sessions")
    Do $$$AssertEquals(ws.outcome, "ok")
    Do $$$AssertEquals(ws.headline.count, 0)
    Set m = ..Entry(s, "memory")
    Do $$$AssertEquals(m.outcome, "ok")
    Do $$$AssertEquals(m.headline.%GetTypeOf("usedPercent"), "null")
    Do $$$AssertEquals(m.headline.mostUsed.usedPercent, 50)
}

Method TestLargeReadingCountsEveryRow()
{
    Do ##class(sentai.unittest.overview.OverviewFixtures).ScriptAll()
    Set many = []
    For i = 1:1:2000 { Do many.%Push({"Pid": (i), "Reference": ("^X("_i_")")}) }
    Do ##class(sentai.unittest.overview.OverviewFixtures).Script("/api/admin/v2/locks", many)
    Set s = ##class(sentai.overview.OverviewService).Summary("fake-token")
    Do $$$AssertEquals(..Entry(s, "locks").headline.count, 2000)
}

}
