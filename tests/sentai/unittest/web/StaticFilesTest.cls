/// The canvas's static bundle is served by sentai.web.StaticFiles behind password
/// authentication (no unauthenticated web app — HANDOFF constraint). These tests pin the
/// file resolution, which is the part that can leak: nothing outside the build root is
/// ever served, whatever the request path.
Class sentai.unittest.web.StaticFilesTest Extends sentai.unittest.SentaiTestCase
{

Property Root As %String;

Method OnBeforeOneTest() As %Status
{
    // TempFilename creates a file by that name; the test needs a directory there.
    Set dir = ##class(%File).TempFilename("web")
    Do ##class(%File).Delete(dir)
    Set dir = dir_"/"
    Do ##class(%File).CreateDirectoryChain(dir_"_app/immutable")
    Set ..Root = ##class(%File).NormalizeDirectory(dir)
    For file = "index.html", "_app/version.json", "_app/immutable/start.js" {
        Set stream = ##class(%Stream.FileCharacter).%New()
        Do stream.LinkToFile(..Root_file)
        Do stream.Write("x")
        Do stream.%Save()
    }
    Quit ##super()
}

Method OnAfterOneTest() As %Status
{
    Do ##class(%File).RemoveDirectoryTree(..Root)
    Quit ##super()
}

Method TestRootServesTheIndex()
{
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).Resolve("", ..Root), ..Root_"index.html")
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).Resolve("index.html", ..Root), ..Root_"index.html")
}

Method TestNestedFileResolves()
{
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).Resolve("_app/immutable/start.js", ..Root), ..Root_"_app/immutable/start.js")
}

Method TestMissingFileAndDirectoryAreNotServed()
{
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).Resolve("nope.js", ..Root), "")
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).Resolve("_app", ..Root), "")
}

Method TestPathTraversalIsRefused()
{
    For path = "../etc/passwd", "_app/../../etc/passwd", "..", "_app/..%2F..%2Fetc/passwd", "/etc/passwd", "_app\..\..\x" {
        Do $$$AssertEquals(##class(sentai.web.StaticFiles).Resolve(path, ..Root), "", "refused: "_path)
    }
}

Method TestMissingRootServesNothing()
{
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).Resolve("index.html", ..Root_"does-not-exist/"), "")
}

Method TestContentTypes()
{
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).ContentType("a/index.html"), "text/html")
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).ContentType("a/start.js"), "text/javascript")
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).ContentType("a/b.css"), "text/css")
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).ContentType("a/v.json"), "application/json")
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).ContentType("a/f.woff2"), "font/woff2")
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).ContentType("a/unknown.bin"), "application/octet-stream")
}

Method TestHashedAssetsAreCachedAndTheIndexIsNot()
{
    Do $$$AssertTrue(##class(sentai.web.StaticFiles).CacheControl("_app/immutable/start.js")["immutable")
    Do $$$AssertEquals(##class(sentai.web.StaticFiles).CacheControl("index.html"), "no-cache")
}

}
