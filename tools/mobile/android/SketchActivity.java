// SPDX-License-Identifier: 0BSD
package org.rocinante.sketch;

import org.libsdl.app.SDLActivity;

// SDL does the work. This class gives the app its own name and says which function in libmain.so to start.
public class SketchActivity extends SDLActivity {
    @Override
    protected String getMainFunction() {
        return "rocinante_main";
    }
}
