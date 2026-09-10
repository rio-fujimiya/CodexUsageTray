package me.i2for.codexusage;

final class UsageData {
    static final class Window {
        final int remainingPercent;
        final long resetsAt;

        Window(int remainingPercent, long resetsAt) {
            this.remainingPercent = Math.max(0, Math.min(100, remainingPercent));
            this.resetsAt = resetsAt;
        }
    }

    final long updatedAt;
    final boolean stale;
    final Window fiveHour;
    final Window weekly;

    UsageData(long updatedAt, boolean stale, Window fiveHour, Window weekly) {
        this.updatedAt = updatedAt;
        this.stale = stale;
        this.fiveHour = fiveHour;
        this.weekly = weekly;
    }
}
