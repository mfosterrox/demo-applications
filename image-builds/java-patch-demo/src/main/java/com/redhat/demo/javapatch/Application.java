package com.redhat.demo.javapatch;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootVersion;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
@RestController
public class Application {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }

    @GetMapping(value = "/", produces = MediaType.APPLICATION_JSON_VALUE)
    public String home() {
        return "{"
                + "\"application\":\"java-patch-demo\","
                + "\"patch\":\"" + jsonEscape(env("DEMO_PATCH")) + "\","
                + "\"springBoot\":\"" + jsonEscape(springBootVersion()) + "\","
                + "\"java\":\"" + jsonEscape(System.getProperty("java.version", "unknown")) + "\","
                + "\"baseImage\":\"" + jsonEscape(env("DEMO_BASE_IMAGE")) + "\""
                + "}";
    }

    @GetMapping(value = "/health", produces = MediaType.APPLICATION_JSON_VALUE)
    public String health() {
        return "{\"status\":\"UP\"}";
    }

    private static String springBootVersion() {
        String version = SpringBootVersion.getVersion();
        if (version == null || version.isBlank()) {
            return "unknown";
        }
        return version;
    }

    private static String env(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            return "unknown";
        }
        return value;
    }

    private static String jsonEscape(String value) {
        return value.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
