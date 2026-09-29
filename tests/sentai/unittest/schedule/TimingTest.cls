/// Spec 015 T004: the four schedule kinds as Task Manager fields (evidence t001 R-2), their words,
/// and the field errors.
Class sentai.unittest.schedule.TimingTest Extends %UnitTest.TestCase
{

ClassMethod Fields(schedule As %DynamicObject) As %DynamicObject
{
    Quit ##class(sentai.schedule.Timing).ToTaskFields(schedule)
}

ClassMethod ErrorFields(schedule As %DynamicObject) As %String
{
    Set out = ""
    Set it = ##class(sentai.schedule.Timing).Validate(schedule).%GetIterator()
    While it.%GetNext(.k, .e) { Set out = out_$S(out = "":"", 1:",")_e.field }
    Quit out
}

Method TestDaily()
{
    Set f = ..Fields({"kind": "daily", "startTime": "03:00"})
    Do $$$AssertEquals(f.TimePeriod, "Daily")
    Do $$$AssertEquals(f.DailyFrequency, "Once")
    Do $$$AssertEquals(f.DailyStartTime, "03:00:00")
    Do $$$AssertEquals(f.TimePeriodEvery, 1)
    Do $$$AssertEquals(##class(sentai.schedule.Timing).Describe({"kind": "daily", "startTime": "03:00"}), "Daily at 03:00")
}

/// The platform counts 1 = Sunday; the product 1 = Monday (R-2: Monday + Friday = "26").
Method TestWeeklyConvertsWeekdays()
{
    Set s = {"kind": "weekly", "days": [5, 1], "startTime": "22:30"}
    Set f = ..Fields(s)
    Do $$$AssertEquals(f.TimePeriod, "Weekly")
    Do $$$AssertEquals(f.TimePeriodDay, "26")
    Do $$$AssertEquals(..Fields({"kind": "weekly", "days": [7, 6], "startTime": "01:00"}).TimePeriodDay, "17")
    Do $$$AssertEquals(##class(sentai.schedule.Timing).Describe(s), "Weekly on Mon, Fri at 22:30")
}

Method TestMonthly()
{
    Set s = {"kind": "monthly", "dayOfMonth": 1, "startTime": "04:00"}
    Set f = ..Fields(s)
    Do $$$AssertEquals(f.TimePeriod, "Monthly")
    Do $$$AssertEquals(f.TimePeriodDay, "1")
    Do $$$AssertEquals(##class(sentai.schedule.Timing).Describe(s), "Monthly on day 1 at 04:00")
}

Method TestHourly()
{
    Set s = {"kind": "hourly", "everyHours": 4, "startTime": "00:00"}
    Set f = ..Fields(s)
    Do $$$AssertEquals(f.TimePeriod, "Daily")
    Do $$$AssertEquals(f.DailyFrequency, "Several")
    Do $$$AssertEquals(f.DailyFrequencyTime, "1")
    Do $$$AssertEquals(f.DailyIncrement, 4)
    Do $$$AssertEquals(f.DailyEndTime, "23:59:59")
    Do $$$AssertEquals(##class(sentai.schedule.Timing).Describe(s), "Every 4 hours from 00:00")
    Do $$$AssertEquals(##class(sentai.schedule.Timing).Describe({"kind": "hourly", "everyHours": 1, "startTime": "06:00"}), "Every 1 hour from 06:00")
}

Method TestValidation()
{
    Do $$$AssertEquals(..ErrorFields({"kind": "daily", "startTime": "03:00"}), "")
    Do $$$AssertEquals(..ErrorFields({"kind": "weekly", "startTime": "03:00"}), "days")
    Do $$$AssertEquals(..ErrorFields({"kind": "weekly", "days": [], "startTime": "03:00"}), "days")
    Do $$$AssertEquals(..ErrorFields({"kind": "weekly", "days": [8], "startTime": "03:00"}), "days")
    Do $$$AssertEquals(..ErrorFields({"kind": "monthly", "dayOfMonth": 32, "startTime": "03:00"}), "dayOfMonth")
    Do $$$AssertEquals(..ErrorFields({"kind": "hourly", "everyHours": 0, "startTime": "03:00"}), "everyHours")
    Do $$$AssertEquals(..ErrorFields({"kind": "hourly", "everyHours": 13, "startTime": "03:00"}), "everyHours")
    Do $$$AssertEquals(..ErrorFields({"kind": "daily", "startTime": "24:00"}), "startTime")
    Do $$$AssertEquals(..ErrorFields({"kind": "daily", "startTime": "3:00"}), "startTime")
    Do $$$AssertEquals(..ErrorFields({"kind": "yearly", "startTime": "03:00"}), "kind")
    Do $$$AssertEquals(..ErrorFields(""), "schedule")
}

}
