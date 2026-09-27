/// Spec 008 T004: the /targets routes answer with the contract's status codes
/// (contracts/api-delta.md §Targets). Any signed-in operator may manage targets (FR-023).
Class sentai.unittest.targets.TargetRestTest Extends sentai.unittest.SentaiTestCase
{

ClassMethod Request(body As %DynamicObject = "")
{
    Set %request = ##class(%CSP.Request).%New()
    Set %request.Content = ##class(%Stream.TmpCharacter).%New()
    Do:$IsObject(body) %request.Content.Write(body.%ToJSON())
    Set %response = ##class(%CSP.Response).%New()
}

Method TestTargetRoutes()
{
    Set name = ##class(sentai.unittest.targets.TargetServiceTest).Unique("rest")

    Do ..Request({"name": (name), "baseUrl": "https://r.example:52773", "description": "d"})
    Do ##class(sentai.rest.Dispatcher).CreateTarget()
    Do $$$AssertEquals(%response.Status, 201)

    Do ..Request({"name": (name), "baseUrl": "https://r.example:52773"})
    Do ##class(sentai.rest.Dispatcher).CreateTarget()
    Do $$$AssertEquals(%response.Status, 409)

    Do ..Request()
    Do ##class(sentai.rest.Dispatcher).ListTargets()
    Do $$$AssertEquals(%response.Status, 200)

    Do ..Request()
    Do ##class(sentai.rest.Dispatcher).ReadTarget(name)
    Do $$$AssertEquals(%response.Status, 200)

    Do ..Request({"baseUrl": "https://r2.example:52773", "description": ""})
    Do ##class(sentai.rest.Dispatcher).UpdateTarget(name)
    Do $$$AssertEquals(%response.Status, 200)

    Do ..Request({"online": false})
    Do ##class(sentai.rest.Dispatcher).SetTargetOnline(name)
    Do $$$AssertEquals(%response.Status, 200)

    Do ..Request({"online": "no"})
    Do ##class(sentai.rest.Dispatcher).SetTargetOnline(name)
    Do $$$AssertEquals(%response.Status, 400)

    Do ..Request()
    Do ##class(sentai.rest.Dispatcher).DeleteTarget(name)
    Do $$$AssertEquals(%response.Status, 204)

    Do ..Request()
    Do ##class(sentai.rest.Dispatcher).ReadTarget(name)
    Do $$$AssertEquals(%response.Status, 404)
}

}
