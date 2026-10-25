// SPDX-License-Identifier: 0BSD
package org.rocinante.spike;

import org.libsdl.app.SDLActivity;

// SDL does the work. This class gives the app its own name and says which
// function in libmain.so to start (see main.odin for why it is not SDL_main).
public class SpikeActivity extends SDLActivity {
    @Override
    protected String getMainFunction() {
        return "rocinante_main";
    }
}
