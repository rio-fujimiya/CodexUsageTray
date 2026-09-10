package me.i2for.codexusage;

import android.content.Context;

import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

public final class UsageWorker extends Worker {
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
            UsageData data = UsageClient.fetch(context);
            UsageStore.save(context, data);
            WidgetRenderer.updateAll(context);
            return Result.success();
        } catch (Exception e) {
            UsageStore.saveError(context, e.getMessage());
            WidgetRenderer.updateAll(context);
            return Result.retry();
        }
    }
}
