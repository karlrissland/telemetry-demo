using System.Diagnostics;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.ApplicationInsights;
using Microsoft.Extensions.Logging;

namespace Company.Function;

public class HttpTrigger1
{
    private readonly ILogger<HttpTrigger1> _logger;
    private readonly TelemetryClient _telemetryClient;

    public HttpTrigger1(ILogger<HttpTrigger1> logger, TelemetryClient telemetryClient)
    {
        _logger = logger;
        _telemetryClient = telemetryClient;
    }

    [Function("HttpTrigger1")]
    public async Task<IActionResult> Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", "post")] HttpRequest req)
    {
        using var document = await JsonDocument.ParseAsync(req.Body);
        if (document.RootElement.TryGetProperty("orderNumber", out var orderNumberElement) &&
            orderNumberElement.ValueKind == JsonValueKind.String)
        {
            var orderNumber = orderNumberElement.GetString();
            if (!string.IsNullOrWhiteSpace(orderNumber))
            {
                Activity.Current?.SetTag("orderNumber", orderNumber);
                _telemetryClient.TrackEvent(
                    "funcordernumber",
                    new Dictionary<string, string> { ["orderNumber"] = orderNumber });
            }
        }

        _logger.LogInformation("C# HTTP trigger function processed a request.");
        return new OkObjectResult("Welcome to Azure Functions!");
    }
}