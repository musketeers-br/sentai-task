/// Spec 015 (data-model §2): a structured schedule, validated, turned into the Task Manager's timing
/// fields (evidence t001-wallet-tasks.md R-2) and described in words. Pure: no platform call.
///
/// Schedule: {"kind": "daily"|"weekly"|"monthly"|"hourly", "days": [1..7] (Mon=1, weekly),
///            "dayOfMonth": 1..31 (monthly), "everyHours": 1..12 (hourly), "startTime": "HH:MM"}
Class sentai.schedule.Timing Extends %RegisteredObject
{

/// Field errors as [{"field", "detail"}]; [] when the schedule is valid.
ClassMethod Validate(schedule As %DynamicObject) As %DynamicArray
{
    Set errors = []
    If '$IsObject(schedule) {
        Do errors.%Push({"field": "schedule", "detail": "a schedule object is required"})
        Quit errors
    }
    Set kind = schedule.kind
    If '$LISTFIND($LB("daily", "weekly", "monthly", "hourly"), kind) {
        Do errors.%Push({"field": "kind", "detail": "kind must be daily, weekly, monthly or hourly"})
    }
    Set time = schedule.startTime
    If (time '? 2N1":"2N) || (+$P(time, ":", 1) > 23) || (+$P(time, ":", 2) > 59) {
        Do errors.%Push({"field": "startTime", "detail": "startTime must be HH:MM between 00:00 and 23:59"})
    }
    If (kind = "weekly") {
        Set ok = $IsObject(schedule.days) && (schedule.days.%Size() > 0)
        If ok {
            Set it = schedule.days.%GetIterator()
            While it.%GetNext(.k, .d) { Set:((d '? 1N) || (d < 1) || (d > 7)) ok = 0 }
        }
        Do:'ok errors.%Push({"field": "days", "detail": "choose at least one day (1 = Monday … 7 = Sunday)"})
    }
    If (kind = "monthly") && ((schedule.dayOfMonth '? 1.2N) || (schedule.dayOfMonth < 1) || (schedule.dayOfMonth > 31)) {
        Do errors.%Push({"field": "dayOfMonth", "detail": "dayOfMonth must be 1 to 31"})
    }
    If (kind = "hourly") && ((schedule.everyHours '? 1.2N) || (schedule.everyHours < 1) || (schedule.everyHours > 12)) {
        Do errors.%Push({"field": "everyHours", "detail": "everyHours must be 1 to 12"})
    }
    Quit errors
}

/// The Task Manager fields for a valid schedule (merged into the create body).
ClassMethod ToTaskFields(schedule As %DynamicObject) As %DynamicObject
{
    Set out = {"TimePeriod": "Daily", "TimePeriodDay": "", "DailyFrequency": "Once", "DailyFrequencyTime": "",
               "DailyIncrement": "", "DailyStartTime": (schedule.startTime_":00"), "DailyEndTime": "00:00:00"}
    Do out.%Set("TimePeriodEvery", 1, "number")
    If (schedule.kind = "weekly") {
        Set out.TimePeriod = "Weekly", out.TimePeriodDay = ..PlatformDays(schedule.days)
    } ElseIf (schedule.kind = "monthly") {
        Set out.TimePeriod = "Monthly", out.TimePeriodDay = ""_(+schedule.dayOfMonth)
    } ElseIf (schedule.kind = "hourly") {
        // "1" = hours (the platform's VALUELIST is ,0,1; evidence R-2).
        Set out.DailyFrequency = "Several", out.DailyFrequencyTime = "1", out.DailyEndTime = "23:59:59"
        Do out.%Set("DailyIncrement", +schedule.everyHours, "number")
    }
    Quit out
}

/// The platform numbers weekdays 1 = Sunday … 7 = Saturday; the product 1 = Monday … 7 = Sunday.
ClassMethod PlatformDays(days As %DynamicArray) As %String
{
    Kill set
    Set it = days.%GetIterator()
    While it.%GetNext(.k, .d) { Set set((d # 7) + 1) = "" }
    Set out = "", k = ""
    For {
        Set k = $O(set(k))
        Quit:(k = "")
        Set out = out_k
    }
    Quit out
}

/// "Daily at 03:00", "Weekly on Mon, Fri at 22:30", "Monthly on day 1 at 04:00", "Every 4 hours from 00:00".
ClassMethod Describe(schedule As %DynamicObject) As %String
{
    Set t = schedule.startTime
    Quit:(schedule.kind = "daily") "Daily at "_t
    Quit:(schedule.kind = "monthly") "Monthly on day "_(+schedule.dayOfMonth)_" at "_t
    Quit:(schedule.kind = "hourly") "Every "_(+schedule.everyHours)_" hour"_$S(+schedule.everyHours = 1:"", 1:"s")_" from "_t
    Set names = $LB("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"), list = ""
    Kill seen
    Set it = schedule.days.%GetIterator()
    While it.%GetNext(.k, .d) { Set seen(+d) = "" }
    Set d = ""
    For {
        Set d = $O(seen(d))
        Quit:(d = "")
        Set list = list_$S(list = "":"", 1:", ")_$LG(names, d)
    }
    Quit "Weekly on "_list_" at "_t
}

}
