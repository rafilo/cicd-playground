using System.Globalization;
using System.Net;
using System.Text.Json;

await DemoApplication.Build(args).RunAsync();

public static class DemoApplication
{
    public static WebApplication Build(string[] args, string? upstreamOverride = null)
    {
        var builder = WebApplication.CreateBuilder(args);
        builder.Logging.ClearProviders();
        builder.Logging.AddJsonConsole();
        builder.WebHost.ConfigureKestrel(options => options.AddServerHeader = false);
        builder.Services.AddSingleton(new HttpClient(new SocketsHttpHandler
        {
            AllowAutoRedirect = false,
            UseProxy = false,
            PooledConnectionLifetime = TimeSpan.Zero
        }) { Timeout = TimeSpan.FromSeconds(4) });

        var app = builder.Build();
        var upstream = upstreamOverride ?? Environment.GetEnvironmentVariable("UPSTREAM_URL");
        Uri? upstreamUri = null;
        if (!string.IsNullOrEmpty(upstream))
        {
            if (!Uri.TryCreate(upstream, UriKind.Absolute, out upstreamUri) ||
                (upstreamUri.Scheme != "http" && upstreamUri.Scheme != "https"))
                throw new InvalidOperationException("UPSTREAM_URL must be an absolute HTTP(S) URL.");
        }

        long requestCount = 0;
        app.Run(async context =>
        {
            Interlocked.Increment(ref requestCount);
            context.Response.Headers["X-Content-Type-Options"] = "nosniff";
            context.Response.Headers.CacheControl = "no-store";
            context.Response.Headers.ContentSecurityPolicy =
                "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'";
            try
            {
                if (!HttpMethods.IsGet(context.Request.Method))
                {
                    context.Response.Headers.Allow = "GET";
                    await Error(context, 405, "Method not allowed");
                    return;
                }
                var path = context.Request.Path.Value;
                if (path is "/healthz" or "/readyz")
                {
                    await context.Response.WriteAsJsonAsync(new { status = "ok" }, context.RequestAborted);
                    return;
                }
                if (path == "/metrics")
                {
                    context.Response.ContentType = "text/plain; version=0.0.4";
                    await context.Response.WriteAsync("# TYPE app_requests_total counter\napp_requests_total " +
                        Interlocked.Read(ref requestCount).ToString(CultureInfo.InvariantCulture) + "\n", context.RequestAborted);
                    return;
                }
                if (path == "/api/whoami")
                {
                    context.Response.Headers.Connection = "close";
                    if (upstreamUri is null)
                    {
                        await context.Response.WriteAsJsonAsync(new
                        {
                            pod = Environment.GetEnvironmentVariable("HOSTNAME") ?? Environment.MachineName,
                            version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "dev",
                            time = DateTimeOffset.UtcNow.ToString("O")
                        }, context.RequestAborted);
                        return;
                    }
                    await ForwardIdentity(context, upstreamUri, app.Services.GetRequiredService<HttpClient>());
                    return;
                }
                var asset = path switch
                {
                    "/" => ("index.html", "text/html; charset=utf-8"),
                    "/style.css" => ("style.css", "text/css; charset=utf-8"),
                    "/client.js" => ("client.js", "text/javascript; charset=utf-8"),
                    _ => ((string, string)?)null
                };
                if (asset is { } file)
                {
                    // Explicit whitelist: never expose application/configuration files.
                    var filePath = Path.Combine(app.Environment.ContentRootPath, "wwwroot", file.Item1);
                    await Results.File(filePath, file.Item2).ExecuteAsync(context);
                    return;
                }
                await Error(context, 404, "Not found");
            }
            finally
            {
                app.Logger.LogInformation("HTTP {Method} {Path} {StatusCode}",
                    context.Request.Method, context.Request.Path, context.Response.StatusCode);
            }
        });
        return app;
    }

    private static async Task ForwardIdentity(HttpContext context, Uri upstream, HttpClient client)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(upstream, "/api/whoami"));
            request.Headers.ConnectionClose = true;
            request.Version = HttpVersion.Version11;
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, context.RequestAborted);
            response.EnsureSuccessStatusCode();
            // Bound both response size and the time spent reading a streaming body.
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
            timeout.CancelAfter(TimeSpan.FromSeconds(4));
            await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token);
            var buffer = new byte[65_537];
            var length = 0;
            int read;
            while (length < buffer.Length && (read = await stream.ReadAsync(buffer.AsMemory(length), timeout.Token)) > 0)
                length += read;
            if (length > 65_536) throw new InvalidDataException("Upstream response is too large.");
            using var document = JsonDocument.Parse(buffer.AsMemory(0, length));
            var body = document.RootElement;
            IdentityResponseValidator.Validate(body);
            await context.Response.WriteAsJsonAsync(body, context.RequestAborted);
        }
        catch (Exception ex) when (ex is HttpRequestException or OperationCanceledException or JsonException or IOException or InvalidDataException)
        {
            if (!context.RequestAborted.IsCancellationRequested)
                await Error(context, 502, "Backend unavailable");
        }
    }

    private static Task Error(HttpContext context, int status, string message)
    {
        context.Response.StatusCode = status;
        return context.Response.WriteAsJsonAsync(new { error = message }, context.RequestAborted);
    }
}
