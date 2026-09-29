/// Spec 015 (data-model §3): the scheduled-run credentials in the IRIS Wallet collection
/// `SentaiTask`, protected by the resource `SentaiSchedule` (sentai.schedule.Install). Writes run in
/// the operator's process, so the platform checks the collection's edit resource; reads happen only
/// inside the platform's own `ApplyHTTP` (AdminApiClient.LoginWithSecret). Nothing here returns a
/// secret value. Under the unit-test double, the calls are recorded instead of touching the wallet.
Class sentai.schedule.Wallet Extends %RegisteredObject
{

Parameter COLLECTION = "SentaiTask";

Parameter RESOURCE = "SentaiSchedule";

/// "SentaiTask.flow<id>-g<generation>-<instance>", instance = "primary" or a target name.
ClassMethod SecretName(flowId As %String, generation As %Integer, instance As %String) As %String
{
    Quit ..#COLLECTION_".flow"_flowId_"-g"_generation_"-"_instance
}

/// Stores `user`/`password` as a key-value secret of usage HTTP. The password is only passed on.
ClassMethod Put(name As %String, user As %String, password As %String) As %Status
{
    If $G(^sentaiTestDouble("enabled")) {
        Quit:$D(^sentaiTestDouble("walletRefused")) $$$ERROR($$$GeneralError, ^sentaiTestDouble("walletRefused"))
        Set ^sentaiTestDouble("wallet", name) = user
        Quit $$$OK
    }
    Try {
        Kill props
        Set props("Secret") = {"user": (user), "password": (password)}.%ToJSON(), props("Usage") = "HTTP"
        Set sc = $S(##class(%Wallet.KeyValue).Exists(name):##class(%Wallet.KeyValue).Modify(name, .props), 1:##class(%Wallet.KeyValue).Create(name, .props))
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Kill props
    Quit sc
}

/// Removes a secret; $$$OK when it did not exist.
ClassMethod Delete(name As %String) As %Status
{
    If $G(^sentaiTestDouble("enabled")) {
        Kill ^sentaiTestDouble("wallet", name)
        Quit $$$OK
    }
    Try {
        Set sc = $S(##class(%Wallet.KeyValue).Exists(name):##class(%Wallet.KeyValue).Delete(name), 1:$$$OK)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

}
