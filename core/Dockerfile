# Winopo core · una imagen para API y worker (el perfil lo decide WINOPO_PROFILE)
FROM gradle:8.10-jdk21 AS build
WORKDIR /src
COPY core/settings.gradle.kts core/build.gradle.kts ./
COPY core/gradle ./gradle
COPY core/src ./src
RUN gradle --no-daemon installDist

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
# Usuario sin privilegios: si alguien entra por un fallo, no entra como root.
RUN addgroup -S winopo && adduser -S -G winopo winopo
COPY --from=build --chown=winopo:winopo /src/build/install/winopo/ ./
USER winopo
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \
  CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1
ENTRYPOINT ["./bin/winopo"]
