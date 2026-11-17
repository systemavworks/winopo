plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    application
}

group = "es.winopo"
version = "0.1.0"

repositories { mavenCentral() }

/**
 * Objetivo de JVM. Por defecto 21 (lo que corre en Docker). En una máquina sin JDK 21 se puede
 * compilar con `-PjvmTarget=17`; el bytecode 17 corre sin problema en el runtime 21.
 */
val jvmObjetivo = (findProperty("jvmTarget") as String?)?.toInt() ?: 21

kotlin { jvmToolchain(jvmObjetivo) }

dependencies {
    implementation(libs.ktor.server.core)
    implementation(libs.ktor.server.netty)
    implementation(libs.ktor.server.content.negotiation)
    implementation(libs.ktor.serialization.json)
    implementation(libs.ktor.server.status.pages)
    implementation(libs.ktor.server.call.logging)
    implementation(libs.postgresql)
    implementation(libs.hikari)
    implementation(libs.logback)

    testImplementation(kotlin("test"))
    testImplementation(libs.ktor.server.test.host)
    testImplementation(libs.ktor.client.content.negotiation)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

application {
    mainClass.set("es.winopo.core.MainKt")
    applicationName = "winopo"
}

tasks.test {
    useJUnitPlatform()
    testLogging { events("passed", "skipped", "failed") }
    // Sin DATABASE_URL los tests de integración se saltan, no fallan: el CI los corre con su Postgres.
    environment("DATABASE_URL", System.getenv("DATABASE_URL") ?: "")
}
