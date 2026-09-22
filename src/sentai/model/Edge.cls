/// A directed dependency between two steps of the same flow. The edge set of a flow MUST
/// always be acyclic — checked on every mutation, not only at save (FR-007, NFR-003).
Class sentai.model.Edge Extends (%Persistent, %JSON.Adaptor)
{

Property flow As sentai.model.Flow [ Required ];

Property source As %String(MAXLEN = 8) [ Required ];

Property target As %String(MAXLEN = 8) [ Required ];

/// Supports wave-eligibility computation and cycle detection without scanning every edge
/// of the flow on each check (data-model.md).
Index FlowTargetIndex On (flow, target);

Index FlowSourceIndex On (flow, source);

/// Replaces every edge of `flow` with the submitted array, inside the caller's transaction.
/// Rejects (without persisting anything) if the resulting graph would be cyclic.
ClassMethod ReplaceAll(flowId As %String, edgesArray As %DynamicArray) As %Status
{
    Set sc = $$$OK
    Try {
        If ..WouldGraphBeCyclic(flowId, edgesArray) {
            Set sc = $$$ERROR($$$GeneralError, "SentaiCycle: the submitted edge set contains a cycle")
            Quit
        }

        &sql(DELETE FROM sentai.model.Edge WHERE flow = :flowId)
        If (edgesArray = "") Quit

        Set iter = edgesArray.%GetIterator()
        While iter.%GetNext(.k, .edgeObj) {
            Set edge = ..%New()
            Set edge.flow = flowId
            Set edge.source = edgeObj.source
            Set edge.target = edgeObj.target
            Set sc = edge.%Save()
            If $$$ISERR(sc) Quit
        }
    }
    Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// True if adding a single new edge (source -> target) on top of the flow's currently
/// PERSISTED edges would close a cycle — the check used on every incremental mutation
/// (FR-007). Depth-first search from `target`: if `source` is reachable from `target`
/// following existing edges, the new edge would close a cycle.
ClassMethod WouldCreateCycle(flowId As %String, source As %String, target As %String) As %Boolean
{
    If (source = target) Quit 1
    Set visited("") = ""
    Kill visited("")
    Quit ..IsReachable(flowId, target, source, .visited)
}

/// Depth-first reachability of `to` starting from `from`, over the flow's persisted edges.
ClassMethod IsReachable(flowId As %String, from As %String, to As %String, ByRef visited) As %Boolean
{
    If $D(visited(from)) Quit 0
    Set visited(from) = 1
    If (from = to) Quit 1

    Set rs = ##class(%SQL.Statement).%New()
    Do rs.%Prepare("SELECT target FROM sentai.model.Edge WHERE flow = ? AND source = ?")
    Set result = rs.%Execute(flowId, from)
    While result.%Next() {
        If ..IsReachable(flowId, result.%Get("target"), to, .visited) Quit 1
    }
    Quit 0
}

/// Whole-graph acyclicity check over a candidate edge array not yet persisted — used by
/// ReplaceAll (a full PUT/POST may resubmit the entire edge set at once) via a standard
/// topological-sort (Kahn's algorithm) over the in-memory candidate set only.
ClassMethod WouldGraphBeCyclic(flowId As %String, edgesArray As %DynamicArray) As %Boolean
{
    If (edgesArray = "") Quit 0

    Kill adj, indegree, nodes
    Set iter = edgesArray.%GetIterator()
    While iter.%GetNext(.k, .edgeObj) {
        Set s = edgeObj.source, t = edgeObj.target
        Set nodes(s) = 1, nodes(t) = 1
        Set adj(s, $I(adj(s))) = t
        Set indegree(t) = $G(indegree(t)) + 1
        If '$D(indegree(s)) Set indegree(s) = 0
    }

    Set queueCount = 0
    Set node = ""
    For {
        Set node = $O(nodes(node))
        Quit:node=""
        If ($G(indegree(node)) = 0) {
            Set queueCount = queueCount + 1
            Set queue(queueCount) = node
        }
    }

    Set processed = 0, qHead = 1
    While (qHead <= queueCount) {
        Set n = queue(qHead)
        Set qHead = qHead + 1
        Set processed = processed + 1
        Set i = ""
        For {
            Set i = $O(adj(n, i))
            Quit:i=""
            Set m = adj(n, i)
            Set indegree(m) = indegree(m) - 1
            If (indegree(m) = 0) {
                Set queueCount = queueCount + 1
                Set queue(queueCount) = m
            }
        }
    }

    Set nodeCount = 0
    Set node = ""
    For {
        Set node = $O(nodes(node))
        Quit:node=""
        Set nodeCount = nodeCount + 1
    }

    Quit (processed '= nodeCount)
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
