// SPDX-License-Identifier: 0BSD
package org.rocinante.sketch;

import android.content.pm.PackageInfo;
import android.content.res.AssetManager;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import org.libsdl.app.SDLActivity;

// SDL does the work. This class gives the app its own name, says which function in libmain.so to start, and lets
// the sketch draw edge to edge: behind the status bar, the navigation bar and the camera's cut-out, which a sketch
// keeps clear of with `safe` (SDL reports the strips from the window's insets once the content reaches them).
public class SketchActivity extends SDLActivity {
    @Override
    protected String getMainFunction() {
        return "rocinante_main";
    }

    // A packaged app carries the sketch's files inside its APK, under assets/sketch/: `assets` and `libs` as they are, and in `seed`
    // the files a sketch starts from. The program reads them as files in the app's own folder, so they are unpacked there before it
    // starts: `assets` and `libs` again after every install or update (they are the app's, and a new version may have changed them),
    // and each starting file only when it is not there yet, since what the sketch wrote to it since is the player's. A test build
    // has nothing under assets/sketch/ (adb puts its files in the folder), so there is nothing to do.
    private void unpackSketchFiles() {
        try {
            AssetManager assets = getAssets();
            String[] carried = assets.list("sketch");
            if (carried == null || carried.length == 0) {
                return;
            }
            File home = getFilesDir();
            PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
            String stamp = Long.toString(info.lastUpdateTime);
            File marker = new File(home, ".sketch-files");
            if (marker.isFile() && stamp.equals(new String(Files.readAllBytes(marker.toPath()), StandardCharsets.UTF_8))) {
                return;
            }
            deleteTree(new File(home, "assets"));
            deleteTree(new File(home, "libs"));
            copyTree(assets, "sketch/assets", new File(home, "assets"));
            copyTree(assets, "sketch/libs", new File(home, "libs"));
            String[] seeds = assets.list("sketch/seed");
            if (seeds != null) {
                for (String seed : seeds) {
                    File to = new File(home, seed);
                    if (!seed.startsWith(".") && !to.exists()) {
                        copyTree(assets, "sketch/seed/" + seed, to);
                    }
                }
            }
            Files.write(marker.toPath(), stamp.getBytes(StandardCharsets.UTF_8));
            Log.i("rocinante", "unpacked the sketch's files: " + countFiles(new File(home, "assets")) + " in assets, "
                + countFiles(new File(home, "libs")) + " in libs");
        } catch (Exception e) {
            Log.e("rocinante", "could not unpack the sketch's files", e);
        }
    }

    private static int countFiles(File file) {
        File[] inside = file.listFiles();
        if (inside == null) {
            return file.isFile() ? 1 : 0;
        }
        int n = 0;
        for (File child : inside) {
            n += countFiles(child);
        }
        return n;
    }

    private static void deleteTree(File file) {
        File[] inside = file.listFiles();
        if (inside != null) {
            for (File child : inside) {
                deleteTree(child);
            }
        }
        file.delete();
    }

    // Copies what is under `path` in the APK to `to`: a folder is made and its entries copied, a file is copied. A folder that is not
    // in the APK (the sketch has no `libs`) has nothing to copy, and is not an error.
    private static void copyTree(AssetManager assets, String path, File to) throws IOException {
        String[] names = assets.list(path);
        if (names != null && names.length > 0) {
            to.mkdirs();
            for (String name : names) {
                copyTree(assets, path + "/" + name, new File(to, name));
            }
            return;
        }
        try (InputStream in = assets.open(path); OutputStream out = new FileOutputStream(to)) {
            byte[] buffer = new byte[65536];
            int n;
            while ((n = in.read(buffer)) > 0) {
                out.write(buffer, 0, n);
            }
        } catch (FileNotFoundException missing) {
            to.delete();
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        unpackSketchFiles();
        super.onCreate(savedInstanceState);
        Window window = getWindow();
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS | WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION);
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(Color.TRANSPARENT);
        if (Build.VERSION.SDK_INT >= 29) {
            window.setNavigationBarContrastEnforced(false);
            window.setStatusBarContrastEnforced(false);
        }
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false);
            window.getAttributes().layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS;
        } else {
            window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
            window.getAttributes().layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        }
    }
}
