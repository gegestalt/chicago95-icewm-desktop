// Chicago OS — Firefox defaults. Copied into each Firefox profile by
// install.sh; Firefox applies it at every start. Delete a line here (and
// in the profile's user.js) to hand that setting back to Firefox.

// Use the desktop's themed window frame and buttons instead of Firefox
// drawing its own GNOME/Windows-style title bar with the tabs.
user_pref("browser.tabs.inTitlebar", 0);

// Interface scale = the desktop scale. chicago-display-adapt rewrites
// this line in every profile when the scale changes (applies at the next
// Firefox start). "-1.0" would follow the DPI instead, which includes
// TEXT_SCALE and made the toolbars oversized.
user_pref("layout.css.devPixelsPerPx", "2.0");

// Compact toolbars and tabs: slimmer rows, same layout.
user_pref("browser.compactmode.show", true);
user_pref("browser.uidensity", 1);

// Same type as the rest of the desktop.
user_pref("font.name.sans-serif.x-western", "Ubuntu Sans");
user_pref("font.name.monospace.x-western", "JetBrains Mono");
user_pref("font.default.x-western", "sans-serif");
user_pref("font.size.variable.x-western", 15);
user_pref("font.size.monospace.x-western", 13);
