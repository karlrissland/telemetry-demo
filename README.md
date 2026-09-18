# Telemetry Demo Notes

## Summary

This demo shows an Azure Logic App Standard workflow calling an Azure Function over managed identity, with a shared Application Insights workspace for cross-service telemetry correlation.

The deployed solution is working end-to-end for the auth path and request flow. A successful request is returning HTTP 200 and the workflow is emitting the expected `x-ms-client-tracking-id` value.

## Verified behavior

### 1. Auth and invocation path work

The Logic App trigger URL must be the current signed callback returned by the Logic App runtime. A stale callback URL causes authorization failures even when the managed identity / Easy Auth configuration is correct.

The current valid trigger URL pattern is:

```
https://<logicapp>.azurewebsites.net:443/api/reqres/triggers/When_an_HTTP_request_is_received/invoke?api-version=2022-05-01&sp=%2Ftriggers%2FWhen_an_HTTP_request_is_received%2Frun&sv=1.0&sig=<current-sig>
```

When invoked with the current signed URL, the Logic App returns HTTP 200 and includes headers such as:

- `x-ms-client-tracking-id: 12345`
- `x-ms-workflow-run-id: ...`
- `x-ms-correlation-id: ...`

### 2. Trace propagation works when the caller supplies W3C trace headers

A request to the Logic App trigger with a caller-supplied W3C `traceparent` header was verified to propagate through to the Function.

Example header sent:

```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
tracestate: rojo=00f067aa0ba902b7
```

The live telemetry showed:

- Function `OperationId = 4bf92f3577b34da6a3ce929d0e0e4736`
- Function `ParentId = 00f067aa0ba902b7`

This matches the caller-supplied `traceparent`, confirming the Function is receiving and adopting the W3C trace context.

## Important product question for the team

The current behavior suggests that the workflow can explicitly forward inbound trace headers and the Function logs the propagated W3C trace lineage correctly. However, the Logic App / Function Application Map still does not reliably stitch into a single end-to-end dependency graph in the portal, even when trace propagation is working.

This raises the key product question:

- Is there a supported way for Logic Apps Standard to expose or continue the current runtime trace context so that the Logic App and downstream Function appear as a single distributed trace in Azure Monitor / Application Insights Application Map?

The specific issue we observed is that the Logic App runtime and the Function can each emit valid operation IDs and parent IDs, yet the portal still does not consistently show them as a single linked dependency graph even after trace propagation is enabled.

## Practical takeaway

For customer demos, the following combination is the most reliable:

1. Keep using the managed-identity HTTP call to the Function.
2. Set the Logic App trigger `clientTrackingId` to the order identifier.
3. Forward the incoming `traceparent` to the downstream Function when the caller provides one.
4. Use the `x-ms-client-tracking-id` and the W3C trace headers for business-level and trace-level correlation.

This provides a strong story for troubleshooting and debugging, while also highlighting the remaining product gap in the portal’s cross-service topology view.

## Files touched for this experiment

- `src/logicapps/td-lg/reqres/workflow.json`
- `src/function/HttpTrigger1.cs`
- `tests/happypath.http`

## Result

The auth path is fixed and the trace propagation path is proven. The remaining area to ask the product team about is the portal-level graph stitching / Application Map behavior for Logic App Standard to Function when W3C trace propagation is already in place.
