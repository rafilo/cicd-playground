using System.Text.Json;
using Xunit;

public class IdentityResponseValidatorTests
{
    [Fact]
    public void Valid_simulated_backend_identity_is_accepted()
    {
        // Simulated backend response: no server, network or Kubernetes required.
        using var response = JsonDocument.Parse("""
            {"pod":"demo-7d9c-test","version":"release-123","time":"2026-10-14T00:00:00Z"}
            """);
        var exception = Record.Exception(() => IdentityResponseValidator.Validate(response.RootElement));
        Assert.Null(exception);
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"pod\":\"demo\"}")]
    [InlineData("{\"version\":\"v1\"}")]
    [InlineData("{\"pod\":123,\"version\":\"v1\"}")]
    [InlineData("{\"pod\":\"demo\",\"version\":null}")]
    [InlineData("[]")]
    [InlineData("null")]
    public void Invalid_simulated_identity_is_rejected(string json)
    {
        using var response = JsonDocument.Parse(json);
        Assert.Throws<InvalidDataException>(() => IdentityResponseValidator.Validate(response.RootElement));
    }
}
