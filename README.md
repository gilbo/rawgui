

# "Install"

In order to run this project, you'll need 3 C libraries, and Lua/Terra.
No extra compilation is needed once you've installed the dependencies.  Simply run the command `terra svgview.t` assuming that you've added the `terra` binary to your path.

## Lua/Terra Install

Just go to www.terralang.org and download the binaries there.

## SDL2, CairoGraphics, libXML2

If you're on Mac, you can download these all via homebrew.  Unfortunately, I haven't tested this code in any setup except my own dev environment.  You should be able to get it to run wherever thanks to using cross-platform libraries, but you may need to dig into a few files and edit the code for finding and loading dynamic libraries.


# License

This code is made available under an Apache 2 license.  However, I would greatly appreciate it if you (i) let me know if you use the code to do something interesting; (ii) credit me in your documents.  As an academic, I  benefit tremendously from being able to concretely demonstrate that my work is making a difference to someone else.  Thanks for your understanding.

# Font Licenses

I am including 3 free fonts with this project: Consolas.ttf, DroidSans.ttf, DroidSansMono.ttf.  DroidSans is provided by Google under Apache 2.

OsakaMono.ttf if provided by default on Mac OSX.  If you're not using Mac OSX, please be aware that you may not have a license to use OsakaMono.  A quick find and replace on the source code to use Consolas or another monospace font should protect you legally.

# SVG Licenses

The included SVGs are CC BY 3.0 Freepik, obtained from flaticon.com