/// Spec 008 T004 (US1, FR-001…FR-004, FR-023): the registry of target servers — names, base
/// addresses and the HTTPS rule, the operator-set online flag — and no credential anywhere.
Class sentai.unittest.targets.TargetServiceTest Extends sentai.unittest.SentaiTestCase
{

Property SavedAllowance As %String;

Method OnBeforeOneTest() As %Status
{
    Set ..SavedAllowance = $G(^sentai("config", "allowInsecureTargets"))
    Kill ^sentai("config", "allowInsecureTargets")
    Quit ##super()
}

Method OnAfterOneTest() As %Status
{
    If (..SavedAllowance = "") { Kill ^sentai("config", "allowInsecureTargets") } Else { Set ^sentai("config", "allowInsecureTargets") = ..SavedAllowance }
    Quit ##super()
}

/// A name unique to this test run.
ClassMethod Unique(prefix As %String = "t") As %String
{
    Quit prefix_"-"_$TR($H, ",", "-")_"-"_$I(^sentaiTestSeq)
}

Method TestCreateReadListUpdateDelete()
{
    Set name = ..Unique("crud")
    Set out = ##class(sentai.targets.TargetService).Create({"name": (name), "baseUrl": "https://mirror-b.example:52773", "description": "async member"}, "tester")
    Do $$$AssertEquals(out.httpStatus, 201, out.%ToJSON())
    Do $$$AssertEquals(out.body.name, name)
    Do $$$AssertEquals(out.body.baseUrl, "https://mirror-b.example:52773")
    Do $$$AssertEquals(out.body.description, "async member")
    Do $$$AssertEquals(out.body.online, 1)
    Do $$$AssertEquals(out.body.%GetTypeOf("online"), "boolean")

    Set read = ##class(sentai.targets.TargetService).Get(name)
    Do $$$AssertEquals(read.httpStatus, 200)
    Do $$$AssertEquals(read.body.baseUrl, "https://mirror-b.example:52773")

    Set found = 0, iter = ##class(sentai.targets.TargetService).List().body.%GetIterator()
    While iter.%GetNext(.k, .t) { Set:(t.name = name) found = 1 }
    Do $$$AssertTrue(found, "listed")

    Set upd = ##class(sentai.targets.TargetService).Update(name, {"baseUrl": "https://mirror-c.example:1972", "description": ""}, "tester")
    Do $$$AssertEquals(upd.httpStatus, 200, upd.%ToJSON())
    Do $$$AssertEquals(##class(sentai.targets.TargetService).Get(name).body.baseUrl, "https://mirror-c.example:1972")

    Do $$$AssertEquals(##class(sentai.targets.TargetService).Delete(name).httpStatus, 204)
    Set gone = ##class(sentai.targets.TargetService).Get(name)
    Do $$$AssertEquals(gone.httpStatus, 404)
    Do $$$AssertTrue(gone.problem.detail [ "TARGET_NOT_FOUND")
    Do $$$AssertEquals(##class(sentai.targets.TargetService).Delete(name).httpStatus, 404)
}

Method TestDuplicateNameIsRefusedAndFirstUnchanged()
{
    Set name = ..Unique("dup")
    Do ##class(sentai.targets.TargetService).Create({"name": (name), "baseUrl": "https://a.example:52773"}, "tester")
    Set out = ##class(sentai.targets.TargetService).Create({"name": (name), "baseUrl": "https://b.example:52773"}, "tester")
    Do $$$AssertEquals(out.httpStatus, 409)
    Do $$$AssertTrue(out.problem.detail [ "TARGET_EXISTS")
    Do $$$AssertEquals(##class(sentai.targets.TargetService).Get(name).body.baseUrl, "https://a.example:52773")
}

Method TestNameAndAddressRules()
{
    For name = "", "-lead", "has space", "a/b", $TR($J("", 65), " ", "x") {
        Set out = ##class(sentai.targets.TargetService).Create({"name": (name), "baseUrl": "https://ok.example:52773"}, "tester")
        Do $$$AssertEquals(out.httpStatus, 400, "name '"_name_"'")
        Do $$$AssertTrue(out.problem.detail [ "INVALID_TARGET")
    }
    For url = "", "ftp://h.example:21", "https://h.example", "https://h.example:52773/api", "https://h.example:52773?x=1", "https://user:pw@h.example:52773", "https://h.example:99999", "iris-target:52773" {
        Set out = ##class(sentai.targets.TargetService).Create({"name": (..Unique("url")), "baseUrl": (url)}, "tester")
        Do $$$AssertEquals(out.httpStatus, 400, "url '"_url_"'")
        Do $$$AssertTrue(out.problem.detail [ "INVALID_TARGET", out.problem.detail)
    }
}

/// FR-003: http only for loopback, unless the development allowance is set.
Method TestHttpNeedsLoopbackOrTheAllowance()
{
    Set out = ##class(sentai.targets.TargetService).Create({"name": (..Unique("insecure")), "baseUrl": "http://iris-target:52773"}, "tester")
    Do $$$AssertEquals(out.httpStatus, 400)
    Do $$$AssertTrue(out.problem.detail [ "INSECURE_TARGET", out.problem.detail)

    For url = "http://127.0.0.1:52773", "http://localhost:52773" {
        Do $$$AssertEquals(##class(sentai.targets.TargetService).Create({"name": (..Unique("loop")), "baseUrl": (url)}, "tester").httpStatus, 201, url)
    }

    Set ^sentai("config", "allowInsecureTargets") = 1
    Do $$$AssertEquals(##class(sentai.targets.TargetService).Create({"name": (..Unique("allowed")), "baseUrl": "http://iris-target:52773"}, "tester").httpStatus, 201)
}

/// FR-004: the flag is the operator's, set only through SetOnline; PUT cannot change it.
Method TestOnlineFlagIsSetOnlyThroughItsCall()
{
    Set name = ..Unique("flag")
    Do ##class(sentai.targets.TargetService).Create({"name": (name), "baseUrl": "https://f.example:52773"}, "tester")
    Do ##class(sentai.targets.TargetService).Update(name, {"baseUrl": "https://f.example:52773", "online": false}, "tester")
    Do $$$AssertEquals(##class(sentai.targets.TargetService).Get(name).body.online, 1, "PUT ignores online")

    Set off = ##class(sentai.targets.TargetService).SetOnline(name, {"online": false}, "tester")
    Do $$$AssertEquals(off.httpStatus, 200)
    Do $$$AssertEquals(off.body.online, 0)
    Do $$$AssertEquals(##class(sentai.targets.TargetService).SetOnline(name, {"online": "yes"}, "tester").httpStatus, 400)
    Do $$$AssertEquals(##class(sentai.targets.TargetService).SetOnline(name, {"online": true}, "tester").body.online, 1)
    Do $$$AssertEquals(##class(sentai.targets.TargetService).SetOnline("no-such-target", {"online": true}, "tester").httpStatus, 404)
}

/// FR-002: the stored record has no place for a credential.
Method TestTheRecordHoldsNoCredential()
{
    Set cls = ##class(%Dictionary.CompiledClass).%OpenId("sentai.model.Target")
    Do $$$AssertTrue($IsObject(cls))
    For i = 1:1:cls.Properties.Count() {
        Set prop = $ZCVT(cls.Properties.GetAt(i).Name, "L")
        Do $$$AssertNotTrue((prop [ "pass") || (prop [ "token") || (prop [ "secret") || (prop [ "credential"), "no credential property: "_prop)
    }
}

}
