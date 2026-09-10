package me.i2for.codexusage;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

public final class UsageWorker extends Worker {
    private static final String CHANNEL_ID = "quota_restored";
    private static final int NOTIFICATION_ID = 5101;

    public UsageWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    @NonNull
    @Override
    public Result doWork() {
        Context context = getApplicationContext();
        if (!SecurePrefs.isConfigured(context)) {
            WidgetRenderer.updateAll(context);
            return Result.success();
        }

        try {
            UsageData previous = UsageStore.load(context);
            UsageData data = UsageClient.fetch(context);

            boolean fiveRestored = restored(previous.fiveHour, data.fiveHour);
            boolean weekRestored = restored(previous.weekly, data.weekly);

            UsageStore.save(context, data);
            WidgetRenderer.updateAll(context);

            if (fiveRestored || weekRestored) {
                notifyQuotaRestored(context, data, fiveRestored, weekRestored);
            }
            return Result.success();
        } catch (Exception e) {
            UsageStore.saveError(context, e.getMessage());
            WidgetRenderer.updateAll(context);
            return Result.retry();
        }
    }

    private static boolean restored(UsageData.Window previous, UsageData.Window current) {
        return previous != null
                && current != null
                && previous.remainingPercent == 0
                && current.remainingPercent > 0;
    }

    private static void notifyQuotaRestored(
            Context context,
            UsageData current,
            boolean fiveRestored,
            boolean weekRestored
    ) {
        if (Build.VERSION.SDK_INT >= 33
                && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            return;
        }

        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);

        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Codex / Work 残量復活",
                NotificationManager.IMPORTANCE_DEFAULT
        );
        channel.setDescription("5h枠または週間枠が0%から復活したときに通知します");
        manager.createNotificationChannel(channel);

        String body;
        if (fiveRestored && weekRestored) {
            body = "5h " + current.fiveHour.remainingPercent + "% / W "
                    + current.weekly.remainingPercent + "% に復活しました";
        } else if (fiveRestored) {
            body = "5h枠が " + current.fiveHour.remainingPercent + "% に復活しました";
        } else {
            body = "週間枠が " + current.weekly.remainingPercent + "% に復活しました";
        }

        Intent openChatGpt = context.getPackageManager()
                .getLaunchIntentForPackage("com.openai.chatgpt");
        if (openChatGpt == null) {
            openChatGpt = new Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://chatgpt.com/")
            );
        }
        openChatGpt.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        PendingIntent contentIntent = PendingIntent.getActivity(
                context,
                5101,
                openChatGpt,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        Notification notification = new Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_notify_more)
                .setContentTitle("Codex / Work の残量が復活")
                .setContentText(body)
                .setContentIntent(contentIntent)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_STATUS)
                .build();

        manager.notify(NOTIFICATION_ID, notification);
    }
}
