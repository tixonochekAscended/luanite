<div align="center">
  <img style="height: 250px;" src="https://raw.githubusercontent.com/tixonochekAscended/luanite/refs/heads/main/LuaniteLogo.png">
</div>

------
# Luanite — the project builder for Lua.
**Luanite** is a project builder for the programming language Lua that is somewhat similar to Rust's `cargo`. It allows to easily bundle your Lua application into a self-contained standalone executable which runs on machines with no Lua installed. Every single Luanite project features its own **Lua 5.4.6** installation built from source — here Luanite takes inspiration from Python's virtual enviroments. Unfortunately, **Luanite** doesn't yet feature all functionality that I want it to have, but we are getting there. Read further to learn more information.

## 🛠️ Installation
As for now, **Luanite** only supports Linux - but it will support Windows in the near future. There are 2 main methods to install Luanite.

:one: **First Method**: you can easily install Luanite by going to the "Releases" page of this repository and installing Luanite's executable file. Afterwards, put it wherever you like on your machine and remember to put it in **PATH**.

:two: **Second Method**: if you don't trust my executable for whatever reason or would like to create it yourself, you can clone the `luanite.lua` file from this repository - that's where all of Luanite's code lies. Afterwards, you can just execute it with the **Lua 5.4.6** installation that you already have on your machine by using `lua luanite.lua` or a similar command. You can indeed create an executable of **Luanite** by using **Luanite** - just create a new Luanite project, put luanite's code in the `app/` folder, change up some settings in the `luanite.project` configuration file and build the executable. Now you can enjoy all of Luanite's wonders.

## ⚙️ Usage
Version `1.0`, which at the moment is the latest version of **Luanite**, features 6 commands:
1. `luanite help` - outputs a list of all available commands
2. `luanite version` - outputs Luanite's version
3. `luanite license` - outputs information regarding Luanite's one and only license - which is of course the GNU General Public License v3.0.
4. `luanite init <Directory>` - creates a new _Luanite project_ in the directory provided by the user. A project **can't be initialized** in a non-empty directory (directories that don't exist yet are completely fine - Luanite will create them for you). At the moment requires an internet connection to download Lua 5.4.6's tarball - will probably be changed in the next versions.
5. `luanite build` - builds a self-contained, standalone executable. This command bundles **all** Lua files in the `app/` directory inside of your Luanite project - even the ones that aren't `require()`'d by any other file. The name of the built executable and the entry point of the program are all based on the values that are stored inside of the `luanite.project` configuration file. Needs to be ran from the `root/` of a Luanite project.
6. `luanite run` - does the same thing as `luanite build` but runs the built executable afterwards. Needs to be ran from the `root/` of a Luanite project.

## 📂 Structure of a Luanite project
Upon creating a new Luanite project via `luanite init ...`, you are going to see this kind of filetree appear at the `root/` of your new project:
```
root/
├── luanite.project      # Configuration file for your Luanite project
├── app/                 # Source code of your Lua application
│   └── main.lua         # Default entry point for your Lua application
├── bin/                 # Output folder for the standalone executable after building
└── luanite/             # Contains Lua 5.4.6, luastatic and other internal tools (do not modify)
```

## 📝 Naming
**Luanite's** name comes from the word "meteorite" being combined with "Lua". The space-ish theme comes from the fact that "Lua" means "Moon". The best way to mention Luanite in a conversation is to use the name `Luanite`. `LUANITE`, `luanite` and others are just more complicated, look uglier than the original version and don't follow the rules specified for the name "Lua" on [Lua's official webpage](https://www.lua.org/about.html) - we also follow those.

## ☑️ TO-DO List
- [ ] Support Windows
- [ ] Support cross-compilation to Windows from Linux
- [ ] Create a `luanite lua` command as an interface for talking to the Lua 5.4.6 contained in every Luanite project (for this whole virtual-enviroment functionality to become much more useful)
- [ ] Think on how to make `luanite init` not depend on an internet connection to work
- [ ] Improve the bundling system (bundle only the files that are `require()`'d by other files instead of bundling everything)
- [ ] Allow to install packages/libraries from Luarocks directly and additionaly automatically bundle them into the standalone executable

## ©️ Credits
This project wouldn't be possible without [luastatic](https://github.com/ers35/luastatic).
