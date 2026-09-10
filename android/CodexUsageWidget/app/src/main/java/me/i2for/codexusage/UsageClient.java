package me.i2for.codexusage;

import android.content.Context;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

final class UsageClient {
    private UsageClient() {}

    static UsageData fetch(Context context) throws Exception {
        String base = SecurePrefs.getBaseUrl(context);
        String token = SecurePrefs.getToken(context);
        if (base.isEmpty() || token.isEmpty()) throw new IllegalStateException("Not configured");

        URL url = new URL(base + "/usage");
        HttpURLConnection c = (HttpURLConnection) url.openConnection();
        c.setRequestMethod("GET");
        c.setConnectTimeout(10_000);
        c.setReadTimeout(10_000);
        c.setUseCaches(false);
        c.setRequestProperty("Accept", "application/json");
        c.setRequestProperty("Authorization", "Bearer " + token);
        c.setRequestProperty("ngrok-skip-browser-warning", "1");

        try {
            int code = c.getResponseCode();
            InputStream in = code >= 200 && code < 300 ? c.getInputStream() : c.getErrorStream();
            String body = readAll(in);
            if (code != 200) throw new IllegalStateException("HTTP " + code + ": " + body);

            JSONObject o = new JSONObject(body);
            return new UsageData(
                    o.optLong("updatedAt", 0),
                    o.optBoolean("stale", false),
                    parseWindow(o, "fiveHour"),
                    parseWindow(o, "weekly")
            );
        } finally {
            c.disconnect();
        }
    }

    private static UsageData.Window parseWindow(JSONObject root, String key) {
        if (root.isNull(key)) return null;
        JSONObject o = root.optJSONObject(key);
        if (o == null) return null;
        if (!o.has("remainingPercent")) return null;
        return new UsageData.Window(
                o.optInt("remainingPercent", 0),
                o.optLong("resetsAt", 0)
        );
    }

    private static String readAll(InputStream input) throws Exception {
        if (input == null) return "";
        StringBuilder sb = new StringBuilder();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            String line;
            while ((line = r.readLine()) != null) sb.append(line);
        }
        return sb.toString();
    }
}
