/// Spec 015 (T008): the platform objects scheduled runs need, created once by the installer
/// (module.xml's activate step) and idempotent: the resource `SentaiSchedule` and the wallet
/// collection `SentaiTask` that it protects. The collection names the permission it checks: a bare
/// resource name means READ to use and WRITE to edit (acceptance finding, 2026-09-29), so they are
/// set explicitly: `SentaiSchedule:USE` to use a secret, `SentaiSchedule:WRITE` to write one. No role
/// receives the resource: the administrator grants `SentaiSchedule:U` to run-as accounts and
/// `SentaiSchedule:W` to operators who schedule (README). Must run with security administration
/// (the installer runs as the instance owner).
Class sentai.schedule.Install Extends %RegisteredObject
{

ClassMethod Run() As %Status
{
    // Read in this namespace: the class does not exist in %SYS.
    Set resource = ##class(sentai.schedule.Wallet).#RESOURCE, collection = ##class(sentai.schedule.Wallet).#COLLECTION
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If '##class(Security.Resources).Exists(resource) {
        Set sc = ##class(Security.Resources).Create(resource, "SentaiTask scheduled-run credentials (spec 015)", "")
        Quit:$$$ISERR(sc) sc
    }
    Kill props
    Set props("UseResource") = resource_":USE", props("EditResource") = resource_":WRITE"
    If ##class(%Wallet.Collection).Exists(collection) {
        Set existing = ##class(%Wallet.Collection).%OpenId(collection, 0)
        Quit:($IsObject(existing) && (existing.UseResource = props("UseResource")) && (existing.EditResource = props("EditResource"))) $$$OK
        Quit ##class(%Wallet.Collection).Modify(collection, .props)
    }
    Quit ##class(%Wallet.Collection).Create(collection, .props)
}

}
