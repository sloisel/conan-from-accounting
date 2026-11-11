# Conan from Accounting

An adventure game for the Commodore 64, by S. Loisel.

**Play it in your browser:** https://sloisel.github.io/conan-from-accounting/

**Disk image:** https://sloisel.github.io/conan-from-accounting/mygame.d64
(`LOAD"*",8,1` and `RUN`; it uses a fastloader, so turn on true drive
emulation in emulators other than VICE)

Find the old wizard, take his sword, collect the red, green and blue keys,
and free the princess from her jail.

## Controls

- `W` `A` `S` `D`: walk
- `J`: sword
- or a joystick in port 2

## Building

Needs Java (for [Kick Assembler](http://theweb.dk/KickAssembler/), included as
`KickAss.jar`), Python 3 with numpy, and make:

```
make            # builds mygame.d64
make run        # plays it in VICE (x64sc), joystick 2 on the cursor keys
make test       # headless checks in VICE
```

Every push to `main` builds the disk image and publishes it with
`web/index.html` (EmulatorJS) on GitHub Pages
(`.github/workflows/pages.yml`).

## Credits

Music: "Degalvanized" by Ole Marius Pettersen, (C) 2011 Offence.
