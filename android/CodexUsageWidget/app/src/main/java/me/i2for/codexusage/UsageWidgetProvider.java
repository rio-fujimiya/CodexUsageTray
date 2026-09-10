package me.i2for.codexusage;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;

public final class UsageWidgetProvider extends AppWidgetProvider {
    static final String ACTION_REFRESH = "me.i2for.codexusage.ACTION_REFRESH";

    @Override
    public void onEnabled(Context context) {
        UsageScheduler.ensurePeriodic(context);
        UsageScheduler.refreshNow(context);
    }

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        UsageScheduler.ensurePeriodic(context);
        for (int id : appWidgetIds) WidgetRenderer.update(context, appWidgetManager, id);
        UsageScheduler.refreshNow(context);
    }

    @Override
    public void onAppWidgetOptionsChanged(Context context, AppWidgetManager appWidgetManager,
                                          int appWidgetId, Bundle newOptions) {
        WidgetRenderer.update(context, appWidgetManager, appWidgetId);
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (ACTION_REFRESH.equals(intent.getAction())) {
            WidgetRenderer.updateAll(context);
            UsageScheduler.refreshNow(context);
        }
    }
}
