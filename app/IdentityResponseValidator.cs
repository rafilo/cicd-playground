using System.Text.Json;

public static class IdentityResponseValidator
{
    public static void Validate(JsonElement body)
    {
        if (body.ValueKind != JsonValueKind.Object ||
            !body.TryGetProperty("pod", out var pod) || pod.ValueKind != JsonValueKind.String ||
            !body.TryGetProperty("version", out var version) || version.ValueKind != JsonValueKind.String)
            throw new InvalidDataException("Invalid identity response.");
    }
}
