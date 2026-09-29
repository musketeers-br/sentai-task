/// Spec 015 (data-model §1): the schedule of one flow. Holds no password, token or secret value —
/// the credentials live in the IRIS Wallet, named from `generation` (sentai.schedule.Wallet).
Class sentai.model.Schedule Extends %Persistent
{

Property flow As sentai.model.Flow [ Required ];

/// daily | weekly | monthly | hourly
Property kind As %String(MAXLEN = 16) [ Required ];

/// Weekly: days as "1,5" (Mon = 1 … Sun = 7).
Property days As %String(MAXLEN = 32);

Property dayOfMonth As %Integer;

Property everyHours As %Integer;

/// "HH:MM", the instance's local time.
Property startTime As %String(MAXLEN = 5) [ Required ];

Property runAs As %String(MAXLEN = 128) [ Required ];

/// The flow's remote targets at scheduling time, comma-separated (their secrets exist).
Property targets As %String(MAXLEN = 2000);

Property taskId As %Integer;

/// Increases with every schedule or credential renewal; names the wallet secrets.
Property generation As %Integer [ InitialExpression = 0 ];

/// The last next-run time the platform reported (plan D-8).
Property nextRun As %TimeStamp;

Property createdBy As %String(MAXLEN = 128);

Property createdAt As %TimeStamp;

Property updatedAt As %TimeStamp;

Index FlowIndex On flow [ Unique ];

/// The schedule as the API's `schedule` object.
Method ToSchedule() As %DynamicObject
{
    Set out = {"kind": (..kind), "startTime": (..startTime)}
    If (..kind = "weekly") {
        Set days = []
        For i = 1:1:$L(..days, ",") { Do:($P(..days, ",", i) '= "") days.%Push(+$P(..days, ",", i)) }
        Do out.%Set("days", days)
    }
    Do:(..kind = "monthly") out.%Set("dayOfMonth", ..dayOfMonth)
    Do:(..kind = "hourly") out.%Set("everyHours", ..everyHours)
    Quit out
}

ClassMethod ForFlow(flowId As %String) As sentai.model.Schedule
{
    Quit ..FlowIndexOpen(flowId, 4)
}

Storage Default
{
<Data name="ScheduleDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>flow</Value>
</Value>
<Value name="3">
<Value>kind</Value>
</Value>
<Value name="4">
<Value>days</Value>
</Value>
<Value name="5">
<Value>dayOfMonth</Value>
</Value>
<Value name="6">
<Value>everyHours</Value>
</Value>
<Value name="7">
<Value>startTime</Value>
</Value>
<Value name="8">
<Value>runAs</Value>
</Value>
<Value name="9">
<Value>targets</Value>
</Value>
<Value name="10">
<Value>taskId</Value>
</Value>
<Value name="11">
<Value>generation</Value>
</Value>
<Value name="12">
<Value>nextRun</Value>
</Value>
<Value name="13">
<Value>createdBy</Value>
</Value>
<Value name="14">
<Value>createdAt</Value>
</Value>
<Value name="15">
<Value>updatedAt</Value>
</Value>
</Data>
<DataLocation>^sentai.model.ScheduleD</DataLocation>
<DefaultData>ScheduleDefaultData</DefaultData>
<IdLocation>^sentai.model.ScheduleD</IdLocation>
<IndexLocation>^sentai.model.ScheduleI</IndexLocation>
<StreamLocation>^sentai.model.ScheduleS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
