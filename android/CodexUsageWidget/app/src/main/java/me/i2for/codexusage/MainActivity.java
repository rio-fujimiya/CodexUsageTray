package me.i2for.codexusage;

import android.app.Activity;
import android.appwidget.AppWidgetManager;
import android.content.Intent;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

public final class MainActivity extends Activity {
    private EditText url;
    private EditText token;
    private TextView status;
    private int configuringWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID;
    private boolean launchedAsWidgetConfig = false;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        launchedAsWidgetConfig = AppWidgetManager.ACTION_APPWIDGET_CONFIGURE.equals(getIntent().getAction())
                || getIntent().hasExtra(AppWidgetManager.EXTRA_APPWIDGET_ID);
        configuringWidgetId = getIntent().getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID);

        if (launchedAsWidgetConfig) {
            Intent canceled = new Intent();
            canceled.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, configuringWidgetId);
            setResult(RESULT_CANCELED, canceled);
        }

        int pad = dp(20);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("Codex Usage Widget");
        title.setTextSize(24);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(title, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView help = new TextView(this);
        help.setText("\nngrok の固定 dev domain HTTPS URLと、Windowsの Install.ps1 が表示したBearer tokenを入力します。"
                + "\n\nウィジェット: タップ → ChatGPT / 長押し → 再設定（対応ランチャー）\n");
        help.setTextSize(14);
        root.addView(help);

        url = new EditText(this);
        url.setHint("https://your-assigned-name.ngrok-free.app");
        url.setSingleLine(true);
        url.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        url.setText(SecurePrefs.getBaseUrl(this));
        root.addView(url, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        token = new EditText(this);
        token.setHint("Bearer token");
        token.setSingleLine(true);
        token.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        root.addView(token, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        Button save = new Button(this);
        save.setText(launchedAsWidgetConfig ? "保存" : "保存してテスト");
        root.addView(save);

        status = new TextView(this);
        status.setText("\n設定は全ウィジェット共通です。アプリ一覧から Codex Usage を開いてもいつでも編集できます。");
        root.addView(status);

        save.setOnClickListener(v -> saveAndTest());
        setContentView(root);
    }

    private void saveAndTest() {
        try {
            String newToken = token.getText().toString();
            if (newToken.trim().isEmpty() && SecurePrefs.isConfigured(this)) {
                // Reconfiguration normally changes only the URL. Preserve the existing secret when the token box is blank.
                SecurePrefs.save(this, url.getText().toString(), SecurePrefs.getToken(this));
            } else {
                SecurePrefs.save(this, url.getText().toString(), newToken);
            }
            token.setText("");
            UsageScheduler.ensurePeriodic(this);
            WidgetRenderer.updateAll(this);
        } catch (Exception e) {
            status.setText("設定エラー: " + e.getMessage());
            return;
        }

        if (launchedAsWidgetConfig) {
            Intent result = new Intent();
            result.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, configuringWidgetId);
            setResult(RESULT_OK, result);
            UsageScheduler.refreshNow(this);
            Toast.makeText(this, "設定を保存しました", Toast.LENGTH_SHORT).show();
            finish();
            return;
        }

        status.setText("接続テスト中…");
        new Thread(() -> {
            try {
                UsageData data = UsageClient.fetch(this);
                UsageStore.save(this, data);
                WidgetRenderer.updateAll(this);
                runOnUiThread(() -> {
                    status.setText("OK: Windows relayへ接続できました。");
                    Toast.makeText(this, "接続OK", Toast.LENGTH_SHORT).show();
                });
            } catch (Exception e) {
                UsageStore.saveError(this, e.getMessage());
                WidgetRenderer.updateAll(this);
                runOnUiThread(() -> status.setText("接続失敗: " + e.getMessage()));
            }
        }).start();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
