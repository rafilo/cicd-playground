FROM mcr.microsoft.com/dotnet/sdk:10.0.402 AS build
WORKDIR /src
COPY global.json ./
COPY NuGet.Config ./
COPY Directory.Build.props ./
COPY app/PodFlow.csproj app/
COPY app/packages.lock.json app/
RUN dotnet restore app/PodFlow.csproj --configfile NuGet.Config --locked-mode
COPY app/ app/
RUN dotnet publish app/PodFlow.csproj -c Release --no-restore -o /out /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
ARG VERSION=dev
ENV APP_VERSION=$VERSION ASPNETCORE_HTTP_PORTS=8080 DOTNET_EnableDiagnostics=0
WORKDIR /app
COPY --from=build --chown=1000:1000 /out/ ./
# Match existing Kubernetes runAsUser/runAsGroup and restricted Pod Security.
USER 1000:1000
EXPOSE 8080
ENTRYPOINT ["dotnet", "PodFlow.dll"]
