# Apps for LILYGO T-Deck

A collection of small apps for LILYGO T-Deck devices running WADAMESH firmware.

The idea behind this project is pretty simple: make some useful, fun, and practical apps that can be loaded directly onto the T-Deck and used without needing a phone or computer.

These are unofficial community-made apps and are not affiliated with the companies or projects that make the hardware and firmware.

For the full legal disclaimer and third-party notices, see [DISCLAIMER.md](DISCLAIMER.md).

---

# Prerequisites

You'll need:

1. A LILYGO T-Deck, T-Deck Pro, or another compatible device.
2. WADAMESH firmware installed on the device.
3. A way to transfer files to the device.

Depending on your setup, this can be done through the MicroSD card, USB-C, or the file transfer option provided by your firmware or transfer app.

The exact process may vary depending on your hardware and firmware version.

---

# How to get the files:
Copy the raw file, then create a new file named <App_Name>.lua
What you name the file will determine what it appears as on the T-Deck.

---

# App Requests

If there's an app you'd like to see, [open an issue](https://github.com/JackCortines/T-deck_Apps/issues/new) and tell me what you have in mind.

I'll take a look at requests and see what I can do. There are no guarantees that every idea will be possible, especially when it comes to the limitations of ESP32 hardware and the available filesystem.

Please keep those limitations in mind. Asking for a local LLM or YouTube probably isn't going to work out.

That said, if you have an idea that sounds even remotely practical, go ahead and ask.

---

# Storage Limitations

The `wada.fs` filesystem has limited space (32KB), which can make larger applications difficult to fit.

This is especially noticeable with text-heavy applications. The complete Bible, for example, is simply too large to fit within the current limits as a single application.

Because of this, some apps may need to be kept small or split into multiple sections.

---

# Bugs and Issues

If you find a bug, please [open an issue](https://github.com/JackCortines/T-deck_Apps/issues/new).

When possible, include:

- Which app you're using
- Your hardware model
- Your firmware version
- What you were doing when the problem occurred
- What you expected to happen
- What actually happened
- Any error messages or screenshots

The more information you provide, the easier it is to figure out what's going on.

---

# Contributions

Contributions, bug fixes, suggestions, and new app ideas are welcome.

If you want to make a larger change, opening an issue first is probably a good idea so we can discuss it before you spend time working on something that may not fit the project.

---

# Licensing and Third-Party Material

Different parts of this project may have different licensing requirements.

Third-party software, firmware, libraries, Bible translations, and other materials remain subject to their respective licenses and copyrights.

Nothing in this repository is intended to claim ownership of third-party material or grant rights that I don't have.

See [DISCLAIMER.md](DISCLAIMER.md) for more information.

---

# Final Note

This is mostly a project for fun. I like the T-Deck and wanted to see what useful little things I could make for it.

If you find something useful here, great. If you find a bug, let me know. And if you have an idea for another app, open an issue.

Thanks for checking it out, and happy meshing!
