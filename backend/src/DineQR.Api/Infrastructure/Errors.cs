using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Infrastructure;

/// An expected failure with a stable machine-readable [Code] (e.g.
/// `tableUnavailable`) and a message safe to show to the user.
public sealed class ApiException(
    int status,
    string code,
    string message,
    IDictionary<string, string[]>? errors = null) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
    public IDictionary<string, string[]>? Errors { get; } = errors;

    public static ApiException BadRequest(string code, string message) =>
        new(StatusCodes.Status400BadRequest, code, message);

    public static ApiException Validation(string field, string message) =>
        new(StatusCodes.Status400BadRequest, "validation", message,
            new Dictionary<string, string[]> { [field] = [message] });

    public static ApiException NotFound(string message = "Not found.") =>
        new(StatusCodes.Status404NotFound, "notFound", message);

    public static ApiException Conflict(string code, string message) =>
        new(StatusCodes.Status409Conflict, code, message);

    public static ApiException Forbidden(string message = "You do not have permission to do that.") =>
        new(StatusCodes.Status403Forbidden, "forbidden", message);

    public static ApiException Unauthorized(string code, string message) =>
        new(StatusCodes.Status401Unauthorized, code, message);

    public static ApiException Unavailable(string code, string message) =>
        new(StatusCodes.Status503ServiceUnavailable, code, message);
}

/// Turns exceptions into RFC 7807 problem responses. Unexpected errors are
/// logged with details but returned without any.
public sealed class ApiExceptionHandler(
    IProblemDetailsService problems,
    ILogger<ApiExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext http,
        Exception exception,
        CancellationToken ct)
    {
        var (status, code, message, errors) = exception switch
        {
            ApiException api => (api.Status, api.Code, api.Message, api.Errors),
            DbUpdateConcurrencyException => (StatusCodes.Status409Conflict, "conflict",
                "Someone else changed this at the same time. Refresh and try again.", null),
            BadHttpRequestException => (StatusCodes.Status400BadRequest, "badRequest",
                "The request was not valid.", null),
            _ => (StatusCodes.Status500InternalServerError, "internal",
                "Something went wrong on the server.", (IDictionary<string, string[]>?)null),
        };
        if (status >= 500)
        {
            logger.LogError(exception, "Unhandled error for {Method} {Path}", http.Request.Method, http.Request.Path);
        }
        http.Response.StatusCode = status;
        var details = new ProblemDetails { Status = status, Title = message };
        details.Extensions["code"] = code;
        if (errors != null) details.Extensions["errors"] = errors;
        return await problems.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = http,
            ProblemDetails = details,
            Exception = exception,
        });
    }
}
