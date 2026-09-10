package me.i2for.codexusage;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.RemoteViews;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

final class WidgetRenderer {
    private static final int WIDE_MIN_WIDTH_DP = 180;
    private static final int WIDE_MIN_HEIGHT_DP = 68;
    private static final String CHATGPT_PACKAGE = "com.openai.chatgpt";

    private WidgetRenderer() {}

    static void updateAll(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        ComponentName provider = new ComponentName(context, UsageWidgetProvider.class);
        int[] ids = manager.getAppWidgetIds(provider);
        for (int id : ids) update(context, manager, id);
    }

    static void update(Context context, AppWidgetManager manager, int appWidgetId) {
        Bundle options = manager.getAppWidgetOptions(appWidgetId);
        int minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 56);
        int minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 56);
        boolean wide = minWidth >= WIDE_MIN_WIDTH_DP && minHeight >= WIDE_MIN_HEIGHT_DP;

        UsageData data = UsageStore.load(context);
        RemoteViews views = wide
                ? renderWide(context, data)
                : renderCompact(context, data);

        bindClicks(context, views, wide);
        manager.updateAppWidget(appWidgetId, views);
    }

    private static RemoteViews renderCompact(Context context, UsageData data) {
        RemoteViews v = new RemoteViews(context.getPackageName(), R.layout.usage_widget_compact);
        bindCompactWindow(context, v, R.id.compact_five_ring, R.id.compact_five_reset, "5h", data.fiveHour);
        bindCompactWindow(context, v, R.id.compact_week_ring, R.id.compact_week_reset, "W", data.weekly);

        v.setTextViewText(R.id.compact_status, statusMark(context, data));
        return v;
    }

    private static RemoteViews renderWide(Context context, UsageData data) {
        RemoteViews v = new RemoteViews(context.getPackageName(), R.layout.usage_widget_wide);
        bindWindow(v, R.id.five_progress, R.id.five_percent, R.id.five_reset, data.fiveHour);
        bindWindow(v, R.id.week_progress, R.id.week_percent, R.id.week_reset, data.weekly);

        String status;
        if (!SecurePrefs.isConfigured(context)) {
            status = "Long-press → Reconfigure";
        } else if (!UsageStore.getError(context).isEmpty()) {
            status = "ERR · tap ↻";
        } else if (data.updatedAt <= 0) {
            status = "Waiting for first update";
        } else if (isStale(data)) {
            status = "STALE · " + formatUpdated(data.updatedAt);
        } else {
            status = "Updated " + formatUpdated(data.updatedAt);
        }
        v.setTextViewText(R.id.status, status);
        return v;
    }

    private static void bindClicks(Context context, RemoteViews v, boolean wide) {
        Intent chatGptIntent = context.getPackageManager().getLaunchIntentForPackage(CHATGPT_PACKAGE);
        if (chatGptIntent == null) {
            // If the official app is not installed, fall back to ChatGPT on the web.
            chatGptIntent = new Intent(Intent.ACTION_VIEW, Uri.parse("https://chatgpt.com/"));
        }
        chatGptIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent chatGptPi = PendingIntent.getActivity(
                context, 101, chatGptIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        v.setOnClickPendingIntent(R.id.widget_root, chatGptPi);

        if (wide) {
            Intent refreshIntent = new Intent(context, UsageWidgetProvider.class)
                    .setAction(UsageWidgetProvider.ACTION_REFRESH);
            PendingIntent refreshPi = PendingIntent.getBroadcast(
                    context, 102, refreshIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            v.setOnClickPendingIntent(R.id.refresh, refreshPi);
        }
    }

    private static void bindCompactWindow(Context context, RemoteViews v, int ringId, int resetId,
                                          String label, UsageData.Window w) {
        v.setImageViewBitmap(ringId, RingRenderer.render(context, label, w));
        v.setTextViewText(resetId, w == null ? "--" : formatReset(w.resetsAt));
    }

    private static String statusMark(Context context, UsageData data) {
        if (!SecurePrefs.isConfigured(context)) return "SET";
        if (!UsageStore.getError(context).isEmpty()) return "ERR";
        if (data.updatedAt <= 0) return "…";
        if (isStale(data)) return "!";
        return "";
    }

    private static boolean isStale(UsageData data) {
        return data.stale || (data.updatedAt > 0 && System.currentTimeMillis() / 1000L - data.updatedAt > 1200);
    }

    private static void bindWindow(RemoteViews v, int progressId, int percentId, int resetId, UsageData.Window w) {
        if (w == null) {
            v.setProgressBar(progressId, 100, 0, false);
            v.setTextViewText(percentId, "--%");
            v.setTextViewText(resetId, "--");
            return;
        }
        v.setProgressBar(progressId, 100, w.remainingPercent, false);
        v.setTextViewText(percentId, w.remainingPercent + "%");
        v.setTextViewText(resetId, formatReset(w.resetsAt));
    }

    private static String formatReset(long epochSeconds) {
        if (epochSeconds <= 0) return "--";
        long now = System.currentTimeMillis() / 1000L;
        long delta = epochSeconds - now;
        String pattern = (delta >= 0 && delta <= 24L * 60L * 60L) ? "HH:mm" : "MM/dd";
        return new SimpleDateFormat(pattern, Locale.getDefault()).format(new Date(epochSeconds * 1000L));
    }

    private static String formatUpdated(long epochSeconds) {
        return new SimpleDateFormat("HH:mm", Locale.getDefault()).format(new Date(epochSeconds * 1000L));
    }
}
