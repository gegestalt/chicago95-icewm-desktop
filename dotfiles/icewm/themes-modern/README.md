# ChicagoModernXP

The default Chicago OS window theme: navy title bar with red / amber / green
round buttons on the left.

The button images (`close*`, `minimize*`, `maximize*`, `restore*`) are
deliberately opaque: their round shapes are pre-blended onto the title bar
colour (#00007B active, #7B7B7B inactive). IceWM draws each button as its own
small window, and without a compositor a transparent pixel there shows
whatever is behind the window (teal desktop, bits of other windows). If you
change the title bar colour, re-blend the buttons, e.g.

    magick closeA.png -background '#00007B' -alpha remove -alpha off closeA.png

Pixel sizes here are 1x; chicago-display-adapt renders scaled copies for
HiDPI screens automatically.

Rounded window corners: the `frame[AI]{TL,TR,BL,BR}.xpm` corner pixmaps have
a 12px rounded cut (transparent pixels) with a 1px bevel line along the curve.
IceWM turns those into an X Shape mask, so windows are really rounded without
a compositor. Regenerate after editing the corners with:

    tools/round-frame-corners dotfiles/icewm/themes-modern/ChicagoModernXP 12
