package me.i2for.codexusage;

import android.content.Context;
import android.content.SharedPreferences;

final class UsageStore {
    private static final String PREFS = "codex_usage_cache";

    private UsageStore() {}

    static void save(Context context, UsageData data) {
        SharedPreferences.Editor e = prefs(context).edit();
        e.putLong("updated_at", data.updatedAt);
        e.putBoolean("stale", data.stale);
        putWindow(e, "five", data.fiveHour);
        putWindow(e, "week", data.weekly);
        e.remove("error");
        e.apply();
    }

    static void saveError(Context context, String message) {
        prefs(context).edit().putString("error", message == null ? "error" : message).apply();
    }

    static UsageData load(Context context) {
        SharedPreferences p = prefs(context);
        long updated = p.getLong("updated_at", 0);
        return new UsageData(
                updated,
                p.getBoolean("stale", false),
                getWindow(p, "five"),
                getWindow(p, "week")
        );
    }

    static String getError(Context context) {
        return prefs(context).getString("error", "");
    }

    private static void putWindow(SharedPreferences.Editor e, String prefix, UsageData.Window w) {
        if (w == null) {
            e.putInt(prefix + "_remaining", -1);
            e.putLong(prefix + "_reset", 0);
        } else {
            e.putInt(prefix + "_remaining", w.remainingPercent);
            e.putLong(prefix + "_reset", w.resetsAt);
        }
    }

    private static UsageData.Window getWindow(SharedPreferences p, String prefix) {
        int remaining = p.getInt(prefix + "_remaining", -1);
        if (remaining < 0) return null;
        return new UsageData.Window(remaining, p.getLong(prefix + "_reset", 0));
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
