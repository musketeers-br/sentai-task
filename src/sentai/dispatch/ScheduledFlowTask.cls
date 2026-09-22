/// Native %SYS.Task.Definition subclass created by POST /flows/{id}/schedule
/// (research.md R-007/OQ-1). Only the task compiled for a step with no incoming edges
/// actually starts a run on OnTask(); tasks for downstream steps exist solely to satisfy
/// "one task identifier per scheduled step" (FR-031) and no-op at fire time — the run they
/// belong to, if any, will already have carried them to a terminal state via
/// WaveDispatcher's own wave progression.
Class sentai.dispatch.ScheduledFlowTask Extends %SYS.Task.Definition
{

Property FlowId As %String(MAXLEN = 32);

Property StepId As %String(MAXLEN = 8);

Property IsRoot As %Boolean;

Method OnTask() As %Status
{
    Quit:'..IsRoot $$$OK

    // Highest-risk assumption of this plan (R-007/OQ-1): firing calls back into the same
    // dispatch path a manual operator would use, so edge ordering is preserved by
    // WaveDispatcher rather than reimplemented in the scheduler.
    Set errorCode = "", errorDetail = "", report = ""
    Set run = ##class(sentai.dispatch.WaveDispatcher).Dispatch(..FlowId, [], "$SCHEDULER", .errorCode, .errorDetail, .report)
    Quit:(run = "") $$$OK

    Do ##class(sentai.dispatch.WaveDispatcher).StartBackgroundLoop(run.guid, "")
    Quit $$$OK
}

}
