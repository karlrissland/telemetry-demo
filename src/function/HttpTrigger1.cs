using System.Diagnostics;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace Company.Function;

public class HttpTrigger1
{
    private readonly ILogger<HttpTrigger1> _logger;

    public HttpTrigger1(ILogger<HttpTrigger1> logger)
    {
        _logger = logger;
    }

    [Function("HttpTrigger1")]
    public async Task<IActionResult> Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", "post")] HttpRequest req)
    {
        var traceParent = req.Headers["traceparent"].ToString();
        var traceState = req.Headers["tracestate"].ToString();
        var requestId = req.Headers["x-ms-request-id"].ToString();

        _logger.LogInformation(
            "Incoming trace headers: traceparent={TraceParent}, tracestate={TraceState}, requestId={RequestId}, activityId={ActivityId}, parentId={ParentId}",
            traceParent,
            traceState,
            requestId,
            Activity.Current?.Id,
            Activity.Current?.ParentId);

        Activity.Current?.SetTag("traceparent", traceParent);
        Activity.Current?.SetTag("tracestate", traceState);

        using var document = await JsonDocument.ParseAsync(req.Body);
        if (document.RootElement.TryGetProperty("orderNumber", out var orderNumberElement) &&
            orderNumberElement.ValueKind == JsonValueKind.String)
        {
            var orderNumber = orderNumberElement.GetString();
            if (!string.IsNullOrWhiteSpace(orderNumber))
            {
                Activity.Current?.SetTag("orderNumber", orderNumber);
                _logger.LogInformation("Function processed order {OrderNumber}.", orderNumber);
            }
        }

        _logger.LogInformation("C# HTTP trigger function processed a request.");
        return new OkObjectResult("Welcome to Azure Functions!");
    }
}