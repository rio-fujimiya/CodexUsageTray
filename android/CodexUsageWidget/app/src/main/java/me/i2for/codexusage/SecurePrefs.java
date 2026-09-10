package me.i2for.codexusage;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class SecurePrefs {
    private static final String PREFS = "codex_usage_config";
    private static final String KEY_URL = "base_url";
    private static final String KEY_TOKEN_CT = "token_ct";
    private static final String KEY_TOKEN_IV = "token_iv";
    private static final String ALIAS = "codex_usage_widget_token_v1";

    private SecurePrefs() {}

    static void save(Context context, String baseUrl, String token) throws Exception {
        String normalized = normalizeBaseUrl(baseUrl);
        if (!normalized.startsWith("https://")) {
            throw new IllegalArgumentException("URL must start with https://");
        }
        URI uri = URI.create(normalized);
        String host = uri.getHost();
        if (host == null || !(host.endsWith(".ngrok-free.app") || host.endsWith(".ngrok.app"))) {
            throw new IllegalArgumentException("URL must be an ngrok assigned dev domain");
        }
        if (token == null || token.trim().length() < 32) {
            throw new IllegalArgumentException("Bearer token is missing or too short");
        }

        SecretKey key = getOrCreateKey();
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key);
        byte[] ct = cipher.doFinal(token.trim().getBytes(StandardCharsets.UTF_8));

        prefs(context).edit()
                .putString(KEY_URL, normalized)
                .putString(KEY_TOKEN_CT, Base64.encodeToString(ct, Base64.NO_WRAP))
                .putString(KEY_TOKEN_IV, Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
                .apply();
    }

    static String getBaseUrl(Context context) {
        return prefs(context).getString(KEY_URL, "");
    }

    static String getToken(Context context) throws Exception {
        String ct64 = prefs(context).getString(KEY_TOKEN_CT, "");
        String iv64 = prefs(context).getString(KEY_TOKEN_IV, "");
        if (ct64.isEmpty() || iv64.isEmpty()) return "";

        SecretKey key = getOrCreateKey();
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        GCMParameterSpec spec = new GCMParameterSpec(128, Base64.decode(iv64, Base64.NO_WRAP));
        cipher.init(Cipher.DECRYPT_MODE, key, spec);
        byte[] plain = cipher.doFinal(Base64.decode(ct64, Base64.NO_WRAP));
        return new String(plain, StandardCharsets.UTF_8);
    }

    static boolean isConfigured(Context context) {
        return !getBaseUrl(context).isEmpty() && !prefs(context).getString(KEY_TOKEN_CT, "").isEmpty();
    }

    static String normalizeBaseUrl(String input) {
        String s = input == null ? "" : input.trim();
        while (s.endsWith("/")) s = s.substring(0, s.length() - 1);
        if (s.endsWith("/usage")) s = s.substring(0, s.length() - "/usage".length());
        return s;
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static SecretKey getOrCreateKey() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (ks.containsAlias(ALIAS)) {
            return (SecretKey) ks.getKey(ALIAS, null);
        }

        KeyGenerator kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        kg.init(new KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build());
        return kg.generateKey();
    }
}
