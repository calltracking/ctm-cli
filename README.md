# CTM Command Line Tool

A commandline tool for maintaining CTM objects very useful when building with CTM lambda functions

# Usage

```
ctm verify # will validate the files in your current directory
```

```
ctm deploy # will deploy your files assuming they are correct to upstream ctm servers
```

```
ctm create:lambda -h # will create a new directory and initialize a new git repo for you
usage: ctm create [-h] -n NAME [-p PATH]

options:
  -h, --help            show this help message and exit
  -n NAME, --name NAME  Project name
  -p PATH, --path PATH  Project path
```

```
ctm reset:credentials -n my-project -h # will reset the credentials stored for the current project
usage: ctm reset:credentials [-h] [-n NAME]

options:
  -h, --help            show this help message and exit
  -n NAME, --name NAME  Project name
```

example usage
```
ctm create:lambda -n get-email -p `pwd`
cd get-email
  # edit code.js

ctm verify
ctm deploy
```


# dependencies

python3 -m venv env

./env/bin/pip3 -r requirements.txt

build installer

Mac OSX installer
```
pyinstaller --onedir  ctm --osx-entitlements-file entitlements.plist
security find-identity -p basic -v
codesign --deep --force --options=runtime --entitlements ./entitlements.plist --sign  656DA... --timestamp ./dist/ctm/ctm
```

