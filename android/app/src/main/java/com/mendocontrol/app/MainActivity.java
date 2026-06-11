package com.mendocontrol.app;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;

// Pantalla unica: descubre la PC por broadcast UDP (puerto 8766) y carga
// la interfaz web que sirve server.ps1 en un WebView a pantalla completa.
public class MainActivity extends Activity {

    private static final int DISCOVERY_PORT = 8766;
    private static final String DISCOVERY_QUERY = "MENDOCONTROL?";
    private static final String DISCOVERY_PREFIX = "MENDOCONTROL:";

    private WebView webView;
    private TextView statusView;
    private Button retryButton;
    private LinearLayout overlay;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.parseColor("#0f1115"));

        webView = new WebView(this);
        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setDomStorageEnabled(true); // localStorage: sensibilidad
        webView.setWebViewClient(new WebViewClient());
        webView.setBackgroundColor(Color.parseColor("#0f1115"));
        webView.setVisibility(View.GONE);
        root.addView(webView, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

        overlay = new LinearLayout(this);
        overlay.setOrientation(LinearLayout.VERTICAL);
        overlay.setGravity(Gravity.CENTER);
        int pad = (int) (24 * getResources().getDisplayMetrics().density);
        overlay.setPadding(pad, pad, pad, pad);

        statusView = new TextView(this);
        statusView.setTextColor(Color.parseColor("#e6e6e6"));
        statusView.setTextSize(16);
        statusView.setGravity(Gravity.CENTER);
        overlay.addView(statusView);

        retryButton = new Button(this);
        retryButton.setText("Reintentar");
        retryButton.setVisibility(View.GONE);
        retryButton.setOnClickListener(v -> startDiscovery());
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        bp.topMargin = pad;
        bp.gravity = Gravity.CENTER_HORIZONTAL;
        overlay.addView(retryButton, bp);

        root.addView(overlay, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        setContentView(root);

        startDiscovery();
    }

    private void startDiscovery() {
        statusView.setText("Buscando la PC en la red WiFi...");
        retryButton.setVisibility(View.GONE);
        new Thread(() -> {
            final String url = discover();
            runOnUiThread(() -> {
                if (url != null) {
                    overlay.setVisibility(View.GONE);
                    webView.setVisibility(View.VISIBLE);
                    webView.loadUrl(url);
                } else {
                    statusView.setText("No se encontró la PC.\n\nVerificá que el servidor esté corriendo\ny que el celular esté en la misma red WiFi.");
                    retryButton.setVisibility(View.VISIBLE);
                }
            });
        }).start();
    }

    // Manda "MENDOCONTROL?" por broadcast y espera "MENDOCONTROL:<puerto>".
    // La IP de la PC sale del propio paquete de respuesta.
    private String discover() {
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.setBroadcast(true);
            socket.setSoTimeout(1000);
            byte[] msg = DISCOVERY_QUERY.getBytes(StandardCharsets.UTF_8);
            byte[] buf = new byte[256];
            for (int attempt = 0; attempt < 5; attempt++) {
                socket.send(new DatagramPacket(msg, msg.length,
                        InetAddress.getByName("255.255.255.255"), DISCOVERY_PORT));
                try {
                    DatagramPacket pkt = new DatagramPacket(buf, buf.length);
                    socket.receive(pkt);
                    String text = new String(pkt.getData(), 0, pkt.getLength(), StandardCharsets.UTF_8);
                    if (text.startsWith(DISCOVERY_PREFIX)) {
                        String port = text.substring(DISCOVERY_PREFIX.length()).trim();
                        return "http://" + pkt.getAddress().getHostAddress() + ":" + port;
                    }
                } catch (SocketTimeoutException ignored) {
                    // Reintentar: el broadcast se puede perder.
                }
            }
        } catch (Exception ignored) {
        }
        return null;
    }

    @Override
    public void onBackPressed() {
        // No cerrar la app por un toque accidental del gesto de atras.
        moveTaskToBack(true);
    }
}
