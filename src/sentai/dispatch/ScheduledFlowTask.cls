/// The native Task Manager task of a scheduled flow (spec 015 plan D-4): one per flow, named
/// "SentaiTask: <flowId> <flow name>", created by sentai.schedule.ScheduleService through the
/// platform's management API with `RunAsUser` = the schedule's run-as account and
/// `Settings {FlowId}`. On firing it starts the flow (sentai.schedule.ScheduledStart).
/// Tasks of the legacy one-task-per-step form (spec 001, `StepId` set) never start anything; they
/// are deleted on the flow's next schedule or unschedule.
Class sentai.dispatch.ScheduledFlowTask Extends %SYS.Task.Definition
{

Property FlowId As %String(MAXLEN = 32);

/// Legacy form only.
Property StepId As %String(MAXLEN = 8);

/// Legacy form only.
Property IsRoot As %Boolean;

Method OnTask() As %Status
{
    Quit:(..StepId '= "") $$$OK
    Quit:(..FlowId = "") $$$ERROR($$$GeneralError, "SentaiTask: this task has no FlowId setting")
    Quit ##class(sentai.schedule.ScheduledStart).Fire(..FlowId)
}

}
