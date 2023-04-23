# CTM Command Line Tool

A commandline tool for maintaining CTM objects very useful when building with CTM lambda functions

# Usage

```
usage: ctm create-repo [-h] -n NAME [-p PATH]

options:
  -h, --help            show this help message and exit
  -n NAME, --name NAME  Project name
  -p PATH, --path PATH  Project path
```

```
ctm create-repo -n get-email -p `pwd`
Created project folder: /Users/taf2/work/get-email
Initialized empty Git repository in /Users/taf2/work/get-email/.git/
Initialized Git repository in /Users/taf2/work/get-email
Installed post-push script in /Users/taf2/work/get-email/.git/hooks/post-push
Installed pre-commit script in /Users/taf2/work/get-email/.git/hooks/pre-commit
Please visit https://app.ctmdev.us/accesscode and enter the code WQOT-BOON
Waiting for user authorization...
Waiting for user authorization...
Project ready for development.

cd get-email
```



# How it works

We rely on 2 git hooks

pre-commit: 
  this will validate and verify a few things about your package before it is commited

post-push:
  when you push to one of the following branches release-production, release-staging, or release-development
  information as you have versioned in config.yml will be uploaded via API to the specific instance of CTM and
  provision your new code

# dependencies

python3 -m venv env

./env/bin/pip3 -r requirements.txt

build installer

Mac OSX installer
```
pyinstaller --onefile  ctm --osx-entitlements-file entitlements.plist
security find-identity -p basic -v
codesign --deep --force --options=runtime --entitlements ./entitlements.plist --sign  656DA... --timestamp ./dist/ctm
```

