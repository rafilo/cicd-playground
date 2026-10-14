using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

// Dependency-free integration runner: real Kestrel HTTP, not mocked endpoints.
var contentRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../app"));
static void Check(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
static string Address(WebApplication app) => app.Services.GetRequiredService<IServer>()
    .Features.Get<IServerAddressesFeature>()!.Addresses.Single();
string[] Args() => ["--urls", "http://127.0.0.1:0", "--contentRoot", contentRoot];
await using var backend = DemoApplication.Build(Args(), "");
await backend.StartAsync();
using var client = new HttpClient { BaseAddress = new Uri(Address(backend)) };
var page = await client.GetAsync("/");
Check(page.StatusCode == HttpStatusCode.OK && (await page.Content.ReadAsStringAsync()).Contains("Traffic distribution"), "Homepage");
Check(page.Headers.Contains("Content-Security-Policy"), "Security headers");
foreach (var asset in new[] { "/style.css", "/client.js" })
    Check((await client.GetAsync(asset)).IsSuccessStatusCode, "Static asset " + asset);
foreach (var path in new[] { "/healthz", "/readyz" })
{
    using var json = JsonDocument.Parse(await client.GetStringAsync(path));
    Check(json.RootElement.GetProperty("status").GetString() == "ok", "Probe " + path);
}
var identity = await client.GetAsync("/api/whoami");
using (var json = JsonDocument.Parse(await identity.Content.ReadAsStringAsync()))
{
    Check(json.RootElement.GetProperty("pod").ValueKind == JsonValueKind.String, "Pod identity");
    Check(json.RootElement.GetProperty("version").ValueKind == JsonValueKind.String, "Version identity");
}
Check(identity.Headers.ConnectionClose == true, "Identity connection close");
Check((await client.GetStringAsync("/metrics")).Contains("app_requests_total "), "Metrics");
foreach (var path in new[] { "/missing", "/Program.cs", "/PodFlow.csproj", "/appsettings.json" })
    Check((await client.GetAsync(path)).StatusCode == HttpStatusCode.NotFound, "Route isolation " + path);
Check((await client.PostAsync("/", new StringContent(""))).StatusCode == HttpStatusCode.MethodNotAllowed, "Reject POST");
Console.WriteLine("PASS: frontend, probes, identity, metrics, security headers and route isolation");

var connections = new HashSet<string>();
var builder = WebApplication.CreateBuilder();
builder.WebHost.UseUrls("http://127.0.0.1:0");
await using var upstream = builder.Build();
upstream.MapGet("/api/whoami", (HttpContext ctx) =>
{
    lock (connections) connections.Add(ctx.Connection.Id);
    return Results.Json(new { pod = "test-backend", version = "test-version" });
});
await upstream.StartAsync();
await using var gateway = DemoApplication.Build(Args(), Address(upstream));
await gateway.StartAsync();
using var gatewayClient = new HttpClient { BaseAddress = new Uri(Address(gateway)) };
for (var i = 0; i < 4; i++)
{
    using var json = JsonDocument.Parse(await gatewayClient.GetStringAsync("/api/whoami"));
    Check(json.RootElement.GetProperty("pod").GetString() == "test-backend", "Proxy identity");
}
Check(connections.Count == 4, "Fresh upstream TCP connection per request");
await upstream.StopAsync();
Check((await gatewayClient.GetAsync("/api/whoami")).StatusCode == HttpStatusCode.BadGateway, "Unavailable upstream returns 502");
Console.WriteLine("PASS: reverse proxy, fresh upstream connections and unavailable upstream");

var badBuilder = WebApplication.CreateBuilder();
badBuilder.WebHost.UseUrls("http://127.0.0.1:0");
await using var invalidUpstream = badBuilder.Build();
var oversized = false;
invalidUpstream.MapGet("/api/whoami", () => Results.Text(oversized ? new string('x', 70_000) : "{\"pod\":123}"));
await invalidUpstream.StartAsync();
await using var invalidGateway = DemoApplication.Build(Args(), Address(invalidUpstream));
await invalidGateway.StartAsync();
using var invalidClient = new HttpClient { BaseAddress = new Uri(Address(invalidGateway)) };
Check((await invalidClient.GetAsync("/api/whoami")).StatusCode == HttpStatusCode.BadGateway, "Invalid payload returns 502");
oversized = true;
Check((await invalidClient.GetAsync("/api/whoami")).StatusCode == HttpStatusCode.BadGateway, "Oversized payload returns 502");
Console.WriteLine("PASS: malformed and oversized upstream responses");
Console.WriteLine("All .NET HTTP integration checks passed.");
