/// Serves the canvas's static bundle (the SvelteKit build baked into /opt/sentai-web) from
/// the /csp/sentai application, which is password-authenticated — never Unauthenticated
/// (HANDOFF constraint). A %CSP.REST class instead of the application's "Serve Files"
/// option because an unauthenticated request here gets 401 + WWW-Authenticate: Basic, so
/// the browser asks for the IRIS credentials; with "Serve Files" + CSP security it only
/// ever gets a 404. No business logic and no data: files only, and nothing outside ROOT.
Class sentai.web.StaticFiles Extends %CSP.REST
{

/// Where the Dockerfile copies the frontend build (outside the bind-mounted dev folder).
Parameter ROOT = "/opt/sentai-web/";

Parameter UseSession = 0;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
    <Route Url="/(.*)" Method="GET" Call="Serve"/>
</Routes>
}

ClassMethod Serve(path As %String) As %Status
{
    Set file = ..Resolve(path)
    If (file = "") {
        Set %response.Status = ..#HTTP404NOTFOUND
        Quit $$$OK
    }
    Set stream = ##class(%Stream.FileBinary).%New()
    Set sc = stream.LinkToFile(file)
    If $$$ISERR(sc) Quit sc
    Set type = ..ContentType(file)
    Set %response.ContentType = type
    // Bytes go out exactly as built: text files are already UTF-8 on disk.
    Set %response.NoCharSetConvert = 1
    Set %response.CharSet = $S($E(type, 1, 5) = "text/":"utf-8", type = "application/json":"utf-8", 1:"")
    Do %response.SetHeader("Cache-Control", ..CacheControl(path))
    Do %response.SetHeader("X-Content-Type-Options", "nosniff")
    Do %response.SetHeader("X-Frame-Options", "DENY")
    Quit stream.OutputToDevice()
}

/// The absolute file for a request path, or "" when it is missing, a directory, or
/// anywhere outside root. "" and "/" mean the index.
ClassMethod Resolve(path As %String, root As %String = {..#ROOT}) As %String
{
    If (path = "") || (path = "/") Set path = "index.html"
    If ($E(path) = "/") || (path [ "\") || (path [ ":") Quit ""
    If ("/"_path_"/") [ "/../" Quit ""
    // NormalizeDirectory returns "" for a missing directory; never fall back to the
    // namespace's default directory.
    Set root = ##class(%File).NormalizeDirectory(root)
    If (root = "") Quit ""
    Set file = ##class(%File).NormalizeFilename(path, root)
    If $E(file, 1, $L(root)) '= root Quit ""
    If '##class(%File).Exists(file) || ##class(%File).DirectoryExists(file) Quit ""
    Quit file
}

ClassMethod ContentType(file As %String) As %String
{
    Set ext = $ZCVT($Piece(file, ".", *), "L")
    Quit $Case(ext,
        "html":"text/html", "js":"text/javascript", "css":"text/css", "json":"application/json",
        "svg":"image/svg+xml", "png":"image/png", "ico":"image/x-icon", "txt":"text/plain",
        "woff2":"font/woff2", "woff":"font/woff", "webmanifest":"application/manifest+json",
        :"application/octet-stream")
}

/// SvelteKit's hashed assets never change under a name; everything else is revalidated.
ClassMethod CacheControl(path As %String) As %String
{
    Quit $S($E(path, 1, 15) = "_app/immutable/":"public, max-age=31536000, immutable", 1:"no-cache")
}

}
