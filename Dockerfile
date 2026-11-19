# The customer web app (apps/dineqr_customer-web), served by the API from the
# same origin: an empty VITE_API_URL makes it call /api and /hubs on the host
# it was loaded from, so no CORS origin is needed.
FROM node:22-slim AS web
WORKDIR /web

COPY apps/dineqr_customer-web/package.json apps/dineqr_customer-web/package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY apps/dineqr_customer-web/ ./
ENV VITE_API_URL=
RUN npm run build
# Brotli and gzip copies of the hashed assets, served as they are (no
# compression work per request).
COPY tools/precompress.mjs /tools/precompress.mjs
RUN node /tools/precompress.mjs dist

# The staff admin web app (apps/dineqr_admin_web), served at /admin/ from the
# same origin (empty VITE_API_URL, so no CORS origin is needed either).
FROM node:22-slim AS admin
WORKDIR /admin

COPY apps/dineqr_admin_web/package.json apps/dineqr_admin_web/package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY apps/dineqr_admin_web/ ./
RUN rm -f .env.*.local
ENV VITE_API_URL=
RUN npm run build -- --base=/admin/
COPY tools/precompress.mjs /tools/precompress.mjs
RUN node /tools/precompress.mjs dist

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY backend/src/DineQR.Api/ ./backend/src/DineQR.Api/

# linux-x64 only (not every platform's native image libraries, which made the
# published app 214 MB instead of 67 MB) and ReadyToRun: code is compiled ahead
# of time, so a restarted service answers its first requests without waiting
# for the JIT.
RUN dotnet restore backend/src/DineQR.Api/DineQR.Api.csproj \
    -r linux-x64 \
    -p:PublishReadyToRun=true

COPY . .

RUN dotnet publish backend/src/DineQR.Api/DineQR.Api.csproj \
    --configuration Release \
    --output /app/publish \
    --no-restore \
    -r linux-x64 \
    --self-contained false \
    -p:PublishReadyToRun=true \
    -p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

COPY --from=build /app/publish .
COPY --from=web /web/dist ./web
COPY --from=admin /admin/dist ./web/admin

ENV ASPNETCORE_HTTP_PORTS=10000
# Render terminates HTTPS and forwards plain HTTP with X-Forwarded-Proto and
# X-Forwarded-For. Honour them so the API sees https (uploaded photo URLs)
# and each caller's own address (sign-in and order rate limits).
ENV ASPNETCORE_FORWARDEDHEADERS_ENABLED=true
EXPOSE 10000

ENTRYPOINT ["dotnet", "DineQR.Api.dll"]
