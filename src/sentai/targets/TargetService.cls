/// Spec 008: the registry of target servers (US1, FR-001…FR-004, FR-023). Results are outcome
/// values `{httpStatus, body}` or `{httpStatus, problem}`, written as they are by the REST
/// dispatcher (the same convention as sentai.catalog.TaskService). Any signed-in operator may
/// manage targets (Clarifications Q2): a target grants nothing; every call to it carries the
/// operator's own credential for it.
Class sentai.targets.TargetService Extends %RegisteredObject
{

ClassMethod List() As %DynamicObject
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID AS id FROM sentai_model.Target ORDER BY name")
    While rs.%Next() {
        Do out.%Push(##class(sentai.model.Target).%OpenId(rs.%Get("id"), 0).ToJSON())
    }
    Quit {"httpStatus": 200, "body": (out)}
}

ClassMethod Get(name As %String) As %DynamicObject
{
    Set target = ..Open(name)
    Quit:'$IsObject(target) ..NotFound(name)
    Quit {"httpStatus": 200, "body": (target.ToJSON())}
}

ClassMethod Create(payload As %DynamicObject, user As %String) As %DynamicObject
{
    Set name = $S($IsObject(payload):payload.name, 1:"")
    If '..IsValidName(name) Quit ..Problem(400, "Bad Request", "INVALID_TARGET: name must match [A-Za-z0-9][A-Za-z0-9._-]* and have at most 64 characters")
    Quit:'..IsAcceptableUrl(payload.baseUrl, .problem) problem
    If ##class(sentai.model.Target).NameIndexExists(name) Quit ..Problem(409, "Conflict", "TARGET_EXISTS: a target named '"_name_"' is already registered")

    Set target = ##class(sentai.model.Target).%New()
    Set target.name = name, target.baseUrl = payload.baseUrl, target.description = payload.description, target.online = 1
    Set target.createdAt = $ZDATETIME($HOROLOG, 3), target.createdBy = user
    Set target.updatedAt = target.createdAt, target.updatedBy = user
    Set sc = target.%Save()
    If $$$ISERR(sc) Quit ..Problem(409, "Conflict", "TARGET_EXISTS: "_$SYSTEM.Status.GetErrorText(sc))
    Quit {"httpStatus": 201, "body": (target.ToJSON())}
}

/// The name is the key and does not change; `online` is not accepted here (FR-004).
ClassMethod Update(name As %String, payload As %DynamicObject, user As %String) As %DynamicObject
{
    Set target = ..Open(name, 4)
    Quit:'$IsObject(target) ..NotFound(name)
    Quit:'..IsAcceptableUrl(payload.baseUrl, .problem) problem
    Set target.baseUrl = payload.baseUrl, target.description = payload.description
    Set target.updatedAt = $ZDATETIME($HOROLOG, 3), target.updatedBy = user
    Set sc = target.%Save()
    If $$$ISERR(sc) Quit ..Problem(500, "Internal Error", $SYSTEM.Status.GetErrorText(sc))
    Quit {"httpStatus": 200, "body": (target.ToJSON())}
}

/// Allowed while flows name the target: they then fail validation with TARGET_NOT_FOUND, and a
/// run already started keeps the address it froze (FR-018).
ClassMethod Delete(name As %String) As %DynamicObject
{
    Set target = ..Open(name)
    Quit:'$IsObject(target) ..NotFound(name)
    Set sc = ##class(sentai.model.Target).%DeleteId(target.%Id())
    If $$$ISERR(sc) Quit ..Problem(500, "Internal Error", $SYSTEM.Status.GetErrorText(sc))
    Quit {"httpStatus": 204, "body": ""}
}

ClassMethod SetOnline(name As %String, payload As %DynamicObject, user As %String) As %DynamicObject
{
    Set target = ..Open(name, 4)
    Quit:'$IsObject(target) ..NotFound(name)
    If '$IsObject(payload) || (payload.%GetTypeOf("online") '= "boolean") Quit ..Problem(400, "Bad Request", "online must be a boolean")
    Set target.online = payload.online
    Set target.updatedAt = $ZDATETIME($HOROLOG, 3), target.updatedBy = user
    Set sc = target.%Save()
    If $$$ISERR(sc) Quit ..Problem(500, "Internal Error", $SYSTEM.Status.GetErrorText(sc))
    Quit {"httpStatus": 200, "body": (target.ToJSON())}
}

ClassMethod Open(name As %String, concurrency As %Integer = 0) As sentai.model.Target
{
    Quit:(name = "") ""
    Quit ##class(sentai.model.Target).NameIndexOpen(name, concurrency)
}

ClassMethod IsValidName(name As %String) As %Boolean
{
    Quit ($L(name) > 0) && ($L(name) <= 64) && $MATCH(name, "[A-Za-z0-9][A-Za-z0-9._-]*")
}

/// FR-003 and data-model.md: `scheme://host:port`, nothing else; http only for a loopback host
/// unless the development allowance ^sentai("config","allowInsecureTargets") is set.
ClassMethod IsAcceptableUrl(url As %String, Output problem As %DynamicObject) As %Boolean
{
    Set problem = ""
    If '$MATCH(url, "(?i)(https?)://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\]):([0-9]{1,5})") || (+$PIECE(url, ":", 3) > 65535) || (+$PIECE(url, ":", 3) < 1) {
        Set problem = ..Problem(400, "Bad Request", "INVALID_TARGET: baseUrl must be scheme://host:port (http or https), with no path, query or user info")
        Quit 0
    }
    Set scheme = $ZCVT($PIECE(url, "://", 1), "L"), host = $ZCVT($PIECE($PIECE(url, "://", 2), ":", 1, $L($PIECE(url, "://", 2), ":") - 1), "L")
    If (scheme = "http") && '..IsLoopback(host) && '$G(^sentai("config", "allowInsecureTargets")) {
        Set problem = ..Problem(400, "Bad Request", "INSECURE_TARGET: http is allowed only for loopback targets unless the development allowance is set")
        Quit 0
    }
    Quit 1
}

ClassMethod IsLoopback(host As %String) As %Boolean
{
    Quit $LISTFIND($LB("127.0.0.1", "localhost", "[::1]"), host) > 0
}

ClassMethod NotFound(name As %String) As %DynamicObject
{
    Quit ..Problem(404, "Not Found", "TARGET_NOT_FOUND: no target named '"_name_"'")
}

ClassMethod Problem(status As %Integer, title As %String, detail As %String) As %DynamicObject
{
    Quit {"httpStatus": (status), "problem": {"status": (status), "title": (title), "detail": (detail)}}
}

}
