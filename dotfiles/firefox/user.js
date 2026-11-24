// Chicago OS — Firefox defaults. Copied into each Firefox profile by
// install.sh; Firefox applies it at every start. Delete a line here (and
// in the profile's user.js) to hand that setting back to Firefox.

// Use the desktop's themed window frame and buttons instead of Firefox
// drawing its own GNOME/Windows-style title bar with the tabs.
user_pref("browser.tabs.inTitlebar", 0);

// Follow the system scale set by chicago-display-adapt (no own zoom).
user_pref("layout.css.devPixelsPerPx", "-1.0");

// Same type as the rest of the desktop.
user_pref("font.name.sans-serif.x-western", "Ubuntu Sans");
user_pref("font.name.monospace.x-western", "JetBrains Mono");
user_pref("font.default.x-western", "sans-serif");
user_pref("font.size.variable.x-western", 15);
user_pref("font.size.monospace.x-western", 13);
