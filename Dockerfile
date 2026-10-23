FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY backend/src/DineQR.Api/ ./backend/src/DineQR.Api/

RUN dotnet restore backend/src/DineQR.Api/DineQR.Api.csproj

COPY . .

RUN dotnet publish backend/src/DineQR.Api/DineQR.Api.csproj \
    --configuration Release \
    --output /app/publish \
    --no-restore \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

COPY --from=build /app/publish .

ENV ASPNETCORE_HTTP_PORTS=10000
# Render terminates HTTPS and forwards plain HTTP with X-Forwarded-Proto and
# X-Forwarded-For. Honour them so the API sees https (uploaded photo URLs)
# and each caller's own address (sign-in and order rate limits).
ENV ASPNETCORE_FORWARDEDHEADERS_ENABLED=true
EXPOSE 10000

ENTRYPOINT ["dotnet", "DineQR.Api.dll"]
