# --- Build stage ---
FROM maven:3-eclipse-temurin-21 AS build
WORKDIR /app

# Leverage layer caching: resolve dependencies before copying source
COPY pom.xml .
RUN mvn -q -B dependency:go-offline

COPY src ./src
RUN mvn -q -B clean package -DskipTests

# --- Runtime stage ---
FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app

# The base image's own apk snapshot lags behind Alpine's actual package repo (stage 8's Trivy
# scan has caught real, already-patched-upstream CVEs this way) - upgrade at build time instead
# of waiting for eclipse-temurin to rebuild the image.
RUN apk update && apk upgrade --no-cache

RUN addgroup -S spring && adduser -S spring -G spring
USER spring:spring

COPY --from=build /app/target/backend.jar /app/app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
