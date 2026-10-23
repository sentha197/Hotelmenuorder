using System.Text.Json;
using System.Text.Json.Serialization;

namespace DineQR.Api.Infrastructure;

/// One JSON convention for the API, SignalR and the seed file: camelCase
/// names, enums as camelCase strings (`readyToServe`), nulls left out.
public static class Json
{
    public static readonly JsonSerializerOptions Options = Configure(new JsonSerializerOptions(JsonSerializerDefaults.Web));

    public static JsonSerializerOptions Configure(JsonSerializerOptions options)
    {
        options.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        options.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
        if (!options.Converters.OfType<JsonStringEnumConverter>().Any())
        {
            options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        }
        return options;
    }
}
