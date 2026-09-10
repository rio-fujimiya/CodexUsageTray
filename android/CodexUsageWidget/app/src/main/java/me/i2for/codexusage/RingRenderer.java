package me.i2for.codexusage;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;

final class RingRenderer {
    private RingRenderer() {}

    static Bitmap render(Context context, String label, UsageData.Window window) {
        final int size = dp(context, 38);
        final float stroke = Math.max(dp(context, 2.5f), size * 0.075f);
        final float cx = size / 2f;
        final float cy = size / 2f;
        final float radius = (size - stroke) / 2f - dp(context, 0.5f);

        Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);

        Paint base = new Paint(Paint.ANTI_ALIAS_FLAG);
        base.setStyle(Paint.Style.STROKE);
        base.setStrokeWidth(stroke);
        base.setStrokeCap(Paint.Cap.ROUND);
        base.setColor(Color.argb(68, 255, 255, 255));
        canvas.drawCircle(cx, cy, radius, base);

        int remaining = window == null ? -1 : clamp(window.remainingPercent);
        if (remaining >= 0) {
            Paint progress = new Paint(Paint.ANTI_ALIAS_FLAG);
            progress.setStyle(Paint.Style.STROKE);
            progress.setStrokeWidth(stroke);
            progress.setStrokeCap(Paint.Cap.ROUND);
            progress.setColor(progressColor(remaining));

            if (remaining > 0) {
                RectF oval = new RectF(cx - radius, cy - radius, cx + radius, cy + radius);
                canvas.drawArc(oval, -90f, -remaining * 3.6f, false, progress);
            } else {
                // Empty quota: keep the numerical 0% readable and add a subdued red X.
                Paint cross = new Paint(Paint.ANTI_ALIAS_FLAG);
                cross.setStyle(Paint.Style.STROKE);
                cross.setStrokeWidth(Math.max(dp(context, 2f), stroke * 0.75f));
                cross.setStrokeCap(Paint.Cap.ROUND);
                cross.setColor(Color.argb(150, 255, 92, 92));
                float inset = radius * 0.53f;
                canvas.drawLine(cx - inset, cy - inset, cx + inset, cy + inset, cross);
                canvas.drawLine(cx + inset, cy - inset, cx - inset, cy + inset, cross);
            }
        }

        Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
        text.setColor(Color.rgb(246, 248, 250));
        text.setTextAlign(Paint.Align.CENTER);
        text.setFakeBoldText(true);

        text.setTextSize(size * 0.235f);
        drawCenteredAt(canvas, text, label, cx, cy - size * 0.095f);

        String value = remaining < 0 ? "--" : remaining + "%";
        text.setTextSize(size * (value.length() >= 4 ? 0.205f : 0.225f));
        drawCenteredAt(canvas, text, value, cx, cy + size * 0.155f);
        return bitmap;
    }

    private static void drawCenteredAt(Canvas canvas, Paint paint, String text, float x, float centerY) {
        Paint.FontMetrics fm = paint.getFontMetrics();
        float baseline = centerY - (fm.ascent + fm.descent) / 2f;
        canvas.drawText(text, x, baseline, paint);
    }

    private static int clamp(int value) {
        return Math.max(0, Math.min(100, value));
    }

    private static int progressColor(int remaining) {
        if (remaining >= 50) return Color.rgb(244, 246, 248);
        if (remaining >= 20) return Color.rgb(255, 193, 92);
        return Color.rgb(255, 92, 92);
    }

    private static int dp(Context context, float dp) {
        return Math.max(1, Math.round(dp * context.getResources().getDisplayMetrics().density));
    }
}
